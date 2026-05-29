# Nexus

[简体中文](README.zh-CN.md)

Nexus is a local macOS AI development workbench for managing requirement workspaces, git worktrees, service scope, risk signals, delivery records, and Codex-oriented workflows.

It is designed for teams that work across multiple local service repositories and want a durable, document-first workflow around each requirement.

## Features

- Native macOS app built with Tauri, React, TailwindCSS, and Swift WidgetKit source.
- Workspace cards for requirement folders, branches, services, risks, activity, and worktree state.
- In-app workspace creation using the `ks-project-demand-workspace` layout, with scanned service selection, manual fallback, a preflight review, a confirmation summary, and guided next steps after creation.
- In-app Markdown document preview for status, service scope, branch notes, tasks, and delivery records.
- Local path settings for workspaces, source repositories, and delivery document roots.
- Exportable and importable team settings profiles for sharing local path conventions, Codex URL, and IDE URL templates, including first-run onboarding import and native Settings import/export.
- Native Settings local path rows with environment status, directory pickers, reveal actions, and checks for configured paths, Git availability, workspace counts, and source repository counts.
- Native SwiftUI primary actions use concise Chinese-first labels with hover help for path recovery and task workflows.
- Local audit log for confirmed workspace creation and settings profile exports.
- Local SQLite + FTS index foundation for workspace Markdown, service scope, tasks, decisions, delivery records, and SQL notes.
- Native SwiftUI Markdown document preview with preview/source modes, active-document highlighting, and local loading/error recovery for workspace handoff documents, standard workspace docs, and search result documents.
- Native workspace handoff actions for opening the active workspace in Finder, IDE, Terminal, or Codex, with Codex copying a handoff pack that includes local-check, service/worktree, task, delivery, and recommended-action context. The IDE action uses the Settings URL template and defaults to IntelliJ IDEA.
- Native workspace detail can bind, view, open, copy, and delete multiple Codex session deep links stored in workspace-local `codex-sessions.json`, with suggested bindings from matching recent Agent Events when Codex deep-link metadata is available.
- Native SwiftUI Task Center that surfaces open workspace tasks from `tasks.md`, including direct task-document opens, persisted filters, latest task writeback feedback, agent-sourced task writebacks, confirmed complete/defer actions, and task-level Codex copy-and-open handoff.
- Native SwiftUI menu bar status for quick workspace, risk, task, worktree, refresh, settings, and copy-summary actions.
- Local automation checks for refresh, risk, delivery, task, worktree, and dirty-service signals, exposed through Rust Core, the Swift/Rust bridge, the native menu bar, optional scheduled checks, visible local-check receipts, and configurable macOS notifications.
- Native SwiftUI Automation Action Center that turns local check signals into risk focus, delivery document opens, task focus, worktree review, and Codex handoff prompts.
- Workspace lifecycle stages derived from local workspace evidence, with native progress, next-action, document-open, worktree setup, and Codex handoff controls.
- Confirmed lifecycle writeback from the native shell into `workspace.md` and `STATUS.md`, with local audit events for status transitions.
- Native local-write feedback after task and lifecycle updates, with affected-workspace focus, source-document review, and follow-up local checks.
- Global search popover for indexed workspace documents, SQL notes, and browser-preview metadata fallback, with grouped results and keyboard navigation.
- First-run onboarding for importing team profiles, configuring local paths, scanning source repositories, and optionally creating a demo workspace.
- Environment health checks for configured directories and Git availability.
- Native workspace scanning from the configured paths; no local Python script is required for the packaged app.
- Native create-workspace flow that scans source repositories, filters service candidates, selects real local services, leaves service scope pending when needed, checks root/folder/destination/environment/scope readiness before writing, then focuses the new workspace with an initialization receipt, handoff, worktree, Codex, and check actions.
- Native worktree setup includes a preflight review for target branch readiness, missing worktrees, source repositories, and workspace-local write locations, then refreshes the workspace state after running and routes the next step to Finder, result-aware Codex handoff, or local checks.
- Native workspace Command Center that puts lifecycle progress, a primary-path recommendation, a compact scope -> worktree -> risk -> task -> delivery -> Codex sessions -> handoff session path, Codex continuation, local-check results, Finder, IDE, Terminal, and workspace-link copy at the top of each detail view, with quick actions grouped into handoff, execution, and local tool lanes.
- Native workspace detail overview that keeps lifecycle, branch, services, risk, tasks, delivery, Codex session count, and latest local-check state visible before deeper workflow sections.
- Native Codex handoff feedback that confirms when workspace, lifecycle, risk, task, automation, or agent-event context has been copied and explains the next paste step.
- Native inspector operation feedback for local errors, with dismiss, copy-error, refresh, environment-check, and Settings recovery actions.
- Native empty states for first-run or filtered-out workspace lists, showing configured paths, environment health, and direct Settings, New Workspace, Refresh, and Environment Check actions.
- Native workflow summary in workspace detail for open tasks, blocked tasks, delivery status, a delivery focus card, delivery-readiness checks, lifecycle writeback recommendations, task documents, delivery records, local checks, workspace Codex handoff, and delivery-update Codex handoff, with Chinese-first primary action labels.
- Native risk review in workspace detail for active risks, blocker/warning readiness checks, status documents, worktree setup, local re-check receipts, and copyable Codex risk-review prompts.
- Native workspace Documents Hub for opening and previewing the standard workspace files without leaving the detail view, including retry, copy-path, Finder recovery, and confirmed creation of missing standard documents when a file is absent.
- Branch alignment checks that flag worktrees whose actual branch does not match the workspace target branch.
- Workspace bootstrap reports and reviewable `scripts/worktree-commands.sh` files for semi-automated worktree setup.
- Delivery-record completeness warnings when `交付记录.md` still needs real change notes.
- SQL artifact readiness checks: if `交付记录.md` declares an actual SQL change, `sql/` must include both a formal SQL file and a rollback SQL file before delivery is considered ready.
- Codex launcher and copyable prompts for continuing a workspace, checking git state, updating delivery notes, and risk analysis.
- Widget snapshot generation at `~/Library/Application Support/com.ks.nexus/widget-snapshot.json`, with App Group mirroring when `group.com.ks.nexus` is available.
- `nexus://workspace/<workspace-folder>` deep links from widgets or other tools focus the target workspace in the native shell, and the Command Center can copy the current workspace link with visible inspector feedback.

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

If no workspace appears, the native workspace list shows a setup state with the configured workspace/source/docs paths, the latest environment-health result, and direct actions for Settings, New Workspace, Refresh, and Environment Check. If a search or filter hides every workspace, use `Show all` from that empty state to clear the filter and search query.

To share Nexus setup with another teammate, open `Settings` and export a `nexus-settings-profile-*.json`. The generated JSON contains only path conventions, the Codex URL scheme, the IDE URL template, and refresh interval. Teammates can import the profile from first-run onboarding or native Settings, then adjust paths for their own machine if needed.

After importing a profile, use the native Settings path rows to choose local directories, reveal existing folders, and run `Environment Check` to confirm the configured directories exist, are writable, Git is available, and source repositories are detected. `Tool Links` configures the Codex URL and the IDE URL template. Use `{path}` for the URL-encoded workspace path; the default is `idea://open?file={path}`. Editing a path clears the previous health result so stale checks are not reused.

From a workspace detail view, use `Finder`, `IDE`, `Terminal`, or `Codex` to hand the current workspace to local tools. The IDE action opens the workspace through the configured URL template. The Codex action copies a workspace-specific handoff pack and opens the configured Codex URL from Settings. The handoff pack includes the latest local-check receipt, service/worktree summaries, open tasks, delivery checks, standard document paths, and Nexus recommended actions.

The `Codex Sessions` area in workspace detail can bind multiple Codex deep links for the same requirement. Bindings are stored in the workspace-local `codex-sessions.json`; deleting a binding only removes the local Nexus record and does not delete the Codex conversation.

After any Codex handoff or context copy, the native inspector shows a dismissible `Handoff` panel with the copied context type, timestamp, and a reminder that the prompt is on the clipboard.

When a local operation fails, such as an invalid path, invalid Codex URL, invalid IDE URL template, document-read failure, Terminal launch failure, or worktree setup error, the native inspector shows an `Operation` feedback card. It keeps the error visible and offers copy-error, refresh, environment-check, and Settings actions without moving the user out of the current workspace flow.

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
  codex-sessions.json
  bootstrap-report.md
  logs/
  sql/
  repos/
  scripts/
```

The `repos/<service>` directories are intended to be git worktrees for isolated multi-branch development.

## Creating Workspaces

Use the `New Workspace` action in the left rail. Nexus can scan the configured source repository root, filter the detected repositories, and let you select services from that local list. You can still type service names manually when a repository is not present yet, or leave service scope pending during early scoping. Manual service input supports commas, spaces, new lines, semicolons, and Chinese separators such as `、` and `，`.

Before writing files, Nexus shows a summary of the target path, branch, and service scope. The preflight review blocks obvious failures such as an empty workspaces root, a root path that is not a directory, an invalid folder name, or a destination that already exists. Pending service scope, pending target branch, missing environment checks, and selected services that are not in the latest source-repository scan are shown as review items so early scoping can still be documented. Creating a workspace requires confirming the local write, then writes the standard Markdown document set and records selected services in `services.md` and `branches.md`. It also generates `bootstrap-report.md`, `scripts/worktree-commands.sh`, a local audit event, and an initialization receipt that verifies the generated files, initial `STATUS.md`, service scope, target branch, and worktree readiness.

After creation, Nexus selects the new workspace, clears stale document previews, and shows a short next-step panel with the initialization receipt, opening `handoff.md`, creating confirmed worktrees when the branch and services are ready, handing off to Codex, or running the local check.

Nexus does not automatically create worktrees during workspace creation. When the branch and service scope are confirmed, use the native worktree setup action to run a confirmed local `git fetch` and `git worktree add` flow. Before the action is enabled, Nexus shows a preflight review for target branch readiness, missing worktrees, source repositories, and the workspace-local `repos/<service>` write location. After it runs, Nexus refreshes the workspace state, shows Chinese-first created/skipped/failed service results, and offers Finder, result-aware Codex handoff, and local-check follow-ups. Running the follow-up check from the result card shows the local check summary in place.

## Local Audit Log

Nexus writes JSONL audit events to `~/Library/Application Support/com.ks.nexus/audit/audit-log.jsonl` for user-visible local writes such as workspace creation and settings profile import/export. High-frequency cache writes, such as widget snapshot refreshes, are not audited.

The native menu bar can run a local automation check manually or on a persisted schedule while Nexus is running. That check scans workspace Markdown and git state for refresh, risk, delivery, task, worktree, and dirty-service signals, then appends an `automation.check.completed` audit event when the Rust Core bridge is available. Optional macOS notifications are off by default, support cooldown and signal preferences, and only fire when a check result matches the selected minimum status.

The native right inspector also includes an Automation Action Center. After a check runs, Nexus converts risk, delivery, task, and worktree signals into clickable actions such as focusing a risky workspace, opening delivery notes, selecting the Task Center, presenting the worktree setup confirmation, or copying a Codex prompt with the current local paths and workspace context.

Each workspace detail view starts with a compact overview for lifecycle, branch, services, risk, tasks, delivery, Codex session count, and the latest local check. The `Command Center` then summarizes lifecycle progress, branch readiness, service/worktree status, risk level, open tasks, and saved Codex sessions, and shows a single primary path with the reason behind the next best action. When saved Codex sessions exist, the clean primary path can resume the latest session; otherwise the same area still routes to binding a session or copying a fresh handoff pack. A compact session path keeps scope, worktree, risk, tasks, delivery, Codex sessions, and Codex handoff visible as one sequence. Quick actions are grouped as `Handoff`, `Execute`, and `Local` so Codex continuation, checks/lifecycle actions, and Finder/IDE/Terminal/workspace-link copy stay separate. After a local check runs, the Command Center keeps a compact receipt with status, risk/delivery/task/worktree metrics, audit feedback, and a copyable summary for Codex handoff.

Each workspace detail view includes a `Workflow` section that keeps task and delivery state together. It starts with a delivery focus card that chooses one next action from branch confirmation, service scope, worktree setup, blocked/open tasks, risks, delivery records, SQL notes, dirty services, lifecycle delivery, and done confirmation. It also summarizes open and blocked tasks, shows whether the delivery record is ready or needs review, checks branch confirmation, service worktrees, task closure, risks, SQL readiness, dirty services, and delivery-record status before handoff, opens `tasks.md` and `交付记录.md`, runs the local check, hands the whole workspace to Codex, or copies a delivery-update Codex handoff. SQL readiness is evidence-based: a delivery record that declares a real SQL change must be backed by both formal and rollback `.sql` files under `sql/`. The delivery handoff includes delivery-record path, tasks, SQL checks, risks, services/worktrees, and the latest local-check context so the agent can update the record from evidence instead of a blank document.

When a task status writeback updates `tasks.md`, the native Task Center keeps a compact recent-writeback card with affected-workspace focus and source-document actions, even if the task list changes after the refresh.

Each workspace detail view also includes a `Risk review` section. It consolidates active risk signals and non-delivery readiness checks into risk, blocker, and warning counts, then routes the next step to a fresh local check, `STATUS.md`, confirmed worktree setup when services are missing, or a copied Codex risk-review prompt. The latest check receipt stays visible inside Risk Review so the user can confirm whether a re-check actually changed the risk surface.

The workspace detail view also includes a `Documents` hub for the standard workspace files: `workspace.md`, `STATUS.md`, `services.md`, `branches.md`, `tasks.md`, `交付记录.md`, `handoff.md`, `bootstrap-report.md`, and `scripts/worktree-commands.sh`. Selecting a document highlights the active entry, opens it in the native preview/source viewer, and shows retry, copy-path, and Finder recovery if the file is missing or unreadable. When a standard file is missing, Nexus can create a safe skeleton only after confirmation, then refresh the workspace, open the new document, and show local-write feedback.

Archived workspaces remain visible in the workspace list and Archive filter, but they are excluded from active menu-bar counts, Task Center totals, and automation attention signals.

## Workspace Lifecycle

Rust Core derives a lifecycle stage for every workspace from the current Markdown, task, risk, service, branch, delivery, and git worktree state. The native shell shows that lifecycle on each workspace card and in the detail inspector with progress, current reason, next action, and Codex handoff controls.

The current stages are `scoping`, `setup`, `developing`, `delivery`, `done`, `blocked`, and `archived`. Nexus does not overwrite lifecycle files automatically; it reads local evidence and guides the next safe action.

When the Rust Core bridge is available, lifecycle transitions such as `developing`, `delivery`, `done`, `blocked`, and `archived` can be written back after explicit confirmation. The write updates `workspace.md` and `STATUS.md`, then appends a `workspace_lifecycle.updated` audit event. It does not move folders, delete worktrees, change git branches, or mark tasks complete.

After task-status or lifecycle writebacks, the native inspector shows a local-write feedback card with the changed status, refresh confirmation, affected-workspace focus, a source-document action, and a follow-up local-check action. Source-document and check actions also focus the affected workspace first, so review stays on the refreshed context.

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

The main app already writes the widget snapshot and registers the `nexus://` URL scheme. The native shell writes the same snapshot to Application Support, handles `nexus://workspace/<folder>` focus links, and mirrors the snapshot into `group.com.ks.nexus` once the app is packaged with App Group entitlements. The WidgetKit source lives in:

```text
widget/NexusWidget/NexusWidget.swift
```

Building and shipping the actual `.appex` requires a full Xcode project with a Widget Extension target, App Group configuration, signing, and notarization. See [widget/README.md](widget/README.md).

## Documentation

- [Product shape](docs/product-shape.zh-CN.md)
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
