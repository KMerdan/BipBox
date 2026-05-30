# TASK-306: Settings UI

## Goal

Build settings for library root, watched folders, startup behavior, privacy, and automation controls.

## Scope

- Select Bipbox library root.
- Add and remove watched folders.
- Show permission health.
- Pause/resume automation.
- Startup/login item setting placeholder.
- AI privacy placeholder controls.

## Non-Goals

- No complete login-item implementation if deferred.
- No AI provider setup.
- No visual rule editor.

## Dependencies

- `TASK-003-service-protocols.md`
- `TASK-203-permissions-bookmarks.md`

## Test Requirements

- View model tests for adding/removing folders.
- Test permission error display.
- Test pause/resume control.
- Test AI privacy placeholder defaults to off.

## Acceptance Criteria

- User can configure library root and watched folders through service protocols.
- Permission status is visible.
- Automation can be paused from settings.
- AI content sharing controls exist as placeholders and default to private/off.

