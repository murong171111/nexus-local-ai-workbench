# Roadmap

This roadmap describes the next product and engineering steps for Nexus. The product direction has moved to Swift Native-only for new feature work. See `docs/native-swift-only-roadmap.md` and `docs/main-workflow.md` for the current roadmap and M1 workflow contract.

React, Tauri, Rust, and TypeScript are now legacy/reference surfaces for new product workflow work. They may receive critical maintenance, public-data safety fixes, and migration support, but new workflow features should be implemented in Swift/SwiftUI/AppKit/WidgetKit.

For the current main-workflow convergence audit, see `docs/main-workflow-audit.zh-CN.md`. It narrows the near-term product goal to the requirement lifecycle path: create workspace -> demand intake -> scope freeze -> service/branch confirmation -> worktree setup -> development tasks -> delivery check -> archive.

## Architecture Direction

- Mac-first product experience: SwiftUI + AppKit as the primary implementation surface.
- Native Apple-platform local logic for new workflow rules, using Swift/Foundation/AppKit APIs.
- Local searchable state: SQLite + FTS, rebuildable from workspace Markdown files.
- Apple ecosystem surfaces: WidgetKit first, iPad/iPhone companion views later.
- Current Tauri/React/Rust implementation: keep as frozen legacy/reference until the native Mac shell reaches core workflow parity and deletion conditions are met.

## 0.1.x: Public Preview Hardening

- Add automated CI validation for pull requests and pushes to `main`. `[done with GitHub Actions for environment diagnostics, Node, Rust, Swift widget/native, Tauri checks, and public-data privacy checks]`
- Add automated release builds for Apple Silicon and Intel macOS. `[started with tag/workflow_dispatch DMG builds for aarch64 and x86_64]`
- Keep sample workspace data free of private local paths. `[done with publishable text scan in npm run privacy:check for app/web/native metadata assets, generated build-output exclusions, private keys, GitHub token shapes, and secret-like assignments, plus dashboard sample shape checks in npm run sample:check]`
- Improve error messages for missing directories, invalid paths, and git failures. `[started with native operation feedback, create/worktree preflight copy, settings profile import recovery context, browser-preview operation recovery messages, and local dev-tool diagnostics]`
- Add unit coverage for workspace parsing, creation defaults, widget snapshots, and git status mapping. `[started with JS coverage for workspace parsing, creation defaults, widget snapshots, search grouping, settings profiles, worktree status signal mapping, agent hooks, Swift native model behavior, and Rust Core git/workspace tests]`
- Split the large Rust command layer by extracting reusable logic into `nexus-core`. `[started with workspace, git, documents, search, automation, settings, worktree setup, audit, agent events, tasks, lifecycle, widget snapshots, and demand intake status/initialization]`

## 0.2.x: Native Foundation

- Extract workspace, git, document, risk, settings, demand intake, and widget snapshot logic into a standalone Rust Core crate.
- Keep Tauri commands as thin wrappers around Rust Core during the transition. `[started for workspace creation, source/workspace scans, documents, search, settings, widget snapshots, audit, worktree setup, task/lifecycle writebacks, agent events, automation checks, and demand intake]`
- Define stable Swift/Rust DTO contracts for dashboard data, workspace documents, settings profiles, audit events, and demand intake. `[started for dashboard/source scans, documents, widgets, workspace creation, audit events, and demand intake status/initialization]`
- Add a SwiftUI/AppKit Mac shell that can render sample workspace data. `[started]`
- Add native settings and path configuration in the SwiftUI shell. `[started with persisted paths, path status rows, directory pickers, team profile import/export, and environment checks]`
- Decide and document the Swift/Rust bridge mechanism. `[started with C ABI + JSON]`

## 0.3.x: Native Workspace Operations

- Make the SwiftUI shell read real workspace data from Rust Core. `[started with optional dynamic bridge]`
- Add native Markdown document rendering in the SwiftUI shell. `[started with document bridge, preview/source modes, workspace Documents Hub, scanned SQL artifact entries, active-document highlighting, local document error recovery, and confirmed missing-standard-document creation]`
- Add native demand-intake preflight for workspace-local requirement confirmation before development. `[started with Swift/Rust bridge status refresh, confirmed no-overwrite initialization, per-file readiness, document open actions, local write feedback, $lanhu-demand-intake Codex prompt copy/open handoff, and Rust Core readiness/session-action routing into the native primary path]`
- Add safer worktree creation from selected source repositories. `[started in Rust Core, FFI, Tauri preview UI, and native SwiftUI with explicit confirmation, preflight review, refreshed state, Chinese-first result guidance, result-aware Codex handoff, in-card local-check feedback, and follow-up actions]`
- Add branch alignment checks across services. `[done in 0.1.x preview]`
- Add workspace health checks before a development session starts. `[started in Rust Core, Tauri preview UI, and native SwiftUI shell with demand-intake, active-task, SQL, branch, service, worktree, delivery, and document readiness rows]`
- Add a session startup flow that converts readiness results into prioritized Codex/worktree/document actions. `[started in Rust Core, Tauri preview UI, and native SwiftUI shell with demand-intake preflight, active-task health signals, plus a Command Center-adjacent next-step queue]`
- Add visible clipboard and Codex handoff feedback for copied workspace, lifecycle, risk, task, automation, agent-event, session-link, and task-locator context. `[started in native SwiftUI shell with richer workspace handoff packs, context-aware feedback copy, automation prompts that target relevant delivery/SQL/task/branch/dirty-service workspaces, and Agent Event copy/open Codex actions]`
- Add workspace lifecycle stages that guide each demand from scoping through setup, development, delivery, done, blocked, and archived states. `[started in Rust Core and native SwiftUI shell]`
- Add confirmed lifecycle status writebacks for entering development, delivery, done, blocked, and archived states. `[started in Rust Core, Swift/Rust bridge, and native SwiftUI shell with local-write feedback and affected-workspace focus]`
- Add a native workflow summary for task and delivery status in the workspace detail. `[started in native SwiftUI shell with shared task/delivery workflow summary surfaced in Command Center, service-level operations for worktree/source/IDE/Codex handoff, delivery focus guidance, grouped workflow action lanes, actionable and attention-grouped delivery-readiness rows, SQL artifact review/handoff routing, delivery-update Codex handoff, validation/PR handoff, task source-line locators, task writeback feedback, inline local-check receipts, full-document and SQL-section metadata artifact enforcement for formal/rollback files, workspace-template SQL artifact guardrails, and lifecycle writeback recommendations]`
- Add a native risk review summary for active risks, readiness blockers, local checks, worktree follow-up, and Codex risk handoff. `[started in native SwiftUI shell with local-check receipts and actionable readiness rows]`
- Add a workspace detail Command Center so the native shell has one primary path before deeper Workflow, Risk Review, Documents, and Activity sections. `[started in native SwiftUI shell with a compact detail map for section jumps, actionable detail overview tiles, primary-path guidance, a compact workflow path for scope, demand preflight, worktree, risk, tasks, SQL, delivery, Codex sessions, and handoff, Chinese-first status/action labels, delivery status routing to local check/delivery handoff/validation PR handoff/document review, grouped Handoff/Next/Local quick actions, workspace link copy, plus local-check receipts]`
- Add actionable empty states and recovery feedback for first-run setup, empty filters, missing workspace selection, and local operation errors. `[started in native SwiftUI shell with team-profile -> environment-check -> workspace-create setup guidance, sidebar setup readiness, shared setup action groups, and sidebar reset recovery for hidden workspace lists]`
- Add archived workspace filtering and keep archived contexts out of active risk/task/worktree attention signals. `[started in Rust Core, shared preview/widget model, Tauri preview UI, and native SwiftUI shell]`
- Add explicit confirmation flows for local write operations. `[started for native workspace creation with source-repo service selection, filtering, pending scope, shared preflight model, confirmation summary, initialization receipt, and post-create next steps]`
- Add local audit logs for workspace creation and file writes. `[started for workspace creation, settings profile export, confirmed worktree setup, document opens, Codex handoffs, copied prompts, agent task writeback feedback, and dashboard activity timelines]`

## 0.4.x: Search And Local Index

- Add SQLite local index for workspace metadata and Markdown documents. `[started in Rust Core]`
- Add full-text search across tasks, decisions, delivery records, SQL notes, and service scopes. `[started in Rust Core, bridge, Tauri preview UI, and native SwiftUI shell]`
- Add search result grouping and keyboard navigation in the Mac UI. `[started in Tauri preview UI and native SwiftUI shell with stable group ordering and ranked browser-preview fallback results]`
- Add timeline view for workspace activity. `[started in native SwiftUI shell]`
- Add saved filters and pinned workspaces. `[started in native SwiftUI shell with persisted workspace filters, persisted search scope, persisted task filters, live workspace filter counts, and pinned workspace preferences, plus browser-preview workspace pins backed by localStorage, shared attention sorting, and reusable browser-preview filter matching]`

## 0.5.x: Widget And Automation

- Package the WidgetKit extension in a full Xcode target attached to the native Mac app. `[core snapshot computation and native snapshot writing started]`
- Add App Group storage for widget snapshots. `[started in native SwiftUI shell with Application Support fallback]`
- Add menu bar quick status. `[started in native SwiftUI shell with worktree and dirty-service status copy]`
- Add optional local automation hooks for refresh, risk scans, and delivery checks. `[started in Rust Core, Swift/Rust bridge, native menu bar, schedule settings, notification preferences, action center, and audit log]`

## 0.6.x: Distribution Readiness

- Configure Apple Developer signing and notarization.
- Publish both `aarch64` and `x86_64` DMG assets, or ship a Universal Binary.
- Add native updater support backed by signed GitHub Releases.
- Add release notes automation using `CHANGELOG.md`.
- Expand first-run onboarding with team profile import and optional demo workspace creation. `[started in Tauri preview UI and native SwiftUI shell with a confirmed create-workspace demo template]`
- Add settings export/import for team sharing. `[done in 0.1.x preview; started in native SwiftUI shell]`

## 0.7.x: Agent Interaction Bridge

- Add a Nexus hook helper CLI that can receive Codex, Claude Code, OpenCode, and compatible agent lifecycle events. `[started with fail-open JSONL helper script]`
- Add a local bridge server, preferably Unix socket first, so hook helpers can stream session, prompt, permission, question, and tool-use events into the native Mac app without cloud services. `[event JSONL store, FFI bridge, and native Agent Inbox sidebar feed started with Attention/Recent grouping, empty state, an Agent Workflow bridge to Agent-sourced Task Center items, and task-draft writeback follow-up actions]`
- Add in-app reply and approval surfaces for agents that support structured hook responses, while degrading to copy-and-open handoff for agents that only expose one-way lifecycle events. `[started in native Agent Event detail with copyable approve/deny/answer/review response templates, inspector feedback, and local audit records while keeping command metadata review-only]`
- Add deep links back to the exact Codex thread, terminal pane, IDE workspace, or Nexus workspace when the event contains enough metadata. `[Nexus workspace deep-link focus and copy started in native SwiftUI shell]`
- Add workspace-level Codex session deep-link binding so a requirement can keep multiple return links to active Codex conversations. `[v1 landed in native SwiftUI shell with workspace detail bind, view, open, copy, delete, workspace-local codex-sessions.json storage, and Agent Event suggested bindings]`
- Add native workspace handoff actions for local Finder, IDE, Terminal, and configured Codex URL launches. `[started in native SwiftUI shell with configurable IDE URL templates]`
- Keep hooks fail-open: if Nexus is not running, the agent should continue normally without blocking local development.
- Treat command approval, file mutation, worktree operations, and permission changes as explicit user decisions with visible audit records.

## Later

- Team profile templates for shared workspace conventions.
- Multi-root workspace groups.
- Plugin surface for non-Codex agents and alternate IDEs.
- Signed installer and update channels for stable, beta, and nightly builds.
