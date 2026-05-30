# TASK-102: Workflow Engine

## Goal

Evaluate tree-like workflows against `ItemProfile` values and produce route decisions.

## Scope

- Support router nodes.
- Support fallback branches.
- Support match conditions for item kind, filename, extension, type, source, size, dates, tags, and shallow folder summary.
- Support action nodes that emit action descriptors.
- Support review and stop nodes.
- Support simulate mode.

## Non-Goals

- No filesystem mutations.
- No AI model call.
- No visual editor.

## Dependencies

- `TASK-002-domain-models.md`
- `TASK-003-service-protocols.md`
- `TASK-004-test-harness.md`

## Test Requirements

- Unit tests for first-match routing.
- Unit tests for fallback routing.
- Unit tests for folder-specific rules.
- Unit tests for review node behavior.
- Unit tests for simulation producing the same decision without side effects.

## Acceptance Criteria

- Workflows are deterministic.
- The engine returns matched rule/node IDs for explainability.
- A folder can match folder rules without inspecting its children deeply.
- Unknown or invalid workflow nodes fail safely into review or error state.

