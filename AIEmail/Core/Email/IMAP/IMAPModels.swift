import Foundation

// MARK: - IMAP Server Configuration

struct IMAPServerConfig {
    let host: String
    let port: Int
    let useSSL: Bool
    
    static let gmail = IMAPServerConfig(host: "imap.gmail.com", port: 993, useSSL: true)
    static let outlook = IMAPServerConfig(host: "outlook.office365.com", port: 993, useSSL: true)
    static let qq = IMAPServerConfig(host: "imap.qq.com", port: 993, useSSL: true)
    static let netEase = IMAPServerConfig(host: "imap.163.com", port: 993, useSSL: true)
}

// MARK: - Message Flags

enum MessageFlag: String, Sendable {
    case seen = "\\Seen"
    case answered = "\\Answered"
    case flagged = "\\Flagged"
    case deleted = "\\Deleted"
    case draft = "\\Draft"
    case recent = "\\Recent"
    
    var imapString: String {
        return rawValue
    }
}

// MARK: - Folder Info

struct FolderInfo: Sendable {
    let name: String
    let totalMessages: Int
    let recentMessages: Int
    let unseenMessages: Int
    
    init(name: String, totalMessages: Int = 0, recentMessages: Int = 0, unseenMessages: Int = 0) {
        self.name = name
        self.totalMessages = totalMessages
        self.recentMessages = recentMessages
        self.unseenMessages = unseenMessages
    }
}

// MARK: - Message ID

struct MessageID: Sendable, Hashable {
    let id: String
    
    init(_ id: String) {
        self.id = id
    }
}

// MARK: - Email Header

struct EmailHeader: Sendable {
    let messageID: String
    let from: String
    let subject: String
    let date: Date
    let to: String?
    let cc: String?
    let isRead: Bool
    let isStarred: Bool
    
    init(
        messageID: String,
        from: String,
        subject: String,
        date: Date,
        to: String? = nil,
        cc: String? = nil,
        isRead: Bool = false,
        isStarred: Bool = false
    ) {
        self.messageID = messageID
        self.from = from
        self.subject = subject
        self.date = date
        self.to = to
        self.cc = cc
        self.isRead = isRead
        self.isStarred = isStarred
    }
}

// MARK: - Attachment Info

struct AttachmentInfo: Sendable {
    let partID: String
    let filename: String
    let mimeType: String
    let size: Int
    let isInline: Bool
    
    init(
        partID: String,
        filename: String,
        mimeType: String,
        size: Int,
        isInline: Bool = false
    ) {
        self.partID = partID
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.isInline = isInline
    }
}

// MARK: - Email Body

struct EmailBody: Sendable {
    let messageID: String
    let textBody: String?
    let htmlBody: String?
    let attachments: [AttachmentInfo]
    let inReplyTo: String?
    let references: [String]?
    
    init(
        messageID: String,
        textBody: String? = nil,
        htmlBody: String? = nil,
        attachments: [AttachmentInfo] = [],
        inReplyTo: String? = nil,
        references: [String]? = nil
    ) {
        self.messageID = messageID
        self.textBody = textBody
        self.htmlBody = htmlBody
        self.attachments = attachments
        self.inReplyTo = inReplyTo
        self.references = references
    }
}

enum IMAPResponseType: Sendable {
    case ok
    case no
    case bad
    case bye
    case untagged(ResponseData)
    indirect case tagged(tag: String, response: IMAPResponseType)
}

enum ResponseData: Sendable {
    case flags([String])
    case exists(Int)
    case recent(Int)
    case list([[String: String]])
    case search([String])
    case fetch([String: Any])
    case status([String: Any])
    case raw(String)
}

// MARK: - IMAP Error

enum IMAPError: Error, LocalizedError {
    case connectionFailed(String)
    case authenticationFailed(String)
    case notConnected
    case invalidResponse(String)
    case commandFailed(String)
    case timeout
    case sslError(String)
    case parseError(String)
    case folderNotFound(String)
    case messageNotFound(String)
    
    var errorDescription: String? {
        switch self {
        case .connectionFailed(let msg):
            return "Connection failed: \(msg)"
        case .authenticationFailed(let msg):
            return "Authentication failed: \(msg)"
        case .notConnected:
            return "Not connected to server"
        case .invalidResponse(let msg):
            return "Invalid response: \(msg)"
        case .commandFailed(let msg):
            return "Command failed: \(msg)"
        case .timeout:
            return "Connection timeout"
        case .sslError(let msg):
            return "SSL error: \(msg)"
        case .parseError(let msg):
            return "Parse error: \(msg)"
        case .folderNotFound(let folder):
            return "Folder not found: \(folder)"
        case .messageNotFound(let msg):
            return "Message not found: \(msg)"
        }
    }
}

// MARK: - Connection State

enum ConnectionState: Sendable {
    case disconnected
    case connecting
    case connected
    case authenticated
    case selected(String)
}
