import Foundation

public struct RelatedContextOverview: Equatable, Sendable {
    public var itemID: UUID
    public var contexts: [ContextRelationship]
    public var collections: [KnowledgeCollection]
    public var relatedItems: [RelatedItem]
    public var explanations: [String]

    public init(
        itemID: UUID,
        contexts: [ContextRelationship],
        collections: [KnowledgeCollection],
        relatedItems: [RelatedItem],
        explanations: [String]
    ) {
        self.itemID = itemID
        self.contexts = contexts
        self.collections = collections
        self.relatedItems = relatedItems
        self.explanations = explanations
    }
}

public final class DefaultRelatedContextService: RelatedContextService {
    private let graphService: KnowledgeGraphService
    private let relatednessService: RelatednessService?

    public init(
        graphService: KnowledgeGraphService,
        relatednessService: RelatednessService? = nil
    ) {
        self.graphService = graphService
        self.relatednessService = relatednessService
    }

    public func overview(for itemID: UUID, relatedLimit: Int = 8) async throws -> RelatedContextOverview {
        let contexts = try await graphService.contexts(relatedTo: itemID).sorted { lhs, rhs in
            if lhs.context.kind == rhs.context.kind {
                if lhs.context.name == rhs.context.name {
                    return lhs.relationship.id.uuidString < rhs.relationship.id.uuidString
                }
                return lhs.context.name.localizedStandardCompare(rhs.context.name) == .orderedAscending
            }
            return lhs.context.kind.rawValue < rhs.context.kind.rawValue
        }
        let collections = try await collections(containing: itemID)
        let relatedItems = try await relatednessService?.relatedItems(to: itemID, limit: relatedLimit) ?? []
        var explanations: [String] = []

        if !contexts.isEmpty {
            explanations.append("Connected to \(contexts.count) context(s).")
        }
        if !collections.isEmpty {
            explanations.append("Member of \(collections.count) collection(s).")
        }
        if !relatedItems.isEmpty {
            explanations.append("Has \(relatedItems.count) related item(s).")
        }
        if explanations.isEmpty {
            explanations.append("No related context has been recorded yet.")
        }

        return RelatedContextOverview(
            itemID: itemID,
            contexts: contexts,
            collections: collections,
            relatedItems: relatedItems,
            explanations: explanations
        )
    }

    private func collections(containing itemID: UUID) async throws -> [KnowledgeCollection] {
        var matches: [KnowledgeCollection] = []
        for collection in try await graphService.collections() {
            let itemIDs = try await graphService.itemIDs(inCollection: collection.id)
            if itemIDs.contains(itemID) {
                matches.append(collection)
            }
        }
        return matches.sorted { lhs, rhs in
            if lhs.name == rhs.name {
                return lhs.id.uuidString < rhs.id.uuidString
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
