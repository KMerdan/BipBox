# TASK-403: AI Classification Workflow Node

## Goal

Add workflow support for an `ai_classify` node that can call the placeholder AI gateway and route based on structured AI output.

## Scope

- Add AI classification node evaluation.
- Support confidence thresholds.
- Support high-confidence route decision if allowed by workflow.
- Support medium/low confidence fallback to Needs Review.
- Include AI reason in route decision.

## Non-Goals

- No real AI model.
- No remote provider settings.
- No automatic destructive action.

## Dependencies

- `TASK-102-workflow-engine.md`
- `TASK-401-ai-gateway-placeholder.md`

## Test Requirements

- Unit test for no-decision placeholder response.
- Unit test for high-confidence fixture response.
- Unit test for medium-confidence review fallback.
- Unit test for folder profile classification.
- Unit test that destructive actions still require planner/user safety checks.

## Acceptance Criteria

- Workflows can include AI nodes before real AI exists.
- AI output is treated as advisory and structured.
- Planner remains responsible for safety.
- Folder items can be classified through the same node.

