# TASK-006: Relatedness Spike Harness

## Goal

Create a one-day spike harness that evaluates whether Apple-native NLP plus metadata and graph signals can produce ship-quality related-file candidates on a few hundred real local files.

## Scope

- Add a throwaway or clearly marked spike target/script under `Tools/` or `Sources/` if the package structure supports it.
- Extract filename tokens, parent folder tokens, extension, UTType, dates, Finder tags, cheap text summaries, `NLTagger` signals, and `NLEmbedding` token-neighbor signals.
- Produce top related candidates using metadata-only, Apple NLP-only, and hybrid ranking.
- Write a markdown spike report template with pass/fail criteria from `docs/memory-graph-refactor.md`.
- Primary codegraph scope: `FileSystemItemInspector.swift`, `SQLiteSearchIndex.swift`, future relatedness service contracts.
- Change scope: spike and report only; do not wire into product UI.

## Non-Goals

- Do not ship the spike as a user-facing feature.
- Do not add a remote embedding provider.
- Do not commit private personal file paths or evaluation data.
- Do not make Library depend on this spike.

## Dependencies

- None

## Test Requirements

- Unit tests for token extraction, score normalization, and deterministic ranking on fixture files.
- Manual verification on private local files with results recorded outside source control or in a sanitized report.
- Confirm the harness handles unreadable files, folders, screenshots, Markdown, PDFs with no extracted text, and archives without crashing.

## Acceptance Criteria

- Running the harness produces ranked related candidates for at least three ranking modes.
- The output includes match explanations sufficient for manual review.
- A spike decision is recorded: Tier 1 ship-quality, useful-but-secondary, or not trustworthy.
- Product code does not depend on the spike result until a later implementation task chooses a tier.

