# Changelog

All notable changes to Nexus are documented here.

The format follows Keep a Changelog, and versions should follow semantic versioning once the project reaches a stable public release.

## [Unreleased]

### Added

- `nexus-core` Rust crate foundation for reusable git, source-repository, workspace scanning, document parsing, and risk detection logic.
- Reusable Rust Core support for settings profile export and standard workspace skeleton creation.
- SwiftUI/AppKit native Mac shell scaffold with sample workspace navigation and CI build validation.
- `nexus-ffi` C ABI + JSON bridge scaffold for Swift-callable Rust Core read-only workspace and source-repository scanning.
- Swift `NexusBridge` target with typed dashboard DTOs, preview fallback data, and optional dynamic library loading through `NEXUS_CORE_LIBRARY`.
- Rust Core and Swift/Rust bridge document-reading support for native Markdown/document preview workflows.
- Rust Core widget snapshot computation with FFI and Swift bridge support for native summary surfaces.
- Swift/Rust bridge workspace creation with an explicit confirmation contract and native Mac shell creation sheet.
- Native architecture roadmap for the SwiftUI/AppKit + Rust Core migration path.
- Public maintenance docs and GitHub collaboration templates.
- CI and release workflow definitions for future automated validation and DMG publishing.
- Core workspace model tests using the Node.js test runner.
- Distribution notes for signing, notarization, universal builds, and updater readiness.
- First-run onboarding for local path setup.
- Native source repository scanning for service selection and git state awareness.
- Service picker in the create-workspace flow, backed by scanned local repositories.
- Native environment health checks for configured paths and Git availability.
- Workspace bootstrap reports and reviewable worktree command scripts.
- Delivery-record completeness warnings when records still contain placeholder content.
- Exportable and importable Nexus team settings profiles for sharing path conventions.
- Local audit log support in Rust Core, Tauri commands, and the Swift/Rust bridge for confirmed workspace creation and settings profile exports.
- SQLite + FTS local index foundation in Rust Core, Tauri commands, and the Swift/Rust bridge for workspace Markdown, service scope, tasks, decisions, delivery records, and SQL notes.
- Explicit local-write confirmation in the Tauri create-workspace flow.
- Branch alignment checks, filters, prompts, and UI warnings for worktrees that do not match the workspace target branch.
- Manual service input parsing for commas, spaces, new lines, semicolons, and Chinese separators when creating workspaces.
- Markdown document rendering with a preview/source toggle inside the workspace document viewer.

### Fixed

- First-run onboarding now waits for environment health checks, skips itself when the environment is ready, locks background scrolling, and exposes a clear close button.
- Document preview now opens above workspace details and closes the details drawer to avoid stacked side panels.
- Closing a document opened from workspace details now returns to the details drawer instead of dismissing both layers.

## [0.1.0-alpha] - 2026-05-26

### Added

- Initial Nexus macOS app built with Tauri, React, TailwindCSS, and Swift WidgetKit source.
- Workspace dashboard for requirement folders, branches, services, risks, activity, and worktree state.
- Native workspace scanning from configured local paths.
- In-app workspace creation based on the `ks-project-demand-workspace` layout.
- In-app Markdown document preview.
- Local path settings for workspace, source repository, and delivery document roots.
- Codex launch and copyable workspace prompts.
- Widget snapshot generation and `nexus://workspace/<workspace-folder>` deep links.
- English and Simplified Chinese README files.

[Unreleased]: https://github.com/murong171111/nexus-local-ai-workbench/compare/v0.1.0-alpha...HEAD
[0.1.0-alpha]: https://github.com/murong171111/nexus-local-ai-workbench/releases/tag/v0.1.0-alpha
