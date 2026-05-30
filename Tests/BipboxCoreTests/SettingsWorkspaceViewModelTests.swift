import BipboxCore
import BipboxWorkspaceUI
import XCTest

@MainActor
final class SettingsWorkspaceViewModelTests: XCTestCase {
    func testSetsLibraryRootThroughPermissionStore() async throws {
        let store = FixturePermissionStore()
        let viewModel = SettingsWorkspaceViewModel(permissionStore: store)
        let libraryURL = URL(fileURLWithPath: "/Bipbox", isDirectory: true)

        await viewModel.setLibraryRoot(libraryURL, state: .granted)
        let storedLibraryRoot = try await store.records(scope: .libraryRoot).first

        XCTAssertEqual(viewModel.libraryRoot?.url, libraryURL)
        XCTAssertEqual(viewModel.libraryRoot?.scope, .libraryRoot)
        XCTAssertEqual(storedLibraryRoot?.url, libraryURL)
    }

    func testPermissionErrorDisplay() async {
        let viewModel = SettingsWorkspaceViewModel(permissionStore: ThrowingPermissionStore())

        await viewModel.load()

        XCTAssertEqual(viewModel.errorMessage, SettingsViewModelTestError.permissionFailed.localizedDescription)
        XCTAssertNil(viewModel.libraryRoot)
    }

    func testPauseAndResumeAutomation() async {
        let viewModel = SettingsWorkspaceViewModel(permissionStore: FixturePermissionStore())

        XCTAssertEqual(viewModel.automationState, .running)

        await viewModel.pauseAutomation()
        XCTAssertEqual(viewModel.automationState, .paused)

        await viewModel.resumeAutomation()
        XCTAssertEqual(viewModel.automationState, .running)
    }

    func testAIPrivacyDefaultsToOff() {
        let viewModel = SettingsWorkspaceViewModel(permissionStore: FixturePermissionStore())

        XCTAssertFalse(viewModel.aiContentSharingEnabled)
        XCTAssertFalse(viewModel.aiEnabled)
        XCTAssertEqual(viewModel.aiProvider, .none)
        XCTAssertTrue(viewModel.aiLocalOnlyModeEnabled)
        XCTAssertTrue(viewModel.aiMetadataOnlyModeEnabled)
        XCTAssertTrue(viewModel.aiAuditLoggingEnabled)
        XCTAssertFalse(viewModel.launchAtLoginEnabled)
        XCTAssertEqual(
            viewModel.aiPrivacySummary,
            "AI is off. Tools remain available locally for future agent planning."
        )
    }

    func testLoadsAndPersistsAppSettings() async throws {
        let settingsStore = FixtureAppSettingsStore(
            settings: AppSettings(
                automationState: .paused,
                launchAtLoginEnabled: true,
                aiEnabled: true,
                aiProvider: .openAI,
                aiLocalOnlyModeEnabled: false,
                aiContentSharingEnabled: false
            )
        )
        let viewModel = SettingsWorkspaceViewModel(
            permissionStore: FixturePermissionStore(),
            appSettingsStore: settingsStore
        )

        await viewModel.load()
        XCTAssertEqual(viewModel.automationState, .paused)
        XCTAssertTrue(viewModel.launchAtLoginEnabled)
        XCTAssertTrue(viewModel.aiEnabled)
        XCTAssertEqual(viewModel.aiProvider, .openAI)
        XCTAssertFalse(viewModel.aiLocalOnlyModeEnabled)
        XCTAssertFalse(viewModel.aiContentSharingEnabled)

        await viewModel.setAIContentSharingEnabled(true)
        await viewModel.setAIAuditLoggingEnabled(false)
        await viewModel.setLaunchAtLoginEnabled(false)

        let persisted = try await settingsStore.load()
        XCTAssertTrue(persisted.aiEnabled)
        XCTAssertEqual(persisted.aiProvider, .openAI)
        XCTAssertFalse(persisted.aiLocalOnlyModeEnabled)
        XCTAssertTrue(persisted.aiContentSharingEnabled)
        XCTAssertFalse(persisted.aiMetadataOnlyModeEnabled)
        XCTAssertFalse(persisted.aiAuditLoggingEnabled)
        XCTAssertFalse(persisted.launchAtLoginEnabled)
        XCTAssertEqual(persisted.automationState, .paused)
    }

    func testPermissionHealthSummaryShowsIssues() async {
        let viewModel = SettingsWorkspaceViewModel(permissionStore: FixturePermissionStore())

        XCTAssertEqual(viewModel.permissionHealthSummary, "No library storage folder configured.")
        XCTAssertEqual(
            viewModel.permissionHealthActionHint,
            "Use Library to choose storage; use Start to add remembered source folders."
        )

        await viewModel.setLibraryRoot(URL(fileURLWithPath: "/Bipbox", isDirectory: true), state: .granted)

        XCTAssertEqual(viewModel.permissionHealthSummary, "All permissions healthy.")
        XCTAssertEqual(
            viewModel.permissionHealthActionHint,
            "Source permissions are managed from Start. Missing files are recovered from Library."
        )
    }

    func testDiagnosticsSummaryPointsToActivityAuditTrail() {
        let viewModel = SettingsWorkspaceViewModel(permissionStore: FixturePermissionStore())

        XCTAssertEqual(
            viewModel.diagnosticsSummary,
            "Activity contains the audit trail for capture, indexing, decisions, filesystem operations, and tool calls."
        )
    }
}

private enum SettingsViewModelTestError: Error {
    case permissionFailed
}

private actor ThrowingPermissionStore: PermissionStore {
    func save(_ record: PermissionRecord) async throws {
        throw SettingsViewModelTestError.permissionFailed
    }

    func remove(id: UUID) async throws {
        throw SettingsViewModelTestError.permissionFailed
    }

    func records(scope: PermissionScope?) async throws -> [PermissionRecord] {
        throw SettingsViewModelTestError.permissionFailed
    }
}
