# Batch 03: UI

Purpose: build the user-facing workspace on top of service protocols and fixtures.

Tasks:

- `TASK-301-workspace-shell.md`
- `TASK-302-search-ui.md`
- `TASK-303-rules-ui.md`
- `TASK-304-review-queue-ui.md`
- `TASK-305-activity-undo-ui.md`
- `TASK-306-settings-ui.md`
- `TASK-307-onboarding-cold-start-ui.md`
- `TASK-308-library-collections-related-ui.md`
- `TASK-309-inbox-decision-state-ui.md`

Parallelism:

- All UI tasks can start with mocks after service protocols and fixtures exist.
- Integrate with real services incrementally as core and macOS tasks land.
- `TASK-307`, `TASK-308`, and `TASK-309` can start with fixture-backed view models after memory graph domain models exist.
- Real scanner, relatedness, and watcher integrations should be connected incrementally as their service tasks land.
