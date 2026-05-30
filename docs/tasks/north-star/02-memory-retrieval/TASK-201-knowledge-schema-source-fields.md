# TASK-201: Knowledge Schema Source Fields

## Goal

Persist source-aware knowledge fields required by the north-star retrieval model.

## Scope

- Update SQLite knowledge schema for source ID, original URL, current URL, first/last seen timestamps, and item state if missing.
- Add migration/version handling.
- Update `SQLiteKnowledgeStore` mapping and tests.
- Keep existing capture event and relationship APIs compatible.

## Non-Goals

- No Library UI changes.
- No ranking algorithm changes.
- No vector embeddings.

## Dependencies

- `../00-contracts/TASK-003-memory-capture-contracts.md`

## Test Requirements

- Schema version smoke test.
- Persist/reopen tests for source-aware knowledge items.
- Migration test from previous schema where feasible.
- Tests for missing/permission-needed states.

## Acceptance Criteria

- Knowledge items can be retrieved with source and path history intact.
- Existing knowledge-store tests continue to pass.
- Missing-file state is durable, not view-only.

