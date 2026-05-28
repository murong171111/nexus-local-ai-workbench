# Nexus

[简体中文](README.zh-CN.md)

Nexus is a local macOS AI development workbench for managing requirement workspaces, git worktrees, service scope, risk signals, delivery records, and Codex-oriented workflows.

It is designed for teams that work across multiple local service repositories and want a durable, document-first workflow around each requirement.

## Features

- Native macOS app built with Tauri, React, TailwindCSS, and Swift WidgetKit source.
- Workspace cards for requirement folders, branches, services, risks, activity, and worktree state.
- In-app workspace creation using the `ks-project-demand-workspace` layout.
- In-app Markdown document preview for status, service scope, branch notes, tasks, and delivery records.
- Local path settings for workspaces, source repositories, and delivery document roots.
- Exportable and importable team settings profiles for sharing local path conventions, including first-run onboarding import and native Settings import/export.
- Local audit log for confirmed workspace creation and settings profile exports.
- Local SQLite + FTS index foundation for workspace Markdown, service scope, tasks, decisions, delivery records, and SQL notes.
- Native SwiftUI Markdown document preview with preview/source modes for workspace handoff documents and search result documents.
- Native SwiftUI Task Center that surfaces open workspace tasks from `tasks.md`, including persisted filters, agent-sourced task writebacks, confirmed complete/defer actions, and task-level Codex handoff prompts.
- Native SwiftUI menu bar status for quick workspace, risk, task, worktree, refresh, settings, and copy-summary actions.
- Local automation checks for refresh, risk, delivery, task, worktree, and dirty-service signals, exposed through Rust Core, the Swift/Rust bridge, the native menu bar, optional scheduled checks, and configurable macOS notifications.
- Native SwiftUI Automation Action Center that turns local check signals into risk focus, delivery document opens, task focus, worktree review, and Codex handoff prompts.
- Workspace lifecycle stages derived from local workspace evidence, with native progress, next-action, document-open, worktree setup, and Codex handoff controls.
- Confirmed lifecycle writeback from the native shell into `workspace.md` and `STATUS.md`, with local audit events for status transitions.
- Global search popover for indexed workspace documents, SQL notes, and browser-preview metadata fallback, with grouped results and keyboard navigation.
- First-run onboarding for importing team profiles, configuring local paths, scanning source repositories, and optionally creating a demo workspace.
- Environment health checks for configured directories and Git availability.
- Native workspace scanning from the configured paths; no local Python script is required for the packaged app.
- Native source repository scanning so workspace creation can select services from real local repositories.
- Branch alignment checks that flag worktrees whose actual branch does not match the workspace target branch.
- Workspace bootstrap reports and reviewable `scripts/worktree-commands.sh` files for semi-automated worktree setup.
- Delivery-record completeness warnings when `交付记录.md` still needs real change notes.
- Codex launcher and copyable prompts for continuing a workspace, checking git state, updating delivery notes, and risk analysis.
- Widget snapshot generation at `~/Library/Application Support/com.ks.nexus/widget-snapshot.json`, with App Group mirroring when `group.com.ks.nexus` is available.
- `nexus://workspace/<workspace-folder>` URL scheme for deep links from widgets or other tools.

## Installation

Download the latest `Nexus_*.dmg` from GitHub Releases, open it, and drag `Nexus.app` into Applications.

On first launch:

1. Import a shared `nexus-settings-profile-*.json` if your team already has one, or set paths manually.
2. Set your local paths:
   - Workspaces root, for example `~/ks_project/workspaces`
   - Source repositories root, for example `~/ks_project/source-repos`
   - Delivery documents root, for example `~/ks_project/docs`
3. Click `Save`.
4. Click `Scan source repositories` to populate the service picker.
5. Optionally create the demo workspace from onboarding to inspect the standard Markdown structure.
6. Click the refresh button in the top bar.

To share Nexus setup with another teammate, open `Settings` and export a `nexus-settings-profile-*.json`. The generated JSON contains only path conventions, the Codex URL scheme, and refresh interval. Teammates can import the profile from first-run onboarding or native Settings, then adjust paths for their own machine if needed.

## Workspace Layout

Nexus expects each requirement workspace to contain Markdown files like:

```text
<workspace>/
  AGENTS.md
  workspace.md
  STATUS.md
  services.md
  branches.md
  plan.md
  tasks.md
  decisions.md
  handoff.md
  delivery.md
  交付记录.md
  bootstrap-report.md
  logs/
  sql/
  repos/
  scripts/
```

The `repos/<service>` directories are intended to be git worktrees for isolated multi-branch development.

## Creating Workspaces

Use the `New Workspace` action in the left rail. Nexus can scan the configured source repository root and lets you select services from that local list. You can still type service names manually when a repository is not present yet. Manual service input supports commas, spaces, new lines, semicolons, and Chinese separators such as `、` and `，`.

Creating a workspace requires confirming the local write, then writes the standard Markdown document set and records selected services in `services.md` and `branches.md`. It also generates `bootstrap-report.md`, `scripts/worktree-commands.sh`, and a local audit event.

Nexus does not automatically execute worktree commands. Review the generated script first, then run it manually when the branch and service scope are confirmed.

## Local Audit Log

Nexus writes JSONL audit events to `~/Library/Application Support/com.ks.nexus/audit/audit-log.jsonl` for user-visible local writes such as workspace creation and settings profile import/export. High-frequency cache writes, such as widget snapshot refreshes, are not audited.

The native menu bar can run a local automation check manually or on a persisted schedule while Nexus is running. That check scans workspace Markdown and git state for refresh, risk, delivery, task, worktree, and dirty-service signals, then appends an `automation.check.completed` audit event when the Rust Core bridge is available. Optional macOS notifications are off by default, support cooldown and signal preferences, and only fire when a check result matches the selected minimum status.

The native right inspector also includes an Automation Action Center. After a check runs, Nexus converts risk, delivery, task, and worktree signals into clickable actions such as focusing a risky workspace, opening delivery notes, selecting the Task Center, presenting the worktree setup confirmation, or copying a Codex prompt with the current local paths and workspace context.

Archived workspaces remain visible in the workspace list and Archive filter, but they are excluded from active menu-bar counts, Task Center totals, and automation attention signals.

## Workspace Lifecycle

Rust Core derives a lifecycle stage for every workspace from the current Markdown, task, risk, service, branch, delivery, and git worktree state. The native shell shows that lifecycle on each workspace card and in the detail inspector with progress, current reason, next action, and Codex handoff controls.

The current stages are `scoping`, `setup`, `developing`, `delivery`, `done`, `blocked`, and `archived`. Nexus does not overwrite lifecycle files automatically; it reads local evidence and guides the next safe action.

When the Rust Core bridge is available, lifecycle transitions such as `developing`, `delivery`, `done`, `blocked`, and `archived` can be written back after explicit confirmation. The write updates `workspace.md` and `STATUS.md`, then appends a `workspace_lifecycle.updated` audit event. It does not move folders, delete worktrees, change git branches, or mark tasks complete.

## Local Search Index

Nexus can rebuild a local SQLite + FTS index at `~/Library/Application Support/com.ks.nexus/nexus-index.sqlite3`. The index is a cache that can be rebuilt from human-readable workspace folders. The indexed sources are standard workspace Markdown files and `sql/` notes.

The top search field queries this local index in the packaged app. Results are grouped by workspace, state, workflow, and SQL content. Use arrow keys to move through results, Enter to open the selected item, and Escape to clear the search. In browser preview mode, the same popover falls back to workspace metadata so the search UI remains testable without Tauri.

## Local Development

Requirements:

- macOS 12+
- Node.js 22+
- Rust toolchain
- Xcode Command Line Tools for the Tauri app
- Full Xcode only if you want to compile the WidgetKit extension

Install dependencies:

```bash
npm install
```

Run the web dev server:

```bash
npm run dev
```

Run the Tauri app in development:

```bash
npm run tauri:dev
```

Build the app:

```bash
npm run tauri:build
```

Regenerate app icons:

```bash
npm run icon
```

Type-check the WidgetKit Swift source:

```bash
npm run widget:typecheck
```

Build the native SwiftUI Mac shell scaffold:

```bash
npm run native:build
```

Build the Rust Core bridge dynamic library:

```bash
npm run ffi:build
```

During native shell development, set `NEXUS_CORE_LIBRARY` to the built `libnexus_ffi.dylib` path to load real workspace data through Rust Core. Without that variable, the Swift shell uses preview fallback data.

Run the standard local verification set:

```bash
npm run verify
```

## Widget Status

The main app already writes the widget snapshot and registers the `nexus://` URL scheme. The native shell writes the same snapshot to Application Support and mirrors it into `group.com.ks.nexus` once the app is packaged with App Group entitlements. The WidgetKit source lives in:

```text
widget/NexusWidget/NexusWidget.swift
```

Building and shipping the actual `.appex` requires a full Xcode project with a Widget Extension target, App Group configuration, signing, and notarization. See [widget/README.md](widget/README.md).

## Documentation

- [Architecture](docs/architecture.md)
- [Native architecture target](docs/native-architecture.md)
- [Native migration plan](docs/plans/2026-05-27-native-mac-migration.md)
- [Distribution](docs/distribution.md)
- [Release process](docs/release-process.md)
- [Widget implementation](widget/README.md)
- [Mac app implementation notes](docs/mac-app-implementation.md)
- [Local automation hooks](docs/local-automation-hooks.md)
- [Roadmap](ROADMAP.md)
- [Changelog](CHANGELOG.md)
- [Contributing](CONTRIBUTING.md)
- [Security](SECURITY.md)

## License

MIT
