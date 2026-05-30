import BipboxCore
import XCTest

final class FileSystemItemInspectorTests: XCTestCase {
    func testInspectsRegularFileProfile() async throws {
        let directory = try TemporaryDirectory(name: "inspector-file-\(UUID().uuidString)")
        let fileURL = try directory.createFile(named: "report.txt", contents: "hello")
        let request = ItemFixtures.request(url: fileURL, kind: .file)

        let profile = try await FileSystemItemInspector().inspect(
            request,
            options: InspectionOptions(includeContentHash: true)
        )

        XCTAssertEqual(profile.kind, .file)
        XCTAssertEqual(profile.displayName, "report.txt")
        XCTAssertEqual(profile.fileExtension, "txt")
        XCTAssertEqual(profile.sizeBytes, 5)
        XCTAssertEqual(profile.source, .dragDrop)
        XCTAssertEqual(profile.contentHash?.count, 64)
        XCTAssertNil(profile.folderChildSummary)
    }

    func testInspectsFolderAsSingleItem() async throws {
        let directory = try TemporaryDirectory(name: "inspector-folder-\(UUID().uuidString)")
        let folderURL = try directory.createFolder(named: "Project")
        _ = try directory.createFile(named: "Project/top.pdf", contents: "pdf")
        let nestedURL = folderURL.appendingPathComponent("Nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nestedURL, withIntermediateDirectories: true)
        try "nested".data(using: .utf8)?.write(
            to: nestedURL.appendingPathComponent("inside.txt", isDirectory: false)
        )
        let request = ItemFixtures.request(url: folderURL, kind: .folder)

        let profile = try await FileSystemItemInspector().inspect(request, options: InspectionOptions())

        XCTAssertEqual(profile.kind, .folder)
        XCTAssertEqual(profile.displayName, "Project")
        XCTAssertEqual(profile.folderChildSummary?.visibleChildCount, 2)
        XCTAssertEqual(profile.folderChildSummary?.visibleFileCount, 1)
        XCTAssertEqual(profile.folderChildSummary?.visibleFolderCount, 1)
        XCTAssertEqual(profile.folderChildSummary?.topLevelExtensions["pdf"], 1)
        XCTAssertNil(profile.folderChildSummary?.topLevelExtensions["txt"])
        XCTAssertEqual(profile.folderChildSummary?.recursiveInspectionRequested, false)
    }

    func testRecursiveFolderInspectionMustBeExplicit() async throws {
        let directory = try TemporaryDirectory(name: "inspector-recursive-\(UUID().uuidString)")
        let folderURL = try directory.createFolder(named: "Project")
        let request = ItemFixtures.request(url: folderURL, kind: .folder)

        let defaultProfile = try await FileSystemItemInspector().inspect(request, options: InspectionOptions())
        let explicitProfile = try await FileSystemItemInspector().inspect(
            request,
            options: InspectionOptions(allowRecursiveFolderInspection: true)
        )

        XCTAssertEqual(defaultProfile.folderChildSummary?.recursiveInspectionRequested, false)
        XCTAssertEqual(explicitProfile.folderChildSummary?.recursiveInspectionRequested, true)
    }

    func testFolderChildrenAreNotReturnedAsOrganizationRequests() async throws {
        let directory = try TemporaryDirectory(name: "inspector-no-child-requests-\(UUID().uuidString)")
        let folderURL = try directory.createFolder(named: "DropMe")
        _ = try directory.createFile(named: "DropMe/a.txt", contents: "a")
        _ = try directory.createFile(named: "DropMe/b.txt", contents: "b")
        let request = ItemFixtures.request(url: folderURL, kind: .folder)

        let profile = try await FileSystemItemInspector().inspect(request, options: InspectionOptions())

        XCTAssertEqual(profile.url, folderURL)
        XCTAssertEqual(profile.kind, .folder)
        XCTAssertEqual(profile.folderChildSummary?.visibleChildCount, 2)
        XCTAssertEqual(profile.folderChildSummary?.recursiveInspectionRequested, false)
    }

    func testMissingItemThrowsInspectionError() async {
        let missingURL = URL(fileURLWithPath: "/tmp/bipbox-missing-\(UUID().uuidString)")
        let request = ItemFixtures.request(url: missingURL, kind: .file)

        do {
            _ = try await FileSystemItemInspector().inspect(request, options: InspectionOptions())
            XCTFail("Expected missing item inspection to throw.")
        } catch let error as ItemInspectionError {
            XCTAssertEqual(error, .itemMissing(missingURL))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}

