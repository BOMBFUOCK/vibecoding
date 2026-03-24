import Foundation

enum EmailProvider: String, Codable, CaseIterable {
    case gmail
    case outlook
    case qq
    case netease
    case other
    
    var displayName: String {
        switch self {
        case .gmail: return "Gmail"
        case .outlook: return "Outlook"
        case .qq: return "QQ Mail"
        case .netease: return "163 Mail"
        case .other: return "Other"
        }
    }
    
    var imapHost: String {
        switch self {
        case .gmail: return "imap.gmail.com"
        case .outlook: return "outlook.office365.com"
        case .qq: return "imap.qq.com"
        case .netease: return "imap.163.com"
        case .other: return ""
        }
    }
    
    var imapPort: Int { 993 }
    var smtpHost: String {
        switch self {
        case .gmail: return "smtp.gmail.com"
        case .outlook: return "smtp.office365.com"
        case .qq: return "smtp.qq.com"
        case .netease: return "smtp.163.com"
        case .other: return ""
        }
    }
    var smtpPort: Int { 587 }
}

struct AccountInfo: Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String?
    let provider: EmailProvider
    let imapHost: String
    let imapPort: Int
    let smtpHost: String
    let smtpPort: Int
    var lastSyncedAt: Date?
    var isConnected: Bool
    
    init(
        id: String = UUID().uuidString,
        email: String,
        displayName: String? = nil,
        provider: EmailProvider,
        imapHost: String,
        imapPort: Int,
        smtpHost: String,
        smtpPort: Int,
        lastSyncedAt: Date? = nil,
        isConnected: Bool = false
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.provider = provider
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.lastSyncedAt = lastSyncedAt
        self.isConnected = isConnected
    }
}

struct AccountCredentials: Codable {
    let email: String
    let password: String
    
    init(email: String, password: String) {
        self.email = email
        self.password = password
    }
}

struct EmailInfo: Codable, Identifiable {
    let id: String
    let messageID: String
    let from: String
    let fromName: String?
    let to: [String]
    let cc: [String]?
    let subject: String?
    let preview: String?
    let textBody: String?
    let hasAttachments: Bool
    var isRead: Bool
    var isStarred: Bool
    let date: Date
    
    var displayText: String {
        if let text = textBody, !text.isEmpty {
            return text
        }
        return preview ?? ""
    }
}

struct EmailDetail: Codable {
    let id: String
    let messageID: String
    let from: String
    let fromName: String?
    let to: [String]
    let cc: [String]?
    let subject: String?
    let textBody: String?
    let htmlBody: String?
    let attachments: [AttachmentInfo]
    var isRead: Bool
    let date: Date
    let hasAttachments: Bool
    
    init(from info: EmailInfo, textBody: String? = nil, htmlBody: String? = nil, attachments: [AttachmentInfo] = []) {
        self.id = info.id
        self.messageID = info.messageID
        self.from = info.from
        self.fromName = info.fromName
        self.to = info.to
        self.cc = info.cc
        self.subject = info.subject
        self.textBody = textBody ?? info.textBody
        self.htmlBody = htmlBody
        self.attachments = attachments
        self.isRead = info.isRead
        self.date = info.date
        self.hasAttachments = info.hasAttachments
    }
}

struct AttachmentInfo: Codable, Identifiable {
    let id: String
    let filename: String
    let mimeType: String
    let size: Int
    let isInline: Bool
    
    init(id: String = UUID().uuidString, filename: String, mimeType: String, size: Int, isInline: Bool = false) {
        self.id = id
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.isInline = isInline
    }
}

struct SearchResult: Codable, Identifiable {
    let id: String
    let emailID: String
    let subject: String?
    let snippet: String
    let from: String
    let score: Float
    let matchedFields: [String]
    
    init(emailID: String, subject: String?, snippet: String, from: String, score: Float, matchedFields: [String] = []) {
        self.id = emailID
        self.emailID = emailID
        self.subject = subject
        self.snippet = snippet
        self.from = from
        self.score = score
        self.matchedFields = matchedFields
    }
}

enum SearchMode: String, CaseIterable {
    case fulltext
    case semantic
    case hybrid
    
    var description: String {
        switch self {
        case .fulltext: return "Full-text search"
        case .semantic: return "Semantic search (fuzzy)"
        case .hybrid: return "Hybrid search"
        }
    }
}

enum ReplyTone: String, CaseIterable {
    case professional
    case casual
    case brief
    
    var displayName: String {
        switch self {
        case .professional: return "Professional"
        case .casual: return "Casual"
        case .brief: return "Brief"
        }
    }
}

struct FolderInfo: Codable, Identifiable {
    let id: String
    let name: String
    let path: String
    var unreadCount: Int
    var totalCount: Int
    
    init(id: String = UUID().uuidString, name: String, path: String, unreadCount: Int = 0, totalCount: Int = 0) {
        self.id = id
        self.name = name
        self.path = path
        self.unreadCount = unreadCount
        self.totalCount = totalCount
    }
}
