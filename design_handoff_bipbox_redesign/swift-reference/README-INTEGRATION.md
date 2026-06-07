# Integrating the Bipbox redesign into the app

This `BipboxUI/` folder is a **complete, runnable SwiftUI implementation** of the
redesign (the same IA/UX as `Bipbox.html`). It compiles against in-file sample
data so you can run it today, then swap the data layer for your real services.

## Run it now (fastest)
Create a new macOS App target and add every `.swift` file in `BipboxUI/`. Build
and run — you get the full prototype: grouped sidebar, always-on inspector,
Library (gallery/connections), Overview→Cluster→File graph, search, Inbox
decisions, Rules, Activity, light/dark.

## File map
| File | Role | Maps to your code |
|---|---|---|
| `Theme.swift` | color/spacing/type tokens (light+dark) | new — a shared `Theme` |
| `Models.swift` | UI structs + `Selection` + **sample data** | `KnowledgeItem`, `SourceRecord`, `ContextNode`, `RuleDocument`, activity log |
| `WorkspaceModel.swift` | one `ObservableObject`: selection, nav, search, graph | replaces per-view view-models / `WorkspaceState` |
| `RootView.swift` | fixed 3-column shell + toolbar | `WorkspaceRootView` |
| `SidebarView.swift` | grouped IA | `WorkspaceSidebar` |
| `InspectorView.swift` | the ONE inspector | new (absorbs the detail panes) |
| `LibraryView.swift` | list / gallery + search results | `LibraryWorkspaceView` + `SearchWorkspaceViewModel` |
| `ConnectionsView.swift` | the graph (overview/ego/search) | new |
| `SupportingViews.swift` | Rules / Activity panes | `RulesWorkspaceView`, `ActivityWorkspaceView` |
| `Components.swift` | buttons, chips, flow layout, thumbs | new |

## Wire to real data (the only real work)
`WorkspaceModel` + `Sample` are the seam. Replace the `Sample.*` arrays with
your services and keep the struct shapes:

1. **Items** — map `IndexedItem` / `KnowledgeItem` → `KItem` in a small adapter.
   Feed `items(for:)` from `RetrievalService` / `SearchWorkspaceViewModel`.
2. **Sources** — `SourceRecord` → `Source`; drive the sidebar + source header
   actions (rescan/pause) through your `SourceLifecycleCoordinator`.
3. **Graph** — `neighbors(_:)` and `meta(_:)` are the adapter points for your
   `KnowledgeGraphService` / `RelationshipEdge`s. Today they read sample
   relationships; point them at real edges and everything else works unchanged.
4. **Clusters** — `Sample.clusters` is the Overview level. Start with
   tag/topic grouping; upgrade to embeddings later (your Tier-0 → Tier-1 path).
5. **Decisions** — `decide(_:_:)` should call your `OperationPlanner` /
   `request_user_review` tools instead of mutating `resolved`.
6. **Rules / Activity** — bind to `JSONRuleDocumentStore` and `JSONLinesActivityLog`.

## Suggested PR order (app keeps running after each)
1. Add `Selection` + empty `InspectorView`; host both in `WorkspaceRootView`.
2. Grouped sidebar.
3. Inspector `.item` content incl. decision block; delete the scattered
   per-view action buttons (Library/Inbox/Activity).
4. Strip the watched-source panel from `ReviewQueueView` (Inbox = decisions only).
5. Move preferences into a `Settings { }` scene (⌘,); drop `.settings` from nav.
6. Library gallery; then `ConnectionsView` (ego first, overview next).

## Notes
- Targets **macOS 13+** (uses the `Layout` protocol and `Canvas`).
- Accent color is `BB.accent`; to make it a Tweak, expose it via the model and
  read it in `Theme` (or inject an `@Environment` accent).
- Traffic-light room: `RootView` uses `.windowStyle(.hiddenTitleBar)` and the
  sidebar reserves leading space. If you keep the standard title bar, remove the
  `padding(.leading, 76)` in `SidebarView`.
- No external dependencies; pure SwiftUI + AppKit color bridging.
