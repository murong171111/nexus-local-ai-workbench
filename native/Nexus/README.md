# Nexus Native Shell

This package is the first native macOS shell for Nexus.

The current production-preview app remains the Tauri app. This SwiftUI/AppKit package exists to grow the long-lived Mac experience in parallel while reusable workflow behavior moves into `crates/nexus-core`.

## Scope

- SwiftUI workspace navigation shell.
- AppKit-ready Mac integration boundary.
- Sample data view model that mirrors the Rust Core dashboard contract.
- Build-only validation through Swift Package Manager.

## Build

```bash
swift build --package-path native/Nexus
```

This does not produce a signed `.app` bundle yet. Packaging, signing, notarization, Widget Extension targets, and updater integration are intentionally separate later steps.

## Rust Core Bridge

The Swift package includes a `NexusBridge` target with typed DTOs that match the Rust Core dashboard JSON contract.

For local development, build the bridge library from the repository root:

```bash
npm run ffi:build
```

Then launch the native shell with `NEXUS_CORE_LIBRARY` pointing to the generated `libnexus_ffi.dylib`. If the variable is missing or the library cannot be loaded, the shell falls back to preview data.
