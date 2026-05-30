import BipboxCore
import XCTest

final class MCPToolAdapterTests: XCTestCase {
    func testConvertsNativeToolDescriptorToMCPStyleMetadata() {
        let descriptor = ToolDescriptor(
            name: "knowledge.add_collection",
            description: "Create a collection.",
            inputSchema: #"{"name":"String"}"#,
            outputSchema: #"{"collectionID":"String"}"#,
            permissions: [.read, .write],
            dryRunSupported: true,
            reversible: true
        )

        let metadata = PlaceholderMCPToolMetadataAdapter.convert(descriptor)

        XCTAssertEqual(metadata.name, descriptor.name)
        XCTAssertEqual(metadata.inputSchema, descriptor.inputSchema)
        XCTAssertEqual(metadata.outputSchema, descriptor.outputSchema)
        XCTAssertEqual(metadata.annotations["bipbox.permissions"], "read,write")
        XCTAssertEqual(metadata.annotations["bipbox.dryRunSupported"], "true")
        XCTAssertEqual(metadata.annotations["bipbox.reversible"], "true")
        XCTAssertEqual(metadata.annotations["bipbox.transport"], "placeholder")
    }

    func testDisabledAdapterExposesNoToolMetadata() {
        let adapter = PlaceholderMCPToolMetadataAdapter(configuration: .disabled)
        let descriptor = ToolDescriptor(
            name: "knowledge.search",
            description: "Search.",
            inputSchema: "{}",
            outputSchema: "{}",
            permissions: [.read],
            dryRunSupported: true,
            reversible: false
        )

        XCTAssertFalse(adapter.isEnabled)
        XCTAssertEqual(adapter.metadata(for: [descriptor]), [])
    }

    func testEnabledAdapterPreservesWritePermissionMetadataAcrossBoundary() {
        let adapter = PlaceholderMCPToolMetadataAdapter(configuration: MCPAdapterConfiguration(enabled: true))
        let descriptor = ToolDescriptor(
            name: "knowledge.add_relationship",
            description: "Add relationship.",
            inputSchema: "{}",
            outputSchema: "{}",
            permissions: [.read, .write],
            dryRunSupported: true,
            reversible: true
        )

        let metadata = adapter.metadata(for: [descriptor])

        XCTAssertEqual(metadata.count, 1)
        XCTAssertEqual(metadata.first?.annotations["bipbox.permissions"], "read,write")
        XCTAssertEqual(metadata.first?.annotations["bipbox.nativeTool"], "true")
    }

    func testDisabledAdapterCannotExecuteTools() async throws {
        let adapter = PlaceholderMCPToolMetadataAdapter(configuration: .disabled)
        let registry = DefaultToolRegistry()
        try await registry.register(
            ToolDescriptor(
                name: "knowledge.search",
                description: "Search.",
                inputSchema: "{}",
                outputSchema: "{}",
                permissions: [.read],
                dryRunSupported: true,
                reversible: false
            )
        )

        do {
            _ = try await adapter.execute(
                ToolCall(toolName: "knowledge.search", input: [:], requestedPermissions: [.read]),
                registry: registry,
                context: ExecutionContext(actor: "mcp")
            )
            XCTFail("Expected disabled MCP adapter failure.")
        } catch let error as MCPToolAdapterError {
            XCTAssertEqual(error, .disabled)
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testEnabledAdapterCannotBypassNativePermissions() async throws {
        let adapter = PlaceholderMCPToolMetadataAdapter(configuration: MCPAdapterConfiguration(enabled: true))
        let registry = DefaultToolRegistry()
        try await registry.register(
            ToolDescriptor(
                name: "knowledge.search",
                description: "Search.",
                inputSchema: "{}",
                outputSchema: "{}",
                permissions: [.read],
                dryRunSupported: true,
                reversible: false
            )
        )

        do {
            _ = try await adapter.execute(
                ToolCall(toolName: "knowledge.search", input: [:], requestedPermissions: [.write]),
                registry: registry,
                context: ExecutionContext(actor: "mcp")
            )
            XCTFail("Expected native permission failure.")
        } catch let error as ToolRegistryError {
            XCTAssertEqual(error, .permissionDenied(toolName: "knowledge.search", missing: [.write]))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
}
