# Native Mac Migration Implementation Plan

> **For Codex:** REQUIRED SUB-SKILL: Use executing-plans to implement this plan task-by-task.

**Goal:** Move Nexus from a Tauri-first preview app toward a SwiftUI/AppKit Mac app backed by a reusable Rust Core.

**Architecture:** Keep the current Tauri app usable while extracting domain logic into Rust crates and building a native SwiftUI shell in parallel. Promote the native shell only after it reaches core workflow parity.

**Tech Stack:** SwiftUI, AppKit, WidgetKit, Rust, SQLite/FTS, GitHub Actions, current Tauri preview app.

---

## Phase 0: Architecture Baseline

**Status:** Started in this change.

**Files:**

- Create: `docs/adr/0001-native-swiftui-rust-core.md`
- Create: `docs/native-architecture.md`
- Modify: `ROADMAP.md`
- Modify: `docs/architecture.md`
- Modify: `docs/mac-app-implementation.md`

**Verification:**

- `git diff --check`
- Confirm roadmap points to native-first future work.

## Phase 1: Rust Core Extraction

**Status:** In progress. The first slices extract git status, branch normalization, target-branch confirmation, source repository scanning, workspace scanning, Markdown table parsing, task counts, delivery-placeholder detection, risk detection, worktree command generation, settings profile export, and standard workspace skeleton creation into `crates/nexus-core`.

**Goal:** Make workspace and git logic independent from the Tauri command layer.

**Files:**

- Create: `crates/nexus-core/Cargo.toml`
- Create: `crates/nexus-core/src/lib.rs`
- Create: `crates/nexus-core/src/workspace.rs`
- Create: `crates/nexus-core/src/git.rs`
- Create: `crates/nexus-core/src/documents.rs`
- Create: `crates/nexus-core/src/risks.rs`
- Create: `crates/nexus-core/src/settings.rs`
- Modify: `src-tauri/Cargo.toml`
- Modify: `src-tauri/src/lib.rs`

**Steps:**

1. Move DTOs that represent dashboard/workspace/git/settings data into `nexus-core`.
2. Move read-only scanning and git status functions into `nexus-core`.
3. Keep Tauri commands as thin wrappers around `nexus-core`.
4. Add Rust unit tests for workspace scanning, git branch normalization, delivery placeholder detection, settings validation, settings export, and workspace skeleton creation.
5. Run `cargo test --workspace` and `npm run verify`.

## Phase 2: Native Mac Shell Scaffold

**Status:** Started. A Swift Package based SwiftUI/AppKit shell now lives under `native/Nexus` and builds independently from the Tauri preview app.

**Goal:** Add the native app entry point without replacing the current Tauri app.

**Files:**

- Create: `native/Nexus/Package.swift` or an Xcode project once full Xcode is available.
- Create: `native/Nexus/Sources/NexusApp/NexusApp.swift`
- Create: `native/Nexus/Sources/NexusApp/AppState.swift`
- Create: `native/Nexus/Sources/NexusApp/Views/WorkspaceListView.swift`
- Create: `native/Nexus/Sources/NexusApp/Views/WorkspaceDetailView.swift`
- Create: `native/Nexus/Sources/NexusApp/Views/SettingsView.swift`
- Create: `native/Nexus/Sources/NexusBridge/NexusBridge.swift`

**Steps:**

1. Add a Swift package or Xcode project that can compile a simple Mac app shell.
2. Define Swift DTOs matching the Rust Core contracts.
3. Render workspace list and detail from sample data first.
4. Add Settings screen with local path fields.
5. Add CI type-check/build step once the project can build on GitHub macOS runners.

## Phase 3: Bridge And Feature Parity Slice

**Status:** Started. `crates/nexus-ffi` now exposes a small C ABI + JSON bridge for read-only workspace scans, source repository scans, document reads, and widget snapshot computation. The Swift package has a `NexusBridge` target with DTOs and optional dynamic library loading through `NEXUS_CORE_LIBRARY`.

**Goal:** Make the native app read real workspace data.

**Files:**

- Create: `crates/nexus-ffi/Cargo.toml`
- Create: `crates/nexus-ffi/src/lib.rs`
- Modify: native bridge files under `native/Nexus/Sources/NexusBridge/`
- Modify: `docs/architecture.md`

**Steps:**

1. Choose bridge implementation: UniFFI if it fits, otherwise a small C ABI plus JSON payloads.
2. Expose read-only commands first: scan workspaces, scan source repos, read document, compute widget snapshot.
3. Render the real workspace dashboard in SwiftUI.
4. Keep destructive or write operations out of the first bridge slice.

## Phase 4: Native-First Roadmap Work

**Goal:** Complete remaining roadmap items on the new architecture.

**Order:**

1. Local SQLite + FTS index in Rust Core.
2. Native search UI in SwiftUI.
3. Timeline and pinned workspace views.
4. Safer worktree creation with confirmation and audit log.
5. WidgetKit extension target with App Group storage.
6. Menu bar quick status.
7. Signing, notarization, and update channel.

## Phase 5: Tauri Preview Retirement

**Goal:** Retire or freeze the Tauri shell after native parity.

**Exit Criteria:**

- Native app can scan workspaces and source repos.
- Native app can create workspace skeletons.
- Native app can render Markdown documents.
- Native app can show git/worktree/risk state.
- Native app can write widget snapshots.
- Native app has settings import/export or a replacement.
- Release process can build a distributable Mac app.
