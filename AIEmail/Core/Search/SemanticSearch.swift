import Foundation

final class SemanticSearch {
    
    private let database: SearchDatabase
    private let embeddingService: EmbeddingServiceProtocol
    
    struct SemanticResult: Identifiable {
        let id: String
        let emailID: String
        let subject: String
        let snippet: String
        let similarity: Float
        
        init(emailID: String, subject: String, snippet: String, similarity: Float) {
            self.id = emailID
            self.emailID = emailID
            self.subject = subject
            self.snippet = snippet
            self.similarity = similarity
        }
    }
    
    init(database: SearchDatabase, embeddingService: EmbeddingServiceProtocol) {
        self.database = database
        self.embeddingService = embeddingService
    }
    
    func indexEmail(_ email: EmailRecord) async throws {
        let textContent = buildTextContent(for: email)
        let embedding = try await embeddingService.generateEmbedding(for: textContent)
        try database.saveEmbedding(emailID: email.id, embedding: embedding)
    }
    
    func indexEmails(_ emails: [EmailRecord]) async throws {
        for email in emails {
            try await indexEmail(email)
        }
    }
    
    func search(query: String, limit: Int = 50) async throws -> [SemanticResult] {
        let queryEmbedding = try await embeddingService.generateEmbedding(for: query)
        return try await searchWithEmbedding(queryEmbedding, limit: limit)
    }
    
    private func searchWithEmbedding(_ queryEmbedding: [Float], limit: Int) async throws -> [SemanticResult] {
        let emailIDs = try database.getAllEmailIDsWithMissingEmbeddings()
        var results: [(emailID: String, embedding: [Float])] = []
        
        for emailID in emailIDs {
            if let embedding = try database.getEmbedding(emailID: emailID) {
                results.append((emailID, embedding))
            }
        }
        
        let scoredResults = results.map { (emailID, embedding) -> (String, Float) in
            let similarity = cosineSimilarity(queryEmbedding, embedding)
            return (emailID, similarity)
        }
        .sorted { $0.1 > $1.1 }
        .prefix(limit)
        
        var semanticResults: [SemanticResult] = []
        for (emailID, similarity) in scoredResults {
            if let email = try database.getEmail(id: emailID) {
                let snippet = email.preview ?? String((email.textBody ?? "").prefix(200))
                semanticResults.append(SemanticResult(
                    emailID: emailID,
                    subject: email.subject ?? "",
                    snippet: snippet,
                    similarity: similarity
                ))
            }
        }
        
        return semanticResults
    }
    
    func cosineSimilarity(_ a: [Float], _ b: [Float]) -> Float {
        guard a.count == b.count, !a.isEmpty else { return 0 }
        
        var dotProduct: Float = 0
        var normA: Float = 0
        var normB: Float = 0
        
        for i in 0..<a.count {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }
        
        let denominator = sqrt(normA) * sqrt(normB)
        guard denominator > 0 else { return 0 }
        
        return dotProduct / denominator
    }
    
    private func buildTextContent(for email: EmailRecord) -> String {
        var parts: [String] = []
        
        if let subject = email.subject {
            parts.append(subject)
        }
        parts.append(email.from)
        parts.append(email.to.joined(separator: ", "))
        if let textBody = email.textBody {
            parts.append(textBody)
        }
        
        return parts.joined(separator: " ")
    }
}
