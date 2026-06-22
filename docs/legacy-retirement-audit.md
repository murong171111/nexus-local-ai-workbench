# Legacy Retirement Audit

This audit records the remaining legacy product surfaces and the deletion order for M3 Native Distribution Readiness.

## Current Legacy Surfaces

| Path | Current role | Native replacement evidence | Retirement state |
| --- | --- | --- | --- |
| `src` | React/Tauri preview UI and TypeScript model reference. | `native/Nexus/Sources/NexusApp`, `NativeWorkspaceScanner`, `NativeDocumentStore`, `NativeDemandIntakeStore`, `NativeSearchIndexStore`, `NativeWidgetSnapshotStore`. | Frozen reference. Delete after Native app launch, Settings, workspace detail, documents, search, task, workflow, and widget snapshot paths are validated from Swift only. |
| `src-tauri` | Tauri package, command bridge, app icons, and old DMG path. | `native/Nexus/Scripts/build-app-bundle.sh`, `native/Nexus/Packaging/Info.plist`, `.github/workflows/release.yml`, `docs/distribution.md`. | Frozen packaging reference. Delete after Native app bundle, URL scheme, signed app identity, notarization, DMG packaging, and release workflow are verified. |
| `crates` | Rust Core and FFI bridge reference for migration-era local rules. | M2 Native Local Core evidence: 10/10 Native domains in `AppState.nativeLocalCoreEvidence()`. | Frozen rule reference. Delete after Native local-core behavior has parity evidence and no Swift happy path requires `NEXUS_CORE_LIBRARY`. |

## Native Deletion Order

1. Remove Tauri release and install references from user-facing docs, package scripts, and GitHub Actions.
2. Delete `src-tauri` after the Native app bundle is signed, notarized, packaged as `Nexus.dmg`, and verified through a release dry run.
3. Delete `src` after the Native SwiftUI shell is the only supported UI path in docs, screenshots, install instructions, and release artifacts.
4. Delete `crates` after Swift local-core coverage proves every workflow gate, search/index path, audit path, widget snapshot path, and worktree setup path without loading the Rust FFI bridge.
5. Remove remaining Node/Rust package scripts after the matching directories are gone.
6. Run `git diff --check`, `npm run widget:typecheck`, and `swift test --package-path native/Nexus` before committing each deletion slice.

## Current M3 Decision

Do not delete the directories in one large commit. The Native app bundle and Native WidgetKit target now exist, but public distribution still needs signing, notarization, DMG packaging, and release dry-run evidence. Until those are present, the legacy directories stay as frozen reference material and deletion remains blocked.
