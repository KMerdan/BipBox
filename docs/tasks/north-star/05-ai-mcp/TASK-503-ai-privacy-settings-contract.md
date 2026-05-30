# TASK-503: AI Privacy Settings Contract

## Goal

Define privacy and provider settings before any model-backed AI is enabled.

## Scope

- Add settings for AI enabled state, provider, local-only mode, content sharing permission, metadata-only mode, and audit logging.
- Default all content-sharing settings to off/private.
- Expose settings through `AppSettingsStore` or a dedicated privacy settings store.
- Provide display models for Settings UI.

## Non-Goals

- No provider SDK.
- No model selection UI beyond placeholder fields.
- No network calls.

## Dependencies

- None.

## Test Requirements

- Codable/settings persistence tests.
- Tests that defaults are private/off.
- Tests that disabling AI prevents model-backed execution paths once they exist.

## Acceptance Criteria

- Users can see and control future AI privacy posture before AI ships.
- No code path assumes content may be sent to a provider by default.

