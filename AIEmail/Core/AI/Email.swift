import Foundation

// MARK: - Email Model

/// Represents a complete email message combining header and body information
struct Email: Sendable, Identifiable {
    let id: String
    let header: EmailHeader
    let body: EmailBody
    
    var messageID: String { id }
    var subject: String { header.subject }
    var from: String { header.from }
    var date: Date { header.date }
    var to: String? { header.to }
    var cc: String? { header.cc }
    var isRead: Bool { header.isRead }
    var isStarred: Bool { header.isStarred }
    
    var textBody: String? { body.textBody }
    var htmlBody: String? { body.htmlBody }
    var attachments: [AttachmentInfo] { body.attachments }
    var inReplyTo: String? { body.inReplyTo }
    var references: [String]? { body.references }
    
    /// Returns the best available text content for AI processing
    var displayText: String {
        if let text = textBody, !text.isEmpty {
            return text
        }
        // Strip HTML tags if only HTML is available
        if let html = htmlBody {
            return stripHTML(html)
        }
        return ""
    }
    
    /// Creates an Email from header and body components
    init(header: EmailHeader, body: EmailBody) {
        self.id = header.messageID
        self.header = header
        self.body = body
    }
    
    /// Creates a minimal Email with just essential fields
    init(
        id: String,
        subject: String,
        from: String,
        date: Date,
        textBody: String? = nil,
        htmlBody: String? = nil
    ) {
        self.id = id
        self.header = EmailHeader(
            messageID: id,
            from: from,
            subject: subject,
            date: date
        )
        self.body = EmailBody(
            messageID: id,
            textBody: textBody,
            htmlBody: htmlBody
        )
    }
    
    /// Creates an Email from an EmailRecord (database model)
    init(from record: EmailRecord) {
        self.id = record.id
        self.header = EmailHeader(
            messageID: record.messageID,
            from: record.from,
            subject: record.subject ?? "",
            date: record.receivedAt,
            to: record.to.first,
            cc: record.cc?.first,
            isRead: record.isRead,
            isStarred: record.isStarred
        )
        self.body = EmailBody(
            messageID: record.id,
            textBody: record.textBody,
            htmlBody: record.htmlBody
        )
    }
    
    // MARK: - Private Helpers
    
    private func stripHTML(_ html: String) -> String {
        // Simple HTML tag stripping
        var result = html
        let patterns = [
            "<script[^>]*>[\\s\\S]*?</script>",
            "<style[^>]*>[\\s\\S]*?</style>",
            "<[^>]+>"
        ]
        
        for pattern in patterns {
            if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    options: [],
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: ""
                )
            }
        }
        
        // Decode common HTML entities
        result = result
            .replacingOccurrences(of: "&nbsp;", with: " ")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#39;", with: "'")
        
        // Collapse whitespace
        result = result.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Email Thread

/// Represents a conversation thread (multiple related emails)
struct EmailThread: Sendable, Identifiable {
    let id: String
    let emails: [Email]
    
    /// The most recent email in the thread
    var latestEmail: Email? {
        emails.max(by: { $0.date < $1.date })
    }
    
    /// The oldest email in the thread
    var oldestEmail: Email? {
        emails.min(by: { $0.date < $1.date })
    }
    
    /// All participants in the thread
    var participants: [String] {
        Array(Set(emails.map { $0.from })).sorted()
    }
    
    init(emails: [Email]) {
        // Use the oldest email's message ID as thread ID
        self.id = emails.min(by: { $0.date < $1.date })?.id ?? UUID().uuidString
        self.emails = emails.sorted { $0.date < $1.date }
    }
}
