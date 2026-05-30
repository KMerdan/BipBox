# TASK-204: Related Context Service

## Goal

Expose item relationships, contexts, and collections through a service suitable for Library and AI tools.

## Scope

- Add or refine service APIs for related items, contexts related to an item, and collection membership.
- Include source, folder, project/topic, rule, and similarity relationships where present.
- Provide deterministic Tier 0 relatedness using metadata and graph edges.
- Return explanations for related results.

## Non-Goals

- No local embedding spike.
- No model-backed relatedness.
- No UI layout work.

## Dependencies

- `TASK-201-knowledge-schema-source-fields.md`

## Test Requirements

- Tests for manual and rule-backed collection overlap.
- Tests for source/folder context relationships.
- Tests for deterministic ordering and tie-breaking.
- Tests that folders can have relationships as first-class items.

## Acceptance Criteria

- Library can show related items without using AI.
- Relationship results explain the connection.
- One item can appear in multiple contexts and collections.

