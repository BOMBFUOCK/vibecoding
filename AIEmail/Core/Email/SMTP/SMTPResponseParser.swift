import Foundation

final class SMTPResponseParser: @unchecked Sendable {
    
    func parse(_ data: Data) -> SMTPResponse? {
        guard let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        return parse(string)
    }
    
    func parse(_ responseString: String) -> SMTPResponse? {
        let lines = responseString.split(separator: "\r\n", omittingEmptySubsequences: false).map(String.init)
        guard !lines.isEmpty else { return nil }
        
        var messages: [String] = []
        var code: Int?
        var isIntermediate = false
        
        for (index, line) in lines.enumerated() {
            guard line.count >= 4 else { continue }
            
            let lineCode: Int
            if let parsedCode = Int(line.prefix(3)) {
                lineCode = parsedCode
            } else {
                continue
            }
            
            if index == 0 {
                code = lineCode
                isIntermediate = line.count > 3 && line[line.index(line.startIndex, offsetBy: 3)] == "-"
            }
            
            let messageContent: String
            if line.count > 4 {
                messageContent = String(line.dropFirst(4))
            } else {
                messageContent = ""
            }
            messages.append(messageContent)
        }
        
        guard let responseCode = code else { return nil }
        
        return SMTPResponse(code: responseCode, message: messages, isIntermediate: isIntermediate)
    }
    
    func parseehloExtensions(_ response: SMTPResponse) -> [String: [String]] {
        var extensions: [String: [String]] = [:]
        
        for (index, line) in response.message.enumerated() {
            guard index > 0, !line.isEmpty else { continue }
            
            let parts = line.split(separator: " ").map(String.init)
            guard let key = parts.first else { continue }
            
            if parts.count > 1 {
                extensions[key] = Array(parts.dropFirst())
            } else {
                extensions[key] = []
            }
        }
        
        return extensions
    }
    
    func extractMessageID(from response: SMTPResponse) -> String? {
        for line in response.message {
            let pattern = "<(.+)>"
            if let regex = try? NSRegularExpression(pattern: pattern),
               let match = regex.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)),
               let range = Range(match.range(at: 1), in: line) {
                return String(line[range])
            }
        }
        return nil
    }
    
    func extractAddresses(from response: SMTPResponse) -> [String] {
        var addresses: [String] = []
        
        for line in response.message {
            let pattern = "<(.+@.+)>"
            if let regex = try? NSRegularExpression(pattern: pattern) {
                let matches = regex.matches(in: line, range: NSRange(line.startIndex..., in: line))
                for match in matches {
                    if let range = Range(match.range(at: 1), in: line) {
                        addresses.append(String(line[range]))
                    }
                }
            }
        }
        
        return addresses
    }
    
    func isSuccessResponse(_ code: Int) -> Bool {
        code >= 200 && code < 400
    }
    
    func isIntermediateResponse(_ code: Int) -> Bool {
        code >= 300 && code < 400
    }
    
    func isErrorResponse(_ code: Int) -> Bool {
        code >= 400
    }
    
    func isPositiveCompletion(_ code: Int) -> Bool {
        code >= 200 && code < 300
    }
    
    func isPositiveIntermediate(_ code: Int) -> Bool {
        code >= 300 && code < 400
    }
}
