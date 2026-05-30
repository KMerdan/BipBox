# TASK-303: Rules UI

## Goal

Build the first workflow/rule editor for tree-like routing.

## Scope

- Display workflow tree.
- Add, edit, remove router branches.
- Add match conditions.
- Add action nodes.
- Configure fallback behavior.
- Run simulation against fixture item profiles.

## Non-Goals

- No AI rule authoring.
- No complex drag-reorder if a simpler editor is faster.
- No scripting.

## Dependencies

- `TASK-002-domain-models.md`
- `TASK-003-service-protocols.md`
- `TASK-102-workflow-engine.md` for real simulation, but fixtures can begin first.

## Test Requirements

- View model tests for adding/removing branches.
- Serialization test after editing a workflow.
- Simulation UI test using mock workflow engine.
- Test condition for item kind equals folder.

## Acceptance Criteria

- User can create a simple file rule.
- User can create a simple folder rule.
- User can define fallback to Needs Review.
- Simulation shows matched path through the workflow.

