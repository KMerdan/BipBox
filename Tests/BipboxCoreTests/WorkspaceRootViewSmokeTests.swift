import BipboxWorkspaceUI
import XCTest

@MainActor
final class WorkspaceRootViewSmokeTests: XCTestCase {
    func testWorkspaceRootViewCanInitializeWithoutDropHandler() {
        let view = WorkspaceRootView()

        XCTAssertNotNil(String(describing: view))
    }

    func testWorkspaceRootViewCanRenderEachSectionFixture() {
        for section in WorkspaceSection.allCases {
            let state = WorkspaceState(selectedSection: section)
            let view = WorkspaceRootView(state: state)

            XCTAssertNotNil(String(describing: view))
            XCTAssertEqual(state.selectedSection, section)
        }
    }
}
