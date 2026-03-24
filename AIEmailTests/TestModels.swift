import Foundation
@testable import AIEmail

// MARK: - Test Data Models

/// Test data factory providing sample data for unit tests
enum TestData {
    
    // MARK: - Test Account
    
    static let testAccount = Account(
        id: "test-account-1",
        email: "test@example.com",
        displayName: "Test User",
        provider: .gmail,
        imapHost: "imap.gmail.com",
        imapPort: 993,
        imapUseSSL: true,
        smtpHost: "smtp.gmail.com",
        smtpPort: 465,
        smtpUseSSL: true
    )
    
    // MARK: - Test Folder
    
    static let inboxFolder = Folder(
        id: "folder-inbox",
        accountID: "test-account-1",
        name: "INBOX",
        path: "INBOX",
        unreadCount: 2,
        totalCount: 10
    )
    
    static let sentFolder = Folder(
        id: "folder-sent",
        accountID: "test-account-1",
        name: "Sent",
        path: "Sent",
        unreadCount: 0,
        totalCount: 5
    )
    
    // MARK: - Test Email (Database Model from Schema.swift)
    
    static let sampleEmail = EmailRecord(
        id: "email-1",
        accountID: "test-account-1",
        folderID: "folder-inbox",
        messageID: "<test-message-id-1@example.com>",
        from: "sender@example.com",
        fromName: "Sender Name",
        to: ["test@example.com"],
        cc: nil,
        subject: "Test Email Subject",
        preview: "This is a preview of the email body...",
        textBody: "Hello,\n\nThis is a test email body.\n\nBest regards,\nSender",
        htmlBody: nil,
        hasAttachments: false,
        isRead: false,
        isStarred: false,
        isDeleted: false,
        receivedAt: Date(),
        syncedAt: Date()
    )
    
    static let sampleEmailRead = EmailRecord(
        id: "email-2",
        accountID: "test-account-1",
        folderID: "folder-inbox",
        messageID: "<test-message-id-2@example.com>",
        from: "another@example.com",
        fromName: "Another Sender",
        to: ["test@example.com"],
        cc: nil,
        subject: "Another Test Email",
        preview: "Preview of another email...",
        textBody: "This is another test email with meeting rescheduled information.",
        htmlBody: nil,
        hasAttachments: true,
        isRead: true,
        isStarred: false,
        isDeleted: false,
        receivedAt: Date().addingTimeInterval(-3600),
        syncedAt: Date()
    )
    
    static let sampleEmails: [EmailRecord] = [
        sampleEmail,
        sampleEmailRead
    ]
    
    // MARK: - Test Attachment
    
    static let sampleAttachment = Attachment(
        id: "attachment-1",
        emailID: "email-1",
        partID: "1.2",
        filename: "document.pdf",
        mimeType: "application/pdf",
        size: 102400,
        isInline: false,
        localPath: nil
    )
    
    // MARK: - Test AI Processing
    
    static let sampleAIProcessing = AIProcessing(
        id: "ai-processing-1",
        emailID: "email-1",
        status: .completed,
        summary: "Test summary of the email",
        replyDraft: "Thank you for your email...",
        actionItems: nil,
        errorMessage: nil,
        processedAt: Date()
    )
}

// MARK: - Mock IMAP Responses

enum MockIMAPResponses {
    static let capability = "* CAPABILITY IMAP4rev1 STARTTLS LOGINDISABLED AUTH=LOGIN AUTH=PLAIN\r\n"
    static let capabilityTagged = "A001 OK Completed\r\n"
    static let loginSuccess = "A001 OK Login successful\r\n"
    static let loginFailure = "A001 NO Authentication failed\r\n"
    static let selectInbox = """
    * FLAGS (\\Answered \\Flagged \\Draft \\Deleted \\Seen)
    * 10 EXISTS
    * 0 RECENT
    * OK [UNSEEN 1]
    * OK [UIDVALIDITY 1]
    * OK [UIDNEXT 11]
    * LIST (\\HasNoChildren) "." "INBOX"
    * OK [READ-WRITE]
    A001 OK [READ-WRITE] Select completed.
    """
    
    static let selectSent = """
    * FLAGS (\\Answered \\Flagged \\Draft \\Deleted \\Seen)
    * 5 EXISTS
    * 0 RECENT
    * OK [UIDVALIDITY 1]
    * OK [UIDNEXT 6]
    * LIST (\\HasNoChildren) "." "Sent"
    A001 OK [READ-WRITE] Select completed.
    """
    
    static let searchResults = "A001 OK Search completed.\r\n"
    
    static let fetchHeaders = """
    * 1 FETCH (ENVELOPE ("<test-message-id-1@example.com>" "Test Subject" (("Sender" NIL "sender" "example.com")) ((NIL NIL "sender" "example.com")) ((NIL NIL "sender" "example.com")) ((NIL NIL "test" "example.com")) NIL NIL NIL NIL) UID 1)
    * 2 FETCH (ENVELOPE ("<test-message-id-2@example.com>" "Another Subject" (("Another" NIL "another" "example.com")) ((NIL NIL "another" "example.com")) ((NIL NIL "another" "example.com")) ((NIL NIL "test" "example.com")) NIL NIL NIL NIL) UID 2)
    A001 OK Fetch completed.
    """
    
    static let fetchBody = """
    * 1 FETCH (BODY[TEXT] {50}
    Hello,

    This is a test email body.

    Best regards,
    Sender
    )
    A001 OK Fetch completed.
    """
    
    static let logout = "A001 OK Logout completed.\r\n"
    
    static let listFolders = """
    * LIST (\\HasNoChildren) "." "INBOX"
    * LIST (\\HasNoChildren) "." "Sent"
    * LIST (\\HasNoChildren) "." "Drafts"
    * LIST (\\HasNoChildren) "." "Trash"
    A001 OK List completed.
    """
}

// MARK: - Mock SMTP Responses

enum MockSMTPResponses {
    static let ready = "220 smtp.example.com ESMTP\r\n"
    static let ehloSuccess = """
    250-smtp.example.com
    250-8BITMIME
    250-SIZE 10000000
    250-AUTH LOGIN PLAIN
    250 HELP
    """
    static let authSuccess = "235 Authentication successful\r\n"
    static let mailSuccess = "250 Mail accepted\r\n"
    static let rcptSuccess = "250 Recipient OK\r\n"
    static let dataSuccess = "354 Start mail input\r\n"
    static let sendSuccess = "250 Message accepted for delivery\r\n"
    static let quitSuccess = "221 Goodbye\r\n"
    static let authRequired = "530 Authentication required\r\n"
}

// MARK: - Mock AI Responses

enum MockAIResponses {
    static let summaryResponse = "这是一个测试邮件的摘要，包含重要信息。"
    static let replyResponse = "感谢您的邮件，我会尽快处理您的问题。"
    static let embeddingResponse: [Float] = Array(repeating: 0.1, count: 1536)
}

// MARK: - Test Configuration

enum TestConfig {
    static let testAPIKey = "test-api-key-for-unit-tests"
    static let testEmailHost = "imap.test.com"
    static let testSMTPHost = "smtp.test.com"
    static let connectionTimeout: TimeInterval = 5.0
}
