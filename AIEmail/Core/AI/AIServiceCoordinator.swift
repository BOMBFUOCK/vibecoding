import Foundation

// MARK: - AI Processing Result

struct AIProcessingResult: Sendable {
    let summary: String
    let replyDraft: String?
    let embedding: [Float]
    
    static let empty = AIProcessingResult(
        summary: "",
        replyDraft: nil,
        embedding: []
    )
}

// MARK: - AI Service Coordinator

final class AIServiceCoordinator: Sendable {
    private let summarizer: AISummarizer
    private let replyGenerator: AIReplyGenerator
    private let embeddingService: EmbeddingService
    
    init(openAIClient: OpenAIClient) {
        self.summarizer = AISummarizer(openAIClient: openAIClient)
        self.replyGenerator = AIReplyGenerator(openAIClient: openAIClient)
        self.embeddingService = EmbeddingService(openAIClient: openAIClient)
    }
    
    convenience init() {
        guard let client = OpenAIClient.shared else {
            fatalError("OpenAIClient not configured. Call OpenAIClient.configure(with:) first.")
        }
        self.init(openAIClient: client)
    }
    
    func processEmail(_ email: Email) async throws -> AIProcessingResult {
        async let summaryTask = summarizer.summarize(email: email)
        async let embeddingTask = embeddingService.embed(text: email.displayText)
        
        let (summary, embedding) = try await (summaryTask, embeddingTask)
        
        let replyDraft = try? await replyGenerator.generateReply(
            originalEmail: email,
            tone: .professional,
            includePreviousContext: true
        )
        
        return AIProcessingResult(
            summary: summary,
            replyDraft: replyDraft,
            embedding: embedding
        )
    }
    
    func processEmailWithoutReply(_ email: Email) async throws -> AIProcessingResult {
        async let summaryTask = summarizer.summarize(email: email)
        async let embeddingTask = embeddingService.embed(text: email.displayText)
        
        let (summary, embedding) = try await (summaryTask, embeddingTask)
        
        return AIProcessingResult(
            summary: summary,
            replyDraft: nil,
            embedding: embedding
        )
    }
    
    func summarizeOnly(_ email: EmailRecord) async throws -> String {
        let text = email.textBody ?? email.preview ?? email.subject ?? ""
        return try await summarizer.summarizeText(text)
    }
    
    func summarizeConversation(_ emails: [EmailRecord]) async throws -> String {
        let texts = emails.compactMap { $0.textBody ?? $0.preview ?? $0.subject }
        return try await summarizer.summarizeTexts(texts)
    }
    
    func generateReplyOnly(
        _ email: EmailRecord,
        tone: ReplyTone = .professional
    ) async throws -> String {
        let text = email.textBody ?? email.preview ?? email.subject ?? ""
        return try await replyGenerator.generateReplyFromText(
            text: text,
            tone: tone
        )
    }
    
    func embedOnly(_ text: String) async throws -> [Float] {
        try await embeddingService.embed(text: text)
    }
    
    func embedBatch(_ texts: [String]) async throws -> [[Float]] {
        try await embeddingService.embedBatch(texts: texts)
    }
    
    func getEmbeddingService() -> EmbeddingService {
        return embeddingService
    }
    
    func getSummarizer() -> AISummarizer {
        return summarizer
    }
    
    func getReplyGenerator() -> AIReplyGenerator {
        return replyGenerator
    }
}

// MARK: - Usage Stats

extension AIServiceCoordinator {
    func getUsageStats() async throws -> UsageStats {
        return UsageStats.zero
    }
}
