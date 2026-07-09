# Native Canonical Stage Evidence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make every Native stage surface derive missing demand, scope, and task-transfer evidence from the same real workspace files.

**Architecture:** Keep the existing `WorkspaceSummary.mainStage(...)` API and explicit evidence parameters. When those demand-related values are absent, the resolver reads `NativeDemandIntakeStore.status(workspacePath:)` once and derives the remaining demand evidence before applying the existing stage order.

**Tech Stack:** Swift 5.9, SwiftUI, Foundation, XCTest, Swift Package Manager

## Global Constraints

- New product behavior remains Swift Native-only.
- Real `需求/*.md` files are authoritative for demand intake and scope evidence.
- Explicit evidence parameters remain supported.
- A failed evidence read never fabricates a ready gate.
- No new cache, dependency, bridge field, or persistence layer.
- Production code follows a failing-test-first cycle.

---

### Task 1: Canonical Demand Evidence Fallback

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/PrimaryWorkflowStageResolver.swift:15-142`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift:2198`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: `WorkspaceSummary.path`, optional existing `DemandIntakeStatus`, and Swift Native demand evidence resolvers.
- Produces: unchanged `WorkspaceSummary.mainStage(...) -> WorkspaceMainStage`, now file-backed when demand evidence is omitted.

- [ ] **Step 1: Write the failing real-workspace consistency test**

Add this test next to the Native workspace scanner tests:

```swift
@MainActor
func testRealDemandFilesKeepNativeStageSurfacesAligned() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-native-stage-evidence-\(UUID().uuidString)")
    let workspacesRoot = root.appendingPathComponent("workspaces")
    let sourceRoot = root.appendingPathComponent("source-repos")
    let docsRoot = root.appendingPathComponent("docs")
    let auditRoot = root.appendingPathComponent("audit")
    let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: defaultsSuite)!
    defer {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    for directory in [workspacesRoot, sourceRoot, docsRoot, auditRoot] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let created = try NativeWorkspaceCreationStore.create(
        request: CreateWorkspaceRequest(
            name: "Stage Evidence",
            folder: "2026-07-10-stage-evidence",
            workspacesRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            services: [],
            targetBranch: "",
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Tests"
        )
    )
    _ = try NativeDemandIntakeStore.initialize(
        workspacePath: created.path,
        demandName: "Stage Evidence",
        lanhuLink: "https://lanhu.example/stage-evidence",
        notes: "Keep every Native surface aligned.",
        confirmed: true,
        auditRoot: auditRoot.path,
        actor: "Nexus Tests"
    )
    let dashboard = try NativeWorkspaceScanner.scan(
        workspacesRoot: workspacesRoot.path,
        sourceReposRoot: sourceRoot.path,
        docsRoot: docsRoot.path
    )
    let workspace = try XCTUnwrap(
        dashboard.workspaces.map(WorkspaceSummary.init(snapshot:)).first
    )
    let appState = AppState(
        workspaces: [workspace],
        agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
        bridge: PreviewNexusBridge(),
        workspaceRoot: workspacesRoot.path,
        sourceReposRoot: sourceRoot.path,
        docsRoot: docsRoot.path,
        defaults: defaults
    )

    let canonicalStage = appState.mainWorkflowStage(for: workspace)
    let directStage = workspace.mainStage()
    let boardColumns = WorkspaceBoardColumn.columns(for: [workspace])
    let summary = WorkspaceListSummary(workspaces: [workspace])
    let widget = NativeWidgetSnapshotBuilder.build(
        generatedAt: "2026-07-10T00:00:00Z",
        workspacesRoot: workspacesRoot.path,
        workspaces: [workspace],
        activeWorkspaceID: workspace.id
    )

    XCTAssertEqual(canonicalStage.id, .demandIntake)
    XCTAssertEqual(directStage, canonicalStage)
    XCTAssertEqual(boardColumns.first { $0.id == .demandIntake }?.count, 1)
    XCTAssertEqual(boardColumns.first { $0.id == .created }?.count, 0)
    XCTAssertEqual(summary.blockedWorkspaceCount, 1)
    XCTAssertTrue(appState.menuBarSummary.activeStageLine?.contains(canonicalStage.answer.stageLabel) == true)
    XCTAssertEqual(widget.mainStage, canonicalStage.answer.stageLabel)
    XCTAssertEqual(widget.mainStageStatus, canonicalStage.answer.status.displayLabel)
    XCTAssertEqual(widget.mainStageNextAction, canonicalStage.answer.nextActionLabel)
    XCTAssertEqual(widget.mainStageEvidence, canonicalStage.answer.primaryEvidenceLink?.label)
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testRealDemandFilesKeepNativeStageSurfacesAligned
```

Expected: FAIL because `AppState` sees the initialized but incomplete demand archive as `demand_intake`, while direct resolution, Board, menu bar, Widget, and list counts still resolve the workspace as `created`.

- [ ] **Step 3: Resolve missing demand evidence once inside mainStage**

After the archived early return in `WorkspaceSummary.mainStage(...)`, add:

```swift
let resolvedDemandIntakeStatus = demandIntakeStatus
    ?? (try? NativeDemandIntakeStore.status(workspacePath: path))
let resolvedDemandReadiness = demandReadiness
    ?? resolvedDemandIntakeStatus.map {
        DemandIntakeReadinessEvidence.resolve(status: $0, workspace: self)
    }
let resolvedScopeFreeze = scopeFreeze
    ?? resolvedDemandIntakeStatus.map {
        ScopeFreezeEvidence.resolve(status: $0, workspace: self)
    }
let resolvedDemandTaskTransfer = demandTaskTransfer
    ?? resolvedDemandIntakeStatus.map {
        DemandTaskTransferPlan.resolve(workspace: self, status: $0)
    }
```

Use these four resolved values in:

```swift
shouldShowCreatedStage(
    demandIntakeStatus: resolvedDemandIntakeStatus,
    demandReadiness: resolvedDemandReadiness
)

Self.demandGate(
    for: self,
    status: resolvedDemandIntakeStatus,
    readiness: resolvedDemandReadiness
)

let scopeGate = resolvedScopeFreeze

if let resolvedDemandTaskTransfer, resolvedDemandTaskTransfer.hasTransferableItems {
    return WorkspaceMainStage(
        id: .development,
        status: .next,
        title: "转入执行任务 / Transfer tasks",
        reason: resolvedDemandTaskTransfer.summary,
        primaryActionLabel: "转入 tasks.md",
        primaryActionSystemImage: "arrow.down.doc",
        primaryAction: .transferDemandTasks,
        evidence: compactEvidence("需求/tasks.md", "tasks.md"),
        nextStageAllowed: false
    )
}
```

Do not change service/branch, worktree, development, delivery, archive, labels, or actions in this task.

- [ ] **Step 4: Run the targeted test and verify GREEN**

Run:

```bash
swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testRealDemandFilesKeepNativeStageSurfacesAligned
```

Expected: PASS with one test executed and zero failures.

- [ ] **Step 5: Record and verify the slice**

Add this Unreleased changelog entry:

```markdown
- Native Board, list, menu bar, Widget, and detail stage answers now resolve missing demand and scope evidence from the same real workspace files.
```

Run:

```bash
git diff --check
swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testRealDemandFilesKeepNativeStageSurfacesAligned
swift test --disable-sandbox --package-path native/Nexus
```

Expected: all commands pass and the full Swift suite reports zero failures.

- [ ] **Step 6: Commit the implementation slice**

```bash
git add CHANGELOG.md native/Nexus/Sources/NexusApp/PrimaryWorkflowStageResolver.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift docs/superpowers/plans/2026-07-10-native-canonical-stage-evidence.md
git commit -m "Unify Native stage evidence"
```
