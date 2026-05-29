# Nexus Mac App Implementation

## Product Target

Nexus is a local macOS developer workbench for managing requirement workspaces, git worktrees, service status, delivery documents, risks, and Codex-driven workflows.

The app is designed as a native local tool, not a browser-only dashboard.

## Architecture

- Current preview shell: Tauri
- Current preview UI: React, TailwindCSS
- Target native shell: SwiftUI + AppKit
- Target core: reusable Rust crates, called by the native shell and the current Tauri preview shell during migration
- Workspace data source: user-configured local workspace root
- Human-readable archive: workspace Markdown files
- Future local index: SQLite + FTS
- Widget surface: Swift WidgetKit extension fed by app-generated snapshots

See `docs/adr/0001-native-swiftui-rust-core.md` and `docs/native-architecture.md` for the accepted medium-term architecture direction.

## Implemented In This Step

- Added `src-tauri` application scaffold.
- Added macOS bundle config for `Nexus`.
- Added native commands:
  - `open_url`
  - `open_path`
  - `open_terminal`
  - `open_idea`
  - `scan_workspaces`
  - `create_workspace`
  - `read_text_file`
  - `write_widget_snapshot`
- Added Rust Core JSONL audit logging for confirmed workspace creation and settings profile export.
- Added Rust Core dashboard activity enrichment from the local JSONL audit log.
- Added user-action audit events for document opens, Codex handoffs, copied prompts, copied risk instructions, and copied worktree commands.
- Added Rust Core readiness checks and surfaced them in the Tauri preview cards, workspace drawer, and native SwiftUI detail panel.
- Added Rust Core session actions and surfaced them in the Tauri preview cards, workspace drawer, and native SwiftUI detail panel.
- Added Rust Core workspace lifecycle derivation and native SwiftUI lifecycle displays with progress, next-action, document-open, worktree setup, and Codex handoff controls.
- Added confirmed Rust Core, FFI, and native SwiftUI lifecycle writeback for `workspace.md` and `STATUS.md`, with local audit events for status transitions.
- Added native Workflow lifecycle recommendations that turn delivery-readiness results into confirmed lifecycle writeback actions.
- Added a native Workflow delivery focus card that turns task, delivery, risk, worktree, SQL, and lifecycle state into one recommended next action.
- Added native Workflow delivery-update Codex handoff with delivery record, tasks, SQL, risks, services/worktrees, and latest local-check context.
- Added SQL artifact enforcement so delivery records that declare SQL changes require both formal SQL and rollback SQL files under `sql/`.
- Added native local-write feedback after task and lifecycle writebacks, including source-document review and follow-up check actions.
- Added affected-workspace focus from native local-write feedback so task-center writebacks can return users to the refreshed workspace detail.
- Converged native local-write feedback actions so source-document and follow-up check actions focus the affected workspace first and wrap cleanly in the inspector.
- Added unified native operation feedback for local errors, with copy-error, refresh, environment-check, Settings, and dismiss actions in the inspector.
- Added a compact recent-writeback card to the native Task Center for task status updates that changed `tasks.md`.
- Added confirmed worktree setup through Rust Core, FFI, and the Tauri preview UI, with audit logging and command-copy fallback in browser preview mode.
- Added result-aware native Codex handoff from worktree setup results, including created/skipped/failed service details.
- Added in-card local-check feedback after running checks from native worktree setup results.
- Converged native worktree setup result labels to Chinese-first actions, result groups, and compact metric help.
- Added Rust Core SQLite + FTS index rebuild/search support for workspace Markdown and SQL notes.
- Added Tauri commands for rebuilding and querying the local search index.
- Added a top-bar global search popover that uses the local index in the packaged app and workspace metadata fallback in browser preview mode.
- Added grouped search result sections and keyboard navigation to the Tauri preview search popover.
- Added native SwiftUI search state and a top-bar search popover that uses the Swift/Rust local-index bridge with workspace metadata fallback.
- Added native selected-result context previews and a reusable compact activity timeline for workspace details.
- Added native search scope controls for workspace, state, workflow, SQL, and document search modes.
- Added native Markdown document preview with preview/source modes, active-document highlighting, and local document-open recovery inside the SwiftUI workspace detail panel.
- Added locally persisted pinned workspaces in the native SwiftUI shell, including card-level pin actions and a sidebar pinned section.
- Added a native Settings sheet from the sidebar with persisted local roots, save-and-reload, and reset-defaults actions.
- Added actionable native session rows for document follow-ups and confirmed worktree setup, including a local-write confirmation sheet and created/skipped/failed result summary.
- Added Rust Core and Swift/Rust bridge support for append-only agent event JSONL, plus a native sidebar feed for recent agent events.
- Added native agent event detail inspection with metadata and JSON copy support.
- Added safe native agent event actions for selecting matching workspaces, opening local paths and links, copying Codex continuation context, and copying that context while opening Codex in one action.
- Added shared Rust Core, FFI, and Swift bridge generation for Codex handoff prompts from agent events.
- Added shared Rust Core, FFI, and native SwiftUI task drafts derived from agent events, including category, priority, prompt, and related targets.
- Added confirmed Rust Core, FFI, and native SwiftUI writeback from agent task drafts into workspace `tasks.md`, with audit logging.
- Added structured Rust Core, FFI, and native SwiftUI task snapshots from workspace `tasks.md` rows.
- Added a native local Task Center in the sidebar and a workspace task section in the detail panel.
- Added task source-line locators from Task Center and workspace detail task rows so task review can jump back to the Markdown source of truth with copied line context.
- Added confirmed task status updates from the native Task Center back into `tasks.md`, with FFI audit logging.
- Added shared Rust Core, FFI, and native SwiftUI Codex handoff prompts for workspace tasks.
- Added native task-level Codex copy-and-open handoff from Task Center and workspace detail, with task-specific feedback and audit events.
- Added persisted native Task Center filters for all, high-priority, agent-sourced, and deferred tasks.
- Added a native menu bar quick status item with workspace, risk, task, worktree, refresh, settings, recent-workspace, and copy-summary actions.
- Added Rust Core, FFI, Swift bridge, and native menu bar support for local automation checks covering refresh, risk, delivery, task, worktree, and dirty-service signals with fail-open audit logging.
- Added persisted native scheduled automation checks with 5/15/30/60 minute intervals while Nexus is running.
- Added optional local macOS notifications for automation checks that return review or attention status.
- Added automation notification preferences for cooldown, minimum status, and signal types.
- Added a native Automation Action Center that turns local check signals into focus, delivery, task, worktree, and Codex handoff actions.
- Added inline local-check receipts in Command Center and Risk Review so manual checks leave visible status, metric, audit, and copy-summary feedback near the workflow that triggered them.
- Added a compact native workspace-detail status overview for lifecycle, branch, services, risk, tasks, delivery, Codex sessions, and latest local-check state.
- Added a fail-open hook helper script that local agents can call to append events into Nexus before a local socket server is available.
- Added an explicit local-write confirmation checkbox to the Tauri create-workspace flow.
- Added frontend desktop bridge in `src/desktop.ts`.
- Switched the frontend bridge to the official `@tauri-apps/api/core` dynamic invoke API.
- Added UI actions to open Codex from the workbench.
- Added "copy instruction and open Codex" flow for a workspace, later expanded into a richer handoff pack with checks, tasks, delivery, services, document paths, and recommended actions.
- Added workspace-level Codex session deep-link bindings in the native detail surface, stored in `codex-sessions.json` with bind, view, open, copy, and confirmed delete actions.
- Folded Codex session links into the native Command Center overview, metrics, session path, and clean primary action so saved sessions are part of the core workspace flow.
- Added configurable native IDE handoff from the Command Center local tool lane, backed by a Settings URL template that defaults to IntelliJ IDEA and is included in exported team profiles.
- Added workspace-link copy to the Command Center local tool lane, using the registered `nexus://workspace/<folder>` format and a right-inspector feedback card.
- Added native workspace creation based on the `ks-project-demand-workspace` standard layout.
- Added create-workspace preflight in the native sheet for workspaces root readiness, folder validity, destination collisions, environment health, and scope review before confirmed local writes.
- Added native source repository scanning for service selection.
- Added native environment health checks for configured paths and Git availability.
- Added first-run onboarding for local path setup.
- Added service picker to the workspace creation flow.
- Added workspace bootstrap report and reviewable worktree command script generation.
- Added delivery record placeholder detection as a workspace risk signal.
- Added in-app Markdown document preview for workspace documents.
- Added confirmed missing-standard-document recovery through Rust Core/FFI from the native Documents Hub.
- Moved Settings to the lower-left app rail and kept it focused on local path customization for sharing.
- Added widget snapshot generation through the native `write_widget_snapshot` command.
- Added `nexus://workspace/<workspace-folder>` URL scheme registration and native deep-link handling that focuses the target workspace, clears filters/search, refreshes widget state, and records an audit event. The native Command Center can copy the same link for sharing with widgets, scripts, or another teammate's Nexus setup.
- Added WidgetKit Swift source under `widget/NexusWidget`.
- Added Tauri npm scripts:
  - `npm run tauri:dev`
  - `npm run tauri:build`
- Added temporary app icon at `src-tauri/icons/icon.png`.
- Added repeatable icon generation script at `scripts/generate-icon.mjs`; `npm run icon` also runs `tauri icon` to generate `icon.icns`.
- Built the macOS `.app` and `.dmg` successfully.
- Added public maintenance docs, issue templates, pull request template, CI workflow, release workflow, and a lightweight Node.js test runner.
- Added a stricter Tauri content security policy for production builds.

## Build Outputs

```text
src-tauri/target/release/bundle/macos/Nexus.app
src-tauri/target/release/bundle/dmg/Nexus_0.1.0_aarch64.dmg
```

## Runtime Boundaries

The app should keep three permission levels:

- Read-only: scan workspace documents and git status.
- Confirmed action: open IDEA, Terminal, Finder, Codex, create workspace files, export settings profiles, generate worktree commands.
- Dangerous action: reset, clean, delete branch, overwrite files. These must require explicit confirmation.

Local audit events are stored at `~/Library/Application Support/com.ks.nexus/audit/audit-log.jsonl`. Widget snapshot refreshes are cache writes and are not logged on every refresh.

The local search index is stored at `~/Library/Application Support/com.ks.nexus/nexus-index.sqlite3`. It is a rebuildable cache generated from workspace Markdown files and `sql/` notes.

## Next Engineering Steps

1. Extract workspace, git, document, risk, settings, and widget snapshot logic into a reusable Rust Core crate.
2. Keep Tauri commands as thin wrappers around Rust Core during migration.
3. Scaffold the SwiftUI/AppKit native Mac shell.
4. Add the Swift/Rust bridge and render real workspace data in the native shell.
5. Add more audited event types for validation runs and PR handoff.
6. Package the WidgetKit extension with a full Xcode target and App Group storage.
7. Add signing, notarization, and update channels after the native shell is ready.

## Local Build Notes

Verify Node, Rust, and Cargo before building:

```bash
node --version
cargo --version
rustc --version
```

Use these commands for future builds:

```bash
npm run build
npm run test
npm run widget:typecheck
npm run tauri:build
```

The native workspace flow treats archived workspaces as retained history. They remain available through the Archive filter and deep links, but menu-bar summaries, Task Center totals, and local automation checks exclude them from active attention signals.

## Widget Strategy

The macOS widget should not execute git or modify files. It should read a compact snapshot generated by the main app. The native SwiftUI shell now writes that snapshot to Application Support and mirrors it to `group.com.ks.nexus` when an App Group container is available.

Suggested snapshot:

```json
{
  "generatedAt": "2026-05-26T10:00:00",
  "activeWorkspace": "Sample Workspace",
  "activeWorkspaceFolder": "2026-01-01-sample-workspace",
  "workspaceCount": 1,
  "riskCount": 4,
  "dirtyServiceCount": 0,
  "missingWorktreeCount": 1,
  "topRisks": [],
  "deepLink": "nexus://workspace/2026-01-01-sample-workspace"
}
```

Widget click targets use the app URL scheme and native shell handler:

```text
nexus://workspace/<workspace-folder>
```

Codex launch uses:

```text
codex://
```
