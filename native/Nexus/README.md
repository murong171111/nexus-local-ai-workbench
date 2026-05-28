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
- Sidebar Settings sheet with persisted workspace, source repository, delivery document roots, Codex URL, refresh interval, and compatible team profile import/export.
- Native Settings environment check for local path readiness, Git availability, workspace counts, and source repository counts.
- Native create-workspace sheet that scans configured source repositories, filters and selects service scope, accepts manual service fallback, and shows a confirmation summary before local writes.
- Post-create next-step panel that focuses the new workspace and routes the user toward `handoff.md`, confirmed worktree setup, Codex handoff, or local checks.
- Native document preview renders Markdown by default and keeps a source-mode toggle for raw workspace files.
- Native workspace detail handoff actions open the workspace in Finder, Terminal, or Codex, copying workspace context for Codex first.
- Native widget snapshot writing to Application Support, with automatic `group.com.ks.nexus` App Group mirroring when the signed app has that entitlement.
- Recent agent event sidebar feed backed by the Swift/Rust agent event bridge, with detail inspection, safe metadata actions, shared task drafts, confirmed `tasks.md` writeback, Codex handoff prompts, and JSON copy support.
- Local Task Center that reads structured workspace task rows from Rust Core and lets the sidebar focus the owning workspace.
- Workspace detail task section for reviewing local workspace and agent-sourced tasks without opening Markdown first.
- Confirmed native task status updates for marking local tasks complete or deferred in `tasks.md`.
- Task-level Codex handoff prompts that can be copied from the Task Center or workspace detail.
- Persisted Task Center filters for all, high-priority, agent-sourced, and deferred tasks.
- Menu bar quick status with workspace, risk, task, worktree, refresh, settings, recent-workspace, and copy-summary actions.
- Menu bar local automation checks backed by Rust Core for refresh, risk, delivery, task, worktree, and dirty-service signals.
- Persisted scheduled automation checks with 5/15/30/60 minute intervals while Nexus is running.
- Optional local macOS notifications for automation checks that need review or attention.
- Notification cooldown, minimum-status, and per-signal preferences for local automation alerts.
- Automation Action Center in the right inspector that converts local check signals into focus, delivery, task, worktree, and Codex handoff actions.
- Workspace timelines populated from the Rust Core dashboard activity field, including local audit-log events when the bridge is available.
- Native document opens append audit events and update the visible workspace timeline.
- Native workspace detail shows Rust Core readiness checks for local development and delivery gates.
- Native workspace detail shows Rust Core session actions that prioritize the next Codex, worktree, and document follow-up steps.
- Native workspace detail includes a Workflow summary for open tasks, blocked tasks, delivery status, task/delivery document opens, local checks, and Codex handoff.
- Native workspace detail includes a Documents Hub for standard workspace Markdown/script files, rendered through the preview/source document viewer.
- Native workspace cards and details show Rust Core lifecycle stages with progress, next action, and Codex handoff controls.
- Native lifecycle transitions can be confirmed and written back to `workspace.md` and `STATUS.md` through Rust Core and FFI, with local audit logging.
- Archived workspaces can be filtered and restored later while staying out of active Task Center, menu-bar, and automation attention counts.
- Native worktree setup is available from session actions when the Rust Core bridge is loaded, guarded by an explicit confirmation sheet, refreshed workspace state, result summary, and Finder/Codex/local-check follow-up actions.
- Build-only validation through Swift Package Manager.

## Build

```bash
swift build --package-path native/Nexus
```

This does not produce a signed `.app` bundle yet. Packaging, signing, notarization, Widget Extension targets, and updater integration are intentionally separate later steps.

## Rust Core Bridge

The Swift package includes a `NexusBridge` target with typed DTOs that match the Rust Core dashboard, source repository, workspace task, task handoff prompt, document, widget snapshot, audit event, agent event, SQLite/FTS search, confirmed workspace-creation, and confirmed worktree-setup JSON contracts.

For local development, build the bridge library from the repository root:

```bash
npm run ffi:build
```

Then launch the native shell with `NEXUS_CORE_LIBRARY` pointing to the generated `libnexus_ffi.dylib`. If the variable is missing or the library cannot be loaded, the shell falls back to preview data and metadata search results.
