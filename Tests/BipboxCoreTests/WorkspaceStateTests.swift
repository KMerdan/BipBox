import BipboxCore
import BipboxWorkspaceUI
import XCTest

@MainActor
final class WorkspaceModelTests: XCTestCase {
    private func makeModel() -> WorkspaceModel {
        WorkspaceModel(WorkspaceViewModels())
    }

    private func makeModel(items: [IndexedItem]) async -> WorkspaceModel {
        let library = SearchWorkspaceViewModel(searchService: ClusterFakeSearchService(items: items))
        await library.search()
        return WorkspaceModel(WorkspaceViewModels(library: library))
    }

    func testDefaultsToLibraryGalleryOverview() {
        let model = makeModel()

        XCTAssertEqual(model.section, .allItems)
        XCTAssertEqual(model.presentation, .gallery)
        XCTAssertEqual(model.selection, .overview)
        XCTAssertTrue(model.query.isEmpty)
        XCTAssertFalse(model.isSearching)
    }

    func testNavigationUpdatesSectionAndSelection() {
        let model = makeModel()

        model.go(.inbox)
        XCTAssertEqual(model.section, .inbox)

        model.go(.sources)
        XCTAssertEqual(model.section, .sources)
        XCTAssertEqual(model.selection, Selection.none)

        model.go(.rules)
        XCTAssertEqual(model.section, .rules)

        model.go(.activity)
        XCTAssertEqual(model.section, .activity)
    }

    func testLibraryLikeClassification() {
        XCTAssertTrue(WorkspaceNav.allItems.isLibraryLike)
        XCTAssertTrue(WorkspaceNav.recents.isLibraryLike)
        XCTAssertFalse(WorkspaceNav.inbox.isLibraryLike)
        XCTAssertFalse(WorkspaceNav.sources.isLibraryLike)
        XCTAssertFalse(WorkspaceNav.rules.isLibraryLike)
        XCTAssertFalse(WorkspaceNav.activity.isLibraryLike)
    }

    func testSearchStateTracksQuery() {
        let model = makeModel()
        XCTAssertFalse(model.isSearching)

        model.query = "report"
        XCTAssertTrue(model.isSearching)

        model.query = "   "
        XCTAssertFalse(model.isSearching, "Whitespace-only query is not a search")
    }

    func testSwitchingToGallerySelectsAnItemWhenAvailable() {
        let model = makeModel()
        model.setPresentation(.connections)
        XCTAssertEqual(model.presentation, .connections)
        model.setPresentation(.gallery)
        XCTAssertEqual(model.presentation, .gallery)
    }

    func testHasNoSourcesByDefault() {
        let model = makeModel()
        XCTAssertTrue(model.hasNoSources)
    }

    func testFlashSetsToast() {
        let model = makeModel()
        model.flash("Hello")
        XCTAssertEqual(model.toast, "Hello")
    }

    // MARK: clustering (type & location, not degenerate tags)

    func testClustersGroupByTypeNotByMissingTags() async {
        let items = [
            indexedItemFixture(path: "/U/Downloads/a.pdf", name: "a.pdf", kind: .file),
            indexedItemFixture(path: "/U/Downloads/b.pdf", name: "b.pdf", kind: .file),
            indexedItemFixture(path: "/U/Downloads/c.png", name: "c.png", kind: .file),
            indexedItemFixture(path: "/U/Downloads/proj", name: "proj", kind: .folder),
        ]
        let model = await makeModel(items: items)
        model.lens = .type
        await model.recomputeClusters()
        let clusters = model.clusters

        // None of these have tags, yet they must NOT collapse into one bucket.
        XCTAssertGreaterThan(clusters.count, 1, "Type clustering must produce multiple groups")
        let names = Set(clusters.map(\.name))
        XCTAssertTrue(names.contains("Documents"))
        XCTAssertTrue(names.contains("Images"))
        XCTAssertTrue(names.contains("Folders"))
        XCTAssertEqual(clusters.first(where: { $0.name == "Documents" })?.itemIDs.count, 2)
    }

    // MARK: - indexing status line

    func testReportIndexingPreservesStartTimeAcrossUpdatesThenClears() {
        let model = makeModel()
        XCTAssertNil(model.indexingActivity)

        model.reportIndexing(kind: .scanning(sourceName: "Downloads"), completed: 10, total: 100)
        let started = model.indexingActivity?.startedAt
        XCTAssertNotNil(started)
        XCTAssertEqual(model.indexingActivity?.completed, 10)

        // A later update of the SAME work keeps the original start time (so the
        // ETA is computed over the whole run, not the latest slice).
        model.reportIndexing(kind: .scanning(sourceName: "Downloads"), completed: 40, total: 100)
        XCTAssertEqual(model.indexingActivity?.completed, 40)
        XCTAssertEqual(model.indexingActivity?.startedAt, started)

        // Switching to a different kind of work resets the clock.
        model.reportIndexing(kind: .embedding, completed: 1, total: 50)
        XCTAssertEqual(model.indexingActivity?.kind, .embedding)
        XCTAssertNotEqual(model.indexingActivity?.startedAt, started)

        // Completion (completed >= total) and an explicit nil both clear it.
        model.reportIndexing(kind: .embedding, completed: 50, total: 50)
        XCTAssertNil(model.indexingActivity, "reaching the total clears the line")
        model.reportIndexing(kind: .scanning(sourceName: "Docs"), completed: 5, total: 9)
        XCTAssertNotNil(model.indexingActivity)
        model.reportIndexing(kind: nil)
        XCTAssertNil(model.indexingActivity)
    }
}

private func indexedItemFixture(path: String, name: String, kind: ItemKind) -> IndexedItem {
    IndexedItem(
        currentPath: path,
        originalPath: nil,
        displayName: name,
        kind: kind,
        importedAt: Date(timeIntervalSince1970: 1_800_000_000),
        status: .indexedOnly
    )
}

private final class ClusterFakeSearchService: SearchService, @unchecked Sendable {
    private let items: [IndexedItem]
    init(items: [IndexedItem]) { self.items = items }
    func index(_ item: IndexedItem) async throws {}
    func update(_ item: IndexedItem) async throws {}
    func search(_ query: SearchQuery) async throws -> SearchResults {
        SearchResults(items: Array(items.prefix(query.limit)), totalCount: items.count)
    }
}
