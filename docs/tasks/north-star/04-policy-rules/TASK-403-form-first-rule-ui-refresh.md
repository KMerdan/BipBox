# TASK-403: Form-First Rule UI Refresh

## Goal

Keep rule editing user-friendly while preserving JSON as storage and AI/tooling surface.

## Scope

- Simplify top-level actions to New Rule, Delete, and Apply.
- Render rule fields as forms: name, enabled, conditions, outcome, review requirement.
- Hide raw JSON editor from normal flow while keeping Open/Reveal/AI tooling paths outside the primary UI if needed.
- Support memory outcomes such as collection/context/tag/review in addition to move/copy.

## Non-Goals

- No direct AI prompt UI.
- No nested tree visualizer unless existing code makes it cheap.
- No raw JSON editing as primary UX.

## Dependencies

- `TASK-401-memory-action-contracts.md`

## Test Requirements

- View-model tests for creating, editing, deleting, and applying rules.
- Tests that form edits sync to JSON-backed rule storage.
- Tests that invalid JSON/tool edits are rejected before activation.

## Acceptance Criteria

- User can create useful rules without seeing JSON.
- AI/tooling can still operate through JSON and apply/validate tools.
- Rule UI no longer competes with Library or Inbox responsibilities.

