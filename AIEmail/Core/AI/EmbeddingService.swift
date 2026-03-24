import Foundation

// MARK: - Embedding Service

final class EmbeddingService: Sendable, EmbeddingServiceProtocol {
    private let openAIClient: OpenAIClient
    let dimension: Int
    
    init(openAIClient: OpenAIClient, dimension: Int = AIConfig.embeddingDimension) {
        self.openAIClient = openAIClient
        self.dimension = dimension
    }
    
    convenience init() {
        guard let client = OpenAIClient.shared else {
            fatalError("OpenAIClient not configured. Call OpenAIClient.configure(with:) first.")
        }
        self.init(openAIClient: client)
    }
    
    func embed(text: String) async throws -> [Float] {
        let embedding = try await openAIClient.createEmbedding(
            text: text,
            model: AIConfig.embeddingModel
        )
        
        guard embedding.count == dimension else {
            throw AIError.invalidResponse
        }
        
        return embedding
    }
    
    func generateEmbedding(for text: String) async throws -> [Float] {
        return try await embed(text: text)
    }
    
    func embedBatch(texts: [String]) async throws -> [[Float]] {
        var results: [[Float]] = []
        
        for text in texts {
            let embedding = try await embed(text: text)
            results.append(embedding)
        }
        
        return results
    }
    
    func normalize(_ vector: [Float]) -> [Float] {
        let magnitude = sqrt(vector.reduce(0) { $0 + $1 * $1 })
        
        guard magnitude > 0 else {
            return vector
        }
        
        return vector.map { $0 / magnitude }
    }
    
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else {
            return 0
        }
        
        var dotProduct: Float = 0
        var magnitudeA: Float = 0
        var magnitudeB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            magnitudeA += a[i] * a[i]
            magnitudeB += b[i] * b[i]
        }
        
        let magnitudeProduct = sqrt(magnitudeA) * sqrt(magnitudeB)
        
        guard magnitudeProduct > 0 else {
            return 0
        }
        
        return dotProduct / magnitudeProduct
    }
    
    func cosineSimilarityWithNormalized(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else {
            return 0
        }
        
        var dotProduct: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
        }
        
        return dotProduct
    }
    
    func euclideanDistance(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count else {
            return Float.greatestFiniteMagnitude
        }
        
        var sum: Float = 0
        
        for i in 0..<a.count {
            let diff = a[i] - b[i]
            sum += diff * diff
        }
        
        return sqrt(sum)
    }
    
    func findMostSimilar(
        query: [Float],
        candidates: [[Float]],
        topK: Int = 5
    ) -> [(index: Int, score: Float)] {
        let normalizedQuery = normalize(query)
        let normalizedCandidates = candidates.map { normalize($0) }
        
        var similarities: [(index: Int, score: Float)] = []
        
        for (index, candidate) in normalizedCandidates.enumerated() {
            let score = cosineSimilarityWithNormalized(normalizedQuery, candidate)
            similarities.append((index: index, score: score))
        }
        
        similarities.sort { $0.score > $1.score }
        
        return Array(similarities.prefix(topK))
    }
}
