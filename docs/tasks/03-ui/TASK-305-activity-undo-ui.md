# TASK-305: Activity and Undo UI

## Goal

Show recent organization activity and expose undo for reversible operations.

## Scope

- Recent activity list.
- Activity detail view.
- Operation result status.
- Undo action for reversible operations.
- Error and partial failure display.

## Non-Goals

- No activity log storage.
- No irreversible undo guarantees.
- No timeline analytics.

## Dependencies

- `TASK-003-service-protocols.md`
- `TASK-105-activity-log.md`
- `TASK-201-filesystem-executor.md` for real undo execution later.

## Test Requirements

- View model tests for event rendering.
- Test reversible vs irreversible events.
- Test undo action dispatch.
- Test activity for folder move.

## Acceptance Criteria

- User can see what Bipbox moved, copied, renamed, tagged, indexed, or reviewed.
- Folder operations are displayed as folder operations.
- Undo is shown only when available.
- Failed operations remain visible and explainable.

