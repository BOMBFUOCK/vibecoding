import Foundation

// MARK: - Chat Message

struct ChatMessage: Sendable, Codable {
    let role: String
    let content: String
    
    init(role: String, content: String) {
        self.role = role
        self.content = content
    }
    
    static func system(_ content: String) -> ChatMessage {
        ChatMessage(role: "system", content: content)
    }
    
    static func user(_ content: String) -> ChatMessage {
        ChatMessage(role: "user", content: content)
    }
    
    static func assistant(_ content: String) -> ChatMessage {
        ChatMessage(role: "assistant", content: content)
    }
}

// MARK: - API Request/Response Types

private struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int
    let stream: Bool
    
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature, stream
        case maxTokens = "max_tokens"
    }
}

private struct ChatCompletionResponse: Codable {
    let id: String
    let choices: [Choice]
    let usage: Usage?
    
    struct Choice: Codable {
        let message: Message
        
        struct Message: Codable {
            let role: String
            let content: String
        }
    }
    
    struct Usage: Codable {
        let promptTokens: Int
        let completionTokens: Int
        let totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

private struct EmbeddingRequest: Codable {
    let model: String
    let input: String
    
    enum CodingKeys: String, CodingKey {
        case model, input
    }
}

private struct EmbeddingResponse: Codable {
    let data: [EmbeddingData]
    let usage: Usage
    
    struct EmbeddingData: Codable {
        let embedding: [Float]
        let index: Int
    }
    
    struct Usage: Codable {
        let promptTokens: Int
        let totalTokens: Int
        
        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case totalTokens = "total_tokens"
        }
    }
}

// MARK: - OpenAI Client

final class OpenAIClient: Sendable {
    private let apiKey: String
    private let baseURL = "https://api.openai.com/v1"
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let cache: NSCache<NSString, CachedResponse>
    
    static var shared: OpenAIClient?
    
    init(apiKey: String) {
        self.apiKey = apiKey
        
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = AIConfig.requestTimeout
        config.timeoutIntervalForResource = AIConfig.requestTimeout * 2
        self.session = URLSession(configuration: config)
        
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
        
        self.cache = NSCache()
        self.cache.countLimit = 100
    }
    
    convenience init?(apiKey: String?) {
        guard let key = apiKey, !key.isEmpty else { return nil }
        self.init(apiKey: key)
    }
    
    static func configure(with apiKey: String) {
        shared = OpenAIClient(apiKey: apiKey)
    }
    
    static func configureFromKeychain() -> Bool {
        guard let apiKey = KeychainHelper.load(key: AIConfig.apiKeyKey) else {
            return false
        }
        configure(with: apiKey)
        return true
    }
    
    static func saveAPIKey(_ apiKey: String) throws {
        try KeychainHelper.save(key: AIConfig.apiKeyKey, value: apiKey)
        configure(with: apiKey)
    }
    
    static func clearAPIKey() {
        KeychainHelper.delete(key: AIConfig.apiKeyKey)
        shared = nil
    }
    
    // MARK: - Chat Completion
    
    func chatCompletion(
        messages: [ChatMessage],
        model: String = AIConfig.defaultModel,
        temperature: Double = 0.7,
        maxTokens: Int = 1000
    ) async throws -> String {
        let request = ChatCompletionRequest(
            model: model,
            messages: messages,
            temperature: temperature,
            maxTokens: maxTokens,
            stream: false
        )
        
        let data = try await performRequest(
            endpoint: "/chat/completions",
            method: "POST",
            body: request,
            cacheKey: cacheKey(for: messages, model: model)
        )
        
        let response = try decoder.decode(ChatCompletionResponse.self, from: data)
        
        guard let content = response.choices.first?.message.content else {
            throw AIError.invalidResponse
        }
        
        return content
    }
    
    // MARK: - Embedding
    
    func createEmbedding(
        text: String,
        model: String = AIConfig.embeddingModel
    ) async throws -> [Float] {
        let request = EmbeddingRequest(model: model, input: text)
        
        let data = try await performRequest(
            endpoint: "/embeddings",
            method: "POST",
            body: request,
            cacheKey: cacheKey(for: text, model: model)
        )
        
        let response = try decoder.decode(EmbeddingResponse.self, from: data)
        
        guard let embedding = response.data.first?.embedding else {
            throw AIError.invalidResponse
        }
        
        return embedding
    }
    
    // MARK: - Private Helpers
    
    private func performRequest<T: Encodable>(
        endpoint: String,
        method: String,
        body: T,
        cacheKey: String? = nil
    ) async throws -> Data {
        guard !apiKey.isEmpty else {
            throw AIError.missingAPIKey
        }
        
        if let key = cacheKey, let cached = cache.object(forKey: key as NSString) {
            return cached.data
        }
        
        let url = URL(string: baseURL + endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            throw AIError.encodingError
        }
        
        var lastError: Error = AIError.invalidResponse
        var retryCount = 0
        
        while retryCount <= AIConfig.maxRetries {
            do {
                let (data, response) = try await session.data(for: request)
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    throw AIError.invalidResponse
                }
                
                switch httpResponse.statusCode {
                case 200...299:
                    if let key = cacheKey {
                        let cached = CachedResponse(data: data, timestamp: Date())
                        cache.setObject(cached, forKey: key as NSString)
                    }
                    return data
                    
                case 429:
                    let error = try? decoder.decode(ErrorResponse.self, from: data)
                    if error?.error?.code == "rate_limit_exceeded" {
                        throw AIError.rateLimitExceeded
                    }
                    throw AIError.rateLimitExceeded
                    
                case 400...499:
                    let errorResponse = try? decoder.decode(ErrorResponse.self, from: data)
                    let message = errorResponse?.error?.message ?? "Unknown client error"
                    if httpResponse.statusCode == 401 {
                        throw AIError.missingAPIKey
                    }
                    throw AIError.serverError(httpResponse.statusCode, message)
                    
                case 500...599:
                    let errorResponse = try? decoder.decode(ErrorResponse.self, from: data)
                    let message = errorResponse?.error?.message ?? "Unknown server error"
                    throw AIError.serverError(httpResponse.statusCode, message)
                    
                default:
                    throw AIError.serverError(httpResponse.statusCode, "Unexpected status code")
                }
                
            } catch let error as AIError {
                if error.isRetryable && retryCount < AIConfig.maxRetries {
                    retryCount += 1
                    lastError = error
                    try await Task.sleep(nanoseconds: UInt64(AIConfig.retryDelay * Double(retryCount) * 1_000_000_000))
                    continue
                }
                throw error
                
            } catch {
                if retryCount < AIConfig.maxRetries {
                    retryCount += 1
                    lastError = error
                    try await Task.sleep(nanoseconds: UInt64(AIConfig.retryDelay * Double(retryCount) * 1_000_000_000))
                    continue
                }
                throw AIError.networkError(error)
            }
        }
        
        throw lastError
    }
    
    private func cacheKey(for messages: [ChatMessage], model: String) -> String {
        let content = messages.map { "\($0.role): \($0.content)" }.joined(separator: "|")
        return "chat:\(model):\(content.hashValue)"
    }
    
    private func cacheKey(for text: String, model: String) -> String {
        return "embed:\(model):\(text.hashValue)"
    }
}

// MARK: - Error Response

private struct ErrorResponse: Codable {
    let error: ErrorDetail?
    
    struct ErrorDetail: Codable {
        let message: String
        let code: String?
    }
}

// MARK: - Cache

private final class CachedResponse: NSObject {
    let data: Data
    let timestamp: Date
    
    init(data: Data, timestamp: Date) {
        self.data = data
        self.timestamp = timestamp
    }
    
    var isExpired: Bool {
        Date().timeIntervalSince(timestamp) > AIConfig.cacheExpiration
    }
}
