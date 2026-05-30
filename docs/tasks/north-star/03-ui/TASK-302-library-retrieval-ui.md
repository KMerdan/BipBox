# TASK-302: Library Retrieval UI

## Goal

Make Library the primary retrieval surface for everything Bipbox has captured.

## Scope

- Use `RetrievalService` or equivalent fixture-backed view model.
- Merge Search into Library modes.
- Add modes for Search, Recent, Sources, Collections, Contexts, Related, and Missing where data exists.
- Show match explanations and source context on result rows.
- Add actions for Open, Reveal, Related, Reindex, Locate, and Remove from Library where services exist.

## Non-Goals

- No AI chat UI.
- No advanced graph visualization.
- No rule editor.

## Dependencies

- `../02-memory-retrieval/TASK-202-retrieval-query-service.md`
- `../02-memory-retrieval/TASK-203-missing-file-recovery.md`

## Test Requirements

- View-model tests for query, filters, source mode, missing mode, and selection.
- Tests for match explanation display strings.
- UI smoke tests for empty, populated, missing, and failed states.

## Acceptance Criteria

- Library can find source-added items immediately after indexing.
- Search is no longer a separate top-level product concept.
- Result quality and status are explainable to the user.

