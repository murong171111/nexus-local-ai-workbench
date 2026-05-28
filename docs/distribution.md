# Distribution

This document describes how to prepare Nexus for public download.

## Build Requirements

- macOS 12+
- Node.js 22+
- Rust toolchain
- Xcode Command Line Tools
- Full Xcode for WidgetKit extension packaging

## Build App

```bash
npm install
npm run test
npm run build
npm run widget:typecheck
npm run tauri:build
```

Outputs:

```text
src-tauri/target/release/bundle/macos/Nexus.app
src-tauri/target/release/bundle/dmg/Nexus_0.1.0_aarch64.dmg
```

## Release Checklist

- Ensure `src/data/workspaces.json` and `public/data/workspaces.json` contain only sample data.
- Run `npm run test`.
- Run `npm run build`.
- Run `npm run widget:typecheck`.
- Run `npm run tauri:build`.
- Open the built app and confirm:
  - First-run onboarding opens when no local settings exist.
  - Settings opens.
  - First-run onboarding can import a shared Nexus settings profile and lets the user review paths before saving.
  - First-run onboarding can create an optional demo workspace without creating worktrees.
  - Environment health check reports configured path status and Git availability.
  - Workspace scanning works after setting local paths.
  - Branch alignment filters and warnings appear when a worktree branch differs from the workspace target branch.
  - Source repository scanning populates the create-workspace service picker.
  - Settings export writes a Nexus team profile JSON, and importing that profile applies the same path conventions.
  - Creating a workspace writes `bootstrap-report.md` and `scripts/worktree-commands.sh`.
  - Markdown preview works.
  - `~/Library/Application Support/com.ks.nexus/widget-snapshot.json` is generated.
  - `nexus://workspace/<folder>` opens Nexus.

## Signing And Notarization

For broad distribution outside a trusted team, sign and notarize the app with an Apple Developer account. Tauri supports macOS signing and notarization through its bundle configuration and environment variables.

Recommended GitHub Secrets:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_PASSWORD`
- `APPLE_CERTIFICATE`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`

The current workflow builds unsigned preview artifacts. Enable signing only after the Apple Developer certificate policy is ready.

## GitHub Actions

Two workflows are provided:

- `CI`: runs tests, frontend build, widget type-check, and Rust crate checks on pull requests and pushes to `main`.
- `Release`: builds Apple Silicon and Intel DMG artifacts when a `v*` tag is pushed or the workflow is run manually.

Pushing workflow files requires a GitHub token with the `workflow` scope.

## Auto Updates

The recommended future path is Tauri updater backed by GitHub Releases. Do not enable automatic updates until signing, notarization, updater signing keys, and update metadata policy are ready.

## WidgetKit Packaging

WidgetKit requires an Xcode Widget Extension target. The Swift source is provided in `widget/NexusWidget/NexusWidget.swift`, but a distributable widget bundle requires:

- Full Xcode
- App Group, recommended: `group.com.ks.nexus`
- Widget extension target
- `.appex` copied into `Nexus.app/Contents/PlugIns`
- Signing and notarization of the final bundle
