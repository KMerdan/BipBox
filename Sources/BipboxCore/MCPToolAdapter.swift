import Foundation

public struct MCPToolMetadata: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public var name: String
    public var description: String
    public var inputSchema: String
    public var outputSchema: String
    public var annotations: [String: String]

    public init(
        name: String,
        description: String,
        inputSchema: String,
        outputSchema: String,
        annotations: [String: String] = [:]
    ) {
        self.name = name
        self.description = description
        self.inputSchema = inputSchema
        self.outputSchema = outputSchema
        self.annotations = annotations
    }
}

public struct MCPAdapterConfiguration: Codable, Equatable, Sendable {
    public var enabled: Bool

    public init(enabled: Bool = false) {
        self.enabled = enabled
    }

    public static let disabled = MCPAdapterConfiguration(enabled: false)
}

public enum MCPToolAdapterError: Error, Equatable, LocalizedError, Sendable {
    case disabled

    public var errorDescription: String? {
        switch self {
        case .disabled:
            "MCP tool transport is disabled."
        }
    }
}

public protocol MCPToolMetadataAdapter: Sendable {
    var isEnabled: Bool { get }
    func metadata(for descriptors: [ToolDescriptor]) -> [MCPToolMetadata]
}

public struct PlaceholderMCPToolMetadataAdapter: MCPToolMetadataAdapter {
    public var configuration: MCPAdapterConfiguration

    public init(configuration: MCPAdapterConfiguration = .disabled) {
        self.configuration = configuration
    }

    public var isEnabled: Bool {
        configuration.enabled
    }

    public func metadata(for descriptors: [ToolDescriptor]) -> [MCPToolMetadata] {
        guard isEnabled else {
            return []
        }

        return descriptors.map(Self.convert)
    }

    public static func convert(_ descriptor: ToolDescriptor) -> MCPToolMetadata {
        MCPToolMetadata(
            name: descriptor.name,
            description: descriptor.description,
            inputSchema: descriptor.inputSchema,
            outputSchema: descriptor.outputSchema,
            annotations: [
                "bipbox.nativeTool": "true",
                "bipbox.permissions": descriptor.permissions.map(\.rawValue).joined(separator: ","),
                "bipbox.dryRunSupported": String(descriptor.dryRunSupported),
                "bipbox.reversible": String(descriptor.reversible),
                "bipbox.transport": "placeholder"
            ]
        )
    }

    public func execute(
        _ call: ToolCall,
        registry: ToolRegistry,
        context: ExecutionContext
    ) async throws -> ToolResult {
        guard isEnabled else {
            throw MCPToolAdapterError.disabled
        }
        return try await registry.execute(call, context: context)
    }
}
