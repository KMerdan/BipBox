# TASK-204: Menu-Bar Status Item

## Goal

Create the macOS menu-bar presence for Bipbox.

## Scope

- Add `NSStatusItem` or equivalent menu-bar integration.
- Show app status: running, paused, needs review, error.
- Expose commands: open workspace, pause/resume, recent activity, quick search placeholder, quit.
- Keep menu-bar code behind a small adapter boundary.

## Non-Goals

- No full search UI.
- No real drag/drop behavior unless covered by `TASK-205`.
- No AI.

## Dependencies

- `TASK-001-project-scaffold.md`
- `TASK-003-service-protocols.md`

## Test Requirements

- Unit tests for status view model state transitions.
- Manual verification checklist for menu-bar item visibility and commands.
- Smoke test that the app can launch with status item enabled.

## Acceptance Criteria

- Menu-bar item appears when app launches.
- Pause/resume command calls the organizer control protocol or mock.
- Open workspace command opens or focuses workspace.
- Status state is driven by app state, not hard-coded UI strings.

