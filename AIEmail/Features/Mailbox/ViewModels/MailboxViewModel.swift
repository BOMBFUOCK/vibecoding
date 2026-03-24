import Foundation

@Observable
class MailboxViewModel {
    var emails: [EmailRecord] = []
    var isLoading: Bool = false
    var selectedEmail: EmailRecord?
    var errorMessage: String?
    var currentFolder: Folder?
    var searchText: String = ""
    
    private let mailDatabase: MailDatabase
    
    var filteredEmails: [EmailRecord] {
        if searchText.isEmpty {
            return emails
        }
        return emails.filter { email in
            email.subject?.localizedCaseInsensitiveContains(searchText) == true ||
            email.from.localizedCaseInsensitiveContains(searchText) ||
            (email.preview?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }
    
    var unreadCount: Int {
        emails.filter { !$0.isRead }.count
    }
    
    init(mailDatabase: MailDatabase = MailDatabase()) {
        self.mailDatabase = mailDatabase
    }
    
    func loadEmails() async {
        isLoading = true
        errorMessage = nil
        
        do {
            let folderID = currentFolder?.id ?? "inbox"
            emails = try mailDatabase.getEmails(folderID: folderID, limit: 50, offset: 0)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isLoading = false
    }
    
    func refreshEmails() async {
        await loadEmails()
    }
    
    func markAsRead(_ email: EmailRecord) async {
        guard let index = emails.firstIndex(where: { $0.id == email.id }) else { return }
        
        var updatedEmail = email
        updatedEmail.isRead = true
        
        do {
            try mailDatabase.updateEmail(updatedEmail)
            emails[index] = updatedEmail
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func markAsUnread(_ email: EmailRecord) async {
        guard let index = emails.firstIndex(where: { $0.id == email.id }) else { return }
        
        var updatedEmail = email
        updatedEmail.isRead = false
        
        do {
            try mailDatabase.updateEmail(updatedEmail)
            emails[index] = updatedEmail
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func deleteEmail(_ email: EmailRecord) async {
        do {
            try mailDatabase.deleteEmail(id: email.id)
            emails.removeAll { $0.id == email.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func moveToFolder(_ email: EmailRecord, folder: Folder) async {
        var updatedEmail = email
        updatedEmail.isDeleted = true
        
        do {
            try mailDatabase.updateEmail(updatedEmail)
            emails.removeAll { $0.id == email.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func selectFolder(_ folder: Folder) {
        currentFolder = folder
        Task {
            await loadEmails()
        }
    }
}
