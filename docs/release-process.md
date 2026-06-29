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
- M2 Native Local Core evidence reports `11/11 Native domains`.
- M3 distribution readiness lists only the remaining install target, WidgetKit target, signing, notarization, updater, or legacy deletion blockers.

## GitHub Release

Create and push a tag:

```bash
git tag v0.1.1
git push origin main --tags
```

The current release workflow builds the SwiftPM-backed `Nexus.app` bundle for Apple Silicon and Intel runners, optionally imports the Apple Developer certificate into a temporary keychain when certificate secrets are configured, optionally signs the app when Apple signing secrets are configured, verifies app codesign with `native/Nexus/Scripts/verify-signing-notarization.sh`, packages `nexus-native-<architecture>.dmg`, optionally signs/notarizes the DMG, verifies DMG codesign and stapled notarization evidence when Apple notarization credentials are present, writes a matching `.dmg.sha256` checksum sidecar for the final DMG, generates `nexus-native-release-manifest.json` for the manual GitHub release channel, runs `native/Nexus/Scripts/verify-release-bundle.sh` against the app bundle, DMGs, checksum sidecars, and manifest, verifies the matching `CHANGELOG.md` release notes with `native/Nexus/Scripts/verify-release-notes.sh`, and publishes those Native artifacts to the GitHub Release. The app bundle script also accepts `--widget-extension path/to/NexusWidget.appex`; once the Xcode Widget target produces a signed extension, public release validation should run `verify-release-bundle.sh --require-widget` before packaging. This keeps the release channel on the Native path while signed WidgetKit embedding, a real-credential notarized release run, and updater integration are still under M3 development.

The final public release workflow should build the Native app target for Apple Silicon and Intel, package `Nexus.app` and `Nexus.dmg`, prove signing/notarization with real Apple credentials, and publish those signed Native artifacts to the GitHub Release.

You can also run the `Release` workflow manually with a tag input.

## Release Notes And Updater Gate

Before marking a release public, fill the Release Notes Gate in `docs/native-release-notes-and-updater.md`: version/tag, Native artifacts, `.dmg.sha256` checksums, `nexus-native-release-manifest.json`, signing/notarization status, known blockers, validation summary, and rollback notes. `NativeReleasePolicyEvidence` is the Swift-side evidence model for this gate, and `verify-release-notes.sh` is the release workflow verifier for the actual GitHub Release notes.

Keep automatic updates disabled until the Updater Gate in `docs/native-release-notes-and-updater.md` is satisfied with updater signing keys, appcast metadata, user-visible update settings, and signed/notarized Native artifacts. Native Settings currently surfaces the manual GitHub release channel and `nexus-native-release-manifest.json` while keeping automatic updates disabled.

## Signing And Notarization

Public macOS distribution should use Apple Developer signing and notarization.

Recommended GitHub Secrets:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_PASSWORD`
- `APPLE_CERTIFICATE`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`

Use `native/Nexus/Scripts/import-apple-certificate.sh --help` to inspect the secret-gated certificate import path, `native/Nexus/Scripts/sign-and-notarize.sh --dry-run` to validate the local signing command path without Apple credentials, `native/Nexus/Scripts/verify-signing-notarization.sh --help` to inspect the app/DMG signing, Gatekeeper, and stapled-notarization verification path, and `native/Nexus/Scripts/verify-release-bundle.sh --help` to inspect the final app/DMG/checksum/manifest verification path. Public distribution is still blocked until signed WidgetKit embedding and a real notarized release run are verified.

## Universal Build Options

Nexus should publish Native artifacts for:

- `arm64-apple-macos`: Apple Silicon
- `x86_64-apple-macos`: Intel

A later release can add a Universal Binary if the larger artifact size is acceptable.

## Auto Update Path

Before enabling automatic updates:

- Sign and notarize releases.
- Generate updater signing keys.
- Publish stable appcast metadata or an equivalent update manifest such as `nexus-native-release-manifest.json`.
- Make update checks opt-in or clearly visible in Settings.
- Document what metadata is requested remotely.
