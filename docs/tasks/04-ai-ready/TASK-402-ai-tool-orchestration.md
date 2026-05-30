# TASK-402: AI Tool Orchestration

## Goal

Create the controlled mechanism by which future AI can call registered Bipbox tools.

## Scope

- Define AI tool-call request format.
- Validate tool existence.
- Validate permissions.
- Support dry-run tool calls.
- Return structured tool-call results.
- Log AI-requested tool calls when executed.

## Non-Goals

- No model loop.
- No autonomous execution policy beyond validation.
- No network calls.

## Dependencies

- `TASK-104-tool-registry.md`
- `TASK-105-activity-log.md`
- `TASK-401-ai-gateway-placeholder.md`

## Test Requirements

- Unit test for allowed read tool call.
- Unit test for denied write tool call.
- Unit test for dry-run tool call.
- Unit test that unknown tool names fail safely.
- Unit test that executed tool calls are loggable.

## Acceptance Criteria

- AI can only operate through registered tools.
- Permission failures are explicit and user-visible.
- Tool calls are structured, auditable, and testable.
- No direct filesystem or database mutation exists in AI orchestration.

