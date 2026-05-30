import BipboxMenuBarUI
import XCTest

@MainActor
final class MenuBarStatusViewModelTests: XCTestCase {
    func testStatusMetadataChangesWithState() {
        let viewModel = MenuBarStatusViewModel(status: .running)

        XCTAssertEqual(viewModel.statusTitle, "Bipbox Running")
        XCTAssertEqual(viewModel.systemImageName, "tray.and.arrow.down")
        XCTAssertEqual(viewModel.pauseResumeTitle, "Pause Organizing")

        viewModel.update(status: .needsReview(2))

        XCTAssertEqual(viewModel.statusTitle, "2 Items in Inbox")
        XCTAssertEqual(viewModel.systemImageName, "exclamationmark.triangle")
        XCTAssertEqual(viewModel.pauseResumeTitle, "Pause Organizing")
    }

    func testPauseResumeCommandCallsHandlerWithoutOwningStateTransition() {
        let handler = MockMenuBarCommandHandler()
        let viewModel = MenuBarStatusViewModel(status: .running, commandHandler: handler)

        viewModel.togglePauseResume()
        XCTAssertEqual(handler.pauseCount, 1)
        XCTAssertEqual(handler.resumeCount, 0)
        XCTAssertEqual(viewModel.status, .running)

        viewModel.update(status: .paused)
        viewModel.togglePauseResume()

        XCTAssertEqual(handler.pauseCount, 1)
        XCTAssertEqual(handler.resumeCount, 1)
        XCTAssertEqual(viewModel.status, .paused)
    }

    func testMenuCommandsDelegateToHandler() {
        let handler = MockMenuBarCommandHandler()
        let viewModel = MenuBarStatusViewModel(commandHandler: handler)

        viewModel.openWorkspace()
        viewModel.showRecentActivity()
        viewModel.focusQuickSearch()
        viewModel.submitDroppedFileURLs([URL(fileURLWithPath: "/tmp/report.pdf")])
        viewModel.quit()

        XCTAssertEqual(handler.openWorkspaceCount, 1)
        XCTAssertEqual(handler.recentActivityCount, 1)
        XCTAssertEqual(handler.quickSearchCount, 1)
        XCTAssertEqual(handler.droppedURLs, [URL(fileURLWithPath: "/tmp/report.pdf")])
        XCTAssertEqual(handler.quitCount, 1)
    }

    func testOnChangeOnlyFiresWhenStateChanges() {
        let viewModel = MenuBarStatusViewModel(status: .running)
        var observed: [MenuBarStatus] = []
        viewModel.onChange = { status in
            observed.append(status)
        }

        viewModel.update(status: .running)
        viewModel.update(status: .error("Permission required"))

        XCTAssertEqual(observed, [.error("Permission required")])
    }
}

@MainActor
private final class MockMenuBarCommandHandler: MenuBarCommandHandling {
    private(set) var openWorkspaceCount = 0
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    private(set) var recentActivityCount = 0
    private(set) var quickSearchCount = 0
    private(set) var droppedURLs: [URL] = []
    private(set) var quitCount = 0

    func openWorkspace() {
        openWorkspaceCount += 1
    }

    func pauseOrganizer() {
        pauseCount += 1
    }

    func resumeOrganizer() {
        resumeCount += 1
    }

    func showRecentActivity() {
        recentActivityCount += 1
    }

    func focusQuickSearch() {
        quickSearchCount += 1
    }

    func submitDroppedFileURLs(_ urls: [URL]) {
        droppedURLs = urls
    }

    func quit() {
        quitCount += 1
    }
}
