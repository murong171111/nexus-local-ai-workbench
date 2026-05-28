# Release Process

This document describes the intended release process for Nexus.

## Versioning

Before a release, update the version in:

- `package.json`
- `src-tauri/tauri.conf.json`
- `src-tauri/Cargo.toml`
- `CHANGELOG.md`

Use semantic versioning after stable release. Alpha builds can use tags like `v0.1.1-alpha`.

## Local Validation

Run:

```bash
npm ci
npm run test
npm run build
npm run widget:typecheck
npm run tauri:build
```

Open the built app and verify:

- Settings can be saved.
- First-run onboarding can import a shared Nexus settings profile and then save reviewed local paths.
- Workspace scanning works with a custom workspaces root.
- Markdown preview opens expected workspace documents.
- Workspace creation writes the standard document set.
- Widget snapshot is written to Application Support.
- `nexus://workspace/<folder>` opens the app.

## GitHub Release

Create and push a tag:

```bash
git tag v0.1.1
git push origin main --tags
```

The release workflow builds Apple Silicon and Intel DMG artifacts, then publishes them to the GitHub Release.

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

The current release workflow intentionally builds unsigned preview artifacts. Add signing only after the Apple Developer account and certificate handling policy are ready.

## Universal Build Options

Nexus currently builds separate DMG files for:

- `aarch64-apple-darwin`: Apple Silicon
- `x86_64-apple-darwin`: Intel

A later release can add a Universal Binary if the larger artifact size is acceptable.

## Auto Update Path

The recommended update path is Tauri updater plus GitHub Releases.

Before enabling it:

- Sign and notarize releases.
- Generate updater signing keys.
- Publish a stable update manifest.
- Make update checks opt-in or clearly visible in Settings.
- Document what metadata is requested remotely.
