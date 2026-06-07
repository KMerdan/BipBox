import BipboxCore
import XCTest

final class TargetClassifierTests: XCTestCase {
    private let classifier = DefaultTargetClassifier()
    private var roots: [URL] = []

    override func tearDown() {
        for url in roots { try? FileManager.default.removeItem(at: url) }
        roots = []
    }

    private func makeDir(_ build: (URL) throws -> Void) rethrows -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tc-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        roots.append(url)
        try build(url)
        return url
    }

    private func write(_ dir: URL, _ name: String) {
        try? "x".write(to: dir.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    func testDetectsProjectByMarker() throws {
        let repo = makeDir { write($0, "Package.swift"); write($0, "README.md") }
        XCTAssertEqual(classifier.classify(url: repo).nature, .project)

        let gitRepo = makeDir { dir in
            try? FileManager.default.createDirectory(at: dir.appendingPathComponent(".git"), withIntermediateDirectories: true)
            write(dir, "main.py")
        }
        XCTAssertEqual(classifier.classify(url: gitRepo).nature, .project)
    }

    func testDetectsWorkspaceOfProjects() {
        let workspace = makeDir { root in
            for name in ["alpha", "beta"] {
                let child = root.appendingPathComponent(name)
                try? FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
                write(child, "Cargo.toml")
            }
        }
        XCTAssertEqual(classifier.classify(url: workspace).nature, .workspace)
    }

    func testDetectsMediaAndDocuments() {
        let media = makeDir { write($0, "a.png"); write($0, "b.jpg"); write($0, "c.mov") }
        XCTAssertEqual(classifier.classify(url: media).nature, .media)

        let docs = makeDir { write($0, "a.pdf"); write($0, "b.docx"); write($0, "notes.txt") }
        XCTAssertEqual(classifier.classify(url: docs).nature, .documents)
    }

    func testRecommendsTopLevelByDefault() {
        let mixed = makeDir { write($0, "a.txt"); write($0, "b.png") }
        let c = classifier.classify(url: mixed)
        XCTAssertEqual(c.recommendedPolicy, .never, "Default capture is top-level — never interrogate the user")
    }
}
