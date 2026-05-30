# TASK-108: Knowledge SQLite Store

## Goal

Add the durable SQLite store for memory graph records, starting with knowledge items, capture events, metadata snapshots, relationships, and collections.

## Scope

- Add a new persistence actor, likely `SQLiteKnowledgeStore`, under `Sources/BipboxPersistence`.
- Implement schema migrations for `file_records`, `capture_events`, `context_nodes`, `relationship_edges`, `collections`, `collection_memberships`, and `metadata_snapshots`.
- Provide repository protocols if they were not already added with the core models.
- Keep the schema in the same local-first style as `SQLiteSearchIndex`.
- Primary codegraph scope: `SQLiteSearchIndex.swift`, `BipboxRuntimePaths.swift`, `BipboxAppServices.swift`, `DomainModels.swift`, `ServiceProtocols.swift`.
- Change scope: persistence and dependency wiring only; no UI.

## Non-Goals

- Do not replace `SQLiteSearchIndex`.
- Do not implement vector search.
- Do not implement cold-start scanning.
- Do not expose graph traversal UI.

## Dependencies

- `TASK-005-memory-graph-domain-models.md`

## Test Requirements

- SQLite migration tests for a new database and reopened database.
- CRUD tests for every table.
- Tests for one item belonging to multiple contexts and collections.
- Tests that capture events preserve grouped session IDs.
- Tests for deleting collection membership without deleting the underlying item.

## Acceptance Criteria

- The knowledge store is durable across app restarts.
- Schema versioning is explicit and test-covered.
- Store APIs are actor-safe and usable from the pipeline.
- Existing search and activity tests continue to pass.

