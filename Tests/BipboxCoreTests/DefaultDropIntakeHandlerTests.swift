import BipboxCore
import XCTest

final class DefaultDropIntakeHandlerTests: XCTestCase {
    func testSubmitsDroppedFileAsOrganizationRequest() async throws {
        let directory = try TemporaryDirectory(name: "drop-file-\(UUID().uuidString)")
        let fileURL = try directory.createFile(named: "report.pdf")
        let intake = MockIntakeService()
        let handler = DefaultDropIntakeHandler(
            intakeService: intake,
            itemInspector: FileSystemItemInspector()
        )

        let summary = await handler.submit(fileURLs: [fileURL], receivedAt: TestClock.now)

        XCTAssertEqual(summary.acceptedCount, 1)
        XCTAssertEqual(summary.failures, [])
        XCTAssertEqual(intake.submitted.map(\.itemURL), [fileURL])
        XCTAssertEqual(intake.submitted.map(\.itemKind), [.file])
        XCTAssertEqual(intake.submitted.map(\.source), [.dragDrop])
    }

    func testSubmitsDroppedFolderAsOneOrganizationRequest() async throws {
        let directory = try TemporaryDirectory(name: "drop-folder-\(UUID().uuidString)")
        let folderURL = try directory.createFolder(named: "Project")
        _ = try directory.createFile(named: "Project/inside.txt")
        let intake = MockIntakeService()
        let handler = DefaultDropIntakeHandler(
            intakeService: intake,
            itemInspector: FileSystemItemInspector()
        )

        let summary = await handler.submit(fileURLs: [folderURL], receivedAt: TestClock.now)

        XCTAssertEqual(summary.acceptedCount, 1)
        XCTAssertEqual(summary.failures, [])
        XCTAssertEqual(intake.submitted.count, 1)
        XCTAssertEqual(intake.submitted.first?.itemURL, folderURL)
        XCTAssertEqual(intake.submitted.first?.itemKind, .folder)
    }

    func testMultiItemMenuBarDropSharesCaptureSessionAndSource() async throws {
        let directory = try TemporaryDirectory(name: "drop-session-\(UUID().uuidString)")
        let firstURL = try directory.createFile(named: "first.pdf")
        let secondURL = try directory.createFile(named: "second.pdf")
        let intake = MockIntakeService()
        let sourceStore = MockSourceStore()
        let handler = DefaultDropIntakeHandler(
            intakeService: intake,
            itemInspector: FileSystemItemInspector(),
            sourceStore: sourceStore
        )

        let summary = await handler.submit(
            fileURLs: [firstURL, secondURL],
            source: .dragDrop,
            mode: .indexOnly,
            receivedAt: TestClock.now
        )

        let sources = try await sourceStore.enabledSources(kind: .menuBarDrop)
        let captureSessionIDs = Set(intake.submitted.compactMap { $0.userContext["captureSessionID"] })
        XCTAssertEqual(summary.acceptedCount, 2)
        XCTAssertEqual(sources.count, 1)
        XCTAssertEqual(Set(intake.submitted.map(\.sourceID)), [sources[0].id])
        XCTAssertEqual(captureSessionIDs.count, 1)
        XCTAssertEqual(Set(intake.submitted.map { $0.userContext["captureSource"] }), [CaptureSource.menuBarDrop.rawValue])
        XCTAssertEqual(Set(intake.submitted.map(\.itemURL)), [firstURL, secondURL])
    }

    func testManualImportUsesManualImportSourceKind() async throws {
        let directory = try TemporaryDirectory(name: "manual-import-\(UUID().uuidString)")
        let fileURL = try directory.createFile(named: "notes.md")
        let intake = MockIntakeService()
        let sourceStore = MockSourceStore()
        let handler = DefaultDropIntakeHandler(
            intakeService: intake,
            itemInspector: FileSystemItemInspector(),
            sourceStore: sourceStore
        )

        _ = await handler.submit(
            fileURLs: [fileURL],
            source: .manualImport,
            mode: .indexOnly,
            receivedAt: TestClock.now
        )

        let manualSources = try await sourceStore.enabledSources(kind: .manualImport)
        let source = try XCTUnwrap(manualSources.first)
        XCTAssertEqual(intake.submitted.first?.source, .manualImport)
        XCTAssertEqual(intake.submitted.first?.sourceID, source.id)
        XCTAssertEqual(intake.submitted.first?.userContext["sourceKind"], SourceKind.manualImport.rawValue)
        XCTAssertEqual(intake.submitted.first?.userContext["captureSource"], CaptureSource.manualImport.rawValue)
    }

    func testInspectorUsesNonRecursiveFolderOptions() async {
        let folderURL = URL(fileURLWithPath: "/tmp/Project", isDirectory: true)
        let intake = MockIntakeService()
        let inspector = CapturingDropInspector(profile: ItemFixtures.folderProfile(url: folderURL))
        let handler = DefaultDropIntakeHandler(intakeService: intake, itemInspector: inspector)

        _ = await handler.submit(fileURLs: [folderURL], receivedAt: TestClock.now)

        XCTAssertEqual(inspector.options.map(\.allowRecursiveFolderInspection), [false])
        XCTAssertEqual(inspector.options.map(\.includeShallowFolderSummary), [true])
    }

    func testNonFileURLReturnsStructuredFailure() async {
        let intake = MockIntakeService()
        let handler = DefaultDropIntakeHandler(
            intakeService: intake,
            itemInspector: MockItemInspector(profile: ItemFixtures.fileProfile())
        )
        let remoteURL = URL(string: "https://example.com/report.pdf")!

        let summary = await handler.submit(fileURLs: [remoteURL], receivedAt: TestClock.now)

        XCTAssertEqual(summary.results, [])
        XCTAssertEqual(summary.failures, [
            DropIntakeFailure(itemURL: remoteURL, message: "Only file URLs can be dropped.")
        ])
        XCTAssertEqual(intake.submitted, [])
    }

    func testMissingDroppedItemReturnsStructuredFailure() async {
        let intake = MockIntakeService()
        let missingURL = URL(fileURLWithPath: "/tmp/bipbox-missing-drop-\(UUID().uuidString)")
        let handler = DefaultDropIntakeHandler(
            intakeService: intake,
            itemInspector: FileSystemItemInspector()
        )

        let summary = await handler.submit(fileURLs: [missingURL], receivedAt: TestClock.now)

        XCTAssertEqual(summary.results, [])
        XCTAssertEqual(summary.failures.count, 1)
        XCTAssertEqual(summary.failures.first?.itemURL, missingURL)
        XCTAssertTrue(summary.failures.first?.message.contains("does not exist") ?? false)
        XCTAssertEqual(intake.submitted, [])
    }
}

private final class CapturingDropInspector: ItemInspector {
    let profile: ItemProfile
    private(set) var options: [InspectionOptions] = []

    init(profile: ItemProfile) {
        self.profile = profile
    }

    func inspect(_ request: OrganizationRequest, options: InspectionOptions) async throws -> ItemProfile {
        self.options.append(options)
        return profile
    }
}
