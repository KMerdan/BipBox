# TASK-203: Missing File Recovery

## Goal

Make missing files and permission-blocked files explicit, searchable, and recoverable.

## Scope

- Add path existence and permission checks for retrieval results.
- Mark missing or permission-needed states in knowledge and search records.
- Add service operations for locate, remove from Library, and reindex.
- Ensure reindex updates existing records instead of duplicating them.

## Non-Goals

- No UI implementation.
- No Finder extension.
- No automatic filesystem search outside user-selected paths.

## Dependencies

- `TASK-201-knowledge-schema-source-fields.md`
- `TASK-202-retrieval-query-service.md`

## Test Requirements

- Tests for missing path detection.
- Tests for locate updating current URL and state.
- Tests for remove from Library not deleting the real file.
- Tests for reindex preserving item identity.

## Acceptance Criteria

- Missing items are marked missing, not silently hidden.
- Recovery operations are safe and reversible where applicable.
- Library can surface missing/permission-needed items as a first-class view.

