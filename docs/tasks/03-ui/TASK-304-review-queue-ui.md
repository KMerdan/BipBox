# TASK-304: Review Queue UI

## Goal

Build the review surface for items that require confirmation or could not be confidently routed.

## Scope

- List needs-review items.
- Show item profile and proposed plan.
- Approve plan.
- Change destination or action.
- Reject or leave in inbox.
- Mark item as handled.

## Non-Goals

- No advanced bulk review unless trivial.
- No AI chat interface.
- No rule creation from review unless later task adds it.

## Dependencies

- `TASK-003-service-protocols.md`
- `TASK-103-operation-planner.md`
- `TASK-105-activity-log.md`

## Test Requirements

- View model tests for approve/reject flows.
- Test folder item review.
- Test operation error surfaced to UI.
- Test empty review queue state.

## Acceptance Criteria

- Review UI works with mocked review data.
- Approving a review calls operation execution through protocol or tool.
- Folder reviews preserve folder-as-item semantics.
- User can understand why the item needs review.

