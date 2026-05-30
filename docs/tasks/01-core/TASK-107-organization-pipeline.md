# TASK-107: Organization Pipeline

## Goal

Compose intake, stabilization, inspection, routing, planning, execution, indexing, and logging into one orchestrated organization flow.

## Scope

- Accept an `OrganizationRequest`.
- Stabilize the item through a protocol.
- Inspect item.
- Run workflow.
- Create operation plan.
- Execute approved operations.
- Update search index.
- Write activity log events.
- Support organize, review, index-only, and simulate modes.

## Non-Goals

- No UI.
- No concrete FSEvents watcher.
- No model-backed AI.

## Dependencies

- `TASK-101-item-inspector.md`
- `TASK-102-workflow-engine.md`
- `TASK-103-operation-planner.md`
- `TASK-104-tool-registry.md`
- `TASK-105-activity-log.md`
- `TASK-106-search-index.md`

## Test Requirements

- End-to-end core test with all services mocked.
- Simulate mode test proving no executor call occurs.
- Review mode test proving item is staged, not moved.
- Folder request test proving one folder item flows through the pipeline.
- Error test proving failed execution is logged.

## Acceptance Criteria

- The pipeline has one clear public entry point for organization requests.
- Each stage is replaceable through protocols.
- Side effects happen only in execute/index/log stages.
- Pipeline output tells UI what happened or what review is needed.

