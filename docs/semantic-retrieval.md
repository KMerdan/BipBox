# Semantic retrieval (RAG for the filesystem)

Bipbox turns every captured thing into a point in vector space and answers
"where is my X" by closeness. The same vectors power both retrieval (a ranked
list) and the Connections graph (a drawn map). Mental model: **math → picture →
words.**

## Architecture

```
capture ──► TextEmbedder ──► VectorIndex (points)
                                  │
   query ──► TextEmbedder ──┐     ├─► nearest()  ──► hybrid retrieval (list)
                            └────►│                     (lexical + vector + graph)
                                  └─► cluster()  ──► Connections graph (map)
                                                       (+ entity labels)
                                  └─► [optional] LLMProvider ──► query expand + RAG answer
```

### Components

| Component | File | Role |
|---|---|---|
| `TextEmbedder` / `NLEmbeddingTextEmbedder` | `BipboxCore/TextEmbedder.swift` | text → unit vector (on-device Apple model; pluggable) |
| `VectorIndex` / `SQLiteVectorIndex` | `BipboxCore/VectorIndexModels.swift`, `BipboxPersistence/SQLiteVectorIndex.swift` | store + cosine-nearest; per-model dimension |
| embed at capture | `BipboxCore/DefaultColdStartScanner.swift` | items → item model; folder/project contexts → `.entity` model |
| hybrid retrieval | `BipboxCore/RetrievalService.swift` | fuse lexical + vector (`semanticWeight`) + graph |
| semantic graph | `BipboxWorkspaceUI/WorkspaceModel.swift` | ego neighbors ← `nearest`; clusters ← vector clustering; labels ← nearest entity |
| Group-by lens | `WorkspaceModel.LibraryLens`, toolbar `groupByMenu` | Smart (semantic) · Type · Source · Time |
| target classification | `BipboxCore/TargetClassifier.swift` | folder nature → smart capture (no depth prompt) |
| language layer (optional) | `BipboxAI/LLMProvider.swift`, `SemanticAnswerService.swift` | query expansion + cited RAG answer |

### Key properties
- **Vectors are unit-normalized**, so the index's dot product is cosine similarity.
- **Items vs entities** share the index under sibling model ids (`<model>` and
  `<model>.entity`) so entity vectors label clusters without polluting item clustering.
- **Everything degrades gracefully**: no embeddings → retrieval falls back to
  lexical+graph and clusters fall back to Type; no LLM → query passthrough + no
  synthesized answer (the ranked list still shows).
- **Privacy**: the default embedder is fully on-device. `BIPBOX_SEMANTIC=0`
  disables the semantic layer for A/B. The LLM layer is opt-in behind the AI
  privacy settings.

## The optional language layer (llama.cpp)

`LLMProvider` is the seam. `UnavailableLLMProvider` is the default (no model). To
add a real local model, implement `LLMProvider` with a llama.cpp/GGUF backend and
construct `SemanticAnswerService(provider:)` with it (gated on the AI privacy
settings). **This is the one piece that needs an external artifact** (the GGUF
weights + the llama.cpp binding); the integration points, fallbacks, and tests are
already in place (`SemanticAnswerServiceTests`).

## X1 — Real-file quality spike (do before locking defaults)

Embedding quality must be proven on real files (north-star gate). Procedure:
1. Point Bipbox at a few real folders (a code workspace, Downloads, a docs folder).
2. Run a set of natural-language queries you'd actually type; check the top-5 for
   relevance vs lexical-only (`BIPBOX_SEMANTIC=0`).
3. Open Connections (Smart) and judge whether clusters read as meaningful
   neighborhoods; compare against Type/Source/Time lenses.
4. Tune: `semanticWeight` (RetrievalService), the clustering `threshold`
   (`semanticClusters`), and chunking of extracted text.

Drive it headlessly via the control API / harness (`docs/test-harness.md`):
`addFolder` your real dirs, then compare `search` snapshots with `BIPBOX_SEMANTIC`
on vs off.
