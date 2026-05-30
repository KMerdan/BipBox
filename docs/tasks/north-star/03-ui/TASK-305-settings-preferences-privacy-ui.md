# TASK-305: Settings Preferences And Privacy UI

## Goal

Keep Settings focused on preferences, storage, automation, privacy, diagnostics, and provider configuration.

## Scope

- Remove watched-source management from Settings if any remains.
- Keep Library storage location and global automation pause/resume.
- Add or refine privacy controls for future AI content sharing, defaulting off/private.
- Add diagnostic/log export entry point if service support exists.
- Show permission health summaries that link users back to Start or Library recovery flows.

## Non-Goals

- No source add/remove UI.
- No real AI provider implementation.
- No packaging/notarization settings.

## Dependencies

- `../05-ai-mcp/TASK-503-ai-privacy-settings-contract.md`

## Test Requirements

- View-model tests for settings load/save.
- Tests that AI privacy defaults are off/private.
- UI smoke test for permission health messages.

## Acceptance Criteria

- Settings no longer competes with Start for source management.
- AI/privacy controls are visible before any provider integration.
- Global app preferences persist across restart.

