import Foundation

@Observable
class MailDetailViewModel {
    var email: EmailRecord
    var aiSummary: String?
    var replyDraft: String?
    var isGeneratingSummary: Bool = false
    var isGeneratingReply: Bool = false
    var isSendingReply: Bool = false
    var errorMessage: String?
    
    private let aiCoordinator: AIServiceCoordinator
    private let mailDatabase: MailDatabase
    
    init(
        email: EmailRecord,
        aiCoordinator: AIServiceCoordinator = AIServiceCoordinator(),
        mailDatabase: MailDatabase = MailDatabase()
    ) {
        self.email = email
        self.aiCoordinator = aiCoordinator
        self.mailDatabase = mailDatabase
        self.aiSummary = email.aiSummary
    }
    
    func generateSummary() async {
        guard !isGeneratingSummary else { return }
        
        isGeneratingSummary = true
        errorMessage = nil
        
        do {
            let summary = try await aiCoordinator.summarizeOnly(email)
            aiSummary = summary
            
            try mailDatabase.saveAISummary(emailID: email.id, summary: summary)
            
            var updatedEmail = email
            updatedEmail.aiSummary = summary
            updatedEmail.aiSummaryGeneratedAt = Date()
            email = updatedEmail
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isGeneratingSummary = false
    }
    
    func generateReplyDraft() async {
        guard !isGeneratingReply else { return }
        
        isGeneratingReply = true
        errorMessage = nil
        
        do {
            let draft = try await aiCoordinator.generateReplyOnly(email, tone: .professional)
            replyDraft = draft
            
            try mailDatabase.saveReplyDraft(emailID: email.id, draft: draft)
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isGeneratingReply = false
    }
    
    func sendReply(_ content: String) async throws {
        isSendingReply = true
        errorMessage = nil
        
        do {
            var updatedEmail = email
            updatedEmail.isRead = true
            try mailDatabase.updateEmail(updatedEmail)
            email = updatedEmail
            
            isSendingReply = false
        } catch {
            isSendingReply = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func toggleStarred() async {
        var updatedEmail = email
        updatedEmail.isStarred.toggle()
        
        do {
            try mailDatabase.updateEmail(updatedEmail)
            email = updatedEmail
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
