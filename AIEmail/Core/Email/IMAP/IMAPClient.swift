import Foundation
import Network

final class IMAPClient: @unchecked Sendable {
    private var host: String = ""
    private var port: Int = 993
    private var useSSL: Bool = true
    
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aiemail.imapclient", qos: .userInitiated)
    private var isConnected = false
    private var isAuthenticated = false
    private var selectedFolder: String?
    
    private let parser = IMAPResponseParser()
    private var responseBuffer = Data()
    private let bufferLock = NSLock()
    
    private var continuation: CheckedContinuation<[IMAPResponseType], Error>?
    private var readTask: Task<Void, Never>?
    private var greetingReceived = false
    private var currentTag: String = ""
    
    private var connectionState: ConnectionState = .disconnected
    
    init() {}
    
    func connect(host: String, port: Int, useSSL: Bool) async throws {
        self.host = host
        self.port = port
        self.useSSL = useSSL
        connectionState = .connecting
        
        let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(integerLiteral: UInt16(port)))
        
        let parameters: NWParameters
        if useSSL {
            let tlsOptions = NWProtocolTLS.Options()
            parameters = NWParameters(tls: tlsOptions, tcp: NWProtocolTCP.Options())
        } else {
            parameters = NWParameters.tcp
        }
        
        connection = NWConnection(to: endpoint, using: parameters)
        
        guard let connection = connection else {
            throw IMAPError.connectionFailed("Failed to create connection")
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.connectionState = .connected
                    self?.startReading()
                    continuation.resume()
                case .failed(let error):
                    self?.connectionState = .disconnected
                    continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    self?.connectionState = .disconnected
                default:
                    break
                }
            }
            
            connection.start(queue: queue)
        }
        
        try await waitForGreeting()
    }
    
    private func waitForGreeting() async throws {
        return try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                if !greetingReceived {
                    continuation.resume(throwing: IMAPError.timeout)
                }
            }
            
            Task {
                while !greetingReceived && !Task.isCancelled {
                    try await Task.sleep(nanoseconds: 100_000_000)
                }
                timeoutTask.cancel()
                if !Task.isCancelled {
                    continuation.resume()
                }
            }
        }
    }
    
    private func startReading() {
        readTask = Task { [weak self] in
            guard let self = self else { return }
            
            while !Task.isCancelled && self.isConnected {
                do {
                    let data = try await self.readData()
                    self.bufferLock.lock()
                    self.responseBuffer.append(data)
                    let hasCompleteResponse = self.checkForCompleteResponse()
                    self.bufferLock.unlock()
                    
                    if hasCompleteResponse {
                        self.processResponse()
                    }
                } catch {
                    break
                }
            }
        }
    }
    
    private func readData() async throws -> Data {
        return try await withCheckedThrowingContinuation { continuation in
            connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                } else if let data = data {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
    
    private func checkForCompleteResponse() -> Bool {
        let tag = currentTag
        guard !tag.isEmpty else {
            if let range = responseBuffer.range(of: Data("\r\n".utf8)) {
                let line = String(data: responseBuffer[..<range.upperBound], encoding: .utf8) ?? ""
                if line.hasPrefix("* OK") {
                    greetingReceived = true
                    responseBuffer.removeSubrange(..<range.upperBound)
                    return false
                }
            }
            return false
        }
        
        let tagData = tag.data(using: .utf8) ?? Data()
        if responseBuffer.contains(tagData) {
            let pattern = "\(tag) OK".data(using: .utf8) ?? Data()
            let badPattern = "\(tag) NO".data(using: .utf8) ?? Data()
            let failPattern = "\(tag) BAD".data(using: .utf8) ?? Data()
            
            if responseBuffer.contains(pattern) || responseBuffer.contains(badPattern) || responseBuffer.contains(failPattern) {
                return true
            }
        }
        
        return false
    }
    
    private func processResponse() {
        bufferLock.lock()
        let responseData = responseBuffer
        responseBuffer.removeAll()
        currentTag = ""
        bufferLock.unlock()
        
        do {
            let responses = try parser.parseResponse(responseData)
            continuation?.resume(returning: responses)
            continuation = nil
        } catch {
            continuation?.resume(throwing: error)
            continuation = nil
        }
    }
    
    func login(username: String, password: String) async throws {
        guard isConnected else {
            throw IMAPError.notConnected
        }
        
        let responses = try await sendCommand(.login(username: username, password: password))
        
        guard let lastResponse = responses.last else {
            throw IMAPError.invalidResponse("No login response")
        }
        
        switch lastResponse {
        case .tagged(_, let response):
            switch response {
            case .ok:
                isAuthenticated = true
                connectionState = .authenticated
                return
            case .no:
                throw IMAPError.authenticationFailed("Login failed")
            default:
                throw IMAPError.authenticationFailed("Login failed")
            }
        default:
            throw IMAPError.authenticationFailed("Unexpected response")
        }
    }
    
    func selectFolder(_ folder: String) async throws -> FolderInfo {
        guard isConnected, isAuthenticated else {
            throw IMAPError.notConnected
        }
        
        let responses = try await sendCommand(.select(folder: folder))
        
        guard let lastResponse = responses.last else {
            throw IMAPError.invalidResponse("No select response")
        }
        
        switch lastResponse {
        case .tagged(_, let response):
            if case .ok = response {
                selectedFolder = folder
                connectionState = .selected(folder)
                return parser.parseFolderInfo(from: responses) ?? FolderInfo(name: folder)
            }
            throw IMAPError.commandFailed("Failed to select folder")
        default:
            throw IMAPError.invalidResponse("Unexpected select response")
        }
    }
    
    func fetchMessageIDs(folder: String, since: Date?) async throws -> [MessageID] {
        guard isConnected, isAuthenticated else {
            throw IMAPError.notConnected
        }
        
        if folder != selectedFolder {
            _ = try await selectFolder(folder)
        }
        
        let searchCommand: IMAPCommand
        if let since = since {
            searchCommand = .searchSince(date: since)
        } else {
            searchCommand = .search(charset: nil, criteria: "ALL")
        }
        
        let responses = try await sendCommand(searchCommand)
        return parser.parseMessageIDs(from: responses)
    }
    
    func fetchHeaders(messageIDs: [String]) async throws -> [EmailHeader] {
        guard isConnected, isAuthenticated else {
            throw IMAPError.notConnected
        }
        
        guard !messageIDs.isEmpty else {
            return []
        }
        
        let command = IMAPCommand.fetchMessageHeaders(ids: messageIDs)
        let responses = try await sendCommand(command)
        return parser.parseEmailHeaders(from: responses)
    }
    
    func fetchBody(messageID: String) async throws -> EmailBody {
        guard isConnected, isAuthenticated else {
            throw IMAPError.notConnected
        }
        
        let command = IMAPCommand.fetch(ids: [messageID], items: ["BODY[TEXT]", "BODY[HEADER]"])
        let responses = try await sendCommand(command)
        
        guard let body = parser.parseBody(from: responses, messageID: messageID) else {
            return EmailBody(messageID: messageID)
        }
        
        return body
    }
    
    func fetchAttachments(messageID: String) async throws -> [AttachmentInfo] {
        guard isConnected, isAuthenticated else {
            throw IMAPError.notConnected
        }
        
        let command = IMAPCommand.fetchAttachmentsInfo(ids: [messageID])
        let responses = try await sendCommand(command)
        return parser.parseAttachments(from: responses, messageID: messageID)
    }
    
    func setFlags(messageIDs: [String], flags: [MessageFlag]) async throws {
        guard isConnected, isAuthenticated else {
            throw IMAPError.notConnected
        }
        
        guard !messageIDs.isEmpty else {
            return
        }
        
        let command = IMAPCommand.setFlags(ids: messageIDs, flags: flags, mode: .set)
        let responses = try await sendCommand(command)
        
        guard let lastResponse = responses.last else {
            throw IMAPError.invalidResponse("No response for setFlags")
        }
        
        switch lastResponse {
        case .tagged(_, let response):
            if case .ok = response {
                return
            }
            throw IMAPError.commandFailed("setFlags failed")
        default:
            throw IMAPError.invalidResponse("Unexpected response for setFlags")
        }
    }
    
    func moveMessages(messageIDs: [String], toFolder: String) async throws {
        guard isConnected, isAuthenticated else {
            throw IMAPError.notConnected
        }
        
        guard !messageIDs.isEmpty else {
            return
        }
        
        let responses = try await sendCommand(.move(ids: messageIDs, folder: toFolder))
        
        guard let lastResponse = responses.last else {
            throw IMAPError.invalidResponse("No response for move")
        }
        
        switch lastResponse {
        case .tagged(_, let response):
            if case .ok = response {
                return
            }
            throw IMAPError.commandFailed("move failed")
        default:
            throw IMAPError.invalidResponse("Unexpected response for move")
        }
    }
    
    func deleteMessages(messageIDs: [String]) async throws {
        guard isConnected, isAuthenticated else {
            throw IMAPError.notConnected
        }
        
        guard !messageIDs.isEmpty else {
            return
        }
        
        let flagCommand = IMAPCommand.setFlags(ids: messageIDs, flags: [.deleted], mode: .set)
        _ = try await sendCommand(flagCommand)
        
        _ = try await sendCommand(.expunge)
    }
    
    func logout() async throws {
        guard isConnected else {
            throw IMAPError.notConnected
        }
        
        do {
            _ = try await sendCommand(.logout)
        } catch {
        }
        
        closeConnection()
    }
    
    private func closeConnection() {
        readTask?.cancel()
        readTask = nil
        
        connection?.cancel()
        connection = nil
        
        isConnected = false
        isAuthenticated = false
        selectedFolder = nil
        connectionState = .disconnected
    }
    
    private func sendCommand(_ command: IMAPCommand) async throws -> [IMAPResponseType] {
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = continuation
            self.currentTag = command.tag
            
            let tag = command.tag
            let commandString = "\(tag) \(command.commandString)\r\n"
            
            guard let data = commandString.data(using: .utf8) else {
                continuation.resume(throwing: IMAPError.invalidResponse("Failed to encode command"))
                return
            }
            
            responseBuffer.removeAll()
            
            connection?.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    self.continuation?.resume(throwing: IMAPError.connectionFailed(error.localizedDescription))
                    self.continuation = nil
                }
            })
        }
    }
    
    func capability() async throws -> [String] {
        guard isConnected else {
            throw IMAPError.notConnected
        }
        
        let responses = try await sendCommand(.capability)
        var capabilities: [String] = []
        
        for response in responses {
            if case .untagged(let data) = response {
                if case .raw(let str) = data {
                    let parts = str.components(separatedBy: " ")
                    capabilities.append(contentsOf: parts.filter { !$0.isEmpty })
                }
            }
        }
        
        return capabilities
    }
    
    func listFolders(reference: String = "", pattern: String = "*") async throws -> [FolderInfo] {
        guard isConnected, isAuthenticated else {
            throw IMAPError.notConnected
        }
        
        let responses = try await sendCommand(.list(reference: reference, pattern: pattern))
        return parseFolderList(from: responses)
    }
    
    private func parseFolderList(from responses: [IMAPResponseType]) -> [FolderInfo] {
        var folders: [FolderInfo] = []
        
        for response in responses {
            if case .untagged(let data) = response {
                if case .list(let items) = data {
                    for item in items {
                        let name = item["name"] ?? ""
                        let folder = FolderInfo(name: name)
                        folders.append(folder)
                    }
                }
            }
        }
        
        return folders
    }
}
