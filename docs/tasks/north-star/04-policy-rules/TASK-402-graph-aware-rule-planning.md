# TASK-402: Graph-Aware Rule Planning

## Goal

Update rule evaluation and operation planning so rules operate over item profiles plus graph/source facts.

## Scope

- Allow conditions for source, folder context, collection membership, item kind, type, name, dates, tags, and extracted metadata.
- Produce graph/memory actions in `OperationPlan` or a compatible plan structure.
- Keep Inbox as the default fallback for uncertain/risky outcomes.
- Ensure index-before-action remains enforced.

## Non-Goals

- No UI form redesign.
- No AI classification.
- No recursive folder matching by default.

## Dependencies

- `TASK-401-memory-action-contracts.md`
- `../01-source-capture/TASK-104-watcher-source-integration.md`

## Test Requirements

- Workflow tests for source-aware conditions.
- Tests for graph-only rule actions.
- Tests for risky filesystem actions requiring review.
- Regression tests for folder-as-item behavior.

## Acceptance Criteria

- Rules are policy over memory facts, not just extension-to-folder routes.
- Fallback is review/Inbox unless explicitly configured.
- Physical file operations are optional and safety-checked.

