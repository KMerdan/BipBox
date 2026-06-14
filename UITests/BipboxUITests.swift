// BipboxUITests — rendered-UI regression tests driving the real app window via
// the accessibility identifiers declared in BipboxWorkspaceUI.
//
// Setup is deterministic: each test launches the app against an ISOLATED data
// directory (BIPBOX_DATA_DIR) with the DEBUG control API enabled, seeds a temp
// folder over that API (a synchronous request that returns once indexed), then
// asserts on the rendered UI. This avoids racy background seeding.
import XCTest

@MainActor
final class BipboxUITests: XCTestCase {
    private var dataDir: URL!
    private var seedDir: URL!
    private var runningApp: XCUIApplication?
    private let port = Int.random(in: 8200...8999)

    override func setUp() async throws {
        continueAfterFailure = false
        let fm = FileManager.default
        dataDir = fm.temporaryDirectory.appendingPathComponent("bipbox-uitest-data-\(UUID().uuidString)", isDirectory: true)
        seedDir = fm.temporaryDirectory.appendingPathComponent("bipbox-uitest-seed-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: seedDir, withIntermediateDirectories: true)
        try "annual report".write(to: seedDir.appendingPathComponent("report.pdf"), atomically: true, encoding: .utf8)
        try "team photo".write(to: seedDir.appendingPathComponent("photo.png"), atomically: true, encoding: .utf8)
        try "meeting notes".write(to: seedDir.appendingPathComponent("notes.txt"), atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        runningApp?.terminate()
        runningApp = nil
        try? await Task.sleep(nanoseconds: 400_000_000)
        try? FileManager.default.removeItem(at: dataDir)
        try? FileManager.default.removeItem(at: seedDir)
    }

    /// Launch the app with an isolated store + control API, and wait until ready.
    private func launchedApp(seed: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BIPBOX_DATA_DIR"] = dataDir.path
        app.launchEnvironment["BIPBOX_CONTROL_API"] = "1"
        app.launchEnvironment["BIPBOX_CONTROL_PORT"] = String(port)
        app.launch()
        XCTAssertTrue(app.buttons["sidebar.allItems"].waitForExistence(timeout: 20), "Workspace should render")
        XCTAssertTrue(waitForControlAPI(), "Control API should come up")
        if seed { seedFolder() }
        runningApp = app
        return app
    }

    func testSidebarAndSeededLibraryRender() {
        let app = launchedApp()

        // The grouped sidebar renders.
        XCTAssertTrue(app.buttons["sidebar.inbox"].exists)
        XCTAssertTrue(app.buttons["sidebar.rules"].exists)

        // Seeding produced a watched-folder source row in the sidebar.
        let sourceRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sidebar.source:'")).firstMatch
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 15), "Seeded watched folder should appear in the sidebar")

        // And a gallery card renders in the center.
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'item.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "A seeded library card should render")
    }

    func testNavigateToRulesAndCreateRule() {
        let app = launchedApp(seed: false)
        app.buttons["sidebar.rules"].click()

        let newRule = app.buttons["rule.new"]
        XCTAssertTrue(newRule.waitForExistence(timeout: 5))
        newRule.click()

        let anyToggle = app.descendants(matching: .any).matching(
            NSPredicate(format: "identifier BEGINSWITH 'rule.toggle.'")
        ).firstMatch
        XCTAssertTrue(anyToggle.waitForExistence(timeout: 5), "A created rule should appear with a toggle")
    }

    func testToolbarSearchNarrowsResults() {
        let app = launchedApp()
        let search = app.textFields["toolbar.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.click()
        search.typeText("report\r")

        // The result row is a Button whose children SwiftUI may merge into the
        // label, so match the rendered result by label rather than a bare text.
        let hit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "report.pdf")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 10),
                      "Search should surface the seeded report.pdf")
    }

    func testInboxDecisionApproveFlow() {
        let app = launchedApp(seed: false)
        // Seed pending items deterministically via the control API.
        seedPending(count: 2)

        // The Inbox badge / section should reflect pending decisions.
        let inbox = app.buttons["sidebar.inbox"]
        XCTAssertTrue(inbox.waitForExistence(timeout: 10))
        inbox.click()

        // Select the first pending item row, then approve it from the inspector.
        let rows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'item.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "A pending item should be listed in the Inbox")
        let before = rows.count
        rows.firstMatch.click()

        let approve = app.buttons["decision.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5), "The decision block should offer Approve")
        approve.click()

        // After approving, the decided item leaves the Inbox list (count decreases).
        expectEventually(timeout: 10) { rows.count < before }
        XCTAssertLessThan(rows.count, before, "Approving should remove the item from the Inbox")
    }

    func testGalleryConnectionsToggle() {
        let app = launchedApp()

        let connections = app.buttons["toolbar.toggle.connections"]
        XCTAssertTrue(connections.waitForExistence(timeout: 10))
        connections.click()

        // In Connections mode the breadcrumb / graph shows an "Overview" crumb.
        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 10),
                      "Connections view should show the Overview breadcrumb")

        // Back to Gallery shows item cards again.
        app.buttons["toolbar.toggle.gallery"].click()
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'item.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Gallery should render cards")
    }

    func testNavigateAllSections() {
        let app = launchedApp(seed: false)
        for id in ["sidebar.recents", "sidebar.inbox", "sidebar.activity", "sidebar.rules", "sidebar.allItems"] {
            let button = app.buttons[id]
            XCTAssertTrue(button.waitForExistence(timeout: 5), "\(id) should exist")
            button.click()
        }
    }

    // MARK: - control API helpers (deterministic setup)

    private func seedPending(count: Int) {
        let body = try! JSONSerialization.data(withJSONObject: ["action": "seedPending", "target": String(count)])
        _ = try? syncPOST(URL(string: "http://127.0.0.1:\(port)/command")!, body: body)
    }

    private func expectEventually(timeout: TimeInterval, _ condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return }
            Thread.sleep(forTimeInterval: 0.3)
        }
    }

    private func waitForControlAPI() -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        for _ in 0..<40 {
            if let data = try? syncGET(url), String(data: data, encoding: .utf8)?.contains("\"ok\":true") == true {
                return true
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func seedFolder() {
        let body = try! JSONSerialization.data(withJSONObject: ["action": "addFolder", "path": seedDir.path, "depth": "top"])
        _ = try? syncPOST(URL(string: "http://127.0.0.1:\(port)/command")!, body: body)
    }

    private func syncGET(_ url: URL) throws -> Data {
        try sync(URLRequest(url: url))
    }

    private func syncPOST(_ url: URL, body: Data) throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try sync(req)
    }

    private func sync(_ request: URLRequest) throws -> Data {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<Data, Error>!  // guarded by the semaphore
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { result = .failure(error) } else { result = .success(data ?? Data()) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return try result.get()
    }
}
