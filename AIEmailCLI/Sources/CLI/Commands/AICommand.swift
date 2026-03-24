import ArgumentParser
import Foundation

struct AICommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "ai",
        abstract: "AI-powered email features",
        subcommands: [
            AISummarizeCommand.self,
            AIReplyCommand.self,
            AIBatchSummarizeCommand.self,
            AISetAPIKeyCommand.self
        ]
    )
    
    func run() async throws {
        // This is a group command, it will dispatch to subcommands
        throw CleanExit.helpRequest()
    }
}

struct AISummarizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "summarize",
        abstract: "Generate email summary"
    )
    
    @Option
    var id: String
    
    @Option
    var account: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        try AIService.shared.configureFromDatabase()
        
        guard let email = try DatabaseService.shared.getEmail(byID: id) else {
            Printer.printError("Email not found")
            throw AIError.emailNotFound
        }
        
        Printer.printProgress("Generating summary...")
        
        do {
            let summary = try await AIService.shared.summarize(email: email)
            Printer.printProgressComplete("Summary generated")
            Printer.printAISummary(summary)
        } catch {
            Printer.printProgressFailed("Failed to generate summary")
            throw error
        }
    }
}

struct AIReplyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "reply",
        abstract: "Generate AI reply draft"
    )
    
    @Option
    var id: String
    
    @Option
    var tone: String = "professional"
    
    @Option
    var account: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        try AIService.shared.configureFromDatabase()
        
        guard let email = try DatabaseService.shared.getEmail(byID: id) else {
            Printer.printError("Email not found")
            throw AIError.emailNotFound
        }
        
        let replyTone: ReplyTone
        switch tone.lowercased() {
        case "casual":
            replyTone = .casual
        case "brief":
            replyTone = .brief
        default:
            replyTone = .professional
        }
        
        Printer.printProgress("Generating reply draft...")
        
        do {
            let reply = try await AIService.shared.generateReply(email: email, tone: replyTone)
            Printer.printProgressComplete("Reply draft generated")
            Printer.printAIReply(reply)
        } catch {
            Printer.printProgressFailed("Failed to generate reply")
            throw error
        }
    }
}

struct AIBatchSummarizeCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "batch-summarize",
        abstract: "Batch summarize emails in a folder"
    )
    
    @Option
    var folder: String = "INBOX"
    
    @Option
    var limit: Int = 20
    
    @Option
    var account: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        try AIService.shared.configureFromDatabase()
        
        let accountEmail = account ?? getDefaultAccount()
        guard let accountInfo = try DatabaseService.shared.getAccount(byEmail: accountEmail) else {
            Printer.printError("Account not found: \(accountEmail)")
            throw AIError.accountNotFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: accountInfo.id) else {
            Printer.printError("Credentials not found")
            throw AIError.credentialsNotFound
        }
        
        Printer.printProgress("Fetching emails...")
        
        let imapService = IMAPService()
        
        try await imapService.connect(
            host: accountInfo.imapHost,
            port: accountInfo.imapPort,
            useSSL: true
        )
        
        try await imapService.login(username: accountInfo.email, password: password)
        
        let emails = try await imapService.fetchHeaders(folder: folder, limit: limit)
        
        try await imapService.logout()
        
        Printer.printProgressComplete("Fetched \(emails.count) emails")
        Printer.printInfo("Generating summaries...")
        print()
        
        var completed = 0
        var failed = 0
        
        for email in emails {
            do {
                let summary = try await AIService.shared.summarize(email: email)
                completed += 1
                print("\(Printer.Color.green.rawValue)[\(completed)/\(emails.count)]\(Printer.Color.reset.rawValue) \(email.subject ?? "(No Subject)")")
                print("  \(summary)")
                print()
            } catch {
                failed += 1
                print("\(Printer.Color.red.rawValue)[\(completed + failed)/\(emails.count)] Failed:\(Printer.Color.reset.rawValue) \(email.subject ?? "(No Subject)")")
                print("  Error: \(error.localizedDescription)")
                print()
            }
        }
        
        print()
        Printer.printSuccess("Batch summarize complete: \(completed) succeeded, \(failed) failed")
    }
}

struct AISetAPIKeyCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-api-key",
        abstract: "Set OpenAI API key"
    )
    
    @Option
    var key: String
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        Printer.printProgress("Saving API key...")
        
        try DatabaseService.shared.saveAPIKey(key)
        AIService.shared.configure(apiKey: key)
        
        Printer.printProgressComplete("API key saved")
        Printer.printSuccess("You can now use AI features")
    }
}

enum AIError: Error, LocalizedError {
    case accountNotFound
    case credentialsNotFound
    case emailNotFound
    case apiKeyNotSet
    
    var errorDescription: String? {
        switch self {
        case .accountNotFound:
            return "Account not found"
        case .credentialsNotFound:
            return "Credentials not found"
        case .emailNotFound:
            return "Email not found"
        case .apiKeyNotSet:
            return "API key not set. Use 'aiemail ai set-api-key' to set it."
        }
    }
}

private func getDefaultAccount() -> String {
    if let accounts = try? DatabaseService.shared.getAllAccounts(), let first = accounts.first {
        return first.email
    }
    return ""
}
