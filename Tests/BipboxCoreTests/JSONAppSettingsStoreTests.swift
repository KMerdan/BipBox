import BipboxCore
import BipboxPersistence
import XCTest

final class JSONAppSettingsStoreTests: XCTestCase {
    func testMissingSettingsReturnsDefaults() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONAppSettingsStore(directoryURL: directory.url)

        let settings = try await store.load()

        XCTAssertEqual(settings, .defaults)
    }

    func testSavesAndLoadsSettings() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONAppSettingsStore(directoryURL: directory.url)
        let settings = AppSettings(
            automationState: .paused,
            launchAtLoginEnabled: true,
            aiEnabled: true,
            aiProvider: .anthropic,
            aiLocalOnlyModeEnabled: false,
            aiContentSharingEnabled: true,
            aiMetadataOnlyModeEnabled: false,
            aiAuditLoggingEnabled: true
        )

        try await store.save(settings)
        let reloadedStore = try JSONAppSettingsStore(directoryURL: directory.url)
        let loaded = try await reloadedStore.load()

        XCTAssertEqual(loaded, settings)
    }

    func testLoadsLegacySettingsWithPrivateAIDefaults() async throws {
        let directory = try TemporaryDirectory()
        let fileURL = directory.url.appendingPathComponent("settings.json")
        try Data(#"{"automationState":"paused","launchAtLoginEnabled":true}"#.utf8).write(to: fileURL)
        let store = try JSONAppSettingsStore(directoryURL: directory.url)

        let loaded = try await store.load()

        XCTAssertEqual(loaded.automationState, .paused)
        XCTAssertTrue(loaded.launchAtLoginEnabled)
        XCTAssertFalse(loaded.aiEnabled)
        XCTAssertEqual(loaded.aiProvider, .none)
        XCTAssertTrue(loaded.aiLocalOnlyModeEnabled)
        XCTAssertFalse(loaded.aiContentSharingEnabled)
        XCTAssertTrue(loaded.aiMetadataOnlyModeEnabled)
        XCTAssertTrue(loaded.aiAuditLoggingEnabled)
    }
}
