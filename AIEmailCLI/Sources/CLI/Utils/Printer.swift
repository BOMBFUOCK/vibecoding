import Foundation

struct Printer {
    enum OutputFormat: String, CaseIterable {
        case plain
        case table
        case json
    }
    
    enum Color: String {
        case red = "\u{001B}[31m"
        case green = "\u{001B}[32m"
        case yellow = "\u{001B}[33m"
        case blue = "\u{001B}[34m"
        case magenta = "\u{001B}[35m"
        case cyan = "\u{001B}[36m"
        case white = "\u{001B}[37m"
        case reset = "\u{001B}[0m"
        case bold = "\u{001B}[1m"
        case dim = "\u{001B}[2m"
    }
    
    static func printError(_ message: String) {
        fflush(stdout)
        FileHandle.standardError.write("\(Color.red.rawValue)Error: \(message)\(Color.reset.rawValue)\n".data(using: .utf8)!)
    }
    
    static func printSuccess(_ message: String) {
        print("\(Color.green.rawValue)\(message)\(Color.reset.rawValue)")
    }
    
    static func printWarning(_ message: String) {
        print("\(Color.yellow.rawValue)Warning: \(message)\(Color.reset.rawValue)")
    }
    
    static func printInfo(_ message: String) {
        print("\(Color.cyan.rawValue)\(message)\(Color.reset.rawValue)")
    }
    
    static func printHeader(_ message: String) {
        print("\(Color.bold.rawValue)\(Color.blue.rawValue)\(message)\(Color.reset.rawValue)")
    }
    
    static func printAccounts(_ accounts: [AccountInfo], format: OutputFormat = .table) {
        switch format {
        case .plain:
            accounts.forEach { print($0.email) }
        case .table:
            printAccountsTable(accounts)
        case .json:
            printAccountsJSON(accounts)
        }
    }
    
    private static func printAccountsTable(_ accounts: [AccountInfo]) {
        print()
        print("\(Color.bold.rawValue)Email Accounts:\(Color.reset.rawValue)")
        print(String(repeating: "─", count: 60))
        
        if accounts.isEmpty {
            print("  No accounts configured")
            return
        }
        
        print("\(Color.bold.rawValue)  Email\(Color.reset.rawValue)".padding(toLength: 35, withPad: " ", startingAt: 0) + 
              "\(Color.bold.rawValue)Provider\(Color.reset.rawValue)".padding(toLength: 15, withPad: " ", startingAt: 0) +
              "\(Color.bold.rawValue)Status\(Color.reset.rawValue)")
        print(String(repeating: "─", count: 60))
        
        for account in accounts {
            let status = account.isConnected ? "\(Color.green.rawValue)Connected\(Color.reset.rawValue)" : "\(Color.dim.rawValue)Disconnected\(Color.reset.rawValue)"
            print("  \(account.email.padding(toLength: 35, withPad: " ", startingAt: 0))\(account.provider.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0))\(status)")
        }
        print()
    }
    
    private static func printAccountsJSON(_ accounts: [AccountInfo]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(accounts), let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }
    
    static func printEmails(_ emails: [EmailInfo], format: OutputFormat = .table) {
        switch format {
        case .plain:
            emails.forEach { print("\($0.subject ?? "(No Subject)") - \($0.from)") }
        case .table:
            printEmailsTable(emails)
        case .json:
            printEmailsJSON(emails)
        }
    }
    
    private static func printEmailsTable(_ emails: [EmailInfo]) {
        print()
        print("\(Color.bold.rawValue)Emails:\(Color.reset.rawValue)")
        print(String(repeating: "─", count: 80))
        
        if emails.isEmpty {
            print("  No emails found")
            return
        }
        
        print("\(Color.bold.rawValue)  ID\(Color.reset.rawValue)".padding(toLength: 8, withPad: " ", startingAt: 0) +
              "\(Color.bold.rawValue)From\(Color.reset.rawValue)".padding(toLength: 20, withPad: " ", startingAt: 0) +
              "\(Color.bold.rawValue)Subject\(Color.reset.rawValue)".padding(toLength: 30, withPad: " ", startingAt: 0) +
              "\(Color.bold.rawValue)Date\(Color.reset.rawValue)")
        print(String(repeating: "─", count: 80))
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "MM/dd HH:mm"
        
        for email in emails {
            let shortFrom = String(email.from.prefix(18))
            let shortSubject = String((email.subject ?? "(No Subject)").prefix(28))
            let dateStr = dateFormatter.string(from: email.date)
            let readIndicator = email.isRead ? " " : "\(Color.yellow.rawValue)●\(Color.reset.rawValue)"
            
            print("  \(readIndicator)\(email.id.padding(toLength: 6, withPad: " ", startingAt: 0))\(shortFrom.padding(toLength: 20, withPad: " ", startingAt: 0))\(shortSubject.padding(toLength: 30, withPad: " ", startingAt: 0))\(dateStr)")
        }
        print()
    }
    
    private static func printEmailsJSON(_ emails: [EmailInfo]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(emails), let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }
    
    static func printEmailDetail(_ email: EmailDetail) {
        print()
        printHeader("Email Details")
        print(String(repeating: "─", count: 60))
        
        print("\(Color.bold.rawValue)From:\(Color.reset.rawValue) \(email.from)")
        print("\(Color.bold.rawValue)To:\(Color.reset.rawValue) \(email.to)")
        if let cc = email.cc {
            print("\(Color.bold.rawValue)Cc:\(Color.reset.rawValue) \(cc)")
        }
        print("\(Color.bold.rawValue)Date:\(Color.reset.rawValue) \(formatDate(email.date))")
        print("\(Color.bold.rawValue)Subject:\(Color.reset.rawValue) \(email.subject ?? "(No Subject)")")
        
        if email.hasAttachments {
            print("\(Color.bold.rawValue)Attachments:\(Color.reset.rawValue) \(email.attachments.count)")
        }
        
        print()
        print("\(Color.bold.rawValue)Body:\(Color.reset.rawValue)")
        print(String(repeating: "─", count: 60))
        print(email.textBody ?? "(No body content)")
        print()
    }
    
    static func printSearchResults(_ results: [SearchResult], format: OutputFormat = .table) {
        switch format {
        case .plain:
            results.forEach { print("\($0.subject ?? "(No Subject)") - \($0.snippet)") }
        case .table:
            printSearchResultsTable(results)
        case .json:
            printSearchResultsJSON(results)
        }
    }
    
    private static func printSearchResultsTable(_ results: [SearchResult]) {
        print()
        print("\(Color.bold.rawValue)Search Results:\(Color.reset.rawValue)")
        print(String(repeating: "─", count: 80))
        
        if results.isEmpty {
            print("  No results found")
            return
        }
        
        print("\(Color.bold.rawValue)  Score\(Color.reset.rawValue)".padding(toLength: 10, withPad: " ", startingAt: 0) +
              "\(Color.bold.rawValue)Subject\(Color.reset.rawValue)".padding(toLength: 35, withPad: " ", startingAt: 0) +
              "\(Color.bold.rawValue)From\(Color.reset.rawValue)")
        print(String(repeating: "─", count: 80))
        
        for result in results {
            let shortSubject = String((result.subject ?? "(No Subject)").prefix(33))
            let shortFrom = String(result.from.prefix(15))
            print("  \(String(format: "%.2f", result.score).padding(toLength: 8, withPad: " ", startingAt: 0))\(shortSubject.padding(toLength: 35, withPad: " ", startingAt: 0))\(shortFrom)")
            if !result.snippet.isEmpty {
                print("    \(Color.dim.rawValue)\(String(result.snippet.prefix(60)))...\(Color.reset.rawValue)")
            }
        }
        print()
    }
    
    private static func printSearchResultsJSON(_ results: [SearchResult]) {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        if let data = try? encoder.encode(results), let json = String(data: data, encoding: .utf8) {
            print(json)
        }
    }
    
    static func printAISummary(_ summary: String) {
        print()
        printHeader("AI Summary")
        print(String(repeating: "─", count: 60))
        print(summary)
        print()
    }
    
    static func printAIReply(_ reply: String) {
        print()
        printHeader("AI Reply Draft")
        print(String(repeating: "─", count: 60))
        print(reply)
        print()
        printInfo("You can use 'aiemail mail send' to send this reply")
        print()
    }
    
    static func printProgress(_ message: String) {
        print("\(Color.dim.rawValue)→ \(message)...\(Color.reset.rawValue)", terminator: "")
        fflush(stdout)
    }
    
    static func printProgressComplete(_ message: String) {
        print("\r\(Color.green.rawValue)✓\(Color.reset.rawValue) \(message)")
    }
    
    static func printProgressFailed(_ message: String) {
        print("\r\(Color.red.rawValue)✗\(Color.reset.rawValue) \(message)")
    }
    
    private static func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .full
        formatter.timeStyle = .medium
        return formatter.string(from: date)
    }
}
