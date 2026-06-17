# Native Architecture Target

Nexus is moving toward a Mac-first native architecture while preserving the current Tauri app as the preview implementation. The Chinese product shape in `docs/product-shape.zh-CN.md` defines the target user experience that this architecture supports.

## Target Shape

```text
Nexus
├─ apps
│  ├─ mac-native        SwiftUI + AppKit primary Mac app
│  └─ tauri-preview     Current Tauri + React preview app
├─ crates
│  ├─ nexus-core        Workspace, git, risk, document, and index domain logic
│  └─ nexus-ffi         Swift-callable bridge over nexus-core
├─ native
│  ├─ Nexus             Xcode project / Swift package for the Mac app
│  └─ NexusWidget       WidgetKit extension target
├─ storage
│  └─ SQLite + FTS      Local metadata and Markdown index
└─ docs
   └─ Architecture, roadmap, release, and migration records
```

The exact folder names can evolve during implementation. The important boundary is that the domain logic moves out of UI shells and into `nexus-core`.

The first native shell scaffold is available at `native/Nexus`. It is a Swift Package that compiles a sample SwiftUI workspace experience while the Tauri app remains the usable preview package.

## Layer Responsibilities

### Native Mac App

- SwiftUI app shell, navigation, document views, settings, command surfaces, and workspace cards.
- Primary Native surfaces are `Console` for selected-workspace execution and `Board` for stage-based workspace overview. Board is presentation-only: it groups workspaces from shared workflow evidence and routes selected cards back to Console for mutation or handoff actions.
- AppKit adapters for menu bar, file panels, keyboard shortcuts, Finder/Terminal/IDE launch, and any behavior where AppKit is more reliable than SwiftUI alone.
- Explicit confirmation flows for operations that create files, create worktrees, or change local state.
- Create-workspace UX for scanning source repositories, filtering service candidates, accepting manual fallback services, showing pending scope, preflighting workspaces root readiness, folder validity, destination collisions, environment health, and scope warnings before confirmation, verifying generated files and initial status through an initialization receipt, and guiding the user to the next safe step after creation.
- Workspace demand-intake preflight that reads the workspace-local `需求/` archive status, initializes missing requirement/question/scope/task/delivery templates only after explicit confirmation, routes generated files back into the document preview and local-write feedback loop, can hand `$lanhu-demand-intake` prompts to Codex with existing session links, and is surfaced from Command Center before development starts.
- Swift-owned scope-freeze evidence that reads `需求/scope.md` for in-scope, out-of-scope, pending P0, freeze marker, and scope-change audit signals. Declared scope changes must include reason and affected service/task/SQL/delivery impact before the gate is ready.
- Workspace workflow summary that keeps task status, delivery-record status, document opens, local checks, and Codex handoff together instead of scattering them across unrelated sections.
- Workspace Documents Hub that maps standard workspace files and scanned `sql/*.sql` artifacts to native preview/source rendering, shows each document's purpose, update timing, gate participation, and create policy, and avoids stale previews when the selected workspace changes.

### Rust Core

- Workspace folder discovery.
- Markdown document inventory and metadata extraction.
- Git and worktree status inspection.
- Branch alignment analysis.
- Risk detection.
- Workspace readiness checks for demand-intake preflight, service scope, target branch confirmation, target branch availability, worktree readiness, branch alignment, dirty worktrees, delivery records, full-document and SQL-section metadata SQL artifact completeness, active tasks, and blocked tasks.
- Session-action generation that turns readiness and risk signals into prioritized demand-intake preflight, Codex handoffs, worktree command copies, and document follow-ups.
- Reviewable worktree command generation.
- Confirmed worktree setup that validates service names, source repositories, target branches, and existing worktree paths before running Git, then returns created/skipped/failed details for native follow-up actions.
- Standard workspace skeleton creation, including Markdown documents, SQL/log/repos folders, bootstrap scripts, and initialization receipt data for generated files and initial `STATUS.md`.
- Demand-intake status and confirmed initialization for workspace-local `需求/` files, preserving existing human-written files while producing reusable requirement, question, scope, task, and delivery templates.
- Settings profile validation.
- Settings profile export file naming and JSON serialization.
- Widget snapshot generation.
- Agent event ingestion and local JSONL persistence for future hook helpers and in-app approval surfaces.
- Future SQLite indexing and full-text search.

### Swift/Rust Bridge

- The initial bridge uses a small C ABI with JSON request/response payloads. It is intentionally simple while the native app shape is still moving.
- `crates/nexus-ffi` currently exposes workspace scans with readiness checks, session actions, and audit-log activity enrichment, source-repository scans, document reads, demand-intake status/initialization, widget snapshot computation, JSONL audit event append, JSONL agent event append/read, SQLite/FTS index rebuild/search, confirmed workspace creation, and confirmed worktree setup over `nexus-core`.
- `native/Nexus/Sources/NexusBridge` owns Swift `Codable` DTOs, preview fallback data, and optional dynamic library loading through `NEXUS_CORE_LIBRARY`.
- The native SwiftUI shell uses the same search bridge to rebuild/query the local index, then falls back to in-memory workspace metadata when the dynamic library is not configured.
- Native search results surface selected-result context from the current workspace model, including branch, service count, risk, and recent activity.
- The native shell stores lightweight personal UI preferences, such as local root paths, the selected search scope, and pinned workspace IDs, in `UserDefaults`. These preferences are local conveniences; Markdown workspace records and Rust Core scan output remain the product source of truth.
- The native Settings surface can import and export the shareable Nexus settings profile shape used by the Tauri preview app, adding an optional IDE URL template while keeping existing path/Codex settings import-compatible, so small teams can pass path and tool-link conventions without copying workspace content or code.
- The native Settings surface can show per-path readiness rows, use AppKit directory pickers and reveal actions, and run local environment checks for configured directories, write access, Git availability, workspace counts, and source repository counts after a profile is imported or paths are edited.
- The native workspace list and inspector empty states share the setup action group: they surface configured local paths, the latest environment-health summary, a team-profile -> environment-check -> workspace-create setup path, and the primary recovery actions before users reach a workspace detail.
- The native create-workspace sheet owns local-write preflight for the setup path: it blocks only write-failure conditions such as invalid folders or destination collisions, while allowing branch/service uncertainty to remain visible as review items for early demand scoping. When no workspaces exist, it can prefill a demo workspace template, but the user still has to pass preflight and confirm before any files are written.
- The native shell handles `nexus://workspace/<folder>` as a workspace-focus action: it clears active filters/search, refreshes workspace data when needed, updates widget state, and writes an audit event for successful deep-link focus. The Command Center can also copy the current workspace link from the Local tools lane and show transient inspector feedback.
- The native workspace detail surface owns Mac handoff actions for Finder, IDE, Terminal, and Codex URL launches. IDE launch uses a configurable URL template from Settings, while Codex handoff copies a workspace prompt first, then opens the configured local URL.
- Workspace Codex handoff now acts as a richer local handoff pack: it includes latest local-check status, service/worktree summaries, open tasks, delivery checks, standard document paths, and recommended session actions before opening the configured Codex URL.
- The native workspace detail surface now owns workspace-level Codex session link bindings, backed by `codex-sessions.json`, so one requirement can keep multiple return links to active Codex conversations.
- The `Codex 会话 / Sessions` detail section is also the discovery point for matching Agent Event deep-link metadata. Suggested bindings stay in the session IA and only become durable after the user confirms the bind action.
- Codex session links are also part of the Command Center contract: status overview shows session count, the session path includes a session step, and a clean primary path can resume the latest saved session before falling back to a new handoff pack.
- Bound Codex session links are copied into workspace, lifecycle, task, risk, delivery, validation/PR, service, and automation handoff prompts. Handoffs therefore carry both current evidence and existing conversation return links.
- The native inspector owns transient clipboard feedback so clipboard-based context transfers have visible confirmation without writing additional workspace files. Feedback copy changes with the payload: Codex prompts, session links, automation handoffs, and task-source locators can each show their own section title, clipboard label, and next-step guidance.
- The native inspector also owns unified operation feedback for local failures. It keeps `lastError` visible with recovery actions for copying the error, refreshing workspace data, running environment checks, and opening Settings, while detail sections keep their domain-specific inline hints.
- The native workspace detail surface now starts with a compact `Detail map`, then a `Command Center` that explains the primary path before secondary tool actions and keeps scope, demand preflight, worktree, risk, tasks, SQL, delivery, archive, Codex sessions, and Codex handoff visible as a compact session path. The Detail map gives Overview, Command Center, Demand, Workflow, Services, Risk Review, Documents, and Activity stable jump targets with small state hints, keeping long detail pages navigable without adding another flat action cluster. Path cards expose compact action labels, the demand path routes incomplete preflight back to `需求预检`, the SQL path routes pending evidence to local check, matching artifacts to SQL review, and missing artifacts to handoff; the delivery path routes pending evidence to a local check, review/blocker evidence to delivery-update Codex handoff, completed workspaces to validation/PR handoff, and ready or archived records to document review; the archive path reuses the delivery hard gate and routes lifecycle-safe actions through confirmed writeback for entering delivery, marking done, archiving, or explicitly restoring archived workspaces to development. Its quick actions are grouped into handoff, execution, and local tool lanes instead of one flat button cluster; local tools own Finder, IDE, Terminal, and workspace-link copy. Rust Core session actions sit immediately below as a `Next-step queue`, so secondary demand/document/worktree/handoff candidates stay near the primary path without becoming another late-page action island. Below that it separates product workflow concerns: `Workflow` owns tasks, delivery/archive state, and delivery-readiness checks, `Risk Review` owns active risks and non-delivery readiness checks, `Documents` owns standard Markdown/script entry points, and `Activity` remains historical context.
- The post-create workspace surface is the first-run version of that same contract: it turns the initialization receipt into a service, branch, worktree, handoff, and local-check checklist, routes pending scope decisions to `services.md` or `branches.md` before enabling confirmed worktree setup, and starts the document flow by opening the generated `handoff.md`.
- Workspace detail also owns a compact actionable status overview above Command Center so lifecycle, demand preflight, branch, services, risk, tasks, SQL, delivery, Codex sessions, and latest local-check state are visible before the user enters deeper sections. Each overview tile routes to the nearest core-path action instead of acting as a passive metric: demand preflight, source documents, SQL artifact review or local check, confirmed worktree setup, risk handoff, delivery handoff, session binding/opening, or local check.
- The `Services` detail section owns service-level operations rather than leaving git rows as passive text. Each service row can open its workspace-local worktree, open the source repository for read-only comparison, launch the configured IDE against the service worktree, enter the confirmed worktree setup flow when the worktree is missing, or copy/open a Codex handoff scoped to that service. These actions stay below the Services section so Command Center remains the requirement-level path, while service triage remains close to the service evidence.
- Command Center, Workflow, and Risk Review all render the latest local-check receipt inline so a manual check has immediate visible feedback near the workflow that triggered it, while the right inspector remains the place for actionable automation signals.
- Automation Action Center risk, delivery, task, branch, worktree, and dirty-service signals resolve a concrete target workspace before acting. Risk signals copy a risk-review handoff for the risky workspace; SQL delivery issues are preferred over generic delivery-record issues; task signals prefer high-priority or open-task workspaces; branch signals prefer workspaces with branch-alignment failures; worktree signals include missing services, source availability, script path, and branch-confirmation guidance. Copied automation prompts include the selected workspace's branch notes, delivery record, SQL artifacts, Nexus recommended next-step actions, and delivery/SQL check details when available.
- The native `Documents` hub owns local document-open feedback: it highlights the active standard document or SQL artifact, keeps loading state close to the clicked entry, renders Markdown with a source toggle, lets the user close only the preview state, and shows retry, copy-path, Finder recovery, and confirmed missing-standard-document creation when the bridge reports an absent standard file. Creation is a Rust Core/FFI writeback, refuses non-standard or parent-directory paths, appends audit metadata, refreshes workspace state, and reopens the new document. Dynamic SQL artifact entries are review-only and are never created by the missing-standard-document recovery path.
- Workspace detail also mirrors the active document near the top as a lightweight banner for document opens that originate outside Documents hub, including tasks, risks, delivery, search, and automation routes. The banner can jump to Documents, copy the document path, or clear only the document preview state so closing document context does not dismiss the workspace detail.
- The `Workflow` section starts with a delivery focus card so task and delivery state resolves to one primary next action before users inspect the full readiness checklist. Its secondary actions are grouped into document, local-check, and Agent handoff lanes instead of one flat button row, and its local-check action uses the same compact receipt component as Command Center and Risk Review, keeping check status, metrics, audit feedback, and copy-summary beside task and delivery controls. Delivery-gate evidence now also exposes an ordered resolution plan for blockers, pending checks, review items, and passed evidence, with handoff/writeback hints before the lower-level checklist. Validation/PR evidence sits after the delivery gate and before archive eligibility, summarizing local-check, delivery-record, task/risk, PR/CI, release-note, and lifecycle readiness while keeping GitHub integration optional. Archive eligibility now exposes a confirmation plan that reuses delivery blockers when delivery is incomplete, then orders delivery-record review, validation/PR review, lifecycle writeback, and final archive confirmation once delivery passes. Archived workspaces reuse the same plan surface as read-only history: the primary action opens handoff evidence, while the restore row requires lifecycle confirmation back to `developing` and explicitly tells users to re-run local checks. Delivery-readiness rows are grouped into Attention and Passed sections, then remain actionable: branch, service/worktree, task, risk, delivery-record, SQL, and dirty-service findings route to their source documents, confirmed setup flow, SQL artifact review, SQL-aware delivery handoff, risk handoff, or service-scoped Codex handoff. Risk Review keeps non-delivery readiness rows actionable as well, routing service, branch, worktree, status, task, and SQL findings to their source document, confirmed setup flow, SQL artifact review, or delivery record.
- Development task evidence keeps root `tasks.md` as the execution source and now derives a Swift-owned task plan that explains which tasks are blockers, which task should continue now, which tasks are queued, and which closed/deferred tasks do not block the main path.
- Workflow owns delivery-update and validation/PR handoffs as distinct actions from the general workspace handoff. Delivery-update copies a focused prompt with delivery record, tasks, SQL checks, risks, services/worktrees, and latest local-check context before opening Codex. Validation/PR handoff carries local checks, delivery, SQL, tasks, services/worktrees, and PR-summary requirements into the final review flow, then records `codex_validation_pr_handoff.opened`. SQL checks treat `交付记录.md` as the declaration source: once it records a real SQL change, including SQL-section metadata such as `变更类型：DDL/DML`, affected tables, new fields, or backfill scripts, `sql/` must contain both formal SQL and rollback SQL files.
- Confirmed task-status and lifecycle writebacks surface a local-write feedback card in the inspector, keeping affected-workspace focus, source-document review, and follow-up checks close to the write that changed local Markdown.
- Task-status writebacks also feed Task Center continuation state: Nexus prefers the next active task in the updated workspace, falls back to the next active task globally, highlights the focused task row, and lets recent-writeback cards jump directly into that next item. Agent task draft writebacks set the Task Center Agent filter and focus the matching converted task.
- Local-write feedback actions share the same affected-workspace focus behavior so users do not review updated files or checks against a stale selected workspace.
- The native Task Center mirrors recent `tasks.md` writeback feedback so task status changes remain visible near the task list after a refresh changes the open-task set.
- Task rows keep `tasks.md` source-line metadata from Rust Core. Native task actions can locate the source row by opening the document, copying a line-aware locator, and showing the focused line context inside Documents Hub instead of sending users to an undifferentiated file.
- The native worktree setup surface treats Git worktree creation as a preflighted local-write operation: target branch, missing services, source repositories, workspace-local write paths, and a service-level create/skip/blocked setup plan must be visible before confirmation.
- Native document reads render Markdown by default, keep a source toggle for raw content, append `document.opened` audit events when the Rust Core bridge is available, and update the visible timeline immediately. Missing standard document creation appends `document.created` audit events and reuses local-write feedback instead of silently writing files.
- Native widget snapshots are written by the SwiftUI shell to Application Support and mirrored to `group.com.ks.nexus` when an App Group container is available, keeping unsigned local development and signed WidgetKit packaging on the same data contract.
- Native agent event reads load local agent hook events into the sidebar as an Agent Inbox when the Rust Core bridge is available. The inbox prioritizes permission, question, tool-review, and error events under Attention, keeps informational events under Recent, and shows an empty clear state when no events exist. A compact Agent Workflow bridge sits between Agent Inbox and Task Center, summarizing pending event count plus Agent-sourced task count and routing users to the Agent task filter after event drafts are written into `tasks.md`.
- Agent Event detail keeps continuation actions in the agent-event surface: users can copy the shared Codex context or copy it and open Codex in one action, with audit events tied back to a matched workspace when available.
- Agent Event task-draft writebacks stay in the same review flow after confirmation. Appended and already-existing task results show a focused follow-up card that can switch Task Center to the matching Agent task or reopen `tasks.md`, while the inspector receives the shared local-write feedback used by other Markdown writes.
- Agent Event detail also owns the first in-app reply/approval surface for permission, question, and tool-review events. The surface only copies approve, deny, answer, or review response templates with visible inspector feedback and `agent_event_response.copied` audit entries; command metadata remains review-only text until a future structured bridge can return responses to the agent.
- Native session actions can open follow-up documents and execute confirmed worktree setup through the Swift/Rust bridge. Worktree setup remains a confirmed local write and reports created, skipped, and failed services back to the user.
- Worktree setup result handoff copies created/skipped/failed details before opening Codex, so the follow-up session receives the exact local Git outcome instead of only the general workspace context.
- Worktree setup results classify failed services into Swift-owned recovery actions for missing source repos, invalid source Git state, fetch/branch failures, branch occupancy, and worktree command review, and those recovery actions are shown in-app and copied into the Codex handoff.
- The worktree setup result surface can run a local automation check and display the resulting risk/task/worktree summary in place before the user closes the sheet.
- Worktree setup result labels are Chinese-first for small-team usage while keeping compact English hints where they help with engineering terminology.
- The native shell includes a menu bar status item for quick workspace, risk, task, worktree, refresh, settings, recent-workspace, and copy-summary actions without opening the full window first.
- Rust Core and the Swift/Rust bridge expose a local automation check that emits refresh, risk, delivery, task, worktree, and dirty-service signals for native menu bar and future background hooks.
- The native shell can schedule those local automation checks with persisted UserDefaults while the app process is running; this remains separate from LaunchAgents or system notification permissions.
- Optional UserNotifications alerts are a native-shell concern and are only sent after explicit local authorization when automation status needs review or attention.
- Automation notification preferences, including cooldown, minimum status, and signal filters, stay in local UserDefaults because they are personal attention settings rather than workspace source-of-truth records.
- The command surface should grow in this order: scan, read document, compute widget snapshot, create workspace skeleton, initialize demand intake, audit local actions, rebuild/search the local index, produce worktree plans, and execute confirmed worktree setup.
- Local write operations must include explicit confirmation in the bridge request, not only in UI copy.
- Bridge responses use explicit success/error envelopes so the native shell can show user-facing failures without guessing.

### Local Store

- SQLite database under Application Support. The first database file is `nexus-index.sqlite3`.
- FTS tables for workspace Markdown, delivery records, tasks, decisions, SQL notes, and service scopes.
- Audit log table for local writes and generated commands. The current bridge uses append-only JSONL under Application Support as the durable source that dashboard scans and SQLite can index later.
- Agent event JSONL for local AI agent lifecycle, prompt, question, permission, and tool-use events. These events are operational telemetry, not workspace source-of-truth records.
- Rebuildable from the human-readable workspace folders.

### Widget And Companion Surfaces

- WidgetKit reads a compact snapshot from an App Group container once signing and App Group setup are ready, with Application Support as the local development fallback.
- iPad and iPhone clients should be companion views: status, risks, documents, tasks, approvals, and remote/agent handoff.
- Mac remains the authority for local filesystem and git/worktree operations.

## Data Ownership

Human-readable Markdown files remain the source of truth for requirement workspace records. SQLite is an index/cache that can be rebuilt. The app should never require users to trust an opaque database as the only copy of their project knowledge.

## Safety Model

- **Read-only:** scan workspace documents, inspect git status, preview documents, build search indexes.
- **Confirmed writes:** create workspace skeletons, write standard Markdown files, export settings, write widget snapshots, write audit events.
- **High-risk operations:** branch deletion, reset, clean, worktree removal, or overwriting user files. These need explicit confirmation and should not be part of early native migration.

## Migration Principle

Every new roadmap feature should answer one question before implementation:

> Does this belong in the native shell, the Rust Core, or both?

If a feature can be reused by macOS, iPad, iPhone, CLI, or future agents, it belongs in Rust Core first.
