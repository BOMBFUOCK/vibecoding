import Foundation

@Observable
class SearchViewModel {
    var query: String = ""
    var results: [SearchResult] = []
    var isSearching: Bool = false
    var searchMode: SearchMode = .hybrid
    var errorMessage: String?
    
    enum SearchMode: String, CaseIterable, Identifiable {
        case hybrid = "混合搜索"
        case semanticOnly = "语义搜索"
        case keywordOnly = "关键词搜索"
        
        var id: String { rawValue }
        
        var icon: String {
            switch self {
            case .hybrid: return "sparkles"
            case .semanticOnly: return "brain"
            case .keywordOnly: return "textformat.abc"
            }
        }
    }
    
    struct SearchResult: Identifiable {
        let id: String
        let email: EmailRecord
        let matchedField: MatchedField
        let snippet: String
        let rank: Float
        
        enum MatchedField {
            case subject
            case body
            case from
            case to
        }
    }
    
    private let mailDatabase: MailDatabase
    private let fullTextSearch: FullTextSearch?
    
    init(mailDatabase: MailDatabase = MailDatabase()) {
        self.mailDatabase = mailDatabase
        self.fullTextSearch = nil
    }
    
    func search() async {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            return
        }
        
        isSearching = true
        errorMessage = nil
        
        do {
            let emailIDs = try mailDatabase.searchFTS(query: query, limit: 50)
            
            var searchResults: [SearchResult] = []
            for emailID in emailIDs {
                if let email = try mailDatabase.getEmail(id: emailID) {
                    let result = SearchResult(
                        id: email.id,
                        email: email,
                        matchedField: .subject,
                        snippet: email.preview ?? "",
                        rank: 1.0
                    )
                    searchResults.append(result)
                }
            }
            
            results = searchResults
        } catch {
            errorMessage = error.localizedDescription
            results = []
        }
        
        isSearching = false
    }
    
    func clearSearch() {
        query = ""
        results = []
        errorMessage = nil
    }
    
    func performSemanticSearch() async {
        guard !query.isEmpty else { return }
        
        isSearching = true
        errorMessage = nil
        
        do {
            let aiCoordinator = AIServiceCoordinator()
            let embedding = try await aiCoordinator.embedOnly(query)
            
            results = []
        } catch {
            errorMessage = error.localizedDescription
        }
        
        isSearching = false
    }
}
