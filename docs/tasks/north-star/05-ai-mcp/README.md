# Batch 05: AI And MCP

Purpose: keep AI and MCP as safe adapters over native Bipbox tools, not direct mutators or required retrieval substrates.

Tasks:

- `TASK-501-native-tool-surface-refresh.md`
- `TASK-502-agent-orchestration-contract.md`
- `TASK-503-ai-privacy-settings-contract.md`
- `TASK-504-mcp-adapter-boundary.md`

Parallelism:

- `TASK-501` should happen before agent or MCP adapter work.
- `TASK-502` and `TASK-503` can proceed in parallel.
- `TASK-504` should stay transport-only and depend on native tools.

