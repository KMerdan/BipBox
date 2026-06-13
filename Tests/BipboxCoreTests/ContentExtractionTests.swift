import BipboxCore
import XCTest

/// Verifies the content-extraction port: source code is now read directly, and
/// rich types (PDF/doc/image) are delegated to an injected FileTextExtracting.
final class ContentExtractionTests: XCTestCase {

    func testExtractsSourceCodeAsTextContent() async throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("Engine.swift")
        try "struct WorkflowEngine { func evaluate() {} }".write(to: file, atomically: true, encoding: .utf8)

        let service = DefaultMetadataExtractionService()
        let result = try await service.extractMetadata(for: profile(url: file, ext: "swift", uti: "public.swift-source"))
        XCTAssertEqual(result.metadata["text.content"]?.contains("WorkflowEngine"), true,
                       "source code should be extracted as text.content (it wasn't before)")
    }

    func testDelegatesRichTypesToInjectedExtractor() async throws {
        let pdfURL = URL(fileURLWithPath: "/tmp/report.pdf")
        let service = DefaultMetadataExtractionService(textExtractor: StubExtractor(text: "省エネ診断報告書 annual energy audit"))
        let result = try await service.extractMetadata(for: profile(url: pdfURL, ext: "pdf", uti: "com.adobe.pdf"))
        XCTAssertEqual(result.metadata["text.content"], "省エネ診断報告書 annual energy audit",
                       "rich types are delegated to the injected extractor")
    }

    func testUnsupportedTypeWithoutExtractorIsSkipped() async throws {
        let service = DefaultMetadataExtractionService(textExtractor: nil)
        let result = try await service.extractMetadata(for: profile(url: URL(fileURLWithPath: "/tmp/movie.mov"), ext: "mov", uti: "com.apple.quicktime-movie"))
        XCTAssertNil(result.metadata["text.content"])
        XCTAssertEqual(result.metadata["metadata.extraction.skipped"], "unsupportedType")
    }

    private func profile(url: URL, ext: String, uti: String) -> ItemProfile {
        ItemProfile(url: url, kind: .file, displayName: url.lastPathComponent,
                    fileExtension: ext, uniformTypeIdentifier: uti)
    }
}

private struct StubExtractor: FileTextExtracting {
    let text: String
    func extractText(from url: URL, uti: String?, maxCharacters: Int) async -> String? { text }
}
