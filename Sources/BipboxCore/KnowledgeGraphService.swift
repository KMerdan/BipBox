import Foundation

public struct ContextRelationship: Codable, Equatable, Identifiable, Sendable {
    public var id: UUID { relationship.id }
    public var context: ContextNode
    public var relationship: RelationshipEdge

    public init(context: ContextNode, relationship: RelationshipEdge) {
        self.context = context
        self.relationship = relationship
    }
}

public final class DefaultKnowledgeGraphService: KnowledgeGraphService {
    private let store: KnowledgeStore

    public init(store: KnowledgeStore) {
        self.store = store
    }

    public func upsertContext(_ context: ContextNode) async throws {
        try await store.upsertContext(context)
    }

    public func context(id: UUID) async throws -> ContextNode? {
        try await store.context(id: id)
    }

    public func relate(
        subjectID: UUID,
        subjectKind: GraphNodeKind,
        predicate: RelationshipPredicate,
        objectID: UUID,
        objectKind: GraphNodeKind,
        confidence: ConfidenceScore = ConfidenceScore(1),
        provenance: GraphProvenance,
        now: Date
    ) async throws -> RelationshipEdge {
        let existingRelationships = try await store.relationships(subjectID: subjectID)
        let existing = existingRelationships.first {
            $0.subjectKind == subjectKind &&
                $0.predicate == predicate &&
                $0.objectID == objectID &&
                $0.objectKind == objectKind
        }
        let relationship = RelationshipEdge(
            id: existing?.id ?? UUID(),
            subjectID: subjectID,
            subjectKind: subjectKind,
            predicate: predicate,
            objectID: objectID,
            objectKind: objectKind,
            confidence: confidence,
            provenance: provenance,
            createdAt: existing?.createdAt ?? now,
            updatedAt: now
        )
        try await store.upsertRelationship(relationship)
        return relationship
    }

    public func relationships(subjectID: UUID) async throws -> [RelationshipEdge] {
        try await store.relationships(subjectID: subjectID)
    }

    public func relationships(objectID: UUID) async throws -> [RelationshipEdge] {
        try await store.relationships(objectID: objectID)
    }

    public func contexts(relatedTo itemID: UUID) async throws -> [ContextRelationship] {
        let allRelationships = try await store.relationships(subjectID: itemID)
        let relationships = allRelationships.filter { $0.objectKind == .context }

        var results: [ContextRelationship] = []
        for relationship in relationships {
            if let context = try await store.context(id: relationship.objectID) {
                results.append(ContextRelationship(context: context, relationship: relationship))
            }
        }
        return results
    }

    public func upsertCollection(_ collection: KnowledgeCollection) async throws {
        try await store.upsertCollection(collection)
    }

    public func collection(id: UUID) async throws -> KnowledgeCollection? {
        try await store.collection(id: id)
    }

    public func collections() async throws -> [KnowledgeCollection] {
        try await store.collections()
    }

    public func addItem(_ itemID: UUID, toCollection collectionID: UUID, createdAt: Date) async throws {
        try await store.addItem(itemID, toCollection: collectionID, createdAt: createdAt)
    }

    public func removeItem(_ itemID: UUID, fromCollection collectionID: UUID) async throws {
        try await store.removeItem(itemID, fromCollection: collectionID)
    }

    public func itemIDs(inCollection collectionID: UUID) async throws -> [UUID] {
        try await store.collectionItemIDs(collectionID: collectionID)
    }
}
