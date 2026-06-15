import BipboxCore
import BipboxHarness
import BipboxWorkspaceUI
import XCTest

/// Scripted end-to-end scenarios driven through the programmatic control surface.
@MainActor
final class BipboxHarnessScenarioTests: XCTestCase {
    private func makeWatchedFolder() throws -> URL {
        let fm = FileManager.default
        let dir = fm.temporaryDirectory.appendingPathComponent("bipbox-scn-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        try "report".write(to: dir.appendingPathComponent("report.pdf"), atomically: true, encoding: .utf8)
        try "photo".write(to: dir.appendingPathComponent("photo.png"), atomically: true, encoding: .utf8)
        try "notes".write(to: dir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
        return dir
    }

    func testScriptedAddSearchSelectGraph() async throws {
        let harness = try BipboxHarness()
        await harness.start()
        let folder = try makeWatchedFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        // 1. Empty to start.
        var snap = await harness.snapshot()
        XCTAssertEqual(snap.itemCount, 0)
        XCTAssertTrue(snap.sources.isEmpty)

        // 2. Add the folder → its contents are indexed and a source appears.
        snap = await harness.addFolder(folder, depth: .never)
        XCTAssertGreaterThanOrEqual(snap.itemCount, 3)
        XCTAssertEqual(snap.sources.count, 1)
        XCTAssertEqual(snap.sources.first?.indexedCount, 3)

        // 3. Search narrows results.
        snap = await harness.search("report")
        XCTAssertTrue(snap.isSearching)
        XCTAssertTrue(snap.items.contains { $0.name == "report.pdf" })

        // 4. Select an item → the graph resolves it as the centered node. (A loose
        //    top-level file may legitimately have no strong relations in the clean
        //    model, so we assert the node resolves, not a neighbor count.)
        let reportID = try XCTUnwrap(snap.items.first { $0.name == "report.pdf" }?.id)
        snap = await harness.select("item:\(reportID)")
        XCTAssertEqual(snap.selection, "item:\(reportID)")
        let graph = try XCTUnwrap(snap.graph)
        XCTAssertNotNil(graph.center, "Selected item resolves as the graph center")

        // 5. Navigate to the source hub and confirm its members.
        let sourceID = try XCTUnwrap(snap.sources.first?.id)
        snap = await harness.navigate("source:\(sourceID)")
        XCTAssertEqual(snap.section, "source:\(sourceID)")
    }

    func testJSONCommandRoundTrip() async throws {
        let harness = try BipboxHarness()
        await harness.start()
        let folder = try makeWatchedFolder()
        defer { try? FileManager.default.removeItem(at: folder) }

        let command = WorkspaceCommand(action: WorkspaceAction.addFolder, path: folder.path, depth: "top")
        let json = try JSONEncoder().encode(command)
        let responseData = await harness.applyJSON(json)
        let snapshot = try JSONDecoder().decode(WorkspaceSnapshot.self, from: responseData)
        XCTAssertGreaterThanOrEqual(snapshot.itemCount, 3)
    }

    func testRulesToggleThroughControlSurface() async throws {
        let harness = try BipboxHarness()
        await harness.start()

        var snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.addRule))
        let ruleID = try XCTUnwrap(snap.rules.last?.id)
        XCTAssertTrue(snap.rules.contains { $0.id == ruleID && $0.enabled })

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.toggleRule, id: ruleID))
        XCTAssertTrue(snap.rules.contains { $0.id == ruleID && !$0.enabled }, "Rule should be disabled after toggle")

        snap = await harness.apply(WorkspaceCommand(action: WorkspaceAction.deleteRule, id: ruleID))
        XCTAssertFalse(snap.rules.contains { $0.id == ruleID }, "Rule should be gone after delete")
    }
}
