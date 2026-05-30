import BipboxCore
import Foundation

public final class ToolBackedAIOrchestrator: AIOrchestrator, @unchecked Sendable {
    private let classifier: AIOrchestrator
    private let toolRegistry: ToolRegistry
    private let activityLog: ActivityLog?

    public init(
        classifier: AIOrchestrator = NoModelAIGateway(),
        toolRegistry: ToolRegistry,
        activityLog: ActivityLog? = nil
    ) {
        self.classifier = classifier
        self.toolRegistry = toolRegistry
        self.activityLog = activityLog
    }

    public func classify(_ request: AIRequest) async throws -> AIClassification {
        try await classifier.classify(request)
    }

    public func callTool(_ call: ToolCall, context: ExecutionContext) async throws -> ToolResult {
        guard await toolRegistry.descriptor(named: call.toolName) != nil else {
            throw ToolRegistryError.unknownTool(call.toolName)
        }

        let toolContext = ExecutionContext(dryRun: call.dryRun || context.dryRun, actor: context.actor)
        let effectiveCall = ToolCall(
            id: call.id,
            toolName: call.toolName,
            input: call.input,
            requestedPermissions: call.requestedPermissions,
            dryRun: toolContext.dryRun
        )
        let result = try await toolRegistry.execute(effectiveCall, context: toolContext)
        try await logExecutedToolCall(effectiveCall, context: toolContext, result: result)
        return result
    }

    private func logExecutedToolCall(
        _ call: ToolCall,
        context: ExecutionContext,
        result: ToolResult
    ) async throws {
        guard let activityLog else {
            return
        }

        try await activityLog.append(
            ActivityEvent(
                kind: .toolCall,
                message: "AI requested tool \(call.toolName) as \(context.actor). Result: \(result.message ?? "completed").",
                occurredAt: Date(),
                metadata: [
                    "toolName": call.toolName,
                    "actor": context.actor,
                    "dryRun": String(context.dryRun)
                ]
            )
        )
    }
}
