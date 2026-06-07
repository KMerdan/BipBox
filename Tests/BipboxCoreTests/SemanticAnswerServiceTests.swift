import BipboxAI
import BipboxCore
import XCTest

final class SemanticAnswerServiceTests: XCTestCase {
    private func result(_ name: String, _ text: String) -> RetrievalResult {
        RetrievalResult(
            item: IndexedItem(currentPath: "/x/\(name)", displayName: name, kind: .file,
                              importedAt: Date(timeIntervalSince1970: 1_800_000_000),
                              extractedText: text, status: .indexedOnly),
            score: 0.9, explanations: ["match"]
        )
    }

    // MARK: graceful degradation with no LLM

    func testNoLLMPassesQueryThroughAndYieldsNoAnswer() async {
        let service = SemanticAnswerService()  // UnavailableLLMProvider
        XCTAssertFalse(service.isAvailable)
        let expanded = await service.expandQuery("where is my tax stuff")
        XCTAssertEqual(expanded, "where is my tax stuff", "Without an LLM, query is unchanged")
        let answer = await service.answer(to: "taxes?", using: [result("a.pdf", "tax return")])
        XCTAssertNil(answer, "Without an LLM, no synthesized answer (results still shown by the UI)")
    }

    // MARK: with an LLM (fake)

    func testExpandQueryUsesLLMWhenAvailable() async {
        let service = SemanticAnswerService(provider: FakeLLM(reply: "tax invoice finance"))
        let expanded = await service.expandQuery("the money paperwork")
        XCTAssertEqual(expanded, "tax invoice finance")
    }

    func testAnswerSynthesizesCitedResponse() async throws {
        let service = SemanticAnswerService(provider: FakeLLM(reply: "Your taxes are in annual_finance.pdf [1]."))
        let answer = await service.answer(to: "where are my taxes?", using: [
            result("annual_finance.pdf", "annual tax return 2023"),
            result("cats.zip", "kitten photos")
        ])
        let a = try XCTUnwrap(answer)
        XCTAssertEqual(a.text, "Your taxes are in annual_finance.pdf [1].")
        XCTAssertEqual(a.citations.first?.name, "annual_finance.pdf")
        XCTAssertEqual(a.citations.count, 2)
    }
}

private struct FakeLLM: LLMProvider {
    let reply: String
    var isAvailable: Bool { true }
    var modelID: String { "fake-llm" }
    func complete(_ request: LLMRequest) async throws -> LLMResponse {
        LLMResponse(text: reply, modelID: modelID)
    }
}
