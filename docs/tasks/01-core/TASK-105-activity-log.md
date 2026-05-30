# TASK-105: Activity Log

## Goal

Record organization decisions, operation plans, executed operations, errors, and undo metadata in an append-oriented activity log.

## Scope

- Define activity event schema.
- Persist activity events.
- Query recent activity.
- Query activity by item.
- Store undo metadata for reversible operations.

## Non-Goals

- No UI.
- No actual undo execution.
- No search index content extraction.

## Dependencies

- `TASK-002-domain-models.md`
- `TASK-003-service-protocols.md`

## Test Requirements

- Unit or integration test for appending events.
- Test querying recent events.
- Test querying events for one item.
- Test preserving undo metadata.

## Acceptance Criteria

- Every executed operation can be traced to a decision and request.
- Log records are durable across app restart.
- Activity writes are safe to call from organizer pipeline code.
- Log schema can represent file and folder operations.

