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
  - Native Settings can import and export the same `nexus-settings-profile-*.json` shape for small-team sharing.
  - Native Settings path rows show per-path status, directory picker/reveal actions, and environment checks for configured path status, Git availability, workspace counts, and source repository counts.
  - Native path and task actions use concise Chinese-first labels with hover help for the underlying local effect.
  - First-run onboarding can create an optional demo workspace without creating worktrees.
  - Environment health check reports configured path status and Git availability.
  - Workspace scanning works after setting local paths.
  - Native workspace handoff buttons open Finder, Terminal, and the configured Codex URL after copying context.
  - Branch alignment filters and warnings appear when a worktree branch differs from the workspace target branch.
  - Source repository scanning populates the create-workspace service picker.
  - Native create-workspace can filter scanned services, accept manual services, leave service scope pending, show the final path/branch/service summary before writing files, and show an initialization receipt after creation.
  - After native workspace creation, the app focuses the new workspace and shows the post-create next-step panel.
  - Empty workspace and empty-filter states show configured paths, environment health, Settings, New Workspace, Refresh, Environment Check, and Show all actions as applicable.
  - Native worktree setup shows target branch, missing worktree, source repository, and workspace-local write-location preflight rows before the confirmation toggle is enabled.
  - Native worktree setup refreshes the active workspace state and shows created/skipped/failed results with Finder, Codex, and local-check follow-ups.
  - Workspace detail starts with the Command Center and exposes lifecycle progress, primary-path guidance, branch/service/risk/task signals, Codex continuation, next-step routing, local check, Finder, and Terminal.
  - Codex handoff actions show the Handoff feedback panel after copying workspace, lifecycle, risk, task, automation, or agent-event context.
  - Workspace detail shows the Workflow summary with task counts, delivery status, delivery-readiness checks, task/delivery document opens, local check, and Codex handoff.
  - Task Center and workspace task rows can open the owning `tasks.md` document for source review before status changes or Codex handoff.
  - Task-level Codex actions copy task context, open the configured Codex URL, and write task handoff audit events.
  - Workflow delivery readiness can route into the confirmed lifecycle writeback sheet for entering delivery or marking the workspace done.
  - Workflow action labels are Chinese-first and include hover help for documents, checks, and Codex handoff.
  - Workspace detail shows the Risk Review summary with risk/blocker/warning counts, status document access, local check, worktree follow-up, and Codex risk prompt copy.
  - Workspace detail shows the Documents Hub and clears stale previews after switching workspaces.
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

The native SwiftUI shell writes `widget-snapshot.json` to Application Support during unsigned local development and mirrors the same payload into `group.com.ks.nexus` when the signed app has the App Group entitlement. This keeps small-team local builds usable before the final Widget Extension target is packaged.
