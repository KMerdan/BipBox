# TASK-301: Start Source Management UI

## Goal

Replace onboarding-style Start behavior with a persistent source-management surface.

## Scope

- Rename or refactor `OnboardingWorkspaceViewModel` concepts toward source management.
- Render current sources from `SourceStore`.
- Add actions: Add Folder, Change, Remove, Rescan, Pause/Resume where service support exists.
- Show permission state, index state, watch state, last scan result, and inline errors.
- Keep path selection through native folder pickers.

## Non-Goals

- No Library search UI changes.
- No rule editing.
- No recursive source configuration beyond displaying policy.

## Dependencies

- `../01-source-capture/TASK-102-source-lifecycle-coordinator.md`

## Test Requirements

- View-model tests for load/add/change/remove/rescan flows using fixtures.
- UI smoke test that sources render without changing sidebar size.
- Tests for permission-needed and failed source states.

## Acceptance Criteria

- Start clearly answers "where does Bipbox remember from?"
- A watched source shown in Start is backed by durable storage.
- User does not see separate index-only and watched-folder concepts.

