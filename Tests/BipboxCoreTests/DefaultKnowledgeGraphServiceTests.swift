import BipboxCore
import XCTest

final class DefaultKnowledgeGraphServiceTests: XCTestCase {
    func testRelateIsIdempotentForSameSubjectPredicateAndObject() async throws {
        let store = MockKnowledgeStore()
        let service = DefaultKnowledgeGraphService(store: store)
        let itemID = UUID(uuidString: "51000000-0000-0000-0000-000000000001")!
        let contextID = UUID(uuidString: "51000000-0000-0000-0000-000000000002")!

        let first = try await service.relate(
            subjectID: itemID,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: contextID,
            objectKind: .context,
            confidence: ConfidenceScore(0.4),
            provenance: .existingFolderScan,
            now: TestClock.now
        )
        let updated = try await service.relate(
            subjectID: itemID,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: contextID,
            objectKind: .context,
            confidence: ConfidenceScore(0.9),
            provenance: .user,
            now: TestClock.now.addingTimeInterval(60)
        )
        let relationships = try await service.relationships(subjectID: itemID)

        XCTAssertEqual(first.id, updated.id)
        XCTAssertEqual(relationships.count, 1)
        XCTAssertEqual(relationships.first?.confidence, ConfidenceScore(0.9))
        XCTAssertEqual(relationships.first?.provenance, .user)
        XCTAssertEqual(relationships.first?.createdAt, TestClock.now)
        XCTAssertEqual(relationships.first?.updatedAt, TestClock.now.addingTimeInterval(60))
    }

    func testContextsRelatedToItemLoadsContextDetails() async throws {
        let store = MockKnowledgeStore()
        let service = DefaultKnowledgeGraphService(store: store)
        let itemID = UUID(uuidString: "51000000-0000-0000-0000-000000000003")!
        let context = ContextNode(
            id: UUID(uuidString: "51000000-0000-0000-0000-000000000004")!,
            kind: .project,
            name: "Bipbox",
            confidence: ConfidenceScore(0.8),
            provenance: .user,
            createdAt: TestClock.now,
            updatedAt: TestClock.now
        )
        try await service.upsertContext(context)
        let relationship = try await service.relate(
            subjectID: itemID,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: context.id,
            objectKind: .context,
            confidence: ConfidenceScore(0.8),
            provenance: .user,
            now: TestClock.now
        )

        let related = try await service.contexts(relatedTo: itemID)

        XCTAssertEqual(related, [ContextRelationship(context: context, relationship: relationship)])
    }

    func testCollectionsCanOverlapThroughService() async throws {
        let store = MockKnowledgeStore()
        let service = DefaultKnowledgeGraphService(store: store)
        let itemID = UUID(uuidString: "51000000-0000-0000-0000-000000000005")!
        let research = KnowledgeCollection(
            id: UUID(uuidString: "51000000-0000-0000-0000-000000000006")!,
            name: "Research",
            kind: .manual,
            createdBy: .user,
            createdAt: TestClock.now,
            updatedAt: TestClock.now
        )
        let project = KnowledgeCollection(
            id: UUID(uuidString: "51000000-0000-0000-0000-000000000007")!,
            name: "Project",
            kind: .ruleBacked,
            createdBy: .rule,
            createdAt: TestClock.now,
            updatedAt: TestClock.now
        )

        try await service.upsertCollection(research)
        try await service.upsertCollection(project)
        try await service.addItem(itemID, toCollection: research.id, createdAt: TestClock.now)
        try await service.addItem(itemID, toCollection: project.id, createdAt: TestClock.now)

        let loadedResearch = try await service.collection(id: research.id)
        let researchItemIDs = try await service.itemIDs(inCollection: research.id)
        let projectItemIDs = try await service.itemIDs(inCollection: project.id)

        XCTAssertEqual(loadedResearch, research)
        XCTAssertEqual(researchItemIDs, [itemID])
        XCTAssertEqual(projectItemIDs, [itemID])

        try await service.removeItem(itemID, fromCollection: research.id)

        let updatedResearchItemIDs = try await service.itemIDs(inCollection: research.id)
        let updatedProjectItemIDs = try await service.itemIDs(inCollection: project.id)

        XCTAssertEqual(updatedResearchItemIDs, [])
        XCTAssertEqual(updatedProjectItemIDs, [itemID])
    }
}
