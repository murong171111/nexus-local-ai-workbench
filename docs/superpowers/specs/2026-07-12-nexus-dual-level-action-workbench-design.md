# Nexus Dual-Level Action Workbench Design

## Goal

Turn Nexus into a quiet management surface for local AI-assisted delivery:

- Board answers which workspace needs attention.
- Console answers what the selected workspace needs now and why.
- Codex performs analysis, coding, and testing.
- Nexus preserves project facts, prepares handoffs, reads local evidence, and asks for confirmation before authoritative writes.

The redesign must feel materially different from the current tool-heavy dashboard. It should reduce visible controls and status repetition instead of restyling the existing layout.

## Product Position

Nexus is not a replacement for Codex and must not look like an execution environment. It is the management layer between project evidence and Codex conversations.

The top level has only two user-facing spaces:

1. `全局`: the workspace Board.
2. `当前项目`: the selected workspace Console.

Selecting a Board card opens that workspace in Console. Returning to `全局` preserves the selected workspace. `当前项目` is disabled when no workspace is selected.

## Design Principles

### One question per screen

- Board: `哪个项目需要我关注？`
- Console: `这个项目现在该做什么？`

Information that does not answer the current question moves into a drawer, menu, or secondary detail.

### One primary action

The main content exposes at most one prominent action. It may:

- prepare a handoff and open Codex;
- confirm a proposed fact change;
- run or review a local evidence check when Nexus owns that operation.

Secondary commands remain available but do not compete visually.

### Truthful automation

Nexus must not imply that Codex is running when it only knows that a handoff was opened or copied.

- Use `已交接` when Nexus has successfully opened Codex or copied a handoff.
- Use `进行中` for evidence-driven project progress.
- Do not use `Codex 处理中` without a real Codex execution signal.

### Chinese-first interface

Visible copy is Chinese-first and normally Chinese-only. English labels move to help text or accessibility descriptions. File names, branch names, code identifiers, and protocol terms remain unchanged.

## Global Shell

### Top bar

Keep only:

- `NEXUS` product mark;
- `全局` and `当前项目` segmented navigation;
- search icon;
- overflow tools menu;
- `新建工作区` command.

Remove the permanently visible `Index`, `Refresh`, `Checks`, and `Settings` buttons.

- Refresh runs automatically after workspace changes, app activation, and explicit evidence mutations.
- Search opens a command-style search surface and keeps its existing workspace/document/SQL/task scope.
- Index, checks, settings, and diagnostics live in the overflow menu.
- The overflow menu uses SF Symbols and native menu behavior.

The bar remains stable across Board and Console so switching spaces does not move global controls.

### Visual language

- Preserve the neutral dark palette; do not introduce gradients or decorative effects.
- Use semantic blue for the primary action, amber for attention/risk, green for confirmed success, and red only for destructive or failed states.
- Use 6-8 point continuous corner radii.
- Use compact work-surface typography: 22 point page titles, 18-19 point focus titles, 12-13 point card titles, and 9-11 point supporting copy.
- Keep letter spacing at zero.
- Use SF Symbols for controls and provide help text for unfamiliar icons.
- Do not use nested cards. Lanes and drawers are structural surfaces; individual workspaces and feature proposals are the repeated cards.

## Global Board

### Lane structure

Keep the existing evidence-driven three-lane classification, but change visual weighting:

| Lane | Meaning | Wide layout weight |
| --- | --- | --- |
| `需要你处理` | blocked, pending, review, or the first explicit created-stage action | 1.35 |
| `进行中` | every other non-archived workspace | 1.0 |
| `最近完成` | archived workspaces, newest first | 0.64 |

The current lane model remains authoritative. Risk alone does not change lanes.

`最近完成` shows five items at most and exposes `查看全部` when more exist. It uses compact rows rather than full cards. Empty lanes collapse to a short inline empty state instead of holding a large blank area.

At widths that cannot preserve a minimum readable card width, lanes stack vertically in attention, active, completed order.

### Board heading

Show:

- `工作区`;
- active workspace count;
- count requiring attention;
- last automatic refresh time.

Do not restore summary metric cards or segmented filters.

### Attention and active cards

Each full card contains only:

- workspace name;
- medium/high risk badge when present;
- branch name;
- fine-grained stage;
- one concise reason;
- one destination label such as `进入项目 · 审阅功能点`.

An active card may include feature completion progress only when it comes from confirmed `FEATURES.md` facts. It must not display an invented percentage or simulated Codex progress.

The whole card is one accessible button. Activating it selects the workspace and opens Console; the label does not execute the stage action directly from Board.

### Board ordering

Preserve current ordering:

- attention: blocked, pending, review, then created/next; risk and newest folder break ties;
- active: newest folder, then workspace name;
- completed: newest folder.

## Focused Console

### Page frame

Console has three structural regions:

1. a 140-150 point project stage rail;
2. the flexible action workspace;
3. a 40-44 point collapsed utility rail.

The project header above them contains:

- back to global;
- workspace name;
- branch name;
- medium/high risk badge.

Folder paths and duplicated lifecycle labels do not appear in the header.

### Stage rail

The rail displays the existing five user-facing stages:

- 已建档;
- 需求与功能点;
- 开发;
- 交付;
- 归档.

It is navigation and orientation only. It does not duplicate actions, reasons, evidence, or counters. Completed stages use a quiet green marker; the current stage uses blue.

### Focus band

The first element in the action workspace contains:

- `现在该做什么`;
- one action-oriented title;
- one concise reason;
- at most one prominent action.

Remove the permanent `当前信号` panel and the repeated sentence explaining that activation enters the next operation.

### Stage-driven work surface

Content below the focus band is selected by the current action rather than rendered as a fixed dashboard.

#### Demand editing

- Expand requirement input, links, and materials.
- Hide the feature list until confirmed facts or a proposal exist.
- Primary action: `交给 Codex 梳理功能点`.

#### Handoff completed, no proposal yet

- Collapse the original demand into a summary.
- Show a truthful `已交接` waiting state.
- Keep `继续与 Codex 讨论` available.
- Refresh proposal state when the app returns to the foreground, when the selected workspace changes, and when the user explicitly refreshes from the overflow menu.

#### Proposal ready

- Keep the original demand collapsed but editable.
- Render proposal items inline in the main workspace.
- Support select, edit, add, remove, and cancel without writing `FEATURES.md`.
- Use one confirmation action showing the selected count.
- Bind confirmation to both confirmed-feature and draft revisions.

#### Development

- Show the current confirmed feature, its linked tasks, and collected evidence.
- Primary action prepares a feature-scoped context pack and opens Codex.
- The remaining confirmed features stay in a compact list, not a second Board.

#### Delivery and archive

- Show the exact missing delivery evidence or archive gate.
- Local checks may run in Nexus when Nexus owns them; code changes still route to Codex.
- Files, SQL, branch, and audit details open in the utility drawer.

### Utility rail and drawer

The collapsed rail uses SF Symbol buttons with tooltips for:

- 功能点;
- 文件与 SQL;
- 证据与检查;
- 变更与交接记录.

Selecting a tool opens a 360-420 point right drawer over or beside the action workspace, depending on available width. The drawer does not resize fixed controls or obscure the primary action. It is closed by default and remembers no persisted preference in this iteration.

## Demand-to-Codex Flow

### 1. Describe demand

Nexus saves requirement text, links, and copied materials. It generates a task-scoped handoff rather than attaching every workspace document.

Cross-session project facts remain available through the compact context pack:

- confirmed features;
- relevant tasks;
- selected service/branch/worktree facts;
- latest relevant changes;
- latest checks and delivery facts.

### 2. Handoff to Codex

Nexus saves the draft first, generates the feature proposal contract, copies the handoff, and opens Codex. On success it records only local `已交接` presentation state.

### 3. Review proposal

Codex writes `FEATURES.draft.md`. Nexus parses it on foreground refresh and changes the work surface to inline review. Nothing enters `FEATURES.md` before explicit confirmation.

### 4. Execute confirmed features

After confirmation, Console routes each selected feature to Codex using the smallest context that preserves delivery continuity.

### 5. Evaluate completion

Nexus refreshes Git attribution, linked tasks, test receipts, document evidence, and change records. Automatic evaluation remains active and may mark an authorized feature complete when evidence is fresh and sufficient.

- Conflicting, stale, missing, or unreadable evidence prevents automatic completion.
- Users may manually complete or reopen a feature.
- Completion and reversal preserve audit evidence.

## Error and Recovery States

Every failure surface states:

1. what happened;
2. whether authoritative project facts changed;
3. the next recovery action.

### Codex produced no proposal

- Preserve demand, links, materials, and handoff state.
- Do not navigate to an empty feature list.
- Offer `继续与 Codex 讨论` and explicit proposal refresh.

### Proposal is unreadable

- Show the parser error and affected draft path.
- Do not overwrite `FEATURES.md`.
- Offer open draft and regenerate handoff actions.

### Proposal changed during review

- Reject confirmation as stale.
- Refresh the proposal and preserve no invalid selection as authoritative data.

### Completion evidence conflicts

- Keep the feature incomplete or verifying.
- List missing, stale, or conflicting evidence in the utility drawer.
- Offer a feature-scoped Codex handoff or manual confirmation where policy allows it.

## Accessibility

- Board cards remain single buttons with workspace, branch, risk, stage, reason, and destination in their accessibility label.
- Stage markers expose current/completed state without relying on color.
- Icon-only controls have help text and accessibility labels.
- Keyboard focus order follows top navigation, project navigation, primary action, work surface, then utility rail.
- All confirmation, cancellation, and destructive actions remain reachable without hover.

## Data and Code Boundaries

- Reuse `WorkspaceMainStage`, `WorkspaceBoardLane`, feature proposal review, and existing evidence models.
- Do not create a parallel workflow state machine for the redesign.
- Add only small presentation policies where a view currently duplicates state selection.
- Keep Board classification in `WorkspaceBoardModels.swift`.
- Keep feature proposal and completion truth in existing stores and models.
- Keep `RootView.swift` responsible for shell, Board, and Console composition; move only genuinely reusable or independently testable presentation sections out of it.

Expected implementation surface:

- `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- `native/Nexus/Sources/NexusApp/WorkspaceBoardModels.swift`
- existing focused presentation/model tests

No dependency, persisted layout setting, drag-and-drop, live Codex process integration, or new document format is required.

## Testing and Acceptance

### Focused automated tests

- Board uses the existing three evidence-driven lanes and risk independence.
- Board copy uses `需要你处理`, `进行中`, and `最近完成` without claiming live Codex execution.
- Completed cap and expansion remain correct.
- Console presentation selects exactly one stage-driven work surface.
- Handoff success maps to `已交接`, not a live-processing claim.
- Proposal-ready, malformed-proposal, confirmed-feature, development, delivery, and archive states map to the correct primary action.
- Proposal confirmation remains revision-bound and explicit.
- Accessibility labels retain the required card and action context.

### Full verification

- Run the complete Swift test suite.
- Build the Release app.
- Install and launch `/Applications/Nexus.app`.
- Inspect Board and Console in wide and minimum supported window sizes.
- Verify no text overlaps, stable lane/card dimensions, drawer behavior, keyboard focus, and whole-card navigation.
- Verify demand handoff, app foreground refresh, inline proposal review, explicit confirmation, Codex feature handoff, and completion-evidence presentation with a real temporary workspace.

## Non-Goals

- Replacing Codex conversation UI.
- Showing live Codex execution without a real integration.
- Reworking project document formats.
- Adding Board drag-and-drop or manual lane mutation.
- Adding dashboard analytics, configurable widgets, or user-defined layouts.
- Making every existing tool visible in the first viewport.
