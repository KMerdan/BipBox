# TASK-501: Native Tool Surface Refresh

## Goal

Expose source, retrieval, memory, rule, and safe action operations as native tools for future AI/MCP use.

## Scope

- Register or refine tools for source list/add/rescan, knowledge search/get/related, relationship/collection proposals, rule validate/apply/simulate, and action simulate.
- Include permission requirements, dry-run support, reversibility, and audit metadata.
- Keep native tools usable without MCP or any model provider.

## Non-Goals

- No external MCP transport.
- No real AI model calls.
- No direct database mutation bypassing service APIs.

## Dependencies

- `../01-source-capture/TASK-102-source-lifecycle-coordinator.md`
- `../02-memory-retrieval/TASK-202-retrieval-query-service.md`
- `../04-policy-rules/TASK-401-memory-action-contracts.md`

## Test Requirements

- Descriptor tests for each tool.
- Permission rejection tests.
- Dry-run tests for mutating tools.
- Audit-log tests for executed mutating tools.

## Acceptance Criteria

- Future AI can operate Bipbox only through native registered tools.
- Tool descriptors explain safety, dry-run, and permission behavior.
- Native app behavior does not depend on MCP.

