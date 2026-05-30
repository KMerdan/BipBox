# TASK-303: Inbox Decision Recovery UI

## Goal

Constrain Inbox to decisions and recovery, not source setup or general search.

## Scope

- Remove source-management controls from Inbox.
- Keep only compact source health summary if useful.
- Improve filters for needs decision, kept, failed, rejected, permission needed, and all.
- Provide actions: Approve, Change Plan, Keep for Later, Retry, Reject, Restore, Dismiss.
- Ensure approved items leave the decision list.

## Non-Goals

- No watched-source add/remove UI.
- No Library search duplication.
- No AI chat interface.

## Dependencies

- `../02-memory-retrieval/TASK-203-missing-file-recovery.md`

## Test Requirements

- View-model tests for every decision state transition.
- Tests for keep-later recovery and rejected restore/dismiss.
- Tests that approved items are removed from the active decision list.
- UI smoke tests for empty and failed states.

## Acceptance Criteria

- Inbox answers only "what needs my attention?"
- No user action in Inbox creates or deletes watched sources.
- Recovery from failed/kept/rejected states is visible and test-covered.

