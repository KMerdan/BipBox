# TASK-110: Relationship And Collection Services

## Goal

Build platform-light services for adding, querying, explaining, and maintaining relationships and virtual collections.

## Scope

- Add `KnowledgeGraphService` or equivalent service protocols for relationship writes, collection membership, and related-item lookup.
- Implement service methods over the SQLite knowledge store.
- Support provenance and confidence on relationship writes.
- Add query helpers for contexts, collections, sources, and item-to-item relationships.
- Primary codegraph scope: `ServiceProtocols.swift`, `DefaultToolRegistry.swift`, `SQLiteSearchIndex.swift`, `BipboxAppServices.swift`.
- Change scope: core service plus tests; UI can use fixtures until this lands.

## Non-Goals

- Do not implement embeddings.
- Do not add AI tools yet.
- Do not change filesystem actions.

## Dependencies

- `TASK-108-knowledge-sqlite-store.md`

## Test Requirements

- Unit/integration tests for adding duplicate relationships idempotently.
- Tests for confidence and provenance preservation.
- Tests for manual, saved-search, rule-backed, agent-suggested, and system collection kinds.
- Tests for querying related items without returning the subject item as its own related result.

## Acceptance Criteria

- Core code can ask for related contexts and related items without raw SQL.
- Collections can overlap freely.
- Relationship and collection changes do not mutate physical files.

