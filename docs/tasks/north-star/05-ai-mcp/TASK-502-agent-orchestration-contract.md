# TASK-502: Agent Orchestration Contract

## Goal

Define the internal contract for a future AI agent that plans through tools without direct mutation.

## Scope

- Define agent request/response models for user intent, available tools, proposed plan, dry-run result, required approvals, and execution summary.
- Support "explain", "propose", "simulate", and "request approval" modes.
- Ensure all writes go through registered tools.
- Add no-model implementation for tests and UI placeholders.

## Non-Goals

- No OpenAI/Anthropic SDK integration.
- No autonomous background agent loop.
- No chat UI.

## Dependencies

- `TASK-501-native-tool-surface-refresh.md`

## Test Requirements

- Tests that unknown tools fail safely.
- Tests that write tools require explicit permission and can be dry-run.
- Tests that no-model agent never mutates state.

## Acceptance Criteria

- Agent architecture exists without requiring a model provider.
- Direct filesystem/database mutation is impossible through the agent contract.
- Future provider adapters have one stable boundary to implement.

