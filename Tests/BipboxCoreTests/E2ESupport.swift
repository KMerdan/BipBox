import BipboxCore
import BipboxHarness
import Foundation
import XCTest

/// Shared helpers for the principle-driven acceptance suite.
enum E2ESupport {
    /// A realistic project tree spanning many type categories + nested folders.
    static func makeDummyProject() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("DummyProject-\(UUID().uuidString)", isDirectory: true)
        func write(_ rel: String, _ contents: String) throws {
            let url = root.appendingPathComponent(rel)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try contents.write(to: url, atomically: true, encoding: .utf8)
        }
        try write("README.md", "# Dummy Project\nquarterly report and budget")
        try write("report.pdf", "annual report Q3 finances")
        try write("budget.csv", "item,amount\nrent,1000")
        try write("diagram.png", "png-bytes")
        try write("photo.jpg", "jpg-bytes")
        try write("notes.txt", "meeting notes about the report")
        try write("archive.zip", "zip-bytes")
        try write("src/main.swift", "print(\"hello\")")
        try write("src/util.swift", "func add() {}")
        try write("docs/spec.pdf", "specification document")
        return root
    }
}

@MainActor
func makeStartedHarness() async throws -> BipboxHarness {
    let harness = try BipboxHarness()
    await harness.start()
    return harness
}
