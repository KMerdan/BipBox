// PrincipleUITests — confirms the north-star principles THROUGH the rendered UI.
//
// Pattern: the DEBUG control API arranges deterministic state (isolated data dir +
// seeding), then assertions run against the real rendered window via accessibility
// identifiers declared in BipboxWorkspaceUI. Each test is named for the principle it
// confirms; the exhaustive matrix lives in Tests/BipboxCoreTests/PrincipleAcceptanceTests.
import XCTest

@MainActor
final class PrincipleUITests: XCTestCase {
    private var dataDir: URL!
    private var seedDir: URL!
    private var runningApp: XCUIApplication?
    private let port = Int.random(in: 8200...8999)

    override func setUp() async throws {
        continueAfterFailure = false
        let fm = FileManager.default
        dataDir = fm.temporaryDirectory.appendingPathComponent("bipbox-puit-data-\(UUID().uuidString)", isDirectory: true)
        seedDir = fm.temporaryDirectory.appendingPathComponent("bipbox-puit-seed-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try fm.createDirectory(at: seedDir.appendingPathComponent("nestedfolder"), withIntermediateDirectories: true)
        try "annual report".write(to: seedDir.appendingPathComponent("report.pdf"), atomically: true, encoding: .utf8)
        try "photo".write(to: seedDir.appendingPathComponent("diagram.png"), atomically: true, encoding: .utf8)
        try "code".write(to: seedDir.appendingPathComponent("nestedfolder/buried.swift"), atomically: true, encoding: .utf8)
    }

    override func tearDown() async throws {
        runningApp?.terminate()
        runningApp = nil
        try? await Task.sleep(nanoseconds: 400_000_000)
        try? FileManager.default.removeItem(at: dataDir)
        try? FileManager.default.removeItem(at: seedDir)
    }

    private func launchedApp() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BIPBOX_DATA_DIR"] = dataDir.path
        app.launchEnvironment["BIPBOX_CONTROL_API"] = "1"
        app.launchEnvironment["BIPBOX_CONTROL_PORT"] = String(port)
        app.launch()
        XCTAssertTrue(app.buttons["sidebar.allItems"].waitForExistence(timeout: 20))
        XCTAssertTrue(waitForControlAPI(), "Control API should come up")
        runningApp = app
        return app
    }

    // MARK: Promise + Alpha loop — add source → library → inspector shows the memory

    func testAlphaLoop_AddSourceLibraryAndItemMemory() {
        let app = launchedApp()
        command(["action": "addFolder", "path": seedDir.path, "depth": "top"])

        // Source is first-class: appears in the sidebar.
        let sourceRow = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'sidebar.source:'")).firstMatch
        XCTAssertTrue(sourceRow.waitForExistence(timeout: 15), "Watched folder appears in the sidebar")

        // Library shows a captured item; open it.
        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'item.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15), "Captured item renders in the library")
        card.click()

        // The inspector remembers it: status + why are shown.
        XCTAssertTrue(app.descendants(matching: .any)["item.status"].waitForExistence(timeout: 10), "Status is shown")
        XCTAssertTrue(app.descendants(matching: .any)["item.why"].exists, "'Why you're seeing this' is shown")
    }

    // MARK: Folders are items — top-level capture does not walk into subfolders

    func testFoldersAreItems_SubfolderShownChildHidden() {
        let app = launchedApp()
        command(["action": "addFolder", "path": seedDir.path, "depth": "top"])
        _ = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'item.'")).firstMatch
            .waitForExistence(timeout: 15)
        // The subfolder is captured as one item (its name appears on a card); its
        // child is not surfaced anywhere. (Card text is folded into the button label.)
        let subfolderCard = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "nestedfolder")).firstMatch
        XCTAssertTrue(subfolderCard.waitForExistence(timeout: 10), "Subfolder captured as an item")
        let child = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS[c] %@", "buried"))
        XCTAssertEqual(child.count, 0, "Default capture does not walk into folders")
    }

    // MARK: Retrieval — search gets it back

    func testRetrieval_SearchFindsItem() {
        let app = launchedApp()
        command(["action": "addFolder", "path": seedDir.path, "depth": "top"])
        let search = app.textFields["toolbar.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.click(); search.typeText("report\r")
        // The result row is a Button whose children SwiftUI may merge into the
        // label, so match the rendered result by label rather than a bare text.
        let hit = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label CONTAINS %@", "report.pdf")).firstMatch
        XCTAssertTrue(hit.waitForExistence(timeout: 10), "Search surfaces the item")
    }

    // MARK: Automation is policy — Inbox is the visible fallback; decisions are explicit

    func testInboxFallbackAndExplicitDecision() {
        let app = launchedApp()
        command(["action": "seedPending", "target": "2"])
        app.buttons["sidebar.inbox"].click()

        let rows = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'item.'"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10), "Ambiguous items land in the Inbox")
        let before = rows.count
        rows.firstMatch.click()

        // Safety: the proposed plan is previewed before anything happens.
        XCTAssertTrue(app.descendants(matching: .any)["decision.suggestion"].waitForExistence(timeout: 5),
                      "The plan is previewed (no silent destination)")
        let approve = app.buttons["decision.approve"]
        XCTAssertTrue(approve.waitForExistence(timeout: 5))
        approve.click()

        // Approving removes the decided item from the visible Inbox list.
        expectEventually(timeout: 10) { rows.count < before }
        XCTAssertLessThan(rows.count, before, "Resolves only on explicit user action, then leaves the Inbox")
    }

    // MARK: Sources are first-class — pause is reflected in the UI

    func testSourceFirstClass_PauseReflectsInUI() {
        let app = launchedApp()
        command(["action": "addFolder", "path": seedDir.path, "depth": "top"])
        XCTAssertTrue(app.buttons["sidebar.sources"].waitForExistence(timeout: 10))
        app.buttons["sidebar.sources"].click()

        let pause = app.buttons["source.pauseResume"]
        XCTAssertTrue(pause.waitForExistence(timeout: 10))
        pause.click()
        XCTAssertTrue(app.staticTexts["Paused"].waitForExistence(timeout: 10), "Paused state is visible")
    }

    // MARK: Memory graph — semantic-zoom Overview is reachable

    func testMemoryGraph_OverviewReachable() {
        let app = launchedApp()
        command(["action": "addFolder", "path": seedDir.path, "depth": "all"])
        app.buttons["toolbar.toggle.connections"].click()
        XCTAssertTrue(app.staticTexts["Overview"].waitForExistence(timeout: 10), "Graph Overview is shown")
    }

    // MARK: Safety — missing files are marked and recoverable from the UI

    func testMissingFilesAreMarkedAndRecoverable() {
        let app = launchedApp()
        command(["action": "seedMissing", "target": "1"])

        let card = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'item.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 15))
        card.click()

        // Marked missing, and "Came from" (original path) is remembered.
        XCTAssertTrue(app.staticTexts["Missing"].waitForExistence(timeout: 10), "Missing status is shown")
        XCTAssertTrue(app.descendants(matching: .any)["detail.cameFrom"].exists, "'Came from' is remembered")

        // Recovery affordance exists and works.
        let reindex = app.buttons["recover.reindex"]
        XCTAssertTrue(reindex.waitForExistence(timeout: 5), "Recovery action is offered")
        reindex.click()
        expectEventually(timeout: 10) { !app.staticTexts["Missing"].exists }
        XCTAssertFalse(app.staticTexts["Missing"].exists, "Reindex recovers the item")
    }

    // MARK: Activity — mutations are auditable

    func testActivity_RecordsMutations() {
        let app = launchedApp()
        command(["action": "addFolder", "path": seedDir.path, "depth": "top"])
        app.buttons["sidebar.activity"].click()
        let event = app.descendants(matching: .any).matching(NSPredicate(format: "identifier BEGINSWITH 'activity.'")).firstMatch
        XCTAssertTrue(event.waitForExistence(timeout: 10), "Indexing mutations appear in Activity")
    }

    // MARK: - control API helpers

    @discardableResult
    private func command(_ fields: [String: String]) -> Data? {
        let body = try! JSONSerialization.data(withJSONObject: fields)
        return try? syncPOST(URL(string: "http://127.0.0.1:\(port)/command")!, body: body)
    }

    private func waitForControlAPI() -> Bool {
        let url = URL(string: "http://127.0.0.1:\(port)/health")!
        for _ in 0..<40 {
            if let data = try? sync(URLRequest(url: url)),
               String(data: data, encoding: .utf8)?.contains("\"ok\":true") == true { return true }
            Thread.sleep(forTimeInterval: 0.5)
        }
        return false
    }

    private func expectEventually(timeout: TimeInterval, _ condition: @escaping () -> Bool) {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline { if condition() { return }; Thread.sleep(forTimeInterval: 0.3) }
    }

    private func syncPOST(_ url: URL, body: Data) throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = body
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
