import Foundation

@Observable
class ComposeViewModel {
    var to: String = ""
    var cc: String = ""
    var subject: String = ""
    var body: String = ""
    var isSending: Bool = false
    var attachments: [Attachment] = []
    var errorMessage: String?
    
    private let mailDatabase: MailDatabase
    
    var canSend: Bool {
        !to.isEmpty && !subject.isEmpty && !isSending
    }
    
    init(mailDatabase: MailDatabase = MailDatabase()) {
        self.mailDatabase = mailDatabase
    }
    
    func send() async throws {
        guard canSend else { return }
        
        isSending = true
        errorMessage = nil
        
        do {
            try await Task.sleep(nanoseconds: 500_000_000)
            
            isSending = false
        } catch {
            isSending = false
            errorMessage = error.localizedDescription
            throw error
        }
    }
    
    func saveDraft() async {
        do {
            try await Task.sleep(nanoseconds: 100_000_000)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
    
    func addAttachment(_ attachment: Attachment) {
        attachments.append(attachment)
    }
    
    func removeAttachment(_ attachment: Attachment) {
        attachments.removeAll { $0.id == attachment.id }
    }
    
    func clear() {
        to = ""
        cc = ""
        subject = ""
        body = ""
        attachments = []
        errorMessage = nil
    }
    
    func setupReply(to email: Email) {
        to = email.from
        subject = "Re: \(email.subject)"
        body = ""
    }
    
    func setupForward(of email: Email) {
        to = ""
        subject = "Fwd: \(email.subject)"
        body = """
        ----------
        From: \(email.from)
        Date: \(email.date)
        Subject: \(email.subject)
        
        \(email.displayText)
        """
    }
}
