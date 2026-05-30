import BipboxCore
import XCTest

final class DefaultMetadataExtractionServiceTests: XCTestCase {
    func testExtractsDeterministicNaturalLanguageSignalsFromTextFile() async throws {
        let directory = try TemporaryDirectory(name: "metadata-text-\(UUID().uuidString)")
        let fileURL = try directory.createFile(named: "invoice.md", contents: "Invoice for Acme Research project. Alice reviewed invoice notes.")
        let profile = try await FileSystemItemInspector().inspect(
            OrganizationRequest(
                source: .manualImport,
                itemURL: fileURL,
                itemKind: .file,
                receivedAt: TestClock.now,
                mode: .indexOnly
            ),
            options: InspectionOptions()
        )
        let extractor = DefaultMetadataExtractionService()

        let result = try await extractor.extractMetadata(for: profile)

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.metadata["metadata.extractor"], "local")
        XCTAssertEqual(result.metadata["nl.backend"], "NLTagger")
        XCTAssertTrue(result.metadata["nl.tokens"]?.contains("invoice") == true)
        XCTAssertTrue(result.metadata["nl.tokens"]?.contains("acme") == true)
        XCTAssertEqual(result.metadata["resource.displayName"], "invoice.md")
    }

    func testUnsupportedFolderProducesRecoverableSkipMetadata() async throws {
        let directory = try TemporaryDirectory(name: "metadata-folder-\(UUID().uuidString)")
        let folderURL = try directory.createFolder(named: "Project")
        let profile = ItemProfile(
            url: folderURL,
            kind: .folder,
            displayName: "Project",
            source: .manualImport
        )
        let extractor = DefaultMetadataExtractionService()

        let result = try await extractor.extractMetadata(for: profile)

        XCTAssertEqual(result.warnings, [])
        XCTAssertEqual(result.metadata["metadata.extraction.skipped"], "nonFile")
    }

    func testUnreadableTextProducesWarningWithoutThrowing() async throws {
        let profile = ItemProfile(
            url: URL(fileURLWithPath: "/tmp/bipbox-missing-\(UUID().uuidString).txt"),
            kind: .file,
            displayName: "missing.txt",
            fileExtension: "txt",
            source: .manualImport
        )
        let extractor = DefaultMetadataExtractionService()

        let result = try await extractor.extractMetadata(for: profile)

        XCTAssertEqual(result.warnings.count, 1)
        XCTAssertEqual(result.metadata["metadata.extraction.warningCount"], "1")
    }
}
