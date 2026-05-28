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
- AppKit adapters for menu bar, file panels, keyboard shortcuts, Finder/Terminal/IDE launch, and any behavior where AppKit is more reliable than SwiftUI alone.
- Explicit confirmation flows for operations that create files, create worktrees, or change local state.
- Create-workspace UX for scanning source repositories, filtering service candidates, accepting manual fallback services, showing pending scope, summarizing the local write before confirmation, verifying generated files and initial status through an initialization receipt, and guiding the user to the next safe step after creation.
- Workspace workflow summary that keeps task status, delivery-record status, document opens, local checks, and Codex handoff together instead of scattering them across unrelated sections.
- Workspace Documents Hub that maps standard workspace files to native preview/source rendering and avoids stale previews when the selected workspace changes.

### Rust Core

- Workspace folder discovery.
- Markdown document inventory and metadata extraction.
- Git and worktree status inspection.
- Branch alignment analysis.
- Risk detection.
- Workspace readiness checks for service scope, target branch, worktree readiness, branch alignment, dirty worktrees, delivery records, SQL directory presence, and blocked tasks.
- Session-action generation that turns readiness and risk signals into prioritized Codex handoffs, worktree command copies, and document follow-ups.
- Reviewable worktree command generation.
- Confirmed worktree setup that validates service names, source repositories, target branches, and existing worktree paths before running Git, then returns created/skipped/failed details for native follow-up actions.
- Standard workspace skeleton creation, including Markdown documents, SQL/log/repos folders, bootstrap scripts, and initialization receipt data for generated files and initial `STATUS.md`.
- Settings profile validation.
- Settings profile export file naming and JSON serialization.
- Widget snapshot generation.
- Agent event ingestion and local JSONL persistence for future hook helpers and in-app approval surfaces.
- Future SQLite indexing and full-text search.

### Swift/Rust Bridge

- The initial bridge uses a small C ABI with JSON request/response payloads. It is intentionally simple while the native app shape is still moving.
- `crates/nexus-ffi` currently exposes workspace scans with readiness checks, session actions, and audit-log activity enrichment, source-repository scans, document reads, widget snapshot computation, JSONL audit event append, JSONL agent event append/read, SQLite/FTS index rebuild/search, confirmed workspace creation, and confirmed worktree setup over `nexus-core`.
- `native/Nexus/Sources/NexusBridge` owns Swift `Codable` DTOs, preview fallback data, and optional dynamic library loading through `NEXUS_CORE_LIBRARY`.
- The native SwiftUI shell uses the same search bridge to rebuild/query the local index, then falls back to in-memory workspace metadata when the dynamic library is not configured.
- Native search results surface selected-result context from the current workspace model, including branch, service count, risk, and recent activity.
- The native shell stores lightweight personal UI preferences, such as local root paths, the selected search scope, and pinned workspace IDs, in `UserDefaults`. These preferences are local conveniences; Markdown workspace records and Rust Core scan output remain the product source of truth.
- The native Settings surface can import and export the same shareable Nexus settings profile shape used by the Tauri preview app, so small teams can pass path conventions without copying workspace content or code.
- The native Settings surface can show per-path readiness rows, use AppKit directory pickers and reveal actions, and run local environment checks for configured directories, write access, Git availability, workspace counts, and source repository counts after a profile is imported or paths are edited.
- The native workspace list owns first-run and empty-filter guidance: it surfaces configured local paths, the latest environment-health summary, and the primary recovery actions before users reach a workspace detail.
- The native workspace detail surface owns Mac handoff actions for Finder, Terminal, and Codex URL launches. Codex handoff copies a workspace prompt first, then opens the configured local URL.
- The native inspector owns transient Codex handoff feedback so clipboard-based context transfers have visible confirmation without writing additional workspace files.
- The native workspace detail surface now starts with a `Command Center` that explains the primary path before secondary tool actions, then separates product workflow concerns: `Workflow` owns tasks, delivery state, and delivery-readiness checks, `Risk Review` owns active risks and non-delivery readiness checks, `Documents` owns standard Markdown/script entry points, and `Activity` remains historical context.
- The `Workflow` section starts with a delivery focus card so task and delivery state resolves to one primary next action before users inspect the full readiness checklist.
- Confirmed task-status and lifecycle writebacks surface a local-write feedback card in the inspector, keeping source-document review and follow-up checks close to the write that changed local Markdown.
- The native worktree setup surface treats Git worktree creation as a preflighted local-write operation: target branch, missing services, source repositories, and workspace-local write paths must be visible before confirmation.
- Native document reads render Markdown by default, keep a source toggle for raw content, append `document.opened` audit events when the Rust Core bridge is available, and update the visible timeline immediately.
- Native widget snapshots are written by the SwiftUI shell to Application Support and mirrored to `group.com.ks.nexus` when an App Group container is available, keeping unsigned local development and signed WidgetKit packaging on the same data contract.
- Native agent event reads load recent local agent hook events into the sidebar when the Rust Core bridge is available.
- Native session actions can open follow-up documents and execute confirmed worktree setup through the Swift/Rust bridge. Worktree setup remains a confirmed local write and reports created, skipped, and failed services back to the user.
- Worktree setup result handoff copies created/skipped/failed details before opening Codex, so the follow-up session receives the exact local Git outcome instead of only the general workspace context.
- The worktree setup result surface can run a local automation check and display the resulting risk/task/worktree summary in place before the user closes the sheet.
- Worktree setup result labels are Chinese-first for small-team usage while keeping compact English hints where they help with engineering terminology.
- The native shell includes a menu bar status item for quick workspace, risk, task, worktree, refresh, settings, recent-workspace, and copy-summary actions without opening the full window first.
- Rust Core and the Swift/Rust bridge expose a local automation check that emits refresh, risk, delivery, task, worktree, and dirty-service signals for native menu bar and future background hooks.
- The native shell can schedule those local automation checks with persisted UserDefaults while the app process is running; this remains separate from LaunchAgents or system notification permissions.
- Optional UserNotifications alerts are a native-shell concern and are only sent after explicit local authorization when automation status needs review or attention.
- Automation notification preferences, including cooldown, minimum status, and signal filters, stay in local UserDefaults because they are personal attention settings rather than workspace source-of-truth records.
- The command surface should grow in this order: scan, read document, compute widget snapshot, create workspace skeleton, audit local actions, rebuild/search the local index, produce worktree plans, and execute confirmed worktree setup.
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
