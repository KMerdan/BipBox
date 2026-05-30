# TASK-405: MCP Knowledge Adapter Placeholder

## Goal

Reserve the adapter boundary for a future built-in MCP server/client without making MCP the internal architecture of Bipbox.

## Scope

- Add placeholder protocols or adapter stubs mapping native tool descriptors to MCP-style tool metadata.
- Document the transport boundary and lifecycle expectations.
- Keep native `ToolRegistry` as the source of truth.
- Primary codegraph scope: `DefaultToolRegistry.swift`, `ToolBackedAIOrchestrator.swift`, `BipboxAppServices.swift`, future knowledge tool contracts.
- Change scope: placeholder boundary and tests only.

## Non-Goals

- Do not implement a network server.
- Do not add external dependencies.
- Do not expose local files to external clients.
- Do not make internal AI calls route through MCP.

## Dependencies

- `TASK-404-knowledge-tool-contracts.md`

## Test Requirements

- Unit tests for converting native tool descriptors into placeholder MCP metadata.
- Tests proving disabled MCP adapters do not affect app startup.
- Tests that write-capable tools preserve permission metadata across the adapter boundary.

## Acceptance Criteria

- Future MCP work has a clear adapter seam.
- Native tools remain usable without MCP.
- No user data is exposed by default.

