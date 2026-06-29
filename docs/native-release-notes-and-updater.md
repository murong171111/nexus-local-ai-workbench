# Native Release Notes And Updater Gate

This document defines the release notes and updater policy evidence required before Nexus can move from local Native distribution to a public Mac release channel.

## Release Notes Gate

Every public Native release must include release notes with:

- version/tag and release date
- native artifact names for every published architecture
- checksums for each DMG, matching the published `.dmg.sha256` sidecar assets
- signing/notarization status for the app, DMG, and WidgetKit extension
- migration and rollback notes for workspace data
- known blockers and any intentionally skipped release requirements
- validation summary for Swift tests, app launch, workspace lifecycle proof, and Widget snapshot writing
- release manifest metadata, including `nexus-native-release-manifest.json` when Native DMGs are published

The release notes must be linked from the GitHub Release before the release is marked public. If signing, notarization, WidgetKit embedding, updater metadata, or lifecycle proof is missing, the notes must call that out as a blocker rather than presenting the artifact as production ready.

The release workflow verifies `CHANGELOG.md` with `native/Nexus/Scripts/verify-release-notes.sh` before publishing. For tagged releases, the matching changelog section must name every Native DMG, every `.dmg.sha256` sidecar, `nexus-native-release-manifest.json`, signing/notarization status, known blockers, validation summary, and migration/rollback notes.

## Updater Gate

Automatic updates disabled is the default public-release posture until the updater gate is satisfied.

Do not enable automatic updates until all of the following are true:

- released DMGs are signed and notarized with real Apple Developer credentials
- the WidgetKit extension is embedded, signed, and covered by the same release validation
- updater signing keys are generated, stored outside the repository, and rotated by documented policy
- appcast metadata or an equivalent update manifest is generated from the same signed artifacts published on GitHub; the current manual channel uses `nexus-native-release-manifest.json`
- Settings exposes a user-visible update channel and update-check control; the current Native Settings status shows `Manual GitHub Release`, `Automatic updates disabled`, and `nexus-native-release-manifest.json`
- release notes document what metadata is requested remotely during update checks
- rollback instructions are tested against the previous public Native release

Until this gate passes, GitHub Releases may publish manually downloadable Native DMGs, but the app must not silently check for, download, or install updates. The Swift-side `NativeUpdateChannelStatus` keeps the current channel on `manual-github-release` with `automaticUpdatesEnabled=false`.
