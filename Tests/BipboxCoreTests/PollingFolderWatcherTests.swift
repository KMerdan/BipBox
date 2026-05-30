import BipboxCore
import BipboxMacOSAdapters
import XCTest

final class PollingFolderWatcherTests: XCTestCase {
    func testEmitsRequestForNewTopLevelFile() async throws {
        let directory = try TemporaryDirectory(name: "watcher-file-\(UUID().uuidString)")
        let intake = MockIntakeService()
        let watcher = PollingFolderWatcher(
            configuration: FolderWatchConfiguration(folderURL: directory.url),
            intakeService: intake
        )

        try await watcher.start()
        let fileURL = try directory.createFile(named: "download.pdf")
        let requests = try await watcher.scanNow(receivedAt: TestClock.now)

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.itemURL, fileURL)
        XCTAssertEqual(requests.first?.itemKind, .file)
        XCTAssertEqual(requests.first?.source, .watchedFolder)
        XCTAssertEqual(intake.submitted.map(\.itemURL), [fileURL])
    }

    func testEmittedRequestIncludesConfiguredSourceDetail() async throws {
        let directory = try TemporaryDirectory(name: "watcher-source-detail-\(UUID().uuidString)")
        let intake = MockIntakeService()
        let sourceID = UUID(uuidString: "65000000-0000-0000-0000-000000000001")!
        let watcher = PollingFolderWatcher(
            configuration: FolderWatchConfiguration(
                folderURL: directory.url,
                sourceID: sourceID,
                sourceDetail: [
                    "captureLocation": "downloads",
                    "watchFolderID": "fixture"
                ]
            ),
            intakeService: intake
        )

        try await watcher.start()
        _ = try directory.createFile(named: "download.pdf")
        let requests = try await watcher.scanNow(receivedAt: TestClock.now)

        XCTAssertEqual(requests.first?.userContext["captureLocation"], "downloads")
        XCTAssertEqual(requests.first?.userContext["watchFolderID"], "fixture")
        XCTAssertEqual(requests.first?.sourceID, sourceID)
        XCTAssertEqual(intake.submitted.first?.userContext["captureLocation"], "downloads")
        XCTAssertEqual(intake.submitted.first?.sourceID, sourceID)
    }

    func testEmitsOneRequestForNewTopLevelFolder() async throws {
        let directory = try TemporaryDirectory(name: "watcher-folder-\(UUID().uuidString)")
        let intake = MockIntakeService()
        let watcher = PollingFolderWatcher(
            configuration: FolderWatchConfiguration(folderURL: directory.url),
            intakeService: intake
        )

        try await watcher.start()
        let folderURL = try directory.createFolder(named: "Project")
        _ = try directory.createFile(named: "Project/inside.txt")
        let requests = try await watcher.scanNow(receivedAt: TestClock.now)

        XCTAssertEqual(requests.count, 1)
        XCTAssertEqual(requests.first?.itemURL, folderURL)
        XCTAssertEqual(requests.first?.itemKind, .folder)
        XCTAssertEqual(intake.submitted.count, 1)
    }

    func testNestedChildChangesDoNotCreateChildRequestsByDefault() async throws {
        let directory = try TemporaryDirectory(name: "watcher-nested-\(UUID().uuidString)")
        let intake = MockIntakeService()
        let folderURL = try directory.createFolder(named: "Project")
        let watcher = PollingFolderWatcher(
            configuration: FolderWatchConfiguration(folderURL: directory.url),
            intakeService: intake
        )

        try await watcher.start()
        _ = try directory.createFile(named: "Project/new-child.txt")
        let requests = try await watcher.scanNow(receivedAt: TestClock.now)

        XCTAssertEqual(requests, [])
        XCTAssertEqual(intake.submitted, [])
        XCTAssertTrue(FileManager.default.fileExists(atPath: folderURL.path))
    }

    func testDoesNotDuplicateRequestsAcrossScans() async throws {
        let directory = try TemporaryDirectory(name: "watcher-duplicate-\(UUID().uuidString)")
        let intake = MockIntakeService()
        let watcher = PollingFolderWatcher(
            configuration: FolderWatchConfiguration(folderURL: directory.url),
            intakeService: intake
        )

        try await watcher.start()
        let fileURL = try directory.createFile(named: "download.pdf")
        let first = try await watcher.scanNow(receivedAt: TestClock.now)
        let second = try await watcher.scanNow(receivedAt: TestClock.now.addingTimeInterval(1))

        XCTAssertEqual(first.map(\.itemURL), [fileURL])
        XCTAssertEqual(second, [])
        XCTAssertEqual(intake.submitted.count, 1)
    }

    func testPauseAndResumeControlEmission() async throws {
        let directory = try TemporaryDirectory(name: "watcher-pause-\(UUID().uuidString)")
        let intake = MockIntakeService()
        let watcher = PollingFolderWatcher(
            configuration: FolderWatchConfiguration(folderURL: directory.url),
            intakeService: intake
        )

        try await watcher.start()
        await watcher.pause()
        let pausedState = await watcher.state
        XCTAssertEqual(pausedState, .paused)

        let pausedFileURL = try directory.createFile(named: "paused.txt")
        let pausedRequests = try await watcher.scanNow(receivedAt: TestClock.now)

        try await watcher.resume()
        let resumedState = await watcher.state
        XCTAssertEqual(resumedState, .running)
        let resumedRequests = try await watcher.scanNow(receivedAt: TestClock.now)

        XCTAssertEqual(pausedRequests, [])
        XCTAssertEqual(resumedRequests.map(\.itemURL), [pausedFileURL])
        XCTAssertEqual(intake.submitted.map(\.itemURL), [pausedFileURL])
    }

    func testStopClearsStateAndSuppressesScan() async throws {
        let directory = try TemporaryDirectory(name: "watcher-stop-\(UUID().uuidString)")
        let intake = MockIntakeService()
        let watcher = PollingFolderWatcher(
            configuration: FolderWatchConfiguration(folderURL: directory.url),
            intakeService: intake
        )

        try await watcher.start()
        await watcher.stop()
        _ = try directory.createFile(named: "ignored.txt")
        let requests = try await watcher.scanNow(receivedAt: TestClock.now)
        let stoppedState = await watcher.state

        XCTAssertEqual(stoppedState, .stopped)
        XCTAssertEqual(requests, [])
        XCTAssertEqual(intake.submitted, [])
    }

    func testStartFailsForMissingWatchedFolder() async {
        let missingURL = URL(fileURLWithPath: "/tmp/bipbox-missing-watch-\(UUID().uuidString)")
        let watcher = PollingFolderWatcher(
            configuration: FolderWatchConfiguration(folderURL: missingURL),
            intakeService: MockIntakeService()
        )

        do {
            try await watcher.start()
            XCTFail("Expected missing watched folder failure.")
        } catch let error as FolderWatcherError {
            XCTAssertEqual(error, .watchedFolderMissing(missingURL))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
