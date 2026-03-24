import Foundation
import SQLite3

final class DatabaseService {
    static let shared = DatabaseService()
    
    private var db: OpaquePointer?
    private let dbQueue = DispatchQueue(label: "com.aiemailcli.database", qos: .userInitiated)
    
    private init() {}
    
    func initialize() throws {
        try dbQueue.sync {
            if db != nil { return }
            
            let fileManager = FileManager.default
            let appSupport = try fileManager.url(
                for: .applicationSupportDirectory,
                in: .userDomainMask,
                appropriateFor: nil,
                create: true
            )
            
            let dbDir = appSupport.appendingPathComponent("AIEmailCLI", isDirectory: true)
            try fileManager.createDirectory(at: dbDir, withIntermediateDirectories: true)
            
            let dbPath = dbDir.appendingPathComponent("aiemailcli.sqlite3").path
            
            var tempDb: OpaquePointer?
            let result = sqlite3_open(dbPath, &tempDb)
            
            guard result == SQLITE_OK else {
                let errorMsg = String(cString: sqlite3_errmsg(tempDb))
                sqlite3_close(tempDb)
                throw DatabaseServiceError.executionFailed("Failed to open database: \(errorMsg)")
            }
            
            db = tempDb
            
            try createSchema()
        }
    }
    
    func close() {
        dbQueue.sync {
            guard let db = db else { return }
            sqlite3_close(db)
            self.db = nil
        }
    }
    
    private func createSchema() throws {
        let statements = [
            """
            CREATE TABLE IF NOT EXISTS accounts (
                id TEXT PRIMARY KEY,
                email TEXT NOT NULL UNIQUE,
                display_name TEXT,
                provider TEXT NOT NULL,
                imap_host TEXT NOT NULL,
                imap_port INTEGER NOT NULL,
                smtp_host TEXT NOT NULL,
                smtp_port INTEGER NOT NULL,
                last_synced_at INTEGER,
                created_at INTEGER NOT NULL,
                updated_at INTEGER NOT NULL
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS credentials (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL UNIQUE,
                password TEXT NOT NULL,
                FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS folders (
                id TEXT PRIMARY KEY,
                account_id TEXT NOT NULL,
                name TEXT NOT NULL,
                path TEXT NOT NULL,
                unread_count INTEGER NOT NULL DEFAULT 0,
                total_count INTEGER NOT NULL DEFAULT 0,
                FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE
            );
            """,
            """
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
                has_attachments INTEGER NOT NULL DEFAULT 0,
                is_read INTEGER NOT NULL DEFAULT 0,
                is_starred INTEGER NOT NULL DEFAULT 0,
                received_at INTEGER NOT NULL,
                synced_at INTEGER NOT NULL,
                ai_summary TEXT,
                ai_summary_generated_at INTEGER,
                FOREIGN KEY (account_id) REFERENCES accounts(id) ON DELETE CASCADE,
                FOREIGN KEY (folder_id) REFERENCES folders(id) ON DELETE CASCADE
            );
            """,
            """
            CREATE TABLE IF NOT EXISTS ai_config (
                id INTEGER PRIMARY KEY CHECK (id = 1),
                api_key TEXT,
                updated_at INTEGER NOT NULL
            );
            """
        ]
        
        for sql in statements {
            try execute(sql)
        }
    }
    
    private func execute(_ sql: String) throws {
        guard let db = db else {
            throw DatabaseServiceError.notInitialized
        }
        
        var errorMsg: UnsafeMutablePointer<CChar>?
        let result = sqlite3_exec(db, sql, nil, nil, &errorMsg)
        
        if result != SQLITE_OK {
            let error = errorMsg != nil ? String(cString: errorMsg!) : "Unknown error"
            sqlite3_free(errorMsg)
            throw DatabaseServiceError.executionFailed(error)
        }
    }
    
    func saveAccount(_ account: AccountInfo, password: String) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = """
                INSERT OR REPLACE INTO accounts (
                    id, email, display_name, provider, imap_host, imap_port,
                    smtp_host, smtp_port, last_synced_at, created_at, updated_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            sqlite3_bind_text(stmt, 1, account.id.cString(using: .utf8))
            sqlite3_bind_text(stmt, 2, account.email.cString(using: .utf8))
            sqlite3_bind_text(stmt, 3, account.displayName?.cString(using: .utf8))
            sqlite3_bind_text(stmt, 4, account.provider.rawValue.cString(using: .utf8))
            sqlite3_bind_text(stmt, 5, account.imapHost.cString(using: .utf8))
            sqlite3_bind_int(stmt, 6, Int32(account.imapPort))
            sqlite3_bind_text(stmt, 7, account.smtpHost.cString(using: .utf8))
            sqlite3_bind_int(stmt, 8, Int32(account.smtpPort))
            
            if let lastSynced = account.lastSyncedAt {
                sqlite3_bind_int64(stmt, 9, Int64(lastSynced.timeIntervalSince1970))
            } else {
                sqlite3_bind_null(stmt, 9)
            }
            
            sqlite3_bind_int64(stmt, 10, Int64(Date().timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 11, Int64(Date().timeIntervalSince1970))
            
            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE else {
                throw DatabaseServiceError.executionFailed("Save account failed: \(result)")
            }
            
            let credSql = """
                INSERT OR REPLACE INTO credentials (id, account_id, password)
                VALUES (?, ?, ?)
            """
            let credStmt = try prepareStatement(credSql)
            defer { finalizeStatement(credStmt) }
            
            sqlite3_bind_text(credStmt, 1, UUID().uuidString.cString(using: .utf8))
            sqlite3_bind_text(credStmt, 2, account.id.cString(using: .utf8))
            sqlite3_bind_text(credStmt, 3, password.cString(using: .utf8))
            
            let credResult = sqlite3_step(credStmt)
            guard credResult == SQLITE_DONE else {
                throw DatabaseServiceError.executionFailed("Save credentials failed: \(credResult)")
            }
        }
    }
    
    func getAllAccounts() throws -> [AccountInfo] {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = "SELECT * FROM accounts ORDER BY created_at DESC"
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            var accounts: [AccountInfo] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                accounts.append(parseAccount(from: stmt))
            }
            return accounts
        }
    }
    
    func getAccount(byEmail email: String) throws -> AccountInfo? {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = "SELECT * FROM accounts WHERE email = ?"
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            sqlite3_bind_text(stmt, 1, email.cString(using: .utf8))
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return parseAccount(from: stmt)
            }
            return nil
        }
    }
    
    func getAccount(byID id: String) throws -> AccountInfo? {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = "SELECT * FROM accounts WHERE id = ?"
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            sqlite3_bind_text(stmt, 1, id.cString(using: .utf8))
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return parseAccount(from: stmt)
            }
            return nil
        }
    }
    
    func getPassword(forAccountID accountID: String) throws -> String? {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = "SELECT password FROM credentials WHERE account_id = ?"
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            sqlite3_bind_text(stmt, 1, accountID.cString(using: .utf8))
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return String(cString: sqlite3_column_text(stmt, 0))
            }
            return nil
        }
    }
    
    func deleteAccount(byEmail email: String) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            if let account = try getAccount(byEmail: email) {
                let sql = "DELETE FROM accounts WHERE id = ?"
                let stmt = try prepareStatement(sql)
                defer { finalizeStatement(stmt) }
                
                sqlite3_bind_text(stmt, 1, account.id.cString(using: .utf8))
                
                let result = sqlite3_step(stmt)
                guard result == SQLITE_DONE else {
                    throw DatabaseServiceError.executionFailed("Delete account failed: \(result)")
                }
            }
        }
    }
    
    func saveEmail(_ email: EmailInfo, accountID: String, folderID: String) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = """
                INSERT OR REPLACE INTO emails (
                    id, account_id, folder_id, message_id, from_address, from_name,
                    to_addresses, cc_addresses, subject, preview, text_body,
                    has_attachments, is_read, is_starred, received_at, synced_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """
            
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            sqlite3_bind_text(stmt, 1, email.id.cString(using: .utf8))
            sqlite3_bind_text(stmt, 2, accountID.cString(using: .utf8))
            sqlite3_bind_text(stmt, 3, folderID.cString(using: .utf8))
            sqlite3_bind_text(stmt, 4, email.messageID.cString(using: .utf8))
            sqlite3_bind_text(stmt, 5, email.from.cString(using: .utf8))
            sqlite3_bind_text(stmt, 6, email.fromName?.cString(using: .utf8))
            sqlite3_bind_text(stmt, 7, email.to.joined(separator: ",").cString(using: .utf8))
            sqlite3_bind_text(stmt, 8, email.cc?.joined(separator: ",").cString(using: .utf8))
            sqlite3_bind_text(stmt, 9, email.subject?.cString(using: .utf8))
            sqlite3_bind_text(stmt, 10, email.preview?.cString(using: .utf8))
            sqlite3_bind_text(stmt, 11, email.textBody?.cString(using: .utf8))
            sqlite3_bind_int(stmt, 12, email.hasAttachments ? 1 : 0)
            sqlite3_bind_int(stmt, 13, email.isRead ? 1 : 0)
            sqlite3_bind_int(stmt, 14, email.isStarred ? 1 : 0)
            sqlite3_bind_int64(stmt, 15, Int64(email.date.timeIntervalSince1970))
            sqlite3_bind_int64(stmt, 16, Int64(Date().timeIntervalSince1970))
            
            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE else {
                throw DatabaseServiceError.executionFailed("Save email failed: \(result)")
            }
        }
    }
    
    func getEmails(folderID: String, limit: Int = 20, offset: Int = 0) throws -> [EmailInfo] {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = """
                SELECT * FROM emails
                WHERE folder_id = ?
                ORDER BY received_at DESC
                LIMIT ? OFFSET ?
            """
            
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            sqlite3_bind_text(stmt, 1, folderID.cString(using: .utf8))
            sqlite3_bind_int(stmt, 2, Int32(limit))
            sqlite3_bind_int(stmt, 3, Int32(offset))
            
            var emails: [EmailInfo] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                emails.append(parseEmail(from: stmt))
            }
            return emails
        }
    }
    
    func getEmail(byID id: String) throws -> EmailInfo? {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = "SELECT * FROM emails WHERE id = ?"
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            sqlite3_bind_text(stmt, 1, id.cString(using: .utf8))
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return parseEmail(from: stmt)
            }
            return nil
        }
    }
    
    func saveFolder(_ folder: FolderInfo, accountID: String) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = """
                INSERT OR REPLACE INTO folders (id, account_id, name, path, unread_count, total_count)
                VALUES (?, ?, ?, ?, ?, ?)
            """
            
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            sqlite3_bind_text(stmt, 1, folder.id.cString(using: .utf8))
            sqlite3_bind_text(stmt, 2, accountID.cString(using: .utf8))
            sqlite3_bind_text(stmt, 3, folder.name.cString(using: .utf8))
            sqlite3_bind_text(stmt, 4, folder.path.cString(using: .utf8))
            sqlite3_bind_int(stmt, 5, Int32(folder.unreadCount))
            sqlite3_bind_int(stmt, 6, Int32(folder.totalCount))
            
            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE else {
                throw DatabaseServiceError.executionFailed("Save folder failed: \(result)")
            }
        }
    }
    
    func getFolders(accountID: String) throws -> [FolderInfo] {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = "SELECT * FROM folders WHERE account_id = ? ORDER BY name"
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            sqlite3_bind_text(stmt, 1, accountID.cString(using: .utf8))
            
            var folders: [FolderInfo] = []
            while sqlite3_step(stmt) == SQLITE_ROW {
                folders.append(parseFolder(from: stmt))
            }
            return folders
        }
    }
    
    func getAPIKey() throws -> String? {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = "SELECT api_key FROM ai_config WHERE id = 1"
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            if sqlite3_step(stmt) == SQLITE_ROW {
                return String(cString: sqlite3_column_text(stmt, 0))
            }
            return nil
        }
    }
    
    func saveAPIKey(_ key: String) throws {
        try dbQueue.sync {
            guard let db = db else {
                throw DatabaseServiceError.notInitialized
            }
            
            let sql = """
                INSERT OR REPLACE INTO ai_config (id, api_key, updated_at)
                VALUES (1, ?, ?)
            """
            
            let stmt = try prepareStatement(sql)
            defer { finalizeStatement(stmt) }
            
            sqlite3_bind_text(stmt, 1, key.cString(using: .utf8))
            sqlite3_bind_int64(stmt, 2, Int64(Date().timeIntervalSince1970))
            
            let result = sqlite3_step(stmt)
            guard result == SQLITE_DONE else {
                throw DatabaseServiceError.executionFailed("Save API key failed: \(result)")
            }
        }
    }
    
    private func prepareStatement(_ sql: String) throws -> OpaquePointer {
        guard let db = db else {
            throw DatabaseServiceError.notInitialized
        }
        
        var stmt: OpaquePointer?
        let result = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        
        guard result == SQLITE_OK, let statement = stmt else {
            let errorMsg = String(cString: sqlite3_errmsg(db))
            throw DatabaseServiceError.executionFailed("Prepare statement failed: \(errorMsg)")
        }
        
        return statement
    }
    
    private func finalizeStatement(_ stmt: OpaquePointer) {
        sqlite3_finalize(stmt)
    }
    
    private func parseAccount(from stmt: OpaquePointer) -> AccountInfo {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let email = String(cString: sqlite3_column_text(stmt, 1))
        let displayName = sqlite3_column_text(stmt, 2).map { String(cString: $0) }
        let providerStr = String(cString: sqlite3_column_text(stmt, 3))
        let provider = EmailProvider(rawValue: providerStr) ?? .other
        let imapHost = String(cString: sqlite3_column_text(stmt, 4))
        let imapPort = Int(sqlite3_column_int(stmt, 5))
        let smtpHost = String(cString: sqlite3_column_text(stmt, 6))
        let smtpPort = Int(sqlite3_column_int(stmt, 7))
        let lastSyncedAt = sqlite3_column_int64(stmt, 8) != 0
            ? Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 8)))
            : nil
        
        return AccountInfo(
            id: id,
            email: email,
            displayName: displayName,
            provider: provider,
            imapHost: imapHost,
            imapPort: imapPort,
            smtpHost: smtpHost,
            smtpPort: smtpPort,
            lastSyncedAt: lastSyncedAt,
            isConnected: false
        )
    }
    
    private func parseEmail(from stmt: OpaquePointer) -> EmailInfo {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let messageID = String(cString: sqlite3_column_text(stmt, 3))
        let from = String(cString: sqlite3_column_text(stmt, 4))
        let fromName = sqlite3_column_text(stmt, 5).map { String(cString: $0) }
        let toStr = String(cString: sqlite3_column_text(stmt, 6))
        let to = toStr.components(separatedBy: ",").filter { !$0.isEmpty }
        let ccStr = sqlite3_column_text(stmt, 7).map { String(cString: $0) }
        let cc = ccStr?.components(separatedBy: ",").filter { !$0.isEmpty }
        let subject = sqlite3_column_text(stmt, 8).map { String(cString: $0) }
        let preview = sqlite3_column_text(stmt, 9).map { String(cString: $0) }
        let textBody = sqlite3_column_text(stmt, 10).map { String(cString: $0) }
        let hasAttachments = sqlite3_column_int(stmt, 11) == 1
        let isRead = sqlite3_column_int(stmt, 12) == 1
        let isStarred = sqlite3_column_int(stmt, 13) == 1
        let receivedAt = Date(timeIntervalSince1970: TimeInterval(sqlite3_column_int64(stmt, 14)))
        
        return EmailInfo(
            id: id,
            messageID: messageID,
            from: from,
            fromName: fromName,
            to: to,
            cc: cc,
            subject: subject,
            preview: preview,
            textBody: textBody,
            hasAttachments: hasAttachments,
            isRead: isRead,
            isStarred: isStarred,
            date: receivedAt
        )
    }
    
    private func parseFolder(from stmt: OpaquePointer) -> FolderInfo {
        let id = String(cString: sqlite3_column_text(stmt, 0))
        let name = String(cString: sqlite3_column_text(stmt, 2))
        let path = String(cString: sqlite3_column_text(stmt, 3))
        let unreadCount = Int(sqlite3_column_int(stmt, 4))
        let totalCount = Int(sqlite3_column_int(stmt, 5))
        
        return FolderInfo(
            id: id,
            name: name,
            path: path,
            unreadCount: unreadCount,
            totalCount: totalCount
        )
    }
}

enum DatabaseServiceError: Error, LocalizedError {
    case notInitialized
    case executionFailed(String)
    case notFound
    case duplicateEntry
    
    var errorDescription: String? {
        switch self {
        case .notInitialized: return "Database not initialized"
        case .executionFailed(let msg): return "Execution failed: \(msg)"
        case .notFound: return "Record not found"
        case .duplicateEntry: return "Duplicate entry"
        }
    }
}
