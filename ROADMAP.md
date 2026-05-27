# Roadmap

This roadmap describes the next product and engineering steps for Nexus. The current Tauri app remains the preview app, but future roadmap work should move toward the native architecture documented in `docs/adr/0001-native-swiftui-rust-core.md` and `docs/native-architecture.md`.

## Architecture Direction

- Mac-first product experience: SwiftUI + AppKit.
- Portable local engine: Rust Core.
- Local searchable state: SQLite + FTS, rebuildable from workspace Markdown files.
- Apple ecosystem surfaces: WidgetKit first, iPad/iPhone companion views later.
- Current Tauri implementation: keep as working preview until the native Mac shell reaches core workflow parity.

## 0.1.x: Public Preview Hardening

- Add automated CI validation for pull requests and pushes to `main`.
- Add automated release builds for Apple Silicon and Intel macOS.
- Keep sample workspace data free of private local paths.
- Improve error messages for missing directories, invalid paths, and git failures.
- Add unit coverage for workspace parsing, creation defaults, widget snapshots, and git status mapping.
- Split the large Rust command layer by extracting reusable logic into `nexus-core`.

## 0.2.x: Native Foundation

- Extract workspace, git, document, risk, settings, and widget snapshot logic into a standalone Rust Core crate.
- Keep Tauri commands as thin wrappers around Rust Core during the transition.
- Define stable Swift/Rust DTO contracts for dashboard data, workspace documents, settings profiles, and audit events. `[started for dashboard/source scans]`
- Add a SwiftUI/AppKit Mac shell that can render sample workspace data. `[started]`
- Add native settings and path configuration in the SwiftUI shell.
- Decide and document the Swift/Rust bridge mechanism. `[started with C ABI + JSON]`

## 0.3.x: Native Workspace Operations

- Make the SwiftUI shell read real workspace data from Rust Core. `[started with optional dynamic bridge]`
- Add native Markdown document rendering in the SwiftUI shell. `[started with document bridge and text preview]`
- Add safer worktree creation from selected source repositories.
- Add branch alignment checks across services. `[done in 0.1.x preview]`
- Add workspace health checks before a development session starts.
- Add explicit confirmation flows for destructive operations.
- Add local audit logs for workspace creation and file writes.

## 0.4.x: Search And Local Index

- Add SQLite local index for workspace metadata and Markdown documents.
- Add full-text search across tasks, decisions, delivery records, SQL notes, and service scopes.
- Add timeline view for workspace activity.
- Add saved filters and pinned workspaces.

## 0.5.x: Widget And Automation

- Package the WidgetKit extension in a full Xcode target attached to the native Mac app.
- Add App Group storage for widget snapshots.
- Add menu bar quick status.
- Add optional local automation hooks for refresh, risk scans, and delivery checks.

## 0.6.x: Distribution Readiness

- Configure Apple Developer signing and notarization.
- Publish both `aarch64` and `x86_64` DMG assets, or ship a Universal Binary.
- Add native updater support backed by signed GitHub Releases.
- Add release notes automation using `CHANGELOG.md`.
- Expand first-run onboarding with team profile import and optional demo workspace creation.
- Add settings export/import for team sharing. `[done in 0.1.x preview]`

## Later

- Team profile templates for shared workspace conventions.
- Multi-root workspace groups.
- Plugin surface for non-Codex agents and alternate IDEs.
- Signed installer and update channels for stable, beta, and nightly builds.
