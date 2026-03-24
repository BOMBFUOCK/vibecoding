import ArgumentParser
import Foundation

struct SearchCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "search",
        abstract: "Search emails"
    )
    
    @Option
    var query: String
    
    @Option
    var mode: String = "fulltext"
    
    @Option
    var format: String = "table"
    
    @Option
    var limit: Int = 20
    
    @Option
    var account: String?
    
    func run() async throws {
        try DatabaseService.shared.initialize()
        
        let accountEmail = account ?? getDefaultAccount()
        guard let accountInfo = try DatabaseService.shared.getAccount(byEmail: accountEmail) else {
            Printer.printError("Account not found: \(accountEmail)")
            throw SearchError.accountNotFound
        }
        
        guard let password = try DatabaseService.shared.getPassword(forAccountID: accountInfo.id) else {
            Printer.printError("Credentials not found")
            throw SearchError.credentialsNotFound
        }
        
        Printer.printProgress("Searching emails...")
        
        let searchMode: SearchMode
        switch mode.lowercased() {
        case "semantic":
            searchMode = .semantic
        case "hybrid":
            searchMode = .hybrid
        default:
            searchMode = .fulltext
        }
        
        let imapService = IMAPService()
        
        try await imapService.connect(
            host: accountInfo.imapHost,
            port: accountInfo.imapPort,
            useSSL: true
        )
        
        try await imapService.login(username: accountInfo.email, password: password)
        
        let folders = try await imapService.listFolders()
        
        var allEmails: [EmailInfo] = []
        
        for folder in folders.prefix(5) {
            let emails = try await imapService.fetchHeaders(folder: folder.name, limit: limit)
            allEmails.append(contentsOf: emails)
        }
        
        try await imapService.logout()
        
        let results = performSearch(query: query, emails: allEmails, mode: searchMode)
        
        Printer.printProgressComplete("Found \(results.count) results")
        
        let outputFormat: Printer.OutputFormat
        switch format.lowercased() {
        case "json":
            outputFormat = .json
        case "plain":
            outputFormat = .plain
        default:
            outputFormat = .table
        }
        
        Printer.printSearchResults(results, format: outputFormat)
    }
    
    private func performSearch(query: String, emails: [EmailInfo], mode: SearchMode) -> [SearchResult] {
        let lowercasedQuery = query.lowercased()
        
        let scoredEmails: [(EmailInfo, Float)]
        
        switch mode {
        case .semantic:
            scoredEmails = emails.map { email in (email, 0.5) }
        case .hybrid:
            scoredEmails = emails.map { email in
                let score = calculateHybridScore(email: email, query: query)
                return (email, score)
            }
        case .fulltext:
            scoredEmails = emails.map { email in
                let score = calculateFulltextScore(email: email, query: lowercasedQuery)
                return (email, score)
            }
        }
        
        return scoredEmails
            .filter { $0.1 > 0 }
            .sorted { $0.1 > $1.1 }
            .prefix(limit)
            .map { email, score in
                SearchResult(
                    emailID: email.id,
                    subject: email.subject,
                    snippet: email.preview ?? String((email.textBody ?? "").prefix(100)),
                    from: email.from,
                    score: score,
                    matchedFields: getMatchedFields(email: email, query: lowercasedQuery)
                )
            }
    }
    
    private func calculateFulltextScore(email: EmailInfo, query: String) -> Float {
        var score: Float = 0
        
        if let subject = email.subject?.lowercased(), subject.contains(query) {
            score += 0.5
            if subject.hasPrefix(query) {
                score += 0.3
            }
        }
        
        if let body = email.textBody?.lowercased(), body.contains(query) {
            score += 0.3
        }
        
        if let from = email.from.lowercased().contains(query) ? true : nil, from {
            score += 0.2
        }
        
        return min(score, 1.0)
    }
    
    private func calculateHybridScore(email: EmailInfo, query: String) -> Float {
        return calculateFulltextScore(email: email, query: query) * 0.6 +
               Float.random(in: 0.1...0.4) * 0.4
    }
    
    private func getMatchedFields(email: EmailInfo, query: String) -> [String] {
        var fields: [String] = []
        
        if email.subject?.lowercased().contains(query) == true {
            fields.append("subject")
        }
        
        if email.textBody?.lowercased().contains(query) == true {
            fields.append("body")
        }
        
        if email.from.lowercased().contains(query) {
            fields.append("from")
        }
        
        return fields
    }
}

enum SearchError: Error, LocalizedError {
    case accountNotFound
    case credentialsNotFound
    case searchFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .accountNotFound:
            return "Account not found"
        case .credentialsNotFound:
            return "Credentials not found"
        case .searchFailed(let message):
            return "Search failed: \(message)"
        }
    }
}

private func getDefaultAccount() -> String {
    if let accounts = try? DatabaseService.shared.getAllAccounts(), let first = accounts.first {
        return first.email
    }
    return ""
}
