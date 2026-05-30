# TASK-404: Policy Safety Invariants

## Goal

Codify safety rules across capture, rules, planning, execution, and AI/tool paths.

## Scope

- Add tests and guardrails for index-before-action.
- Enforce no recursive folder processing by default.
- Prevent silent fallback destinations.
- Require review or reversible plans for risky filesystem operations.
- Ensure Activity logs every mutation.

## Non-Goals

- No UI redesign.
- No notarization or sandbox entitlement work.
- No new AI provider behavior.

## Dependencies

- `TASK-402-graph-aware-rule-planning.md`
- `../01-source-capture/TASK-104-watcher-source-integration.md`

## Test Requirements

- End-to-end tests for watched-source arrival indexing before movement.
- Tests for rule failure leaving item findable in Library.
- Tests for folder-as-item invariants across drop, scan, watcher, and rules.
- Tests for activity log entries on every mutation path.

## Acceptance Criteria

- The north-star safety rules are executable tests.
- No capture path can move/delete before the item is indexed.
- Unknown or risky outcomes are staged for decision instead of silently filed.

