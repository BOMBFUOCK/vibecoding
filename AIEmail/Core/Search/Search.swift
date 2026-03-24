import Foundation
import SQLite3
#if canImport(SwiftUI)
import SwiftUI
#endif

protocol SearchDatabase {
    func searchFTS(query: String, limit: Int) throws -> [FTSResult]
    func getEmail(id: String) throws -> EmailRecord?
    func saveEmbedding(emailID: String, embedding: [Float]) throws
    func getEmbedding(emailID: String) throws -> [Float]?
    func getAllEmailIDsWithMissingEmbeddings() throws -> [String]
}

protocol EmbeddingServiceProtocol {
    func generateEmbedding(for text: String) async throws -> [Float]
}

struct FTSResult {
    let emailID: String
    let subject: String
    let snippet: String
    let matchedField: String
    let rank: Float
}

final class FullTextSearch {
    
    private let database: SearchDatabase
    
    struct SearchResult: Identifiable {
        let id: String
        let emailID: String
        let subject: String
        let snippet: String
        let matchedField: MatchedField
        let rank: Float
        
        init(emailID: String, subject: String, snippet: String, matchedField: MatchedField, rank: Float) {
            self.id = emailID
            self.emailID = emailID
            self.subject = subject
            self.snippet = snippet
            self.matchedField = matchedField
            self.rank = rank
        }
    }
    
    enum MatchedField: String {
        case subject
        case body
        case from
        case to
    }
    
    init(database: SearchDatabase) {
        self.database = database
    }
    
    func search(query: String, limit: Int = 50) throws -> [SearchResult] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        
        let ftsResults = try database.searchFTS(query: query, limit: limit)
        
        return ftsResults.map { result in
            let matchedField: MatchedField
            switch result.matchedField.lowercased() {
            case "subject":
                matchedField = .subject
            case "text_body", "body":
                matchedField = .body
            case "from_address", "from":
                matchedField = .from
            case "to_addresses", "to":
                matchedField = .to
            default:
                matchedField = .body
            }
            
            return SearchResult(
                emailID: result.emailID,
                subject: result.subject,
                snippet: result.snippet,
                matchedField: matchedField,
                rank: result.rank
            )
        }
    }
    
    func highlightMatches(text: String, query: String) -> AttributedString {
        var attributedString = AttributedString(text)
        
        let searchTerms = query
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
        
        for term in searchTerms {
            highlightTerm(term, in: &attributedString)
        }
        
        return attributedString
    }
    
    private func highlightTerm(_ term: String, in attributedString: inout AttributedString) {
        let lowercasedTerm = term.lowercased()
        var searchRange = attributedString.startIndex..<attributedString.endIndex
        
        while let range = attributedString[searchRange].range(of: lowercasedTerm, options: .caseInsensitive) {
            let highlightEnd = attributedString.index(range.lowerBound, offsetByCharacters: term.count)
            attributedString[range].backgroundColor = .yellow
            attributedString[range].foregroundColor = .black
            
            searchRange = highlightEnd..<attributedString.endIndex
        }
    }
}

final class HybridSearchMerger {
    
    struct MergedResult: Identifiable {
        let id: String
        let emailID: String
        let subject: String
        let snippet: String
        let fromAddress: String
        let date: Date
        let ftsScore: Float
        let semanticScore: Float
        let finalScore: Float
        let matchedFields: [String]
        
        init(
            emailID: String,
            subject: String,
            snippet: String,
            fromAddress: String,
            date: Date,
            ftsScore: Float,
            semanticScore: Float,
            finalScore: Float,
            matchedFields: [String]
        ) {
            self.id = emailID
            self.emailID = emailID
            self.subject = subject
            self.snippet = snippet
            self.fromAddress = fromAddress
            self.date = date
            self.ftsScore = ftsScore
            self.semanticScore = semanticScore
            self.finalScore = finalScore
            self.matchedFields = matchedFields
        }
    }
    
    func search(
        query: String,
        ftsSearch: FullTextSearch,
        semanticSearch: SemanticSearch,
        ftsWeight: Float = 0.4,
        semanticWeight: Float = 0.6,
        limit: Int = 50
    ) async throws -> [MergedResult] {
        let ftsResults = try ftsSearch.search(query: query, limit: limit)
        let semanticResults = try await semanticSearch.search(query: query, limit: limit)
        
        return mergeResults(
            ftsResults: ftsResults,
            semanticResults: semanticResults,
            ftsWeight: ftsWeight,
            semanticWeight: semanticWeight
        )
    }
    
    func mergeResults(
        ftsResults: [FullTextSearch.SearchResult],
        semanticResults: [SemanticSearch.SemanticResult],
        ftsWeight: Float,
        semanticWeight: Float
    ) -> [MergedResult] {
        var mergedMap: [String: MergedResult] = [:]
        
        let normalizedFTSScores = normalize(ftsResults.map { $0.rank })
        for (index, ftsResult) in ftsResults.enumerated() {
            let normalizedScore = index < normalizedFTSScores.count ? normalizedFTSScores[index] : 0
            let finalScore = normalizedScore * ftsWeight
            
            mergedMap[ftsResult.emailID] = MergedResult(
                emailID: ftsResult.emailID,
                subject: ftsResult.subject,
                snippet: ftsResult.snippet,
                fromAddress: "",
                date: Date(),
                ftsScore: normalizedScore,
                semanticScore: 0,
                finalScore: finalScore,
                matchedFields: [ftsResult.matchedField.rawValue]
            )
        }
        
        let normalizedSemanticScores = normalize(semanticResults.map { $0.similarity })
        for (index, semanticResult) in semanticResults.enumerated() {
            let normalizedScore = index < normalizedSemanticScores.count ? normalizedSemanticScores[index] : 0
            
            if let existing = mergedMap[semanticResult.emailID] {
                let combinedScore = (existing.ftsScore * ftsWeight) + (normalizedScore * semanticWeight)
                mergedMap[semanticResult.emailID] = MergedResult(
                    emailID: existing.emailID,
                    subject: semanticResult.subject,
                    snippet: semanticResult.snippet,
                    fromAddress: existing.fromAddress,
                    date: existing.date,
                    ftsScore: existing.ftsScore,
                    semanticScore: normalizedScore,
                    finalScore: combinedScore,
                    matchedFields: existing.matchedFields
                )
            } else {
                let finalScore = normalizedScore * semanticWeight
                mergedMap[semanticResult.emailID] = MergedResult(
                    emailID: semanticResult.emailID,
                    subject: semanticResult.subject,
                    snippet: semanticResult.snippet,
                    fromAddress: "",
                    date: Date(),
                    ftsScore: 0,
                    semanticScore: normalizedScore,
                    finalScore: finalScore,
                    matchedFields: []
                )
            }
        }
        
        return mergedMap.values
            .sorted { $0.finalScore > $1.finalScore }
    }
    
    func normalize(_ scores: [Float]) -> [Float] {
        guard let minVal = scores.min(),
              let maxVal = scores.max(),
              maxVal > minVal else {
            return scores.map { _ in 0.5 }
        }
        return scores.map { ($0 - minVal) / (maxVal - minVal) }
    }
}

final class SearchService {
    
    private let fullTextSearch: FullTextSearch
    private let semanticSearch: SemanticSearch
    private let merger: HybridSearchMerger
    
    init(database: SearchDatabase, embeddingService: EmbeddingService) {
        self.fullTextSearch = FullTextSearch(database: database)
        self.semanticSearch = SemanticSearch(database: database, embeddingService: embeddingService)
        self.merger = HybridSearchMerger()
    }
    
    func search(query: String, limit: Int = 50) async throws -> [HybridSearchMerger.MergedResult] {
        return try await merger.search(
            query: query,
            ftsSearch: fullTextSearch,
            semanticSearch: semanticSearch,
            limit: limit
        )
    }
    
    func quickSearch(query: String, limit: Int = 20) throws -> [FullTextSearch.SearchResult] {
        return try fullTextSearch.search(query: query, limit: limit)
    }
    
    func semanticOnlySearch(query: String, limit: Int = 20) async throws -> [SemanticSearch.SemanticResult] {
        return try await semanticSearch.search(query: query, limit: limit)
    }
    
    func rebuildIndex(emails: [EmailRecord]) async throws {
        for email in emails {
            try await semanticSearch.indexEmail(email)
        }
    }
}
