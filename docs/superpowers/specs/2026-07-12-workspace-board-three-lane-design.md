# Workspace Board Three-Lane Design

## Goal

Make Board answer two questions within a few seconds:

1. Which workspace needs attention now?
2. What is the next action for each workspace?

Replace the eight technical workflow columns with three user-facing lanes: `待处理`, `进行中`, and `已完成`.

## Non-Goals

- Do not change the underlying workflow stages or lifecycle evidence.
- Do not change Console content or actions.
- Do not add drag-and-drop; workspace state remains evidence-driven.
- Do not add new filters, dependencies, or persisted preferences.

## Lane Classification

Classification derives from the existing `WorkspaceMainStage` and workspace archive state.

### 待处理

A non-archived workspace belongs here when:

- its main-stage status is `blocked`, `pending`, or `review`; or
- it is at the created stage and requires the first explicit user action.

This lane represents blockers, confirmation, review, and initial input. Risk alone does not move a normally progressing workspace into this lane.

### 进行中

Every other non-archived workspace belongs here. This includes normal demand, development, delivery, and automatic handoff progress that does not currently require user intervention.

### 已完成

Only archived workspaces belong here. Delivery checks remain active work and therefore stay in `待处理` or `进行中` according to their stage status.

The lane shows the five most recent archived workspaces by default. When more exist, its header exposes one secondary `查看全部` action.

## Ordering

- `待处理`: blocked first, then pending, then review; ties use risk rank and newest folder first.
- `进行中`: newest folder first, then workspace name.
- `已完成`: newest folder first, capped at five unless expanded.

The implementation should reuse the existing board status priority and folder-based ordering instead of introducing timestamps or persisted sort settings.

## Header

The Board header contains only:

- `工作区`
- the active workspace count

Remove the four summary metrics and the `全部 / 需处理 / 交付 / 归档` segmented scope. Lane headers already provide the counts needed for scanning.

## Card Content

Each card keeps only:

- workspace name;
- branch name, directly below the title and truncated to one line;
- medium or high risk badge; low risk stays implicit;
- current fine-grained workflow stage;
- one concise reason;
- one next-action label.

Remove workspace folder, task count, Worktree count, service chips, and the repeated `打开控制台` label. These details remain available in Console.

The whole card remains one accessible button that selects the workspace and opens Console. The next-action label describes where Console will focus; it does not execute the action directly from Board.

## Layout

- Use three stable, equal-width lanes on a wide window.
- Stack the lanes vertically when the available width cannot preserve readable cards.
- Keep empty lanes compact with a short `暂无` state instead of a large placeholder card.
- Preserve the current dark palette, 8px-or-less corner radii, and Chinese-first copy.

## Data and Code Boundaries

Replace the stage-column board projection with a three-lane projection in `WorkspaceBoardModels.swift`. `RootView.swift` renders the projection and does not duplicate classification rules.

The expected implementation surface is limited to:

- `native/Nexus/Sources/NexusApp/WorkspaceBoardModels.swift`
- `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- focused board tests in `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

## Verification

Add focused tests for:

- lane classification for blocked, review, normal progress, created, delivery, and archived workspaces;
- lane ordering;
- the five-item completed cap and expansion;
- Chinese-first card/header copy;
- removal of the old eight-column and scope behavior.

Then run the complete Swift test suite, build the Release app, install it, and inspect Board at desktop and narrow window sizes.
