# Bipbox redesign → SwiftUI refactor guide

How to apply the HTML prototype (`Bipbox.html`) to the real app in
`Sources/BipboxWorkspaceUI`. The prototype is the **spec**; this maps each
idea to concrete Swift changes. Do it in small, shippable slices — the order
below is chosen so the app keeps building and running after every step.

---

## 0. Mental model shift

| Prototype concept | Today in code | Refactor target |
|---|---|---|
| One grouped sidebar | `WorkspaceSection` flat enum + `WorkspaceSidebar` | A sectioned `List` sidebar (groups) |
| Always-on inspector | each view rolls its own detail pane | one shared `InspectorView` |
| Selected item drives everything | per-view `@State` selection | one `Selection` model in `WorkspaceState` |
| Library = home, Overview→Cluster→File | `LibraryWorkspaceView` (search+filters) | `LibraryView` hosting list / gallery / graph |
| Inbox = decisions only | `ReviewQueueView` (+ duplicated source panel) | strip the watched-source panel; decision lives in the inspector |
| Sources in 3 places | Onboarding + ReviewQueue + Settings | one `SourcesView`; Settings keeps prefs only |
| Settings off main nav | `WorkspaceSection.settings` | macOS `Settings { }` scene (⌘,) |

The single biggest win — and the thing that removes most duplication — is the
**shared inspector driven by one selection**. Build that first.

---

## 1. Introduce a single Selection (do this first)

Create one selection type the whole workspace shares:

```swift
enum Selection: Hashable {
    case none
    case overview                 // graph overview level
    case item(KnowledgeItem.ID)
    case cluster(String)          // similarity group id
    case context(ContextNode.ID)  // person / project / topic / source / collection node
    case rule(RuleDocument.ID)
    case activity(ActivityEvent.ID)
}
```

Put `@Published var selection: Selection` on `WorkspaceState`. Every list sets
it; the inspector reads it. This is the prototype's `sel` string, typed.

Acceptance: clicking a Library row updates a shared selection (even before the
inspector exists).

---

## 2. Regroup the sidebar

Replace the flat `ForEach(WorkspaceSection.allCases)` in `WorkspaceRootView`
with a grouped SwiftUI `List` using `Section`s, matching the prototype:

- **Library**: All Items · Recents · Inbox (badge)
- **Watched Folders**: one row per `SourceRecord` (+ Add)
- **Collections**: saved searches / smart sets
- **Organize**: Rules · Activity

Keep `WorkspaceSection` but split `library` into `allItems` / `recents`, and add
a `source(SourceRecord.ID)` and `collection(Collection.ID)` case. Drive the
Inbox badge from `reviewQueue.pendingCount`.

Remove `.settings` from the sidebar — see step 6.

---

## 3. Build the shared InspectorView

One `InspectorView` switches on `state.selection` and renders:

- `.item` → details + "Why you're seeing this" + In context + Related +
  (if pending) the **decision block** (Approve / Keep / Reject).
- `.context`/`.cluster` → the **hub** view: header + "Connected items" list.
- `.rule` / `.activity` → the rule / event detail (move the existing detail
  panes from `RulesWorkspaceView` / `ActivityWorkspaceView` here).
- `.none` → empty prompt.

Pin it on the trailing edge of the workspace at a fixed width so it never
collapses (the "no layout shift" rule). Every per-item action (Open, Reveal,
Reindex, Locate, Add to Collection, Undo, Approve) lives here — delete those
buttons from the individual views as you migrate them.

---

## 4. Library hosts the three presentations

`LibraryView` keeps the search field + a view switch (Gallery / Connections)
and renders the current result set three ways. Reuse your existing
`SearchWorkspaceViewModel` for the data; the prototype's Gallery/Connections
are just alternate renderers over the same `[IndexedItem]`.

Connections is the only genuinely new view — see step 7. Ship List + Gallery
first; add the graph after.

---

## 5. Inbox = decisions only

In `ReviewQueueView`: **delete** the `intakePane` "Watched Sources" panel
(that logic now lives only in Sources). Inbox becomes a list of pending items;
selecting one shows the decision in the shared inspector. The queue list can
literally be the Library list filtered to `state == .needsReview`.

---

## 6. Sources + Settings split

- New `SourcesView` = today's onboarding source management
  (`OnboardingWorkspaceViewModel` is already most of it). This is the *only*
  place to add / pause / rescan / remove a source.
- Move Library-root / privacy / automation prefs into a real
  `Settings { SettingsView() }` scene so it opens with ⌘, and leaves the main
  nav.

---

## 7. Connections graph (last, optional)

This is the only part with no SwiftUI equivalent yet. Options:
- **Native**: a `Canvas`/`ZStack` ego-graph — center node + ring of neighbors,
  using your `RelationshipEdge` data. Start with the item ego view; add the
  Overview cluster level once clusters exist.
- **Pragmatic**: embed the HTML graph in a `WKWebView` and bridge selection via
  `postMessage` while the native version is built.

Cluster/Overview needs a similarity grouping the backend doesn't have yet —
ship Overview against simple topic/tag clusters first, upgrade to embeddings
later (matches your Tier-0 → Tier-1 plan in the north-star doc).

---

## Suggested PR order

1. `Selection` model + shared (empty) `InspectorView`, wired to Library list.
2. Grouped sidebar.
3. Inspector content for `.item` (incl. decision block); strip item actions
   from Library/Inbox.
4. Inbox panel removal; Sources view; Settings scene.
5. Library Gallery renderer.
6. Connections graph (ego → overview).

Each step is independently shippable and reduces duplication. Tokens (color,
spacing, type, light/dark) are in `assets/bipbox.css` if you want to mirror
exact values into a SwiftUI `Theme`.
