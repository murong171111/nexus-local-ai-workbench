# Contributing

Thanks for helping improve Nexus.

Nexus is a local-first macOS developer workbench. Contributions should preserve that boundary: workspace data, git state, and documents should stay on the user's machine unless a feature explicitly asks for remote integration and documents the data flow.

## Development Setup

Requirements:

- macOS 12+
- Node.js 22+
- Rust toolchain
- Xcode Command Line Tools
- Full Xcode only for WidgetKit packaging work

Install dependencies:

```bash
npm ci
```

Run the app in web development mode:

```bash
npm run dev
```

Run the native Tauri app:

```bash
npm run tauri:dev
```

## Branches

Use short, focused branches:

```bash
git checkout main
git pull
git checkout -b chen/feature-name
```

For external contributors, any clear prefix is fine, such as `feature/`, `fix/`, or your username.

## Verification

Before opening a pull request, run:

```bash
npm run env:check
npm run test
npm run build
npm run widget:typecheck
```

`npm run env:check` verifies the local Node, Git, Rust, Swift, SwiftPM, and `node_modules` prerequisites before the full verification suite, with recovery guidance for missing tools.

`npm run test` also runs `npm run privacy:check`, which scans publishable text files for private local paths, private key blocks, GitHub token shapes, and secret-like assignments. You can run that check directly after changing sample data or documentation:

```bash
npm run privacy:check
```

For native changes, also run:

```bash
npm run rust:test
npm run native:build
npm run tauri:build
```

When changing release packaging, verify the built `.app` and `.dmg` manually on macOS.

## Pull Request Checklist

- The change is focused on one problem.
- User-facing behavior is reflected in `README.md` and `README.zh-CN.md` when needed.
- Release or packaging changes are reflected in `docs/distribution.md`.
- Architecture changes are reflected in `docs/architecture.md`.
- Tests or verification notes are included.
- No private local paths, business data, tokens, or workspace documents are committed.

## Local-First Safety Rules

- Reading workspace documents and git state should be safe by default.
- Creating files or workspaces should be explicit and visible to the user.
- Destructive actions such as branch deletion, worktree removal, reset, or clean must require explicit confirmation.
- New remote integrations must explain what data leaves the machine.
