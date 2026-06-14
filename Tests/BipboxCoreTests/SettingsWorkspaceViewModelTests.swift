import BipboxCore
import BipboxWorkspaceUI
import XCTest

@MainActor
final class SettingsWorkspaceViewModelTests: XCTestCase {

    func testWatchFoldersTogglePersistsAutomationState() async throws {
        let store = FixtureAppSettingsStore()
        let viewModel = SettingsWorkspaceViewModel(appSettingsStore: store)
        XCTAssertTrue(viewModel.watchFoldersEnabled)

        await viewModel.setWatchFoldersEnabled(false)
        XCTAssertFalse(viewModel.watchFoldersEnabled)
        var persisted = try await store.load()
        XCTAssertEqual(persisted.automationState, .paused)

        await viewModel.setWatchFoldersEnabled(true)
        persisted = try await store.load()
        XCTAssertEqual(persisted.automationState, .running)
    }

    func testLoadAppliesPersistedAutomationState() async {
        let store = FixtureAppSettingsStore(settings: AppSettings(automationState: .paused))
        let viewModel = SettingsWorkspaceViewModel(appSettingsStore: store)

        await viewModel.load()
        XCTAssertFalse(viewModel.watchFoldersEnabled)
    }

    func testLaunchAtLoginDrivesTheLoginItem() async {
        let loginItem = FakeLoginItem(enabled: false)
        let viewModel = SettingsWorkspaceViewModel(
            appSettingsStore: FixtureAppSettingsStore(), loginItem: loginItem)

        await viewModel.setLaunchAtLoginEnabled(true)
        XCTAssertTrue(loginItem.enabled)
        XCTAssertTrue(viewModel.launchAtLoginEnabled)

        await viewModel.setLaunchAtLoginEnabled(false)
        XCTAssertFalse(loginItem.enabled)
        XCTAssertFalse(viewModel.launchAtLoginEnabled)
    }

    func testLaunchAtLoginReflectsActualOSStateOnLoad() async {
        // The login item — not AppSettings — is the source of truth: a stale
        // persisted `true` must not override the OS reporting it as disabled.
        let store = FixtureAppSettingsStore(settings: AppSettings(launchAtLoginEnabled: true))
        let viewModel = SettingsWorkspaceViewModel(
            appSettingsStore: store, loginItem: FakeLoginItem(enabled: false))

        await viewModel.load()
        XCTAssertFalse(viewModel.launchAtLoginEnabled)
    }

    func testLaunchAtLoginSurfacesLoginItemError() async {
        let viewModel = SettingsWorkspaceViewModel(
            appSettingsStore: FixtureAppSettingsStore(), loginItem: ThrowingLoginItem())

        await viewModel.setLaunchAtLoginEnabled(true)
        XCTAssertNotNil(viewModel.errorMessage)
        XCTAssertFalse(viewModel.launchAtLoginEnabled)
    }

    func testSavePreservesUnmanagedAISettings() async throws {
        // Settings no longer exposes AI, but must not clobber persisted AI config.
        let store = FixtureAppSettingsStore(settings: AppSettings(
            automationState: .running, aiEnabled: true, aiProvider: .openAI,
            aiLocalOnlyModeEnabled: false))
        let viewModel = SettingsWorkspaceViewModel(appSettingsStore: store)

        await viewModel.setWatchFoldersEnabled(false)

        let persisted = try await store.load()
        XCTAssertEqual(persisted.automationState, .paused, "the managed field changed")
        XCTAssertTrue(persisted.aiEnabled, "unmanaged AI fields preserved")
        XCTAssertEqual(persisted.aiProvider, .openAI)
        XCTAssertFalse(persisted.aiLocalOnlyModeEnabled)
    }

    func testLoadSurfacesStoreError() async {
        let viewModel = SettingsWorkspaceViewModel(appSettingsStore: ThrowingAppSettingsStore())
        await viewModel.load()
        XCTAssertNotNil(viewModel.errorMessage)
    }

    func testExposesDataDirectory() {
        let dir = URL(fileURLWithPath: "/tmp/bipbox-data", isDirectory: true)
        let viewModel = SettingsWorkspaceViewModel(
            appSettingsStore: FixtureAppSettingsStore(), dataDirectoryURL: dir)
        XCTAssertEqual(viewModel.dataDirectoryURL, dir)
    }
}

private final class FakeLoginItem: LoginItemControlling, @unchecked Sendable {
    var enabled: Bool
    init(enabled: Bool) { self.enabled = enabled }
    func isEnabled() -> Bool { enabled }
    func setEnabled(_ enabled: Bool) throws { self.enabled = enabled }
}

private struct ThrowingLoginItem: LoginItemControlling {
    struct Failure: Error {}
    func isEnabled() -> Bool { false }
    func setEnabled(_ enabled: Bool) throws { throw Failure() }
}

private actor ThrowingAppSettingsStore: AppSettingsStore {
    struct Failure: Error {}
    func load() async throws -> AppSettings { throw Failure() }
    func save(_ settings: AppSettings) async throws { throw Failure() }
}
