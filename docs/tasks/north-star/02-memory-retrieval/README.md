# Batch 02: Memory Retrieval

Purpose: make Library the primary retrieval surface backed by source-aware knowledge, graph relationships, and recoverable missing-file state.

Tasks:

- `TASK-201-knowledge-schema-source-fields.md`
- `TASK-202-retrieval-query-service.md`
- `TASK-203-missing-file-recovery.md`
- `TASK-204-related-context-service.md`

Parallelism:

- `TASK-201` should precede persistence-dependent work.
- `TASK-202` can start with mock stores after contracts.
- `TASK-203` depends on source-aware knowledge state.
- `TASK-204` can start from existing graph services and fixture data.

