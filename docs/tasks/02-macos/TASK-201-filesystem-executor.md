# TASK-201: Filesystem Executor

## Goal

Implement macOS filesystem operations for moving, copying, renaming, tagging, revealing, and opening items.

## Scope

- Execute operation plans.
- Move file or folder items.
- Copy file or folder items.
- Rename file or folder items.
- Add and remove Finder tags if feasible.
- Reveal item in Finder.
- Open item with default app.
- Return structured execution results.

## Non-Goals

- No workflow evaluation.
- No UI.
- No watched folder intake.

## Dependencies

- `TASK-003-service-protocols.md`
- `TASK-103-operation-planner.md`
- `TASK-004-test-harness.md`

## Test Requirements

- Integration test moving a file in a temp directory.
- Integration test moving a folder as one object.
- Test that folder children are preserved but not individually processed.
- Conflict failure test.
- Dry-run or plan-only test if exposed at this layer.

## Acceptance Criteria

- Executor mutates only paths included in the operation plan.
- Folder operations apply to the folder object.
- Execution returns enough data for activity logging and undo.
- Errors are structured and do not crash the app.

