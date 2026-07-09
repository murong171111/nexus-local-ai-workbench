# Native Canonical Stage Evidence Design

## Context

`AppState.mainWorkflowStage(for:)` injects demand-intake status and readiness read from the real workspace. Several other production surfaces call `workspace.mainStage()` directly, including Board grouping, list summaries, menu bar handoff text, and Widget snapshots. The no-argument path does not read `需求/`, so a workspace with initialized but incomplete intake files can appear as `demand_intake` in detail and still appear as `created` elsewhere.

This is the third delivery slice of the Native M1 Truthful Workflow goal.

## Goal

Every Native surface that resolves a workspace stage must derive demand intake, scope freeze, and demand-task transfer from the same real workspace files when explicit evidence is not supplied.

## Non-Goals

- Remove explicit evidence parameters used by focused model tests.
- Redesign Board, menu bar, Widget, or workspace detail UI.
- Change the Markdown formats or parsing rules in this slice.
- Solve lifecycle, delivery-record, PR/CI, or audit-evidence truthfulness; those remain separate slices.

## Approaches Considered

### 1. Pass an AppState resolver through every surface

This makes dependencies explicit, but it changes Board grouping, scope filters, summaries, cards, Widget construction, and tests only to route data that the stage resolver can already obtain from the workspace path. It also leaves future direct callers vulnerable to the same fallback bug.

### 2. Make the default stage resolver load missing file evidence

This is the selected approach. `WorkspaceSummary.mainStage()` keeps accepting explicit evidence, but when demand evidence is absent it reads `NativeDemandIntakeStore.status`, then derives readiness, scope freeze, and task-transfer evidence from that same status. One resolver therefore protects all current and future direct callers.

### 3. Add demand evidence to WorkspaceSummary and bridge snapshots

This would make stage resolution fully value-based, but it broadens the bridge/model contract and scanner mapping for a problem already owned by Swift Native stores. It is better considered only if repeated file reads become measurable.

## Design

### Evidence resolution

At the start of `WorkspaceSummary.mainStage()`:

1. Use the caller-provided `DemandIntakeStatus` when present.
2. Otherwise attempt `NativeDemandIntakeStore.status(workspacePath:)`.
3. Derive missing `DemandIntakeReadinessEvidence`, `ScopeFreezeEvidence`, and `DemandTaskTransferPlan` from the resolved status.
4. Continue using caller-provided evidence for any value that was explicitly supplied.

The existing stage order and primary actions do not change. Only the evidence source used by the default path changes.

### Error handling

If the workspace path is missing or unreadable, the store read fails and the resolver preserves its current health-check or pending fallback. Failure never fabricates a ready demand gate.

### Performance boundary

The fallback reads five small Markdown file entries and only runs when the caller did not already provide demand evidence. No cache or new persistence layer is added. If profiling later shows repeated Board/Widget resolution is material, scanner enrichment can replace the fallback without changing stage behavior.

## Test Strategy

Build a real temporary workspace with Native stores, initialize its five demand-intake files, and scan it back into `WorkspaceSummary`. The generated intake templates are intentionally incomplete, so the canonical stage must be `demand_intake`, not `created`.

Prove that:

- `AppState.mainWorkflowStage(for:)` resolves `demand_intake` from the real files;
- direct `workspace.mainStage()` resolves the same stage and status;
- Board grouping, workspace-list blocked counts, menu bar stage text, and Widget stage fields agree with that answer;
- the full Swift suite remains green.

## Success Criteria

1. A real initialized `需求/` directory cannot appear as `created` on any tested Native surface.
2. Direct and AppState stage resolution agree on stage, status, next action, and primary evidence.
3. Explicit test evidence remains supported.
4. A failed local evidence read remains pending/review/blocked rather than ready.
