import Foundation
import Security

final class SMTPService {
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let stateLock = NSLock()
    private var connectionState: SMTPConnectionState = .disconnected
    private var serverExtensions: [String: [String]] = [:]
    private let hostname: String
    
    init(hostname: String = SMTPService.localHostname()) {
        self.hostname = hostname
    }
    
    func connect(host: String, port: Int, useSSL: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stateLock.lock()
            guard connectionState == .disconnected else {
                stateLock.unlock()
                continuation.resume(throwing: SMTPServiceError.connectionFailed("Already connected"))
                return
            }
            connectionState = .connecting
            stateLock.unlock()
            
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            
            CFStreamCreatePairWithSocketToHost(nil, host as CFString, UInt32(port), &readStream, &writeStream)
            
            guard let input = readStream?.takeRetainedValue(),
                  let output = writeStream?.takeRetainedValue() else {
                stateLock.lock()
                connectionState = .disconnected
                stateLock.unlock()
                continuation.resume(throwing: SMTPServiceError.connectionFailed("Failed to create streams"))
                return
            }
            
            inputStream = input as InputStream
            outputStream = output as OutputStream
            
            if useSSL {
                let sslSettings: [String: Any] = [
                    "kCFStreamSocketSecurityLevelKey": "TLSv1.2",
                    "kCFStreamPropertyShouldCloseNativeSocket": true
                ]
                inputStream?.setProperty(sslSettings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
                outputStream?.setProperty(sslSettings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
            }
            
            inputStream?.open()
            outputStream?.open()
            
            stateLock.lock()
            connectionState = .connected
            stateLock.unlock()
            
            guard let response = readResponse() else {
                stateLock.lock()
                connectionState = .disconnected
                stateLock.unlock()
                continuation.resume(throwing: SMTPServiceError.connectionFailed("No greeting from server"))
                return
            }
            
            if response.code != 220 {
                stateLock.lock()
                connectionState = .disconnected
                stateLock.unlock()
                continuation.resume(throwing: SMTPServiceError.serverError(response.code, response.message))
                return
            }
            
            continuation.resume()
        }
    }
    
    func login(username: String, password: String) async throws {
        try await performEHLO()
        
        let response = try await authenticate(username: username, password: password)
        
        if !response.isSuccess {
            throw SMTPServiceError.authenticationFailed(response.message)
        }
        
        stateLock.lock()
        connectionState = .authenticated
        stateLock.unlock()
    }
    
    func send(message: SendMessageRequest) async throws -> SendResult {
        try await ensureConnected()
        
        try await sendCommand(.mailFrom(message.from))
        
        var acceptedRecipients: [String] = []
        var rejectedRecipients: [String] = []
        
        for recipient in message.to {
            let response = try await sendCommand(.rcptTo(recipient))
            if response.code == 250 {
                acceptedRecipients.append(recipient)
            } else {
                rejectedRecipients.append(recipient)
            }
        }
        
        if let ccRecipients = message.cc {
            for recipient in ccRecipients {
                let response = try await sendCommand(.rcptTo(recipient))
                if response.code == 250 {
                    acceptedRecipients.append(recipient)
                } else {
                    rejectedRecipients.append(recipient)
                }
            }
        }
        
        if let bccRecipients = message.bcc {
            for recipient in bccRecipients {
                try await sendCommand(.rcptTo(recipient))
            }
        }
        
        try await sendCommand(.data)
        
        let messageData = buildMessageData(message)
        try await sendRawData(messageData)
        
        guard let response = readResponse() else {
            throw SMTPServiceError.messageSendFailed("No response after DATA")
        }
        
        if response.code != 250 {
            throw SMTPServiceError.messageSendFailed(response.message)
        }
        
        let messageID = SMTPService.generateMessageID()
        
        return SendResult(
            messageID: messageID,
            sentAt: Date(),
            acceptedRecipients: acceptedRecipients,
            rejectedRecipients: rejectedRecipients.isEmpty ? nil : rejectedRecipients
        )
    }
    
    func disconnect() async throws {
        stateLock.lock()
        let isConnected = connectionState != .disconnected
        stateLock.unlock()
        
        guard isConnected else { return }
        
        try? await sendCommand(.quit)
        
        inputStream?.close()
        outputStream?.close()
        
        inputStream = nil
        outputStream = nil
        
        stateLock.lock()
        connectionState = .disconnected
        stateLock.unlock()
    }
    
    private func performEHLO() async throws {
        let response = try await sendCommand(.ehlo(hostname))
        
        if response.code == 502 || response.code == 500 {
            _ = try await sendCommand(.helo(hostname))
            return
        }
        
        if response.code != 250 {
            throw SMTPServiceError.serverError(response.code, response.message)
        }
        
        serverExtensions = parseEHLOExtensions(response.message)
    }
    
    private func authenticate(username: String, password: String) async throws -> SMTPResponse {
        let supportedAuths = serverExtensions["AUTH"] ?? []
        
        if supportedAuths.contains("PLAIN") || supportedAuths.isEmpty {
            let credentials = SMTPAuthCredentials(username: username, password: password)
            let authString = credentials.plainCredential()
            return try await sendCommand(.authPlain(authString))
        }
        
        if supportedAuths.contains("LOGIN") {
            _ = try await sendCommand(.authLogin)
            _ = try await sendCommand(.authLoginUsername(username))
            return try await sendCommand(.authLoginPassword(password))
        }
        
        throw SMTPServiceError.authenticationFailed("No supported authentication method")
    }
    
    private func sendCommand(_ command: SMTPCommand) async throws -> SMTPResponse {
        try await ensureConnected()
        return try await withCheckedThrowingContinuation { continuation in
            guard let output = outputStream else {
                continuation.resume(throwing: SMTPServiceError.notConnected)
                return
            }
            
            let data = command.data
            data.withUnsafeBytes { buffer in
                guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
                output.write(pointer, maxLength: data.count)
            }
            
            if let response = readResponse() {
                continuation.resume(returning: response)
            } else {
                continuation.resume(throwing: SMTPServiceError.connectionFailed("Failed to read response"))
            }
        }
    }
    
    private func sendRawData(_ data: Data) async throws {
        try await ensureConnected()
        
        guard let output = outputStream else {
            throw SMTPServiceError.notConnected
        }
        
        data.withUnsafeBytes { buffer in
            guard let pointer = buffer.baseAddress?.assumingMemoryBound(to: UInt8.self) else { return }
            output.write(pointer, maxLength: data.count)
        }
    }
    
    private func readResponse() -> SMTPResponse? {
        guard let input = inputStream else { return nil }
        
        var buffer = [UInt8](repeating: 0, count: 4096)
        var responseData = Data()
        
        while input.hasBytesAvailable {
            let bytesRead = input.read(&buffer, maxLength: buffer.count)
            if bytesRead > 0 {
                responseData.append(contentsOf: buffer[0..<bytesRead])
            } else if bytesRead < 0 {
                return nil
            }
            
            if let response = parseResponse(responseData) {
                if response.message.count > 1 {
                    if let lastLine = response.message.last, String(lastLine).hasSuffix(response.code.description) {
                        return response
                    }
                } else {
                    return response
                }
            }
        }
        
        return parseResponse(responseData)
    }
    
    private func parseResponse(_ data: Data) -> SMTPResponse? {
        guard let str = String(data: data, encoding: .utf8) else { return nil }
        
        let lines = str.components(separatedBy: "\r\n").filter { !$0.isEmpty }
        guard let firstLine = lines.first else { return nil }
        
        let parts = firstLine.components(separatedBy: " ")
        guard parts.count >= 2,
              let code = Int(parts[0]) else { return nil }
        
        let message = lines.map { String($0.dropFirst(4)) }
        return SMTPResponse(code: code, message: message.joined(separator: " "), lines: lines)
    }
    
    private func parseEHLOExtensions(_ message: String) -> [String: [String]] {
        var extensions: [String: [String]] = [:]
        let lines = message.components(separatedBy: "\r\n")
        
        for line in lines.dropFirst() {
            let parts = line.components(separatedBy: " ")
            if let key = parts.first {
                extensions[key] = Array(parts.dropFirst())
            }
        }
        
        return extensions
    }
    
    private func ensureConnected() async throws {
        stateLock.lock()
        let state = connectionState
        stateLock.unlock()
        
        guard state == .connected || state == .authenticated else {
            throw SMTPServiceError.notConnected
        }
    }
    
    private func buildMessageData(_ message: SendMessageRequest) -> Data {
        var result = Data()
        
        let messageID = SMTPService.generateMessageID()
        let date = SMTPService.formatDate(Date())
        
        result.append("Message-ID: <\(messageID)>\r\n".data(using: .utf8)!)
        result.append("Date: \(date)\r\n".data(using: .utf8)!)
        result.append("From: \(message.from)\r\n".data(using: .utf8)!)
        result.append("To: \(message.to.joined(separator: ", "))\r\n".data(using: .utf8)!)
        
        if let cc = message.cc {
            result.append("Cc: \(cc.joined(separator: ", "))\r\n".data(using: .utf8)!)
        }
        
        result.append("Subject: \(SMTPService.encodeHeader(message.subject))\r\n".data(using: .utf8)!)
        
        if let inReplyTo = message.inReplyTo {
            result.append("In-Reply-To: \(inReplyTo)\r\n".data(using: .utf8)!)
        }
        
        if let references = message.references {
            result.append("References: \(references.joined(separator: " "))\r\n".data(using: .utf8)!)
        }
        
        result.append("\r\n".data(using: .utf8)!)
        
        if let textBody = message.textBody {
            result.append(textBody.data(using: .utf8)!)
        }
        
        result.append("\r\n".data(using: .utf8)!)
        
        return result
    }
    
    private static func localHostname() -> String {
        ProcessInfo.processInfo.hostName
    }
    
    private static func generateMessageID() -> String {
        let uuid = UUID().uuidString.lowercased()
        let hostname = localHostname()
        return "\(uuid).\(hostname)"
    }
    
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
    
    private static func encodeHeader(_ string: String) -> String {
        guard string.range(of: "[^\\x00-\\x7F]", options: .regularExpression) != nil else {
            return string
        }
        
        let data = string.data(using: .utf8)!
        return "=?utf-8?B?\(data.base64EncodedString())?="
    }
}

enum SMTPConnectionState {
    case disconnected
    case connecting
    case connected
    case authenticated
}

struct SMTPResponse {
    let code: Int
    let message: String
    let lines: [String]
    
    var isSuccess: Bool { code >= 200 && code < 300 }
}

enum SMTPServiceError: Error, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case notConnected
    case serverError(Int, String)
    case messageSendFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg): return "Connection failed: \(msg)"
        case .authenticationFailed(let msg): return "Authentication failed: \(msg)"
        case .notConnected: return "Not connected to server"
        case .serverError(let code, let msg): return "Server error (\(code)): \(msg)"
        case .messageSendFailed(let msg): return "Message send failed: \(msg)"
        }
    }
}

struct SendMessageRequest {
    let from: String
    let to: [String]
    let cc: [String]?
    let bcc: [String]?
    let subject: String
    let textBody: String?
    let htmlBody: String?
    let inReplyTo: String?
    let references: [String]?
    
    init(
        from: String,
        to: [String],
        cc: [String]? = nil,
        bcc: [String]? = nil,
        subject: String,
        textBody: String? = nil,
        htmlBody: String? = nil,
        inReplyTo: String? = nil,
        references: [String]? = nil
    ) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.textBody = textBody
        self.htmlBody = htmlBody
        self.inReplyTo = inReplyTo
        self.references = references
    }
}

struct SendResult {
    let messageID: String
    let sentAt: Date
    let acceptedRecipients: [String]
    let rejectedRecipients: [String]?
}

enum SMTPCommand {
    case ehlo(String)
    case helo(String)
    case authPlain(String)
    case authLogin
    case authLoginUsername(String)
    case authLoginPassword(String)
    case mailFrom(String)
    case rcptTo(String)
    case data
    case quit
    case help(String)
    
    var data: Data {
        switch self {
        case .ehlo(let host):
            return "EHLO \(host)\r\n".data(using: .utf8)!
        case .helo(let host):
            return "HELO \(host)\r\n".data(using: .utf8)!
        case .authPlain(let credentials):
            return "AUTH PLAIN \(credentials)\r\n".data(using: .utf8)!
        case .authLogin:
            return "AUTH LOGIN\r\n".data(using: .utf8)!
        case .authLoginUsername(let username):
            return "\(username)\r\n".data(using: .utf8)!
        case .authLoginPassword(let password):
            return "\(password)\r\n".data(using: .utf8)!
        case .mailFrom(let from):
            return "MAIL FROM:<\(from)>\r\n".data(using: .utf8)!
        case .rcptTo(let to):
            return "RCPT TO:<\(to)>\r\n".data(using: .utf8)!
        case .data:
            return "DATA\r\n".data(using: .utf8)!
        case .quit:
            return "QUIT\r\n".data(using: .utf8)!
        case .help(let help):
            return "HELP \(help)\r\n".data(using: .utf8)!
        }
    }
}

struct SMTPAuthCredentials {
    let username: String
    let password: String
    
    func plainCredential() -> String {
        let authString = "\u{0000}\(username)\u{0000}\(password)"
        return authString.data(using: .utf8)!.base64EncodedString()
    }
}
