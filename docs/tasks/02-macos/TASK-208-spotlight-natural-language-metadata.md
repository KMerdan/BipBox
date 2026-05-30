# TASK-208: Spotlight And Natural Language Metadata

## Goal

Collect optional macOS-native metadata and lightweight NLP signals that can improve search, relatedness, and cold-start context without requiring remote AI.

## Scope

- Add a metadata extraction adapter for Spotlight-accessible metadata where available.
- Add NaturalLanguage extraction for `NLTagger` tokens, lemmas, lexical classes, and candidate names on cheap text inputs.
- Store extracted signals in metadata snapshots or a dedicated feature table through the knowledge store.
- Gate `NLEmbedding` use behind the spike result and graceful availability checks.
- Primary codegraph scope: `FileSystemItemInspector.swift`, `SQLiteSearchIndex.swift`, knowledge store from `TASK-108`, `TASK-006-relatedness-spike-harness.md`.
- Change scope: metadata adapters and tests; no UI and no product promise until validated.

## Non-Goals

- Do not add remote AI.
- Do not require OCR.
- Do not block capture when metadata extraction fails.

## Dependencies

- `TASK-006-relatedness-spike-harness.md`
- `TASK-108-knowledge-sqlite-store.md`

## Test Requirements

- Unit tests with fixture text for deterministic `NLTagger` extraction.
- Tests that unsupported metadata or unreadable files produce recoverable warnings.
- Tests that metadata extraction is optional and does not fail pipeline capture.

## Acceptance Criteria

- Metadata/NLP signals can be stored and queried for ranking.
- Extraction failures never prevent an item from being captured.
- The implementation can be disabled or ignored if Tier 1 spike quality is not good enough.

