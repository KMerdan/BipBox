# TASK-104: Watcher Source Integration

## Goal

Run watchers from `SourceStore` rather than raw permission records.

## Scope

- Update watch-folder automation to load enabled watched-folder sources.
- Resolve each source's permission record before starting a watcher.
- Update source watch state and last scan summary after scans.
- Ensure watcher-submitted organization requests carry source ID and source detail.
- Keep non-recursive top-level detection.

## Non-Goals

- No FSEvents rewrite unless already planned; polling can remain.
- No UI changes except through exposed status data.
- No physical move policy changes.

## Dependencies

- `TASK-101-json-source-store.md`
- `TASK-103-source-aware-cold-start-scan.md`

## Test Requirements

- Tests that enabled watched sources start watchers.
- Tests that disabled sources do not start watchers.
- Tests for missing/stale permission state updating source watch state.
- Tests that a new file is indexed before any route/action path.

## Acceptance Criteria

- Watcher automation no longer conflates "has permission" with "is a source."
- Start can show accurate per-source operational state.
- Watched-folder arrivals can be traced to a source record.

