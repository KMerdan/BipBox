# TASK-309: Inbox Decision State UI

## Goal

Refine Inbox into a clear decision queue for unresolved context, failed operations, permission-needed items, kept-for-later items, and watcher status.

## Scope

- Add filters for Needs Decision, Kept For Later, Failed, Permission Needed, Rejected, and All.
- Surface watcher status for Downloads, Desktop, and user-added watched folders.
- Add recovery actions: retry, restore, dismiss, reconnect permission, scan now, pause/resume.
- Keep drag/drop capture out of the workspace page unless a specific UI decision later reintroduces it.
- Primary codegraph scope: `ReviewQueueView.swift`, `ReviewQueueViewModel.swift`, `WatchFolderAutomationService.swift`, `SQLiteSearchIndex.swift`, knowledge store from `TASK-108`.
- Change scope: Inbox UI/view model; service methods can be mocked first.

## Non-Goals

- Do not duplicate Library search.
- Do not add raw rule editing here.
- Do not recursively scan watched folders.

## Dependencies

- `TASK-005-memory-graph-domain-models.md`
- Real integration later: `TASK-206-downloads-desktop-capture.md`
- Real integration later: `TASK-109-capture-first-pipeline.md`

## Test Requirements

- View model tests for each decision-state filter.
- Tests that approved/restored/dismissed items move to the expected state.
- UI smoke tests for empty, active, paused, failed, and permission-needed states.
- Manual verification for `Scan Now` and reconnect permission flows.

## Acceptance Criteria

- Inbox answers "what needs my decision now?"
- Kept, failed, and rejected items are recoverable.
- Watcher health is visible without opening Settings.

