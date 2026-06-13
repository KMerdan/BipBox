import BipboxCore
import XCTest

/// The descent/collection node model: project folders are single units (stop),
/// non-project folders collapse into collections with individually-listed
/// members, junk dirs are pruned, and exact byte duplicates are flagged.
final class FilesystemDescenderTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("descender-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    private func write(_ rel: String, _ contents: String = "x") throws {
        let url = root.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try contents.write(to: url, atomically: true, encoding: .utf8)
    }

    private func descend() -> [DescentUnit] {
        FilesystemDescender().descend(root: root)
    }

    func testProjectFolderIsOneUnitAndStopsDescent() throws {
        try write("myrepo/Package.swift", "// swift-tools-version: 6.0")
        try write("myrepo/Sources/App/main.swift", "print(1)")
        try write("loose.md", "# notes")

        let units = descend()
        let project = units.first { $0.kind == .project }
        XCTAssertEqual(project?.url.lastPathComponent, "myrepo")
        XCTAssertEqual(project?.markers, ["Package.swift"])
        XCTAssertFalse(units.contains { $0.url.lastPathComponent == "main.swift" },
                       "project internals must not be emitted")
        XCTAssertTrue(units.contains { $0.kind == .file && $0.url.lastPathComponent == "loose.md" && $0.collectionURL == nil })
    }

    func testNonProjectFolderCollapsesIntoCollectionWithMembers() throws {
        try write("FTA_Data/report1.md", "fault tree analysis")
        try write("FTA_Data/nested/report2.md", "fault tree analysis 2")

        let units = descend()
        let collection = units.first { $0.kind == .collection }
        XCTAssertEqual(collection?.url.lastPathComponent, "FTA_Data")
        let members = units.filter { $0.kind == .file && $0.collectionURL == collection?.url }
        XCTAssertEqual(Set(members.map(\.url.lastPathComponent)), ["report1.md", "report2.md"],
                       "all subtree files are members of the one collection")
    }

    func testCollectionSplitsOutDeeplyNestedProject() throws {
        // The one-level lookahead sees no project child -> "conference" is a
        // collection; the project two levels down is split out during the
        // member walk (a collection never swallows a project).
        try write("conference/slides.pdf")
        try write("conference/sessions/agenda.md", "schedule")
        try write("conference/sessions/demo-app/package.json", "{\"name\": \"demo\"}")
        try write("conference/sessions/demo-app/index.js", "console.log(1)")

        let units = descend()
        XCTAssertTrue(units.contains { $0.kind == .collection && $0.url.lastPathComponent == "conference" })
        XCTAssertTrue(units.contains { $0.kind == .project && $0.url.lastPathComponent == "demo-app" })
        XCTAssertFalse(units.contains { $0.url.lastPathComponent == "index.js" })
        let members = units.filter { $0.kind == .file && $0.collectionURL != nil }
        XCTAssertEqual(Set(members.map(\.url.lastPathComponent)), ["slides.pdf", "agenda.md"],
                       "members exclude everything inside the split-out project")
    }

    func testContainerWithProjectChildDescends() throws {
        try write("localGit/repo-a/.git/HEAD", "ref:")
        try write("localGit/repo-a/main.py", "pass")
        try write("localGit/notes.txt", "scratch")

        let units = descend()
        XCTAssertTrue(units.contains { $0.kind == .project && $0.url.lastPathComponent == "repo-a" },
                      ".git marks a project even one level down")
        XCTAssertFalse(units.contains { $0.kind == .collection && $0.url.lastPathComponent == "localGit" },
                       "a folder holding projects is a container, not a collection")
        XCTAssertTrue(units.contains { $0.kind == .file && $0.url.lastPathComponent == "notes.txt" && $0.collectionURL == nil },
                      "container files are loose files")
    }

    func testWorkspaceMonorepoSurfacesMemberProjects() throws {
        try write("mono/package.json", "{}")
        try write("mono/pnpm-workspace.yaml", "packages: ['*']")
        try write("mono/web/package.json", "{\"name\": \"web\"}")
        try write("mono/web/index.js", "x")

        let units = descend()
        XCTAssertTrue(units.contains { $0.kind == .project && $0.url.lastPathComponent == "mono" })
        XCTAssertTrue(units.contains { $0.kind == .workspaceMember && $0.url.lastPathComponent == "web" },
                      "immediate child projects of a workspace are surfaced as members")
        XCTAssertFalse(units.contains { $0.url.lastPathComponent == "index.js" })
    }

    func testPrunesJunkDirectories() throws {
        try write("webapp/package.json", "{}")
        try write("stuff/node_modules/lib/index.js", "x")
        try write("stuff/doc.md", "hello")

        let units = descend()
        XCTAssertFalse(units.contains { $0.url.path.contains("node_modules") })
        XCTAssertTrue(units.contains { $0.kind == .collection && $0.url.lastPathComponent == "stuff" })
    }

    func testBundleIsOpaqueUnit() throws {
        try write("Export.photoslibrary/database/photos.db", "blob")

        let units = descend()
        XCTAssertEqual(units.filter { $0.kind == .bundle }.map(\.url.lastPathComponent), ["Export.photoslibrary"])
        XCTAssertFalse(units.contains { $0.url.lastPathComponent == "photos.db" })
    }

    func testExactDuplicatesAreFlaggedNameIndependently() throws {
        let contents = String(repeating: "same bytes, different name. ", count: 600) // > 8 KiB
        try write("a.md", contents)
        try write("deeper/renamed-copy.md", contents)
        try write("deeper/unique.md", "different bytes")

        let units = descend()
        let dups = units.filter(\.isDuplicate)
        XCTAssertEqual(dups.map(\.url.lastPathComponent), ["renamed-copy.md"],
                       "the shortest path is primary; the renamed copy is the duplicate")
        XCTAssertFalse(units.first { $0.url.lastPathComponent == "unique.md" }!.isDuplicate)
    }
}
