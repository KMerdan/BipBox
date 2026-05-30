# Batch 02: macOS Integration

Purpose: provide concrete macOS implementations behind the core service protocols.

Tasks:

- `TASK-201-filesystem-executor.md`
- `TASK-202-folder-watcher.md`
- `TASK-203-permissions-bookmarks.md`
- `TASK-204-menu-bar-status-item.md`
- `TASK-205-drag-drop-intake.md`
- `TASK-206-downloads-desktop-capture.md`
- `TASK-207-cold-start-scanner.md`
- `TASK-208-spotlight-natural-language-metadata.md`

Parallelism:

- `TASK-201`, `TASK-202`, and `TASK-203` can progress independently after service protocols exist.
- `TASK-204` and `TASK-205` can progress with mocked intake services.
- `TASK-206` depends on the capture-first pipeline so watched items are remembered before routing.
- `TASK-207` depends on the knowledge store and permission bookmarks.
- `TASK-208` depends on the relatedness spike and knowledge store, but its extraction failures must remain non-blocking.
