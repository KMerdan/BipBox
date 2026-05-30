# TASK-104: Tool Registry

## Goal

Implement the registry that exposes app capabilities as explicit tools for workflows, UI automation, and future AI operation.

## Scope

- Register tools by name.
- Describe input and output schemas.
- Declare permissions.
- Declare dry-run support.
- Declare reversibility.
- Execute tools through a controlled context.
- Provide mock and fixture tools for tests.

## Non-Goals

- No model-backed AI.
- No arbitrary scripting.
- No network tools.

## Dependencies

- `TASK-002-domain-models.md`
- `TASK-003-service-protocols.md`

## Test Requirements

- Unit test for registering and finding a tool.
- Unit test for duplicate tool name rejection.
- Unit test for permission failure.
- Unit test for dry-run behavior metadata.
- Unit test for mock tool execution.

## Acceptance Criteria

- Tools are the only interface the future AI layer uses for app actions.
- Dangerous tools require explicit permission classes.
- Tool execution has structured inputs, outputs, and errors.
- Registry can be used by workflows without importing AI code.

