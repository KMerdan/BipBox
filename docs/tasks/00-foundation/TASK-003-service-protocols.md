# TASK-003: Service Protocols

## Goal

Define protocols that let UI, core services, macOS adapters, persistence, and future AI interact without tight coupling.

## Scope

Add protocols for:

- `IntakeService`
- `ItemInspector`
- `WorkflowEngine`
- `OperationPlanner`
- `OperationExecutor`
- `ToolRegistry`
- `SearchService`
- `ActivityLog`
- `PermissionStore`
- `AIOrchestrator`

## Non-Goals

- No real implementations.
- No concrete storage choices beyond protocol needs.
- No UI.

## Dependencies

- `TASK-002-domain-models.md`

## Test Requirements

- Compile-time test fixtures or mocks for each protocol.
- Unit test proving a mock organization pipeline can be composed from protocols.

## Acceptance Criteria

- UI code can depend on protocols and fixture data.
- Core services do not import concrete UI modules.
- The AI boundary can access app capabilities only through registered tools or service protocols.
- Protocols include async/error behavior where filesystem, AI, or persistence work can fail.

