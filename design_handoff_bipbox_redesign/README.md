# Handoff: Bipbox workspace UI/UX redesign

## Overview
This package re-architects the Bipbox macOS workspace from **6 flat tabs with
duplicated functions** into a **single grouped sidebar + one shared inspector**,
and adds a scalable **memory-graph** (Connections) view with semantic zoom
(Overview clusters -> Cluster -> File), live search, and filter chips.

The goal is to **bring this UI/UX into the real app** (`Sources/BipboxWorkspaceUI`,
SwiftUI), reusing the codebase's existing services and patterns — not to ship the
reference files verbatim.

## About the design files
Two references are included:
- `prototype/Bipbox.html` (+ `prototype/assets/`) — the **interactive HTML
  prototype**. Open in a browser to see exact look, motion, and behavior. It is a
  design reference, not production code.
- `swift-reference/BipboxUI/` — a **complete, runnable SwiftUI implementation** of
  the same design against sample data. This is your blueprint: structure, view
  hierarchy, tokens, and graph math are all here. Port it onto the real data
  layer; keep the structure.

## Fidelity
**High-fidelity.** Recreate pixel-for-pixel. Exact tokens are in
`swift-reference/BipboxUI/Theme.swift` (and `prototype/assets/bipbox.css`). Match
colors, spacing, radii, type, light/dark.

---

## The information architecture (what changes)

**Before** — `WorkspaceSection` flat enum: Start / Intake / Library / Rules /
Activity / Settings. Sources are managed in *three* places; per-item actions are
scattered; search/filter is re-invented per tab.

**After** — one grouped sidebar:
- **Library**: All Items / Recents / **Inbox** (badge = pending decisions)
- **Watched Folders**: one row per `SourceRecord` (the *only* place sources live)
- **Collections**: saved searches / smart sets
- **Organize**: Rules / Activity
- **Settings** -> moves to a `Settings { }` scene (Cmd+,), OFF the main nav

The keystone: **one `Selection` drives one `InspectorView`.** Selecting any item
anywhere shows its details + every per-item action there; if the item is pending,
the Approve/Keep/Reject decision appears in that same inspector (Inbox is just All
Items filtered to "needs a decision").

---

## Screens / views

### Shell (`WorkspaceRootView`)
Fixed 3 columns that NEVER change width on navigation — only their *content* swaps.
Sidebar **252pt** / center (flex) / inspector **344pt**. A unified toolbar sits
above center+inspector (search field, view toggle, appearance toggle).
> The previous app had layout shifts during navigation. The fixed-shell rule is a
> hard requirement: never add/remove a whole column when navigating.

### Sidebar
Grouped `ScrollView` with section headers (see IA above). Selected row =
accent-tinted rounded fill, accent icon+label. Inbox row shows a count badge.
Each watched-folder row shows a colored status dot.

### Library (center)
Global search field (top). A **view toggle** switches the center between:
- **Gallery** — calm card grid (thumb, status pill, name, source chip, date).
- **Connections** — the graph (default). See below.
Inbox reuses this as a plain decision list.

### Connections graph (the new, important part)
Three semantic-zoom levels with a clickable **breadcrumb** (`Overview > Cluster >
File`):
1. **Overview** (default, no selection) — similarity **clusters** as orbs, sized
   by file count, linked by shared-file overlap (edge thickness = overlap). Never
   renders all files at once — this is what makes it scale.
2. **Cluster / hub** — click a cluster (or a watched folder / collection) to zoom
   to its member files. Context/source/collection nodes are "hubs" with a badge
   showing their file count.
3. **File ego** — click a file to center it with its direct connections (source,
   contexts, similar file, collection). Edge labels name the relation. Hover dims
   everything except the hovered path. **Filter chips**
   (Sources/Projects/People/Topics/Files/Collections) appear on busy nodes and
   toggle each neighbor category.
Searching narrows the graph to a **results constellation** (a `"query" * N` center
with the matching files around it, colored by cluster).

### Inspector (one component, switches on `Selection`)
- **item** -> thumb + name + status pill; (if pending) decision block; "Why you're
  seeing this"; Details; In context (chips); Related (click to navigate).
- **hub** (context/source/collection/cluster) -> "Connected items" list + (for a
  source) Rescan/Pause.
- **overview** -> "Your library, by similarity" + cluster list.
- **rule** / **activity** -> rule editor summary / event detail + Undo.

### Search
Typing switches center to Search mode: view toggle becomes **Results / Map**.
Results = ranked list with matched-text highlighting, "Best matches / Also
related" groups, per-result "matched in ..." explanation. Map = the results
constellation. The clear (x) returns to Overview.

---

## Map to the real codebase

| Reference file | Real target |
|---|---|
| `Theme.swift` | new shared theme (or fold tokens where you keep styling) |
| `Models.swift` (`KItem`,`Source`,`ContextNode`,`Cluster`,`Rule`,`ActivityEvent`,`Selection`,`NavSection`) | adapters over `IndexedItem`/`KnowledgeItem`, `SourceRecord`, `ContextNode`, `RuleDocument`, activity log (`DomainModels.swift`, `MemoryGraphModels.swift`, `SourceModels.swift`, `RuleDocuments.swift`) |
| `WorkspaceModel.swift` | replaces per-view view-models / extends `WorkspaceState`; one `ObservableObject` holding `selection`, `section`, `mode`, `query` |
| `RootView.swift` | `WorkspaceRootView.swift` |
| `SidebarView.swift` | `WorkspaceSidebar` (in `WorkspaceRootView.swift`) + `WorkspaceSection`/`WorkspaceState.swift` |
| `InspectorView.swift` | new — absorbs detail panes from `LibraryWorkspaceView`, `ReviewQueueView`, `RulesWorkspaceView`, `ActivityWorkspaceView` |
| `LibraryView.swift` | `LibraryWorkspaceView.swift` + `SearchWorkspaceViewModel` |
| `ConnectionsView.swift` | new — `meta(_:)`/`neighbors(_:)` adapt onto `KnowledgeGraphService` / `RelatednessService` / `RelationshipEdge` |
| `SupportingViews.swift` | `RulesWorkspaceView.swift`, `ActivityWorkspaceView.swift` |

### Data seam (the only real work)
In `swift-reference/BipboxUI/WorkspaceModel.swift`, `items(for:)`, `search()`,
`meta(_:)`, `neighbors(_:)` read the `Sample.*` arrays. Repoint them at your
services and the rest works unchanged:
- items <- `RetrievalService` / `SearchWorkspaceViewModel`
- sources <- `SourceStore` / `DefaultSourceLifecycleCoordinator`
- graph neighbors/meta <- `KnowledgeGraphService` (`RelationshipEdge`, `ContextNode`)
- clusters <- start with tag/topic grouping; upgrade to embeddings later
  (Tier-0 -> Tier-1, per `docs/product-north-star.md`)
- `decide(_:_:)` <- route through `OperationPlanner` / `request_user_review`
- rules/activity <- `JSONRuleDocumentStore`, `JSONLinesActivityLog`

### Naming (user-facing)
Start -> **Watched Folders**, Intake -> **Inbox**, "Needs Review" -> **Needs a
decision**, "Index in place" -> **Remember**. Hide `OrganizationRequest` etc.

---

## Suggested PR order (app builds & runs after each)
1. Add `Selection` + an empty `InspectorView`; host both in `WorkspaceRootView`
   wired to the Library list selection.
2. Regroup the sidebar into sections.
3. Inspector `.item` content incl. the decision block; **delete** the scattered
   per-view action buttons (Library/Inbox/Activity).
4. Strip the "Watched Sources" panel from `ReviewQueueView` (Inbox = decisions
   only); build `SourcesView` / keep source rows in the sidebar.
5. Move preferences into `Settings { }` (Cmd+,); remove `.settings` from nav.
6. Library Gallery renderer; then `ConnectionsView` (ego first, then Overview).

## Design tokens
See `swift-reference/BipboxUI/Theme.swift` — accent `#0A84FF`; status good
`#1F9D57` / warn `#D98B1F` / bad `#E0533D` / info `#0A84FF` / grape `#8A5CF6`; ink
`#1D1D1F` <-> `#F4F4F6`; radii rows 7 / cards 10 / panels 12; spacing
4/8/12/16/20/24/32; SF system font; translucent sidebar+toolbar over opaque
content; hairline (0.5px) dividers.

## Notes
- macOS 13+ (uses `Layout` and `Canvas`). No external dependencies.
- The Swift reference is a careful first pass written without a compiler — expect
  minor fix-ups on first build.

## Files
- `prototype/Bipbox.html`, `prototype/assets/*` — interactive prototype
- `swift-reference/BipboxUI/*` — SwiftUI blueprint + its `README-INTEGRATION.md`
- `CLAUDE-CODE-PROMPT.md` — paste-ready starting prompt
