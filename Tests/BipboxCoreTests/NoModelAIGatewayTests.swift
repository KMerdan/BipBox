import BipboxAI
import BipboxCore
import XCTest

final class NoModelAIGatewayTests: XCTestCase {
    func testPlaceholderClassificationRequiresReviewAndDoesNotSuggestDestination() async throws {
        let gateway = NoModelAIGateway()
        let request = AIRequest(
            itemProfile: ItemFixtures.fileProfile(),
            allowedTools: ["search.index", "operation.plan"]
        )

        let classification = try await gateway.classify(request)

        XCTAssertNil(classification.category)
        XCTAssertNil(classification.suggestedDestinationURL)
        XCTAssertEqual(classification.confidence, 0)
        XCTAssertEqual(classification.requiredTools, ["search.index", "operation.plan"])
        XCTAssertEqual(classification.reviewRequirement, .required)
        XCTAssertTrue(classification.reason.contains("No AI model"))
    }

    func testRequestsCanIncludeFileAndFolderProfiles() async throws {
        let gateway = NoModelAIGateway()

        _ = try await gateway.classify(AIRequest(itemProfile: ItemFixtures.fileProfile()))
        _ = try await gateway.classify(AIRequest(itemProfile: ItemFixtures.folderProfile()))

        XCTAssertEqual(gateway.classifications.map(\.itemKind), [.file, .folder])
    }

    func testRemoteContentSharingDefaultsToDisabled() {
        let request = AIRequest(itemProfile: ItemFixtures.fileProfile())

        XCTAssertFalse(AIGatewayDefaults.remoteContentSharingAllowed)
        XCTAssertFalse(request.remoteContentSharingAllowed)
    }

    func testPrivacySnapshotRecordsFlagsWithoutUploadingContent() async throws {
        let gateway = NoModelAIGateway()
        var profile = ItemFixtures.fileProfile()
        profile.extractedTextSummary = "local summary only"
        let request = AIRequest(
            itemProfile: profile,
            allowedTools: ["activity.recent"],
            remoteContentSharingAllowed: false
        )

        _ = try await gateway.classify(request)

        XCTAssertEqual(gateway.classifications, [
            AIPrivacySnapshot(
                remoteContentSharingAllowed: false,
                itemKind: .file,
                includesExtractedTextSummary: true,
                allowedToolCount: 1
            )
        ])
    }

    func testToolCallsAreUnavailableWithoutModel() async {
        let gateway = NoModelAIGateway()
        let call = ToolCall(toolName: "operation.execute", input: [:], requestedPermissions: [.write])

        do {
            _ = try await gateway.callTool(call, context: ExecutionContext(dryRun: true))
            XCTFail("Expected tool use to be unavailable.")
        } catch let error as AIGatewayError {
            XCTAssertEqual(error, .toolUseUnavailable("operation.execute"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testNoModelAgentBuildsApprovalPlanWithoutMutating() async throws {
        let registry = DefaultToolRegistry()
        try await registry.register(
            ToolDescriptor(
                name: "knowledge.add_collection",
                description: "Create collection",
                inputSchema: "{}",
                outputSchema: "{}",
                permissions: [.read, .write],
                dryRunSupported: true,
                reversible: true
            )
        ) { _, _ in
            XCTFail("No-model agent must not execute tools.")
            return ToolResult(toolName: "knowledge.add_collection")
        }
        let agent = NoModelAgentOrchestrator(toolRegistry: registry)
        let call = ToolCall(
            toolName: "knowledge.add_collection",
            input: ["name": "Research"],
            requestedPermissions: [.read, .write]
        )

        let response = try await agent.respond(
            to: AgentRequest(intent: "Create a research collection", mode: .requestApproval, proposedToolCalls: [call]),
            context: ExecutionContext(actor: "test")
        )

        XCTAssertEqual(response.mode, .requestApproval)
        XCTAssertEqual(response.proposedPlan.steps.first?.status, .requiresApproval)
        XCTAssertEqual(response.requiredApprovals.first?.toolName, "knowledge.add_collection")
        XCTAssertEqual(response.executionSummary, "No tools executed.")
    }

    func testNoModelAgentUnknownToolFailsSafely() async throws {
        let agent = NoModelAgentOrchestrator(toolRegistry: DefaultToolRegistry())

        do {
            _ = try await agent.respond(
                to: AgentRequest(
                    intent: "Use missing tool",
                    mode: .propose,
                    proposedToolCalls: [ToolCall(toolName: "missing", input: [:], requestedPermissions: [.read])]
                ),
                context: ExecutionContext(actor: "test")
            )
            XCTFail("Expected unknown tool failure.")
        } catch let error as ToolRegistryError {
            XCTAssertEqual(error, .unknownTool("missing"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
