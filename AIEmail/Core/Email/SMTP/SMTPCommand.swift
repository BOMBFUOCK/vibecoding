import Foundation

enum SMTPCommand: Sendable {
    case helo(String)
    case ehlo(String)
    case authPlain(String)
    case authLogin
    case authLoginUsername(String)
    case authLoginPassword(String)
    case mailFrom(String)
    case mailFromWithSize(String, Int)
    case rcptTo(String)
    case data
    case dataEnd
    case rset
    case vrfy(String)
    case expn(String)
    case help(String?)
    case starttls
    case noop
    case quit
    
    var bytes: [UInt8] {
        switch self {
        case .helo(let domain):
            return Array("HELO \(domain)\r\n".utf8)
        case .ehlo(let domain):
            return Array("EHLO \(domain)\r\n".utf8)
        case .authPlain(let credentials):
            let base64 = Data(credentials.utf8).base64EncodedString()
            return Array("AUTH PLAIN \(base64)\r\n".utf8)
        case .authLogin:
            return Array("AUTH LOGIN\r\n".utf8)
        case .authLoginUsername(let username):
            let base64 = Data(username.utf8).base64EncodedString()
            return Array("\(base64)\r\n".utf8)
        case .authLoginPassword(let password):
            let base64 = Data(password.utf8).base64EncodedString()
            return Array("\(base64)\r\n".utf8)
        case .mailFrom(let address):
            return Array("MAIL FROM:<\(address)>\r\n".utf8)
        case .mailFromWithSize(let address, let size):
            return Array("MAIL FROM:<\(address)> SIZE=\(size)\r\n".utf8)
        case .rcptTo(let address):
            return Array("RCPT TO:<\(address)>\r\n".utf8)
        case .data:
            return Array("DATA\r\n".utf8)
        case .dataEnd:
            return Array("\r\n.\r\n".utf8)
        case .rset:
            return Array("RSET\r\n".utf8)
        case .vrfy(let address):
            return Array("VRFY \(address)\r\n".utf8)
        case .expn(let address):
            return Array("EXPN \(address)\r\n".utf8)
        case .help(let argument):
            if let arg = argument {
                return Array("HELP \(arg)\r\n".utf8)
            }
            return Array("HELP\r\n".utf8)
        case .starttls:
            return Array("STARTTLS\r\n".utf8)
        case .noop:
            return Array("NOOP\r\n".utf8)
        case .quit:
            return Array("QUIT\r\n".utf8)
        }
    }
    
    var data: Data {
        Data(bytes)
    }
    
    var string: String? {
        String(bytes: bytes, encoding: .utf8)
    }
}

struct SMTPAuthCredentials {
    let username: String
    let password: String
    
    func plainCredential() -> String {
        "\u{0000}\(username)\u{0000}\(password)"
    }
}
