# Nexus

Nexus is a local macOS AI development workbench for managing requirement workspaces, git worktrees, service scope, risk signals, delivery records, and Codex-oriented workflows.

It is designed for teams that work across multiple local service repositories and want a durable, document-first workflow around each requirement.

## Features

- Native macOS app built with Tauri, React, TailwindCSS, and Swift WidgetKit source.
- Workspace cards for requirement folders, branches, services, risks, activity, and worktree state.
- In-app workspace creation using the `ks-project-demand-workspace` layout.
- In-app Markdown document preview for status, service scope, branch notes, tasks, and delivery records.
- Local path settings for workspaces, source repositories, and delivery document roots.
- Native workspace scanning from the configured paths; no local Python script is required for the packaged app.
- Codex launcher and copyable prompts for continuing a workspace, checking git state, updating delivery notes, and risk analysis.
- Widget snapshot generation at `~/Library/Application Support/com.ks.nexus/widget-snapshot.json`.
- `nexus://workspace/<workspace-folder>` URL scheme for deep links from widgets or other tools.

## Installation

Download the latest `Nexus_*.dmg` from GitHub Releases, open it, and drag `Nexus.app` into Applications.

On first launch:

1. Open `Settings` in the lower-left rail.
2. Set your local paths:
   - Workspaces root, for example `~/ks_project/workspaces`
   - Source repositories root, for example `~/ks_project/source-repos`
   - Delivery documents root, for example `~/ks_project/docs`
3. Click `Save`.
4. Click the refresh button in the top bar.

## Workspace Layout

Nexus expects each requirement workspace to contain Markdown files like:

```text
<workspace>/
  AGENTS.md
  workspace.md
  STATUS.md
  services.md
  branches.md
  plan.md
  tasks.md
  decisions.md
  handoff.md
  delivery.md
  交付记录.md
  logs/
  sql/
  repos/
```

The `repos/<service>` directories are intended to be git worktrees for isolated multi-branch development.

## Local Development

Requirements:

- macOS 12+
- Node.js 22+
- Rust toolchain
- Xcode Command Line Tools for the Tauri app
- Full Xcode only if you want to compile the WidgetKit extension

Install dependencies:

```bash
npm install
```

Run the web dev server:

```bash
npm run dev
```

Run the Tauri app in development:

```bash
npm run tauri:dev
```

Build the app:

```bash
npm run tauri:build
```

Regenerate app icons:

```bash
npm run icon
```

Type-check the WidgetKit Swift source:

```bash
npm run widget:typecheck
```

## Widget Status

The main app already writes the widget snapshot and registers the `nexus://` URL scheme. The WidgetKit source lives in:

```text
widget/NexusWidget/NexusWidget.swift
```

Building and shipping the actual `.appex` requires a full Xcode project with a Widget Extension target, App Group configuration, signing, and notarization. See [widget/README.md](widget/README.md).

## Documentation

- [Architecture](docs/architecture.md)
- [Distribution](docs/distribution.md)
- [Widget implementation](widget/README.md)
- [Mac app implementation notes](docs/mac-app-implementation.md)

## License

MIT
