# TASK-301: Workspace Shell

## Goal

Create the main workspace window with navigation, app state wiring, and placeholder destinations for primary sections.

## Scope

- Sidebar/navigation.
- Sections: Inbox, Library, Rules, Activity, Settings.
- App-level state container.
- Empty and loading states.

## Non-Goals

- No complete section implementations.
- No real file organization.

## Dependencies

- `TASK-001-project-scaffold.md`
- `TASK-003-service-protocols.md`

## Test Requirements

- UI state tests for selected section.
- Preview or fixture-backed rendering for each section.
- Manual smoke test for window launch and navigation.

## Acceptance Criteria

- Workspace opens from app launch and menu-bar command.
- Navigation is stable and does not depend on real filesystem state.
- Each section has a clear placeholder that can be replaced independently.
