# TASK-101: JSON Source Store

## Goal

Persist source records outside view-model memory using a local JSON store.

## Scope

- Implement `JSONSourceStore` in `BipboxPersistence`.
- Store records in a stable file such as `sources.json` under runtime settings or database storage.
- Use atomic writes and sorted, pretty JSON for inspectability.
- Preserve IDs and timestamps on update.
- Add store construction to `BipboxAppServices`.

## Non-Goals

- No SQLite migration yet.
- No UI changes.
- No bookmark storage; keep bookmark data in `PermissionStore`.

## Dependencies

- `../00-contracts/TASK-002-source-store-contract.md`

## Test Requirements

- Save, update, remove, reload, and list tests.
- Tests for empty and missing store file.
- Tests for duplicate path handling if enforced at store layer.
- Corrupt JSON error test.

## Acceptance Criteria

- Source records survive app restart.
- Store failures are surfaced as explicit errors.
- No source state required by Start lives only in memory.

