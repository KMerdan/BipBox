import BipboxWorkspaceUI
import XCTest

@MainActor
final class WorkspaceRootViewSmokeTests: XCTestCase {
    func testWorkspaceRootViewCanInitializeWithoutDropHandler() {
        let view = WorkspaceRootView()

        XCTAssertNotNil(String(describing: view))
    }

    func testWorkspaceRootViewCanInitializeWithViewModelsAndHandlers() {
        var dropped: [URL] = []
        let view = WorkspaceRootView(
            viewModels: WorkspaceViewModels(),
            openSettings: {},
            onDropURLs: { dropped = $0 }
        )

        XCTAssertNotNil(String(describing: view))
        XCTAssertTrue(dropped.isEmpty)
    }

    func testWorkspaceModelRendersEachSection() {
        let model = WorkspaceModel(WorkspaceViewModels())
        for nav in [WorkspaceNav.allItems, .recents, .inbox, .sources, .rules, .activity] {
            model.go(nav)
            XCTAssertEqual(model.section, nav)
        }
    }
}
