# Nexus Dual-Level Action Workbench Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn Nexus into a two-level management workbench where Board identifies the workspace needing attention, Console presents one truthful next action, and Codex receives bounded proposal or confirmed-feature handoffs.

**Architecture:** Reuse the existing evidence-driven `WorkspaceBoardLane`, `WorkspaceMainStage`, feature proposal review, and completion stores as the only sources of workflow truth. Add small presentation policies for the global shell, stage-driven Console, utility drawer, and feature execution handoff; keep composition in `RootView.swift` and demand/proposal interaction in `FeatureWorkspaceView.swift`.

**Tech Stack:** Swift 6, SwiftUI, AppKit (`NSPasteboard`, `NSWorkspace`), Swift Testing/XCTest through SwiftPM, existing Rust bridge and Markdown workspace stores.

## Global Constraints

- The only top-level spaces are `全局` and `当前项目`; `当前项目` is unavailable without a selected workspace.
- Nexus manages and presents project facts; Codex performs analysis, coding, and testing.
- Expose at most one prominent action in the main work surface.
- Use `已交接` after a copied/opened handoff; never claim live Codex execution without a real execution signal.
- Visible copy is Chinese-first and normally Chinese-only; file names, branch names, identifiers, and protocol terms remain unchanged.
- Preserve the neutral dark palette, semantic state colors, 6-8 point radii, compact typography, zero letter spacing, and SF Symbols.
- Do not introduce gradients, nested cards, dependencies, persisted layout settings, drag-and-drop, live Codex integration, or a new document format.
- Preserve the `FEATURES.draft.md` review gate: no authoritative `FEATURES.md` write before explicit user confirmation bound to current draft and feature revisions.
- Preserve evidence-driven Board classification and ordering; risk alone never changes a lane.
- Every failure surface states what happened, whether authoritative facts changed, and the next recovery action.

---

## File Map

- `native/Nexus/Sources/NexusApp/ConsoleInteractionModels.swift`: shell modes, Console stage presentation, utility panel identifiers, and one-primary-action presentation policy.
- `native/Nexus/Sources/NexusApp/WorkspaceBoardModels.swift`: Board copy, counts, completed-item cap, and presentation metadata while retaining current lane truth.
- `native/Nexus/Sources/NexusApp/AppState.swift`: successful refresh timestamp and bounded confirmed-feature execution handoff.
- `native/Nexus/Sources/NexusApp/Views/RootView.swift`: global shell, asymmetric Board, project header/stage rail/focus band, and utility drawer composition.
- `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`: stage-driven demand, handoff, proposal review, confirmed-feature development, and recovery surfaces.
- `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`: shell, Board, refresh, Console frame, utility presentation, and execution-prompt tests.
- `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`: demand/handoff/proposal/development phase and explicit revision-bound confirmation tests.

---

### Task 1: Two-Level Shell and Truthful Refresh State

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/ConsoleInteractionModels.swift`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Produces: `NexusPrimarySurface.global`, `NexusPrimarySurface.project`, `NexusPrimarySurface.isAvailable(hasSelection:)`.
- Produces: `AppState.lastWorkspaceRefreshAt: Date?`, updated only after a successful bridge refresh.
- Consumes: existing search, index, checks, settings, workspace creation, and refresh actions.

- [ ] **Step 1: Add failing shell and refresh-state tests**

Add focused tests asserting the public presentation contract:

```swift
func testPrimarySurfacesAreGlobalAndCurrentProject() {
    #expect(NexusPrimarySurface.global.label == "全局")
    #expect(NexusPrimarySurface.project.label == "当前项目")
    #expect(NexusPrimarySurface.project.isAvailable(hasSelection: false) == false)
    #expect(NexusPrimarySurface.project.isAvailable(hasSelection: true))
}

@MainActor
func testSuccessfulBridgeRefreshRecordsRefreshTime() async {
    let appState = makeAppState()
    #expect(appState.lastWorkspaceRefreshAt == nil)
    await appState.refreshFromBridge()
    #expect(appState.lastWorkspaceRefreshAt != nil)
}
```

- [ ] **Step 2: Run the focused tests and verify failure**

Run:

```bash
swift test --package-path native/Nexus --filter ModelBehaviorTests.testPrimarySurfacesAreGlobalAndCurrentProject
swift test --package-path native/Nexus --filter ModelBehaviorTests.testSuccessfulBridgeRefreshRecordsRefreshTime
```

Expected: FAIL because the new surface names and refresh timestamp do not exist.

- [ ] **Step 3: Implement the small presentation interfaces**

Move the shell mode out of the private view scope and add the refresh timestamp:

```swift
enum NexusPrimarySurface: String, CaseIterable, Identifiable {
    case global
    case project

    var id: Self { self }
    var label: String { self == .global ? "全局" : "当前项目" }

    func isAvailable(hasSelection: Bool) -> Bool {
        self == .global || hasSelection
    }
}
```

In `AppState`, add `@Published private(set) var lastWorkspaceRefreshAt: Date?` and set it to `Date()` only after `refreshFromBridge()` has successfully replaced the workspace snapshot. Leave the previous timestamp intact when refresh fails.

- [ ] **Step 4: Recompose the top command bar**

In `RootView.swift`:

- default `primarySurface` to `.global`;
- render `NEXUS`, a two-option segmented picker, search icon, overflow `Menu`, and `新建工作区`;
- open the existing search surface from the icon instead of holding a permanent field;
- move Index, Refresh, Checks, Settings, and diagnostics into the menu using existing actions;
- disable `当前项目` without a selected workspace;
- preserve selected workspace when returning to `全局`;
- trigger existing refresh behavior on activation and mutations, without adding a timer.

The menu labels are exactly `重建索引`, `立即刷新`, `运行检查`, `设置`, and `诊断` where the existing command exists.

- [ ] **Step 5: Run focused and regression tests**

Run:

```bash
swift test --package-path native/Nexus --filter ModelBehaviorTests
```

Expected: PASS with the new shell contract and existing command behavior intact.

- [ ] **Step 6: Commit the shell**

```bash
git add native/Nexus/Sources/NexusApp/ConsoleInteractionModels.swift native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Sources/NexusApp/Views/RootView.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Redesign Nexus dual-level shell"
```

---

### Task 2: Asymmetric Global Board

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/WorkspaceBoardModels.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: `WorkspaceBoardLane.lanes(for:showAllCompleted:)` without changing classification or ordering.
- Produces: Chinese-first lane copy and `WorkspaceBoardSummary(activeCount:attentionCount:lastRefreshAt:)`.
- Produces: full attention/active card accessibility labels and compact completed-row labels.

- [ ] **Step 1: Add failing Board presentation tests**

Add tests for exact lane copy, summary counts, risk independence, and completed cap:

```swift
func testBoardCopyUsesActionOrientedChineseLaneTitles() {
    #expect(WorkspaceBoardCopy.attentionTitle == "需要你处理")
    #expect(WorkspaceBoardCopy.activeTitle == "进行中")
    #expect(WorkspaceBoardCopy.completedTitle == "最近完成")
    #expect(WorkspaceBoardCopy.showAll == "查看全部")
}

func testBoardSummaryCountsActiveAndAttentionWorkspaces() {
    let lanes = WorkspaceBoardLane.lanes(for: boardFixtures, showAllCompleted: false)
    let summary = WorkspaceBoardSummary(lanes: lanes, lastRefreshAt: nil)
    #expect(summary.activeCount == lanes.attention.items.count + lanes.active.items.count)
    #expect(summary.attentionCount == lanes.attention.items.count)
}
```

Retain the existing tests proving risk alone does not move a workspace and completed items are capped at five.

- [ ] **Step 2: Run focused Board tests and verify failure**

Run:

```bash
swift test --package-path native/Nexus --filter WorkspaceBoard
```

Expected: FAIL on the new copy and summary model, while existing lane-truth tests still pass.

- [ ] **Step 3: Implement Board copy and summary without changing lane truth**

Add presentation-only values in `WorkspaceBoardModels.swift`:

```swift
struct WorkspaceBoardSummary: Equatable {
    let activeCount: Int
    let attentionCount: Int
    let lastRefreshAt: Date?

    init(lanes: WorkspaceBoardLanes, lastRefreshAt: Date?) {
        activeCount = lanes.attention.items.count + lanes.active.items.count
        attentionCount = lanes.attention.items.count
        self.lastRefreshAt = lastRefreshAt
    }
}
```

Use the repository's actual aggregate lane type name if it differs; do not create a second classification pass.

- [ ] **Step 4: Build the asymmetric Board composition**

In `RootView.swift`:

- heading: `工作区`, active count, attention count, and formatted `lastWorkspaceRefreshAt`;
- wide grid weights: attention `1.35`, active `1.0`, completed `0.64`, with readable minimum widths;
- stack vertically in attention, active, completed order when available width is insufficient;
- render attention and active items as single-button full cards;
- render completed items as compact rows, at most five unless expanded;
- make empty lanes short inline states;
- show only name, medium/high risk, branch, fine stage, concise reason, and destination;
- show confirmed feature progress only from existing confirmed feature facts.

The full-card accessibility label combines workspace name, branch, risk when present, stage, reason, and destination.

- [ ] **Step 5: Run focused Board tests**

Run:

```bash
swift test --package-path native/Nexus --filter WorkspaceBoard
swift test --package-path native/Nexus --filter Board
```

Expected: PASS; lane assignment and order remain unchanged.

- [ ] **Step 6: Commit the Board**

```bash
git add native/Nexus/Sources/NexusApp/WorkspaceBoardModels.swift native/Nexus/Sources/NexusApp/Views/RootView.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Build asymmetric global workspace board"
```

---

### Task 3: Focused Console Frame and Utility Drawer

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/ConsoleInteractionModels.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Produces: `WorkspaceConsoleUtilityPanel` cases `features`, `filesAndSQL`, `evidenceAndChecks`, `changesAndHandoffs`.
- Produces: `WorkspaceConsolePresentation` with one selected stage surface and one primary action.
- Consumes: existing `WorkspaceConsoleStageGroup`, `WorkspaceConsoleEvidenceGroups`, `WorkspaceConsoleDocumentPanel`, and summary/history views.

- [ ] **Step 1: Add failing Console presentation tests**

Add tests that define the frame contract:

```swift
func testConsoleUtilityPanelsAreChineseFirstAndClosedByDefault() {
    #expect(WorkspaceConsoleUtilityPanel.allCases.map(\.label) == [
        "功能点", "文件与 SQL", "证据与检查", "变更与交接记录"
    ])
    #expect(WorkspaceConsolePresentation.defaultUtilityPanel == nil)
}

func testConsolePresentationExposesOnePrimaryAction() {
    let presentation = WorkspaceConsolePresentation.make(for: workspaceFixture)
    #expect(presentation.primaryActions.count <= 1)
    #expect(presentation.stage == WorkspaceConsoleStageGroup(stage: workspaceFixture.mainStage()))
}
```

Update the current layout-policy test so it expects the permanent current-signals panel to be absent.

- [ ] **Step 2: Run focused tests and verify failure**

Run:

```bash
swift test --package-path native/Nexus --filter ConsoleLayout
swift test --package-path native/Nexus --filter ConsolePresentation
```

Expected: FAIL because the utility panel and stage presentation contracts do not yet exist.

- [ ] **Step 3: Implement presentation policies**

Add only presentation types, delegating all workflow facts to existing models:

```swift
enum WorkspaceConsoleUtilityPanel: String, CaseIterable, Identifiable {
    case features, filesAndSQL, evidenceAndChecks, changesAndHandoffs
    var id: Self { self }
    var label: String { /* exact Chinese labels from the test */ }
    var systemImage: String { /* list.bullet.rectangle, folder, checkmark.seal, clock.arrow.circlepath */ }
}
```

`WorkspaceConsolePresentation` must map one existing main stage to one `WorkspaceConsoleStageGroup`, a concise reason, and zero or one action descriptor. It must not hold mutable workflow state or duplicate evidence evaluation.

- [ ] **Step 4: Recompose Console into three structural regions**

In `RootView.swift`:

- project header: back button, workspace name, branch, medium/high risk; remove folder path;
- vertical stage rail: fixed 140-150 points, five existing stages, completed/current accessibility values;
- flexible main workspace: focus band plus one stage-driven surface;
- collapsed utility rail: fixed 40-44 points, icon buttons with help and accessibility labels;
- drawer: 390 points within the required 360-420 range, closed by default, no persisted preference;
- remove `WorkspaceConsoleCurrentSignals`, repeated activation explanation, permanent evidence disclosure, and `更多状态` from the main surface;
- reuse existing feature, file/SQL, evidence/check, change, and handoff views inside the drawer.

Keep the primary action visible when the drawer opens; use an overlay on narrow widths and an adjacent drawer only when sufficient width remains.

- [ ] **Step 5: Run focused Console tests**

Run:

```bash
swift test --package-path native/Nexus --filter Console
```

Expected: PASS with one main action and no permanent current-signals section.

- [ ] **Step 6: Commit the Console frame**

```bash
git add native/Nexus/Sources/NexusApp/ConsoleInteractionModels.swift native/Nexus/Sources/NexusApp/Views/RootView.swift native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Refocus project console around one action"
```

---

### Task 4: Stage-Driven Demand and Proposal Flow

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- Modify: `native/Nexus/Sources/NexusApp/ConsoleInteractionModels.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

**Interfaces:**
- Consumes: `FeatureWorkspacePresentation.Phase`, demand autosave, foreground refresh, proposal parser, and revision-bound confirmation.
- Produces: exact phase labels and one prominent action for editing, waiting, proposal-ready, invalid, and confirmed states.
- Preserves: `FEATURES.draft.md` remains non-authoritative until explicit confirmation.

- [ ] **Step 1: Add failing phase and recovery tests**

Extend the existing phase test with exact truthful copy and action cardinality:

```swift
func testFeatureWorkspaceUsesTruthfulStageCopy() {
    #expect(FeatureWorkspacePresentation.label(for: .editing) == "填写需求")
    #expect(FeatureWorkspacePresentation.label(for: .waiting) == "已交接")
    #expect(FeatureWorkspacePresentation.label(for: .proposalReady) == "审阅功能点")
    #expect(FeatureWorkspacePresentation.label(for: .proposalInvalid) == "提案需修正")
    #expect(FeatureWorkspacePresentation.label(for: .confirmed) == "开始开发")
}

func testWaitingAndInvalidStatesExplainRecoveryWithoutChangingFacts() {
    #expect(FeatureWorkspacePresentation.recovery(for: .waiting).factsChanged == false)
    #expect(FeatureWorkspacePresentation.recovery(for: .proposalInvalid).factsChanged == false)
}
```

Retain and run the existing stale-revision confirmation tests.

- [ ] **Step 2: Run the phase tests and verify failure**

Run:

```bash
swift test --package-path native/Nexus --filter FeatureWorkspacePresentation
swift test --package-path native/Nexus --filter ProposalRevision
```

Expected: FAIL on new copy/recovery metadata; existing revision tests pass.

- [ ] **Step 3: Implement phase presentation metadata**

Add computed presentation values to the existing phase enum instead of adding workflow state:

```swift
extension FeatureWorkspacePresentation.Phase {
    var label: String { /* exact Chinese phase labels */ }
    var demandIsExpanded: Bool { self == .editing }
    var proposalIsVisible: Bool { self == .proposalReady || self == .proposalInvalid }
    var showsConfirmedFeatures: Bool { self == .confirmed }
}
```

Recovery metadata must explicitly say that demand/draft facts were preserved and `FEATURES.md` was not changed.

- [ ] **Step 4: Recompose each phase in the main work surface**

In `FeatureWorkspaceView.swift`:

- editing: expanded requirement, links, materials; hide feature list without confirmed/proposed facts; primary `交给 Codex 梳理功能点`;
- waiting: collapsed demand summary, `已交接`, `继续与 Codex 讨论`, explicit proposal refresh; do not show an empty feature list;
- proposal ready: collapsed/editable demand, inline select/edit/add/remove/cancel, one `确认 N 个功能点` action;
- malformed proposal: parser error and draft path, `打开提案文件`, and one prominent `重新生成交接` action; state that `FEATURES.md` was not changed;
- confirmed: compact confirmed feature development surface rather than keeping the original large demand form open.

Continue refreshing on selected-workspace change and app foreground; reuse the explicit global refresh command for manual refresh.

- [ ] **Step 5: Run proposal workflow tests**

Run:

```bash
swift test --package-path native/Nexus --filter FeatureWorkflowTests
```

Expected: PASS, including autosave, malformed proposal, stale proposal, explicit confirmation, manual completion, and reversal tests.

- [ ] **Step 6: Commit the stage-driven flow**

```bash
git add native/Nexus/Sources/NexusApp/ConsoleInteractionModels.swift native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift
git commit -m "Make demand and proposal flow stage driven"
```

---

### Task 5: Confirmed-Feature Codex Handoff and Evidence Completion

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/NativeContextPackBuilder.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Produces: `AppState.confirmedFeatureExecutionPrompt(for:featureID:) async -> String`.
- Produces: `AppState.openConfirmedFeatureInCodex(for:featureID:) async -> Bool`.
- Consumes: selected confirmed feature, linked active tasks, service/branch/worktree snapshot, relevant changes, latest checks, delivery evidence, and source revisions.
- Preserves: current automatic completion evaluator, manual complete/reopen, and audit evidence.

- [ ] **Step 1: Add failing bounded execution-prompt tests**

Add tests proving this prompt is not the proposal contract:

```swift
@MainActor
func testConfirmedFeatureExecutionPromptIsScopedToSelectedFeature() async {
    let prompt = await appState.confirmedFeatureExecutionPrompt(
        for: workspace,
        featureID: "FEAT-002"
    )
    #expect(prompt.contains("FEAT-002"))
    #expect(prompt.contains("实现并验证已确认功能点"))
    #expect(prompt.contains("FEATURES.draft.md") == false)
    #expect(prompt.contains("Prepare a feature proposal") == false)
}

@MainActor
func testMissingConfirmedFeatureDoesNotOpenCodexOrChangeFacts() async {
    let didOpen = await appState.openConfirmedFeatureInCodex(
        for: workspace,
        featureID: "MISSING"
    )
    #expect(didOpen == false)
    #expect(appState.lastError?.contains("未找到已确认功能点") == true)
}
```

Also assert that the generated context remains within the existing maximum UTF-8 byte budget.

- [ ] **Step 2: Run execution-prompt tests and verify failure**

Run:

```bash
swift test --package-path native/Nexus --filter ConfirmedFeatureExecution
```

Expected: FAIL because the scoped execution methods do not exist.

- [ ] **Step 3: Implement the bounded execution context**

Extract the shared snapshot assembly used by `featureIntakePrompt` only where it removes actual duplication. Build `NativeContextPackInput` with:

```swift
nextAction: "实现并验证已确认功能点；完成后更新相关任务、changes.md 和交付证据。",
featureProposal: nil
```

Select the requested non-cancelled confirmed feature exactly, include only linked active tasks, relevant blockers, services/branches/worktrees, confirmed changes, latest check, delivery/SQL evidence paths, and source revisions. Do not attach all Markdown contents and do not write `FEATURES.draft.md`.

`openConfirmedFeatureInCodex` copies the bounded pack, opens the configured Codex URL, records `已交接`, and returns `true` when the payload was prepared even if the app URL must be opened manually. On a missing feature or context-write failure, leave authoritative facts untouched and expose the recovery action.

- [ ] **Step 4: Connect confirmed-feature development UI**

In the confirmed/development surface:

- choose the current incomplete confirmed feature using existing selection or first actionable feature;
- show title, linked task summary, and concise evidence state;
- expose one primary `交给 Codex 开发` action using the scoped execution method;
- keep remaining features compact with existing add/edit/manual-complete/reopen controls;
- put detailed evidence conflicts, missing/stale items, and checks in the utility drawer;
- retain aggressive automatic completion when fresh authorized evidence is sufficient.

Do not label the feature as live Codex work after handoff; use `已交接` until evidence changes.

- [ ] **Step 5: Run focused workflow and context tests**

Run:

```bash
swift test --package-path native/Nexus --filter ConfirmedFeatureExecution
swift test --package-path native/Nexus --filter FeatureCompletion
swift test --package-path native/Nexus --filter NativeContextPackBuilder
```

Expected: PASS with proposal and execution prompts remaining distinct.

- [ ] **Step 6: Commit confirmed-feature execution**

```bash
git add native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Sources/NexusApp/NativeContextPackBuilder.swift native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Add scoped Codex feature execution handoff"
```

---

### Task 6: Integration, Build, Installation, and Visual Acceptance

**Files:**
- Modify only if acceptance finds a defect in files already listed above.
- Do not add `.superpowers/brainstorm/` to source control.

**Interfaces:**
- Consumes: all tasks above.
- Produces: passing test suite, Release app bundle, installed `/Applications/Nexus.app`, and documented visual/interaction evidence.

- [ ] **Step 1: Run the complete Swift test suite**

Run:

```bash
swift test --package-path native/Nexus
```

Expected: all tests pass with zero failures. Record the exact count.

- [ ] **Step 2: Build the Release app**

Run:

```bash
native/Nexus/Scripts/build-app-bundle.sh --arch arm64 --output native/Nexus/build/Release/Nexus.app
```

Expected: `native/Nexus/build/Release/Nexus.app/Contents/MacOS/Nexus` exists and is executable.

- [ ] **Step 3: Install and launch the app**

After obtaining the required filesystem/GUI approval, replace the existing local development install with the new bundle, launch `/Applications/Nexus.app`, and verify the installed executable hash matches the Release bundle executable hash.

- [ ] **Step 4: Inspect Board at wide and minimum supported widths**

Using Computer Use, capture and inspect both widths. Verify:

- stable top bar with only the approved controls;
- asymmetric wide lanes and vertical fallback;
- no overlaps or clipped Chinese copy;
- compact completed/empty states;
- whole-card navigation and required accessibility context;
- truthful counts and refresh time.

- [ ] **Step 5: Inspect Console and drawer at wide and minimum supported widths**

Verify:

- 140-150 point vertical stage rail, flexible work surface, and 40-44 point utility rail;
- header has back/name/branch/risk and no path;
- one focus action and no permanent current-signals panel;
- 360-420 point drawer behavior without obscuring the primary action;
- icon labels/help, keyboard focus order, and no text overlap.

- [ ] **Step 6: Run a real temporary-workspace acceptance flow**

Exercise this exact sequence:

1. create/select a temporary workspace;
2. enter requirement text, link, and a copied material;
3. hand off to Codex and verify Nexus says `已交接`;
4. place a valid `FEATURES.draft.md`, return to Nexus, and verify inline review;
5. edit/add/remove/select features and explicitly confirm;
6. hand one confirmed feature to Codex and verify the context excludes the proposal contract;
7. add fresh completion evidence and verify automatic evaluation updates the feature;
8. manually reopen and complete to verify reversible audit behavior;
9. inject malformed/stale evidence and verify recovery copy states whether facts changed.

- [ ] **Step 7: Fix acceptance defects with focused regression tests**

For each defect, first add one failing focused test, implement the smallest correction, rerun that test, then rerun the complete Swift suite. Do not redesign beyond the approved spec during this step.

- [ ] **Step 8: Commit verified acceptance fixes**

```bash
git add native/Nexus/Sources native/Nexus/Tests docs/superpowers/plans/2026-07-12-nexus-dual-level-action-workbench.md
git commit -m "Verify dual-level Nexus workbench"
```

Only create this commit when there are real tracked changes not already committed; otherwise leave the verified tree clean.

---

## Self-Review Record

- Spec coverage: shell, Board, Console frame, stage-driven demand/proposal flow, confirmed-feature execution, evidence completion, recovery, accessibility, tests, build, install, and visual acceptance each map to a task.
- Workflow truth: no new state machine; Board, stage, proposal, and completion models remain authoritative.
- Prompt separation: proposal intake retains `FEATURES.draft.md`; confirmed-feature execution explicitly excludes it.
- Placeholder scan: every implementation and verification step names its concrete behavior, command, and expected result.
- Type consistency: shell, summary, utility panel, presentation, and execution-handoff names are introduced before consumption; implementation may reuse an existing aggregate lane type rather than duplicate it.
- Scope control: no dependency, document format, persisted layout, live Codex process, drag-and-drop, or dashboard analytics work is included.
