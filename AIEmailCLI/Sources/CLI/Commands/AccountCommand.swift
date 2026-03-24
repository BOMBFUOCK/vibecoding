import ArgumentParser
import Foundation

struct AccountCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "account",
        abstract: "Manage email accounts",
        subcommands: [
            AccountAddCommand.self,
            AccountListCommand.self,
            AccountDeleteCommand.self,
            AccountTestCommand.self
        ]
    )
    
    func run() async throws {
    }
}

struct AccountAddCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "Add a new email account"
    )
    
    @Option
    var email: String
    
    @Option
    var provider: String
    
    @Option
    var password: String
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let emailProvider: EmailProvider
        switch provider.lowercased() {
        case "gmail":
            emailProvider = .gmail
        case "outlook":
            emailProvider = .outlook
        case "qq":
            emailProvider = .qq
        case "163", "netease":
            emailProvider = .netease
        default:
            emailProvider = .other
        }
        
        let account = AccountInfo(
            email: email,
            displayName: nil,
            provider: emailProvider,
            imapHost: emailProvider.imapHost,
            imapPort: emailProvider.imapPort,
            smtpHost: emailProvider.smtpHost,
            smtpPort: emailProvider.smtpPort,
            lastSyncedAt: nil,
            isConnected: false
        )
        
        Printer.printProgress("Adding account...")
        
        do {
            try DatabaseService.shared.saveAccount(account, password: password)
            Printer.printProgressComplete("Account added successfully")
        } catch {
            Printer.printProgressFailed("Failed to add account")
            throw error
        }
    }
}

struct AccountListCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List all configured accounts"
    )
    
    @Option
    var format: String = "table"
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let accounts = try DatabaseService.shared.getAllAccounts()
        
        let outputFormat: Printer.OutputFormat
        switch format.lowercased() {
        case "json":
            outputFormat = .json
        case "plain":
            outputFormat = .plain
        default:
            outputFormat = .table
        }
        
        Printer.printAccounts(accounts, format: outputFormat)
    }
}

struct AccountDeleteCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "delete",
        abstract: "Delete an email account"
    )
    
    @Option
    var email: String
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        Printer.printProgress("Deleting account...")
        
        do {
            try DatabaseService.shared.deleteAccount(byEmail: email)
            Printer.printProgressComplete("Account deleted successfully")
        } catch {
            Printer.printProgressFailed("Failed to delete account")
            throw error
        }
    }
}

struct AccountTestCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "test",
        abstract: "Test account connection"
    )
    
    @Option
    var email: String
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        guard let account = try DatabaseService.shared.getAccount(byEmail: email) else {
            Printer.printError("Account not found: \(email)")
            throw AccountError.notFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: account.id) else {
            Printer.printError("Credentials not found for account")
            throw AccountError.credentialsNotFound
        }
        
        Printer.printProgress("Connecting to IMAP server...")
        
        let imapService = IMAPService()
        
        try await imapService.connect(
            host: account.imapHost,
            port: account.imapPort,
            useSSL: true
        )
        
        Printer.printProgressComplete("IMAP connection established")
        
        Printer.printProgress("Testing authentication...")
        
        try await imapService.login(username: account.email, password: password)
        
        Printer.printProgressComplete("Authentication successful")
        
        Printer.printProgress("Testing SMTP server...")
        
        let smtpService = SMTPService()
        try await smtpService.connect(
            host: account.smtpHost,
            port: account.smtpPort,
            useSSL: false
        )
        
        Printer.printProgressComplete("SMTP connection established")
        
        try await smtpService.login(username: account.email, password: password)
        
        Printer.printProgressComplete("SMTP authentication successful")
        
        try await imapService.logout()
        try await smtpService.disconnect()
        
        Printer.printSuccess("Account test passed!")
    }
}

enum AccountError: Error, LocalizedError {
    case notFound
    case credentialsNotFound
    
    var errorDescription: String? {
        switch self {
        case .notFound:
            return "Account not found"
        case .credentialsNotFound:
            return "Account credentials not found"
        }
    }
}
