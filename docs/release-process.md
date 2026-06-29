# Release Process

This document describes the intended Native Mac release process for Nexus.

## Versioning

Before a release, update the version in:

- `native/Nexus/Package.swift` when package metadata is introduced
- the future Native app target settings
- `CHANGELOG.md`

Use semantic versioning after stable release. Alpha builds can use tags like `v0.1.1-alpha`.

## Local Validation

Run:

```bash
swift test --package-path native/Nexus
swift build --package-path native/Nexus
```

Before publishing an installable artifact, also run the Native app target build once it exists.

Open the built app and verify:

- Settings can be saved.
- A shared Nexus settings profile can be imported and exported.
- Environment checks report configured path status, Git availability, workspace counts, and source repository counts.
- Workspace scanning uses the Native local core.
- Source repository scanning uses the Native local core.
- Worktree setup uses the Native local core and writes Native audit events.
- Markdown preview opens expected workspace documents.
- Documents Hub can recover a missing standard document only after confirmation.
- Workspace creation writes the standard document set.
- Widget snapshot is written to Application Support.
- `nexus://workspace/<folder>` opens the app and focuses the target workspace when it exists.
- M1 main workflow evidence is ready.
- M2 Native Local Core evidence reports `10/10 Native domains`.
- M3 distribution readiness lists only the remaining install target, WidgetKit target, signing, notarization, updater, or legacy deletion blockers.

## GitHub Release

Create and push a tag:

```bash
git tag v0.1.1
git push origin main --tags
```

The current release workflow builds the SwiftPM-backed `Nexus.app` bundle for Apple Silicon and Intel runners, optionally signs the app when Apple signing secrets are configured, packages `nexus-native-<architecture>.dmg`, optionally signs/notarizes the DMG, and publishes those Native artifacts to the GitHub Release. This keeps the release channel on the Native path while final certificate import policy, signed WidgetKit embedding, and updater integration are still under M3 development.

The final public release workflow should build the Native app target for Apple Silicon and Intel, package `Nexus.app` and `Nexus.dmg`, prove signing/notarization with real Apple credentials, and publish those signed Native artifacts to the GitHub Release.

You can also run the `Release` workflow manually with a tag input.

## Signing And Notarization

Public macOS distribution should use Apple Developer signing and notarization.

Recommended GitHub Secrets:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_PASSWORD`
- `APPLE_CERTIFICATE`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`

Use `native/Nexus/Scripts/sign-and-notarize.sh --dry-run` to validate the local command path without Apple credentials. Public distribution is still blocked until certificate import, signed WidgetKit embedding, and a real notarized release run are verified.

## Universal Build Options

Nexus should publish Native artifacts for:

- `arm64-apple-macos`: Apple Silicon
- `x86_64-apple-macos`: Intel

A later release can add a Universal Binary if the larger artifact size is acceptable.

## Auto Update Path

Before enabling automatic updates:

- Sign and notarize releases.
- Generate updater signing keys.
- Publish a stable update manifest.
- Make update checks opt-in or clearly visible in Settings.
- Document what metadata is requested remotely.
