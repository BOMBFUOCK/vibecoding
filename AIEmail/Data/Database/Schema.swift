import Foundation

// MARK: - Email Provider

enum EmailProvider: String, Sendable, Codable, CaseIterable {
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
}

// MARK: - Account Model

struct Account: Sendable, Codable, Identifiable {
    let id: String
    let email: String
    let displayName: String?
    let provider: EmailProvider
    let imapHost: String
    let imapPort: Int
    let imapUseSSL: Bool
    let smtpHost: String
    let smtpPort: Int
    let smtpUseSSL: Bool
    var lastSyncedAt: Date?
    let createdAt: Date
    var updatedAt: Date
    
    init(
        id: String = UUID().uuidString,
        email: String,
        displayName: String? = nil,
        provider: EmailProvider,
        imapHost: String,
        imapPort: Int,
        imapUseSSL: Bool = true,
        smtpHost: String,
        smtpPort: Int,
        smtpUseSSL: Bool = true,
        lastSyncedAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.email = email
        self.displayName = displayName
        self.provider = provider
        self.imapHost = imapHost
        self.imapPort = imapPort
        self.imapUseSSL = imapUseSSL
        self.smtpHost = smtpHost
        self.smtpPort = smtpPort
        self.smtpUseSSL = smtpUseSSL
        self.lastSyncedAt = lastSyncedAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

// MARK: - Folder Model

struct Folder: Sendable, Codable, Identifiable {
    let id: String
    let accountID: String
    let name: String
    let path: String
    var unreadCount: Int
    var totalCount: Int
    let isSync: Bool
    
    init(
        id: String = UUID().uuidString,
        accountID: String,
        name: String,
        path: String,
        unreadCount: Int = 0,
        totalCount: Int = 0,
        isSync: Bool = true
    ) {
        self.id = id
        self.accountID = accountID
        self.name = name
        self.path = path
        self.unreadCount = unreadCount
        self.totalCount = totalCount
        self.isSync = isSync
    }
}

// MARK: - Email Model

struct EmailRecord: Sendable, Codable, Identifiable {
    let id: String
    let accountID: String
    let folderID: String
    let messageID: String
    let from: String
    let fromName: String?
    let to: [String]
    let cc: [String]?
    let subject: String?
    let preview: String?
    let textBody: String?
    let htmlBody: String?
    let hasAttachments: Bool
    var isRead: Bool
    var isStarred: Bool
    var isDeleted: Bool
    let receivedAt: Date
    let syncedAt: Date
    var aiSummary: String?
    var aiSummaryGeneratedAt: Date?
    
    init(
        id: String = UUID().uuidString,
        accountID: String,
        folderID: String,
        messageID: String,
        from: String,
        fromName: String? = nil,
        to: [String],
        cc: [String]? = nil,
        subject: String? = nil,
        preview: String? = nil,
        textBody: String? = nil,
        htmlBody: String? = nil,
        hasAttachments: Bool = false,
        isRead: Bool = false,
        isStarred: Bool = false,
        isDeleted: Bool = false,
        receivedAt: Date,
        syncedAt: Date = Date(),
        aiSummary: String? = nil,
        aiSummaryGeneratedAt: Date? = nil
    ) {
        self.id = id
        self.accountID = accountID
        self.folderID = folderID
        self.messageID = messageID
        self.from = from
        self.fromName = fromName
        self.to = to
        self.cc = cc
        self.subject = subject
        self.preview = preview
        self.textBody = textBody
        self.htmlBody = htmlBody
        self.hasAttachments = hasAttachments
        self.isRead = isRead
        self.isStarred = isStarred
        self.isDeleted = isDeleted
        self.receivedAt = receivedAt
        self.syncedAt = syncedAt
        self.aiSummary = aiSummary
        self.aiSummaryGeneratedAt = aiSummaryGeneratedAt
    }
    
    /// Generate preview from text body (first 200 chars)
    static func generatePreview(from text: String?, maxLength: Int = 200) -> String? {
        guard let text = text, !text.isEmpty else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count <= maxLength {
            return trimmed
        }
        let index = trimmed.index(trimmed.startIndex, offsetBy: maxLength)
        return String(trimmed[..<index]) + "..."
    }
}

// MARK: - Attachment Model

struct Attachment: Sendable, Codable, Identifiable {
    let id: String
    let emailID: String
    let partID: String
    let filename: String
    let mimeType: String
    let size: Int
    let isInline: Bool
    var localPath: String?
    
    init(
        id: String = UUID().uuidString,
        emailID: String,
        partID: String,
        filename: String,
        mimeType: String,
        size: Int,
        isInline: Bool = false,
        localPath: String? = nil
    ) {
        self.id = id
        self.emailID = emailID
        self.partID = partID
        self.filename = filename
        self.mimeType = mimeType
        self.size = size
        self.isInline = isInline
        self.localPath = localPath
    }
}

// MARK: - AI Processing Status

enum AIProcessingStatus: String, Sendable, Codable {
    case pending
    case processing
    case completed
    case failed
}

// MARK: - AI Processing Model

struct AIProcessing: Sendable, Codable, Identifiable {
    let id: String
    let emailID: String
    var status: AIProcessingStatus
    var summary: String?
    var replyDraft: String?
    var actionItems: [String]?
    var errorMessage: String?
    var processedAt: Date?
    
    init(
        id: String = UUID().uuidString,
        emailID: String,
        status: AIProcessingStatus = .pending,
        summary: String? = nil,
        replyDraft: String? = nil,
        actionItems: [String]? = nil,
        errorMessage: String? = nil,
        processedAt: Date? = nil
    ) {
        self.id = id
        self.emailID = emailID
        self.status = status
        self.summary = summary
        self.replyDraft = replyDraft
        self.actionItems = actionItems
        self.errorMessage = errorMessage
        self.processedAt = processedAt
    }
}

// MARK: - Schema Version

enum SchemaVersion: Int {
    case initial = 1
    static let current = 1
}

// MARK: - Database Schema

enum Schema {
    
    // MARK: - Schema SQL Statements
    
    static let createAccountsTable = """
        CREATE TABLE IF NOT EXISTS accounts (
            id TEXT PRIMARY KEY,
            email TEXT NOT NULL UNIQUE,
            display_name TEXT,
            provider TEXT NOT NULL,
            imap_host TEXT NOT NULL,
            imap_port INTEGER NOT NULL,
            imap_use_ssl INTEGER NOT NULL DEFAULT 1,
            smtp_host TEXT NOT NULL,
            smtp_port INTEGER NOT NULL,
            smtp_use_ssl INTEGER NOT NULL DEFAULT 1,
            last_synced_at INTEGER,
            created_at INTEGER NOT NULL,
            updated_at INTEGER NOT NULL
        );
    """
    
    static let createFoldersTable = """
        CREATE TABLE IF NOT EXISTS folders (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            name TEXT NOT NULL,
            path TEXT NOT NULL,
            unread_count INTEGER NOT NULL DEFAULT 0,
            total_count INTEGER NOT NULL DEFAULT 0,
            is_sync INTEGER NOT NULL DEFAULT 1,
            FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
        );
    """
    
    static let createEmailsTable = """
        CREATE TABLE IF NOT EXISTS emails (
            id TEXT PRIMARY KEY,
            account_id TEXT NOT NULL,
            folder_id TEXT NOT NULL,
            message_id TEXT NOT NULL,
            from_address TEXT NOT NULL,
            from_name TEXT,
            to_addresses TEXT NOT NULL,
            cc_addresses TEXT,
            subject TEXT,
            preview TEXT,
            text_body TEXT,
            html_body TEXT,
            has_attachments INTEGER NOT NULL DEFAULT 0,
            is_read INTEGER NOT NULL DEFAULT 0,
            is_starred INTEGER NOT NULL DEFAULT 0,
            is_deleted INTEGER NOT NULL DEFAULT 0,
            received_at INTEGER NOT NULL,
            synced_at INTEGER NOT NULL,
            ai_summary TEXT,
            ai_summary_generated_at INTEGER,
            FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
            FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
        );
    """
    
    static let createAttachmentsTable = """
        CREATE TABLE IF NOT EXISTS attachments (
            id TEXT PRIMARY KEY,
            email_id TEXT NOT NULL,
            part_id TEXT NOT NULL,
            filename TEXT NOT NULL,
            mime_type TEXT NOT NULL,
            size INTEGER NOT NULL,
            is_inline INTEGER NOT NULL DEFAULT 0,
            local_path TEXT,
            FOREIGN KEY (email_id) REFERENCES emails(id) ON DELETE CASCADE
        );
    """
    
    static let createFTS5Table = """
        CREATE VIRTUAL TABLE IF NOT EXISTS emails_fts USING fts5(
            subject,
            text_body,
            from_address,
            to_addresses,
            content='emails',
            content_rowid='rowid'
        );
    """
    
    static let createAIProcessingTable = """
        CREATE TABLE IF NOT EXISTS ai_processing (
            id TEXT PRIMARY KEY,
            email_id TEXT NOT NULL UNIQUE,
            status TEXT NOT NULL DEFAULT 'pending',
            summary TEXT,
            reply_draft TEXT,
            action_items TEXT,
            error_message TEXT,
            processed_at INTEGER,
            FOREIGN KEY (email_id) REFERENCES emails(id) ON DELETE CASCADE
        );
    """
    
    // MARK: - Indexes
    
    static let createIndexes = [
        "CREATE INDEX IF NOT EXISTS idx_folders_account_id ON folders(account_id);",
        "CREATE INDEX IF NOT EXISTS idx_emails_account_id ON emails(account_id);",
        "CREATE INDEX IF NOT EXISTS idx_emails_folder_id ON emails(folder_id);",
        "CREATE INDEX IF NOT EXISTS idx_emails_received_at ON emails(received_at DESC);",
        "CREATE INDEX IF NOT EXISTS idx_emails_message_id ON emails(message_id);",
        "CREATE INDEX IF NOT EXISTS idx_attachments_email_id ON attachments(email_id);",
        "CREATE INDEX IF NOT EXISTS idx_ai_processing_email_id ON ai_processing(email_id);"
    ]
    
    // MARK: - FTS Triggers
    
    static let createFTSTriggers = [
        """
        CREATE TRIGGER IF NOT EXISTS emails_ai_insert AFTER INSERT ON emails BEGIN
            INSERT INTO emails_fts(rowid, subject, text_body, from_address, to_addresses)
            VALUES (new.rowid, new.subject, new.text_body, new.from_address, new.to_addresses);
        END;
        """,
        """
        CREATE TRIGGER IF NOT EXISTS emails_ai_update AFTER UPDATE ON emails BEGIN
            INSERT INTO emails_fts(emails_fts, rowid, subject, text_body, from_address, to_addresses)
            VALUES ('delete', old.rowid, old.subject, old.text_body, old.from_address, old.to_addresses);
            INSERT INTO emails_fts(rowid, subject, text_body, from_address, to_addresses)
            VALUES (new.rowid, new.subject, new.text_body, new.from_address, new.to_addresses);
        END;
        """,
        """
        CREATE TRIGGER IF NOT EXISTS emails_ai_delete AFTER DELETE ON emails BEGIN
            INSERT INTO emails_fts(emails_fts, rowid, subject, text_body, from_address, to_addresses)
            VALUES ('delete', old.rowid, old.subject, old.text_body, old.from_address, old.to_addresses);
        END;
        """
    ]
    
    // MARK: - Migration SQL
    
    static func migrationSQL(from oldVersion: SchemaVersion, to newVersion: SchemaVersion) -> [String] {
        // Currently at initial version, no migrations needed
        return []
    }
}

// MARK: - Database Errors

enum DatabaseError: Error, LocalizedError {
    case notInitialized
    case alreadyInitialized
    case executionFailed(String)
    case notFound
    case duplicateEntry
    case invalidData(String)
    case migrationFailed(String)
    case ftsError(String)
    
    var errorDescription: String? {
        switch self {
        case .notInitialized:
            return "Database not initialized"
        case .alreadyInitialized:
            return "Database already initialized"
        case .executionFailed(let msg):
            return "SQL execution failed: \(msg)"
        case .notFound:
            return "Record not found"
        case .duplicateEntry:
            return "Duplicate entry"
        case .invalidData(let msg):
            return "Invalid data: \(msg)"
        case .migrationFailed(let msg):
            return "Migration failed: \(msg)"
        case .ftsError(let msg):
            return "FTS error: \(msg)"
        }
    }
}
