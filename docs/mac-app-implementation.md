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
- Added confirmed worktree setup through Rust Core, FFI, and the Tauri preview UI, with audit logging and command-copy fallback in browser preview mode.
- Added Rust Core SQLite + FTS index rebuild/search support for workspace Markdown and SQL notes.
- Added Tauri commands for rebuilding and querying the local search index.
- Added a top-bar global search popover that uses the local index in the packaged app and workspace metadata fallback in browser preview mode.
- Added grouped search result sections and keyboard navigation to the Tauri preview search popover.
- Added native SwiftUI search state and a top-bar search popover that uses the Swift/Rust local-index bridge with workspace metadata fallback.
- Added native selected-result context previews and a reusable compact activity timeline for workspace details.
- Added native search scope controls for workspace, state, workflow, SQL, and document search modes.
- Added locally persisted pinned workspaces in the native SwiftUI shell, including card-level pin actions and a sidebar pinned section.
- Added a native Settings sheet from the sidebar with persisted local roots, save-and-reload, and reset-defaults actions.
- Added actionable native session rows for document follow-ups and confirmed worktree setup, including a local-write confirmation sheet and created/skipped/failed result summary.
- Added Rust Core and Swift/Rust bridge support for append-only agent event JSONL, plus a native sidebar feed for recent agent events.
- Added native agent event detail inspection with metadata and JSON copy support.
- Added safe native agent event actions for selecting matching workspaces, opening local paths and links, and copying Codex continuation context.
- Added a fail-open hook helper script that local agents can call to append events into Nexus before a local socket server is available.
- Added an explicit local-write confirmation checkbox to the Tauri create-workspace flow.
- Added frontend desktop bridge in `src/desktop.ts`.
- Switched the frontend bridge to the official `@tauri-apps/api/core` dynamic invoke API.
- Added UI actions to open Codex from the workbench.
- Added "copy instruction and open Codex" flow for a workspace.
- Added native workspace creation based on the `ks-project-demand-workspace` standard layout.
- Added native source repository scanning for service selection.
- Added native environment health checks for configured paths and Git availability.
- Added first-run onboarding for local path setup.
- Added service picker to the workspace creation flow.
- Added workspace bootstrap report and reviewable worktree command script generation.
- Added delivery record placeholder detection as a workspace risk signal.
- Added in-app Markdown document preview for workspace documents.
- Moved Settings to the lower-left app rail and kept it focused on local path customization for sharing.
- Added widget snapshot generation through the native `write_widget_snapshot` command.
- Added `nexus://workspace/<workspace-folder>` URL scheme registration.
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
5. Expand native search scopes into reusable saved filters and add more audited event types for generated commands, validation runs, PR handoff, and future task automation.
6. Package the WidgetKit extension with a full Xcode target and App Group storage.
7. Add signing, notarization, update channels, and menu bar status after the native shell is ready.

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

## Widget Strategy

The macOS widget should not execute git or modify files. It should read a compact snapshot generated by the main app.

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

Widget click targets use the app URL scheme:

```text
nexus://workspace/<workspace-folder>
```

Codex launch uses:

```text
codex://
```
