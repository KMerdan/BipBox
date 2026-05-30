# TASK-302: Library Search UI

## Goal

Build the Library search interface for finding files and folders indexed by Bipbox.

## Scope

- Search field.
- Results list.
- Filters for kind, type, tag, status, and date.
- Result detail pane.
- Actions: open, reveal in Finder, copy path if added later.
- Fixture-backed UI before real search integration.

## Non-Goals

- No search index implementation.
- No Spotlight integration.
- No content preview renderer beyond basic metadata.

## Dependencies

- `TASK-003-service-protocols.md`
- `TASK-106-search-index.md` for real integration, but mocks are enough to begin.

## Test Requirements

- View model tests for query and filters.
- Test that folders can appear in results.
- Test empty result state.
- Test error state from search service.

## Acceptance Criteria

- Library search UI can work against a mock `SearchService`.
- Results clearly show item kind and current path.
- Folder results are not visually treated as failed file records.
- Open/reveal actions call tool or service protocols.
