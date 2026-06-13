// AppShellUITests — app-shell surfaces that the workspace tests don't cover:
// the Settings window and the startup-error banner.
//
// Drag-drop intake is intentionally NOT covered here: XCUITest can't synthesize a
// real OS file-drag from Finder. That path is covered headlessly by
// BipboxHarnessScenarioTests.testDropIntakeIndexesFile.
import XCTest

@MainActor
final class AppShellUITests: XCTestCase {
    private var dataDir: URL!

    override func setUp() async throws {
        continueAfterFailure = false
        dataDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("bipbox-shell-ui-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dataDir)
    }

    private func makeApp(extraEnv: [String: String] = [:]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["BIPBOX_DATA_DIR"] = dataDir.path
        for (k, v) in extraEnv { app.launchEnvironment[k] = v }
        return app
    }

    func testSettingsWindowOpens() {
        let app = makeApp()
        app.launch()
        XCTAssertTrue(app.buttons["sidebar.allItems"].waitForExistence(timeout: 20))

        // Open Settings via the app menu (more reliable than a Cmd+, keystroke in the runner).
        let appMenu = app.menuBarItems.element(boundBy: 1)   // 0 = Apple menu
        if appMenu.waitForExistence(timeout: 5) { appMenu.click() }
        let settingsItem = app.menuItems.matching(NSPredicate(format: "title BEGINSWITH 'Settings'")).firstMatch
        if settingsItem.waitForExistence(timeout: 5) {
            settingsItem.click()
        } else {
            app.typeKey(",", modifierFlags: .command)
        }

        let aiToggle = app.descendants(matching: .any)["settings.aiEnabled"]
        XCTAssertTrue(aiToggle.waitForExistence(timeout: 10) || app.staticTexts["Enable AI agent"].waitForExistence(timeout: 5),
                      "Settings window should render the preferences form")
    }

    func testStartupErrorBannerShows() {
        let app = makeApp(extraEnv: ["BIPBOX_FORCE_STARTUP_ERROR": "1"])
        app.launch()
        // Even when services fail to start, the window renders (fixtures) and surfaces the error.
        XCTAssertTrue(app.descendants(matching: .any)["startup.error"].waitForExistence(timeout: 20),
                      "A startup failure should surface a visible error banner")
    }
}
