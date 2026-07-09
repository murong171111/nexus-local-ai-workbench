# Native Workspace Recognition Design

## Context

`NativeWorkspaceScanner` currently treats nearly every visible child directory under the configured workspaces root as a workspace. Native environment health separately counts child directories with a different ignore rule. A scratch folder can therefore appear as a workspace, while the board, onboarding path, and status diagnostics can disagree about the number of real workspaces.

This is the second delivery slice of the Native M1 Truthful Workflow goal.

## Goal

Workspace scanning, environment health, onboarding, and empty-state diagnostics must use one file-backed definition of a real workspace.

## Non-Goals

- Make `INDEX.md` authoritative; index rows can be stale.
- Require every standard document before a workspace can be recovered.
- Change workspace Markdown formats or add a registry database.
- Redesign the Board or Settings UI.

## Approaches Considered

### 1. Keep counting all child directories

This preserves compatibility but continues to classify scratch, export, and copied folders as workspaces. It does not satisfy truthful local state.

### 2. Share a file-backed recognizer

This is the selected approach. A visible child directory is recognized when it is not a known build/dashboard directory and contains `workspace.md` or `STATUS.md`. Either identity file is sufficient so an incomplete workspace can still be scanned and repaired.

### 3. Use `INDEX.md` as the workspace registry

This would make counting cheap, but the index is derived data and may outlive a moved or deleted directory. It remains diagnostic evidence, not the source of truth.

## Design

### Recognition rule

`NativeWorkspaceScanner` owns the rule and exposes a count operation for environment health. Its full scan and count operation both enumerate the same recognized directory list.

A directory is recognized only when:

- it is a direct, visible directory under the configured workspaces root;
- its name is not `dashboard`, `node_modules`, `target`, `dist`, `build`, or `.build`;
- `workspace.md` or `STATUS.md` exists as a regular file inside it.

The identity rule is intentionally tolerant of missing standard documents. Existing document recovery remains responsible for restoring recoverable files.

### Data flow

- Dashboard refresh maps only recognized directories into `WorkspaceSummary` values.
- Native environment health asks the scanner for the recognized directory count instead of counting arbitrary children.
- `NativeSetupReadiness`, `NativeOnboardingPath`, and `NativeStatusDiagnostics` continue consuming environment health, so their empty states automatically use the same truth as the dashboard.
- `INDEX.md` remains an independent diagnostic count used to detect stale-index mismatches.

### Errors

A missing root produces zero recognized workspaces, matching the existing scanner behavior. An unreadable existing root still throws from the full scan so the current bridge/error path can report the failure; environment health already reports path access separately.

## Test Strategy

Create a temporary workspaces root containing:

- one directory with `workspace.md`;
- one directory with only `STATUS.md`;
- one unrelated visible directory;
- one ignored `dashboard` directory.

Prove that the scanner returns only the two identity-backed workspaces and that `AppState.checkNativeEnvironment()` reports the same count. Keep the full Swift suite green.

## Success Criteria

1. Unrelated child directories never become workspace cards.
2. Environment health and dashboard scanning report the same real workspace count.
3. A recoverable workspace with either identity file remains visible.
4. Status diagnostics can still compare real directories with stale `INDEX.md` rows.
