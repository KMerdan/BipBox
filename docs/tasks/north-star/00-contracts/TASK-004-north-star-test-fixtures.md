# TASK-004: North-Star Test Fixtures

## Goal

Create reusable fixtures for source, capture, memory, and retrieval tests so later tasks can be implemented in parallel.

## Scope

- Add fixture builders for `SourceRecord`, source scan summaries, source-aware knowledge items, capture events, and Library search results.
- Add temp-directory helpers for watched-source folders with files, folders, packages, and missing paths.
- Add mock protocols for `SourceStore`, source coordinator, source scanner, and retrieval services as contracts appear.

## Non-Goals

- No production code behavior changes.
- No real filesystem watcher implementation.
- No UI snapshots.

## Dependencies

- `TASK-001-source-models.md`
- `TASK-002-source-store-contract.md`
- `TASK-003-memory-capture-contracts.md`

## Test Requirements

- Fixture smoke tests verifying generated records are valid.
- Test helper proving folder fixtures are not recursively expanded by default.
- Tests that fixture stores behave deterministically.

## Acceptance Criteria

- Later UI and service tests can use fixtures without touching real user folders.
- Fixture names and defaults reflect the north-star language: source, Library, Inbox decision, memory, retrieval.

