# Changelog

All notable changes to Nexus are documented here.

The format follows Keep a Changelog, and versions should follow semantic versioning once the project reaches a stable public release.

## [Unreleased]

### Added

- `nexus-core` Rust crate foundation for reusable git, source-repository, workspace scanning, document parsing, and risk detection logic.
- Reusable Rust Core support for settings profile export and standard workspace skeleton creation.
- SwiftUI/AppKit native Mac shell scaffold with sample workspace navigation and CI build validation.
- `nexus-ffi` C ABI + JSON bridge scaffold for Swift-callable Rust Core read-only workspace and source-repository scanning.
- Swift `NexusBridge` target with typed dashboard DTOs, preview fallback data, and optional dynamic library loading through `NEXUS_CORE_LIBRARY`.
- Rust Core and Swift/Rust bridge document-reading support for native Markdown/document preview workflows.
- Rust Core widget snapshot computation with FFI and Swift bridge support for native summary surfaces.
- Swift/Rust bridge workspace creation with an explicit confirmation contract and native Mac shell creation sheet.
- Native architecture roadmap for the SwiftUI/AppKit + Rust Core migration path.
- Public maintenance docs and GitHub collaboration templates.
- CI and release workflow definitions for future automated validation and DMG publishing.
- Core workspace model tests using the Node.js test runner.
- Distribution notes for signing, notarization, universal builds, and updater readiness.
- First-run onboarding for local path setup.
- Native source repository scanning for service selection and git state awareness.
- Service picker in the create-workspace flow, backed by scanned local repositories.
- Native SwiftUI create-workspace flow now supports service filtering, selected scanned repositories, manual service fallback, pending service scope, and a creation summary before confirmed local writes.
- Native SwiftUI now focuses a newly created workspace and shows a dismissible post-create next-step panel for handoff, worktree setup, Codex handoff, and local checks.
- Native environment health checks for configured paths and Git availability.
- Workspace bootstrap reports and reviewable worktree command scripts.
- Delivery-record completeness warnings when records still contain placeholder content.
- Exportable and importable Nexus team settings profiles for sharing path conventions.
- Local audit log support in Rust Core, Tauri commands, and the Swift/Rust bridge for confirmed workspace creation and settings profile exports.
- SQLite + FTS local index foundation in Rust Core, Tauri commands, and the Swift/Rust bridge for workspace Markdown, service scope, tasks, decisions, delivery records, and SQL notes.
- Global search popover in the Tauri preview app, backed by the local SQLite/FTS index with browser-preview metadata fallback.
- Grouped global search results with arrow-key selection, Enter-to-open, and Escape-to-clear navigation.
- Native SwiftUI search popover backed by the Swift/Rust search bridge, with grouped results, keyboard navigation, and workspace metadata fallback.
- Native search-result context preview with workspace risk, branch/service summary, and compact activity timeline.
- Native search scope controls for workspace/state/workflow/SQL/document-focused search in the SwiftUI shell.
- Native SwiftUI document previews now render Markdown by default and keep a source-mode toggle for raw content.
- Native workspace details now include local handoff actions for Finder, Terminal, and configured Codex URL launches with copied workspace context.
- Native SwiftUI now writes WidgetKit snapshots to Application Support and mirrors them to `group.com.ks.nexus` when an App Group container is available.
- Native pinned workspaces with local persistence so important requirement workspaces stay at the top of the Mac shell.
- Native Settings can now be opened from the sidebar, persists configured local roots, and can save/reload or reset default paths.
- Native Settings can now import and export shareable Nexus team profiles compatible with the Tauri preview app.
- Native Settings now includes an environment check for configured paths, Git availability, workspace counts, and source repository counts.
- Native SwiftUI session actions are now actionable for document follow-ups and confirmed worktree setup, with visible created/skipped/failed results.
- Native SwiftUI worktree setup now refreshes the active workspace result state, explains blocked/empty states, and provides Finder, Codex, local-check, and close follow-up actions after setup.
- Native SwiftUI workspace details now include a Workflow summary that keeps task counts, blocked tasks, delivery-record status, task/delivery document opens, local checks, and Codex handoff in one section.
- Native SwiftUI workspace details now include a Documents Hub for standard workspace files, with stale previews cleared when switching workspaces.
- Native SwiftUI workspace details now include a Risk Review section that consolidates non-delivery readiness checks, active risk signals, local re-checks, status document access, worktree setup, and a copyable Codex risk-review prompt.
- Native SwiftUI workspace details now start with a Command Center that consolidates lifecycle progress, branch/service/risk/task signals, Codex continuation, local checks, next-step routing, and Finder/Terminal handoff.
- Native SwiftUI now shows actionable empty states for missing workspaces, empty filters, and unselected details, with direct Settings, New Workspace, Refresh, and Environment Check actions.
- Native SwiftUI worktree setup now includes a preflight review for target branch readiness, missing worktrees, source repositories, and workspace-local write locations before local Git commands can run.
- Native SwiftUI now shows a dismissible Codex handoff feedback panel after workspace, lifecycle, risk, task, automation, or agent-event context is copied.
- Native SwiftUI Workflow now includes a delivery-readiness checklist for branch confirmation, service worktrees, task closure, risks, SQL readiness, delivery record status, and dirty services.
- Native SwiftUI Command Center now surfaces a single primary path that explains the next best action before secondary tool actions.
- Native create-workspace results now include an initialization receipt for generated standard files, directories, initial `STATUS.md`, service scope, target branch, and worktree readiness.
- Native Settings local path configuration now shows per-path health, directory pickers, reveal actions, and clears stale environment results after edits.
- Native Task Center and workspace task rows now open the owning `tasks.md` document directly, keeping task review close to the source Markdown record.
- Native SwiftUI action labels now use clearer Chinese-first wording and hover help for path recovery, task documents, task status updates, and task Codex handoff.
- Native Task Center and workspace task rows now copy task context and open Codex in one action, with task-specific handoff feedback and audit records.
- Native task and lifecycle writebacks now show a dismissible local-write feedback card with updated source-document and follow-up check actions.
- Native Task Center now shows the latest `tasks.md` writeback result with focus and source-document actions.
- Native Workspace Command Center now includes a compact session path for scope, worktree, risk, tasks, delivery, and Codex handoff, with Chinese-first primary actions.
- Native Documents Hub now highlights the active document and shows local loading/error feedback with retry, copy-path, and Finder recovery actions.
- Native Command Center and Risk Review now show a compact local-check receipt with status, metrics, audit feedback, and a copyable summary after running checks.
- Native workspace detail now starts with a compact status overview for lifecycle, branch, services, risk, tasks, delivery, and latest local check state.
- Native local-write feedback can now focus the affected workspace, clearing search and filters before the user reviews the refreshed Workflow state.
- Native local-write feedback actions now use a compact wrapping layout, and document/check actions also focus the affected workspace first.
- Native Workflow delivery summary now recommends lifecycle writebacks from delivery readiness, routing users into the existing confirmation flow for entering delivery or marking done.
- Native Workflow action labels now use Chinese-first wording and hover help for task documents, delivery records, local checks, and workspace Codex handoff.
- Native Workflow now starts with a delivery focus card that turns branch, service, worktree, task, risk, SQL, dirty-service, and delivery-record state into one recommended next action.
- Native worktree setup results now copy created/skipped/failed details into the Codex handoff before opening Codex.
- Native worktree setup results now show the follow-up local-check summary inside the result card after running checks.
- Native worktree setup result actions now use Chinese-first labels, clearer result group names, and hover help for compact metrics.
- Documentation now includes a Chinese complete product-shape blueprint for the Mac-first local AI development workbench target.
- Rust Core and the Swift/Rust bridge now support local agent event append/read flows backed by `agent-events.jsonl`.
- Native SwiftUI sidebar now shows recent agent events from the local bridge, with preview fallback data when Rust Core is not loaded.
- Native SwiftUI agent events can now be opened for full context, metadata inspection, and JSON copy.
- Native SwiftUI agent event details now expose safe next-step actions for matching workspaces, local paths, web links, and Codex context copy.
- Rust Core, FFI, and the Swift bridge now provide a shared Codex handoff prompt for agent events.
- Rust Core, FFI, and the native SwiftUI shell now derive structured agent task drafts with category, priority, status, prompt, and related targets.
- Confirmed native agent task drafts can now be appended to workspace `tasks.md` through Rust Core and FFI writeback.
- Rust Core, FFI, and the native SwiftUI shell now expose workspace `tasks.md` rows as structured local tasks.
- Native SwiftUI now includes a local Task Center in the sidebar and a per-workspace task section in the detail panel.
- Native Task Center and workspace task rows can now mark tasks complete or deferred after explicit `tasks.md` write confirmation.
- Rust Core, FFI, and native SwiftUI now generate copyable Codex handoff prompts from workspace tasks.
- Native Task Center now has persisted filters for all open tasks, high-priority tasks, agent-sourced tasks, and deferred tasks.
- Native SwiftUI now includes a macOS menu bar status item with workspace, risk, task, worktree, refresh, settings, and copy-summary actions.
- Rust Core, FFI, and the native menu bar now expose a local automation check for refresh, risk, delivery, task, worktree, and dirty-service signals, with fail-open audit logging.
- Native SwiftUI now supports persisted scheduled local automation checks with 5/15/30/60 minute intervals while Nexus is running.
- Native SwiftUI now supports optional local macOS notifications for automation checks that need review or attention.
- Native SwiftUI automation notifications now support cooldown, minimum-status, and per-signal preferences.
- Native SwiftUI now includes an Automation Action Center that turns local check signals into focus, delivery, task, worktree, and Codex handoff actions.
- Rust Core and native SwiftUI now derive and display workspace lifecycle stages from scoping through setup, development, delivery, done, blocked, and archived states.
- Native SwiftUI can now confirm lifecycle status writebacks to `workspace.md` and `STATUS.md`, backed by Rust Core, FFI, and local audit events.
- Native SwiftUI now includes an Archive workspace filter, visually muted archived cards, archived menu-bar counts, and automation checks that exclude archived workspaces from active attention signals.
- Added a fail-open `nexus-agent-event` hook helper script for local agents to append events before the socket bridge exists.
- Rust Core dashboard scans now enrich workspace activity timelines from the local JSONL audit log, with Tauri and native SwiftUI shells consuming the same activity field.
- User-visible workspace actions now append audit events for document opens, Codex handoffs, copied prompts, copied risk instructions, and copied worktree commands.
- Rust Core now emits workspace readiness checks for service scope, target branch, worktrees, branch alignment, dirty worktrees, delivery records, SQL directory presence, and blocked tasks.
- Rust Core now emits recommended workspace session actions so the UI can turn readiness checks into Codex handoffs, worktree command copies, and document follow-ups.
- Confirmed worktree setup can now create missing workspace-local `repos/<service>` worktrees from selected source repositories, with audit logging and a browser-preview command-copy fallback.
- Explicit local-write confirmation in the Tauri create-workspace flow.
- First-run onboarding can now import a shared Nexus team settings profile before the user reviews and saves local paths.
- First-run onboarding can now create an optional demo workspace using the standard local workspace skeleton.
- Branch alignment checks, filters, prompts, and UI warnings for worktrees that do not match the workspace target branch.
- Manual service input parsing for commas, spaces, new lines, semicolons, and Chinese separators when creating workspaces.
- Markdown document rendering with a preview/source toggle inside the workspace document viewer.

### Fixed

- First-run onboarding now waits for environment health checks, skips itself when the environment is ready, locks background scrolling, and exposes a clear close button.
- Document preview now opens above workspace details and closes the details drawer to avoid stacked side panels.
- Closing a document opened from workspace details now returns to the details drawer instead of dismissing both layers.

## [0.1.0-alpha] - 2026-05-26

### Added

- Initial Nexus macOS app built with Tauri, React, TailwindCSS, and Swift WidgetKit source.
- Workspace dashboard for requirement folders, branches, services, risks, activity, and worktree state.
- Native workspace scanning from configured local paths.
- In-app workspace creation based on the `ks-project-demand-workspace` layout.
- In-app Markdown document preview.
- Local path settings for workspace, source repository, and delivery document roots.
- Codex launch and copyable workspace prompts.
- Widget snapshot generation and `nexus://workspace/<workspace-folder>` deep links.
- English and Simplified Chinese README files.

[Unreleased]: https://github.com/murong171111/nexus-local-ai-workbench/compare/v0.1.0-alpha...HEAD
[0.1.0-alpha]: https://github.com/murong171111/nexus-local-ai-workbench/releases/tag/v0.1.0-alpha
