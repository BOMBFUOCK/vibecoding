import Foundation

// MARK: - SMTP Message Model

/// Represents an SMTP email message
public struct SMTPMessage: Sendable {
    /// Sender's email address
    public let from: String
    
    /// List of recipient email addresses
    public let to: [String]
    
    /// CC recipients (optional)
    public let cc: [String]?
    
    /// BCC recipients (optional)
    public let bcc: [String]?
    
    /// Email subject
    public let subject: String
    
    /// Plain text body (optional)
    public let textBody: String?
    
    /// HTML body (optional)
    public let htmlBody: String?
    
    /// List of attachments
    public let attachments: [SMTPAttachment]
    
    /// Message-ID this message is in reply to (optional)
    public let inReplyTo: String?
    
    /// List of reference Message-IDs (optional)
    public let references: [String]?
    
    /// Custom headers
    public let customHeaders: [String: String]
    
    public init(
        from: String,
        to: [String],
        cc: [String]? = nil,
        bcc: [String]? = nil,
        subject: String,
        textBody: String? = nil,
        htmlBody: String? = nil,
        attachments: [SMTPAttachment] = [],
        inReplyTo: String? = nil,
        references: [String]? = nil,
        customHeaders: [String: String] = [:]
    ) {
        self.from = from
        self.to = to
        self.cc = cc
        self.bcc = bcc
        self.subject = subject
        self.textBody = textBody
        self.htmlBody = htmlBody
        self.attachments = attachments
        self.inReplyTo = inReplyTo
        self.references = references
        self.customHeaders = customHeaders
    }
}

// MARK: - SMTP Attachment

/// Represents an email attachment
public struct SMTPAttachment: Sendable {
    /// Filename
    public let filename: String
    
    /// MIME type (e.g., "image/png", "application/pdf")
    public let mimeType: String
    
    /// Raw attachment data
    public let data: Data
    
    /// Content-ID for inline attachments (optional)
    public let contentID: String?
    
    /// Whether this is an inline attachment
    public let isInline: Bool
    
    public init(
        filename: String,
        mimeType: String,
        data: Data,
        contentID: String? = nil,
        isInline: Bool = false
    ) {
        self.filename = filename
        self.mimeType = mimeType
        self.data = data
        self.contentID = contentID
        self.isInline = isInline
    }
}

// MARK: - Send Result

/// Result of sending an email
public struct SendResult: Sendable {
    /// The Message-ID assigned by the server
    public let messageID: String
    
    /// Timestamp when the email was sent
    public let sentAt: Date
    
    /// List of accepted recipient addresses
    public let acceptedRecipients: [String]
    
    /// List of rejected recipient addresses (optional)
    public let rejectedRecipients: [String]?
    
    public init(
        messageID: String,
        sentAt: Date = Date(),
        acceptedRecipients: [String],
        rejectedRecipients: [String]? = nil
    ) {
        self.messageID = messageID
        self.sentAt = sentAt
        self.acceptedRecipients = acceptedRecipients
        self.rejectedRecipients = rejectedRecipients
    }
}

// MARK: - SMTP Response

/// Represents an SMTP server response
public struct SMTPResponse: Sendable {
    /// Response code (220, 250, 354, etc.)
    public let code: Int
    
    /// Response message lines
    public let message: [String]
    
    /// Whether this is an intermediate response (starts with '-')
    public let isIntermediate: Bool
    
    /// Whether the response indicates success
    public var isSuccess: Bool {
        code >= 200 && code < 400
    }
    
    /// Whether the response indicates an error
    public var isError: Bool {
        code >= 400
    }
    
    public init(code: Int, message: [String], isIntermediate: Bool = false) {
        self.code = code
        self.message = message
        self.isIntermediate = isIntermediate
    }
    
    /// Combined message string
    public var combinedMessage: String {
        message.joined(separator: " ")
    }
}

// MARK: - SMTP Connection State

/// Represents the state of an SMTP connection
public enum SMTPConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case authenticated
    case ready
}

// MARK: - SMTP Authentication Method

/// Supported SMTP authentication methods
public enum SMTPAuthMethod: Sendable {
    case plain
    case login
    
    var authString: String {
        switch self {
        case .plain:
            return "PLAIN"
        case .login:
            return "LOGIN"
        }
    }
}

// MARK: - SMTP Server Info

/// SMTP server configuration for common email providers
public struct SMTPServerInfo: Sendable {
    public let host: String
    public let port: Int
    public let useSSL: Bool
    
    public init(host: String, port: Int, useSSL: Bool) {
        self.host = host
        self.port = port
        self.useSSL = useSSL
    }
    
    // MARK: - Common Email Providers
    
    public static let gmail = SMTPServerInfo(host: "smtp.gmail.com", port: 465, useSSL: true)
    public static let outlook = SMTPServerInfo(host: "smtp.office365.com", port: 587, useSSL: false)
    public static let qqmail = SMTPServerInfo(host: "smtp.qq.com", port: 465, useSSL: true)
    public static let netEase163 = SMTPServerInfo(host: "smtp.163.com", port: 465, useSSL: true)
    public static let netEase126 = SMTPServerInfo(host: "smtp.126.com", port: 465, useSSL: true)
    public static let yahoo = SMTPServerInfo(host: "smtp.mail.yahoo.com", port: 465, useSSL: true)
    public static let iCloud = SMTPServerInfo(host: "smtp.mail.me.com", port: 587, useSSL: false)
}

// MARK: - SMTP Error

/// SMTP-related errors
public enum SMTPError: Error, LocalizedError, Sendable {
    case connectionFailed(String)
    case connectionTimeout
    case sslError(String)
    case invalidResponse(SMTPResponse)
    case authenticationFailed(String)
    case authenticationRequired
    case notConnected
    case messageSendFailed(String)
    case recipientRejected(String)
    case serverError(Int, String)
    case encodingError(String)
    case invalidEmailAddress(String)
    case networkError(String)
    case cancelled
    
    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return "Connection failed: \(message)"
        case .connectionTimeout:
            return "Connection timed out"
        case .sslError(let message):
            return "SSL/TLS error: \(message)"
        case .invalidResponse(let response):
            return "Invalid response: \(response.code) - \(response.combinedMessage)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .authenticationRequired:
            return "Authentication required"
        case .notConnected:
            return "Not connected to server"
        case .messageSendFailed(let message):
            return "Failed to send message: \(message)"
        case .recipientRejected(let address):
            return "Recipient rejected: \(address)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .encodingError(let message):
            return "Encoding error: \(message)"
        case .invalidEmailAddress(let address):
            return "Invalid email address: \(address)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .cancelled:
            return "Operation cancelled"
        }
    }
}
