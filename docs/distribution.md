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

The package produces the `NexusNative` executable and verifies the Swift local-core, workflow evidence, Widget snapshot, and distribution readiness models. It is not yet a distributable `.app` bundle; M3 remains blocked until `native/Nexus/Nexus.xcodeproj` or an equivalent app target builds an installable `Nexus.app`.

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
- Confirm M2 Native Local Core evidence reports `10/10 Native domains`.
- Confirm at least one real archived workspace provides lifecycle proof: archived stage, delivery evidence, ready services, no active tasks, and no open risks.
- Confirm Widget snapshot writing works in Application Support and, when signed, the App Group container.
- Confirm `nexus://workspace/<folder>` opens Nexus and focuses the target workspace.
- Confirm release docs and workflows point at the Native app artifact path.
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

The current repository does not yet contain the final installable app target. Enable signing only after the Native app target, WidgetKit extension target, and certificate handling policy are ready.

## GitHub Actions

Two workflows are expected for M3:

- `CI`: runs Swift tests for `native/Nexus` and any remaining compatibility checks required by touched legacy reference code.
- `Release`: builds signed Native app artifacts from `native/Nexus`, packages `Nexus.app` and `Nexus.dmg`, uploads those artifacts to GitHub Releases, and does not publish legacy preview artifacts.

Pushing workflow files requires a GitHub token with the `workflow` scope.

## Auto Updates

Do not enable automatic updates until signing, notarization, updater signing keys, update metadata policy, and user-visible update settings are ready.

## WidgetKit Packaging

WidgetKit requires an Xcode Widget Extension target. The Swift source is provided in `widget/NexusWidget/NexusWidget.swift`, but a distributable widget bundle requires:

- Full Xcode
- App Group, recommended: `group.com.ks.nexus`
- Widget extension target
- `.appex` copied into `Nexus.app/Contents/PlugIns`
- Signing and notarization of the final bundle

The native SwiftUI shell writes `widget-snapshot.json` to Application Support during unsigned local development and mirrors the same payload into `group.com.ks.nexus` when the signed app has the App Group entitlement. This keeps small-team local builds usable before the final Widget Extension target is packaged.
