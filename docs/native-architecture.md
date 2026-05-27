# Native Architecture Target

Nexus is moving toward a Mac-first native architecture while preserving the current Tauri app as the preview implementation.

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

### Rust Core

- Workspace folder discovery.
- Markdown document inventory and metadata extraction.
- Git and worktree status inspection.
- Branch alignment analysis.
- Risk detection.
- Reviewable worktree command generation.
- Standard workspace skeleton creation, including Markdown documents, SQL/log/repos folders, and bootstrap scripts.
- Settings profile validation.
- Settings profile export file naming and JSON serialization.
- Widget snapshot generation.
- Future SQLite indexing and full-text search.

### Swift/Rust Bridge

- The initial bridge uses a small C ABI with JSON request/response payloads. It is intentionally simple while the native app shape is still moving.
- `crates/nexus-ffi` currently exposes workspace scans, source-repository scans, document reads, widget snapshot computation, JSONL audit event append, SQLite/FTS index rebuild/search, and confirmed workspace creation over `nexus-core`.
- `native/Nexus/Sources/NexusBridge` owns Swift `Codable` DTOs, preview fallback data, and optional dynamic library loading through `NEXUS_CORE_LIBRARY`.
- The native SwiftUI shell uses the same search bridge to rebuild/query the local index, then falls back to in-memory workspace metadata when the dynamic library is not configured.
- Native search results surface selected-result context from the current workspace model, including branch, service count, risk, and recent activity.
- The command surface should grow in this order: scan, read document, compute widget snapshot, create workspace skeleton, audit local actions, rebuild/search the local index, and produce worktree plans.
- Local write operations must include explicit confirmation in the bridge request, not only in UI copy.
- Bridge responses use explicit success/error envelopes so the native shell can show user-facing failures without guessing.

### Local Store

- SQLite database under Application Support. The first database file is `nexus-index.sqlite3`.
- FTS tables for workspace Markdown, delivery records, tasks, decisions, SQL notes, and service scopes.
- Audit log table for local writes and generated commands. The current bridge uses append-only JSONL under Application Support as the durable source that SQLite can index later.
- Rebuildable from the human-readable workspace folders.

### Widget And Companion Surfaces

- WidgetKit reads a compact snapshot from an App Group container once signing and App Group setup are ready.
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
