# Native Truthful Fallback Design

## Context

Nexus now reads the main workspace workflow through Swift Native stores. The app still starts with `WorkspaceSummary.previewData`, and `PreviewNexusBridge` returns fabricated workspaces, source repositories, documents, Agent events, and automation findings when an authoritative read falls back to the unavailable legacy bridge. That makes a missing file or failed scan look like valid local state.

This is the first delivery slice of the long-term Native M1 Truthful Workflow goal.

## Goal

Default app startup and bridge fallback must never present sample data as real local workspace state.

## Non-Goals

- Delete preview fixtures used by model tests.
- Remove the `NexusBridge` compatibility protocol.
- Redesign the workspace UI or main workflow.
- Add a new demo-mode preference.

## Approaches Considered

### 1. Remove Preview support entirely

This gives the strongest boundary but forces unrelated test-fixture and bridge cleanup into the first slice. It is too broad.

### 2. Keep fixtures, make runtime fallback truthful

This is the selected approach. `AppState.preview()` starts empty, authoritative Preview bridge reads throw an explicit unavailable error, and optional feeds return empty collections. Existing sample fixtures remain available to tests that reference them directly.

### 3. Add an explicit demo-mode setting

This can be useful later, but a new setting, persistence rule, and UI state are unnecessary for fixing the current trust problem.

## Design

### Startup

`AppState.preview()` remains the app construction entry point for compatibility, but initializes with no workspaces and a loading status. `RootView.task` continues to perform the real Native refresh.

### Bridge fallback

`PreviewNexusBridge` represents an unavailable compatibility bridge, not a data source.

- Workspace scan, source repository scan, document read, demand-intake read, widget read, and automation check throw `NexusBridgeError.coreError` with an operation-specific message.
- Agent events, search results, and index summaries stay empty because they are optional feeds and already have empty-state UI.
- Write methods keep their existing explicit-confirmation checks and unavailable errors.
- Prompt formatting methods may keep deriving output from caller-supplied real values because they do not invent local state.

### Error handling

No new error framework is introduced. Existing `AppState` catches already route failed authoritative reads into `lastError`, document errors, source scan errors, or bridge error status.

### Test strategy

- Prove default app startup contains no sample workspace.
- Prove Preview bridge optional feeds are empty.
- Prove authoritative Preview bridge reads fail instead of returning samples.
- Keep the full Swift model/store suite green.

## Success Criteria

1. Launching the Native app never shows `WorkspaceSummary.previewData` before the first refresh.
2. A missing or unreadable document cannot render `# Preview Document`.
3. An unavailable bridge cannot invent source repositories, workspace risks, Agent events, or automation counts.
4. Existing explicit model fixtures remain usable by tests.
