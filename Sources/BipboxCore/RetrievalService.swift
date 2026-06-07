import Foundation

public struct RetrievalQuery: Codable, Equatable, Sendable {
    public var text: String
    public var sourceIDs: [UUID]
    public var kinds: [ItemKind]
    public var statuses: [IndexedItemStatus]
    public var tags: [String]
    public var importedFrom: Date?
    public var importedThrough: Date?
    public var contextIDs: [UUID]
    public var limit: Int

    public init(
        text: String = "",
        sourceIDs: [UUID] = [],
        kinds: [ItemKind] = [],
        statuses: [IndexedItemStatus] = [],
        tags: [String] = [],
        importedFrom: Date? = nil,
        importedThrough: Date? = nil,
        contextIDs: [UUID] = [],
        limit: Int = 50
    ) {
        self.text = text
        self.sourceIDs = sourceIDs
        self.kinds = kinds
        self.statuses = statuses
        self.tags = tags
        self.importedFrom = importedFrom
        self.importedThrough = importedThrough
        self.contextIDs = contextIDs
        self.limit = limit
    }
}

public struct RetrievalResult: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { item.id }
    public var item: IndexedItem
    public var knowledgeItem: KnowledgeItem?
    public var score: Double
    public var explanations: [String]

    public init(
        item: IndexedItem,
        knowledgeItem: KnowledgeItem? = nil,
        score: Double,
        explanations: [String]
    ) {
        self.item = item
        self.knowledgeItem = knowledgeItem
        self.score = score
        self.explanations = explanations
    }
}

public struct RetrievalResults: Codable, Equatable, Sendable {
    public var items: [RetrievalResult]
    public var totalCount: Int

    public init(items: [RetrievalResult], totalCount: Int) {
        self.items = items
        self.totalCount = totalCount
    }
}

public enum RetrievalError: Error, Equatable, LocalizedError {
    case invalidLimit(Int)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let limit):
            "Retrieval limit must be positive: \(limit)."
        }
    }
}

public final class DefaultRetrievalService: RetrievalService {
    private let searchService: SearchService
    private let knowledgeStore: KnowledgeStore?
    private let graphService: KnowledgeGraphService?
    private let vectorIndex: VectorIndex?
    private let embedder: TextEmbedder?
    private let semanticWeight: Double
    private let candidateLimit: Int

    public init(
        searchService: SearchService,
        knowledgeStore: KnowledgeStore? = nil,
        graphService: KnowledgeGraphService? = nil,
        vectorIndex: VectorIndex? = nil,
        embedder: TextEmbedder? = nil,
        semanticWeight: Double = 0,
        candidateLimit: Int = 500
    ) {
        self.searchService = searchService
        self.knowledgeStore = knowledgeStore
        self.graphService = graphService
        self.vectorIndex = vectorIndex
        self.embedder = embedder
        self.semanticWeight = semanticWeight
        self.candidateLimit = candidateLimit
    }

    public func retrieve(_ query: RetrievalQuery) async throws -> RetrievalResults {
        guard query.limit > 0 else {
            throw RetrievalError.invalidLimit(query.limit)
        }

        let searchResults = try await searchService.search(
            SearchQuery(
                text: "",
                kinds: query.kinds,
                tags: query.tags,
                statuses: query.statuses,
                importedFrom: query.importedFrom,
                importedThrough: query.importedThrough,
                limit: max(query.limit, candidateLimit)
            )
        )
        let text = query.text.trimmingCharacters(in: .whitespacesAndNewlines)
        let semanticByID = await semanticScores(text: text, limit: max(query.limit, candidateLimit))
        var results: [RetrievalResult] = []

        for item in searchResults.items {
            let knowledgeItem = try await knowledgeStore?.knowledgeItem(id: item.id)
            guard sourceMatches(query.sourceIDs, item: item, knowledgeItem: knowledgeItem) else {
                continue
            }
            guard try await contextMatches(query.contextIDs, itemID: item.id) else {
                continue
            }

            var scored = score(item: item, knowledgeItem: knowledgeItem, text: text, sourceIDs: query.sourceIDs)
            if let semantic = semanticByID[item.id], semantic > 0 {
                scored.score = min(1, scored.score + semanticWeight * semantic)
                scored.explanations.append("Semantically related.")
            }
            if text.isEmpty || scored.score > 0 {
                results.append(scored)
            }
        }

        let sorted = results.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                if lhs.item.importedAt == rhs.item.importedAt {
                    return lhs.item.id.uuidString < rhs.item.id.uuidString
                }
                return lhs.item.importedAt > rhs.item.importedAt
            }
            return lhs.score > rhs.score
        }

        return RetrievalResults(items: Array(sorted.prefix(query.limit)), totalCount: sorted.count)
    }

    /// Semantic similarity of each candidate to the query, via the vector index.
    /// Returns [:] when semantics are disabled or the query can't be embedded —
    /// retrieval then falls back to lexical + graph only.
    private func semanticScores(text: String, limit: Int) async -> [UUID: Double] {
        guard semanticWeight > 0, !text.isEmpty, let embedder, let vectorIndex else { return [:] }
        guard let vector = await embedder.embed(text) else { return [:] }
        let query = VectorSearchQuery(modelID: embedder.modelID, vector: vector, limit: limit)
        guard let matches = try? await vectorIndex.nearest(to: query) else { return [:] }
        var scores: [UUID: Double] = [:]
        for match in matches { scores[match.itemID] = max(0, match.score) }
        return scores
    }

    private func sourceMatches(_ sourceIDs: [UUID], item: IndexedItem, knowledgeItem: KnowledgeItem?) -> Bool {
        guard !sourceIDs.isEmpty else {
            return true
        }
        if let sourceID = knowledgeItem?.sourceID, sourceIDs.contains(sourceID) {
            return true
        }
        let sourceTags = Set(sourceIDs.map { "source:\($0.uuidString)" })
        return !sourceTags.isDisjoint(with: Set(item.tags))
    }

    private func contextMatches(_ contextIDs: [UUID], itemID: UUID) async throws -> Bool {
        guard !contextIDs.isEmpty else {
            return true
        }
        guard let graphService else {
            return false
        }
        let itemContexts = Set(try await graphService.contexts(relatedTo: itemID).map(\.context.id))
        return !itemContexts.isDisjoint(with: Set(contextIDs))
    }

    private func score(
        item: IndexedItem,
        knowledgeItem: KnowledgeItem?,
        text: String,
        sourceIDs: [UUID]
    ) -> RetrievalResult {
        var score = text.isEmpty ? 0.1 : 0
        var explanations: [String] = []
        let foldedText = text.lowercased()

        if text.isEmpty {
            explanations.append("Recently captured or updated.")
        } else {
            if item.displayName.lowercased().contains(foldedText) {
                score += 0.55
                explanations.append("Filename matched.")
            }
            if item.currentPath.lowercased().contains(foldedText) || (item.originalPath?.lowercased().contains(foldedText) == true) {
                score += 0.3
                explanations.append("Path matched.")
            }
            if item.tags.contains(where: { $0.localizedCaseInsensitiveContains(text) }) {
                score += 0.25
                explanations.append("Tag or source matched.")
            }
            if item.extractedText?.localizedCaseInsensitiveContains(text) == true {
                score += 0.2
                explanations.append("Extracted text matched.")
            }
        }

        if let knowledgeItem, !sourceIDs.isEmpty, sourceIDs.contains(where: { $0 == knowledgeItem.sourceID }) {
            score += 0.2
            explanations.append("Matched capture source.")
        }

        if item.status == .missing {
            explanations.append("Current file is missing or needs recovery.")
        }

        return RetrievalResult(
            item: item,
            knowledgeItem: knowledgeItem,
            score: min(score, 1),
            explanations: explanations.isEmpty ? ["Matched Library record."] : explanations
        )
    }
}
