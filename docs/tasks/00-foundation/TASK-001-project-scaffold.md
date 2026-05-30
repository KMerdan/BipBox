# TASK-001: Project Scaffold

## Goal

Create the initial native macOS project structure for Bipbox with separate modules or targets for app UI, core domain logic, macOS adapters, persistence, and tests.

## Scope

- Create the macOS app scaffold.
- Add a clear source layout.
- Add build settings suitable for a modern Swift macOS app.
- Add empty test targets.
- Add basic app entry point that launches a workspace window.

## Non-Goals

- No real organization behavior.
- No menu-bar app behavior beyond placeholder structure.
- No persistence schema.

## Suggested Structure

```text
BipboxApp/
  App/
  WorkspaceUI/
  MenuBarUI/
  Core/
  MacOSAdapters/
  Persistence/
  AI/
  Tests/
```

The exact structure can change if the selected project system requires it, but the separation must remain.

## Dependencies

- None.

## Test Requirements

- Project builds from a clean checkout.
- Test target runs even if it contains only smoke tests.
- Add a smoke test that imports the core module.

## Acceptance Criteria

- A developer can build the app locally.
- A developer can run tests locally.
- UI, core logic, macOS adapters, persistence, and AI placeholders are not mixed into one undifferentiated module.
- No filesystem organization side effects occur when launching the app.

