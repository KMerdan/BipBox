# Bipbox MCP Boundary

MCP is an adapter over Bipbox native tools. It is not the app's internal architecture and must not mutate files, rules, or the memory graph directly.

## Native Source Of Truth

- `ToolRegistry` owns all callable tool descriptors and execution handlers.
- Native tools call Bipbox services such as `SourceLifecycleCoordinating`, `RetrievalService`, `KnowledgeGraphService`, `JSONRuleDocumentStore`, and the operation planner.
- Every future model-backed agent must plan through native `ToolCall` values and receive `ToolResult` values.
- Write-capable tools keep dry-run support, permission metadata, reversibility metadata, and activity logging at the native layer.

## MCP Server Responsibilities

- Convert native `ToolDescriptor` values into MCP tool metadata.
- Forward tool calls into `ToolRegistry.execute`.
- Preserve requested permissions, dry-run flags, and actor identity.
- Refuse execution when MCP is disabled.
- Never open files, write JSON rules, mutate SQLite, or run filesystem operations outside native tools.

## MCP Client Responsibilities

- Treat MCP metadata as a transport description, not a permission grant.
- Request explicit user approval before write, rule-write, or external tools.
- Prefer dry-run calls before approved execution.
- Surface native `ToolResult` output and native errors without rewriting safety meaning.

## Current Product State

`PlaceholderMCPToolMetadataAdapter` is disabled by default. When enabled in tests, it can expose descriptor metadata and delegate execution to `ToolRegistry`, which means native permission checks still apply. No MCP server transport, external process bridge, or provider-backed autonomous loop is implemented.
