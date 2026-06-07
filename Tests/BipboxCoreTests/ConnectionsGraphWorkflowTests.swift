import BipboxCore
import BipboxHarness
import BipboxWorkspaceUI
import XCTest

/// Workflow tests for the Connections graph — the semantic-zoom memory map
/// (Overview clusters → Cluster → File ego → hub round-trips → search). Each test
/// walks a multi-step navigation a user performs and asserts the graph state at
/// every hop, driven in-process over the real services via BipboxHarness.
@MainActor
final class ConnectionsGraphWorkflowTests: XCTestCase {
    private var project: URL!
    private var harness: BipboxHarness!

    override func setUp() async throws {
        project = try E2ESupport.makeDummyProject()
        harness = try await makeStartedHarness()
        await harness.addFolder(project, depth: .always)
    }

    override func tearDown() async throws {
        if let project { try? FileManager.default.removeItem(at: project) }
        harness = nil
    }

    // MARK: helpers

    /// The graph for a centered node (center name + neighbors), via the control snapshot.
    private func graph(centering ref: String) async -> WorkspaceSnapshot.GraphSnapshot {
        let snap = await harness.select(ref)
        return snap.graph ?? WorkspaceSnapshot.GraphSnapshot(center: nil, neighbors: [])
    }

    /// First library item with the given name (await hoisted out of XCTUnwrap).
    private func item(named name: String) async throws -> WorkspaceSnapshot.ItemSummary {
        let snap = await harness.snapshot()
        return try XCTUnwrap(snap.items.first { $0.name == name }, "no item named \(name)")
    }

    // MARK: - Workflow 1: full semantic-zoom journey (Overview → Cluster → File)

    func testZoomJourney_OverviewToClusterToFile() async throws {
        // Overview: multiple type clusters, linked where they share folders.
        let clusters = harness.model.clusters
        XCTAssertGreaterThanOrEqual(clusters.count, 3, "Overview shows several clusters: \(clusters.map(\.name))")
        XCTAssertFalse(harness.model.clusterLinks().isEmpty, "Co-located categories are linked")

        // Zoom into a cluster → its members are files.
        let documents = try XCTUnwrap(clusters.first { $0.name == "Documents" })
        let clusterGraph = await graph(centering: "cluster:\(documents.id)")
        XCTAssertEqual(clusterGraph.center, "Documents")
        XCTAssertFalse(clusterGraph.neighbors.isEmpty, "Cluster lists member files")
        XCTAssertTrue(clusterGraph.neighbors.allSatisfy { $0.selection.hasPrefix("item:") })

        // Zoom into a member file → its ego shows source + cluster (+ maybe context/related).
        let memberRef = try XCTUnwrap(clusterGraph.neighbors.first?.selection)
        let fileGraph = await graph(centering: memberRef)
        XCTAssertNotNil(fileGraph.center)
        XCTAssertTrue(fileGraph.neighbors.contains { $0.predicate == "came from" }, "File knows its source")
        XCTAssertTrue(fileGraph.neighbors.contains { $0.selection.hasPrefix("cluster:") }, "File knows its group")
    }

    // MARK: - Workflow 2: every neighbour is navigable (no dead ends)

    func testEveryNeighborNavigatesSomewhere() async throws {
        let report = try await item(named: "report.pdf")
        let ego = await graph(centering: "item:\(report.id)")
        XCTAssertFalse(ego.neighbors.isEmpty)

        for neighbor in ego.neighbors {
            let next = await graph(centering: neighbor.selection)
            XCTAssertNotNil(next.center, "Clicking '\(neighbor.name)' (\(neighbor.selection)) must lead somewhere, not nowhere")
        }
    }

    // MARK: - Workflow 3: source hub round-trip (file → source → back to file)

    func testSourceHubRoundTrip() async throws {
        let report = try await item(named: "report.pdf")
        let ego = await graph(centering: "item:\(report.id)")
        let sourceNeighbor = try XCTUnwrap(ego.neighbors.first { $0.selection.hasPrefix("source:") },
                                           "File ego includes its source")

        // Into the source hub: its members include the file we came from.
        let hub = await graph(centering: sourceNeighbor.selection)
        XCTAssertNotNil(hub.center)
        XCTAssertTrue(hub.neighbors.contains { $0.selection == "item:\(report.id)" },
                      "Source hub lists the file that came from it")

        // Back to the file: the source is still a neighbour (stable round-trip).
        let back = await graph(centering: "item:\(report.id)")
        XCTAssertTrue(back.neighbors.contains { $0.selection == sourceNeighbor.selection })
    }

    // MARK: - Workflow 4: cluster hub lists exactly its members

    func testClusterHubMatchesMembership() async throws {
        let images = try XCTUnwrap(harness.model.clusters.first { $0.name == "Images" })
        let graphSnap = await graph(centering: "cluster:\(images.id)")
        let neighborIDs = Set(graphSnap.neighbors.compactMap { $0.selection.hasPrefix("item:") ? String($0.selection.dropFirst(5)) : nil })
        let expected = Set(images.itemIDs.map(\.uuidString))
        XCTAssertEqual(neighborIDs, expected, "Cluster neighbours are exactly its member items")
    }

    // MARK: - Workflow 5: context hub (file → folder context → members include the file)

    func testContextHubContainsOriginatingFile() async throws {
        let report = try await item(named: "report.pdf")
        let ego = await graph(centering: "item:\(report.id)")
        let contextNeighbor = try XCTUnwrap(ego.neighbors.first { $0.selection.hasPrefix("context:") },
                                            "File belongs to a folder context")
        let hub = await graph(centering: contextNeighbor.selection)
        XCTAssertNotNil(hub.center)
        XCTAssertTrue(hub.neighbors.contains { $0.selection == "item:\(report.id)" },
                      "Context hub lists the originating file")
    }

    // MARK: - Workflow 6: navigation is deterministic (no stale neighbours)

    func testNavigationIsDeterministicAcrossHops() async throws {
        let items = (await harness.snapshot()).items
        let a = try XCTUnwrap(items.first { $0.name == "report.pdf" })
        let b = try XCTUnwrap(items.first { $0.name == "main.swift" })

        let a1 = await graph(centering: "item:\(a.id)")
        let bGraph = await graph(centering: "item:\(b.id)")
        let a2 = await graph(centering: "item:\(a.id)")

        XCTAssertEqual(a1.center, a2.center)
        XCTAssertEqual(Set(a1.neighbors.map(\.selection)), Set(a2.neighbors.map(\.selection)),
                       "Re-centering on the same node yields the same neighbours (no stale data)")
        XCTAssertNotEqual(a1.center, bGraph.center, "Different nodes center differently")
    }

    // MARK: - Workflow 7: search constellation focuses a matching result

    func testSearchFocusesMatchingResultGraph() async throws {
        let snap = await harness.search("report")
        XCTAssertTrue(snap.isSearching)
        // Searching centers the graph on a matching result whose ego resolves.
        XCTAssertTrue(snap.selection.hasPrefix("item:"))
        XCTAssertNotNil(snap.graph?.center)

        // Clearing returns to Overview.
        let cleared = await harness.apply(WorkspaceCommand(action: WorkspaceAction.clearSearch))
        XCTAssertFalse(cleared.isSearching)
        XCTAssertEqual(cleared.selection, "overview")
    }

    // MARK: - Workflow 8: breadcrumb path (Overview > Cluster > File) is well-formed

    func testBreadcrumbReflectsZoomDepth() async throws {
        let report = try await item(named: "report.pdf")
        // A file in a cluster has a 3-level path; the cluster of the file is resolvable.
        let reportUUID = try XCTUnwrap(UUID(uuidString: report.id))
        let cluster = try XCTUnwrap(harness.model.clusterOf(reportUUID))
        XCTAssertEqual(cluster.name, "Documents")
        // Selecting the cluster then overview walks the breadcrumb back up.
        var snap = await harness.select("cluster:\(cluster.id)")
        XCTAssertEqual(snap.graph?.center, "Documents")
        snap = await harness.select("overview")
        XCTAssertEqual(snap.selection, "overview")
    }

    // MARK: - Workflow 9: empty library degrades gracefully

    func testEmptyLibraryHasNoClustersAndNoCrash() async throws {
        let empty = try await makeStartedHarness()
        XCTAssertTrue(empty.model.clusters.isEmpty)
        let overview = await empty.snapshot()
        XCTAssertEqual(overview.itemCount, 0)
        // Centering on a nonexistent item resolves to an empty graph, not a crash.
        let bogus = await empty.select("item:\(UUID().uuidString)")
        XCTAssertNil(bogus.graph?.center)
    }
}
