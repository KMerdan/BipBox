import BipboxAI
import BipboxCore
import XCTest

final class ToolBackedAIOrchestratorTests: XCTestCase {
    func testAllowedReadToolCallExecutesThroughRegistry() async throws {
        let registry = DefaultToolRegistry()
        try await registry.register(aiToolDescriptor(name: "search.index", permissions: [.read])) { call, context in
            ToolResult(
                toolName: call.toolName,
                output: ["query": call.input["query"] ?? "", "actor": context.actor],
                message: "searched"
            )
        }
        let orchestrator = ToolBackedAIOrchestrator(toolRegistry: registry)

        let result = try await orchestrator.callTool(
            ToolCall(toolName: "search.index", input: ["query": "invoice"], requestedPermissions: [.read]),
            context: ExecutionContext(actor: "ai")
        )

        XCTAssertEqual(result.toolName, "search.index")
        XCTAssertEqual(result.output["query"], "invoice")
        XCTAssertEqual(result.output["actor"], "ai")
        XCTAssertEqual(result.message, "searched")
    }

    func testDeniedWriteToolCallFailsExplicitly() async throws {
        let registry = DefaultToolRegistry()
        try await registry.register(aiToolDescriptor(name: "search.index", permissions: [.read]))
        let orchestrator = ToolBackedAIOrchestrator(toolRegistry: registry)

        do {
            _ = try await orchestrator.callTool(
                ToolCall(toolName: "search.index", input: [:], requestedPermissions: [.write]),
                context: ExecutionContext(actor: "ai")
            )
            XCTFail("Expected permission failure.")
        } catch let error as ToolRegistryError {
            XCTAssertEqual(error, .permissionDenied(toolName: "search.index", missing: [.write]))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDryRunToolCallPropagatesDryRunContext() async throws {
        let registry = DefaultToolRegistry()
        try await registry.register(aiToolDescriptor(name: "operation.plan", permissions: [.plan], dryRunSupported: true)) { call, context in
            ToolResult(
                toolName: call.toolName,
                output: ["dryRun": String(context.dryRun)],
                message: call.dryRun ? "dry-run" : "executed"
            )
        }
        let orchestrator = ToolBackedAIOrchestrator(toolRegistry: registry)

        let result = try await orchestrator.callTool(
            ToolCall(toolName: "operation.plan", input: [:], requestedPermissions: [.plan], dryRun: true),
            context: ExecutionContext(actor: "ai")
        )

        XCTAssertEqual(result.output["dryRun"], "true")
        XCTAssertEqual(result.message, "dry-run")
    }

    func testContextDryRunForcesEffectiveToolCallDryRun() async throws {
        let registry = DefaultToolRegistry()
        try await registry.register(aiToolDescriptor(name: "knowledge.add_collection", permissions: [.write], dryRunSupported: true)) { call, context in
            ToolResult(
                toolName: call.toolName,
                output: ["callDryRun": String(call.dryRun), "contextDryRun": String(context.dryRun)]
            )
        }
        let orchestrator = ToolBackedAIOrchestrator(toolRegistry: registry)

        let result = try await orchestrator.callTool(
            ToolCall(toolName: "knowledge.add_collection", input: [:], requestedPermissions: [.write]),
            context: ExecutionContext(dryRun: true, actor: "ai")
        )

        XCTAssertEqual(result.output["callDryRun"], "true")
        XCTAssertEqual(result.output["contextDryRun"], "true")
    }

    func testUnknownToolNameFailsSafely() async {
        let orchestrator = ToolBackedAIOrchestrator(toolRegistry: DefaultToolRegistry())

        do {
            _ = try await orchestrator.callTool(
                ToolCall(toolName: "missing", input: [:], requestedPermissions: [.read]),
                context: ExecutionContext(actor: "ai")
            )
            XCTFail("Expected unknown tool failure.")
        } catch let error as ToolRegistryError {
            XCTAssertEqual(error, .unknownTool("missing"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExecutedToolCallsAreLoggable() async throws {
        let registry = DefaultToolRegistry()
        let activityLog = MockActivityLog()
        try await registry.register(aiToolDescriptor(name: "activity.recent", permissions: [.read])) { call, _ in
            ToolResult(toolName: call.toolName, message: "listed")
        }
        let orchestrator = ToolBackedAIOrchestrator(toolRegistry: registry, activityLog: activityLog)

        _ = try await orchestrator.callTool(
            ToolCall(toolName: "activity.recent", input: [:], requestedPermissions: [.read]),
            context: ExecutionContext(actor: "ai")
        )

        XCTAssertEqual(activityLog.events.count, 1)
        XCTAssertEqual(activityLog.events.first?.kind, .toolCall)
        XCTAssertTrue(activityLog.events.first?.message.contains("activity.recent") ?? false)
        XCTAssertTrue(activityLog.events.first?.message.contains("listed") ?? false)
        XCTAssertEqual(activityLog.events.first?.metadata["toolName"], "activity.recent")
        XCTAssertEqual(activityLog.events.first?.metadata["actor"], "ai")
    }

    func testClassificationStillUsesNoModelGatewayByDefault() async throws {
        let orchestrator = ToolBackedAIOrchestrator(toolRegistry: DefaultToolRegistry())

        let classification = try await orchestrator.classify(AIRequest(itemProfile: ItemFixtures.fileProfile()))

        XCTAssertEqual(classification.confidence, 0)
        XCTAssertEqual(classification.reviewRequirement, .required)
    }
}

private func aiToolDescriptor(
    name: String,
    permissions: [ToolPermission],
    dryRunSupported: Bool = true,
    reversible: Bool = false
) -> ToolDescriptor {
    ToolDescriptor(
        name: name,
        description: "AI test tool",
        inputSchema: #"{"type":"object"}"#,
        outputSchema: #"{"type":"object"}"#,
        permissions: permissions,
        dryRunSupported: dryRunSupported,
        reversible: reversible
    )
}
