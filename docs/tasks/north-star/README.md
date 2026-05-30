# Bipbox North-Star Task Pyramid

This task pyramid decomposes `docs/product-north-star.md` into the next implementation wave.

The goal of this wave is to realign Bipbox around the product center:

> Local file memory and retrieval first; physical filing only as an optional safe action.

## Structure

```text
00-contracts
  Shared source, capture, memory, and test contracts.

01-source-capture
  Persistent sources, source lifecycle orchestration, cold-start indexing, and watcher integration.

02-memory-retrieval
  Knowledge graph persistence, Library retrieval, missing-file recovery, and relatedness.

03-ui
  Start, Library, Inbox, Activity, and Settings surfaces aligned to the north-star product roles.

04-policy-rules
  Rules and planning as policy over memory, including graph outcomes and safe filesystem actions.

05-ai-mcp
  Tool-bound AI/MCP boundaries that can operate over sources, memory, retrieval, and rules later.
```

## Dependency Rule

Depend on the smallest usable contract, not on a full feature stack. UI tasks can start against fixtures once contracts exist. Persistence tasks should not depend on UI. AI/MCP tasks should depend on native tool contracts, not on a real model provider.

## Parallel Work Guidance

- `00-contracts` should land first because it defines shared model names.
- After source and memory contracts exist, `01-source-capture` and `02-memory-retrieval` can run in parallel.
- `03-ui` can start with fixture-backed view models while real stores are under construction.
- `04-policy-rules` can start after memory action contracts exist.
- `05-ai-mcp` can start with descriptors and dry-run tools before any provider is integrated.

## Recommended Order

1. Complete `00-contracts`.
2. Implement `01-source-capture/TASK-101` and `TASK-102`.
3. Implement `02-memory-retrieval/TASK-201` and `TASK-202`.
4. Wire the Start and Library UI tasks.
5. Move Inbox, Rules, Activity, Settings, and AI/MCP onto the new boundaries.

## Definition Of Done

Every implementation task must include tests or a written reason it is docs-only. No task is complete if it makes physical filing the only successful outcome. Every touched capture path must preserve folder-as-item semantics and index before action.

