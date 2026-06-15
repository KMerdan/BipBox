import BipboxCore
import BipboxHarness
import BipboxWorkspaceUI
import XCTest

/// The clean item relations resolved by WorkspaceModel: `duplicate` (exact byte
/// fingerprint), `contains`/containingUnit (collection membership). Deterministic
/// — no embeddings required.
@MainActor
final class CleanGraphRelationsTests: XCTestCase {
    private var root: URL!
    private var harness: BipboxHarness!

    override func setUp() async throws {
        let fm = FileManager.default
        root = fm.temporaryDirectory.appendingPathComponent("clean-rel-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: root.appendingPathComponent("reports"), withIntermediateDirectories: true)
        // Two identical files (different names, different folders) → duplicates.
        let body = String(repeating: "identical content for the duplicate check. ", count: 400)
        try body.write(to: root.appendingPathComponent("original.md"), atomically: true, encoding: .utf8)
        try body.write(to: root.appendingPathComponent("reports/renamed-copy.md"), atomically: true, encoding: .utf8)
        try "a unique report".write(to: root.appendingPathComponent("reports/march.md"), atomically: true, encoding: .utf8)

        harness = try await makeStartedHarness()
        await harness.addFolder(root, depth: .always)
    }

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
        harness = nil
    }

    private func item(_ name: String) throws -> IndexedItem {
        try XCTUnwrap(harness.model.library.results.first { $0.displayName == name }, "no item \(name)")
    }

    func testDuplicatesAreLinkedNameIndependently() throws {
        let original = try item("original.md")
        let dups = harness.model.duplicates(of: original.id)
        XCTAssertEqual(dups.map(\.displayName), ["renamed-copy.md"],
                       "the renamed copy is recognized as an exact duplicate")
    }

    func testCollectionMemberResolvesItsContainer() throws {
        let march = try item("march.md")
        let container = try XCTUnwrap(harness.model.containingUnit(of: march.id),
                                      "a collection member resolves its container")
        XCTAssertEqual(container.displayName, "reports")
        let members = Set(harness.model.containedItems(of: container.id).map(\.displayName))
        XCTAssertTrue(members.contains("march.md"), "the container lists its members, got: \(members)")
    }

    func testLooseFileHasNoContainer() throws {
        // original.md is a top-level loose file → no containing unit.
        XCTAssertNil(harness.model.containingUnit(of: try item("original.md").id))
    }
}
