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
        // A subfolder becomes a collection unit; its files are members with a
        // deterministic `contains` link (no embeddings needed).
        try fm.createDirectory(at: watched.appendingPathComponent("notes"), withIntermediateDirectories: true)
        try "one".write(to: watched.appendingPathComponent("notes/one.txt"), atomically: true, encoding: .utf8)
        try "two".write(to: watched.appendingPathComponent("notes/two.txt"), atomically: true, encoding: .utf8)

        let services = try BipboxAppServices.makeDefault(paths: BipboxRuntimePaths(baseDirectoryURL: base))
        _ = try await services.sourceLifecycleCoordinator.addWatchedFolder(
            SourceLifecycleRequest(url: watched, displayName: "Watched", recursivePolicy: .always)
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

        let member = try XCTUnwrap(library.results.first { $0.displayName == "one.txt" })

        // The member's ego links up to its containing collection (clean `in` edge).
        let itemGraph = await model.loadGraph(center: .item(member.id))
        XCTAssertNotNil(itemGraph.center)
        let containerNeighbor = itemGraph.neighbors.first { $0.pred == "in" }
        let container = try XCTUnwrap(containerNeighbor,
                                      "Member should link to its container; got \(itemGraph.neighbors.map(\.name))")

        // Clicking the container lists its member items (not "nowhere").
        let containerGraph = await model.loadGraph(center: container.selection)
        XCTAssertNotNil(containerGraph.center, "Container resolves a real name")
        let members = Set(containerGraph.neighbors.filter { $0.pred == "contains" }.map(\.name))
        XCTAssertTrue(members.contains("one.txt") && members.contains("two.txt"),
                      "Container lists its members, got: \(members)")
    }
}
