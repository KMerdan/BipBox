import BipboxCore
import Foundation

public final class NoModelAgentOrchestrator: AgentOrchestrator, @unchecked Sendable {
    private let toolRegistry: ToolRegistry

    public init(toolRegistry: ToolRegistry) {
        self.toolRegistry = toolRegistry
    }

    public func respond(to request: AgentRequest, context: ExecutionContext) async throws -> AgentResponse {
        let availableTools = await toolRegistry.descriptors()
        let steps = try await request.proposedToolCalls.asyncMap { call in
            guard let descriptor = await toolRegistry.descriptor(named: call.toolName) else {
                throw ToolRegistryError.unknownTool(call.toolName)
            }
            let requiresApproval = descriptor.permissions.contains { $0 == .write || $0 == .ruleWrite || $0 == .external }
            let status: AgentPlanStepStatus = requiresApproval ? .requiresApproval : .proposed
            return AgentPlanStep(
                toolCall: call,
                status: status,
                requiresApproval: requiresApproval,
                message: requiresApproval ? "Write-capable tool requires explicit approval." : "Read or planning tool is available."
            )
        }
        let plan = AgentPlan(intent: request.intent, steps: steps)

        switch request.mode {
        case .explain, .propose:
            return AgentResponse(
                mode: request.mode,
                explanation: "No model is configured. Bipbox can expose available native tools and build a non-mutating plan.",
                availableTools: availableTools,
                proposedPlan: plan,
                requiredApprovals: steps.filter(\.requiresApproval).map(\.toolCall)
            )
        case .simulate:
            return AgentResponse(
                mode: .simulate,
                explanation: "No model is configured. Simulation is represented as a dry-run plan; no tools were executed.",
                availableTools: availableTools,
                proposedPlan: AgentPlan(
                    intent: request.intent,
                    steps: steps.map { step in
                        AgentPlanStep(
                            toolCall: ToolCall(
                                id: step.toolCall.id,
                                toolName: step.toolCall.toolName,
                                input: step.toolCall.input,
                                requestedPermissions: step.toolCall.requestedPermissions,
                                dryRun: true
                            ),
                            status: .simulated,
                            requiresApproval: step.requiresApproval,
                            message: "Dry-run only; no mutation was performed."
                        )
                    }
                ),
                dryRunResults: steps.map {
                    ToolResult(toolName: $0.toolCall.toolName, output: ["dryRun": "true"], message: "Planned dry-run only.")
                },
                requiredApprovals: steps.filter(\.requiresApproval).map(\.toolCall)
            )
        case .requestApproval:
            return AgentResponse(
                mode: .requestApproval,
                explanation: "Approval is required before any write-capable native tool can run.",
                availableTools: availableTools,
                proposedPlan: plan,
                requiredApprovals: steps.filter(\.requiresApproval).map(\.toolCall),
                executionSummary: "No tools executed."
            )
        }
    }
}

private extension Array {
    func asyncMap<T>(_ transform: (Element) async throws -> T) async throws -> [T] {
        var results: [T] = []
        results.reserveCapacity(count)
        for element in self {
            let value = try await transform(element)
            results.append(value)
        }
        return results
    }
}
