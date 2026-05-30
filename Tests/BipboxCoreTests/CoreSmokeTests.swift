import BipboxCore
import XCTest

final class CoreSmokeTests: XCTestCase {
    func testImportsCoreModule() {
        XCTAssertEqual(BipboxCoreInfo.schemaVersion, 1)
    }
}
