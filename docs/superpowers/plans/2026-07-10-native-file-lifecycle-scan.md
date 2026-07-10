# Native File Lifecycle Scan Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Native workspace scans derive lifecycle from explicit `workspace.md` and `STATUS.md` evidence, while exposing missing, unsupported, or contradictory state conservatively.

**Architecture:** `NativeWorkspaceScanner` will resolve both Markdown state fields into one canonical state and one `WorkspaceLifecycleSnapshot`. The scanner will preserve real focus and next-action text, append lifecycle parse problems to the existing risk list, and stop `WorkspaceSummary` from invoking heuristic lifecycle synthesis for scanned workspaces.

**Tech Stack:** Swift 5.9+, Foundation, XCTest, Swift Package Manager, NexusBridge models.

## Global Constraints

- Keep `workspace.md` and `STATUS.md` as the only lifecycle sources in this slice; do not add a registry, cache, or persistence layer.
- Do not change the main workflow gate order or make lifecycle writes atomic in this slice.
- `WorkspaceSnapshot.state` and `WorkspaceLifecycleSnapshot.stage` must contain the same resolved canonical state.
- Missing lifecycle evidence must resolve to `unknown`, never `developing`, `done`, or `archived`.
- Conflicting recognized states must resolve to `blocked` and append a risk that names both source values.
- Unsupported non-empty states must resolve to `unknown` and append a risk that preserves the raw source value.
- Known English and Chinese aliases already accepted by `NativeWorkspaceLifecycleStore` must remain supported.
- Real `STATUS.md` focus and next-action values override presentation defaults; lifecycle `documentKey` is `status`.
- Preserve all existing scanner, workflow-gate, and end-to-end lifecycle behavior outside lifecycle resolution.

---

### Task 1: Resolve File-Backed Lifecycle During Native Scan

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift:93-148`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift:2216`
- Modify: `CHANGELOG.md:9`

**Interfaces:**
- Consumes: `NativeWorkspaceScanner.scan(workspacesRoot:sourceReposRoot:docsRoot:fileManager:now:)`, existing Markdown `firstValue(in:labels:)`, and `WorkspaceLifecycleSnapshot(stage:label:detail:progress:nextAction:documentKey:)`.
- Produces: a private `LifecycleResolution` value with `state: String`, `snapshot: WorkspaceLifecycleSnapshot`, and `risk: String?`; every scanned `WorkspaceSnapshot` receives its `state` and `lifecycle` from this value.

- [ ] **Step 1: Add failing model-behavior coverage for explicit, missing, conflicting, and unsupported file states**

Add this test beside `testNativeWorkspaceScannerBuildsDashboardFromLocalFiles` in `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`:

```swift
func testNativeWorkspaceScannerBuildsConservativeLifecycleFromMarkdownEvidence() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-native-lifecycle-scan-\(UUID().uuidString)")
    let explicit = root.appendingPathComponent("2026-07-10-explicit-lifecycle")
    let missing = root.appendingPathComponent("2026-07-10-missing-lifecycle")
    let conflict = root.appendingPathComponent("2026-07-10-conflicting-lifecycle")
    let unsupported = root.appendingPathComponent("2026-07-10-unsupported-lifecycle")
    defer {
        try? FileManager.default.removeItem(at: root)
    }

    for directory in [explicit, missing, conflict, unsupported] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    try """
    # Explicit Lifecycle

    - 需求名称: Explicit Lifecycle
    - 当前状态: developing
    - 目标分支: feature/lifecycle-scan
    """.write(to: explicit.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
    try """
    # STATUS

    - 状态: development
    - 当前焦点: Verify file-backed lifecycle
    - 下一步: Run lifecycle scan tests
    """.write(to: explicit.appendingPathComponent("STATUS.md"), atomically: true, encoding: .utf8)
    try """
    | 服务 | 范围 |
    | --- | --- |
    | order | confirmed |
    """.write(to: explicit.appendingPathComponent("services.md"), atomically: true, encoding: .utf8)

    try """
    # Missing Lifecycle

    - 需求名称: Missing Lifecycle
    """.write(to: missing.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)

    try """
    # Conflicting Lifecycle

    - 需求名称: Conflicting Lifecycle
    - 当前状态: developing
    """.write(to: conflict.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
    try """
    # STATUS

    - 状态: archived
    """.write(to: conflict.appendingPathComponent("STATUS.md"), atomically: true, encoding: .utf8)

    try """
    # Unsupported Lifecycle

    - 需求名称: Unsupported Lifecycle
    - 当前状态: waiting-for-magic
    """.write(to: unsupported.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)

    let dashboard = try NativeWorkspaceScanner.scan(
        workspacesRoot: root.path,
        sourceReposRoot: root.appendingPathComponent("source-repos").path,
        docsRoot: root.appendingPathComponent("docs").path,
        now: Date(timeIntervalSince1970: 0)
    )
    let snapshots = Dictionary(uniqueKeysWithValues: dashboard.workspaces.map { ($0.folder, $0) })

    let explicitSnapshot = try XCTUnwrap(snapshots[explicit.lastPathComponent])
    XCTAssertEqual(explicitSnapshot.state, "developing")
    XCTAssertEqual(explicitSnapshot.lifecycle?.stage, "developing")
    XCTAssertEqual(explicitSnapshot.lifecycle?.detail, "Verify file-backed lifecycle")
    XCTAssertEqual(explicitSnapshot.lifecycle?.nextAction, "Run lifecycle scan tests")
    XCTAssertEqual(explicitSnapshot.lifecycle?.documentKey, "status")
    XCTAssertEqual(WorkspaceSummary(snapshot: explicitSnapshot).lifecycle.stage, "developing")

    let missingSnapshot = try XCTUnwrap(snapshots[missing.lastPathComponent])
    XCTAssertEqual(missingSnapshot.state, "unknown")
    XCTAssertEqual(missingSnapshot.lifecycle?.stage, "unknown")
    XCTAssertEqual(missingSnapshot.lifecycle?.progress, 0)

    let conflictSnapshot = try XCTUnwrap(snapshots[conflict.lastPathComponent])
    XCTAssertEqual(conflictSnapshot.state, "blocked")
    XCTAssertEqual(conflictSnapshot.lifecycle?.stage, "blocked")
    XCTAssertTrue(conflictSnapshot.lifecycle?.detail.contains("developing") == true)
    XCTAssertTrue(conflictSnapshot.lifecycle?.detail.contains("archived") == true)
    XCTAssertTrue(conflictSnapshot.risks.contains {
        $0.contains("生命周期状态冲突") && $0.contains("workspace.md=developing") && $0.contains("STATUS.md=archived")
    })

    let unsupportedSnapshot = try XCTUnwrap(snapshots[unsupported.lastPathComponent])
    XCTAssertEqual(unsupportedSnapshot.state, "unknown")
    XCTAssertEqual(unsupportedSnapshot.lifecycle?.stage, "unknown")
    XCTAssertTrue(unsupportedSnapshot.lifecycle?.detail.contains("waiting-for-magic") == true)
    XCTAssertTrue(unsupportedSnapshot.risks.contains {
        $0.contains("生命周期状态无法识别") && $0.contains("workspace.md=waiting-for-magic")
    })
}
```

- [ ] **Step 2: Run the focused test and prove the current scanner fails**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testNativeWorkspaceScannerBuildsConservativeLifecycleFromMarkdownEvidence
```

Expected: FAIL because the explicit snapshot has `lifecycle == nil`, the missing snapshot defaults to `developing`, and no conflict/unsupported lifecycle risks exist.

- [ ] **Step 3: Resolve lifecycle evidence before constructing the workspace snapshot**

In `workspaceSnapshot(at:sourceRoot:fileManager:)`, resolve lifecycle before assembling risks and use it for both snapshot fields:

```swift
let lifecycle = lifecycleResolution(
    workspaceContent: workspaceContent,
    statusContent: statusContent
)
let lifecycleRisks = lifecycle.risk.map { [$0] } ?? []
let risks = riskLines(from: statusContent) + lifecycleRisks + gitRisks(
    targetBranch: targetBranch,
    services: services.confirmed,
    gitRows: gitRows
)
```

Then replace the existing state fallback and nil lifecycle:

```swift
state: lifecycle.state,
// existing targetBranch through riskCount arguments remain unchanged
lifecycle: lifecycle.snapshot,
```

- [ ] **Step 4: Add minimal lifecycle normalization, resolution, and presentation helpers**

Add the following private members inside `NativeWorkspaceScanner`, immediately before `workspaceName(folder:workspaceContent:)`:

```swift
private struct LifecycleResolution {
    let state: String
    let snapshot: WorkspaceLifecycleSnapshot
    let risk: String?
}

private static func lifecycleResolution(
    workspaceContent: String,
    statusContent: String
) -> LifecycleResolution {
    let workspaceRaw = firstValue(in: workspaceContent, labels: ["当前状态", "状态", "state"])
    let statusRaw = firstValue(in: statusContent, labels: ["当前状态", "状态", "state"])
    let focus = firstValue(in: statusContent, labels: ["当前焦点", "focus"])
    let requestedNextAction = firstValue(in: statusContent, labels: ["下一步", "next action"])
    let workspaceState = workspaceRaw.flatMap(normalizedLifecycleState)
    let statusState = statusRaw.flatMap(normalizedLifecycleState)

    let evidence = [
        workspaceRaw.map { "workspace.md=\($0)" },
        statusRaw.map { "STATUS.md=\($0)" }
    ].compactMap { $0 }.joined(separator: ", ")

    let state: String
    let detail: String
    let risk: String?

    if (workspaceRaw != nil && workspaceState == nil) || (statusRaw != nil && statusState == nil) {
        state = "unknown"
        detail = "生命周期状态无法识别: \(evidence)"
        risk = detail
    } else if let workspaceState, let statusState, workspaceState != statusState {
        state = "blocked"
        detail = "生命周期状态冲突: \(evidence)"
        risk = detail
    } else if let resolved = workspaceState ?? statusState {
        state = resolved
        detail = focus ?? "已从本地 Markdown 读取生命周期状态: \(resolved)。"
        risk = nil
    } else {
        state = "unknown"
        detail = "workspace.md 和 STATUS.md 尚未记录生命周期状态。"
        risk = nil
    }

    let presentation = lifecyclePresentation(for: state)
    return LifecycleResolution(
        state: state,
        snapshot: WorkspaceLifecycleSnapshot(
            stage: state,
            label: presentation.label,
            detail: detail,
            progress: presentation.progress,
            nextAction: requestedNextAction ?? presentation.nextAction,
            documentKey: "status"
        ),
        risk: risk
    )
}

private static func normalizedLifecycleState(_ value: String) -> String? {
    switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
    case "analyzing", "analysis", "scoping", "scope", "范围确认", "分析中":
        return "scoping"
    case "setup", "environment", "环境准备", "准备中":
        return "setup"
    case "developing", "development", "dev", "开发中":
        return "developing"
    case "delivery", "delivering", "交付", "交付整理":
        return "delivery"
    case "done", "ready", "completed", "complete", "完成", "已完成":
        return "done"
    case "blocked", "block", "阻塞":
        return "blocked"
    case "archived", "archive", "归档", "已归档":
        return "archived"
    default:
        return nil
    }
}

private static func lifecyclePresentation(
    for state: String
) -> (label: String, progress: Int, nextAction: String) {
    switch state {
    case "scoping":
        return ("范围确认 / Scoping", 15, "补齐服务范围和目标分支。")
    case "setup":
        return ("环境准备 / Setup", 35, "创建缺失 worktree 后再进入开发。")
    case "developing":
        return ("开发中 / Developing", 60, "继续编码、验证，并保持交付记录同步。")
    case "delivery":
        return ("交付整理 / Delivery", 80, "补齐交付记录、SQL、验证和风险说明。")
    case "done":
        return ("待归档 / Done", 95, "确认 PR/发布状态后归档工作区。")
    case "blocked":
        return ("阻塞 / Blocked", 25, "先处理阻塞项。")
    case "archived":
        return ("已归档 / Archived", 100, "需要再次开发时从 handoff 恢复上下文。")
    default:
        return ("状态待确认 / Unknown", 0, "在 workspace.md 或 STATUS.md 记录当前状态。")
    }
}
```

- [ ] **Step 5: Run the focused test and existing scanner test**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeWorkspaceScannerBuildsConservativeLifecycleFromMarkdownEvidence|testNativeWorkspaceScannerBuildsDashboardFromLocalFiles)'
```

Expected: both tests PASS. The existing scanner test must keep its state, task, service, Git-risk, document, and SQL assertions unchanged.

- [ ] **Step 6: Document the behavior change**

Add this bullet at the top of the `[Unreleased]` `Added` list in `CHANGELOG.md`:

```markdown
- Native workspace scanning now builds lifecycle from `workspace.md` and `STATUS.md`, preserving explicit states while surfacing missing, unsupported, or conflicting records conservatively.
```

- [ ] **Step 7: Run the complete Native Swift test suite**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox --package-path native/Nexus
```

Expected: all Swift tests PASS, including the end-to-end lifecycle proof and archive scan assertions.

- [ ] **Step 8: Commit the independently verified slice**

```bash
git add native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift \
    CHANGELOG.md
git commit -m "Build Native lifecycle from workspace files"
```
