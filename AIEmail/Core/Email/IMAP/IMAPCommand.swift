import Foundation

enum IMAPCommand: Sendable {
    case login(username: String, password: String)
    case select(folder: String)
    case examine(folder: String)
    case create(folder: String)
    case delete(folder: String)
    case rename(oldFolder: String, newFolder: String)
    case list(reference: String, pattern: String)
    case lsub(reference: String, pattern: String)
    case search(charset: String?, criteria: String)
    case fetch(ids: [String], items: [String])
    case store(ids: [String], flags: [String])
    case copy(ids: [String], folder: String)
    case move(ids: [String], folder: String)
    case expunge
    case check
    case logout
    case capability
    case noop
    
    var tag: String {
        return CommandTagGenerator.next()
    }
    
    var commandString: String {
        switch self {
        case .login(let username, let password):
            return "LOGIN \"\(escapeString(username))\" \"\(escapeString(password))\""
        case .select(let folder):
            return "SELECT \"\(escapeString(folder))\""
        case .examine(let folder):
            return "EXAMINE \"\(escapeString(folder))\""
        case .create(let folder):
            return "CREATE \"\(escapeString(folder))\""
        case .delete(let folder):
            return "DELETE \"\(escapeString(folder))\""
        case .rename(let oldFolder, let newFolder):
            return "RENAME \"\(escapeString(oldFolder))\" \"\(escapeString(newFolder))\""
        case .list(let reference, let pattern):
            return "LIST \"\(escapeString(reference))\" \"\(escapeString(pattern))\""
        case .lsub(let reference, let pattern):
            return "LSUB \"\(escapeString(reference))\" \"\(escapeString(pattern))\""
        case .search(let charset, let criteria):
            if let charset = charset {
                return "SEARCH CHARSET \"\(charset)\" \(criteria)"
            }
            return "SEARCH \(criteria)"
        case .fetch(let ids, let items):
            return "FETCH \(idList(ids)) \(items.joined(separator: " "))"
        case .store(let ids, let flags):
            return "STORE \(idList(ids)) \(flags.joined(separator: " "))"
        case .copy(let ids, let folder):
            return "COPY \(idList(ids)) \"\(escapeString(folder))\""
        case .move(let ids, let folder):
            return "MOVE \(idList(ids)) \"\(escapeString(folder))\""
        case .expunge:
            return "EXPUNGE"
        case .check:
            return "CHECK"
        case .logout:
            return "LOGOUT"
        case .capability:
            return "CAPABILITY"
        case .noop:
            return "NOOP"
        }
    }
    
    private func escapeString(_ str: String) -> String {
        return str.replacingOccurrences(of: "\\", with: "\\\\")
                  .replacingOccurrences(of: "\"", with: "\\\"")
    }
    
    private func idList(_ ids: [String]) -> String {
        if ids.count == 1 {
            return ids[0]
        }
        return ids.joined(separator: ",")
    }
}

final class CommandTagGenerator: @unchecked Sendable {
    private static var counter: Int = 0
    private static let lock = NSLock()
    
    static func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        counter += 1
        return "A\(String(format: "%04d", counter))"
    }
    
    static func reset() {
        lock.lock()
        defer { lock.unlock() }
        counter = 0
    }
}

extension IMAPCommand {
    static func fetchMessageHeaders(ids: [String]) -> IMAPCommand {
        return .fetch(ids: ids, items: ["ENVELOPE", "FLAGS", "INTERNALDATE"])
    }
    
    static func fetchMessageBody(ids: [String]) -> IMAPCommand {
        return .fetch(ids: ids, items: ["BODY[TEXT]", "BODY[HEADER]"])
    }
    
    static func fetchAttachmentsInfo(ids: [String]) -> IMAPCommand {
        return .fetch(ids: ids, items: ["BODYSTRUCTURE"])
    }
    
    static func searchSince(date: Date) -> IMAPCommand {
        let formatter = DateFormatter()
        formatter.dateFormat = "dd-MMM-yyyy"
        let dateString = formatter.string(from: date)
        return .search(charset: nil, criteria: "SINCE \(dateString)")
    }
    
    static func searchUnread() -> IMAPCommand {
        return .search(charset: nil, criteria: "UNSEEN")
    }
    
    static func setFlags(ids: [String], flags: [MessageFlag], mode: FlagMode) -> IMAPCommand {
        let flagStrings = flags.map { $0.imapString }
        let items: String
        switch mode {
        case .set:
            items = "FLAGS (\(flagStrings.joined(separator: " ")))"
        case .add:
            items = "+FLAGS (\(flagStrings.joined(separator: " ")))"
        case .remove:
            items = "-FLAGS (\(flagStrings.joined(separator: " ")))"
        }
        return .store(ids: ids, flags: [items])
    }
    
    enum FlagMode {
        case set
        case add
        case remove
    }
}
