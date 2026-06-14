// ProvisioningUITests — drives the first-run embedding-model download banner.
//
// Uses the DEBUG hook BIPBOX_FAKE_PROVISIONING to substitute a scripted provisioner
// (no real ~600 MB download): `needsDownload` shows the banner and plays a brief
// progress sequence on Download; `ready` starts provisioned (no banner).
import XCTest

@MainActor
final class ProvisioningUITests: XCTestCase {
    private var dataDir: URL!
    private var launchedApp: XCUIApplication?
    private let port = Int.random(in: 8200...8999)

    override func setUp() async throws {
        continueAfterFailure = false
        dataDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bipbox-prov-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        launchedApp?.terminate()
        launchedApp = nil
        try? await Task.sleep(nanoseconds: 400_000_000)
        try? FileManager.default.removeItem(at: dataDir)
    }

    private func launch(provisioning: String) -> XCUIApplication {
        let app = XCUIApplication()
        launchedApp = app
        app.launchEnvironment["BIPBOX_DATA_DIR"] = dataDir.path
        app.launchEnvironment["BIPBOX_FAKE_PROVISIONING"] = provisioning
        app.launchEnvironment["BIPBOX_CONTROL_API"] = "1"
        app.launchEnvironment["BIPBOX_CONTROL_PORT"] = String(port)
        app.launch()
        XCTAssertTrue(app.buttons["sidebar.allItems"].waitForExistence(timeout: 20), "Workspace should render")
        return app
    }

    func testFirstRunShowsDownloadBanner() {
        let app = launch(provisioning: "needsDownload")
        XCTAssertTrue(app.buttons["provisioning.download"].waitForExistence(timeout: 12),
                      "First start should surface the one-time-download banner with a Download button")
    }

    func testReadyStateHasNoBanner() {
        let app = launch(provisioning: "ready")
        // A cached/ready model loads silently — the Download button must never appear.
        XCTAssertFalse(app.buttons["provisioning.download"].waitForExistence(timeout: 6),
                       "A provisioned model should not show the download banner")
    }

    func testDownloadFlowReachesReady() {
        let app = launch(provisioning: "needsDownload")
        let download = app.buttons["provisioning.download"]
        XCTAssertTrue(download.waitForExistence(timeout: 12))
        download.click()

        // Progress indicator appears during the (simulated) download…
        XCTAssertTrue(app.staticTexts["provisioning.downloading"].waitForExistence(timeout: 5),
                      "Download should show a progress indicator")

        // …then the Download button disappears once the model is ready.
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline, download.exists { Thread.sleep(forTimeInterval: 0.3) }
        XCTAssertFalse(download.exists, "Download button should disappear once the model is ready")
    }

    func testAppIsUsableWhileNotProvisioned() {
        let app = launch(provisioning: "needsDownload")
        XCTAssertTrue(app.buttons["provisioning.download"].waitForExistence(timeout: 12),
                      "Download banner should be up — the model is not provisioned")
        seedFolder()   // capture + indexing happen regardless of embedding state
        let card = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'item.'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20),
                      "Captured items should render (browse/lexical works) before the model is downloaded")
    }

    // MARK: - control API seeding

    private func seedFolder() {
        let seed = FileManager.default.temporaryDirectory.appendingPathComponent("bipbox-prov-seed-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: seed, withIntermediateDirectories: true)
        try? "annual report".write(to: seed.appendingPathComponent("report.pdf"), atomically: true, encoding: .utf8)
        _ = waitForControlAPI()
        let body = try! JSONSerialization.data(withJSONObject: ["action": "addFolder", "path": seed.path, "depth": "top"])
        var req = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/command")!)
        req.httpMethod = "POST"; req.httpBody = body
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        _ = try? sync(req)
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

    private func sync(_ request: URLRequest) throws -> Data {
        let sem = DispatchSemaphore(value: 0)
        nonisolated(unsafe) var result: Result<Data, Error>!  // guarded by the semaphore
        URLSession.shared.dataTask(with: request) { data, _, error in
            result = error.map { .failure($0) } ?? .success(data ?? Data()); sem.signal()
        }.resume()
        _ = sem.wait(timeout: .now() + 10)
        return try result.get()
    }
}
