# Changelog

All notable changes to Nexus are documented here.

The format follows Keep a Changelog, and versions should follow semantic versioning once the project reaches a stable public release.

## [Unreleased]

### Added

- Public maintenance docs and GitHub collaboration templates.
- CI and release workflow definitions for future automated validation and DMG publishing.
- Core workspace model tests using the Node.js test runner.
- Distribution notes for signing, notarization, universal builds, and updater readiness.
- First-run onboarding for local path setup.
- Native source repository scanning for service selection and git state awareness.
- Service picker in the create-workspace flow, backed by scanned local repositories.

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
