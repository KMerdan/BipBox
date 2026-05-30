# Batch 03: UI

Purpose: align visible app surfaces to the north-star product roles: Start manages sources, Library retrieves memory, Inbox handles decisions, Activity audits changes, Settings owns preferences.

Tasks:

- `TASK-301-start-source-management-ui.md`
- `TASK-302-library-retrieval-ui.md`
- `TASK-303-inbox-decision-recovery-ui.md`
- `TASK-304-activity-memory-audit-ui.md`
- `TASK-305-settings-preferences-privacy-ui.md`

Parallelism:

- `TASK-301` depends on source contracts and can use mock source coordinator.
- `TASK-302` depends on retrieval service but can start with fixtures.
- `TASK-303`, `TASK-304`, and `TASK-305` can proceed mostly independently after their view-model contracts settle.

