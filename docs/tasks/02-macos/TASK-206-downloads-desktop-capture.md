# TASK-206: Downloads And Desktop Capture

## Goal

Promote Downloads and Desktop watching into first-class high-leverage capture sources while keeping all watcher behavior permission-based, visible, and non-recursive.

## Scope

- Add setup helpers for common capture locations: Downloads and Desktop.
- Reuse existing permission store and watcher automation instead of creating a separate path system.
- Record source details so capture events distinguish Downloads, Desktop, and user-added watched folders.
- Ensure automation can pause/resume all common capture watchers.
- Primary codegraph scope: `WatchFolderAutomationService.swift`, `PollingFolderWatcher.swift`, `SecurityScopedBookmarkPermissionStore.swift`, `ReviewQueueViewModel.swift`, `BipboxAppServices.swift`.
- Change scope: macOS adapter and app-service wiring; UI polish is separate.

## Non-Goals

- Do not watch folders without user-granted permission.
- Do not recursively process folder children.
- Do not require menu-bar drop to be removed.

## Dependencies

- `TASK-109-capture-first-pipeline.md`

## Test Requirements

- Automation tests for Downloads/Desktop permission records starting watchers.
- Tests that new top-level folders are submitted as one organization request.
- Tests for pause/resume and remove behavior.
- Manual verification that permissions can be granted and watchers survive app restart.

## Acceptance Criteria

- Downloads and Desktop can be enabled as capture sources.
- Captured items enter the same pipeline as menu-bar drops.
- Watcher status can be surfaced to Inbox through existing or extended view model state.

