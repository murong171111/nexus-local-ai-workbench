# Native File Lifecycle Scan Design

## Context

`NativeWorkspaceScanner` reads the workspace state string from `workspace.md` or `STATUS.md`, defaults missing state to `developing`, and always emits `lifecycle: nil`. `WorkspaceSummary` then synthesizes lifecycle from target branch, service, worktree, risk, and task heuristics before it considers some explicit states. A file that says `developing` can therefore display lifecycle `setup`, and a file with no state can silently become `developing` or `done`.

This is the fourth delivery slice of the Native M1 Truthful Workflow goal.

## Goal

Native workspace scanning must construct lifecycle state from explicit Markdown evidence and surface missing or contradictory lifecycle records conservatively.

## Non-Goals

- Change the main workflow gate order; worktree and delivery gates may still block an explicitly developing lifecycle.
- Make lifecycle updates atomic across `workspace.md` and `STATUS.md`; that is a separate write-safety slice.
- Redesign lifecycle UI or change the bridge model.
- Add a JSON registry, cache, or new persistence layer.

## Approaches Considered

### 1. Keep lifecycle synthesis and adjust its precedence

Moving explicit state checks before worktree heuristics would fix one symptom, but missing state would still be fabricated and conflicting files would remain invisible.

### 2. Build a conservative lifecycle snapshot from both Markdown files

This is the selected approach. The scanner reads lifecycle values from `workspace.md` and `STATUS.md`, normalizes known aliases, and emits a `WorkspaceLifecycleSnapshot`. Missing state becomes `unknown`; conflicting normalized states become `blocked` plus a scan risk.

### 3. Add a dedicated lifecycle registry file

A new structured file would simplify parsing but introduce another source of truth and a migration problem. Existing Markdown is already the product contract and the lifecycle store writes both files.

## Design

### State sources

The scanner reads:

- `workspace.md`: `当前状态`, `状态`, or `state`.
- `STATUS.md`: `当前状态`, `状态`, or `state`.
- `STATUS.md`: `当前焦点` or `focus` for lifecycle detail.
- `STATUS.md`: `下一步` or `next action` for the recommended lifecycle action.

Known aliases normalize to the lifecycle stages already used by Native:

- `analyzing`, `analysis`, `scoping`, `scope` -> `scoping`
- `setup`, `environment` -> `setup`
- `developing`, `development`, `dev` -> `developing`
- `delivery`, `delivering` -> `delivery`
- `done`, `ready`, `completed`, `complete` -> `done`
- `blocked`, `block` -> `blocked`
- `archived`, `archive` -> `archived`

The existing Chinese aliases written or accepted by `NativeWorkspaceLifecycleStore` remain supported.

### Resolution

- If both files contain equivalent normalized states, use that state.
- If only one file contains a recognized state, use it.
- If both recognized states differ, emit state and lifecycle stage `blocked`; lifecycle detail and a risk name both source values.
- If neither file contains a state, emit state and lifecycle stage `unknown`; do not default to `developing`.
- If a file contains an unsupported non-empty state, treat the lifecycle as `unknown` and include the raw value in the detail and risk.

`WorkspaceSnapshot.state` and `WorkspaceLifecycleSnapshot.stage` use the same resolved canonical state. `WorkspaceState` continues mapping `unknown` to its existing analyzing UI state, while `WorkspaceLifecycle` keeps the explicit `unknown` snapshot instead of running heuristic synthesis.

### Presentation metadata

Known stages reuse the existing lifecycle labels, progress values, and default next actions. Real `当前焦点` and `下一步` values override display defaults. The lifecycle evidence document key is `status`.

### Error handling

Unreadable or empty files are treated as missing evidence. The scanner never invents a ready, developing, done, or archived lifecycle from unrelated service/task signals. Existing path-level scan errors remain unchanged.

## Test Strategy

Create three temporary identity-backed workspaces in one root:

1. `workspace.md` and `STATUS.md` both say developing, while service/worktree signals would previously synthesize setup. Assert snapshot and mapped lifecycle remain developing, and real focus/next-action text is preserved.
2. The identity file has no state. Assert snapshot state and lifecycle are unknown, not developing or done.
3. `workspace.md` says developing while `STATUS.md` says archived. Assert state/lifecycle are blocked and a conflict risk names both values.

Keep existing scanner and end-to-end lifecycle tests green.

## Success Criteria

1. Explicit file lifecycle wins over heuristic lifecycle synthesis.
2. Missing lifecycle evidence never defaults to developing or done.
3. Conflicting lifecycle files cannot silently appear healthy.
4. Main workflow gates still independently enforce demand, service, worktree, development, delivery, and archive readiness.
