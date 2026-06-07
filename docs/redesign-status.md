# Redesign status & purpose refresh (2026-06-07)

## TL;DR

The backend is **real and working**. The redesigned UI is faithful to the handoff
but **launches empty and removed the app's front door**, so it *feels* like a demo.
This doc records the diagnosis and the fixes that re-anchor the UI to the product
north star (`docs/product-north-star.md`).

## What the product is (restated from the north star)

> Bipbox is a local file memory and retrieval system for macOS. It watches
> user-chosen sources, remembers files and folders in context, makes them
> searchable and relatable, and only performs physical filing as an optional,
> safe action.

The alpha loop that must work:
1. Add a folder (Downloads/Desktop/Documents/…) as a watched **source**.
2. Bipbox indexes current top-level items.
3. **Library immediately shows them.**
4. New arrivals appear automatically.
5. Ambiguous/risky items land in **Inbox**.
6. User approves/recovers decisions.
7. User searches by name, source, type, date, related context.

## Diagnosis: is the backend wired?

Audited end-to-end. The data path is sound:

- `BipboxAppServices.makeDefault()` builds **persistent SQLite** stores
  (`~/Library/Application Support/Bipbox/Data/...`) — search index + knowledge
  store + activity log + sources. No demo seeding; empty on first run.
- Empty-text query returns **all** indexed items (`SELECT id FROM indexed_items
  ORDER BY imported_at DESC`), so "All Items" shows everything that's indexed.
- `ColdStartScanner` writes each scanned file into the **same** search index the
  retrieval service reads from. Adding a source genuinely populates the Library.

What's actually WIRED through the new `WorkspaceModel`:

| Area | Status |
|---|---|
| Search / retrieval (text, kind, status, tags, source, date) | ✅ wired |
| Review decisions (approve/keep/reject → executor + persistence) | ✅ wired |
| Source lifecycle (add / rescan / pause / resume) | ✅ wired (VM intact) |
| Missing-file recovery (refresh/locate/reindex/remove) | ✅ wired (VM intact) |
| Activity log + undo | ✅ wired |
| Item contexts / related (read-only) | ✅ wired |

## Why it feels like a dummy (the real problem)

1. **Empty on launch, with no guidance.** Zero sources → zero indexed items →
   Library, Connections graph, clusters, and Inbox all render blank. Nothing tells
   the user what to do.
2. **The Start / Sources surface was deleted in the redesign.** The north star's
   #1 surface ("Start: Source Management" — Add Folder, quick-add common folders,
   permission/scan state, rescan/pause/resume, inline errors) was the deleted
   `OnboardingWorkspaceView`. Its view model (`OnboardingWorkspaceViewModel`) is
   still fully wired to the real lifecycle coordinator — only the UI is gone. Source
   adding was demoted to a single "+" in a sidebar header.
3. **Connections (empty graph) is the default center.** With no data the first
   thing a user sees is an empty hairball, reinforcing the "demo" impression. The
   north star says **Library/Search is the primary surface**, not the graph.

## Capabilities that exist in the backend but have no UI (by design, later)

These are *not* regressions — they were always backend-only and the north star
defers them (Tier-1/Tier-2): graph/relationship editing, collection building,
context creation, tool invocation panel, AI orchestration (currently a
`NoModelAIGateway` placeholder), workflow/plan inspection, metadata inspection.

## Fixes applied in this pass (re-anchor to the north star)

- **Restored a real Sources management surface** (`SourcesView`) as a first-class
  center pane, reusing `OnboardingWorkspaceViewModel`: quick-add Downloads/Desktop/
  Documents, Add Folder, per-source permission/scan state, rescan/pause/resume/remove,
  inline errors. Reachable from the sidebar "Watched Folders" header.
- **First-run / empty-state guidance** in the Library that routes to "Add a folder".
- **Default the Library center to Gallery** (real files first); Connections stays a
  toggle, with a helpful empty state when there's no data.
- **Drag-drop capture into the window** (`onDrop` → existing `dropIntakeHandler`),
  so files can be captured directly — north-star "capture coverage."

## Second pass (2026-06-07): rules, data hygiene, connections

- **Rules page is now functional.** It was render-only (static toggle, no add/delete).
  Added real VM operations: `addBlankRule`, `deleteRule`, `setRuleEnabled`,
  `renameRule`, each persisting to the JSON rule store. Critically, disabling a rule
  keeps it on disk (the workflow only contains enabled rules, so the naive
  "re-derive docs from workflow" save path would have *deleted* disabled rules — the
  new `persistRuleDocuments` path preserves them). Center view has a working
  per-rule switch + "New Rule"; inspector has rename + delete + enable toggle.
  Condition/destination editing is still JSON-backed (noted in the UI).
- **Database cleaned.** Old experiment data (degenerate index, stale WAL, leftover
  top-level `Inbox/`/`Library/` dirs from an older layout) was moved to
  `~/Library/Application Support/Bipbox.backup-<ts>` (reversible). The app recreates
  a clean store on launch.
- **Connections clustering fixed + made honest.** The previous clustering grouped by
  `tags.first`; real scanned files have no Finder tags, so everything collapsed into
  one "untagged" orb, and `clusterLinks` (item-overlap between *disjoint* clusters)
  was always empty → no edges. Replaced with **type-category clustering** (Folders /
  Documents / Images / Code / …, always populated) and **edges by shared parent
  folder** (a real structural co-occurrence signal). Relabelled "by similarity" →
  "by type & location"; ego "similar" edge → "related". There is still **no semantic
  embedding model** — that remains the Tier-1 upgrade and is the honest answer to
  "semantic similarity": it isn't computed yet; today's graph is lexical + structural.

## Third pass (2026-06-07): connections graph + watch-folder depth

### Connections graph — deep fix
Root causes found by reading the data model + a real end-to-end test:
- Context/collection center nodes had **hardcoded placeholder names** ("Context",
  "Collection") and **empty member lists** → clicking them led nowhere with a
  meaningless label.
- Item neighbors piggybacked on `selectedOverview`/`selectedRelated`, which are
  loaded lazily by the *inspector* for the selected item → stale/missing data when
  the graph centered on a different node (the "meaningless connections").

Fix: the graph now loads its **own** data, async, **keyed by the centered node**
(`WorkspaceModel.loadGraph(center:)` + `WorkspaceGraphServices` injecting the real
`KnowledgeGraphService` / `RelatednessService` / `KnowledgeStore`). `EgoGraph` uses
`.task(id: center)` so each node loads fresh — no stale neighbors. Real neighbor
sources: item→folder/topic contexts (`graph.contexts(relatedTo:)`), related files
(`relatedness.relatedItems`), source, type cluster; context hub→member items
(`graph.relationships(objectID:)`); collection hub→`graph.itemIDs(inCollection:)`.
Verified by `WatchedFolderIndexingIntegrationTests.testGraphLoadsItemContextsAndContextMembers`
(item links to its folder context; clicking the context lists its member files).

Data-model note: `IndexedItem.id == KnowledgeItem.id == stableUUID("knowledge-item:<path>")`,
and each scanned item gets a `belongsTo` edge to a folder `ContextNode`
(`stableUUID("folder-context:<path>")`). That shared id space is what makes the
graph adapters resolve.

### Watch-folder indexing depth
The backend was **not** broken: `testAddingWatchedFolderIndexesTopLevelChildren`
proves adding a folder indexes its top-level children (and the bookmark grant works
unsandboxed). The real gap was UX: depth was hardcoded to `.never` (top level only),
so any **subfolder** was captured as a single item — i.e. "treats the folder as a
single target." Added an **index-depth prompt** (`WorkspaceModel.askIndexDepth`) on
add: "Top level only" (`.never`) vs "Everything inside" (`.always`, recurses).
Threaded `recursivePolicy` through `OnboardingWorkspaceViewModel.add*WatchedFolder`.

## Still deferred (tracked, not done here)

- Knowledge-graph / collection **editing** UI.
- Context-filtered search (`RetrievalQuery.contextIDs` is supported; no picker yet).
- Real AI provider behind privacy settings.
- Metadata / workflow / operation-plan inspectors.
