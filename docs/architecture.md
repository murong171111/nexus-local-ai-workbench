# Architecture

Nexus currently has a Tauri preview architecture and a native target architecture.

The accepted medium-term direction is documented in `docs/adr/0001-native-swiftui-rust-core.md`: SwiftUI/AppKit for the long-lived Mac shell, Rust Core for reusable local workflow logic, SQLite/FTS for local indexing, and WidgetKit for Apple ecosystem surfaces.

The current Tauri app remains the working preview app until the native Mac shell reaches core workflow parity.

The native shell scaffold currently lives in `native/Nexus` as a Swift Package. It validates the long-lived SwiftUI/AppKit direction without changing the preview app distribution path.

The first Swift/Rust bridge lives in `crates/nexus-ffi` and `native/Nexus/Sources/NexusBridge`. It uses C ABI functions with JSON payloads for scans, document reads, widget snapshot computation, and confirmed workspace creation, with a preview fallback when no local dynamic library is configured.

## Target Native Architecture

- Native shell: SwiftUI with AppKit adapters for Mac-specific integration.
- Core engine: Rust crates for workspace scanning, git/worktree state, document/risk analysis, settings validation, widget snapshots, and future indexing.
- Local store: SQLite + FTS under Application Support, rebuildable from workspace Markdown files.
- Extension surfaces: WidgetKit, menu bar, and future iPad/iPhone companion views.
- Bridge: a small Swift/Rust contract layer with typed DTOs and explicit error codes.
- Current bridge implementation: C ABI + JSON through `nexus-ffi`, loaded by the Swift shell through `NEXUS_CORE_LIBRARY` during local development. Write operations such as workspace creation require explicit confirmation in the request payload.

## Current Preview Architecture

Nexus is currently split into four layers.

## Desktop Shell

- Tauri v2 packages the macOS app.
- Rust commands provide native file, path, environment health, and widget snapshot capabilities. Reusable workspace scanning, source repository scanning, git status, workspace creation, and settings profile export rules live in `crates/nexus-core` and are called by the Tauri command layer.
- The app registers the `nexus://` URL scheme for deep links.

## Frontend

- React renders the workspace dashboard.
- TailwindCSS provides the visual system.
- The desktop bridge in `src/desktop.ts` calls Tauri commands when running as a desktop app and uses browser fallbacks during web development.

## Workspace Model

The configured workspaces root contains one folder per requirement. Each workspace owns:

- Requirement context
- Status and tasks
- Service scope
- Branch and worktree notes
- Delivery records
- SQL and investigation logs
- `repos/<service>` git worktrees

Source repositories are read from a separate configured root. Nexus treats source repositories as worktree sources, not as the default edit targets.

## Data Flow

1. User configures paths in Settings.
2. Nexus scans the workspace root through the `scan_workspaces` command, which delegates reusable parsing and risk analysis to `nexus-core`.
3. Nexus scans the source repository root through the `scan_source_repos` command, which delegates git/source-repo inspection to `nexus-core`.
4. The UI renders cards, risk alerts, branch alignment signals, service pickers, and document entry points.
5. Settings can export a team profile JSON into Application Support or import a profile selected by the user. Export validation and file naming are owned by `nexus-core`.
6. The app writes a compact WidgetKit snapshot to Application Support.
7. The WidgetKit extension reads that snapshot and opens Nexus through `nexus://` links.

## Safety Boundaries

- Read-only operations: scan Markdown files, inspect git status, compare worktree branches with workspace target branches, preview documents.
- Confirmed local writes: create workspace folders, standard documents, settings profile exports, and widget snapshots.
- Semi-automated worktree setup: Nexus generates reviewable shell commands, but does not execute them automatically.
- Future dangerous operations such as branch deletion, worktree removal, reset, or clean should require explicit confirmation.

## Verification And Release Automation

- Unit tests cover reusable workspace model behavior under `tests/`.
- `npm run verify` runs tests, frontend build, and WidgetKit source type-checking.
- GitHub Actions define pull-request validation and tag-based release builds for Apple Silicon and Intel macOS.
- Signing, notarization, and automatic updates are intentionally documented but not enabled until Apple Developer credentials and updater signing policy are ready.

## Migration Boundary

New roadmap work should prefer Rust Core for reusable logic and SwiftUI/AppKit for new long-lived Mac UI. The Tauri app should receive only preview maintenance, bug fixes, and small features that help validate workflows before native migration.
