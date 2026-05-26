# Architecture

Nexus is split into four layers.

## Desktop Shell

- Tauri v2 packages the macOS app.
- Rust commands provide native file, path, git status, environment health, workspace creation, source repository scanning, settings profile export, and widget snapshot capabilities.
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
2. Nexus scans the workspace root using the native `scan_workspaces` command.
3. Nexus scans the source repository root using the native `scan_source_repos` command.
4. The UI renders cards, risk alerts, service pickers, and document entry points.
5. Settings can export a team profile JSON into Application Support or import a profile selected by the user.
6. The app writes a compact WidgetKit snapshot to Application Support.
7. The WidgetKit extension reads that snapshot and opens Nexus through `nexus://` links.

## Safety Boundaries

- Read-only operations: scan Markdown files, inspect git status, preview documents.
- Confirmed local writes: create workspace folders, standard documents, settings profile exports, and widget snapshots.
- Semi-automated worktree setup: Nexus generates reviewable shell commands, but does not execute them automatically.
- Future dangerous operations such as branch deletion, worktree removal, reset, or clean should require explicit confirmation.

## Verification And Release Automation

- Unit tests cover reusable workspace model behavior under `tests/`.
- `npm run verify` runs tests, frontend build, and WidgetKit source type-checking.
- GitHub Actions define pull-request validation and tag-based release builds for Apple Silicon and Intel macOS.
- Signing, notarization, and automatic updates are intentionally documented but not enabled until Apple Developer credentials and updater signing policy are ready.
