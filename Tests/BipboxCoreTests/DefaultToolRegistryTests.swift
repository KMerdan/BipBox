import BipboxCore
import XCTest

final class DefaultToolRegistryTests: XCTestCase {
    func testRegistersAndFindsToolDescriptor() async throws {
        let registry = DefaultToolRegistry()
        let descriptor = makeDescriptor(name: "inspect_item", permissions: [.read])

        try await registry.register(descriptor)
        let found = await registry.descriptor(named: "inspect_item")

        XCTAssertEqual(found, descriptor)
    }

    func testRejectsDuplicateToolName() async throws {
        let registry = DefaultToolRegistry()
        let descriptor = makeDescriptor(name: "inspect_item", permissions: [.read])

        try await registry.register(descriptor)

        do {
            try await registry.register(descriptor)
            XCTFail("Expected duplicate tool registration to fail.")
        } catch let error as ToolRegistryError {
            XCTAssertEqual(error, .duplicateTool("inspect_item"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testPermissionFailureIsExplicit() async throws {
        let registry = DefaultToolRegistry()
        let descriptor = makeDescriptor(name: "move_item", permissions: [.read])
        try await registry.register(descriptor)

        do {
            _ = try await registry.execute(
                ToolCall(
                    toolName: "move_item",
                    input: ["path": "/tmp/report.pdf"],
                    requestedPermissions: [.write]
                ),
                context: ExecutionContext(actor: "ai")
            )
            XCTFail("Expected permission failure.")
        } catch let error as ToolRegistryError {
            XCTAssertEqual(error, .permissionDenied(toolName: "move_item", missing: [.write]))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testDryRunUnsupportedFailureIsExplicit() async throws {
        let registry = DefaultToolRegistry()
        let descriptor = makeDescriptor(name: "open_item", permissions: [.read], dryRunSupported: false)
        try await registry.register(descriptor)

        do {
            _ = try await registry.execute(
                ToolCall(
                    toolName: "open_item",
                    input: ["path": "/tmp/report.pdf"],
                    requestedPermissions: [.read],
                    dryRun: true
                ),
                context: ExecutionContext(dryRun: true, actor: "test")
            )
            XCTFail("Expected dry-run unsupported failure.")
        } catch let error as ToolRegistryError {
            XCTAssertEqual(error, .dryRunUnsupported("open_item"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testUnknownToolFailureIsExplicit() async {
        let registry = DefaultToolRegistry()

        do {
            _ = try await registry.execute(
                ToolCall(toolName: "missing", input: [:], requestedPermissions: [.read]),
                context: ExecutionContext(actor: "test")
            )
            XCTFail("Expected unknown tool failure.")
        } catch let error as ToolRegistryError {
            XCTAssertEqual(error, .unknownTool("missing"))
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }

    func testExecutesRegisteredMockTool() async throws {
        let registry = DefaultToolRegistry()
        let descriptor = makeDescriptor(name: "search_index", permissions: [.read])
        try await registry.register(descriptor) { call, context in
            ToolResult(
                toolName: call.toolName,
                output: [
                    "query": call.input["query"] ?? "",
                    "actor": context.actor
                ],
                message: call.dryRun ? "dry-run" : "executed"
            )
        }

        let result = try await registry.execute(
            ToolCall(
                toolName: "search_index",
                input: ["query": "invoice"],
                requestedPermissions: [.read],
                dryRun: true
            ),
            context: ExecutionContext(dryRun: true, actor: "ai")
        )

        XCTAssertEqual(result.toolName, "search_index")
        XCTAssertEqual(result.output["query"], "invoice")
        XCTAssertEqual(result.output["actor"], "ai")
        XCTAssertEqual(result.message, "dry-run")
    }

    func testDescriptorExposesDryRunAndReversibilityMetadata() async throws {
        let registry = DefaultToolRegistry()
        let descriptor = makeDescriptor(
            name: "move_item",
            permissions: [.read, .write],
            dryRunSupported: true,
            reversible: true
        )

        try await registry.register(descriptor)
        let found = await registry.descriptor(named: "move_item")

        XCTAssertEqual(found?.dryRunSupported, true)
        XCTAssertEqual(found?.reversible, true)
        XCTAssertEqual(found?.permissions, [.read, .write])
    }
}

private func makeDescriptor(
    name: String,
    permissions: [ToolPermission],
    dryRunSupported: Bool = true,
    reversible: Bool = false
) -> ToolDescriptor {
    ToolDescriptor(
        name: name,
        description: "Test tool",
        inputSchema: #"{"type":"object"}"#,
        outputSchema: #"{"type":"object"}"#,
        permissions: permissions,
        dryRunSupported: dryRunSupported,
        reversible: reversible
    )
}

