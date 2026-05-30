# TASK-202: Retrieval Query Service

## Goal

Create a Library retrieval service that blends search index records with graph and source signals.

## Scope

- Define `RetrievalService` query/result models.
- Support empty recent view, text search, source filter, kind filter, status filter, date filter, and collection/context filters where available.
- Include match explanations: filename, path, source, tag, extracted text, relationship, recent capture.
- Use existing `SearchService`, knowledge store, and relatedness services behind the service.

## Non-Goals

- No UI implementation.
- No embeddings or remote AI.
- No full-text rewrite unless needed.

## Dependencies

- `TASK-201-knowledge-schema-source-fields.md`
- `../00-contracts/TASK-004-north-star-test-fixtures.md`

## Test Requirements

- Unit tests for filename/path/source ranking basics.
- Tests for empty query returning recent captures.
- Tests for match explanations.
- Tests for filters composing predictably.

## Acceptance Criteria

- Library UI can depend on one retrieval service instead of manually composing search and graph calls.
- Results explain why they matched.
- Physical file location is shown as current state, not the only organization signal.

