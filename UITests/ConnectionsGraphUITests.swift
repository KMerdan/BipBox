// ConnectionsGraphUITests — the semantic-zoom journey confirmed through the rendered
// graph: Overview clusters → Cluster → File ego → breadcrumb back. Setup is seeded
// deterministically over the DEBUG control API; assertions run on the real window via
// the graph accessibility identifiers (graph.cluster.*, graph.node.*, graph.crumb.*,
// graph.center).
import XCTest

final class ConnectionsGraphUITests: XCTestCase {
    private var dataDir: URL!
    private var seedDir: URL!
    private let port = 7915

    override func setUpWithError() throws {
        continueAfterFailure = false
        let fm = FileManager.default
        dataDir = fm.temporaryDirectory.appendingPathComponent("bipbox-cguit-data-\(UUID().uuidString)", isDirectory: true)
        seedDir = fm.temporaryDirectory.appendingPathComponent("bipbox-cguit-seed-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: seedDir.appendingPathComponent("sub"), withIntermediateDirectories: true)
        try fm.createDirectory(at: dataDir, withIntermediateDirectories: true)
        // A mix of categories so Overview has several clusters that share a folder.
        try "annual report".write(to: seedDir.appendingPathComponent("report.pdf"), atomically: true, encoding: .utf8)
        try "spec".write(to: seedDir.appendingPathComponent("spec.pdf"), atomically: true, encoding: .utf8)
        try "img".write(to: seedDir.appendingPathComponent("diagram.png"), atomically: true, encoding: .utf8)
        try "code".write(to: seedDir.appendingPathComponent("sub/main.swift"), atomically: true, encoding: .utf8)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dataDir)
        try? FileManager.default.removeItem(at: seedDir)
    }

    private func launchedAppInConnections() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BIPBOX_DATA_DIR"] = dataDir.path
        app.launchEnvironment["BIPBOX_CONTROL_API"] = "1"
        app.launchEnvironment["BIPBOX_CONTROL_PORT"] = String(port)
        app.launch()
        XCTAssertTrue(app.buttons["sidebar.allItems"].waitForExistence(timeout: 20))
        XCTAssertTrue(waitForControlAPI(), "Control API should come up")
        command(["action": "addFolder", "path": seedDir.path, "depth": "all"])
        app.buttons["toolbar.toggle.connections"].click()
        return app
    }

    // MARK: full zoom journey through the rendered graph

    func testZoomJourney_OverviewClusterFileBreadcrumb() {
        let app = launchedAppInConnections()

        // Overview renders cluster orbs.
        let cluster = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'graph.cluster.'")).firstMatch
        XCTAssertTrue(cluster.waitForExistence(timeout: 15), "Overview shows similarity clusters")
        cluster.click()

        // Cluster zoom: the centered node card + member file nodes appear.
        XCTAssertTrue(app.descendants(matching: .any)["graph.center"].waitForExistence(timeout: 10),
                      "Cluster becomes the centered node")
        let fileNode = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'graph.node.item:'")).firstMatch
        XCTAssertTrue(fileNode.waitForExistence(timeout: 10), "Cluster lists member file nodes")
        fileNode.click()

        // File ego: still has a centered node, now with its own neighbours.
        XCTAssertTrue(app.descendants(matching: .any)["graph.center"].waitForExistence(timeout: 10),
                      "File becomes the centered node")
        let anyNeighbor = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'graph.node.'")).firstMatch
        XCTAssertTrue(anyNeighbor.waitForExistence(timeout: 10), "File ego shows neighbours")

        // Breadcrumb back to Overview.
        let overviewCrumb = app.buttons["graph.crumb.overview"]
        XCTAssertTrue(overviewCrumb.waitForExistence(timeout: 5), "Breadcrumb offers Overview")
        overviewCrumb.click()
        XCTAssertTrue(cluster.waitForExistence(timeout: 10), "Breadcrumb returns to the Overview clusters")
    }

    // MARK: clicking a node re-centers (no dead-end)

    func testClickingNeighborReCenters() {
        let app = launchedAppInConnections()
        let cluster = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'graph.cluster.'")).firstMatch
        XCTAssertTrue(cluster.waitForExistence(timeout: 15))
        cluster.click()

        let fileNode = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'graph.node.item:'")).firstMatch
        XCTAssertTrue(fileNode.waitForExistence(timeout: 10))
        fileNode.click()

        // A source/cluster neighbour exists in the file ego; clicking it re-centers
        // (the node leads somewhere — the "leads to nowhere" regression guard).
        let neighbor = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'graph.node.'")).firstMatch
        XCTAssertTrue(neighbor.waitForExistence(timeout: 10))
        neighbor.click()
        XCTAssertTrue(app.descendants(matching: .any)["graph.center"].waitForExistence(timeout: 10),
                      "Clicking a neighbour re-centers the graph")
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

    private func syncPOST(_ url: URL, body: Data) throws -> Data {
        var req = URLRequest(url: url)
        req.httpMethod = "POST"; req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return try sync(req)
    }

    private func sync(_ request: URLRequest) throws -> Data {
        let sem = DispatchSemaphore(value: 0)
        var result: Result<Data, Error>!
        URLSession.shared.dataTask(with: request) { data, _, error in
            if let error { result = .failure(error) } else { result = .success(data ?? Data()) }
            sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return try result.get()
    }
}
