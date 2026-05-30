# TASK-401: AI Gateway Placeholder

## Goal

Define and implement a no-model AI gateway that preserves the future API shape without sending file data anywhere.

## Scope

- Define AI request and response models.
- Implement placeholder classifier.
- Return structured no-decision or needs-review responses.
- Include privacy flags in request context.
- Ensure no network access occurs.

## Non-Goals

- No real AI provider.
- No prompt engineering.
- No content upload.

## Dependencies

- `TASK-002-domain-models.md`
- `TASK-003-service-protocols.md`

## Test Requirements

- Unit test for placeholder classification response.
- Unit test that requests can include file and folder profiles.
- Unit test that remote content sharing defaults to disabled.

## Acceptance Criteria

- Future AI integration has a clear boundary.
- Placeholder never auto-approves organization by itself.
- Placeholder can be used by workflow nodes without special casing UI code.
- No item content is sent outside the app.

