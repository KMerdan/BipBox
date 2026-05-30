import BipboxWorkspaceUI
import XCTest

@MainActor
final class WorkspaceStateTests: XCTestCase {
    func testDefaultsToOnboardingSection() {
        let state = WorkspaceState()

        XCTAssertEqual(state.selectedSection, .onboarding)
        XCTAssertFalse(state.isLoading)
        XCTAssertNil(state.dropSummary)
    }

    func testCanSelectEachWorkspaceSection() {
        let state = WorkspaceState()

        XCTAssertEqual(WorkspaceSection.allCases, [.onboarding, .inbox, .library, .rules, .activity, .settings])
        XCTAssertEqual(WorkspaceSection.inbox.title, "Intake")

        for section in WorkspaceSection.allCases {
            state.select(section)
            XCTAssertEqual(state.selectedSection, section)
            XCTAssertFalse(section.title.isEmpty)
            XCTAssertFalse(section.systemImage.isEmpty)
            XCTAssertFalse(section.placeholderDescription.isEmpty)
        }
    }

    func testLoadingStateCanBeToggled() {
        let state = WorkspaceState()

        state.setLoading(true)
        XCTAssertTrue(state.isLoading)

        state.setLoading(false)
        XCTAssertFalse(state.isLoading)
    }

    func testDropSummaryRecordsAcceptedAndFailedDrops() {
        let state = WorkspaceState()

        state.recordDropAccepted(itemCount: 1)
        XCTAssertEqual(state.dropSummary, "1 item received.")

        state.recordDropAccepted(itemCount: 3)
        XCTAssertEqual(state.dropSummary, "3 items received.")

        state.recordDropFailure("Drop did not contain files.")
        XCTAssertEqual(state.dropSummary, "Drop did not contain files.")

        state.clearDropSummary()
        XCTAssertNil(state.dropSummary)
    }
}
