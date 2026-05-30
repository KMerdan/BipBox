import Foundation

public struct RelatedItem: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { item.id }
    public var item: IndexedItem
    public var score: Double
    public var explanations: [String]

    public init(item: IndexedItem, score: Double, explanations: [String]) {
        self.item = item
        self.score = score
        self.explanations = explanations
    }
}

public enum RelatednessError: Error, Equatable, LocalizedError {
    case invalidLimit(Int)
    case itemNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .invalidLimit(let limit):
            "Related item limit must be positive: \(limit)."
        case .itemNotFound(let id):
            "Cannot find item for relatedness query: \(id)."
        }
    }
}

public final class DefaultHybridRelatednessService: RelatednessService {
    private let knowledgeStore: KnowledgeStore
    private let searchService: SearchService
    private let graphService: KnowledgeGraphService
    private let candidateLimit: Int

    public init(
        knowledgeStore: KnowledgeStore,
        searchService: SearchService,
        graphService: KnowledgeGraphService,
        candidateLimit: Int = 500
    ) {
        self.knowledgeStore = knowledgeStore
        self.searchService = searchService
        self.graphService = graphService
        self.candidateLimit = candidateLimit
    }

    public func relatedItems(to itemID: UUID, limit: Int) async throws -> [RelatedItem] {
        guard limit > 0 else {
            throw RelatednessError.invalidLimit(limit)
        }
        guard let subject = try await knowledgeStore.knowledgeItem(id: itemID) else {
            throw RelatednessError.itemNotFound(itemID)
        }

        let subjectContexts = Set(try await graphService.contexts(relatedTo: itemID).map { $0.context.id })
        let candidates = try await searchService.search(SearchQuery(text: "", limit: candidateLimit))

        var related: [RelatedItem] = []
        for candidate in candidates.items where candidate.id != itemID {
            let candidateContexts = Set(try await graphService.contexts(relatedTo: candidate.id).map { $0.context.id })
            let scored = score(candidate: candidate, against: subject, sharedContexts: subjectContexts.intersection(candidateContexts))
            if scored.score > 0 {
                related.append(scored)
            }
        }

        return Array(
            related
                .sorted { lhs, rhs in
                    if lhs.score == rhs.score {
                        if lhs.item.importedAt == rhs.item.importedAt {
                            return lhs.item.id.uuidString < rhs.item.id.uuidString
                        }
                        return lhs.item.importedAt > rhs.item.importedAt
                    }
                    return lhs.score > rhs.score
                }
                .prefix(limit)
        )
    }

    private func score(
        candidate: IndexedItem,
        against subject: KnowledgeItem,
        sharedContexts: Set<UUID>
    ) -> RelatedItem {
        var score = 0.0
        var explanations: [String] = []

        if candidate.kind == subject.kind {
            score += 0.15
            explanations.append("Same item kind.")
        }

        let subjectNameTokens = tokenSet(subject.displayName)
        let candidateNameTokens = tokenSet(candidate.displayName)
        let sharedNameTokens = subjectNameTokens.intersection(candidateNameTokens)
        if !sharedNameTokens.isEmpty {
            score += min(0.4, 0.12 * Double(sharedNameTokens.count))
            explanations.append("Filename shares \(formattedTokens(sharedNameTokens)).")
        }

        let subjectPathTokens = pathTokens(subject.currentURL?.path ?? subject.originalURL?.path)
        let candidatePathTokens = pathTokens(candidate.currentPath)
            .union(pathTokens(candidate.originalPath))
        let sharedPathTokens = subjectPathTokens.intersection(candidatePathTokens)
        if !sharedPathTokens.isEmpty {
            score += min(0.15, 0.05 * Double(sharedPathTokens.count))
            explanations.append("Path shares \(formattedTokens(sharedPathTokens)).")
        }

        if let subjectSeenAt = Optional(subject.lastSeenAt) {
            let distance = abs(candidate.importedAt.timeIntervalSince(subjectSeenAt))
            if distance <= 24 * 60 * 60 {
                score += 0.1
                explanations.append("Captured within one day.")
            } else if distance <= 7 * 24 * 60 * 60 {
                score += 0.05
                explanations.append("Captured within one week.")
            }
        }

        if !sharedContexts.isEmpty {
            score += min(0.3, 0.15 * Double(sharedContexts.count))
            explanations.append("Shares \(sharedContexts.count) graph context(s).")
        }

        return RelatedItem(
            item: candidate,
            score: min(score, 1),
            explanations: explanations
        )
    }

    private func tokenSet(_ text: String?) -> Set<String> {
        guard let text else { return [] }
        return Set(
            text
                .lowercased()
                .split { !$0.isLetter && !$0.isNumber }
                .map(String.init)
                .filter { $0.count > 1 }
        )
    }

    private func pathTokens(_ path: String?) -> Set<String> {
        guard let path else { return [] }
        let components = path
            .split(separator: "/")
            .dropLast()
            .map(String.init)
            .joined(separator: " ")
        return tokenSet(components)
    }

    private func formattedTokens(_ tokens: Set<String>) -> String {
        tokens.sorted().prefix(3).joined(separator: ", ")
    }
}
