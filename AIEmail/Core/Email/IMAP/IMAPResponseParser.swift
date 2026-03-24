import Foundation

final class IMAPResponseParser: @unchecked Sendable {
    
    func parseResponse(_ data: Data) throws -> [IMAPResponseType] {
        guard let string = String(data: data, encoding: .utf8) else {
            throw IMAPError.parseError("Unable to decode response data")
        }
        return try parseResponse(string)
    }
    
    func parseResponse(_ response: String) throws -> [IMAPResponseType] {
        var responses: [IMAPResponseType] = []
        let lines = response.components(separatedBy: "\r\n")
        
        var currentIndex = 0
        while currentIndex < lines.count {
            let line = lines[currentIndex]
            if line.isEmpty {
                currentIndex += 1
                continue
            }
            
            if let response = try parseLine(line, allLines: lines, currentIndex: &currentIndex) {
                responses.append(response)
            }
            currentIndex += 1
        }
        
        return responses
    }
    
    private func parseLine(_ line: String, allLines: [String], currentIndex: inout Int) throws -> IMAPResponseType? {
        if line.hasSuffix("{") {
            return nil
        }
        
        if line.hasPrefix("* ") {
            return try parseUntagged(line)
        }
        
        if let range = line.range(of: #"^[A-Z]\d{4} "#, options: .regularExpression) {
            let tag = String(line[range]).trimmingCharacters(in: .whitespaces)
            let rest = String(line[range.upperBound...])
            let response = try parseTaggedResponse(rest)
            return .tagged(tag: tag, response: response)
        }
        
        return nil
    }
    
    private func parseUntagged(_ line: String) throws -> IMAPResponseType {
        let content = String(line.dropFirst(2))
        
        if content.hasPrefix("OK") || content.hasPrefix("NO") || content.hasPrefix("BAD") || content.hasPrefix("BYE") {
            return try parseStatusResponse(content)
        }
        
        if content.hasPrefix("CAPABILITY") {
            return .untagged(.raw(content))
        }
        
        if content.hasPrefix("LIST") || content.hasPrefix("LSUB") {
            return try parseListResponse(content)
        }
        
        if content.hasPrefix("SEARCH") {
            return try parseSearchResponse(content)
        }
        
        if content.hasPrefix("FLAGS") {
            return try parseFlagsResponse(content)
        }
        
        if content.hasPrefix("EXISTS") {
            return try parseExistsResponse(content)
        }
        
        if content.hasPrefix("RECENT") {
            return try parseRecentResponse(content)
        }
        
        if content.hasPrefix("FETCH") {
            return try parseFetchResponse(content)
        }
        
        if content.hasPrefix("STATUS") {
            return try parseStatusResponse(content)
        }
        
        return .untagged(.raw(content))
    }
    
    private func parseStatusResponse(_ content: String) throws -> IMAPResponseType {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("OK") {
            return .ok
        } else if trimmed.hasPrefix("NO") {
            return .no
        } else if trimmed.hasPrefix("BAD") {
            return .bad
        } else if trimmed.hasPrefix("BYE") {
            return .bye
        }
        throw IMAPError.parseError("Unknown status response: \(content)")
    }
    
    private func parseListResponse(_ content: String) throws -> IMAPResponseType {
        var bracketLevel = 0
        var fields: [String] = []
        var currentField = ""
        
        let chars = Array(content)
        var i = 0
        
        while i < chars.count {
            let char = chars[i]
            
            if char == "(" {
                bracketLevel += 1
                currentField.append(char)
            } else if char == ")" {
                bracketLevel -= 1
                currentField.append(char)
            } else if char == " " && bracketLevel == 0 {
                if !currentField.isEmpty {
                    fields.append(currentField)
                    currentField = ""
                }
            } else {
                currentField.append(char)
            }
            i += 1
        }
        
        if !currentField.isEmpty {
            fields.append(currentField)
        }
        
        var attributes: [String] = []
        var delimiter = ""
        var folderName = ""
        
        var parsingAttributes = true
        for field in fields {
            if parsingAttributes {
                if field.hasPrefix("(") {
                    parsingAttributes = false
                    let attrString = field.trimmingCharacters(in: CharacterSet(charactersIn: "()"))
                    if !attrString.isEmpty {
                        attributes = attrString.components(separatedBy: " ").filter { !$0.isEmpty }
                    }
                } else {
                    attributes.append(field)
                }
            } else if delimiter.isEmpty && !field.hasPrefix("\"") {
                delimiter = field
            } else if field.hasPrefix("\"") && field.hasSuffix("\"") && folderName.isEmpty {
                folderName = String(field.dropFirst().dropLast())
            } else if folderName.isEmpty {
                folderName = field.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
        }
        
        return .untagged(.list([[
            "attributes": attributes.joined(separator: " "),
            "delimiter": delimiter,
            "name": folderName
        ]]))
    }
    
    private func parseSearchResponse(_ content: String) throws -> IMAPResponseType {
        let parts = content.components(separatedBy: " ")
        let ids = parts.dropFirst().filter { !$0.isEmpty }
        return .untagged(.search(ids.map { String($0) }))
    }
    
    private func parseFlagsResponse(_ content: String) throws -> IMAPResponseType {
        let match = content.range(of: #"FLAGS\s+\(([^)]*)\)"#, options: .regularExpression)
        if let match = match {
            let flagsString = String(content[match]).dropFirst(7).dropLast()
            let flags = flagsString.components(separatedBy: " ").filter { !$0.isEmpty }
            return .untagged(.flags(flags))
        }
        return .untagged(.flags([]))
    }
    
    private func parseExistsResponse(_ content: String) throws -> IMAPResponseType {
        let parts = content.components(separatedBy: " ")
        if let count = Int(parts.first ?? "") {
            return .untagged(.exists(count))
        }
        throw IMAPError.parseError("Invalid EXISTS response: \(content)")
    }
    
    private func parseRecentResponse(_ content: String) throws -> IMAPResponseType {
        let parts = content.components(separatedBy: " ")
        if let count = Int(parts.first ?? "") {
            return .untagged(.recent(count))
        }
        throw IMAPError.parseError("Invalid RECENT response: \(content)")
    }
    
    private func parseFetchResponse(_ content: String) throws -> IMAPResponseType {
        var fetchData: [String: Any] = [:]
        
        let fetchMatch = content.range(of: #"(\d+)\s+FETCH\s+"#, options: .regularExpression)
        if let fetchMatch = fetchMatch, let messageID = Int(content[..<fetchMatch.lowerBound]) {
            fetchData["messageID"] = String(messageID)
        }
        
        var bodyContent = content
        if let fetchRange = content.range(of: #"FETCH\s+\{"#, options: .regularExpression) {
            bodyContent = String(content[fetchRange.upperBound...])
        }
        
        if let openBrace = bodyContent.firstIndex(of: "{"),
           let closeBrace = bodyContent.lastIndex(of: "}") {
            let literalContent = String(bodyContent[bodyContent.index(after: openBrace)..<closeBrace])
            if let size = Int(literalContent) {
                fetchData["literalSize"] = size
            }
        }
        
        let envelopeMatch = content.range(of: #"ENVELOPE\s+\(\([^)]*\)\)"#, options: .regularExpression)
        if let envelopeMatch = envelopeMatch {
            let envelopeStr = String(content[envelopeMatch])
            fetchData["envelope"] = envelopeStr
        }
        
        let flagsMatch = content.range(of: #"FLAGS\s+\(([^)]*)\)"#, options: .regularExpression)
        if let flagsMatch = flagsMatch {
            let flagsStr = String(content[flagsMatch])
            fetchData["flags"] = flagsStr
        }
        
        return .untagged(.fetch(fetchData))
    }
    
    private func parseTaggedResponse(_ content: String) throws -> IMAPResponseType {
        let trimmed = content.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("OK") {
            return .ok
        } else if trimmed.hasPrefix("NO") {
            return .no
        } else if trimmed.hasPrefix("BAD") {
            return .bad
        }
        throw IMAPError.parseError("Unknown tagged response: \(content)")
    }
    
    func parseFolderInfo(from responses: [IMAPResponseType]) -> FolderInfo? {
        var name = "INBOX"
        var totalMessages = 0
        var recentMessages = 0
        var unseenMessages = 0
        
        for response in responses {
            switch response {
            case .untagged(let data):
                switch data {
                case .exists(let count):
                    totalMessages = count
                case .recent(let count):
                    recentMessages = count
                case .flags:
                    break
                default:
                    break
                }
            default:
                break
            }
        }
        
        return FolderInfo(
            name: name,
            totalMessages: totalMessages,
            recentMessages: recentMessages,
            unseenMessages: unseenMessages
        )
    }
    
    func parseEmailHeaders(from responses: [IMAPResponseType]) -> [EmailHeader] {
        var headers: [EmailHeader] = []
        
        for response in responses {
            if case .untagged(let data) = response {
                if case .fetch(let fetchData) = data {
                    if let header = parseEmailHeader(from: fetchData) {
                        headers.append(header)
                    }
                }
            }
        }
        
        return headers
    }
    
    private func parseEmailHeader(from fetchData: [String: Any]) -> EmailHeader? {
        guard let messageIDStr = fetchData["messageID"] as? String,
              let messageID = Int(messageIDStr) else {
            return nil
        }
        
        let envelope = fetchData["envelope"] as? String ?? ""
        let flagsStr = fetchData["flags"] as? String ?? ""
        
        let parsedEnvelope = parseEnvelope(envelope)
        
        let isRead = flagsStr.contains("\\Seen")
        let isStarred = flagsStr.contains("\\Flagged")
        
        return EmailHeader(
            messageID: String(messageID),
            from: parsedEnvelope.from,
            subject: parsedEnvelope.subject,
            date: parsedEnvelope.date,
            to: parsedEnvelope.to,
            cc: parsedEnvelope.cc,
            isRead: isRead,
            isStarred: isStarred
        )
    }
    
    private func parseEnvelope(_ envelope: String) -> (from: String, subject: String, date: Date, to: String?, cc: String?) {
        var from = ""
        var subject = ""
        var date = Date()
        var to: String?
        var cc: String?
        
        if let fromMatch = envelope.range(of: #"\"([^\"]+)\""#, options: .regularExpression) {
            from = String(envelope[fromMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        
        if let subjectMatch = envelope.range(of: #"\"([^\"]*)\""#, options: .regularExpression) {
            subject = String(envelope[subjectMatch]).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        }
        
        return (from, subject, date, to, cc)
    }
    
    func parseMessageIDs(from responses: [IMAPResponseType]) -> [MessageID] {
        var ids: [MessageID] = []
        
        for response in responses {
            if case .untagged(let data) = response {
                if case .search(let searchIds) = data {
                    ids = searchIds.map { MessageID($0) }
                }
            }
        }
        
        return ids
    }
    
    func parseAttachments(from responses: [IMAPResponseType], messageID: String) -> [AttachmentInfo] {
        return []
    }
    
    func parseBody(from responses: [IMAPResponseType], messageID: String) -> EmailBody? {
        return EmailBody(messageID: messageID)
    }
}
