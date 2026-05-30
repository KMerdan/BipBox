# Batch 01: Source Capture

Purpose: make watched sources durable, permission-aware, initially indexed, and continuously monitored.

Tasks:

- `TASK-101-json-source-store.md`
- `TASK-102-source-lifecycle-coordinator.md`
- `TASK-103-source-aware-cold-start-scan.md`
- `TASK-104-watcher-source-integration.md`
- `TASK-105-menu-bar-manual-source-events.md`

Parallelism:

- `TASK-101` and `TASK-102` can begin after contracts.
- `TASK-103` and `TASK-104` depend on source store behavior.
- `TASK-105` can start with fixtures once source-aware capture contracts exist.

