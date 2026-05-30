import BipboxCore
import BipboxWorkspaceUI
import XCTest

@MainActor
final class SearchWorkspaceViewModelTests: XCTestCase {
    func testBuildsQueryFromTextAndFilters() async {
        let service = CapturingSearchService(items: [])
        let viewModel = SearchWorkspaceViewModel(searchService: service)
        viewModel.searchText = "  tax  "
        viewModel.kindFilter = .folders
        viewModel.typeFilterText = "public.folder, com.apple.package"
        viewModel.tagFilterText = "finance, urgent"
        viewModel.statusFilter = .needsReview
        viewModel.importedFrom = TestClock.now
        viewModel.importedThrough = TestClock.now.addingTimeInterval(60)

        await viewModel.search()

        XCTAssertEqual(service.lastQuery?.text, "tax")
        XCTAssertEqual(service.lastQuery?.kinds, [.folder])
        XCTAssertEqual(service.lastQuery?.uniformTypeIdentifiers, ["public.folder", "com.apple.package"])
        XCTAssertEqual(service.lastQuery?.tags, ["finance", "urgent"])
        XCTAssertEqual(service.lastQuery?.statuses, [.needsReview])
        XCTAssertEqual(service.lastQuery?.importedFrom, TestClock.now)
        XCTAssertEqual(service.lastQuery?.importedThrough, TestClock.now.addingTimeInterval(60))
    }

    func testFoldersCanAppearInResultsAndBeSelected() async {
        let folder = indexedItem(
            path: "/Library/Projects/Client",
            name: "Client",
            kind: .folder,
            status: .needsReview
        )
        let viewModel = SearchWorkspaceViewModel(searchService: CapturingSearchService(items: [folder]))

        await viewModel.search()

        XCTAssertEqual(viewModel.results, [folder])
        XCTAssertEqual(viewModel.totalCount, 1)
        XCTAssertEqual(viewModel.selectedItem, folder)
        XCTAssertNil(viewModel.errorMessage)
    }

    func testEmptyResultStateClearsSelection() async {
        let viewModel = SearchWorkspaceViewModel(searchService: CapturingSearchService(items: []))

        await viewModel.search()

        XCTAssertEqual(viewModel.results, [])
        XCTAssertEqual(viewModel.totalCount, 0)
        XCTAssertNil(viewModel.selectedItem)
        XCTAssertFalse(viewModel.hasResults)
    }

    func testSearchErrorClearsResultsAndStoresMessage() async {
        let viewModel = SearchWorkspaceViewModel(
            searchService: CapturingSearchService(error: SearchViewModelTestError.searchFailed)
        )

        await viewModel.search()

        XCTAssertEqual(viewModel.results, [])
        XCTAssertEqual(viewModel.totalCount, 0)
        XCTAssertNil(viewModel.selectedItem)
        XCTAssertEqual(viewModel.errorMessage, SearchViewModelTestError.searchFailed.localizedDescription)
    }

    func testSelectedResultActionsDelegateToHandler() {
        let item = indexedItem(path: "/Library/report.pdf", name: "report.pdf", kind: .file)
        let handler = CapturingSearchActionHandler()
        let viewModel = SearchWorkspaceViewModel(
            searchService: CapturingSearchService(items: [item]),
            actionHandler: handler
        )
        viewModel.select(item)

        viewModel.openSelectedItem()
        viewModel.revealSelectedItem()
        viewModel.copySelectedPath()

        XCTAssertEqual(handler.opened, [item])
        XCTAssertEqual(handler.revealed, [item])
        XCTAssertEqual(handler.copied, [item])
    }

    func testLibraryModeFiltersCollectionSourceAndMissingStates() async {
        let service = CapturingSearchService(items: [])
        let viewModel = SearchWorkspaceViewModel(searchService: service)
        viewModel.collectionFilterText = "finance"
        viewModel.sourceFilterText = "downloads"
        viewModel.mode = .missing

        await viewModel.search()

        XCTAssertEqual(service.lastQuery?.tags, ["finance", "downloads"])
        XCTAssertEqual(service.lastQuery?.statuses, [.missing])
    }

    func testRetrievalServiceDrivesLibraryResultsAndExplanations() async {
        let sourceID = UUID(uuidString: "30000000-0000-0000-0000-000000000001")!
        let item = indexedItem(path: "/Library/source-report.pdf", name: "source-report.pdf", kind: .file)
        let retrieval = CapturingRetrievalService(results: [
            RetrievalResult(item: item, score: 0.9, explanations: ["Filename matched.", "Matched capture source."])
        ])
        let viewModel = SearchWorkspaceViewModel(
            searchService: CapturingSearchService(items: []),
            retrievalService: retrieval
        )
        viewModel.searchText = "report"
        viewModel.sourceFilterText = sourceID.uuidString

        await viewModel.search()

        XCTAssertEqual(retrieval.lastQuery?.text, "report")
        XCTAssertEqual(retrieval.lastQuery?.sourceIDs, [sourceID])
        XCTAssertEqual(viewModel.results, [item])
        XCTAssertEqual(viewModel.matchExplanation(for: item), "Filename matched. Matched capture source.")
    }

    func testRecoveryActionsUpdateOrRemoveSelectedLibraryItem() async {
        let original = indexedItem(path: "/Library/missing.pdf", name: "missing.pdf", kind: .file, status: .missing)
        let reindexed = indexedItem(id: original.id, path: "/Library/missing.pdf", name: "missing.pdf", kind: .file, status: .indexedOnly)
        let recovery = CapturingMissingFileRecoveryService(reindexResult: reindexed)
        let viewModel = SearchWorkspaceViewModel(
            searchService: CapturingSearchService(items: [original]),
            missingFileRecoveryService: recovery
        )
        await viewModel.search()

        await viewModel.reindexSelectedItem()

        XCTAssertEqual(recovery.reindexedIDs, [original.id])
        XCTAssertEqual(viewModel.selectedItem?.status, .indexedOnly)

        await viewModel.removeSelectedItemFromLibrary()

        XCTAssertEqual(recovery.removedIDs, [original.id])
        XCTAssertEqual(viewModel.results, [])
        XCTAssertNil(viewModel.selectedItem)
    }

    func testContextModeLoadsRelatedContextOverview() async {
        let item = indexedItem(path: "/Library/report.pdf", name: "report.pdf", kind: .file)
        let context = ContextNode(kind: .project, name: "Launch", provenance: .user, createdAt: TestClock.now, updatedAt: TestClock.now)
        let relationship = RelationshipEdge(
            subjectID: item.id,
            subjectKind: .knowledgeItem,
            predicate: .belongsTo,
            objectID: context.id,
            objectKind: .context,
            provenance: .user,
            createdAt: TestClock.now,
            updatedAt: TestClock.now
        )
        let overview = RelatedContextOverview(
            itemID: item.id,
            contexts: [ContextRelationship(context: context, relationship: relationship)],
            collections: [],
            relatedItems: [],
            explanations: ["Connected to 1 context(s)."]
        )
        let contextService = CapturingRelatedContextService(overview: overview)
        let viewModel = SearchWorkspaceViewModel(
            searchService: CapturingSearchService(items: [item]),
            relatedContextService: contextService,
            mode: .contexts
        )

        await viewModel.search()

        XCTAssertEqual(contextService.requestedItemIDs, [item.id])
        XCTAssertEqual(viewModel.relatedContextOverview?.contexts.map(\.context.name), ["Launch"])
    }

    func testRelatedModeLoadsRelatedItemsAndExplanations() async {
        let seed = indexedItem(path: "/Library/report.pdf", name: "report.pdf", kind: .file)
        let related = indexedItem(path: "/Library/report-notes.md", name: "report-notes.md", kind: .file)
        let relatedness = CapturingRelatednessService(
            relatedItems: [
                RelatedItem(item: related, score: 0.8, explanations: ["Shared filename token report"])
            ]
        )
        let viewModel = SearchWorkspaceViewModel(
            searchService: CapturingSearchService(items: [seed]),
            relatednessService: relatedness,
            mode: .related
        )

        await viewModel.search()

        XCTAssertEqual(relatedness.requestedItemIDs, [seed.id])
        XCTAssertEqual(viewModel.relatedItems.map(\.item), [related])
        XCTAssertEqual(viewModel.matchExplanation(for: related), "Shared filename token report")
    }

    func testMatchExplanationForSearchAndMissingStates() {
        let item = indexedItem(path: "/Library/missing.pdf", name: "missing.pdf", kind: .file, status: .missing)
        let viewModel = SearchWorkspaceViewModel(searchService: CapturingSearchService(items: [item]))

        XCTAssertEqual(viewModel.matchExplanation(for: item), "Missing or permission-needed item.")

        viewModel.searchText = "missing"
        XCTAssertEqual(viewModel.matchExplanation(for: item), "Matched name, path, or indexed text.")
    }
}

private enum SearchViewModelTestError: Error {
    case searchFailed
}

private final class CapturingSearchService: SearchService, @unchecked Sendable {
    private let items: [IndexedItem]
    private let error: Error?
    private(set) var lastQuery: SearchQuery?

    init(items: [IndexedItem] = [], error: Error? = nil) {
        self.items = items
        self.error = error
    }

    func index(_ item: IndexedItem) async throws {}

    func update(_ item: IndexedItem) async throws {}

    func search(_ query: SearchQuery) async throws -> SearchResults {
        lastQuery = query
        if let error {
            throw error
        }
        return SearchResults(items: Array(items.prefix(query.limit)), totalCount: items.count)
    }
}

private final class CapturingRelatednessService: RelatednessService, @unchecked Sendable {
    private let related: [RelatedItem]
    private(set) var requestedItemIDs: [UUID] = []

    init(relatedItems: [RelatedItem]) {
        related = relatedItems
    }

    func relatedItems(to itemID: UUID, limit: Int) async throws -> [RelatedItem] {
        requestedItemIDs.append(itemID)
        return Array(related.prefix(limit))
    }
}

private final class CapturingRetrievalService: RetrievalService, @unchecked Sendable {
    private let results: [RetrievalResult]
    private(set) var lastQuery: RetrievalQuery?

    init(results: [RetrievalResult]) {
        self.results = results
    }

    func retrieve(_ query: RetrievalQuery) async throws -> RetrievalResults {
        lastQuery = query
        return RetrievalResults(items: Array(results.prefix(query.limit)), totalCount: results.count)
    }
}

private final class CapturingMissingFileRecoveryService: MissingFileRecoveryService, @unchecked Sendable {
    private let reindexResult: IndexedItem
    private(set) var reindexedIDs: [UUID] = []
    private(set) var removedIDs: [UUID] = []

    init(reindexResult: IndexedItem) {
        self.reindexResult = reindexResult
    }

    func refreshStatus(itemID: UUID) async throws -> LibraryRecoveryResult {
        LibraryRecoveryResult(item: knowledgeItem(id: itemID), indexedItem: reindexResult, message: "Refreshed.")
    }

    func locate(itemID: UUID, at url: URL) async throws -> LibraryRecoveryResult {
        LibraryRecoveryResult(item: knowledgeItem(id: itemID, url: url), indexedItem: reindexResult, message: "Located.")
    }

    func removeFromLibrary(itemID: UUID) async throws {
        removedIDs.append(itemID)
    }

    func reindex(itemID: UUID) async throws -> LibraryRecoveryResult {
        reindexedIDs.append(itemID)
        return LibraryRecoveryResult(item: knowledgeItem(id: itemID), indexedItem: reindexResult, message: "Reindexed.")
    }

    private func knowledgeItem(id: UUID, url: URL? = nil) -> KnowledgeItem {
        KnowledgeItem(
            id: id,
            kind: .file,
            displayName: url?.lastPathComponent ?? "item",
            currentURL: url,
            originalURL: url,
            firstSeenAt: TestClock.now,
            lastSeenAt: TestClock.now,
            state: .active
        )
    }
}

private final class CapturingRelatedContextService: RelatedContextService, @unchecked Sendable {
    private let overview: RelatedContextOverview
    private(set) var requestedItemIDs: [UUID] = []

    init(overview: RelatedContextOverview) {
        self.overview = overview
    }

    func overview(for itemID: UUID, relatedLimit: Int) async throws -> RelatedContextOverview {
        requestedItemIDs.append(itemID)
        return overview
    }
}

@MainActor
private final class CapturingSearchActionHandler: SearchResultActionHandling {
    private(set) var opened: [IndexedItem] = []
    private(set) var revealed: [IndexedItem] = []
    private(set) var copied: [IndexedItem] = []

    func open(_ item: IndexedItem) {
        opened.append(item)
    }

    func revealInFinder(_ item: IndexedItem) {
        revealed.append(item)
    }

    func copyPath(_ item: IndexedItem) {
        copied.append(item)
    }
}

private func indexedItem(
    id: UUID = UUID(),
    path: String,
    name: String,
    kind: ItemKind,
    status: IndexedItemStatus = .organized
) -> IndexedItem {
    IndexedItem(
        id: id,
        currentPath: path,
        displayName: name,
        kind: kind,
        importedAt: TestClock.now,
        status: status
    )
}
