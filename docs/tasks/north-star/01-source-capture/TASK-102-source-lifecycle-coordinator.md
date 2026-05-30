# TASK-102: Source Lifecycle Coordinator

## Goal

Create one service that owns add, change, remove, rescan, pause, and resume behavior for sources.

## Scope

- Add a source coordinator protocol and implementation.
- On add/change, save permission bookmark, upsert source record, run initial shallow scan, and request watcher reload.
- On remove, remove source record and stop watching; decide whether permission removal is explicit or coupled.
- On pause/resume, update source or automation state without deleting records.
- Return progress and errors suitable for Start UI.

## Non-Goals

- No visual UI changes.
- No new scanner internals beyond calling existing scanner protocols.
- No recursive indexing.

## Dependencies

- `TASK-101-json-source-store.md`
- `../00-contracts/TASK-003-memory-capture-contracts.md`

## Test Requirements

- Unit tests for add source success path: permission saved, source upserted, scan called, watcher reload requested.
- Tests for change preserving source ID while updating path and permission reference.
- Tests for remove stopping watcher and removing source.
- Failure tests for permission denied, scan failure, and watcher reload failure.

## Acceptance Criteria

- There is a single non-UI API for source lifecycle operations.
- Adding a watched folder means "index now and watch later."
- Permission and source responsibilities remain separate.

