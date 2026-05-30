import BipboxCore
import XCTest

final class DefaultHybridRelatednessServiceTests: XCTestCase {
    func testRanksByHybridMetadataAndGraphSignals() async throws {
        let store = MockKnowledgeStore()
        let search = MockSearchService()
        let graph = DefaultKnowledgeGraphService(store: store)
        let service = DefaultHybridRelatednessService(
            knowledgeStore: store,
            searchService: search,
            graphService: graph
        )
        let subject = KnowledgeItem(
            id: UUID(uuidString: "52000000-0000-0000-0000-000000000001")!,
            kind: .file,
            displayName: "invoice-may.pdf",
            currentURL: URL(fileURLWithPath: "/Users/example/Downloads/invoice-may.pdf"),
            firstSeenAt: TestClock.now,
            lastSeenAt: TestClock.now
        )
        let strong = relatedIndexedItem(
            id: UUID(uuidString: "52000000-0000-0000-0000-000000000002")!,
            displayName: "invoice-june.pdf",
            path: "/Users/example/Downloads/invoice-june.pdf",
            importedAt: TestClock.now.addingTimeInterval(60)
        )
        let weak = relatedIndexedItem(
            id: UUID(uuidString: "52000000-0000-0000-0000-000000000003")!,
            displayName: "notes.txt",
            path: "/Users/example/Desktop/notes.txt",
            importedAt: TestClock.now.addingTimeInterval(-30 * 24 * 60 * 60)
        )
        let context = ContextNode(
            id: UUID(uuidString: "52000000-0000-0000-0000-000000000004")!,
            kind: .project,
            name: "Finance",
            provenance: .user,
            createdAt: TestClock.now,
            updatedAt: TestClock.now
        )

        try await store.upsertKnowledgeItem(subject)
        try await search.index(strong)
        try await search.index(weak)
        try await graph.upsertContext(context)
        _ = try await graph.relate(
            subjectID: subject.id,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: context.id,
            objectKind: .context,
            confidence: ConfidenceScore(1),
            provenance: .user,
            now: TestClock.now
        )
        _ = try await graph.relate(
            subjectID: strong.id,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: context.id,
            objectKind: .context,
            confidence: ConfidenceScore(1),
            provenance: .user,
            now: TestClock.now
        )

        let results = try await service.relatedItems(to: subject.id, limit: 10)

        XCTAssertEqual(results.map(\.item.id), [strong.id, weak.id])
        XCTAssertTrue(results[0].score > results[1].score)
        XCTAssertTrue(results[0].explanations.contains { $0.contains("Filename shares") })
        XCTAssertTrue(results[0].explanations.contains("Shares 1 graph context(s)."))
    }

    func testLimitAndTieBreakingAreDeterministic() async throws {
        let store = MockKnowledgeStore()
        let search = MockSearchService()
        let graph = DefaultKnowledgeGraphService(store: store)
        let service = DefaultHybridRelatednessService(
            knowledgeStore: store,
            searchService: search,
            graphService: graph
        )
        let subject = KnowledgeItem(
            id: UUID(uuidString: "52000000-0000-0000-0000-000000000005")!,
            kind: .file,
            displayName: "project-plan.txt",
            currentURL: URL(fileURLWithPath: "/tmp/project-plan.txt"),
            firstSeenAt: TestClock.now,
            lastSeenAt: TestClock.now
        )
        let older = relatedIndexedItem(
            id: UUID(uuidString: "52000000-0000-0000-0000-000000000006")!,
            displayName: "project-alpha.txt",
            importedAt: TestClock.now.addingTimeInterval(-2)
        )
        let newer = relatedIndexedItem(
            id: UUID(uuidString: "52000000-0000-0000-0000-000000000007")!,
            displayName: "project-beta.txt",
            importedAt: TestClock.now.addingTimeInterval(-1)
        )

        try await store.upsertKnowledgeItem(subject)
        try await search.index(older)
        try await search.index(newer)

        let results = try await service.relatedItems(to: subject.id, limit: 1)

        XCTAssertEqual(results.map(\.item.id), [newer.id])
    }

    func testInvalidLimitFails() async throws {
        let service = DefaultHybridRelatednessService(
            knowledgeStore: MockKnowledgeStore(),
            searchService: MockSearchService(),
            graphService: DefaultKnowledgeGraphService(store: MockKnowledgeStore())
        )

        do {
            _ = try await service.relatedItems(to: UUID(), limit: 0)
            XCTFail("Expected invalid limit.")
        } catch {
            XCTAssertEqual(error as? RelatednessError, .invalidLimit(0))
        }
    }

    func testMissingSubjectFailsClearly() async throws {
        let missingID = UUID(uuidString: "52000000-0000-0000-0000-000000000008")!
        let store = MockKnowledgeStore()
        let service = DefaultHybridRelatednessService(
            knowledgeStore: store,
            searchService: MockSearchService(),
            graphService: DefaultKnowledgeGraphService(store: store)
        )

        do {
            _ = try await service.relatedItems(to: missingID, limit: 5)
            XCTFail("Expected missing subject failure.")
        } catch {
            XCTAssertEqual(error as? RelatednessError, .itemNotFound(missingID))
        }
    }
}

private func relatedIndexedItem(
    id: UUID,
    displayName: String,
    path: String? = nil,
    importedAt: Date = TestClock.now
) -> IndexedItem {
    IndexedItem(
        id: id,
        currentPath: path ?? "/tmp/\(displayName)",
        displayName: displayName,
        kind: .file,
        importedAt: importedAt,
        status: .indexedOnly
    )
}
