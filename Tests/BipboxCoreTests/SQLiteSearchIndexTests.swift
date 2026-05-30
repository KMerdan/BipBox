import BipboxCore
import BipboxPersistence
import XCTest

final class SQLiteSearchIndexTests: XCTestCase {
    func testIndexesAndFindsFileByFilename() async throws {
        let directory = try TemporaryDirectory(name: "search-file-\(UUID().uuidString)")
        let index = try SQLiteSearchIndex(directoryURL: directory.url)
        let item = indexedItem(
            displayName: "invoice-may.pdf",
            kind: .file,
            uniformTypeIdentifier: "com.adobe.pdf",
            tags: ["finance", "invoice"],
            extractedText: "May cloud hosting invoice"
        )

        try await index.index(item)
        let results = try await index.search(SearchQuery(text: "invoice"))

        XCTAssertEqual(results.totalCount, 1)
        XCTAssertEqual(results.items.first, item)
    }

    func testIndexesFolderAsSearchableItem() async throws {
        let directory = try TemporaryDirectory(name: "search-folder-\(UUID().uuidString)")
        let index = try SQLiteSearchIndex(directoryURL: directory.url)
        let folder = indexedItem(
            displayName: "Client Project",
            kind: .folder,
            currentPath: "/tmp/Bipbox/Projects/Client Project",
            originalPath: "/tmp/Downloads/Client Project",
            tags: ["project"],
            status: .organized
        )

        try await index.index(folder)
        let results = try await index.search(SearchQuery(text: "client", kinds: [.folder]))

        XCTAssertEqual(results.items.count, 1)
        XCTAssertEqual(results.items.first?.kind, .folder)
        XCTAssertEqual(results.items.first?.currentPath, "/tmp/Bipbox/Projects/Client Project")
        XCTAssertEqual(results.items.first?.originalPath, "/tmp/Downloads/Client Project")
    }

    func testFiltersByKindTypeTagStatusAndImportedDate() async throws {
        let directory = try TemporaryDirectory(name: "search-filters-\(UUID().uuidString)")
        let index = try SQLiteSearchIndex(directoryURL: directory.url)
        let matching = indexedItem(
            displayName: "receipt.pdf",
            kind: .file,
            uniformTypeIdentifier: "com.adobe.pdf",
            tags: ["finance"],
            importedAt: TestClock.now,
            status: .organized
        )
        let wrongKind = indexedItem(displayName: "receipt-folder", kind: .folder, tags: ["finance"])
        let wrongStatus = indexedItem(displayName: "receipt-failed.pdf", status: .failed)

        try await index.index(matching)
        try await index.index(wrongKind)
        try await index.index(wrongStatus)

        let results = try await index.search(
            SearchQuery(
                text: "receipt",
                kinds: [.file],
                uniformTypeIdentifiers: ["com.adobe.pdf"],
                tags: ["finance"],
                statuses: [.organized],
                importedFrom: TestClock.now.addingTimeInterval(-60),
                importedThrough: TestClock.now.addingTimeInterval(60)
            )
        )

        XCTAssertEqual(results.items, [matching])
    }

    func testUpdateReplacesExistingRecordAndFTSContent() async throws {
        let directory = try TemporaryDirectory(name: "search-update-\(UUID().uuidString)")
        let index = try SQLiteSearchIndex(directoryURL: directory.url)
        let id = UUID(uuidString: "30000000-0000-0000-0000-000000000099")!
        let original = indexedItem(
            id: id,
            displayName: "roughdraft.txt",
            currentPath: "/tmp/Bipbox/Inbox/roughdraft.txt",
            status: .needsReview
        )
        let updated = indexedItem(
            id: id,
            displayName: "final-contract.txt",
            currentPath: "/tmp/Bipbox/Documents/final-contract.txt",
            originalPath: "/tmp/Bipbox/Inbox/old.txt",
            status: .organized
        )

        try await index.index(original)
        try await index.update(updated)

        let oldResults = try await index.search(SearchQuery(text: "roughdraft"))
        let newResults = try await index.search(SearchQuery(text: "contract"))

        XCTAssertEqual(oldResults.items, [])
        XCTAssertEqual(newResults.items, [updated])
        XCTAssertEqual(newResults.items.first?.originalPath, "/tmp/Bipbox/Inbox/old.txt")
    }

    func testRemoveDeletesIndexedAndFTSRecords() async throws {
        let directory = try TemporaryDirectory(name: "search-remove-\(UUID().uuidString)")
        let index = try SQLiteSearchIndex(directoryURL: directory.url)
        let item = indexedItem(displayName: "remove-me.txt", extractedText: "delete from library")

        try await index.index(item)
        try await index.remove(id: item.id)

        let allResults = try await index.search(SearchQuery(text: ""))
        let ftsResults = try await index.search(SearchQuery(text: "library"))

        XCTAssertEqual(allResults.items, [])
        XCTAssertEqual(ftsResults.items, [])
    }

    func testEmptyTextSearchReturnsRecentLimitedResults() async throws {
        let directory = try TemporaryDirectory(name: "search-empty-\(UUID().uuidString)")
        let index = try SQLiteSearchIndex(directoryURL: directory.url)
        let older = indexedItem(
            displayName: "older.txt",
            importedAt: TestClock.now.addingTimeInterval(-10)
        )
        let newer = indexedItem(
            displayName: "newer.txt",
            importedAt: TestClock.now
        )

        try await index.index(older)
        try await index.index(newer)

        let results = try await index.search(SearchQuery(text: "", limit: 1))

        XCTAssertEqual(results.totalCount, 2)
        XCTAssertEqual(results.items, [newer])
    }

    func testSchemaVersionSmokeTest() async throws {
        let directory = try TemporaryDirectory(name: "search-schema-\(UUID().uuidString)")
        let index = try SQLiteSearchIndex(directoryURL: directory.url)

        let version = try await index.schemaVersion()

        XCTAssertEqual(version, SQLiteSearchIndex.schemaVersion)
    }

    func testInvalidLimitFails() async throws {
        let directory = try TemporaryDirectory(name: "search-limit-\(UUID().uuidString)")
        let index = try SQLiteSearchIndex(directoryURL: directory.url)

        do {
            _ = try await index.search(SearchQuery(text: "", limit: 0))
            XCTFail("Expected invalid search limit.")
        } catch let error as SearchIndexError {
            XCTAssertEqual(error, .invalidLimit(0))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

private func indexedItem(
    id: UUID = UUID(),
    displayName: String,
    kind: ItemKind = .file,
    currentPath: String? = nil,
    originalPath: String? = nil,
    uniformTypeIdentifier: String? = nil,
    tags: [String] = [],
    extractedText: String? = nil,
    importedAt: Date = TestClock.now,
    status: IndexedItemStatus = .organized
) -> IndexedItem {
    IndexedItem(
        id: id,
        currentPath: currentPath ?? "/tmp/Bipbox/\(displayName)",
        originalPath: originalPath,
        displayName: displayName,
        kind: kind,
        uniformTypeIdentifier: uniformTypeIdentifier,
        sizeBytes: 128,
        createdAt: importedAt.addingTimeInterval(-30),
        modifiedAt: importedAt,
        importedAt: importedAt,
        routedAt: importedAt,
        tags: tags,
        extractedText: extractedText,
        status: status
    )
}
