import BipboxCore
import BipboxPersistence
import XCTest

final class JSONRuleDocumentStoreTests: XCTestCase {
    func testSavesLoadsAndDeletesRuleFiles() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONRuleDocumentStore(directoryURL: directory.url)
        let rule = ruleDocument(name: "PDF Documents", position: 2)

        try await store.saveRule(rule)

        let loaded = try await store.loadRules()
        XCTAssertEqual(loaded, [rule])
        let ruleFileURL = try await store.fileURL(for: rule.id)
        XCTAssertEqual(ruleFileURL?.pathExtension, "json")
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: directory.url.path)
                .contains { $0.hasSuffix(".json") && $0.contains(rule.id.uuidString.lowercased()) }
        )

        try await store.deleteRule(id: rule.id)

        let afterDelete = try await store.loadRules()
        XCTAssertEqual(afterDelete, [])
    }

    func testLoadedRulesAreSortedByPosition() async throws {
        let directory = try TemporaryDirectory()
        let store = try JSONRuleDocumentStore(directoryURL: directory.url)
        let later = ruleDocument(name: "Later", position: 10)
        let earlier = ruleDocument(name: "Earlier", position: 1)

        try await store.saveRule(later)
        try await store.saveRule(earlier)

        let loaded = try await store.loadRules()
        XCTAssertEqual(loaded, [earlier, later])
    }
}

private func ruleDocument(name: String, position: Int) -> RuleDocument {
    RuleDocument(
        id: UUID(uuidString: "20000000-0000-0000-0000-\(String(format: "%012d", position))")!,
        name: name,
        position: position,
        conditions: [
            ConditionDescriptor(field: .fileExtension, operation: .equals, value: "pdf")
        ],
        action: RuleActionDocument(operation: .move, destinationPath: "/Library/Documents")
    )
}
