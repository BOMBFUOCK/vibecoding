import Foundation

final class MailDatabase {
    
    static let shared = MailDatabase()
    
    private var accounts: [Account] = []
    private var folders: [Folder] = []
    private var emails: [EmailRecord] = []
    
    init() {}
    
    // MARK: - Account Operations
    
    func insertAccount(_ account: Account) throws {
        accounts.append(account)
    }
    
    func updateAccount(_ account: Account) throws {
        if let idx = accounts.firstIndex(where: { $0.id == account.id }) {
            accounts[idx] = account
        }
    }
    
    func deleteAccount(id: String) throws {
        accounts.removeAll { $0.id == id }
        folders.removeAll { $0.accountID == id }
        emails.removeAll { $0.accountID == id }
    }
    
    func getAccount(id: String) throws -> Account? {
        return accounts.first { $0.id == id }
    }
    
    func getAllAccounts() throws -> [Account] {
        return accounts
    }
    
    // MARK: - Folder Operations
    
    func insertFolder(_ folder: Folder) throws {
        folders.append(folder)
    }
    
    func updateFolder(_ folder: Folder) throws {
        if let idx = folders.firstIndex(where: { $0.id == folder.id }) {
            folders[idx] = folder
        }
    }
    
    func deleteFolder(id: String) throws {
        folders.removeAll { $0.id == id }
    }
    
    func getFolders(accountID: String) throws -> [Folder] {
        return folders.filter { $0.accountID == accountID }
    }
    
    // MARK: - Email Operations
    
    func insertEmail(_ email: EmailRecord) throws {
        emails.append(email)
    }
    
    func updateEmail(_ email: EmailRecord) throws {
        if let idx = emails.firstIndex(where: { $0.id == email.id }) {
            emails[idx] = email
        }
    }
    
    func deleteEmail(id: String) throws {
        emails.removeAll { $0.id == id }
    }
    
    func getEmail(id: String) throws -> EmailRecord? {
        return emails.first { $0.id == id }
    }
    
    func getEmails(folderID: String, limit: Int = 50, offset: Int = 0) throws -> [EmailRecord] {
        let filtered = emails.filter { $0.folderID == folderID }
            .sorted { $0.receivedAt > $1.receivedAt }
        let end = min(offset + limit, filtered.count)
        guard offset < filtered.count else { return [] }
        return Array(filtered[offset..<end])
    }
    
    func getUnreadEmails(folderID: String) throws -> [EmailRecord] {
        return emails.filter { $0.folderID == folderID && !$0.isRead }
    }
    
    func searchEmails(query: String, limit: Int = 50) throws -> [EmailRecord] {
        let lowercased = query.lowercased()
        return emails.filter { email in
            (email.subject?.lowercased().contains(lowercased) ?? false) ||
            (email.textBody?.lowercased().contains(lowercased) ?? false) ||
            email.from.lowercased().contains(lowercased)
        }.prefix(limit).map { $0 }
    }
    
    // MARK: - Attachment Operations
    
    func insertAttachment(_ attachment: Attachment) throws {
    }
    
    func getAttachments(emailID: String) throws -> [Attachment] {
        return []
    }
    
    // MARK: - FTS Operations
    
    func rebuildFTSIndex() throws {
    }
    
    func updateFTSDocument(emailID: String, subject: String, body: String, from: String, to: String) throws {
    }
    
    func deleteFTSDocument(emailID: String) throws {
    }
    
    func searchFTS(query: String, limit: Int = 50) throws -> [String] {
        return []
    }
    
    // MARK: - AI Processing
    
    func saveAISummary(emailID: String, summary: String) throws {
        if let idx = emails.firstIndex(where: { $0.id == emailID }) {
            emails[idx].aiSummary = summary
        }
    }
    
    func saveReplyDraft(emailID: String, draft: String) throws {
    }
    
    func getAISummary(emailID: String) throws -> String? {
        return emails.first { $0.id == emailID }?.aiSummary
    }
    
    func getReplyDraft(emailID: String) throws -> String? {
        return nil
    }
}
