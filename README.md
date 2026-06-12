# Nexus

[简体中文](README.zh-CN.md)

Nexus is a local macOS AI development workbench for managing requirement workspaces, git worktrees, service scope, risk signals, delivery records, and Codex-oriented workflows.

It is designed for teams that work across multiple local service repositories and want a durable, document-first workflow around each requirement.

## Features

- Native macOS app built with Tauri, React, TailwindCSS, and Swift WidgetKit source.
- Workspace cards for requirement folders, branches, services, risks, activity, and worktree state.
- In-app workspace creation using the `ks-project-demand-workspace` layout, with scanned service selection, manual fallback, a preflight review, a confirmation summary, and guided next steps after creation.
- Workspace detail demand-intake panel for checking or initializing a fixed `需求/` folder with `requirement.md`, `questions.md`, `scope.md`, `tasks.md`, and `delivery.md`, plus a copyable `$lanhu-demand-intake` Codex prompt. The Native shell now reads those Markdown files for requirement content, unresolved P0 questions, scope status, and requirement task readiness, then uses a separate scope-freeze gate before transferring real requirement rows into root `tasks.md` after confirmation; Nexus still does not parse Lanhu or call AI.
- Native service/branch confirmation evidence checks `services.md`, `branches.md`, workspace service rows, source repository availability, and branch policy before worktree setup.
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
- The Tauri workspace detail drawer also reads and writes workspace-local `codex-sessions.json`, so the packaged app can bind, view, open, copy, and delete multiple Codex session links from the same details flow used for documents and tasks.
- Native SwiftUI Task Center that surfaces open workspace tasks from `tasks.md`, including task source-line locators, persisted filters, latest task writeback feedback, agent-sourced task writebacks with post-write focus/source actions, confirmed complete/defer actions, and task-level Codex copy-and-open handoff. Deferred tasks remain visible in the deferred filter without creating active automation or workflow blockers.
- Native/Rust local checks now surface active `doing`/`todo` tasks as an `active-tasks` health row and `continue-active-tasks` next-step action, keeping unfinished work routed back to `tasks.md` before delivery cleanup.
- Native SwiftUI workspace filters with persisted selection, live per-filter counts, disabled empty filter targets, and reset recovery from the sidebar or empty state.
- Native SwiftUI menu bar status for quick workspace, risk, task, worktree, dirty-service, refresh, settings, and copy-summary actions, with worktree attention reflected in the menu title and copied status.
- Local automation checks for refresh, risk, delivery, branch alignment, task, worktree, and dirty-service signals, exposed through Rust Core, the Swift/Rust bridge, the native menu bar, optional scheduled checks, visible local-check receipts, and configurable macOS notifications.
- Native SwiftUI Automation Action Center that turns local check signals into risk-review handoff, SQL-aware delivery handoff or delivery-document review, branch-document review, task focus, worktree setup review, dirty-service handoff, and Codex handoff prompts with the relevant task, delivery, risk, branch, worktree, or service workspace context.
- Workspace lifecycle stages derived from local workspace evidence, with native progress, next-action, document-open, worktree setup, and Codex handoff controls.
- Confirmed lifecycle writeback from the native shell into `workspace.md` and `STATUS.md`, with local audit events for status transitions.
- Native local-write feedback after task and lifecycle updates, with affected-workspace focus, source-document review, and follow-up local checks.
- Global search popover for indexed workspace documents, SQL notes, and browser-preview metadata fallback, with grouped results and keyboard navigation.
- Browser-preview workspace pins are persisted locally and keep important workspaces above the risk-score sort while leaving workspace Markdown unchanged.
- First-run onboarding for importing team profiles, configuring local paths, scanning source repositories, and optionally creating a demo workspace, with native empty-state setup guidance and a demo template inside the create-workspace sheet.
- Native sidebar setup readiness keeps Settings visible at the lower-left edge and labels installs as unchecked, ready, or needing review. When the environment check passes, Nexus says initialization is unnecessary and routes directly to refresh or first-workspace creation.
- Environment health checks for configured directories and Git availability.
- Native workspace scanning from the configured paths; no local Python script is required for the packaged app.
- Native create-workspace flow that scans source repositories, filters service candidates, selects real local services, leaves service scope pending when needed, offers a first-run demo template when no workspaces exist, checks root/folder/destination/environment/scope readiness before writing, then focuses the new workspace, opens the generated `handoff.md`, and shows an initialization receipt, handoff, worktree, Codex, and check actions.
- Native worktree setup includes a preflight review for target branch readiness, missing worktrees, source repositories, and workspace-local write locations, then refreshes the workspace state after running and routes the next step to Finder, result-aware Codex handoff, or local checks.
- Native workspace Command Center that puts lifecycle progress, a primary-path recommendation, task, SQL, and delivery status summaries, a compact scope -> worktree -> risk -> task -> SQL -> delivery -> Codex sessions -> handoff workflow path, Codex continuation, local-check results, Finder, IDE, Terminal, and workspace-link copy at the top of each detail view. Path cards show compact action labels, and the SQL and delivery cards route by status to local check, SQL artifact review, delivery handoff, validation/PR handoff, or document review, with Chinese-first status labels and quick actions grouped into handoff, next-step, and local tool lanes.
- Native workspace detail now includes a compact Detail map that keeps Overview, Command Center, Workflow, Services, Risk Review, Documents, and Activity as named jump targets before the deeper sections.
- Native workspace next-step queue directly below Command Center for Rust Core recommended actions, keeping document, worktree, and handoff candidates close to the primary path instead of rendering them as a separate late-page suggestion block.
- Native workspace detail overview that keeps lifecycle, branch, services, risk, tasks, SQL readiness, delivery, Codex session count, and latest local-check state visible before deeper workflow sections. Overview tiles are actionable and route directly to the matching document, worktree setup, risk handoff, SQL artifact review or local check, delivery handoff, Codex session action, or local check.
- Native workspace detail Services section now summarizes service scope, missing worktrees, and dirty services, then gives each service its own worktree, source-repository, IDE, confirmed worktree setup, and service-level Codex handoff actions.
- Native clipboard feedback that confirms workspace, lifecycle, risk, task, automation, agent-event, session-link, or task-locator context has been copied, with context-aware next-step guidance.
- Native sidebar Agent Events now render as an Agent Inbox with Attention and Recent groups, so permission, question, tool-review, and error events appear before informational events; when there are no events, the sidebar shows a clear empty state. A compact Agent Workflow bridge connects Inbox events to Agent-sourced Task Center items, with a direct focus action for the Agent task filter. Agent Event detail actions can copy a Codex continuation pack or copy it and open Codex in one step, with local audit records for both paths. Permission, question, and tool-review events also get an Agent action surface with copyable approve/deny/answer/review response templates that do not execute command metadata. After a task draft is written or detected as already present, the detail sheet shows follow-up actions for focusing the matching Agent task or reopening `tasks.md`, and the inspector uses the same local-write feedback model as other Markdown writes.
- Native inspector operation feedback for local errors, with dismiss, copy-error, refresh, environment-check, and Settings recovery actions. The preview app also expands failed local operations with the operation name, target path, and recovery guidance.
- Native empty states for first-run, filtered-out workspace lists, or unselected details, showing configured paths, environment health, a first-run setup path for team profile -> environment check -> workspace creation, and one shared action group for New Workspace, Settings/Profile, Environment Check, Refresh, and Show All recovery.
- Native workflow summary in workspace detail for open tasks, blocked tasks, delivery status, a delivery focus card, grouped document/check/Agent action lanes, delivery-readiness checks, inline local-check receipts, lifecycle writeback recommendations, task documents, delivery records, workspace Codex handoff, delivery-update Codex handoff, and validation/PR handoff, with Chinese-first primary action labels.
- Native Workflow delivery-readiness checklist rows route directly to the nearest action for branch, services/worktrees, tasks, risks, delivery records, SQL checks, and dirty services, keeping delivery cleanup inside the Workflow section. SQL rows now open SQL artifact review when artifacts exist, or start the SQL-aware delivery handoff when required files are missing.
- Native Workflow delivery-readiness separates Attention and Passed rows so blockers and review items stay ahead of already-clear checks during delivery cleanup.
- Native risk review in workspace detail for active risks, blocker/warning readiness checks, status documents, worktree setup, local re-check receipts, and copyable Codex risk-review prompts. Readiness rows route service, branch, worktree, status, task, and SQL findings to the matching document, setup, or delivery-record action.
- Native workspace Documents Hub for opening and previewing standard workspace files plus scanned `sql/*.sql` artifacts without leaving the detail view, including Markdown preview/source mode, explicit close-preview, retry, copy-path, Finder recovery, and confirmed creation of missing standard documents when a file is absent.
- Branch alignment checks that flag worktrees whose actual branch does not match the workspace target branch.
- Workspace bootstrap reports and reviewable `scripts/worktree-commands.sh` files for semi-automated worktree setup.
- Delivery-record completeness warnings when `交付记录.md` still needs real change notes.
- SQL artifact readiness checks: if `交付记录.md` declares an actual SQL change anywhere in the document, `sql/` must include both a formal SQL file and a rollback SQL file before delivery is considered ready. Change metadata inside a `SQL 变更` section, such as `变更类型：DDL/DML`, affected tables, new fields, backfill scripts, or data-fix notes, also counts as a SQL change. New workspace templates repeat this guard in `AGENTS.md`, `handoff.md`, and `交付记录.md` so SQL pasted only into the delivery record is never treated as complete.
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
5. Optionally use the demo template in `New Workspace` to inspect the standard Markdown structure; it still requires the normal preflight and confirmation toggle before writing files.
6. Click the refresh button in the top bar.

If no workspace appears, the native workspace list and detail empty state show a shared setup action group with the configured workspace/source/docs paths, the latest environment-health result, a first-run path for team profile -> environment check -> workspace creation, and direct actions for New Workspace, Settings/Profile, Environment Check, Refresh, and Show All recovery. If a search or filter hides every workspace, use `Show all` from that empty state or `Reset` in the sidebar filters to clear the persisted workspace filter and search query.

To share Nexus setup with another teammate, open `Settings` and export a `nexus-settings-profile-*.json`. The generated JSON contains only path conventions, the Codex URL scheme, the IDE URL template, and refresh interval. Teammates can import the profile from first-run onboarding or native Settings, then adjust paths for their own machine if needed.

After importing a profile, use the native Settings path rows to choose local directories, reveal existing folders, and run `Environment Check` to confirm the configured directories exist, are writable, Git is available, and source repositories are detected. `Tool Links` configures the Codex URL and the IDE URL template. Use `{path}` for the URL-encoded workspace path; the default is `idea://open?file={path}`. Editing a path clears the previous health result so stale checks are not reused.

From a workspace detail view, use `Finder`, `IDE`, `Terminal`, or `Codex` to hand the current workspace to local tools. The IDE action opens the workspace through the configured URL template. The Codex action copies a workspace-specific handoff pack and opens the configured Codex URL from Settings. The handoff pack includes the latest local-check receipt, service/worktree summaries, open tasks, delivery checks, standard document paths, and Nexus recommended actions. Workflow also provides focused delivery-update and validation/PR handoffs for the two handoff moments near the end of a requirement.

The `Codex Sessions` area in workspace detail can bind multiple Codex deep links for the same requirement. Bindings are stored in the workspace-local `codex-sessions.json`; deleting a binding only removes the local Nexus record and does not delete the Codex conversation.

Bound session links also travel with Codex handoff prompts. Workspace, lifecycle, task, risk, delivery, validation/PR, service, and automation handoffs list the relevant session titles and URLs, so a new continuation can reopen an existing Codex conversation before using the fresh context pack.

After any Codex handoff, context copy, session-link copy, or task-source locator, the native inspector shows a dismissible clipboard feedback panel with the copied context type, timestamp, payload label, and next-step guidance. Codex prompts still explain the paste fallback, while task locators point back to `tasks.md` and the focused Documents Hub line context.

When a local operation fails, such as an invalid path, invalid Codex URL, invalid IDE URL template, document-read failure, Terminal launch failure, or worktree setup error, the native inspector shows an `Operation` feedback card. It keeps the error visible and offers copy-error, refresh, environment-check, and Settings actions without moving the user out of the current workspace flow. The preview app uses the same recovery language in toasts for document opens, index rebuilds, workspace creation, settings import/export, and worktree setup.

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
  需求/
    requirement.md
    questions.md
    scope.md
    tasks.md
    delivery.md
  logs/
  sql/
  repos/
  scripts/
```

The `repos/<service>` directories are intended to be git worktrees for isolated multi-branch development.

## Creating Workspaces

Use the `New Workspace` action in the left rail. Nexus can scan the configured source repository root, filter the detected repositories, and let you select services from that local list. You can still type service names manually when a repository is not present yet, or leave service scope pending during early scoping. Manual service input supports commas, spaces, new lines, semicolons, and Chinese separators such as `、` and `，`.

Before writing files, Nexus shows a summary of the target path, branch, and service scope. The preflight review blocks obvious failures such as an empty workspaces root, a root path that is not a directory, an invalid folder name, or a destination that already exists. Pending service scope, pending target branch, missing environment checks, and selected services that are not in the latest source-repository scan are shown as review items so early scoping can still be documented. Creating a workspace requires confirming the local write, then writes the standard Markdown document set and records selected services in `services.md` and `branches.md`. It also generates `bootstrap-report.md`, `scripts/worktree-commands.sh`, a local audit event, and an initialization receipt that verifies the generated files, initial `STATUS.md`, service scope, target branch, and worktree readiness.

After creation, Nexus selects the new workspace, clears stale document previews, and shows guided next steps. The first recommended step is the `需求预检 / Demand intake` panel: initialize `需求/`, enter a requirement name, Lanhu link, and notes, then copy the `$lanhu-demand-intake` prompt into Codex so the agent can prepare `requirement.md`, `questions.md`, and the unfinished requirement list in `需求/tasks.md`. The Native shell checks the resulting Markdown for non-placeholder requirement content, unresolved P0 items, and real requirement task rows. The next native gate is `范围冻结 / Scope freeze`, which reads `需求/scope.md` for confirmed in-scope work, out-of-scope exclusions, unresolved P0 pending items, and an explicit freeze marker. When `需求/tasks.md` contains real requirement rows, Nexus can transfer them into root `tasks.md` after explicit confirmation; Task Center and delivery gates continue to use root `tasks.md`. Nexus does not parse Lanhu or call AI directly; requirement understanding and question grading remain in the follow-up Codex session.

After demand intake is complete and `需求/scope.md` is frozen, continue with service scope, target branch, worktree readiness, `handoff.md`, and the first local check. The Native service/branch gate explains whether `services.md`, `branches.md`, source repositories, and branch policy are ready, and each row opens the nearest source document or setup flow so pending service/branch decisions are handled before worktree creation.

Nexus does not automatically create worktrees during workspace creation. When the branch and service scope are confirmed, use the native worktree setup action to run a confirmed local `git fetch` and `git worktree add` flow. Before the action is enabled, Nexus shows a preflight review for target branch readiness, missing worktrees, source repositories, and the workspace-local `repos/<service>` write location. After it runs, Nexus refreshes the workspace state, shows Chinese-first created/skipped/failed service results, and offers Finder, result-aware Codex handoff, and local-check follow-ups. Running the follow-up check from the result card shows the local check summary in place.

## Local Audit Log

Nexus writes JSONL audit events to `~/Library/Application Support/com.ks.nexus/audit/audit-log.jsonl` for user-visible local writes such as workspace creation and settings profile import/export. High-frequency cache writes, such as widget snapshot refreshes, are not audited.

The native menu bar can run a local automation check manually or on a persisted schedule while Nexus is running. That check scans workspace Markdown and git state for refresh, risk, delivery, branch-alignment, task, worktree, and dirty-service signals, then appends an `automation.check.completed` audit event when the Rust Core bridge is available. Optional macOS notifications are off by default, support cooldown and signal preferences, and only fire when a check result matches the selected minimum status.

The native right inspector also includes an Automation Action Center. After a check runs, Nexus converts risk, delivery, branch, task, worktree, and dirty-service signals into clickable actions such as copying a risk-review Codex handoff for the risky workspace, opening branch notes for branch mismatches, selecting the Task Center, presenting the worktree setup confirmation, opening a dirty service in a service-scoped Codex handoff, or copying a Codex prompt with the current local paths and workspace context. Delivery signals now pick the relevant workspace first, prefer SQL artifact issues before generic delivery-record issues, and route to SQL-aware delivery handoff or missing-delivery review instead of opening an unrelated document. Worktree prompts include missing service names, source availability, the generated worktree script path, readiness checks, and whether the target branch must be confirmed before setup. Copied automation prompts also include Nexus recommended next-step actions, so branch/service confirmation blockers travel with the signal evidence. Task signals only count active tasks; deferred tasks remain available in Task Center without creating local-check noise. Risk, task, branch, worktree, and dirty-service signals likewise target the first workspace with matching evidence when copying an automation prompt, so the next Codex session starts from the actual blocker instead of an unrelated selection.

Recent Agent Events in the native sidebar are organized as an Agent Inbox. Attention shows permission, question, tool-review, and error events first; Recent keeps the remaining informational events nearby, and an empty state confirms there is nothing waiting for review. The Agent Workflow bridge directly below the inbox explains whether the next step is reviewing events or continuing Agent-sourced tasks, and can switch Task Center to the Agent filter when those tasks exist. Opening an event shows detail review where Nexus can select the matching workspace, open safe local paths or web links, copy the shared Codex continuation pack, or copy that pack and open the configured Codex URL in one action. Permission, question, and tool-review events show an Agent action surface with copyable approve/deny/answer/review templates; these copies are audited, but command metadata remains review-only text and is not executed by Nexus. When an Agent task draft is appended to `tasks.md`, or when the same task already exists, the event detail keeps a result card open so the user can jump to the Agent task filter or inspect the source document without losing the review flow.

Each workspace detail view starts with a compact Detail map, then an overview for lifecycle, branch, services, risk, tasks, delivery, Codex session count, and the latest local check. The Detail map keeps Overview, Command Center, Workflow, Services, Risk Review, Documents, and Activity as named jump targets with small status hints, so the long detail page remains navigable as more workflow capabilities land. The overview tiles are actionable: lifecycle opens its current document, branch/services/tasks return to the source Markdown, missing worktrees open the confirmed setup flow, risks copy the risk handoff, delivery reuses the status route, sessions open or bind Codex links, and check reruns the local automation check. The `Command Center` then summarizes lifecycle progress, branch readiness, service/worktree status, risk level, task state, delivery state, and saved Codex sessions, and shows a single primary path with the reason behind the next best action. Task and delivery metrics are derived from the same workflow summary used by the path, so blocked/open tasks and delivery-record readiness stay visible before the deeper Workflow section. When saved Codex sessions exist, the clean primary path can resume the latest session; otherwise the same area still routes to binding a session or copying a fresh handoff pack. A compact workflow path keeps scope, worktree, risk, tasks, delivery, Codex sessions, and Codex handoff visible as one sequence with Chinese-first status and action labels. The delivery path chooses the next step from evidence: pending status runs a local check, review/blocker status opens a delivery-update Codex handoff, completed status opens validation/PR handoff, and ready or archived records open the delivery document. Quick actions are grouped as `Handoff`, `Next`, and `Local` so Codex continuation, checks/lifecycle actions, and Finder/IDE/Terminal/workspace-link copy stay separate. Rust Core recommended session actions appear immediately below as a `Next-step queue`, preserving secondary document/worktree/handoff candidates without competing with the primary path. After a local check runs, the Command Center keeps a compact receipt with status, risk/delivery/task/worktree metrics, audit feedback, and a copyable summary for Codex handoff.

When a document opens from tasks, risks, delivery, search, or the Documents hub, the workspace detail keeps an active-document banner near the top. The banner shows loading, error, or ready state for the current workspace document, can jump back to the Documents preview, copy the path, or close only the document preview without closing the workspace detail.

The `Services` section is the service-level operations hub for the same flow. It summarizes total services, missing worktrees, and dirty service signals, then keeps each service row close to the concrete local action: open the workspace-local worktree, open the source repository for read-only comparison, launch the configured IDE against that service worktree, enter the confirmed worktree setup flow when the worktree is missing, or copy/open a service-specific Codex handoff that includes paths, branch, git summaries, and the relevant workspace documents.

Each workspace detail view includes a `Workflow` section that keeps task and delivery state together. It starts with a delivery focus card that chooses one next action from branch confirmation, service scope, worktree setup, blocked/open tasks, risks, delivery records, SQL notes, dirty services, lifecycle delivery, done confirmation, and post-done PR/CI review. It also summarizes open and blocked tasks, shows whether the delivery record is ready or needs review, then groups the main actions into `Docs`, `Check`, and `Agent handoff` lanes so opening `tasks.md`, opening `交付记录.md`, running local checks, handing off the workspace, updating delivery, and preparing validation/PR context stay in one readable flow. Workflow then checks branch confirmation, service worktrees, task closure, risks, SQL readiness, dirty services, and delivery-record status before handoff. The readiness checklist is grouped into `Attention` and `Passed` sections, so blockers and review items stay above already-clear checks while still preserving the full evidence list. Those readiness rows are actionable: branch opens branch notes, services open the service document or confirmed worktree setup, tasks open `tasks.md`, risks copy the risk-review handoff, delivery issues open the delivery-update handoff, passing SQL rows open SQL artifact review, missing SQL artifacts open the SQL-aware delivery handoff, and dirty-service rows start a service-scoped Codex handoff. When Workflow triggers or follows a local check, the same compact receipt used by Command Center and Risk Review stays inline with task and delivery actions, including metrics, audit status, and copy-summary. SQL readiness is evidence-based: a delivery record that declares a real SQL change anywhere in the Markdown, including code-change notes, tables, detailed headings, or SQL-section metadata like `变更类型：DDL/DML` and affected tables, must be backed by both formal and rollback `.sql` files under `sql/`. The delivery and PR handoffs include delivery-record path, tasks, SQL checks, risks, services/worktrees, and the latest local-check context so the agent can update or summarize from evidence instead of a blank document.

Task rows carry their source line from the Rust Core `tasks.md` scan. The Task Center and workspace task rows can locate a task by opening `tasks.md`, copying a small task-source locator to the clipboard, and showing the focused line context in the Documents Hub. When a task status writeback updates `tasks.md`, the native Task Center keeps a compact recent-writeback card with affected-workspace focus and source-document actions, even if the task list changes after the refresh. Marking a task deferred keeps it reviewable but removes it from active task automation and workflow blockers.

Task writebacks now keep the processing loop moving. After completing or deferring a task, Nexus can focus the next active task, preferring the same workspace before falling back to the next active item. Agent Event task writebacks also switch Task Center to the Agent filter and focus the matching task so the user can continue from the converted item without hunting through the sidebar.

Each workspace detail view also includes a `Risk review` section. It consolidates active risk signals and non-delivery readiness checks into risk, blocker, and warning counts, then routes the next step to a fresh local check, `STATUS.md`, confirmed worktree setup when services are missing, or a copied Codex risk-review prompt. Individual readiness rows are actionable too: service scope, target branch, worktree, status, task, and SQL artifact findings open the nearest source document, setup flow, or delivery record instead of leaving the user to hunt for the right section. The latest check receipt stays visible inside Risk Review so the user can confirm whether a re-check actually changed the risk surface.

The workspace detail view also includes a `Documents` hub for the standard workspace files: `workspace.md`, `STATUS.md`, `services.md`, `branches.md`, `tasks.md`, `交付记录.md`, `handoff.md`, `bootstrap-report.md`, and `scripts/worktree-commands.sh`. The same hub now lists scanned `sql/*.sql` artifacts in a separate SQL section, including formal and rollback files, so delivery SQL can be reviewed in-app instead of jumping to Finder. Selecting a document highlights the active entry, opens it in the native preview/source viewer, and shows retry, copy-path, and Finder recovery if the file is missing or unreadable. The preview itself can be closed without closing the workspace detail. When a standard file is missing, Nexus can create a safe skeleton only after confirmation, then refresh the workspace, open the new document, and show local-write feedback; dynamic SQL files remain review-only and are not auto-created by the document recovery flow.

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
npm run env:check
npm run verify
```

For a faster public-preview baseline during documentation or sample-data work:

```bash
npm run test
npm run build
npm run privacy:check
```

## Widget Status

The main app already writes the widget snapshot and registers the `nexus://` URL scheme. The native shell writes the same snapshot to Application Support, handles `nexus://workspace/<folder>` focus links, and mirrors the snapshot into `group.com.ks.nexus` once the app is packaged with App Group entitlements. The WidgetKit source lives in:

```text
widget/NexusWidget/NexusWidget.swift
```

Building and shipping the actual `.appex` requires a full Xcode project with a Widget Extension target, App Group configuration, signing, and notarization. See [widget/README.md](widget/README.md).

## Documentation

- [Product shape](docs/product-shape.zh-CN.md)
- [Native Swift-only roadmap](docs/native-swift-only-roadmap.md)
- [Main workflow contract](docs/main-workflow.md)
- [Main workflow audit](docs/main-workflow-audit.zh-CN.md)
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
