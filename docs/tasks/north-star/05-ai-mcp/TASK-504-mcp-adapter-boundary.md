# TASK-504: MCP Adapter Boundary

## Goal

Reserve MCP as an adapter over native tools, not the internal architecture.

## Scope

- Map native tool descriptors to MCP-style descriptors in a disabled-by-default adapter.
- Keep server/client transport unimplemented or behind explicit flags.
- Add tests proving native tools work when MCP is disabled.
- Document what future MCP server and MCP client responsibilities are.

## Non-Goals

- No running MCP server.
- No external tool execution.
- No provider-backed AI.

## Dependencies

- `TASK-501-native-tool-surface-refresh.md`

## Test Requirements

- Descriptor mapping tests.
- Disabled-by-default startup test.
- Tests that MCP adapter cannot bypass native tool permissions.

## Acceptance Criteria

- MCP is clearly a transport/interoperability boundary.
- Native Bipbox services remain the source of truth.
- Enabling MCP later does not require rewiring app internals.

