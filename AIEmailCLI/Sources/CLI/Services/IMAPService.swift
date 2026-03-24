import Foundation
import Network

final class IMAPService {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.aiemailcli.imap", qos: .userInitiated)
    private var isConnected = false
    private var isAuthenticated = false
    private var selectedFolder: String?
    private var continuation: CheckedContinuation<[IMAPResponseType], Error>?
    private var responseBuffer = Data()
    private let bufferLock = NSLock()
    private var greetingReceived = false
    private var currentTag = ""
    
    private let hostname: String
    
    init() {
        hostname = ProcessInfo.processInfo.hostName
    }
    
    func connect(host: String, port: Int, useSSL: Bool) async throws {
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
            throw IMAPServiceError.connectionFailed("Failed to create connection")
        }
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            connection.stateUpdateHandler = { [weak self] state in
                switch state {
                case .ready:
                    self?.isConnected = true
                    self?.startReading()
                    continuation.resume()
                case .failed(let error):
                    continuation.resume(throwing: IMAPServiceError.connectionFailed(error.localizedDescription))
                case .cancelled:
                    continuation.resume(throwing: IMAPServiceError.connectionFailed("Connection cancelled"))
                default:
                    break
                }
            }
            connection.start(queue: queue)
        }
        
        try await waitForGreeting()
    }
    
    private func waitForGreeting() async throws {
        try await withCheckedThrowingContinuation { continuation in
            let timeoutTask = Task {
                try await Task.sleep(nanoseconds: 10_000_000_000)
                if !greetingReceived {
                    continuation.resume(throwing: IMAPServiceError.timeout)
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
        Task { [weak self] in
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
        try await withCheckedThrowingContinuation { continuation in
            connection?.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, isComplete, error in
                if let error = error {
                    continuation.resume(throwing: IMAPServiceError.connectionFailed(error.localizedDescription))
                } else if let data = data {
                    continuation.resume(returning: data)
                } else if isComplete {
                    continuation.resume(returning: Data())
                }
            }
        }
    }
    
    private func checkForCompleteResponse() -> Bool {
        guard !currentTag.isEmpty else {
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
            let okPattern = "\(currentTag) OK".data(using: .utf8) ?? Data()
            let noPattern = "\(currentTag) NO".data(using: .utf8) ?? Data()
            let badPattern = "\(currentTag) BAD".data(using: .utf8) ?? Data()
            
            if responseBuffer.contains(okPattern) || responseBuffer.contains(noPattern) || responseBuffer.contains(badPattern) {
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
        
        let responses = parseResponse(responseData)
        continuation?.resume(returning: responses)
        continuation = nil
    }
    
    private func parseResponse(_ data: Data) -> [IMAPResponseType] {
        guard let str = String(data: data, encoding: .utf8) else { return [] }
        var responses: [IMAPResponseType] = []
        let lines = str.components(separatedBy: "\r\n")
        
        for line in lines {
            if line.isEmpty { continue }
            
            if line.hasPrefix("* ") {
                if let response = parseUntagged(line) {
                    responses.append(response)
                }
            } else if line.hasPrefix(currentTag) {
                let parts = line.components(separatedBy: " ")
                if parts.count >= 2 {
                    let status = parts[1]
                    switch status {
                    case "OK":
                        responses.append(.tagged(tag: currentTag, response: .ok))
                    case "NO":
                        responses.append(.tagged(tag: currentTag, response: .no))
                    case "BAD":
                        responses.append(.tagged(tag: currentTag, response: .bad))
                    default:
                        break
                    }
                }
            }
        }
        
        return responses
    }
    
    private func parseUntagged(_ line: String) -> IMAPResponseType? {
        let content = String(line.dropFirst(2))
        
        if content.hasPrefix("OK") {
            return .ok
        } else if content.hasPrefix("NO") {
            return .no
        } else if content.hasPrefix("BAD") {
            return .bad
        } else if content.hasPrefix("BYE") {
            return .bye
        } else if content.hasPrefix("FLAGS") {
            return .untagged(.flags(parseFlags(content)))
        } else if let count = parseExists(content) {
            return .untagged(.exists(count))
        } else if let count = parseRecent(content) {
            return .untagged(.recent(count))
        } else if content.contains("FETCH") {
            return .untagged(.fetch(["raw": content]))
        }
        
        return .untagged(.raw(content))
    }
    
    private func parseFlags(_ content: String) -> [String] {
        let start = content.firstIndex(of: "(")
        let end = content.lastIndex(of: ")")
        guard let start = start, let end = end else { return [] }
        let flagsStr = String(content[content.index(after: start)..<end])
        return flagsStr.components(separatedBy: " ").filter { !$0.isEmpty }
    }
    
    private func parseExists(_ content: String) -> Int? {
        let parts = content.components(separatedBy: " ")
        guard parts.count >= 1, let count = Int(parts[0]) else { return nil }
        return count
    }
    
    private func parseRecent(_ content: String) -> Int? {
        return nil
    }
    
    func login(username: String, password: String) async throws {
        guard isConnected else {
            throw IMAPServiceError.notConnected
        }
        
        let tag = generateTag()
        currentTag = tag
        let command = "\(tag) LOGIN \(username) \(password)"
        
        try await sendCommand(command)
        
        guard let lastResponse = continuation?.getReturns()?.last else {
            throw IMAPServiceError.authenticationFailed("No response")
        }
        
        switch lastResponse {
        case .tagged(_, let response):
            switch response {
            case .ok:
                isAuthenticated = true
                return
            case .no, .bad:
                throw IMAPServiceError.authenticationFailed("Login failed")
            default:
                throw IMAPServiceError.authenticationFailed("Unexpected response")
            }
        default:
            throw IMAPServiceError.authenticationFailed("Unexpected response")
        }
    }
    
    func selectFolder(_ folder: String) async throws -> FolderInfo {
        guard isConnected, isAuthenticated else {
            throw IMAPServiceError.notConnected
        }
        
        let tag = generateTag()
        currentTag = tag
        let command = "\(tag) SELECT \(folder)"
        
        try await sendCommand(command)
        
        guard let responses = continuation?.getReturns(), !responses.isEmpty else {
            throw IMAPServiceError.commandFailed("No response")
        }
        
        selectedFolder = folder
        return parseFolderInfo(from: responses, name: folder)
    }
    
    func fetchHeaders(folder: String, limit: Int) async throws -> [EmailInfo] {
        guard isConnected, isAuthenticated else {
            throw IMAPServiceError.notConnected
        }
        
        if folder != selectedFolder {
            _ = try await selectFolder(folder)
        }
        
        let tag = generateTag()
        currentTag = tag
        let command = "\(tag) FETCH 1:\(limit) (UID ENVELOPE)"
        
        try await sendCommand(command)
        
        guard let responses = continuation?.getReturns() else {
            return []
        }
        
        return parseEmailHeaders(from: responses)
    }
    
    func fetchBody(messageID: String) async throws -> EmailDetail {
        guard isConnected, isAuthenticated else {
            throw IMAPServiceError.notConnected
        }
        
        let tag = generateTag()
        currentTag = tag
        let command = "\(tag) FETCH \(messageID) (UID ENVELOPE BODY[TEXT] BODY[HEADER])"
        
        try await sendCommand(command)
        
        guard let responses = continuation?.getReturns() else {
            throw IMAPServiceError.commandFailed("No response")
        }
        
        return parseEmailBody(from: responses, messageID: messageID)
    }
    
    func setFlags(messageIDs: [String], seen: Bool) async throws {
        guard isConnected, isAuthenticated else {
            throw IMAPServiceError.notConnected
        }
        
        let flag: String = seen ? "\\Seen" : "\\Seen"
        let mode: String = seen ? "+FLAGS" : "-FLAGS"
        
        for msgID in messageIDs {
            let tag = generateTag()
            currentTag = tag
            let command = "\(tag) STORE \(msgID) \(mode) (\(flag))"
            
            try await sendCommand(command)
        }
    }
    
    func moveMessages(messageIDs: [String], toFolder: String) async throws {
        guard isConnected, isAuthenticated else {
            throw IMAPServiceError.notConnected
        }
        
        for msgID in messageIDs {
            let tag = generateTag()
            currentTag = tag
            let command = "\(tag) MOVE \(msgID) \(toFolder)"
            
            try await sendCommand(command)
        }
    }
    
    func deleteMessages(messageIDs: [String]) async throws {
        guard isConnected, isAuthenticated else {
            throw IMAPServiceError.notConnected
        }
        
        for msgID in messageIDs {
            let tag = generateTag()
            currentTag = tag
            let command = "\(tag) STORE \(msgID) +FLAGS (\\Deleted)"
            
            try await sendCommand(command)
        }
        
        let tag = generateTag()
        currentTag = tag
        let expungeCommand = "\(tag) EXPUNGE"
        
        try await sendCommand(expungeCommand)
    }
    
    func listFolders() async throws -> [FolderInfo] {
        guard isConnected, isAuthenticated else {
            throw IMAPServiceError.notConnected
        }
        
        let tag = generateTag()
        currentTag = tag
        let command = "\(tag) LIST \"\" \"*\""
        
        try await sendCommand(command)
        
        guard let responses = continuation?.getReturns() else {
            return []
        }
        
        return parseFolderList(from: responses)
    }
    
    func logout() async throws {
        guard isConnected else { return }
        
        let tag = generateTag()
        currentTag = tag
        let command = "\(tag) LOGOUT"
        
        try? await sendCommand(command)
        
        closeConnection()
    }
    
    private func closeConnection() {
        connection?.cancel()
        connection = nil
        isConnected = false
        isAuthenticated = false
        selectedFolder = nil
    }
    
    private func sendCommand(_ command: String) async throws {
        guard let data = "\(command)\r\n".data(using: .utf8) else {
            throw IMAPServiceError.commandFailed("Failed to encode command")
        }
        
        responseBuffer.removeAll()
        
        return try await withCheckedThrowingContinuation { continuation in
            self.continuation = CheckedContinuation { self.continuation?.resume(returning: $0); return }
            self.continuation = nil
            
            connection?.send(content: data, completion: .contentProcessed { error in
                if let error = error {
                    continuation.resume(throwing: IMAPServiceError.connectionFailed(error.localizedDescription))
                } else {
                    self.continuation = CheckedContinuation { continuation.resume(returning: $0) }
                }
            })
        }
    }
    
    private func generateTag() -> String {
        return "A\(Int.random(in: 1000...9999))"
    }
    
    private var tag: String {
        return currentTag
    }
    
    private func parseFolderInfo(from responses: [IMAPResponseType], name: String) -> FolderInfo {
        var totalMessages = 0
        var recentMessages = 0
        var unseenMessages = 0
        
        for response in responses {
            if case .untagged(let data) = response {
                switch data {
                case .exists(let count):
                    totalMessages = count
                case .recent(let count):
                    recentMessages = count
                default:
                    break
                }
            }
        }
        
        return FolderInfo(name: name, path: name, unreadCount: unseenMessages, totalCount: totalMessages)
    }
    
    private func parseEmailHeaders(from responses: [IMAPResponseType]) -> [EmailInfo] {
        var emails: [EmailInfo] = []
        
        for response in responses {
            if case .untagged(let data) = response {
                if case .fetch(let fields) = data {
                    if let raw = fields["raw"] as? String {
                        if let email = parseEnvelope(raw) {
                            emails.append(email)
                        }
                    }
                }
            }
        }
        
        return emails
    }
    
    private func parseEnvelope(_ content: String) -> EmailInfo? {
        guard let envelopeStart = content.range(of: "ENVELOPE") else { return nil }
        let rest = String(content[envelopeStart.upperBound...])
        
        guard let openParen = rest.firstIndex(of: "("),
              let closeParen = rest.lastIndex(of: ")") else { return nil }
        
        let envelopeContent = String(rest[openParen...closeParen])
        
        let components = parseParenthesizedList(envelopeContent)
        guard components.count >= 9 else { return nil }
        
        let subject = extractQuotedString(components[0])
        let fromList = parseAddressList(components[2])
        let dateStr = extractQuotedString(components[7])
        let messageID = extractQuotedString(components[8]) ?? UUID().uuidString
        
        let from = fromList.first
        let fromAddr = from?["email"] ?? ""
        let fromName = from?["name"]
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "d-MMM-yyyy HH:mm:ss Z"
        let date = dateFormatter.date(from: dateStr) ?? Date()
        
        return EmailInfo(
            id: messageID,
            messageID: messageID,
            from: fromAddr,
            fromName: fromName,
            to: [],
            cc: nil,
            subject: subject,
            preview: nil,
            textBody: nil,
            hasAttachments: false,
            isRead: false,
            isStarred: false,
            date: date
        )
    }
    
    private func parseAddressList(_ content: String) -> [[String: String]] {
        guard content.contains("(") else { return [] }
        
        var results: [[String: String]] = []
        
        if let outerStart = content.firstIndex(of: "("),
           let outerEnd = content.lastIndex(of: ")") {
            let inner = String(content[content.index(after: outerStart)..<outerEnd])
            let parts = parseParenthesizedList(inner)
            
            if parts.count >= 3 {
                let name = extractQuotedString(parts[0])
                let email = extractQuotedString(parts[2])
                results.append(["name": name ?? "", "email": email ?? ""])
            }
        }
        
        return results
    }
    
    private func parseParenthesizedList(_ content: String) -> [String] {
        var result: [String] = []
        var current = ""
        var depth = 0
        var inQuote = false
        
        for char in content {
            if char == "\"" && !inQuote {
                inQuote = true
            } else if char == "\"" && inQuote {
                inQuote = false
            } else if char == "(" && !inQuote {
                depth += 1
                current.append(char)
            } else if char == ")" && !inQuote {
                depth -= 1
                current.append(char)
            } else if char == " " && depth == 0 && !inQuote {
                if !current.isEmpty {
                    result.append(current)
                    current = ""
                }
            } else {
                current.append(char)
            }
        }
        
        if !current.isEmpty {
            result.append(current)
        }
        
        return result
    }
    
    private func extractQuotedString(_ content: String) -> String? {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("\"") && trimmed.hasSuffix("\"") {
            return String(trimmed.dropFirst().dropLast())
        } else if trimmed.hasPrefix("NIL") {
            return nil
        }
        return trimmed
    }
    
    private func parseEmailBody(from responses: [IMAPResponseType], messageID: String) -> EmailDetail {
        var textBody: String?
        var headers: [String: String] = [:]
        
        for response in responses {
            if case .untagged(let data) = response {
                if case .fetch(let fields) = data {
                    if let raw = fields["raw"] as? String {
                        if raw.contains("BODY[TEXT]") {
                            textBody = extractBodyText(raw)
                        }
                        if raw.contains("BODY[HEADER]") {
                            headers = extractHeaders(raw)
                        }
                    }
                }
            }
        }
        
        return EmailDetail(
            from: EmailInfo(
                id: messageID,
                messageID: messageID,
                from: headers["From"] ?? "",
                fromName: nil,
                to: [],
                cc: nil,
                subject: headers["Subject"],
                preview: nil,
                textBody: textBody,
                hasAttachments: false,
                isRead: false,
                isStarred: false,
                date: Date()
            ),
            textBody: textBody,
            htmlBody: nil,
            attachments: []
        )
    }
    
    private func extractBodyText(_ content: String) -> String? {
        guard let start = content.range(of: "BODY[TEXT]") else { return nil }
        let rest = String(content[start.upperBound...])
        
        if let openBrace = rest.firstIndex(of: "{"),
           let closeBrace = rest.firstIndex(of: "}") {
            let afterBrace = String(rest[rest.index(after: closeBrace)...])
            return afterBrace.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        
        return nil
    }
    
    private func extractHeaders(_ content: String) -> [String: String] {
        var headers: [String: String] = [:]
        
        if let start = content.range(of: "BODY[HEADER]"),
           let openBrace = content.range(of: "{", after: start.upperBound),
           let closeBrace = content.range(of: "}", after: openBrace.upperBound) {
            let headerContent = String(content[closeBrace.upperBound...])
            let lines = headerContent.components(separatedBy: "\r\n")
            
            for line in lines {
                if let colonIndex = line.firstIndex(of: ":") {
                    let key = String(line[..<colonIndex]).trimmingCharacters(in: .whitespaces)
                    let value = String(line[line.index(after: colonIndex)...]).trimmingCharacters(in: .whitespaces)
                    headers[key] = value
                }
            }
        }
        
        return headers
    }
    
    private func parseFolderList(from responses: [IMAPResponseType]) -> [FolderInfo] {
        var folders: [FolderInfo] = []
        
        for response in responses {
            if case .untagged(let data) = response {
                if case .raw(let content) = data {
                    if content.contains("LIST") {
                        if let name = extractFolderName(content) {
                            folders.append(FolderInfo(name: name, path: name))
                        }
                    }
                }
            }
        }
        
        return folders
    }
    
    private func extractFolderName(_ content: String) -> String? {
        let parts = content.components(separatedBy: "\"")
        if parts.count >= 2 {
            return parts[1]
        }
        return nil
    }
}

enum IMAPServiceError: Error, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case notConnected
    case commandFailed(String)
    case timeout
    case folderNotFound(String)
    case messageNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .notConnected: return "Not connected to server"
        case .commandFailed(let msg): return "Command failed: \(msg)"
        case .timeout: return "Connection timeout"
        case .folderNotFound(let folder): return "Folder not found: \(folder)"
        case .messageNotFound(let msg): return "Message not found: \(msg)"
        }
    }
}

enum IMAPResponseType {
    case ok
    case no
    case bad
    case bye
    case untagged(ResponseData)
    case tagged(tag: String, response: IMAPResponseType)
}

enum ResponseData {
    case flags([String])
    case exists(Int)
    case recent(Int)
    case list([[String: String]])
    case search([String])
    case fetch([String: Any])
    case status([String: Any])
    case raw(String)
}

extension CheckedContinuation where Success == [IMAPResponseType], Failure == Error {
    func getReturns() -> Success? {
        return nil
    }
}
