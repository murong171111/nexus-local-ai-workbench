# ADR 0001: Adopt SwiftUI/AppKit + Rust Core As The Medium-Term Architecture

## Status

Accepted.

## Date

2026-05-27

## Context

Nexus started as a Tauri + React + Rust app so the product workflow could be tested quickly: workspace scanning, git/worktree visibility, local document preview, Codex handoff prompts, settings profiles, and a basic WidgetKit data contract.

The product direction is now clearer:

- Nexus is a Mac-first local AI development workbench.
- It needs deep macOS integration: Finder, Terminal, IDE, menu bar, WidgetKit, URL schemes, signing, notarization, updates, local files, and long-running local checks.
- It should later expand to iPad and iPhone, but those platforms should act as companion surfaces rather than full replacements for the Mac app.
- Workspace, git, document, risk, and index logic should not be tied to a single UI framework.

Keeping the whole product in Tauri would keep early iteration speed high, but deeper Mac integration would require more bridge code over time. Building the long-lived product directly on Apple's native stack gives the best fit for macOS and the cleanest path to WidgetKit and future Apple-platform clients.

## Decision

Nexus will move toward:

- **SwiftUI** for the primary Apple-platform UI.
- **AppKit** for Mac-specific affordances that SwiftUI does not cover well.
- **Rust Core** for local workspace scanning, git/worktree status, risk analysis, Markdown parsing, command generation, and future SQLite indexing.
- **SQLite + FTS** for the local searchable index.
- **WidgetKit** for macOS widgets.
- **Sparkle or a signed native updater path** for public Mac distribution, after signing and notarization are ready.

The current Tauri app remains the working preview app until the native Mac shell reaches feature parity.

## Consequences

### Positive

- Better long-term Mac fit for menus, keyboard shortcuts, widgets, file permissions, update UX, and system integrations.
- Shared Apple-platform UI patterns for future iPad and iPhone companion apps.
- Rust Core can remain portable and testable outside any single app shell.
- The current Tauri app can continue shipping while the native shell is built incrementally.

### Negative

- The codebase will temporarily contain two app shells.
- The team must maintain a stable contract between Swift and Rust.
- Native signing, entitlements, WidgetKit packaging, and App Group setup become first-class engineering concerns.
- Some existing React UI work will eventually be reimplemented in SwiftUI.

## Alternatives Considered

### Continue With Tauri As The Final Architecture

This is the lowest migration cost and keeps web iteration speed, but Mac-native features will increasingly live behind custom bridges. It is still useful as the current preview shell.

### Rewrite Entirely In Swift

This gives the most native Apple codebase, but git parsing, filesystem scanning, indexing, and future agent workflows are better kept in a portable core. A pure Swift rewrite would make future non-Apple surfaces harder.

### Flutter Or Electron

Both can ship cross-platform apps, but Nexus is not a generic cross-platform dashboard. It is a local Mac developer tool with deep system integration. These stacks are not the best long-term fit.

## Migration Strategy

Use a strangler migration:

1. Extract reusable domain logic from Tauri Rust commands into a standalone `nexus-core` Rust crate.
2. Define stable data contracts for workspace summaries, git rows, risks, documents, settings profiles, widget snapshots, and audit events.
3. Build a native SwiftUI Mac shell against those contracts.
4. Move feature slices one by one from the Tauri shell into the native shell.
5. Keep the Tauri shell usable until the native shell covers the core workflows.
6. Make the native shell the primary app once workspace browsing, settings, document rendering, git/risk status, workspace creation, widget snapshots, and distribution flows are covered.
