# TASK-202: Folder Watcher

## Goal

Watch configured intake folders and create organization requests for newly arrived top-level items.

## Scope

- Use a macOS folder watching mechanism such as FSEvents.
- Watch user-selected folders.
- Detect newly created or moved-in top-level items.
- Debounce or stabilize events before creating requests.
- Emit one request per top-level item.

## Non-Goals

- No recursive organization of dropped folders.
- No workflow decisions.
- No UI settings screen.

## Dependencies

- `TASK-003-service-protocols.md`
- `TASK-101-item-inspector.md`

## Test Requirements

- Adapter tests with fake watcher if native FSEvents is hard to test.
- Integration test creating a new top-level file.
- Integration test creating a new top-level folder.
- Test that nested child changes inside a folder do not create child organization requests by default.

## Acceptance Criteria

- Watcher emits `OrganizationRequest` values.
- Folder arrivals are emitted as one folder item.
- Event bursts are coalesced enough to avoid duplicate requests.
- Watcher can be paused and resumed.

