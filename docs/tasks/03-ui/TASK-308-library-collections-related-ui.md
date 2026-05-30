# TASK-308: Library Collections And Related UI

## Goal

Evolve Library into the primary retrieval surface with collections, sources, related files, missing/permission-needed states, and match explanations.

## Scope

- Add Library sections or modes for Search, Recent, Collections, Projects, Sources, Missing/Needs Permission, and Related Files.
- Show "why this matched" explanations from search and relatedness services.
- Support fixture-backed UI before real relatedness integration lands.
- Add reveal/open/reconnect affordances for missing or permission-needed items.
- Primary codegraph scope: `LibraryWorkspaceView.swift`, `SearchWorkspaceViewModel.swift`, `SQLiteSearchIndex.swift`, relatedness service from `TASK-111`.
- Change scope: Library UI/view model; no new persistence schema.

## Non-Goals

- Do not reintroduce Search as a separate sidebar item.
- Do not expose graph edge tables directly.
- Do not implement vector search in the UI.

## Dependencies

- `TASK-005-memory-graph-domain-models.md`
- Real integration later: `TASK-111-hybrid-relatedness-service.md`

## Test Requirements

- View model tests for collection filters, related item selections, and match explanations.
- Tests for missing and permission-needed display states.
- UI smoke tests for Library with empty, loading, populated, and error states.

## Acceptance Criteria

- Library can find items by name, source, collection, recent capture, or related item.
- Search result rows explain at least one match reason when available.
- Missing files are recoverable or removable from Library without database inspection.

