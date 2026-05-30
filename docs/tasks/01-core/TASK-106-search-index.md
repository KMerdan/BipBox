# TASK-106: Search Index

## Goal

Implement Bipbox-owned local search over organized files and folders.

## Scope

- Add SQLite schema.
- Add FTS5 table or equivalent text index.
- Index item records.
- Update indexed records after move, rename, tag, or review status change.
- Search by text.
- Filter by kind, type, tag, date, and status.

## Non-Goals

- No Core Spotlight export.
- No OCR.
- No AI summaries unless placeholder fields are needed.

## Dependencies

- `TASK-002-domain-models.md`
- `TASK-003-service-protocols.md`
- `TASK-004-test-harness.md`

## Test Requirements

- Integration test for indexing a file.
- Integration test for indexing a folder.
- Search test by filename.
- Filter test by item kind.
- Update test after path change.
- Migration smoke test or schema version test.

## Acceptance Criteria

- Search works without relying on Finder or Spotlight.
- Indexed folders appear as searchable items.
- Query results include current path and original path when available.
- Database lives under the configured Bipbox app data or library area in implementation.

