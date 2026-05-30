# TASK-001: Source Models

## Goal

Add durable source-domain models that separate capture intent from filesystem permission state.

## Scope

- Define `SourceRecord`, `SourceKind`, `SourceRecursivePolicy`, `SourceIndexState`, `SourceWatchState`, and `SourceScanSummary`.
- Include fields from `docs/product-north-star.md`: display name, URL, permission record ID, enabled state, index state, watch state, last scan metadata, timestamps, and extensible metadata.
- Keep source records Codable, Equatable, Identifiable, and Sendable.
- Add helper constructors for watched folders and future menu-bar/manual-import sources.

## Non-Goals

- No persistence implementation.
- No UI changes.
- No watcher or scanner behavior changes.

## Dependencies

- None.

## Test Requirements

- Codable round-trip tests for every enum and `SourceRecord`.
- Tests proving `PermissionRecord` remains separate and is only referenced by ID.
- Tests for default watched-folder values: non-recursive by default, enabled by default, no scan summary before scanning.

## Acceptance Criteria

- Source models compile in `BipboxCore`.
- Source models can represent watched folders, menu-bar drops, manual imports, and future source kinds without changing existing permission records.
- Folder recursion is represented as `never` or explicit opt-in, never implicit.

