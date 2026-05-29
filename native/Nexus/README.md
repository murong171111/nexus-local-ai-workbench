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
- Sidebar Settings sheet with persisted workspace, source repository, delivery document roots, Codex URL, IDE URL template, refresh interval, and compatible team profile import/export.
- Native Settings path rows with per-path readiness, directory pickers, reveal actions, and environment checks for local path readiness, Git availability, workspace counts, and source repository counts.
- Chinese-first action labels and hover help for native path recovery, task source-document opens, task status updates, and task Codex handoff.
- Native create-workspace sheet that scans configured source repositories, filters and selects service scope, accepts manual service fallback, shows root/folder/destination/environment/scope preflight before local writes, and shows an initialization receipt after creation.
- Post-create next-step panel that focuses the new workspace and routes the user toward `handoff.md`, confirmed worktree setup, Codex handoff, or local checks.
- Result-aware native Codex handoff from worktree setup results, including created, skipped, and failed service details.
- In-card local-check feedback after running checks from native worktree setup results.
- Chinese-first result labels and action help in the native worktree setup result card.
- Native document preview renders Markdown by default and keeps a source-mode toggle for raw workspace files.
- Native workspace detail handoff actions open the workspace in Finder, IDE, Terminal, or Codex, copy a workspace `nexus://workspace/<folder>` link, and copy workspace context before opening Codex.
- Native workspace Codex handoff copies a richer handoff pack with latest local-check status, service/worktree summaries, open tasks, delivery checks, document paths, and Nexus recommended actions.
- Native workspace detail can bind, view, open, copy, and delete multiple Codex session deep links from workspace-local `codex-sessions.json`, and can suggest new bindings from matching recent Agent Event deep-link metadata.
- Native Workflow delivery focus card that turns task, delivery, risk, worktree, SQL, and lifecycle state into one next action.
- Native Workflow delivery-update Codex handoff that copies delivery record, tasks, SQL, risks, services/worktrees, and latest local-check context before opening Codex.
- Native Task Center recent-writeback card for task status updates that changed `tasks.md`.
- Native local-write feedback after task and lifecycle writebacks, with affected-workspace focus, source-document review, follow-up check actions, and compact inspector action layout.
- Unified inspector operation feedback for local errors, with copy-error, refresh, environment-check, Settings, and dismiss actions.
- Native widget snapshot writing to Application Support, with automatic `group.com.ks.nexus` App Group mirroring when the signed app has that entitlement.
- Recent agent event sidebar feed backed by the Swift/Rust agent event bridge, with detail inspection, safe metadata actions, shared task drafts, confirmed `tasks.md` writeback, Codex handoff prompts, and JSON copy support.
- Local Task Center that reads structured workspace task rows from Rust Core, lets the sidebar focus the owning workspace, and opens the owning `tasks.md` document directly when deeper review is needed.
- Workspace detail task section for reviewing local workspace and agent-sourced tasks, with direct access back to the source `tasks.md` record.
- Confirmed native task status updates for marking local tasks complete or deferred in `tasks.md`.
- Task-level Codex handoff actions that copy task context and open the configured Codex URL from the Task Center or workspace detail.
- Persisted Task Center filters for all, high-priority, agent-sourced, and deferred tasks.
- Menu bar quick status with workspace, risk, task, worktree, refresh, settings, recent-workspace, and copy-summary actions.
- Menu bar local automation checks backed by Rust Core for refresh, risk, delivery, task, worktree, and dirty-service signals.
- Persisted scheduled automation checks with 5/15/30/60 minute intervals while Nexus is running.
- Optional local macOS notifications for automation checks that need review or attention.
- Notification cooldown, minimum-status, and per-signal preferences for local automation alerts.
- Automation Action Center in the right inspector that converts local check signals into focus, delivery, task, worktree, and Codex handoff actions.
- Workspace timelines populated from the Rust Core dashboard activity field, including local audit-log events when the bridge is available.
- Native document opens append audit events and update the visible workspace timeline.
- Native workspace detail starts with a Command Center for lifecycle progress, primary-path guidance, a compact scope/worktree/risk/task/delivery/Codex-sessions/handoff session path, Codex continuation, local-check receipts, next-step routing, Finder/IDE/Terminal handoff, and workspace-link copy, with quick actions grouped into handoff, execution, and local tool lanes.
- Native shell handles `nexus://workspace/<workspace-folder>` by clearing filters/search, focusing the target workspace, refreshing widget state, and writing a matching audit event; the Command Center can copy that link for the selected workspace.
- Native Command Center includes Codex session links in the status overview, metrics, session path, bind fallback, and latest-session resume action.
- Native workspace detail starts with a compact status overview for lifecycle, branch, services, risk, tasks, delivery, Codex session count, and latest local-check state before deeper sections.
- Native workspace detail shows a dismissible Codex handoff feedback panel after workspace, lifecycle, risk, task, automation, or agent-event context is copied.
- Native workspace list and detail panes now include actionable empty states for first-run setup, empty filters, and missing selection.
- Native workspace detail shows Rust Core readiness checks for local development and delivery gates.
- Native SQL readiness blocks delivery when `交付记录.md` declares SQL changes but `sql/` lacks either formal SQL or rollback SQL files.
- Native Workflow delivery summary recommends confirmed lifecycle writebacks for entering delivery or marking the workspace done based on delivery readiness.
- Native workspace detail shows Rust Core session actions that prioritize the next Codex, worktree, and document follow-up steps.
- Native workspace detail includes a Workflow summary for open tasks, blocked tasks, delivery status, delivery-readiness checks, task/delivery document opens, local checks, and Codex handoff.
- Native workspace detail includes a Risk Review section for active risks, blocker/warning readiness checks, status document access, confirmed worktree setup, local re-check receipts, and Codex risk-review prompts.
- Native workspace detail includes a Documents Hub for standard workspace Markdown/script files, rendered through the preview/source document viewer with active-document highlighting, local missing-file recovery actions, and confirmed creation of missing standard document skeletons.
- Native workspace cards and details show Rust Core lifecycle stages with progress, next action, and Codex handoff controls.
- Native lifecycle transitions can be confirmed and written back to `workspace.md` and `STATUS.md` through Rust Core and FFI, with local audit logging.
- Archived workspaces can be filtered and restored later while staying out of active Task Center, menu-bar, and automation attention counts.
- Native worktree setup is available from session actions when the Rust Core bridge is loaded, guarded by a preflight review, explicit confirmation sheet, refreshed workspace state, result summary, and Finder/Codex/local-check follow-up actions.
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
