import Foundation
import Security

// MARK: - AI Configuration

struct AIConfig {
    static let apiKeyKey = "openai_api_key"
    static let defaultModel = "gpt-4o-mini"
    static let embeddingModel = "text-embedding-3-small"
    static let embeddingDimension = 1536
    
    static let maxRetries = 3
    static let retryDelay: TimeInterval = 1.0
    static let requestTimeout: TimeInterval = 30.0
    
    static let maxTokensForSummary = 1000
    static let maxTokensForReply = 500
    static let summaryTemperature = 0.7
    static let replyTemperature = 0.7
    
    static let cacheExpiration: TimeInterval = 3600 // 1 hour
}

// MARK: - AI Error

enum AIError: Error, LocalizedError {
    case missingAPIKey
    case invalidResponse
    case rateLimitExceeded
    case quotaExceeded
    case networkError(Error)
    case serverError(Int, String)
    case encodingError
    case decodingError(String)
    case cacheError(String)
    case invalidModel(String)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured"
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .quotaExceeded:
            return "API quota exceeded. Please check your plan."
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .encodingError:
            return "Failed to encode request"
        case .decodingError(let details):
            return "Failed to decode response: \(details)"
        case .cacheError(let details):
            return "Cache error: \(details)"
        case .invalidModel(let model):
            return "Invalid model: \(model)"
        }
    }
    
    var isRetryable: Bool {
        switch self {
        case .rateLimitExceeded, .networkError:
            return true
        case .serverError(let code, _):
            return code >= 500
        default:
            return false
        }
    }
}

// MARK: - Keychain Helper

enum KeychainHelper {
    static func save(key: String, value: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw AIError.encodingError
        }
        
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        
        SecItemDelete(query as CFDictionary)
        
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw AIError.cacheError("Failed to save to Keychain: \(status)")
        }
    }
    
    static func load(key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        
        guard status == errSecSuccess,
              let data = result as? Data,
              let string = String(data: data, encoding: .utf8) else {
            return nil
        }
        
        return string
    }
    
    static func delete(key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrAccount as String: key
        ]
        
        SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Usage Stats

struct UsageStats: Sendable {
    let totalTokensUsed: Int
    let promptTokens: Int
    let completionTokens: Int
    let embeddingTokens: Int
    let totalCost: Double
    let remainingQuota: Int?
    let resetDate: Date?
    
    static let zero = UsageStats(
        totalTokensUsed: 0,
        promptTokens: 0,
        completionTokens: 0,
        embeddingTokens: 0,
        totalCost: 0,
        remainingQuota: nil,
        resetDate: nil
    )
}
