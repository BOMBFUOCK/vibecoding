import Foundation

final class AIService {
    static let shared = AIService()
    
    private let baseURL = "https://api.openai.com/v1"
    private let session: URLSession
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private var apiKey: String?
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        self.session = URLSession(configuration: config)
        self.decoder = JSONDecoder()
        self.encoder = JSONEncoder()
    }
    
    func configure(apiKey: String) {
        self.apiKey = apiKey
    }
    
    func configureFromDatabase() throws {
        if let key = try DatabaseService.shared.getAPIKey() {
            self.apiKey = key
        }
    }
    
    func summarize(email: EmailInfo) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        
        let systemPrompt = """
        你是一个专业的邮件摘要助手。请为邮件生成简洁、准确的摘要。
        要求：
        1. 摘要长度不超过 50 字
        2. 包含邮件的核心内容
        3. 突出重要的 action items 或截止日期
        4. 使用用户的语言
        请直接输出摘要，不要有多余的解释。
        """
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let dateString = dateFormatter.string(from: email.date)
        let content = email.textBody ?? email.preview ?? "(无正文内容)"
        
        let userPrompt = """
        请为以下邮件生成摘要：
        
        发件人：\(email.from)
        主题：\(email.subject ?? "(无主题)")
        日期：\(dateString)
        
        内容：
        \(content)
        
        摘要：
        """
        
        return try await chatCompletion(
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ],
            apiKey: apiKey
        )
    }
    
    func generateReply(email: EmailInfo, tone: ReplyTone) async throws -> String {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        
        let toneInstruction: String
        switch tone {
        case .professional:
            toneInstruction = "使用专业、正式的语气。保持礼貌和尊重。"
        case .casual:
            toneInstruction = "使用轻松、友好的语气。可以适当随意但保持礼貌。"
        case .brief:
            toneInstruction = "保持回复简洁明了，直切主题，不需要过多的客套话。"
        }
        
        let systemPrompt = """
        你是一个专业的邮件回复助手。请根据原邮件内容生成合适的回复草稿。
        要求：
        1. 回复简洁、专业、有礼貌
        2. 适当引用原邮件中的关键信息
        3. 如果原邮件有明确的 action items，在回复中确认收到并说明你会处理
        4. 根据邮件的语气调整回复风格
        
        \(toneInstruction)
        
        请直接生成回复草稿，不要有多余的解释。
        """
        
        let dateFormatter = DateFormatter()
        dateFormatter.dateStyle = .medium
        dateFormatter.timeStyle = .short
        
        let dateString = dateFormatter.string(from: email.date)
        let content = email.textBody ?? email.preview ?? "(无正文内容)"
        
        let userPrompt = """
        请为以下邮件生成回复：
        
        发件人：\(email.from)
        主题：\(email.subject ?? "(无主题)")
        日期：\(dateString)
        
        原邮件内容：
        \(content)
        
        回复草稿：
        """
        
        return try await chatCompletion(
            messages: [
                ChatMessage(role: "system", content: systemPrompt),
                ChatMessage(role: "user", content: userPrompt)
            ],
            apiKey: apiKey
        )
    }
    
    func batchSummarize(emails: [EmailInfo]) async throws -> [String: String] {
        guard let apiKey = apiKey, !apiKey.isEmpty else {
            throw AIServiceError.missingAPIKey
        }
        
        var results: [String: String] = [:]
        
        for email in emails {
            do {
                let summary = try await summarize(email: email)
                results[email.id] = summary
            } catch {
                results[email.id] = "Error: \(error.localizedDescription)"
            }
        }
        
        return results
    }
    
    private func chatCompletion(messages: [ChatMessage], apiKey: String) async throws -> String {
        let request = ChatCompletionRequest(
            model: "gpt-4o-mini",
            messages: messages,
            temperature: 0.7,
            maxTokens: 1000
        )
        
        let data = try await performRequest(
            endpoint: "/chat/completions",
            method: "POST",
            body: request,
            apiKey: apiKey
        )
        
        let response = try decoder.decode(ChatCompletionResponse.self, from: data)
        
        guard let content = response.choices.first?.message.content else {
            throw AIServiceError.invalidResponse
        }
        
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func performRequest<T: Encodable, R: Decodable>(
        endpoint: String,
        method: String,
        body: T,
        apiKey: String
    ) async throws -> Data {
        let url = URL(string: baseURL + endpoint)!
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        
        request.httpBody = try encoder.encode(body)
        
        let (data, response) = try await session.data(for: request)
        
        guard let httpResponse = response as? HTTPURLResponse else {
            throw AIServiceError.invalidResponse
        }
        
        switch httpResponse.statusCode {
        case 200...299:
            return data
        case 401:
            throw AIServiceError.invalidAPIKey
        case 429:
            throw AIServiceError.rateLimitExceeded
        default:
            let errorResponse = try? decoder.decode(ErrorResponse.self, from: data)
            let message = errorResponse?.error?.message ?? "Unknown error"
            throw AIServiceError.serverError(httpResponse.statusCode, message)
        }
    }
}

struct ChatMessage: Codable {
    let role: String
    let content: String
}

struct ChatCompletionRequest: Codable {
    let model: String
    let messages: [ChatMessage]
    let temperature: Double
    let maxTokens: Int
}

struct ChatCompletionResponse: Codable {
    let choices: [Choice]
    
    struct Choice: Codable {
        let message: Message
        
        struct Message: Codable {
            let content: String
        }
    }
}

struct ErrorResponse: Codable {
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let message: String
    }
}

enum AIServiceError: Error, LocalizedError {
    case missingAPIKey
    case invalidAPIKey
    case invalidResponse
    case rateLimitExceeded
    case serverError(Int, String)
    case networkError(String)
    
    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "OpenAI API key is not configured. Use 'aiemail ai set-api-key' to set it."
        case .invalidAPIKey:
            return "Invalid API key. Please check your OpenAI API key."
        case .invalidResponse:
            return "Invalid response from OpenAI API"
        case .rateLimitExceeded:
            return "Rate limit exceeded. Please try again later."
        case .serverError(let code, let message):
            return "Server error (\(code)): \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        }
    }
}
