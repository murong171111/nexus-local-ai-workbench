# Nexus Native Shell

This package is the first native macOS shell for Nexus.

The current production-preview app remains the Tauri app. This SwiftUI/AppKit package exists to grow the long-lived Mac experience in parallel while reusable workflow behavior moves into `crates/nexus-core`.

## Scope

- SwiftUI workspace navigation shell.
- AppKit-ready Mac integration boundary.
- Sample data view model that mirrors the Rust Core dashboard contract.
- Native top-bar search popover backed by the Swift/Rust SQLite + FTS bridge, with preview metadata fallback.
- Search result context previews with workspace risk, branch/service summary, and compact activity timeline.
- Persisted native search scopes for workspace, state, workflow, SQL, and document-focused searches.
- Pinned workspaces in the sidebar and workspace card flow, stored as local Mac preferences.
- Sidebar Settings sheet with persisted workspace, source repository, and delivery document roots.
- Recent agent event sidebar feed backed by the Swift/Rust agent event bridge, with detail inspection, safe metadata actions, shared task drafts, confirmed `tasks.md` writeback, Codex handoff prompts, and JSON copy support.
- Workspace timelines populated from the Rust Core dashboard activity field, including local audit-log events when the bridge is available.
- Native document opens append audit events and update the visible workspace timeline.
- Native workspace detail shows Rust Core readiness checks for local development and delivery gates.
- Native workspace detail shows Rust Core session actions that prioritize the next Codex, worktree, and document follow-up steps.
- Native worktree setup is available from session actions when the Rust Core bridge is loaded, guarded by an explicit confirmation sheet and result summary.
- Build-only validation through Swift Package Manager.

## Build

```bash
swift build --package-path native/Nexus
```

This does not produce a signed `.app` bundle yet. Packaging, signing, notarization, Widget Extension targets, and updater integration are intentionally separate later steps.

## Rust Core Bridge

The Swift package includes a `NexusBridge` target with typed DTOs that match the Rust Core dashboard, source repository, document, widget snapshot, audit event, agent event, SQLite/FTS search, confirmed workspace-creation, and confirmed worktree-setup JSON contracts.

For local development, build the bridge library from the repository root:

```bash
npm run ffi:build
```

Then launch the native shell with `NEXUS_CORE_LIBRARY` pointing to the generated `libnexus_ffi.dylib`. If the variable is missing or the library cannot be loaded, the shell falls back to preview data and metadata search results.
