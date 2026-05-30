import BipboxCore
import XCTest

final class DefaultRelatedContextServiceTests: XCTestCase {
    func testCollectionOverlapReturnsManualAndRuleBackedCollections() async throws {
        let store = MockKnowledgeStore()
        let graph = DefaultKnowledgeGraphService(store: store)
        let service = DefaultRelatedContextService(graphService: graph)
        let itemID = UUID(uuidString: "69000000-0000-0000-0000-000000000001")!
        let manual = relatedCollection(
            id: UUID(uuidString: "69000000-0000-0000-0000-000000000002")!,
            name: "Archive",
            kind: .manual
        )
        let ruleBacked = relatedCollection(
            id: UUID(uuidString: "69000000-0000-0000-0000-000000000003")!,
            name: "Finance",
            kind: .ruleBacked
        )
        try await graph.upsertCollection(ruleBacked)
        try await graph.upsertCollection(manual)
        try await graph.addItem(itemID, toCollection: ruleBacked.id, createdAt: TestClock.now)
        try await graph.addItem(itemID, toCollection: manual.id, createdAt: TestClock.now)

        let overview = try await service.overview(for: itemID, relatedLimit: 4)

        XCTAssertEqual(overview.collections.map(\.name), ["Archive", "Finance"])
        XCTAssertTrue(overview.explanations.contains("Member of 2 collection(s)."))
    }

    func testSourceAndFolderContextRelationshipsAreSortedAndExplained() async throws {
        let store = MockKnowledgeStore()
        let graph = DefaultKnowledgeGraphService(store: store)
        let service = DefaultRelatedContextService(graphService: graph)
        let itemID = UUID(uuidString: "69000000-0000-0000-0000-000000000004")!
        let sourceContext = relatedContext(
            id: UUID(uuidString: "69000000-0000-0000-0000-000000000005")!,
            kind: .application,
            name: "Downloads Source"
        )
        let folderContext = relatedContext(
            id: UUID(uuidString: "69000000-0000-0000-0000-000000000006")!,
            kind: .folder,
            name: "Downloads"
        )
        try await graph.upsertContext(folderContext)
        try await graph.upsertContext(sourceContext)
        _ = try await graph.relate(
            subjectID: itemID,
            subjectKind: .knowledgeItem,
            predicate: .cameFrom,
            objectID: sourceContext.id,
            objectKind: .context,
            confidence: ConfidenceScore(1),
            provenance: .captureSession,
            now: TestClock.now
        )
        _ = try await graph.relate(
            subjectID: itemID,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: folderContext.id,
            objectKind: .context,
            confidence: ConfidenceScore(1),
            provenance: .existingFolderScan,
            now: TestClock.now
        )

        let overview = try await service.overview(for: itemID, relatedLimit: 4)

        XCTAssertEqual(overview.contexts.map(\.context.kind), [.application, .folder])
        XCTAssertEqual(Set(overview.contexts.map(\.relationship.predicate)), [.cameFrom, .belongsTo])
        XCTAssertTrue(overview.explanations.contains("Connected to 2 context(s)."))
    }

    func testRelatedItemsUseDeterministicRelatednessOrdering() async throws {
        let store = MockKnowledgeStore()
        let graph = DefaultKnowledgeGraphService(store: store)
        let search = MockSearchService()
        let subjectID = UUID(uuidString: "69000000-0000-0000-0000-000000000007")!
        let relatedID = UUID(uuidString: "69000000-0000-0000-0000-000000000008")!
        try await store.upsertKnowledgeItem(MemoryFixtures.knowledgeItem(id: subjectID, url: URL(fileURLWithPath: "/tmp/tax-report.pdf")))
        try await store.upsertKnowledgeItem(MemoryFixtures.knowledgeItem(id: relatedID, url: URL(fileURLWithPath: "/tmp/tax-notes.pdf")))
        try await search.index(MemoryFixtures.libraryItem(id: subjectID, path: "/tmp/tax-report.pdf", name: "tax-report.pdf"))
        try await search.index(MemoryFixtures.libraryItem(id: relatedID, path: "/tmp/tax-notes.pdf", name: "tax-notes.pdf"))
        let relatedness = DefaultHybridRelatednessService(
            knowledgeStore: store,
            searchService: search,
            graphService: graph
        )
        let service = DefaultRelatedContextService(graphService: graph, relatednessService: relatedness)

        let overview = try await service.overview(for: subjectID, relatedLimit: 4)

        XCTAssertEqual(overview.relatedItems.map(\.item.id), [relatedID])
        XCTAssertTrue(overview.relatedItems.first?.explanations.isEmpty == false)
        XCTAssertTrue(overview.explanations.contains("Has 1 related item(s)."))
    }

    func testFoldersAreFirstClassRelationshipSubjects() async throws {
        let store = MockKnowledgeStore()
        let graph = DefaultKnowledgeGraphService(store: store)
        let service = DefaultRelatedContextService(graphService: graph)
        let folderID = UUID(uuidString: "69000000-0000-0000-0000-000000000009")!
        let context = relatedContext(
            id: UUID(uuidString: "69000000-0000-0000-0000-000000000010")!,
            kind: .project,
            name: "Client"
        )
        try await store.upsertKnowledgeItem(
            MemoryFixtures.knowledgeItem(
                id: folderID,
                url: URL(fileURLWithPath: "/tmp/Client"),
                kind: .folder
            )
        )
        try await graph.upsertContext(context)
        _ = try await graph.relate(
            subjectID: folderID,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: context.id,
            objectKind: .context,
            confidence: ConfidenceScore(1),
            provenance: .user,
            now: TestClock.now
        )

        let overview = try await service.overview(for: folderID, relatedLimit: 4)

        XCTAssertEqual(overview.contexts.map(\.context.name), ["Client"])
    }
}

private func relatedContext(id: UUID, kind: ContextKind, name: String) -> ContextNode {
    ContextNode(
        id: id,
        kind: kind,
        name: name,
        confidence: ConfidenceScore(1),
        provenance: .user,
        createdAt: TestClock.now,
        updatedAt: TestClock.now
    )
}

private func relatedCollection(id: UUID, name: String, kind: KnowledgeCollectionKind) -> KnowledgeCollection {
    KnowledgeCollection(
        id: id,
        name: name,
        kind: kind,
        manualMembershipAllowed: true,
        createdBy: kind == .manual ? .user : .rule,
        createdAt: TestClock.now,
        updatedAt: TestClock.now
    )
}
