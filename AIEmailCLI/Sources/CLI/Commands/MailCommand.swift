import ArgumentParser
import Foundation

struct MailCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mail",
        abstract: "Email operations",
        subcommands: [
            MailListCommand.self,
            MailViewCommand.self,
            MailSendCommand.self,
            MailReplyCommand.self,
            MailMarkReadCommand.self,
            MailMarkUnreadCommand.self,
            MailDeleteCommand.self,
            MailMoveCommand.self
        ]
    )
    
    @Option
    var account: String?
    
    @Option
    var format: String = "table"
    
    func run() throws {
        throw CleanExit.helpRequest()
    }
}

struct MailListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List emails in a folder"
    )
    
    @Option
    var folder: String = "INBOX"
    
    @Option
    var limit: Int = 20
    
    @Option
    var account: String?
    
    @Option
    var format: String = "table"
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let accountEmail = account ?? getDefaultAccount()
        guard let accountInfo = try DatabaseService.shared.getAccount(byEmail: accountEmail) else {
            Printer.printError("Account not found: \(accountEmail)")
            throw MailError.accountNotFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: accountInfo.id) else {
            Printer.printError("Credentials not found")
            throw MailError.credentialsNotFound
        }
        
        Printer.printProgress("Connecting to mail server...")
        
        let imapService = IMAPService()
        
        try await imapService.connect(
            host: accountInfo.imapHost,
            port: accountInfo.imapPort,
            useSSL: true
        )
        
        try await imapService.login(username: accountInfo.email, password: password)
        
        Printer.printProgressComplete("Connected")
        Printer.printProgress("Fetching emails...")
        
        let emails = try await imapService.fetchHeaders(folder: folder, limit: limit)
        
        Printer.printProgressComplete("Fetched \(emails.count) emails")
        
        try await imapService.logout()
        
        let outputFormat: Printer.OutputFormat
        switch format.lowercased() {
        case "json":
            outputFormat = .json
        case "plain":
            outputFormat = .plain
        default:
            outputFormat = .table
        }
        
        Printer.printEmails(emails, format: outputFormat)
    }
}

struct MailViewCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "View email details"
    )
    
    @Option
    var id: String
    
    @Option
    var account: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let accountEmail = account ?? getDefaultAccount()
        guard let accountInfo = try DatabaseService.shared.getAccount(byEmail: accountEmail) else {
            Printer.printError("Account not found: \(accountEmail)")
            throw MailError.accountNotFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: accountInfo.id) else {
            Printer.printError("Credentials not found")
            throw MailError.credentialsNotFound
        }
        
        Printer.printProgress("Fetching email...")
        
        let imapService = IMAPService()
        
        try await imapService.connect(
            host: accountInfo.imapHost,
            port: accountInfo.imapPort,
            useSSL: true
        )
        
        try await imapService.login(username: accountInfo.email, password: password)
        
        let emailDetail = try await imapService.fetchBody(messageID: id)
        
        try await imapService.logout()
        
        Printer.printProgressComplete("Email fetched")
        Printer.printEmailDetail(emailDetail)
    }
}

struct MailSendCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "send",
        abstract: "Send an email"
    )
    
    @Option
    var to: String
    
    @Option
    var subject: String
    
    @Option
    var body: String
    
    @Option
    var account: String?
    
    @Option
    var cc: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let accountEmail = account ?? getDefaultAccount()
        guard let accountInfo = try DatabaseService.shared.getAccount(byEmail: accountEmail) else {
            Printer.printError("Account not found: \(accountEmail)")
            throw MailError.accountNotFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: accountInfo.id) else {
            Printer.printError("Credentials not found")
            throw MailError.credentialsNotFound
        }
        
        Printer.printProgress("Sending email...")
        
        let smtpService = SMTPService()
        
        try await smtpService.connect(
            host: accountInfo.smtpHost,
            port: accountInfo.smtpPort,
            useSSL: false
        )
        
        try await smtpService.login(username: accountInfo.email, password: password)
        
        let recipients = [to] + (cc?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } ?? [])
        
        let message = SendMessageRequest(
            from: accountInfo.email,
            to: [to],
            cc: cc != nil ? cc?.components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) } : nil,
            subject: subject,
            textBody: body
        )
        
        let result = try await smtpService.send(message: message)
        
        try await smtpService.disconnect()
        
        Printer.printProgressComplete("Email sent successfully")
        Printer.printInfo("Message ID: \(result.messageID)")
        Printer.printInfo("Sent to: \(result.acceptedRecipients.joined(separator: ", "))")
    }
}

struct MailReplyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reply",
        abstract: "Reply to an email"
    )
    
    @Option
    var id: String
    
    @Option
    var body: String
    
    @Option
    var account: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let accountEmail = account ?? getDefaultAccount()
        guard let accountInfo = try DatabaseService.shared.getAccount(byEmail: accountEmail) else {
            Printer.printError("Account not found: \(accountEmail)")
            throw MailError.accountNotFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: accountInfo.id) else {
            Printer.printError("Credentials not found")
            throw MailError.credentialsNotFound
        }
        
        guard let originalEmail = try DatabaseService.shared.getEmail(byID: id) else {
            Printer.printError("Email not found")
            throw MailError.emailNotFound
        }
        
        Printer.printProgress("Fetching original email...")
        
        let imapService = IMAPService()
        
        try await imapService.connect(
            host: accountInfo.imapHost,
            port: accountInfo.imapPort,
            useSSL: true
        )
        
        try await imapService.login(username: accountInfo.email, password: password)
        
        let emailDetail = try await imapService.fetchBody(messageID: id)
        
        try await imapService.logout()
        
        Printer.printProgressComplete("Sending reply...")
        
        let smtpService = SMTPService()
        
        try await smtpService.connect(
            host: accountInfo.smtpHost,
            port: accountInfo.smtpPort,
            useSSL: false
        )
        
        try await smtpService.login(username: accountInfo.email, password: password)
        
        let replySubject = emailDetail.subject?.hasPrefix("Re:") == true
            ? emailDetail.subject!
            : "Re: \(emailDetail.subject ?? "(No Subject)")"
        
        let replyBody = """
        \(body)
        
        ---
        On \(formatDate(emailDetail.date)) \(emailDetail.from) wrote:
        \(emailDetail.textBody ?? "")
        """
        
        let message = SendMessageRequest(
            from: accountInfo.email,
            to: [emailDetail.from],
            subject: replySubject,
            textBody: replyBody,
            inReplyTo: emailDetail.messageID
        )
        
        let result = try await smtpService.send(message: message)
        
        try await smtpService.disconnect()
        
        Printer.printProgressComplete("Reply sent successfully")
        Printer.printInfo("Message ID: \(result.messageID)")
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d, yyyy 'at' h:mm a"
        return formatter.string(from: date)
    }
}

struct MailMarkReadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mark-read",
        abstract: "Mark email as read"
    )
    
    @Option
    var id: String
    
    @Option
    var account: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let accountEmail = account ?? getDefaultAccount()
        guard let accountInfo = try DatabaseService.shared.getAccount(byEmail: accountEmail) else {
            Printer.printError("Account not found: \(accountEmail)")
            throw MailError.accountNotFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: accountInfo.id) else {
            Printer.printError("Credentials not found")
            throw MailError.credentialsNotFound
        }
        
        Printer.printProgress("Marking email as read...")
        
        let imapService = IMAPService()
        
        try await imapService.connect(
            host: accountInfo.imapHost,
            port: accountInfo.imapPort,
            useSSL: true
        )
        
        try await imapService.login(username: accountInfo.email, password: password)
        
        try await imapService.setFlags(messageIDs: [id], seen: true)
        
        try await imapService.logout()
        
        Printer.printProgressComplete("Email marked as read")
    }
}

struct MailMarkUnreadCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "mark-unread",
        abstract: "Mark email as unread"
    )
    
    @Option
    var id: String
    
    @Option
    var account: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let accountEmail = account ?? getDefaultAccount()
        guard let accountInfo = try DatabaseService.shared.getAccount(byEmail: accountEmail) else {
            Printer.printError("Account not found: \(accountEmail)")
            throw MailError.accountNotFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: accountInfo.id) else {
            Printer.printError("Credentials not found")
            throw MailError.credentialsNotFound
        }
        
        Printer.printProgress("Marking email as unread...")
        
        let imapService = IMAPService()
        
        try await imapService.connect(
            host: accountInfo.imapHost,
            port: accountInfo.imapPort,
            useSSL: true
        )
        
        try await imapService.login(username: accountInfo.email, password: password)
        
        try await imapService.setFlags(messageIDs: [id], seen: false)
        
        try await imapService.logout()
        
        Printer.printProgressComplete("Email marked as unread")
    }
}

struct MailDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an email"
    )
    
    @Option
    var id: String
    
    @Option
    var account: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let accountEmail = account ?? getDefaultAccount()
        guard let accountInfo = try DatabaseService.shared.getAccount(byEmail: accountEmail) else {
            Printer.printError("Account not found: \(accountEmail)")
            throw MailError.accountNotFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: accountInfo.id) else {
            Printer.printError("Credentials not found")
            throw MailError.credentialsNotFound
        }
        
        Printer.printProgress("Deleting email...")
        
        let imapService = IMAPService()
        
        try await imapService.connect(
            host: accountInfo.imapHost,
            port: accountInfo.imapPort,
            useSSL: true
        )
        
        try await imapService.login(username: accountInfo.email, password: password)
        
        try await imapService.deleteMessages(messageIDs: [id])
        
        try await imapService.logout()
        
        Printer.printProgressComplete("Email deleted")
    }
}

struct MailMoveCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "move",
        abstract: "Move email to a folder"
    )
    
    @Option
    var id: String
    
    @Option
    var folder: String
    
    @Option
    var account: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let accountEmail = account ?? getDefaultAccount()
        guard let accountInfo = try DatabaseService.shared.getAccount(byEmail: accountEmail) else {
            Printer.printError("Account not found: \(accountEmail)")
            throw MailError.accountNotFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: accountInfo.id) else {
            Printer.printError("Credentials not found")
            throw MailError.credentialsNotFound
        }
        
        Printer.printProgress("Moving email to \(folder)...")
        
        let imapService = IMAPService()
        
        try await imapService.connect(
            host: accountInfo.imapHost,
            port: accountInfo.imapPort,
            useSSL: true
        )
        
        try await imapService.login(username: accountInfo.email, password: password)
        
        try await imapService.moveMessages(messageIDs: [id], toFolder: folder)
        
        try await imapService.logout()
        
        Printer.printProgressComplete("Email moved to \(folder)")
    }
}

enum MailError: Error, LocalizedError {
    case accountNotFound
    case credentialsNotFound
    case emailNotFound
    
    var errorDescription: String? {
        switch self {
        case .accountNotFound:
            return "Account not found"
        case .credentialsNotFound:
            return "Credentials not found"
        case .emailNotFound:
            return "Email not found"
        }
    }
}

private func getDefaultAccount() -> String {
    if let accounts = try? DatabaseService.shared.getAllAccounts(), let first = accounts.first {
        return first.email
    }
    return ""
}
