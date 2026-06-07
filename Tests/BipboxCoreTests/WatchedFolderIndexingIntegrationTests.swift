import BipboxAppSupport
import BipboxCore
import BipboxWorkspaceUI
import XCTest

/// End-to-end: add a real folder as a watched source via the real services and
/// confirm its contents become searchable. Diagnoses "folder treated as a single
/// target" — i.e. whether the cold-start scan actually indexes children.
final class WatchedFolderIndexingIntegrationTests: XCTestCase {
    func testAddingWatchedFolderIndexesTopLevelChildren() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("bipbox-it-\(UUID().uuidString)", isDirectory: true)
        let watched = fm.temporaryDirectory.appendingPathComponent("bipbox-watched-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try fm.createDirectory(at: watched, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base); try? fm.removeItem(at: watched) }

        // Three top-level files + one subfolder containing a nested file.
        try "alpha".write(to: watched.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try "beta".write(to: watched.appendingPathComponent("b.pdf"), atomically: true, encoding: .utf8)
        try "gamma".write(to: watched.appendingPathComponent("c.png"), atomically: true, encoding: .utf8)
        let sub = watched.appendingPathComponent("nested", isDirectory: true)
        try fm.createDirectory(at: sub, withIntermediateDirectories: true)
        try "delta".write(to: sub.appendingPathComponent("d.txt"), atomically: true, encoding: .utf8)

        let services = try BipboxAppServices.makeDefault(paths: BipboxRuntimePaths(baseDirectoryURL: base))

        // Add as a watched source (top-level policy = .never).
        _ = try await services.sourceLifecycleCoordinator.addWatchedFolder(
            SourceLifecycleRequest(url: watched, displayName: "Watched", recursivePolicy: .never)
        )

        let indexed = try await services.searchService.search(SearchQuery(text: "", limit: 100))
        let names = Set(indexed.items.map(\.displayName))

        // Top-level children must be indexed (3 files + the nested folder as 1 item = 4).
        XCTAssertTrue(names.contains("a.txt"), "Top-level file a.txt should be indexed; got \(names)")
        XCTAssertTrue(names.contains("b.pdf"), "Top-level file b.pdf should be indexed; got \(names)")
        XCTAssertTrue(names.contains("c.png"), "Top-level file c.png should be indexed; got \(names)")
        XCTAssertGreaterThanOrEqual(indexed.items.count, 3, "Watched folder contents should be indexed, not just the folder itself")
    }

    /// Proves the Connections graph loads REAL neighbors and that clicking a
    /// context node navigates to its member items (the "leads to nowhere" bug).
    @MainActor
    func testGraphLoadsItemContextsAndContextMembers() async throws {
        let fm = FileManager.default
        let base = fm.temporaryDirectory.appendingPathComponent("bipbox-g-\(UUID().uuidString)", isDirectory: true)
        let watched = fm.temporaryDirectory.appendingPathComponent("bipbox-gw-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: base, withIntermediateDirectories: true)
        try fm.createDirectory(at: watched, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: base); try? fm.removeItem(at: watched) }
        try "one".write(to: watched.appendingPathComponent("one.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: watched.appendingPathComponent("two.txt"), atomically: true, encoding: .utf8)

        let services = try BipboxAppServices.makeDefault(paths: BipboxRuntimePaths(baseDirectoryURL: base))
        _ = try await services.sourceLifecycleCoordinator.addWatchedFolder(
            SourceLifecycleRequest(url: watched, displayName: "Watched", recursivePolicy: .never)
        )

        let library = SearchWorkspaceViewModel(
            searchService: services.searchService,
            retrievalService: services.retrievalService,
            relatednessService: services.relatednessService,
            relatedContextService: services.relatedContextService
        )
        await library.search()
        let model = WorkspaceModel(
            WorkspaceViewModels(library: library),
            graphServices: WorkspaceGraphServices(
                graph: services.knowledgeGraphService,
                relatedness: services.relatednessService,
                store: services.knowledgeStore
            )
        )

        let itemID = try XCTUnwrap(library.results.first?.id)

        // Item ego graph must include the folder context as a real neighbor.
        let itemGraph = await model.loadGraph(center: .item(itemID))
        XCTAssertNotNil(itemGraph.center)
        let contextNeighbor = itemGraph.neighbors.first { if case .context = $0.selection { return true }; return false }
        let context = try XCTUnwrap(contextNeighbor, "Item should be linked to its folder context; got \(itemGraph.neighbors.map(\.name))")

        // Clicking that context must navigate to its member items (not "nowhere").
        guard case .context(let ctxID) = context.selection else { return XCTFail("expected context selection") }
        let contextGraph = await model.loadGraph(center: .context(ctxID))
        XCTAssertNotNil(contextGraph.center, "Context node must resolve a real name, not a placeholder")
        XCTAssertFalse(contextGraph.neighbors.isEmpty, "Context must list its member items")
        XCTAssertTrue(contextGraph.neighbors.contains { $0.name == "one.txt" || $0.name == "two.txt" })
    }
}
