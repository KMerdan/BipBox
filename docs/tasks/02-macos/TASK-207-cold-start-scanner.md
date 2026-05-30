# TASK-207: Cold-Start Scanner

## Goal

Add a shallow, permission-based scanner that imports existing selected folders into the memory graph without moving files.

## Scope

- Implement a scanner service that walks only the selected shallow scope by default.
- Create `KnowledgeItem`, `CaptureEvent`, folder-derived context, and optional collection suggestion records.
- Respect security-scoped bookmarks and missing/denied permission states.
- Support cancellation and progress reporting.
- Primary codegraph scope: `FileSystemItemInspector.swift`, `SecurityScopedBookmarkPermissionStore.swift`, knowledge store from `TASK-108`, `ActivityLog`, `BipboxRuntimePaths.swift`.
- Change scope: platform adapter/service; onboarding UI is separate.

## Non-Goals

- Do not perform automatic filesystem moves.
- Do not deep-scan entire home directories by default.
- Do not add AI classification.

## Dependencies

- `TASK-108-knowledge-sqlite-store.md`
- `TASK-203-permissions-bookmarks.md`

## Test Requirements

- Tests for shallow scan item creation.
- Tests proving folders are recorded as items and not recursively exploded unless explicitly requested.
- Tests for cancellation and permission failure states.
- Tests for folder-path-derived context suggestions.

## Acceptance Criteria

- User-selected folders can be indexed in place.
- Scanner reports progress and recoverable errors.
- Existing folder structure becomes evidence, not an irreversible rule.

