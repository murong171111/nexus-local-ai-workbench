# Distribution

This document describes the Native Mac distribution path for Nexus.

## Build Requirements

- macOS 14+
- Xcode Command Line Tools for SwiftPM validation
- Full Xcode for the installable app target, WidgetKit extension, signing, and notarization
- Apple Developer account for broad external distribution

## Native Build

The current verified Native build is the Swift package in `native/Nexus`:

```bash
swift test --package-path native/Nexus
swift build --package-path native/Nexus
```

The package produces the `NexusNative` executable and verifies the Swift local-core, workflow evidence, Widget snapshot, and distribution readiness models. `native/Nexus/Scripts/build-app-bundle.sh` wraps that executable into a local `Nexus.app` bundle for installation checks and can embed an already-built `NexusWidget.appex` with `--widget-extension`. `native/Nexus/Scripts/package-dmg.sh` packages the app into `Nexus.dmg` for release dry runs. `native/Nexus/Scripts/sign-and-notarize.sh` signs the app or DMG and submits DMGs to Apple notarization when Developer ID credentials are available. `native/Nexus/Scripts/verify-signing-notarization.sh` verifies app/DMG codesign, Gatekeeper assessment, and stapled notarization evidence when those release credentials are present. `native/Nexus/Scripts/verify-release-bundle.sh` verifies the final app bundle, DMG checksum sidecars, and `nexus-native-release-manifest.json` before publication, with `--require-widget` for the signed WidgetKit bundle gate.

## Installable App Target

The M3 install target must produce:

```text
native/Nexus/build/Release/Nexus.app
native/Nexus/build/Release/Nexus.dmg
```

The app bundle must include:

- SwiftUI/AppKit Nexus app entry point from `native/Nexus/Sources/NexusApp`
- Native local-core stores and workflow evidence modules
- WidgetKit extension embedded under `Nexus.app/Contents/PlugIns`
- App Group entitlement for `group.com.ks.nexus`
- Signed deep-link handling for `nexus://workspace/<folder>`

## Release Checklist

- Run `swift test --package-path native/Nexus`.
- Build the Native app target once it exists.
- Verify `NativeDistributionReadinessEvidence` reports the current M3 blockers clearly in Settings.
- Confirm M1 main workflow evidence is ready.
- Confirm M2 Native Local Core evidence reports `11/11 Native domains`.
- Confirm at least one real archived workspace provides `native-lifecycle-proof.json`: archived stage, delivery evidence, ready services, no active tasks, no open risks, required evidence files with size/SHA-256 snapshots, ordered Native audit actions, and a proof export audit event with the bundle SHA-256.
- Confirm Widget snapshot writing works in Application Support and, when signed, the App Group container.
- Confirm the built WidgetKit `.appex` is embedded with `build-app-bundle.sh --widget-extension` and verified with `verify-release-bundle.sh --require-widget` before public distribution.
- Confirm `nexus://workspace/<folder>` opens Nexus and focuses the target workspace.
- Confirm release docs and workflows point at the Native app artifact path.
- Confirm every published Native DMG has a matching `.dmg.sha256` checksum asset.
- Confirm `nexus-native-release-manifest.json` is generated from the same final DMG and checksum assets, and that every manifest SHA-256 matches its `.dmg.sha256` sidecar.
- Confirm `native/Nexus/Scripts/verify-signing-notarization.sh` passes for signed app/DMG artifacts when Apple Developer credentials are configured.
- Confirm `native/Nexus/Scripts/verify-release-bundle.sh` passes for the app bundle, DMGs, checksum sidecars, and release manifest.
- Confirm `native/Nexus/Scripts/verify-release-notes.sh` passes for the tagged `CHANGELOG.md` release notes before publishing GitHub Release assets.
- Confirm `NativeReleasePolicyEvidence` reports release notes, updater default, release manifest metadata, and public-release blocker policy as ready.
- Confirm legacy preview artifacts are not published as product release assets.

## Signing And Notarization

For broad distribution outside a trusted team, sign and notarize the Native app and WidgetKit extension with an Apple Developer account.

Recommended GitHub Secrets:

- `APPLE_ID`
- `APPLE_TEAM_ID`
- `APPLE_PASSWORD`
- `APPLE_CERTIFICATE`
- `APPLE_CERTIFICATE_PASSWORD`
- `APPLE_SIGNING_IDENTITY`

The release workflow includes secret-gated certificate import, signing, and notarization steps. It imports `APPLE_CERTIFICATE` into a temporary keychain when `APPLE_CERTIFICATE_PASSWORD` is also present, signs when `APPLE_SIGNING_IDENTITY` is present, and only notarizes when `APPLE_ID`, `APPLE_TEAM_ID`, and `APPLE_PASSWORD` are present. The current repository still needs a signed WidgetKit extension target and a successful real-credential notarized release run before public distribution is considered complete.

## GitHub Actions

Two workflows are expected for M3:

- `CI`: runs Swift tests for `native/Nexus` and any remaining compatibility checks required by touched legacy reference code.
- `Release`: currently builds the SwiftPM-backed `Nexus.app` bundle from `native/Nexus`, optionally imports the Apple Developer certificate when certificate secrets are configured, optionally signs the app when Apple signing secrets are configured, verifies app codesign, packages `nexus-native-<architecture>.dmg`, optionally signs/notarizes the DMG, verifies DMG codesign and stapled notarization evidence when credentials are present, generates a matching `.dmg.sha256` checksum and `nexus-native-release-manifest.json` from the final DMG, verifies the app/DMG/checksum/manifest bundle outputs, uploads those Native artifacts to GitHub Releases, and does not publish legacy preview artifacts.

The unsigned DMG remains the local fallback when credentials are absent. The public M3 release gate requires a successful signed and notarized run with real Apple Developer credentials.

Pushing workflow files requires a GitHub token with the `workflow` scope.

## Auto Updates

Release notes and updater readiness are tracked in `docs/native-release-notes-and-updater.md`.

Do not enable automatic updates until signing, notarization, updater signing keys, appcast metadata, update metadata policy, and user-visible update settings are ready. The default public-release posture remains automatic updates disabled until that gate is satisfied. Native Settings now exposes the current manual GitHub release channel, `automaticUpdatesEnabled=false`, and `nexus-native-release-manifest.json` as the release manifest name.

## WidgetKit Packaging

WidgetKit requires an Xcode Widget Extension target. The canonical Native source and metadata now live under `native/NexusWidget`, and the SwiftPM app bundle script now has a fixed embedding contract for an already-built extension:

```bash
native/Nexus/Scripts/build-app-bundle.sh \
  --output native/Nexus/build/Release/Nexus.app \
  --widget-extension path/to/NexusWidget.appex

native/Nexus/Scripts/verify-release-bundle.sh \
  --app native/Nexus/build/Release/Nexus.app \
  --require-widget
```

A distributable widget bundle still requires:

- Full Xcode
- App Group, recommended: `group.com.ks.nexus`
- Widget extension target
- `.appex` copied into `Nexus.app/Contents/PlugIns`
- Signing and notarization of the final bundle

The native SwiftUI shell writes `widget-snapshot.json` to Application Support during unsigned local development and mirrors the same payload into `group.com.ks.nexus` when the signed app has the App Group entitlement. This keeps small-team local builds usable before the final Widget Extension target is packaged.
