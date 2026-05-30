# Batch 00: Foundation

Purpose: create the shared project structure, domain contracts, and testing foundation that later work can build against independently.

Tasks:

- `TASK-001-project-scaffold.md`
- `TASK-002-domain-models.md`
- `TASK-003-service-protocols.md`
- `TASK-004-test-harness.md`
- `TASK-005-memory-graph-domain-models.md`
- `TASK-006-relatedness-spike-harness.md`
- `TASK-007-vector-index-contract.md`

Parallelism:

- `TASK-001` should happen first.
- `TASK-002` and `TASK-003` can progress together after the package/module shape is clear.
- `TASK-004` can start as soon as a test target exists.
- `TASK-005` should happen before durable memory graph storage.
- `TASK-006` can run independently as a gated spike and should not block Tier 0 graph/search implementation.
- `TASK-007` depends on `TASK-005` and can progress in parallel with persistence work once IDs and item models are stable.
