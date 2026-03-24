import Foundation
import Security

final class SMTPClient: Sendable {
    private let parser = SMTPResponseParser()
    private var inputStream: InputStream?
    private var outputStream: OutputStream?
    private let stateLock = NSLock()
    private var connectionState: SMTPConnectionState = .disconnected
    private var serverExtensions: [String: [String]] = [:]
    private let hostname: String
    
    init(hostname: String = SMTPUtils.localHostname()) {
        self.hostname = hostname
    }
    
    deinit {
        Task {
            try? await disconnect()
        }
    }
    
    func connect(host: String, port: Int, useSSL: Bool) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            stateLock.lock()
            guard connectionState == .disconnected else {
                stateLock.unlock()
                continuation.resume(throwing: SMTPError.connectionFailed("Already connected"))
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
                continuation.resume(throwing: SMTPError.connectionFailed("Failed to create streams"))
                return
            }
            
            inputStream = input as InputStream
            outputStream = output as OutputStream
            
            if useSSL {
                let sslSettings: [String: Any] = [
                    kCFStreamSSLLevel as String: "kCFStreamSocketSecurityLevelTLSv1_2",
                    kCFStreamPropertyShouldCloseNativeSocket as String: true
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
                continuation.resume(throwing: SMTPError.connectionFailed("No greeting from server"))
                return
            }
            
            if response.code != 220 {
                stateLock.lock()
                connectionState = .disconnected
                stateLock.unlock()
                continuation.resume(throwing: SMTPError.serverError(response.code, response.combinedMessage))
                return
            }
            
            continuation.resume()
        }
    }
    
    func login(username: String, password: String) async throws {
        try await performEHLO()
        
        let response = try await authenticate(username: username, password: password)
        
        if !response.isSuccess {
            throw SMTPError.authenticationFailed(response.combinedMessage)
        }
        
        stateLock.lock()
        connectionState = .authenticated
        stateLock.unlock()
    }
    
    func send(message: SMTPMessage) async throws -> SendResult {
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
            throw SMTPError.messageSendFailed("No response after DATA")
        }
        
        if response.code != 250 {
            throw SMTPError.messageSendFailed(response.combinedMessage)
        }
        
        let messageID = parser.extractMessageID(from: response) ?? SMTPUtils.generateMessageID()
        
        return SendResult(
            messageID: messageID,
            sentAt: Date(),
            acceptedRecipients: acceptedRecipients,
            rejectedRecipients: rejectedRecipients.isEmpty ? nil : rejectedRecipients
        )
    }
    
    func verify(address: String) async throws -> Bool {
        try await ensureConnected()
        
        let response = try await sendCommand(.vrfy(address))
        
        if response.code == 250 || response.code == 251 {
            return true
        }
        return false
    }
    
    func expandList(address: String) async throws -> [String] {
        try await ensureConnected()
        
        let response = try await sendCommand(.expn(address))
        
        if response.code == 250 {
            return parser.extractAddresses(from: response)
        }
        
        throw SMTPError.serverError(response.code, response.combinedMessage)
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
            throw SMTPError.serverError(response.code, response.combinedMessage)
        }
        
        serverExtensions = parser.parseehloExtensions(response)
        
        if serverExtensions["STARTTLS"] != nil && serverExtensions["STARTTLS"]?.isEmpty == false {
            try await performSTARTTLS()
        }
    }
    
    private func performSTARTTLS() async throws {
        try await sendCommand(.help("STARTTLS"))
        
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            guard let input = inputStream, let output = outputStream else {
                continuation.resume(throwing: SMTPError.notConnected)
                return
            }
            
            let sslSettings: [String: Any] = [
                kCFStreamSSLLevel as String: "kCFStreamSocketSecurityLevelTLSv1_2"
            ]
            
            input.setProperty(sslSettings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
            output.setProperty(sslSettings, forKey: kCFStreamPropertySSLSettings as Stream.PropertyKey)
            
            input.close()
            output.close()
            
            var readStream: Unmanaged<CFReadStream>?
            var writeStream: Unmanaged<CFWriteStream>?
            
            CFStreamCreatePairWithSocketToHost(nil, "" as CFString, 0, &readStream, &writeStream)
            
            if let input = readStream?.takeRetainedValue(),
               let output = writeStream?.takeRetainedValue() {
                self.inputStream = input as InputStream
                self.outputStream = output as OutputStream
                self.inputStream?.open()
                self.outputStream?.open()
            }
            
            continuation.resume()
        }
        
        let response = try await sendCommand(.ehlo(hostname))
        if response.code != 250 {
            throw SMTPError.serverError(response.code, response.combinedMessage)
        }
        
        serverExtensions = parser.parseehloExtensions(response)
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
        
        throw SMTPError.authenticationFailed("No supported authentication method")
    }
    
    private func sendCommand(_ command: SMTPCommand) async throws -> SMTPResponse {
        try await ensureConnected()
        return try await withCheckedThrowingContinuation { continuation in
            guard let output = outputStream else {
                continuation.resume(throwing: SMTPError.notConnected)
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
                continuation.resume(throwing: SMTPError.connectionFailed("Failed to read response"))
            }
        }
    }
    
    private func sendRawData(_ data: Data) async throws {
        try await ensureConnected()
        
        guard let output = outputStream else {
            throw SMTPError.notConnected
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
            
            if let response = parser.parse(responseData) {
                if response.message.count > 1 {
                    if let lastLine = response.message.last, lastLine.hasSuffix(response.code.description) {
                        return response
                    }
                } else {
                    return response
                }
            }
        }
        
        return parser.parse(responseData)
    }
    
    private func ensureConnected() async throws {
        stateLock.lock()
        let state = connectionState
        stateLock.unlock()
        
        guard state == .connected || state == .authenticated else {
            throw SMTPError.notConnected
        }
    }
    
    private func buildMessageData(_ message: SMTPMessage) -> Data {
        var result = Data()
        
        let messageID = SMTPUtils.generateMessageID()
        let date = SMTPUtils.formatDate(Date())
        
        result.append("Message-ID: <\(messageID)>\r\n".data(using: .utf8)!)
        result.append("Date: \(date)\r\n".data(using: .utf8)!)
        result.append("From: \(message.from)\r\n".data(using: .utf8)!)
        result.append("To: \(message.to.joined(separator: ", "))\r\n".data(using: .utf8)!)
        
        if let cc = message.cc {
            result.append("Cc: \(cc.joined(separator: ", "))\r\n".data(using: .utf8)!)
        }
        
        result.append("Subject: \(SMTPUtils.encodeHeader(message.subject))\r\n".data(using: .utf8)!)
        
        if let inReplyTo = message.inReplyTo {
            result.append("In-Reply-To: \(inReplyTo)\r\n".data(using: .utf8)!)
        }
        
        if let references = message.references {
            result.append("References: \(references.joined(separator: " "))\r\n".data(using: .utf8)!)
        }
        
        for (key, value) in message.customHeaders {
            result.append("\(key): \(value)\r\n".data(using: .utf8)!)
        }
        
        let hasAttachments = !message.attachments.isEmpty
        let hasHtml = message.htmlBody != nil
        let hasText = message.textBody != nil
        
        if hasAttachments {
            let boundary = SMTPUtils.generateBoundary()
            result.append("MIME-Version: 1.0\r\n".data(using: .utf8)!)
            result.append("Content-Type: multipart/mixed; boundary=\"\(boundary)\"\r\n".data(using: .utf8)!)
            result.append("\r\n".data(using: .utf8)!)
            
            if hasHtml || hasText {
                result.append("--\(boundary)\r\n".data(using: .utf8)!)
                result.append(buildMultipartAlternativeContent(message, hasAttachments: hasAttachments, boundary: boundary))
                result.append("\r\n".data(using: .utf8)!)
            }
            
            for attachment in message.attachments {
                result.append("--\(boundary)\r\n".data(using: .utf8)!)
                result.append(buildAttachmentContent(attachment))
                result.append("\r\n".data(using: .utf8)!)
            }
            
            result.append("--\(boundary)--\r\n".data(using: .utf8)!)
        } else if hasHtml && hasText {
            let boundary = SMTPUtils.generateBoundary()
            result.append("MIME-Version: 1.0\r\n".data(using: .utf8)!)
            result.append("Content-Type: multipart/alternative; boundary=\"\(boundary)\"\r\n".data(using: .utf8)!)
            result.append("\r\n".data(using: .utf8)!)
            
            if let text = message.textBody {
                result.append("--\(boundary)\r\n".data(using: .utf8)!)
                result.append("Content-Type: text/plain; charset=utf-8\r\n".data(using: .utf8)!)
                result.append("Content-Transfer-Encoding: quoted-printable\r\n".data(using: .utf8)!)
                result.append("\r\n".data(using: .utf8)!)
                result.append(SMTPUtils.quotedPrintableEncode(text).data(using: .utf8)!)
                result.append("\r\n".data(using: .utf8)!)
            }
            
            if let html = message.htmlBody {
                result.append("--\(boundary)\r\n".data(using: .utf8)!)
                result.append("Content-Type: text/html; charset=utf-8\r\n".data(using: .utf8)!)
                result.append("Content-Transfer-Encoding: quoted-printable\r\n".data(using: .utf8)!)
                result.append("\r\n".data(using: .utf8)!)
                result.append(SMTPUtils.quotedPrintableEncode(html).data(using: .utf8)!)
                result.append("\r\n".data(using: .utf8)!)
            }
            
            result.append("--\(boundary)--\r\n".data(using: .utf8)!)
        } else if let html = message.htmlBody {
            result.append("MIME-Version: 1.0\r\n".data(using: .utf8)!)
            result.append("Content-Type: text/html; charset=utf-8\r\n".data(using: .utf8)!)
            result.append("Content-Transfer-Encoding: quoted-printable\r\n".data(using: .utf8)!)
            result.append("\r\n".data(using: .utf8)!)
            result.append(SMTPUtils.quotedPrintableEncode(html).data(using: .utf8)!)
            result.append("\r\n".data(using: .utf8)!)
        } else if let text = message.textBody {
            result.append("MIME-Version: 1.0\r\n".data(using: .utf8)!)
            result.append("Content-Type: text/plain; charset=utf-8\r\n".data(using: .utf8)!)
            result.append("Content-Transfer-Encoding: quoted-printable\r\n".data(using: .utf8)!)
            result.append("\r\n".data(using: .utf8)!)
            result.append(SMTPUtils.quotedPrintableEncode(text).data(using: .utf8)!)
            result.append("\r\n".data(using: .utf8)!)
        }
        
        return result
    }
    
    private func buildMultipartAlternativeContent(_ message: SMTPMessage, hasAttachments: Bool, boundary: String) -> Data {
        var result = Data()
        let alternativeBoundary = SMTPUtils.generateBoundary()
        
        result.append("Content-Type: multipart/alternative; boundary=\"\(alternativeBoundary)\"\r\n".data(using: .utf8)!)
        result.append("\r\n".data(using: .utf8)!)
        
        if let text = message.textBody {
            result.append("--\(alternativeBoundary)\r\n".data(using: .utf8)!)
            result.append("Content-Type: text/plain; charset=utf-8\r\n".data(using: .utf8)!)
            result.append("Content-Transfer-Encoding: quoted-printable\r\n".data(using: .utf8)!)
            result.append("\r\n".data(using: .utf8)!)
            result.append(SMTPUtils.quotedPrintableEncode(text).data(using: .utf8)!)
            result.append("\r\n".data(using: .utf8)!)
        }
        
        if let html = message.htmlBody {
            result.append("--\(alternativeBoundary)\r\n".data(using: .utf8)!)
            result.append("Content-Type: text/html; charset=utf-8\r\n".data(using: .utf8)!)
            result.append("Content-Transfer-Encoding: quoted-printable\r\n".data(using: .utf8)!)
            result.append("\r\n".data(using: .utf8)!)
            result.append(SMTPUtils.quotedPrintableEncode(html).data(using: .utf8)!)
            result.append("\r\n".data(using: .utf8)!)
        }
        
        result.append("--\(alternativeBoundary)--\r\n".data(using: .utf8)!)
        
        return result
    }
    
    private func buildAttachmentContent(_ attachment: SMTPAttachment) -> Data {
        var result = Data()
        
        let contentDisposition: String
        if attachment.isInline {
            contentDisposition = "inline"
        } else {
            contentDisposition = "attachment"
        }
        
        let encodedFilename = SMTPUtils.encodeHeader(attachment.filename)
        
        result.append("Content-Type: \(attachment.mimeType); name=\"\(encodedFilename)\"\r\n".data(using: .utf8)!)
        result.append("Content-Disposition: \(contentDisposition); filename=\"\(encodedFilename)\"\r\n".data(using: .utf8)!)
        
        if let contentID = attachment.contentID {
            result.append("Content-ID: <\(contentID)>\r\n".data(using: .utf8)!)
        }
        
        result.append("Content-Transfer-Encoding: base64\r\n".data(using: .utf8)!)
        result.append("\r\n".data(using: .utf8)!)
        result.append(attachment.data.base64EncodedData())
        result.append("\r\n".data(using: .utf8)!)
        
        return result
    }
}

enum SMTPUtils {
    static func localHostname() -> String {
        ProcessInfo.processInfo.hostName
    }
    
    static func generateMessageID() -> String {
        let uuid = UUID().uuidString.lowercased()
        let hostname = localHostname()
        return "\(uuid).\(hostname)"
    }
    
    static func generateBoundary() -> String {
        "----=_Part_\(UUID().uuidString)"
    }
    
    static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "EEE, dd MMM yyyy HH:mm:ss Z"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: date)
    }
    
    static func encodeHeader(_ string: String) -> String {
        guard string.range(of: "[^\\x00-\\x7F]", options: .regularExpression) != nil else {
            return string
        }
        
        let data = string.data(using: .utf8)!
        return "=?utf-8?B?\(data.base64EncodedString())?="
    }
    
    static func quotedPrintableEncode(_ string: String) -> String {
        var result = ""
        let chars = Array(string.utf8)
        
        for char in chars {
            if char == 10 || char == 13 {
                result.append(Character(UnicodeScalar(char)))
            } else if char >= 33 && char <= 126 && char != 61 {
                result.append(Character(UnicodeScalar(char)))
            } else {
                result.append(String(format: "=%02X", char))
            }
        }
        
        return result
    }
}
