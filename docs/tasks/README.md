# Bipbox Task Pyramid

This directory decomposes `docs/design.md` and `docs/memory-graph-refactor.md` into incremental implementation tasks.

The current coherent next wave is the north-star source/memory/retrieval refactor:

- [`north-star/README.md`](north-star/README.md)

Use the north-star pyramid when choosing new work. The older batches remain as historical and partially implemented planning context.

The structure is a pyramid:

```text
00-foundation
  Shared contracts, project shape, app shell, test harness.

01-core
  Platform-light organization engine, rules, tools, planning, index, log.

02-macos
  macOS adapters for filesystem, permissions, folder watching, status item.

03-ui
  Workspace screens and menu-bar interaction on top of core services.

04-ai-ready
  Placeholder AI interfaces and tool orchestration boundaries.
```

The current next development wave is the memory-graph refactor:

- Keep the current organizer working.
- Add retrieval-first memory graph contracts and stores.
- Move capture before routing.
- Promote Library and Inbox around retrieval and decision state.
- Keep AI/MCP behind native tool contracts.

## Dependency Rule

Tasks should depend on contracts, not concrete implementations, whenever possible.

For example, the search UI should depend on a `SearchService` protocol and fixture data before the SQLite implementation is complete. The rule editor should depend on workflow model fixtures before the full workflow engine is complete.

## Parallel Work Guidance

Good parallel lanes:

- Domain models and test harness.
- Rule engine and SQLite search index.
- macOS status item and workspace shell.
- Activity UI and operation log.
- AI gateway placeholder and tool registry.
- Memory graph domain contracts, relatedness spike, and vector-index contract.
- Knowledge SQLite store, Library fixture UI, and Inbox fixture UI once contracts exist.

Avoid parallelizing two tasks that both define the same public model or storage schema unless the contract task is already complete.

## Batch Order

1. Complete foundation contracts first.
2. Start core services and macOS adapters in parallel.
3. Start UI screens once service protocols and fixtures exist.
4. Add AI-ready orchestration once the tool registry contract exists.
5. For the memory-graph wave, run `TASK-006` before committing to Tier 1 NLP relatedness, but do not block Tier 0 graph/search work on that spike.

## Definition of Done

Each task file includes:

- Scope.
- Non-goals.
- Inputs and outputs.
- Dependencies.
- Test requirements.
- Acceptance criteria.

No task is complete without its paired tests or a documented reason that it is documentation-only.

For memory-graph work, no task is complete if it makes physical filing the only successful outcome. Indexing in place, adding relationships, and adding collections must remain valid outcomes where the task touches capture, retrieval, or rules.
