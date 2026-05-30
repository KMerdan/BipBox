# TASK-304: Activity Memory Audit UI

## Goal

Expand Activity from filesystem operation history into the audit ledger for capture, index, relationship, rule, decision, and future AI/tool events.

## Scope

- Add display models for capture, index, relationship, rule match, review decision, filesystem operation, error, and tool-call events.
- Preserve undo controls for reversible filesystem operations.
- Add filters by event kind and source/item where services exist.
- Show enough context to explain why a file was indexed, moved, related, or staged.

## Non-Goals

- No crash reporter.
- No external log export unless already available.
- No timeline visualization beyond the current list/detail pattern.

## Dependencies

- `../02-memory-retrieval/TASK-201-knowledge-schema-source-fields.md`

## Test Requirements

- View-model tests for each event kind.
- Tests that reversible and irreversible operations render correct actions.
- Tests that capture and relationship events do not show undo when no undo exists.

## Acceptance Criteria

- Every mutation from the north-star runtime flow can be represented in Activity.
- Filesystem undo behavior remains intact.
- Activity helps debug source and retrieval problems without database inspection.

