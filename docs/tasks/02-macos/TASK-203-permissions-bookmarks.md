# TASK-203: Permissions and Bookmarks

## Goal

Persist user-granted access to watched folders and the Bipbox library using security-scoped bookmarks where needed.

## Scope

- Store selected watched folders.
- Store selected library root.
- Resolve saved permissions on launch.
- Report missing or stale permissions.
- Support removing a permission.

## Non-Goals

- No complete settings UI.
- No folder watching implementation.
- No App Store submission work.

## Dependencies

- `TASK-003-service-protocols.md`

## Test Requirements

- Unit tests for permission records.
- Tests for stale or missing permission states using mocked bookmark resolver.
- Persistence test for adding and removing folder permissions.

## Acceptance Criteria

- App does not assume access to arbitrary user folders.
- Permission state can be queried by UI and services.
- Watched folder and library root permissions are represented separately.
- Failure to resolve permission gives actionable error data.

