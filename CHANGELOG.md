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
- Native pinned workspaces with local persistence so important requirement workspaces stay at the top of the Mac shell.
- Native Settings can now be opened from the sidebar, persists configured local roots, and can save/reload or reset default paths.
- Native SwiftUI session actions are now actionable for document follow-ups and confirmed worktree setup, with visible created/skipped/failed results.
- Rust Core and the Swift/Rust bridge now support local agent event append/read flows backed by `agent-events.jsonl`.
- Native SwiftUI sidebar now shows recent agent events from the local bridge, with preview fallback data when Rust Core is not loaded.
- Native SwiftUI agent events can now be opened for full context, metadata inspection, and JSON copy.
- Added a fail-open `nexus-agent-event` hook helper script for local agents to append events before the socket bridge exists.
- Rust Core dashboard scans now enrich workspace activity timelines from the local JSONL audit log, with Tauri and native SwiftUI shells consuming the same activity field.
- User-visible workspace actions now append audit events for document opens, Codex handoffs, copied prompts, copied risk instructions, and copied worktree commands.
- Rust Core now emits workspace readiness checks for service scope, target branch, worktrees, branch alignment, dirty worktrees, delivery records, SQL directory presence, and blocked tasks.
- Rust Core now emits recommended workspace session actions so the UI can turn readiness checks into Codex handoffs, worktree command copies, and document follow-ups.
- Confirmed worktree setup can now create missing workspace-local `repos/<service>` worktrees from selected source repositories, with audit logging and a browser-preview command-copy fallback.
- Explicit local-write confirmation in the Tauri create-workspace flow.
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
