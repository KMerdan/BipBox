import Foundation

public enum ToolRegistryError: Error, Equatable, LocalizedError {
    case duplicateTool(String)
    case unknownTool(String)
    case permissionDenied(toolName: String, missing: [ToolPermission])
    case dryRunUnsupported(String)

    public var errorDescription: String? {
        switch self {
        case .duplicateTool(let name):
            "Tool already registered: \(name)"
        case .unknownTool(let name):
            "Tool is not registered: \(name)"
        case .permissionDenied(let toolName, let missing):
            "Tool \(toolName) is missing required permissions: \(missing.map(\.rawValue).joined(separator: ", "))"
        case .dryRunUnsupported(let name):
            "Tool does not support dry-run execution: \(name)"
        }
    }
}

public typealias ToolHandler = @Sendable (ToolCall, ExecutionContext) async throws -> ToolResult

public final class DefaultToolRegistry: ToolRegistry, @unchecked Sendable {
    private struct RegisteredTool {
        var descriptor: ToolDescriptor
        var handler: ToolHandler
    }

    private var tools: [String: RegisteredTool] = [:]

    public init() {}

    public func register(_ descriptor: ToolDescriptor) async throws {
        try registerSync(descriptor) { call, _ in
            ToolResult(toolName: call.toolName, message: "Tool has no handler.")
        }
    }

    public func register(_ descriptor: ToolDescriptor, handler: @escaping ToolHandler) async throws {
        try registerSync(descriptor, handler: handler)
    }

    public func registerSync(_ descriptor: ToolDescriptor, handler: @escaping ToolHandler) throws {
        guard tools[descriptor.name] == nil else {
            throw ToolRegistryError.duplicateTool(descriptor.name)
        }

        tools[descriptor.name] = RegisteredTool(descriptor: descriptor, handler: handler)
    }

    public func descriptor(named name: String) async -> ToolDescriptor? {
        tools[name]?.descriptor
    }

    public func descriptors() async -> [ToolDescriptor] {
        tools.values.map(\.descriptor).sorted { $0.name < $1.name }
    }

    public func execute(_ call: ToolCall, context: ExecutionContext) async throws -> ToolResult {
        guard let tool = tools[call.toolName] else {
            throw ToolRegistryError.unknownTool(call.toolName)
        }

        if call.dryRun && !tool.descriptor.dryRunSupported {
            throw ToolRegistryError.dryRunUnsupported(call.toolName)
        }

        let descriptorPermissions = Set(tool.descriptor.permissions)
        let missingPermissions = call.requestedPermissions.filter { !descriptorPermissions.contains($0) }
        guard missingPermissions.isEmpty else {
            throw ToolRegistryError.permissionDenied(toolName: call.toolName, missing: missingPermissions)
        }

        return try await tool.handler(call, context)
    }
}
