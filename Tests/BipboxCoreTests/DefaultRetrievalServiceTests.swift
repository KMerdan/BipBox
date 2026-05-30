import BipboxCore
import XCTest

final class DefaultRetrievalServiceTests: XCTestCase {
    func testEmptyQueryReturnsRecentItemsWithExplanation() async throws {
        let search = MockSearchService()
        let older = MemoryFixtures.libraryItem(
            id: UUID(uuidString: "67000000-0000-0000-0000-000000000001")!,
            name: "older.pdf"
        )
        var newer = MemoryFixtures.libraryItem(
            id: UUID(uuidString: "67000000-0000-0000-0000-000000000002")!,
            name: "newer.pdf"
        )
        newer.importedAt = TestClock.now.addingTimeInterval(60)
        try await search.index(older)
        try await search.index(newer)
        let service = DefaultRetrievalService(searchService: search)

        let results = try await service.retrieve(RetrievalQuery(limit: 2))

        XCTAssertEqual(results.items.map(\.item.displayName), ["newer.pdf", "older.pdf"])
        XCTAssertEqual(results.items.first?.explanations, ["Recently captured or updated."])
    }

    func testRanksFilenamePathTagAndExtractedTextMatches() async throws {
        let search = MockSearchService()
        let filenameMatch = MemoryFixtures.libraryItem(
            id: UUID(uuidString: "67000000-0000-0000-0000-000000000003")!,
            path: "/Library/Invoices/2026.pdf",
            name: "tax-report.pdf"
        )
        let pathMatch = MemoryFixtures.libraryItem(
            id: UUID(uuidString: "67000000-0000-0000-0000-000000000004")!,
            path: "/Library/tax/archive.pdf",
            name: "archive.pdf"
        )
        var textMatch = MemoryFixtures.libraryItem(
            id: UUID(uuidString: "67000000-0000-0000-0000-000000000005")!,
            path: "/Library/notes.md",
            name: "notes.md"
        )
        textMatch.extractedText = "quarterly tax planning"
        try await search.index(pathMatch)
        try await search.index(textMatch)
        try await search.index(filenameMatch)
        let service = DefaultRetrievalService(searchService: search)

        let results = try await service.retrieve(RetrievalQuery(text: "tax"))

        XCTAssertEqual(results.items.first?.item.id, filenameMatch.id)
        XCTAssertTrue(results.items.first?.explanations.contains("Filename matched.") == true)
        XCTAssertTrue(results.items.contains { $0.explanations.contains("Path matched.") })
        XCTAssertTrue(results.items.contains { $0.explanations.contains("Extracted text matched.") })
    }

    func testSourceKindStatusAndDateFiltersCompose() async throws {
        let sourceID = UUID(uuidString: "67000000-0000-0000-0000-000000000006")!
        let otherSourceID = UUID(uuidString: "67000000-0000-0000-0000-000000000007")!
        let source = SourceFixtures.watchedFolder(id: sourceID)
        let otherSource = SourceFixtures.manualImport(id: otherSourceID)
        let search = MockSearchService()
        let knowledge = MockKnowledgeStore()
        var matching = MemoryFixtures.libraryItem(
            id: UUID(uuidString: "67000000-0000-0000-0000-000000000008")!,
            source: source,
            name: "match.pdf",
            kind: .file,
            status: .indexedOnly,
            tags: ["finance"]
        )
        matching.importedAt = TestClock.now
        var wrongSource = MemoryFixtures.libraryItem(
            id: UUID(uuidString: "67000000-0000-0000-0000-000000000009")!,
            source: otherSource,
            name: "wrong-source.pdf",
            status: .indexedOnly,
            tags: ["finance"]
        )
        wrongSource.importedAt = TestClock.now
        try await search.index(matching)
        try await search.index(wrongSource)
        try await knowledge.upsertKnowledgeItem(MemoryFixtures.knowledgeItem(id: matching.id, source: source))
        try await knowledge.upsertKnowledgeItem(MemoryFixtures.knowledgeItem(id: wrongSource.id, source: otherSource))
        let service = DefaultRetrievalService(searchService: search, knowledgeStore: knowledge)

        let results = try await service.retrieve(
            RetrievalQuery(
                sourceIDs: [sourceID],
                kinds: [.file],
                statuses: [.indexedOnly],
                tags: ["finance"],
                importedFrom: TestClock.now.addingTimeInterval(-1),
                importedThrough: TestClock.now.addingTimeInterval(1)
            )
        )

        XCTAssertEqual(results.items.map(\.item.id), [matching.id])
        XCTAssertTrue(results.items.first?.explanations.contains("Matched capture source.") == true)
    }

    func testContextFilterUsesGraphRelationships() async throws {
        let search = MockSearchService()
        let knowledge = MockKnowledgeStore()
        let graph = DefaultKnowledgeGraphService(store: knowledge)
        let item = MemoryFixtures.libraryItem(
            id: UUID(uuidString: "67000000-0000-0000-0000-000000000010")!,
            name: "project.pdf"
        )
        let context = ContextNode(
            id: UUID(uuidString: "67000000-0000-0000-0000-000000000011")!,
            kind: .project,
            name: "Bipbox",
            confidence: ConfidenceScore(1),
            provenance: .user,
            createdAt: TestClock.now,
            updatedAt: TestClock.now
        )
        try await search.index(item)
        try await knowledge.upsertKnowledgeItem(MemoryFixtures.knowledgeItem(id: item.id))
        try await graph.upsertContext(context)
        _ = try await graph.relate(
            subjectID: item.id,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: context.id,
            objectKind: .context,
            confidence: ConfidenceScore(1),
            provenance: .user,
            now: TestClock.now
        )
        let service = DefaultRetrievalService(
            searchService: search,
            knowledgeStore: knowledge,
            graphService: graph
        )

        let results = try await service.retrieve(RetrievalQuery(contextIDs: [context.id]))

        XCTAssertEqual(results.items.map(\.item.id), [item.id])
    }
}
