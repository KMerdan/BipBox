# TASK-103: Operation Planner

## Goal

Convert route decisions into safe operation plans before any filesystem mutation occurs.

## Scope

- Plan move, copy, rename, tag, review, and index operations.
- Detect destination conflicts.
- Mark reversible and irreversible steps.
- Generate user-readable preview text.
- Support dry-run planning.

## Non-Goals

- No direct execution.
- No UI confirmation flow.
- No AI.

## Dependencies

- `TASK-002-domain-models.md`
- `TASK-003-service-protocols.md`
- `TASK-102-workflow-engine.md`

## Test Requirements

- Unit test for move plan.
- Unit test for folder move plan.
- Unit test for destination conflict.
- Unit test for reversible operation metadata.
- Unit test that unsafe or ambiguous decisions require review.

## Acceptance Criteria

- No operation executes during planning.
- Plans are serializable or loggable.
- Conflict handling is explicit.
- Folder plans move the folder object, not its children.

