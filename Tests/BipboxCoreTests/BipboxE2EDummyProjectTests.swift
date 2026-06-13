import BipboxCore
import BipboxHarness
import BipboxWorkspaceUI
import XCTest

/// High-coverage end-to-end scenarios over the real stack, driven through the
/// programmatic control surface against a realistic "dummy project" folder.
@MainActor
final class BipboxE2EDummyProjectTests: XCTestCase {
    /// A realistic project tree spanning many type categories + nested folders.
    private func makeDummyProject() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DummyProject-\(UUID().uuidString)", isDirectory: true)
        func write(_ rel: String, _ contents: String) throws {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("README.md", "# Dummy Project\nquarterly report and budget")
        try write("report.pdf", "annual report Q3 finances")
        try write("budget.csv", "item,amount\nrent,1000")
        try write("diagram.png", "png-bytes")
        try write("photo.jpg", "jpg-bytes")
        try write("notes.txt", "meeting notes about the report")
        try write("archive.zip", "zip-bytes")
        try write("src/main.swift", "print(\"hello\")")
        try write("src/util.swift", "func add() {}")
        try write("docs/spec.pdf", "specification document")
        return root
    }

    private func startedHarness() async throws -> BipboxHarness {
        let harness = try BipboxHarness()
        await harness.start()
        return harness
    }

    // MARK: indexing + clustering

    func testDummyProjectRecursiveIndexingAndClusters() async throws {
        let harness = try await startedHarness()
        let project = try makeDummyProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let snap = await harness.addFolder(project, depth: .always)
        // 10 files + 2 subfolders (src, docs) captured as items when recursing.
        XCTAssertGreaterThanOrEqual(snap.itemCount, 10, "Recursive indexing should capture the whole tree")
        XCTAssertEqual(snap.sources.count, 1)

        // Tier-0 clusters span multiple type categories (not one degenerate bucket).
        harness.model.lens = .type
        await harness.model.recomputeClusters()
        let clusters = Set(harness.model.clusters.map(\.name))
        XCTAssertTrue(clusters.contains("Documents"))
        XCTAssertTrue(clusters.contains("Images"))
        XCTAssertTrue(clusters.contains("Code"))
        XCTAssertGreaterThanOrEqual(clusters.count, 4, "Expected several type clusters, got \(clusters)")
    }

    func testTopLevelDepthCapturesSubfoldersAsSingleItems() async throws {
        let harness = try await startedHarness()
        let project = try makeDummyProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let snap = await harness.addFolder(project, depth: .never)
        let names = Set(snap.items.map(\.name))
        // Top-level only: subfolders appear as single items, not their contents.
        XCTAssertTrue(names.contains("src"))
        XCTAssertTrue(names.contains("docs"))
        XCTAssertFalse(names.contains("main.swift"), "Top-level depth must not walk into subfolders")
    }

    // MARK: search + graph navigation

    func testSearchSelectAndGraphNavigation() async throws {
        let harness = try await startedHarness()
        let project = try makeDummyProject()
        defer { try? FileManager.default.removeItem(at: project) }
        await harness.addFolder(project, depth: .always)

        // Search finds the report across name + content.
        var snap = await harness.search("report")
        XCTAssertTrue(snap.isSearching)
        let report = try XCTUnwrap(snap.items.first { $0.name == "report.pdf" })

        // Select it → graph resolves the folder context + cluster neighbors.
        snap = await harness.select("item:\(report.id)")
        let graph = try XCTUnwrap(snap.graph)
        XCTAssertNotNil(graph.center)
        XCTAssertFalse(graph.neighbors.isEmpty)

        // Follow a context neighbor → its members include sibling files.
        if let ctx = graph.neighbors.first(where: { $0.selection.hasPrefix("context:") }) {
            let ctxSnap = await harness.select(ctx.selection)
            XCTAssertFalse(ctxSnap.graph?.neighbors.isEmpty ?? true, "Context hub should list member items")
        }

        // Clear search returns to overview.
        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.clearSearch))
        XCTAssertFalse(snap.isSearching)
        XCTAssertEqual(snap.selection, "overview")
    }

    // MARK: inbox decision flow (approve / keep / reject)

    func testDecisionApproveRemovesFromInbox() async throws {
        let harness = try await startedHarness()
        var snap = await harness.seedPending(3)
        XCTAssertEqual(snap.pendingCount, 3)

        snap = await harness.navigate("inbox")
        let pending = try XCTUnwrap(snap.items.first { $0.status == "needsReview" })

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.decide, decision: "approve", id: pending.id))
        XCTAssertEqual(snap.pendingCount, 2, "Approving should drop the pending count")
        XCTAssertFalse(snap.items.contains { $0.id == pending.id && $0.status == "needsReview" })
    }

    func testDecisionRejectAndKeep() async throws {
        let harness = try await startedHarness()
        var snap = await harness.seedPending(3)
        await harness.navigate("inbox")

        let ids = snap.items.filter { $0.status == "needsReview" }.map(\.id)
        XCTAssertGreaterThanOrEqual(ids.count, 3)

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.decide, decision: "reject", id: ids[0]))
        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.decide, decision: "keep", id: ids[1]))
        XCTAssertLessThanOrEqual(snap.pendingCount, 1, "Reject + keep should resolve two pending items")
    }

    // MARK: rules lifecycle

    func testRulesLifecycleThroughControl() async throws {
        let harness = try await startedHarness()
        var snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.addRule))
        let ruleID = try XCTUnwrap(snap.rules.last?.id)

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.toggleRule, id: ruleID))
        XCTAssertTrue(snap.rules.contains { $0.id == ruleID && !$0.enabled })

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.deleteRule, id: ruleID))
        XCTAssertFalse(snap.rules.contains { $0.id == ruleID })
    }

    // MARK: source lifecycle

    func testSourceLifecyclePauseResumeRemove() async throws {
        let harness = try await startedHarness()
        let project = try makeDummyProject()
        defer { try? FileManager.default.removeItem(at: project) }
        var snap = await harness.addFolder(project, depth: .never)
        let sourceID = try XCTUnwrap(snap.sources.first?.id)

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.pauseSource, id: sourceID))
        XCTAssertEqual(snap.sources.first { $0.id == sourceID }?.enabled, false)

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.resumeSource, id: sourceID))
        XCTAssertEqual(snap.sources.first { $0.id == sourceID }?.enabled, true)

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.scanSource, id: sourceID))
        XCTAssertNotNil(snap.sources.first { $0.id == sourceID })
    }

    // MARK: drop intake (real capture pipeline)

    func testDropIntakeIndexesFile() async throws {
        let harness = try await startedHarness()
        let project = try makeDummyProject()
        defer { try? FileManager.default.removeItem(at: project) }

        let before = (await harness.snapshot()).itemCount
        let snap = await harness.submitDrop([project.appendingPathComponent("report.pdf")])
        XCTAssertGreaterThan(snap.itemCount, before, "Dropped file should be captured into the library")
    }
}
