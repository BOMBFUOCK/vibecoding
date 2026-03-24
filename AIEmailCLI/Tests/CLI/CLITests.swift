import XCTest
@testable import cli

final class CLITests: XCTestCase {
    func testEmailProvider() throws {
        XCTAssertEqual(EmailProvider.gmail.imapHost, "imap.gmail.com")
        XCTAssertEqual(EmailProvider.gmail.imapPort, 993)
        XCTAssertEqual(EmailProvider.outlook.smtpHost, "smtp.office365.com")
    }
    
    func testAccountInfo() throws {
        let account = AccountInfo(
            email: "test@gmail.com",
            provider: .gmail,
            imapHost: "imap.gmail.com",
            imapPort: 993,
            smtpHost: "smtp.gmail.com",
            smtpPort: 587
        )
        
        XCTAssertEqual(account.email, "test@gmail.com")
        XCTAssertEqual(account.provider, .gmail)
    }
    
    func testEmailInfo() throws {
        let email = EmailInfo(
            id: "123",
            messageID: "msg-123",
            from: "sender@example.com",
            fromName: nil,
            to: ["recipient@example.com"],
            cc: nil,
            subject: "Test Subject",
            preview: "Preview text",
            textBody: "Body text",
            hasAttachments: false,
            isRead: false,
            isStarred: false,
            date: Date()
        )
        
        XCTAssertEqual(email.id, "123")
        XCTAssertEqual(email.subject, "Test Subject")
        XCTAssertEqual(email.from, "sender@example.com")
    }
}
