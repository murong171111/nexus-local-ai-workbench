# Roadmap

This roadmap describes the next product and engineering steps for Nexus. It is intentionally ordered from operational readiness to deeper product capabilities.

## 0.1.x: Public Preview Hardening

- Add automated CI validation for pull requests and pushes to `main`.
- Add automated release builds for Apple Silicon and Intel macOS.
- Keep sample workspace data free of private local paths.
- Improve error messages for missing directories, invalid paths, and git failures.
- Add unit coverage for workspace parsing, creation defaults, widget snapshots, and git status mapping.
- Split the large React and Rust entry files into feature-focused modules.

## 0.2.x: Distribution Readiness

- Configure Apple Developer signing and notarization.
- Publish both `aarch64` and `x86_64` DMG assets, or ship a Universal Binary.
- Add Tauri updater support backed by GitHub Releases.
- Add release notes automation using `CHANGELOG.md`.
- Expand first-run onboarding with directory existence checks and team profile import.
- Add settings export/import for team sharing.

## 0.3.x: Native Workspace Operations

- Add safer worktree creation from selected source repositories.
- Add branch alignment checks across services.
- Add workspace health checks before a development session starts.
- Add explicit confirmation flows for destructive operations.
- Add local audit logs for workspace creation and file writes.

## 0.4.x: Search And Local Index

- Add SQLite local index for workspace metadata and Markdown documents.
- Add full-text search across tasks, decisions, delivery records, SQL notes, and service scopes.
- Add timeline view for workspace activity.
- Add saved filters and pinned workspaces.

## 0.5.x: Widget And Automation

- Package the WidgetKit extension in a full Xcode target.
- Add App Group storage for widget snapshots.
- Add menu bar quick status.
- Add optional local automation hooks for refresh, risk scans, and delivery checks.

## Later

- Team profile templates for shared workspace conventions.
- Multi-root workspace groups.
- Plugin surface for non-Codex agents and alternate IDEs.
- Signed installer and update channels for stable, beta, and nightly builds.
