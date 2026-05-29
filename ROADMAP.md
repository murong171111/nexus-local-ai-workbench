# Roadmap

This roadmap describes the next product and engineering steps for Nexus. The current Tauri app remains the preview app, but future roadmap work should move toward the native architecture documented in `docs/adr/0001-native-swiftui-rust-core.md`, `docs/native-architecture.md`, and the product shape in `docs/product-shape.zh-CN.md`.

## Architecture Direction

- Mac-first product experience: SwiftUI + AppKit.
- Portable local engine: Rust Core.
- Local searchable state: SQLite + FTS, rebuildable from workspace Markdown files.
- Apple ecosystem surfaces: WidgetKit first, iPad/iPhone companion views later.
- Current Tauri implementation: keep as working preview until the native Mac shell reaches core workflow parity.

## 0.1.x: Public Preview Hardening

- Add automated CI validation for pull requests and pushes to `main`.
- Add automated release builds for Apple Silicon and Intel macOS.
- Keep sample workspace data free of private local paths.
- Improve error messages for missing directories, invalid paths, and git failures.
- Add unit coverage for workspace parsing, creation defaults, widget snapshots, and git status mapping.
- Split the large Rust command layer by extracting reusable logic into `nexus-core`.

## 0.2.x: Native Foundation

- Extract workspace, git, document, risk, settings, and widget snapshot logic into a standalone Rust Core crate.
- Keep Tauri commands as thin wrappers around Rust Core during the transition.
- Define stable Swift/Rust DTO contracts for dashboard data, workspace documents, settings profiles, and audit events. `[started for dashboard/source scans, documents, widgets, workspace creation, and audit events]`
- Add a SwiftUI/AppKit Mac shell that can render sample workspace data. `[started]`
- Add native settings and path configuration in the SwiftUI shell. `[started with persisted paths, path status rows, directory pickers, team profile import/export, and environment checks]`
- Decide and document the Swift/Rust bridge mechanism. `[started with C ABI + JSON]`

## 0.3.x: Native Workspace Operations

- Make the SwiftUI shell read real workspace data from Rust Core. `[started with optional dynamic bridge]`
- Add native Markdown document rendering in the SwiftUI shell. `[started with document bridge, preview/source modes, workspace Documents Hub, active-document highlighting, and local document error recovery]`
- Add safer worktree creation from selected source repositories. `[started in Rust Core, FFI, Tauri preview UI, and native SwiftUI with explicit confirmation, preflight review, refreshed state, Chinese-first result guidance, result-aware Codex handoff, in-card local-check feedback, and follow-up actions]`
- Add branch alignment checks across services. `[done in 0.1.x preview]`
- Add workspace health checks before a development session starts. `[started in Rust Core, Tauri preview UI, and native SwiftUI shell]`
- Add a session startup flow that converts readiness results into prioritized Codex/worktree/document actions. `[started in Rust Core, Tauri preview UI, and native SwiftUI shell]`
- Add visible Codex handoff feedback for copied workspace, lifecycle, risk, task, automation, and agent-event context. `[started in native SwiftUI shell with richer workspace handoff packs]`
- Add workspace lifecycle stages that guide each demand from scoping through setup, development, delivery, done, blocked, and archived states. `[started in Rust Core and native SwiftUI shell]`
- Add confirmed lifecycle status writebacks for entering development, delivery, done, blocked, and archived states. `[started in Rust Core, Swift/Rust bridge, and native SwiftUI shell with local-write feedback and affected-workspace focus]`
- Add a native workflow summary for task and delivery status in the workspace detail. `[started in native SwiftUI shell with delivery focus guidance, task writeback feedback, delivery-readiness checks, and lifecycle writeback recommendations]`
- Add a native risk review summary for active risks, readiness blockers, local checks, worktree follow-up, and Codex risk handoff. `[started in native SwiftUI shell with local-check receipts]`
- Add a workspace detail Command Center so the native shell has one primary path before deeper Workflow, Risk Review, Documents, and Activity sections. `[started in native SwiftUI shell with detail status overview, primary-path guidance, a compact session path for scope, worktree, risk, tasks, delivery, Codex sessions, and handoff, plus local-check receipts]`
- Add actionable empty states and recovery feedback for first-run setup, empty filters, missing workspace selection, and local operation errors. `[started in native SwiftUI shell]`
- Add archived workspace filtering and keep archived contexts out of active risk/task/worktree attention signals. `[started in Rust Core, Tauri preview UI, and native SwiftUI shell]`
- Add explicit confirmation flows for local write operations. `[started for native workspace creation with source-repo service selection, filtering, pending scope, preflight review, confirmation summary, initialization receipt, and post-create next steps]`
- Add local audit logs for workspace creation and file writes. `[started for workspace creation, settings profile export, confirmed worktree setup, document opens, Codex handoffs, copied prompts, and dashboard activity timelines]`

## 0.4.x: Search And Local Index

- Add SQLite local index for workspace metadata and Markdown documents. `[started in Rust Core]`
- Add full-text search across tasks, decisions, delivery records, SQL notes, and service scopes. `[started in Rust Core, bridge, Tauri preview UI, and native SwiftUI shell]`
- Add search result grouping and keyboard navigation in the Mac UI. `[started in Tauri preview UI and native SwiftUI shell]`
- Add timeline view for workspace activity. `[started in native SwiftUI shell]`
- Add saved filters and pinned workspaces. `[started in native SwiftUI shell with persisted search scope and pinned workspace preferences]`

## 0.5.x: Widget And Automation

- Package the WidgetKit extension in a full Xcode target attached to the native Mac app. `[core snapshot computation and native snapshot writing started]`
- Add App Group storage for widget snapshots. `[started in native SwiftUI shell with Application Support fallback]`
- Add menu bar quick status. `[started in native SwiftUI shell]`
- Add optional local automation hooks for refresh, risk scans, and delivery checks. `[started in Rust Core, Swift/Rust bridge, native menu bar, schedule settings, notification preferences, action center, and audit log]`

## 0.6.x: Distribution Readiness

- Configure Apple Developer signing and notarization.
- Publish both `aarch64` and `x86_64` DMG assets, or ship a Universal Binary.
- Add native updater support backed by signed GitHub Releases.
- Add release notes automation using `CHANGELOG.md`.
- Expand first-run onboarding with team profile import and optional demo workspace creation. `[started in Tauri preview UI]`
- Add settings export/import for team sharing. `[done in 0.1.x preview; started in native SwiftUI shell]`

## 0.7.x: Agent Interaction Bridge

- Add a Nexus hook helper CLI that can receive Codex, Claude Code, OpenCode, and compatible agent lifecycle events. `[started with fail-open JSONL helper script]`
- Add a local bridge server, preferably Unix socket first, so hook helpers can stream session, prompt, permission, question, and tool-use events into the native Mac app without cloud services. `[event JSONL store, FFI bridge, and native sidebar feed started]`
- Add in-app reply and approval surfaces for agents that support structured hook responses, while degrading to copy-and-open handoff for agents that only expose one-way lifecycle events.
- Add deep links back to the exact Codex thread, terminal pane, IDE workspace, or Nexus workspace when the event contains enough metadata.
- Add workspace-level Codex session deep-link binding so a requirement can keep multiple return links to active Codex conversations. `[started in native SwiftUI shell with workspace-local codex-sessions.json bindings]`
- Add native workspace handoff actions for local Finder, Terminal, and configured Codex URL launches. `[started in native SwiftUI shell]`
- Keep hooks fail-open: if Nexus is not running, the agent should continue normally without blocking local development.
- Treat command approval, file mutation, worktree operations, and permission changes as explicit user decisions with visible audit records.

## Later

- Team profile templates for shared workspace conventions.
- Multi-root workspace groups.
- Plugin surface for non-Codex agents and alternate IDEs.
- Signed installer and update channels for stable, beta, and nightly builds.
