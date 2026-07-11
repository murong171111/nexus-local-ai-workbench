# Workspace Board Three-Lane Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the eight-stage workspace Board with three focused lanes and compact cards that preserve branch context.

**Architecture:** `WorkspaceBoardModels.swift` owns lane classification, ordering, and archive limiting from existing `WorkspaceMainStage` evidence. `RootView.swift` renders those lanes and keeps cards as single buttons into Console; no workflow state is mutated from Board.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, existing Nexus models and palette only.

## Global Constraints

- Keep the underlying workflow stages and Console behavior unchanged.
- Use exactly three Board lanes: `待处理`, `进行中`, and `已完成`.
- Keep branch names; remove folder, task count, Worktree count, service chips, repeated open label, metrics, and segmented scope.
- Treat only archived workspaces as completed and show five by default.
- Do not add dependencies, persisted preferences, or drag-and-drop.
- Preserve current dark styling, Chinese-first copy, accessibility, and corner radii of 8px or less.
- Do not overwrite or stage unrelated pre-existing working-tree changes.

**Execution note:** Tasks 1 and 2 must be implemented and committed atomically because replacing the Board model API makes the existing `RootView.swift` fail to compile until the UI migration lands.

---

### Task 1: Three-Lane Board Projection

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/WorkspaceBoardModels.swift:3-166`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift:514-540`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift:6283-6455`

**Interfaces:**
- Consumes: `WorkspaceSummary.isArchived`, `WorkspaceSummary.mainStage()`, `WorkflowPathStatus.boardPriority`, `RiskLevel.rank`, `WorkspaceSummary.folder`
- Produces: `WorkspaceBoardLaneID.resolve(isArchived:stage:)` and `WorkspaceBoardLane.lanes(for:showsAllCompleted:) -> [WorkspaceBoardLane]`

- [ ] **Step 1: Replace the old board behavior tests with failing three-lane tests**

Add deterministic classification assertions using explicit stages:

```swift
func testWorkspaceBoardLaneClassificationUsesAttentionProgressAndArchive() {
    func stage(_ id: WorkspaceMainStageID, _ status: WorkflowPathStatus) -> WorkspaceMainStage {
        WorkspaceMainStage(
            id: id,
            status: status,
            title: "Stage",
            reason: "Reason",
            primaryActionLabel: "Continue",
            primaryActionSystemImage: "arrow.right",
            primaryAction: .document("workspace"),
            evidence: ["workspace.md"],
            nextStageAllowed: false
        )
    }

    XCTAssertEqual(
        WorkspaceBoardLaneID.resolve(isArchived: false, stage: stage(.development, .blocked)),
        .attention
    )
    XCTAssertEqual(
        WorkspaceBoardLaneID.resolve(isArchived: false, stage: stage(.demandIntake, .review)),
        .attention
    )
    XCTAssertEqual(
        WorkspaceBoardLaneID.resolve(isArchived: false, stage: stage(.created, .next)),
        .attention
    )
    XCTAssertEqual(
        WorkspaceBoardLaneID.resolve(isArchived: false, stage: stage(.development, .next)),
        .active
    )
    XCTAssertEqual(
        WorkspaceBoardLaneID.resolve(isArchived: true, stage: stage(.archived, .archived)),
        .completed
    )
}
```

Replace the old stage-column and scope tests with ordering and archive-cap assertions:

```swift
func testWorkspaceBoardLanesOrderProjectsAndLimitCompletedToFive() {
    let archived = (1...7).map { index in
        workspaceForWorkflowSummary(
            stage: "archived",
            id: "archive-\(index)",
            folder: String(format: "2026-07-%02d-archive", index)
        )
    }
    let limited = WorkspaceBoardLane.lanes(for: archived)
    let completed = limited.first { $0.id == .completed }
    XCTAssertEqual(limited.map(\.id), [.attention, .active, .completed])
    XCTAssertEqual(completed?.totalCount, 7)
    XCTAssertEqual(completed?.workspaces.count, 5)
    XCTAssertEqual(completed?.workspaces.first?.id, "archive-7")
    XCTAssertTrue(completed?.hasHiddenWorkspaces == true)

    let expanded = WorkspaceBoardLane.lanes(for: archived, showsAllCompleted: true)
    XCTAssertEqual(expanded.first { $0.id == .completed }?.workspaces.count, 7)
}
```

Update the model-layering assertion to forbid `WorkspaceBoardLane` and `WorkspaceBoardLaneID` in `Models.swift` instead of the removed column/scope symbols.

- [ ] **Step 2: Run the focused tests and verify they fail**

Run:

```bash
swift test --package-path native/Nexus --filter ModelBehaviorTests/testWorkspaceBoard
```

Expected: compilation fails because `WorkspaceBoardLaneID` and `WorkspaceBoardLane` do not exist.

- [ ] **Step 3: Replace stage columns and scope filters with the minimal lane model**

Replace `WorkspaceBoardColumn`, `WorkspaceBoardScope`, and `needsBoardAttention` with:

```swift
enum WorkspaceBoardLaneID: String, CaseIterable, Hashable, Identifiable {
    case attention
    case active
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: "待处理"
        case .active: "进行中"
        case .completed: "已完成"
        }
    }

    var systemImage: String {
        switch self {
        case .attention: "exclamationmark.circle"
        case .active: "arrow.right.circle"
        case .completed: "checkmark.circle"
        }
    }

    static func resolve(isArchived: Bool, stage: WorkspaceMainStage) -> Self {
        if isArchived { return .completed }
        if stage.status == .blocked || stage.status == .pending || stage.status == .review {
            return .attention
        }
        if stage.id == .created && stage.status == .next { return .attention }
        return .active
    }
}

struct WorkspaceBoardLane: Hashable, Identifiable {
    let id: WorkspaceBoardLaneID
    let workspaces: [WorkspaceSummary]
    let totalCount: Int

    var title: String { id.title }
    var systemImage: String { id.systemImage }
    var hasHiddenWorkspaces: Bool { workspaces.count < totalCount }

    static func lanes(
        for workspaces: [WorkspaceSummary],
        showsAllCompleted: Bool = false
    ) -> [WorkspaceBoardLane] {
        let grouped = Dictionary(grouping: workspaces) { workspace in
            WorkspaceBoardLaneID.resolve(
                isArchived: workspace.isArchived,
                stage: workspace.mainStage()
            )
        }

        return WorkspaceBoardLaneID.allCases.map { id in
            let sorted = (grouped[id] ?? []).sorted { lhs, rhs in
                if id == .attention {
                    let lhsPriority = lhs.mainStage().status.boardPriority
                    let rhsPriority = rhs.mainStage().status.boardPriority
                    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                    if lhs.riskLevel.rank != rhs.riskLevel.rank {
                        return lhs.riskLevel.rank < rhs.riskLevel.rank
                    }
                }
                if lhs.folder != rhs.folder { return lhs.folder > rhs.folder }
                return lhs.name < rhs.name
            }
            let visible = id == .completed && !showsAllCompleted
                ? Array(sorted.prefix(5))
                : sorted
            return WorkspaceBoardLane(id: id, workspaces: visible, totalCount: sorted.count)
        }
    }
}
```

Keep `WorkflowPathStatus.boardPriority`. Reduce `WorkspaceBoardCopy` to the copy still rendered:

```swift
struct WorkspaceBoardCopy: Hashable {
    static let title = "工作区"
    static let titleHelp = "Board"
    static let showAllCompleted = "查看全部"
    static let showRecentCompleted = "收起"

    static func activeWorkspaceCount(_ count: Int) -> String {
        "\(count) 个活跃项目"
    }
}
```

- [ ] **Step 4: Run focused tests and verify they pass**

Run:

```bash
swift test --package-path native/Nexus --filter ModelBehaviorTests/testWorkspaceBoard
```

Expected: all selected board model and copy tests pass.

- [ ] **Step 5: Commit the model projection without unrelated hunks**

Inspect first:

```bash
git diff -- native/Nexus/Sources/NexusApp/WorkspaceBoardModels.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
```

Stage only this task's hunks, verify with `git diff --cached`, then commit:

```bash
git commit -m "Simplify workspace board into three lanes"
```

### Task 2: Focused SwiftUI Board

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/Views/RootView.swift:3474-3825`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift:514-540`

**Interfaces:**
- Consumes: `WorkspaceBoardLane.lanes(for:showsAllCompleted:)`, `WorkspaceBoardCopy`, existing `WorkspaceMainStage`
- Produces: three rendered lanes and compact workspace cards; card tap still calls `appState.select(workspace)` then `openConsole()`

- [ ] **Step 1: Add failing copy assertions for the focused header and archive control**

```swift
func testWorkspaceBoardCopyStaysChineseFirstAndFocused() {
    XCTAssertEqual(WorkspaceBoardCopy.title, "工作区")
    XCTAssertEqual(WorkspaceBoardCopy.titleHelp, "Board")
    XCTAssertEqual(WorkspaceBoardCopy.activeWorkspaceCount(2), "2 个活跃项目")
    XCTAssertEqual(WorkspaceBoardCopy.showAllCompleted, "查看全部")
    XCTAssertEqual(WorkspaceBoardCopy.showRecentCompleted, "收起")
}
```

- [ ] **Step 2: Run the copy test and verify it fails before the UI edit**

Run:

```bash
swift test --package-path native/Nexus --filter ModelBehaviorTests/testWorkspaceBoardCopyStaysChineseFirstAndFocused
```

Expected: the new copy properties do not match the old Board header API.

- [ ] **Step 3: Replace Board header, scope state, and column rendering**

In `WorkspaceBoardView`:

```swift
@State private var showsAllCompleted = false

private var lanes: [WorkspaceBoardLane] {
    WorkspaceBoardLane.lanes(
        for: workspaces,
        showsAllCompleted: showsAllCompleted
    )
}
```

Remove `boardScope`, `visibleWorkspaces`, the segmented picker, metrics, and filtered reset. Render:

```swift
WorkspaceBoardHeader(activeCount: summary.activeWorkspaceCount)
Divider()

if workspaces.isEmpty {
    VStack(alignment: .leading, spacing: 14) {
        if let recoveryReceipt {
            CreatedWorkspaceVisibilityRecoveryView(
                receipt: recoveryReceipt,
                isSettingsPresented: $isSettingsPresented
            )
        }
        WorkspaceBoardEmptyState(
            reason: emptyStateReason ?? .configuredNoDirectories,
            diagnostics: appState.nativeStatusDiagnostics,
            runPrimaryAction: runEmptyStatePrimaryAction
        )
    }
    .padding(18)
} else {
    ScrollView {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 12) {
                ForEach(lanes) { lane in
                    laneView(lane)
                }
            }
            VStack(alignment: .leading, spacing: 12) {
                ForEach(lanes) { lane in
                    laneView(lane)
                }
            }
        }
        .padding(18)
    }
}
```

Add the single lane factory inside `WorkspaceBoardView`:

```swift
private func laneView(_ lane: WorkspaceBoardLane) -> some View {
    WorkspaceBoardLaneView(
        lane: lane,
        showsAllCompleted: $showsAllCompleted,
        openWorkspace: { workspace in
            appState.select(workspace)
            openConsole()
        }
    )
}
```

Replace `WorkspaceBoardHeader`, `BoardMetric`, and the old column views with:

```swift
private struct WorkspaceBoardHeader: View {
    let activeCount: Int

    var body: some View {
        HStack {
            Text(WorkspaceBoardCopy.title)
                .font(.title3.weight(.semibold))
                .help(WorkspaceBoardCopy.titleHelp)
            Text(WorkspaceBoardCopy.activeWorkspaceCount(activeCount))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 18)
        .frame(height: 60)
    }
}

private struct WorkspaceBoardLaneView: View {
    let lane: WorkspaceBoardLane
    @Binding var showsAllCompleted: Bool
    let openWorkspace: (WorkspaceSummary) -> Void

    private var tone: Color {
        switch lane.id {
        case .attention: NexusPalette.warning
        case .active: NexusPalette.accent
        case .completed: NexusPalette.success
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                Image(systemName: lane.systemImage)
                    .foregroundStyle(tone)
                Text(lane.title)
                    .font(.caption.weight(.semibold))
                Text("\(lane.totalCount)")
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                Spacer()
                if lane.id == .completed && lane.totalCount > 5 {
                    Button(showsAllCompleted
                        ? WorkspaceBoardCopy.showRecentCompleted
                        : WorkspaceBoardCopy.showAllCompleted
                    ) {
                        showsAllCompleted.toggle()
                    }
                    .buttonStyle(.borderless)
                    .font(.caption)
                }
            }

            if lane.workspaces.isEmpty {
                Text("暂无")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 56)
            } else {
                ForEach(lane.workspaces) { workspace in
                    WorkspaceBoardCard(workspace: workspace) {
                        openWorkspace(workspace)
                    }
                }
            }
        }
        .padding(10)
        .frame(minWidth: 260, maxWidth: .infinity, alignment: .topLeading)
        .background(NexusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NexusPalette.border)
        }
    }
}
```

Set `emptyStateReason` to use `visibleCount: workspaces.count`. In `runEmptyStatePrimaryAction`, keep setup and create routing; the now-unreachable `.filteredNoResults` case returns without changing state.

- [ ] **Step 4: Reduce each card to the approved content**

Remove `activeTaskCount`, `worktreeSummary`, `serviceChips`, `extraServiceCount`, `BoardInfoRow`, folder display, and the repeated open label. The card body becomes:

```swift
Button(action: openConsole) {
    VStack(alignment: .leading, spacing: 8) {
        HStack(alignment: .top, spacing: 8) {
            Text(workspace.name)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer(minLength: 8)
            if workspace.riskLevel != .low {
                RiskBadge(level: workspace.riskLevel)
            }
        }

        Text(workspace.branch)
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help(workspace.branch)

        Text(stage.id.shortLabel)
            .font(.caption)
            .foregroundStyle(.secondary)

        Text(stage.reason)
            .font(.caption)
            .foregroundStyle(.secondary)
            .lineLimit(2)

        HStack {
            Text("下一步：\(stage.primaryActionLabel)")
                .font(.caption.weight(.medium))
                .foregroundStyle(NexusPalette.accent)
            Spacer()
            Image(systemName: "chevron.right")
                .foregroundStyle(NexusPalette.accent)
        }
    }
    .padding(11)
    .frame(maxWidth: .infinity, alignment: .leading)
}
.buttonStyle(.plain)
.accessibilityLabel("\(workspace.name)，分支 \(workspace.branch)，下一步 \(stage.primaryActionLabel)")
```

Keep existing palette colors, 8px card/lane radii, and the whole-card button behavior.

- [ ] **Step 5: Run focused tests and compile the SwiftUI target**

Run:

```bash
swift test --package-path native/Nexus --filter ModelBehaviorTests/testWorkspaceBoard
swift build --package-path native/Nexus
```

Expected: selected Board tests pass and `NexusNative` builds without SwiftUI type errors.

- [ ] **Step 6: Commit the focused Board UI without unrelated hunks**

Inspect and stage only Task 2 changes:

```bash
git diff -- native/Nexus/Sources/NexusApp/Views/RootView.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git diff --cached
git commit -m "Focus workspace board cards"
```

### Task 3: Regression, Release Build, and Visual Acceptance

**Files:**
- Modify only if verification finds a defect in the Task 1 or Task 2 files.

**Interfaces:**
- Consumes: completed three-lane Board implementation
- Produces: tested and installed `/Applications/Nexus.app`

- [ ] **Step 1: Run the complete Swift test suite**

Run:

```bash
swift test --package-path native/Nexus
```

Expected: all tests pass. If unrelated pre-existing tests fail, record their exact names separately and keep the focused Board tests green.

- [ ] **Step 2: Build the arm64 Release app bundle**

Run from the repository root:

```bash
native/Nexus/Scripts/build-app-bundle.sh \
  --arch arm64 \
  --output native/Nexus/build/Release/Nexus.app
```

Expected: `Built native/Nexus/build/Release/Nexus.app`.

- [ ] **Step 3: Install and verify the app bundle**

Close Nexus, replace `/Applications/Nexus.app` with the Release bundle, and compare executable hashes:

```bash
shasum -a 256 \
  native/Nexus/build/Release/Nexus.app/Contents/MacOS/Nexus \
  /Applications/Nexus.app/Contents/MacOS/Nexus
```

Expected: both SHA-256 values match.

- [ ] **Step 4: Inspect Board at wide and narrow window sizes**

Verify with the installed app:

- wide layout shows exactly three lanes without horizontal stage scrolling;
- narrow layout stacks lanes without clipped card text;
- branch names are visible and truncate safely;
- low risk is implicit, while medium/high risk remains visible;
- archived lane shows five cards and one `查看全部` control when needed;
- clicking any card opens the same selected workspace in Console;
- empty setup/create states still route correctly.

- [ ] **Step 5: Final diff audit**

Run:

```bash
git diff --check
git status --short
```

Expected: no whitespace errors; report unrelated pre-existing changes separately from the Board implementation.
