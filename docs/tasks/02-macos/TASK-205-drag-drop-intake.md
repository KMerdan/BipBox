# TASK-205: Drag and Drop Intake

## Goal

Allow users to drop files or folders onto Bipbox and convert each top-level dropped item into an organization request.

## Scope

- Support drag/drop in the workspace.
- Support drag/drop in the menu-bar popover or capture surface where practical.
- Accept file URLs.
- Create one request per top-level dropped item.
- Treat folders as items.

## Non-Goals

- No recursive folder organization.
- No rule editor.
- No operation execution UI beyond basic feedback.

## Dependencies

- `TASK-003-service-protocols.md`
- `TASK-101-item-inspector.md`

## Test Requirements

- Unit tests for drop handler with file URL fixtures.
- Unit tests for drop handler with folder URL fixtures.
- UI or integration smoke test for workspace drop target.
- Test that folder drops create one request for the folder.

## Acceptance Criteria

- Dropping a folder does not enqueue its children.
- Drop failures return visible, structured errors.
- Drop handler works with mocked intake service.
- Intake result can be surfaced to activity or review UI later.

