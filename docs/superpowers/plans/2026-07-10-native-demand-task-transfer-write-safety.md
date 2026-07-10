# Native Demand Task Transfer Write Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make confirmed transfer from `需求/tasks.md` to root `tasks.md` bind the visible candidates and duplicate filtering to two exact document revisions, rejecting unsafe or changed evidence before atomic append and success audit.

**Architecture:** A domain-specific `NativeDemandTaskDocumentSnapshot` supplies both original-byte revision and decoded content. `DemandTaskTransferPlan` resolves once from strict intake/output snapshots, the main path exposes unsafe evidence as a blocker, and `NativeDemandTaskTransferStore` requires both revisions to remain exact before writing the output.

**Tech Stack:** Swift 5.10, Foundation, CryptoKit, SwiftUI, XCTest, SwiftPM.

## Global Constraints

- Keep all new workflow behavior Swift Native-only; do not modify React, Tauri, Rust, TypeScript, or bridge DTOs.
- Intake `需求/tasks.md` must exist as regular UTF-8; root `tasks.md` may be missing or regular UTF-8.
- Candidate rows and duplicate identities must come from the exact two snapshots stored in the plan.
- Use `NativeWorkspaceTaskParser` for root task titles; do not union stale `workspace.tasks` into duplicate detection.
- Use strict full-byte revision comparison for both paths; do not merge or silently recompute after confirmation.
- Unsafe evidence must block the Development stage with one relevant file-opening primary action.
- Preserve candidate filtering, priority mapping, appended Markdown rows, response shape, audit action, and successful AppState feedback.
- Append `demand_tasks.transferred` only after the output write succeeds.
- Do not add locks, retries, a registry, a generic CAS framework, or dependencies beyond Foundation/CryptoKit.
- Preserve the existing service/branch and worktree stage order in this slice.

---

### Task 1: Resolve Transfer Candidates From Two Strict Snapshots

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeDemandTaskTransferStore.swift`
- Modify: `native/Nexus/Sources/NexusApp/DemandTaskTransfer.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Produces: `NativeDemandTaskDocumentRevision`.
- Produces: `NativeDemandTaskDocumentSnapshot`.
- Produces: `NativeDemandTaskTransferStore.inspectDocument(at:fileManager:)`.
- Produces: `DemandTaskTransferPlan.expectedIntakeRevision`, `expectedExecutionRevision`, `blockerSummary`, `blockerPath`, and `isBlocked`.
- Preserves: existing `candidates`, `existingTitles`, `transferableItems`, `duplicateCount`, and `summary` for safe snapshots.

- [ ] **Step 1: Add a failing strict-plan snapshot test**

Add `testDemandTaskTransferPlanCapturesStrictInputAndOutputSnapshots` beside the existing demand transfer test. Build real temporary cases for:

- regular intake + regular output;
- regular intake + missing output;
- missing intake;
- intake symlink;
- intake invalid UTF-8;
- output symlink;
- output invalid UTF-8.

Use this safe intake fixture:

```swift
let intake = """
# 需求列表

| 需求点 | 状态 | 优先级 | 来源 | 说明 |
| --- | --- | --- | --- | --- |
| 新增交易快照写入 | 待办 | P0 | 蓝湖 | 保存订单时记录快照 |
""" + "\n"
```

Use this safe output fixture:

```swift
let execution = """
# Tasks

| 任务 | 状态 | 说明 |
| --- | --- | --- |
| 已有执行任务 | 待办 | priority=medium |
""" + "\n"
```

Resolve each plan through a real `DemandIntakeStatus`. Assert:

```swift
guard case .regularUTF8(let intakeSHA, let intakeBytes) = regular.expectedIntakeRevision else {
    return XCTFail("expected regular intake revision")
}
guard case .regularUTF8(let outputSHA, let outputBytes) = regular.expectedExecutionRevision else {
    return XCTFail("expected regular execution revision")
}
XCTAssertEqual(intakeSHA.count, 64)
XCTAssertEqual(intakeBytes, Data(intake.utf8).count)
XCTAssertEqual(outputSHA.count, 64)
XCTAssertEqual(outputBytes, Data(execution.utf8).count)
XCTAssertNil(regular.blockerSummary)
XCTAssertEqual(regular.transferableItems.map(\.title), ["新增交易快照写入"])

XCTAssertEqual(missingOutput.expectedExecutionRevision, .missing)
XCTAssertNil(missingOutput.blockerSummary)
XCTAssertTrue(missingOutput.hasTransferableItems)

XCTAssertTrue(missingIntake.isBlocked)
XCTAssertTrue(missingIntake.blockerSummary?.contains("missing") == true)
XCTAssertFalse(missingIntake.hasTransferableItems)
XCTAssertTrue(linkedIntake.blockerSummary?.contains("not a regular file") == true)
XCTAssertTrue(invalidIntake.blockerSummary?.contains("not valid UTF-8") == true)
XCTAssertTrue(linkedOutput.blockerSummary?.contains("not a regular file") == true)
XCTAssertTrue(invalidOutput.blockerSummary?.contains("not valid UTF-8") == true)
```

- [ ] **Step 2: Add a failing stale-workspace duplicate test**

Add `testDemandTaskTransferPlanUsesExactOutputSnapshotInsteadOfStaleWorkspaceTasks`:

1. write intake containing `重新加入任务`;
2. write root `tasks.md` without that title;
3. construct `WorkspaceSummary.tasks` with a stale `WorkspaceTask` titled `重新加入任务`;
4. resolve the plan;
5. assert the title remains transferable and `duplicateCount == 0`.

Expected current failure: the plan unions `workspace.tasks`, so it wrongly treats the title as an existing duplicate.

- [ ] **Step 3: Run both focused tests and record RED**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testDemandTaskTransferPlanCapturesStrictInputAndOutputSnapshots|testDemandTaskTransferPlanUsesExactOutputSnapshotInsteadOfStaleWorkspaceTasks)'
```

Expected: compile failure for missing revision/blocker APIs plus stale-workspace duplicate assertion failure after the test compiles.

- [ ] **Step 4: Add the strict document snapshot**

In `NativeDemandTaskTransferStore.swift`, import CryptoKit and add:

```swift
enum NativeDemandTaskDocumentRevision: Hashable {
    case missing
    case regularUTF8(sha256: String, byteCount: Int)
    case invalid(reason: String)

    var label: String {
        switch self {
        case .missing:
            return "missing"
        case .regularUTF8(let sha256, let byteCount):
            return "regular UTF-8 \(byteCount) bytes sha256=\(sha256)"
        case .invalid(let reason):
            return "invalid: \(reason)"
        }
    }
}

struct NativeDemandTaskDocumentSnapshot {
    let revision: NativeDemandTaskDocumentRevision
    let content: String?
}
```

Add:

```swift
static func inspectDocument(
    at path: String,
    fileManager: FileManager = .default
) -> NativeDemandTaskDocumentSnapshot
```

The implementation must expand `~`, distinguish missing from other attribute failures, require `.typeRegular`, decode UTF-8, and compute lowercase SHA-256 from original bytes. Reason strings must identify `demand task document`, the expanded path, and one of `not a regular file`, `not valid UTF-8`, or `unreadable`.

- [ ] **Step 5: Resolve plan from the two snapshots**

Add these fields:

```swift
let expectedIntakeRevision: NativeDemandTaskDocumentRevision
let expectedExecutionRevision: NativeDemandTaskDocumentRevision
let blockerSummary: String?
let blockerPath: String?

var isBlocked: Bool { blockerSummary != nil }
```

Change the resolver signature:

```swift
static func resolve(
    workspace: WorkspaceSummary,
    status: DemandIntakeStatus,
    fileManager: FileManager = .default
) -> DemandTaskTransferPlan
```

Inspect each path once. Intake is safe only for `.regularUTF8`; execution is safe for `.regularUTF8` or `.missing`. Parse candidates from `intakeSnapshot.content ?? ""` only. Parse root titles from:

```swift
let existingTitles = Set(
    (executionSnapshot.content.map {
        NativeWorkspaceTaskParser.rows(from: $0, folder: workspace.id)
    } ?? [])
        .map { DemandTaskTransferItem.normalizeTitle($0.snapshot.title) }
)
```

Do not use `workspace.tasks` in this set. Set `blockerPath` to the unsafe intake or execution path. Make `hasTransferableItems` require `!isBlocked`. Make `summary` return the blocker first, then retain the existing no-candidate/all-duplicate/partial/new summaries.

- [ ] **Step 6: Run plan tests and commit Task 1**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/testDemandTaskTransferPlan.*'
```

Expected: all selected plan tests pass.

Commit:

```bash
git add native/Nexus/Sources/NexusApp/NativeDemandTaskTransferStore.swift \
    native/Nexus/Sources/NexusApp/DemandTaskTransfer.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Capture Native demand task revisions"
```

---

### Task 2: Surface Unsafe Transfer Evidence as One Main-Path Blocker

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/PrimaryWorkflowStageResolver.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: Task 1 `DemandTaskTransferPlan.isBlocked`, `blockerSummary`, and `blockerPath`.
- Produces: blocked Development stage with one file-opening action.
- Preserves: existing transfer, no-candidate, and already-transferred preview states.

- [ ] **Step 1: Add a failing blocked-stage test**

Add `testMainStageBlocksUnsafeDemandTaskTransferEvidence`:

1. create a workspace whose demand/scope/service/worktree gates are ready;
2. provide a `DemandTaskTransferPlan` with an invalid intake revision, a blocker summary, and intake blocker path;
3. call `workspace.mainStage(... demandTaskTransfer: plan ...)`;
4. assert:

```swift
XCTAssertEqual(stage.id, .development)
XCTAssertEqual(stage.status, .blocked)
XCTAssertEqual(stage.title, "需求任务证据不可用 / Task evidence unavailable")
XCTAssertEqual(stage.reason, plan.blockerSummary)
XCTAssertEqual(stage.primaryActionLabel, "打开需求任务")
XCTAssertEqual(stage.primaryAction, .path(plan.intakeTasksPath))
XCTAssertFalse(stage.nextStageAllowed)
```

- [ ] **Step 2: Run the test and record RED**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testMainStageBlocksUnsafeDemandTaskTransferEvidence
```

Expected: current resolver skips blocked plans because it checks only `hasTransferableItems`.

- [ ] **Step 3: Add the blocked resolver branch**

Immediately before the existing transferable branch in `PrimaryWorkflowStageResolver.swift`, add:

```swift
if let plan = resolvedDemandTaskTransfer, plan.isBlocked {
    return WorkspaceMainStage(
        id: .development,
        status: .blocked,
        title: "需求任务证据不可用 / Task evidence unavailable",
        reason: plan.blockerSummary ?? "需求任务文档不可安全读取。",
        primaryActionLabel: plan.blockerPath == plan.executionTasksPath ? "打开执行任务" : "打开需求任务",
        primaryActionSystemImage: "doc.badge.ellipsis",
        primaryAction: .path(plan.blockerPath ?? plan.intakeTasksPath),
        evidence: compactEvidence("需求/tasks.md", "tasks.md"),
        nextStageAllowed: false
    )
}
```

Keep the existing `hasTransferableItems` branch immediately after it.

- [ ] **Step 4: Update the compact preview without adding a new surface**

In `DemandTaskTransferPreview`:

- blocked tone uses `NexusPalette.danger`;
- blocked title is `需求任务证据不可用 / Evidence blocked`;
- blocked icon is `doc.badge.ellipsis`;
- transfer remains disabled because `hasTransferableItems == false`;
- both file-opening buttons remain visible.

Check `plan.isBlocked` before candidates/duplicates in `tone`, `title`, and icon selection. Do not change sheet layout or add another card.

- [ ] **Step 5: Run stage and existing transfer-route tests, then commit Task 2**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testMainStageBlocksUnsafeDemandTaskTransferEvidence|testDemandTaskTransferPlanFindsNewIntakeTasksAndUpdatesMainStage)'
```

Expected: blocked and normal transfer stages both pass.

Commit:

```bash
git add native/Nexus/Sources/NexusApp/PrimaryWorkflowStageResolver.swift \
    native/Nexus/Sources/NexusApp/Views/RootView.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Block unsafe Native demand task evidence"
```

---

### Task 3: Reject Either Document Changing Before Transfer

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeDemandTaskTransferStore.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: Task 1 strict snapshots and expected revisions.
- Produces: exact two-document confirmation enforcement.
- Preserves: `NativeDemandTaskTransferResponse` and post-write audit metadata.

- [ ] **Step 1: Add a failing two-document conflict matrix**

Add `testNativeDemandTaskTransferStoreRejectsChangedDeletedAndUnsafeEvidence`. Use independent real temporary cases with a writable plan for:

- intake changed;
- intake deleted;
- intake replaced by symlink;
- intake replaced by invalid UTF-8;
- regular output changed;
- regular output deleted;
- regular output replaced by symlink;
- regular output replaced by invalid UTF-8;
- missing output created after plan.

For each case assert the localized reason identifies `intake` or `execution` and either `changed since confirmation`, `not a regular file`, or `not valid UTF-8`. Assert both source and target external evidence remain exact and no audit file exists.

- [ ] **Step 2: Add failing missing-output success and duplicate tests**

Add:

```swift
func testNativeDemandTaskTransferStoreCreatesMissingOutputWhenStillMissing() throws
func testNativeDemandTaskTransferStoreRejectsSecondSubmissionWithoutDuplicateAudit() throws
```

The first asserts a missing root `tasks.md` is created with the standard header, one Requirement Tasks section, one candidate row, and one audit event. The second submits one regular-output plan twice and asserts one candidate row plus one `demand_tasks.transferred` event.

- [ ] **Step 3: Run the three tests and record RED**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeDemandTaskTransferStoreRejectsChangedDeletedAndUnsafeEvidence|testNativeDemandTaskTransferStoreCreatesMissingOutputWhenStillMissing|testNativeDemandTaskTransferStoreRejectsSecondSubmissionWithoutDuplicateAudit)'
```

Expected: current store transfers stale intake candidates, merges output edits, and allows duplicate submission.

- [ ] **Step 4: Enforce strict preflight ordering**

In `transfer`:

1. keep the confirmation guard first;
2. reject expected intake unless `.regularUTF8`;
3. reject expected execution unless `.regularUTF8` or `.missing`;
4. require `!plan.isBlocked && plan.hasTransferableItems`;
5. inspect current intake and execution snapshots;
6. reject invalid current revisions with path-specific errors;
7. require current intake equals expected intake;
8. require current execution equals expected execution;
9. build output from execution content or the standard missing-file header;
10. atomically write to the same expanded output URL;
11. create response and optional audit only after write.

Remove `readOrCreateExecutionTasksDocument`; it must not create a parent or read a different version. Add localized error cases that distinguish expected/current intake, expected/current execution, and stale document path. Stale descriptions must contain `changed since confirmation`.

- [ ] **Step 5: Run direct store tests and commit Task 3**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeDemandTaskTransferStore.*|testDemandTaskTransferPlanFindsNewIntakeTasksAndUpdatesMainStage)'
```

Expected: conflict matrix, first creation, duplicate rejection, and existing success all pass.

Commit:

```bash
git add native/Nexus/Sources/NexusApp/NativeDemandTaskTransferStore.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Protect Native demand task transfers"
```

---

### Task 4: Prove AppState Conflict Feedback And End-To-End Compatibility

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift` only if the test proves a defect
- Modify: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Task 3 stale errors and existing pending transfer plan.
- Produces: verified AppState conflict behavior and lifecycle compatibility.
- Preserves: successful transfer focus and local-write feedback.

- [ ] **Step 1: Add the AppState stale-output interaction test**

Add `@MainActor func testAppStateDemandTaskTransferConfirmationKeepsStalePendingEvidence() async throws` beside existing confirmation interaction tests.

The test must:

1. create a real temporary workspace with `workspace.md`, `STATUS.md`, root `tasks.md`, and all five ready `需求/*.md` documents;
2. scan it into `WorkspaceSummary`;
3. create AppState with `PreviewNexusBridge`, isolated UserDefaults, and temporary application support;
4. call `requestDemandTaskTransfer(in:)` and store the writable pending plan;
5. append an external root-task row after confirmation opens;
6. call `confirmPendingDemandTaskTransfer(confirmed: true)`;
7. assert:

```swift
XCTAssertEqual(appState.pendingDemandTaskTransfer, pending)
XCTAssertTrue(appState.lastError?.contains("changed since confirmation") == true)
XCTAssertFalse(appState.isUpdatingTask)
XCTAssertEqual(try String(contentsOf: executionURL, encoding: .utf8), externallyEdited)
XCTAssertEqual(try String(contentsOf: intakeURL, encoding: .utf8), originalIntake)
XCTAssertNil(appState.localWriteFeedback)
XCTAssertFalse(FileManager.default.fileExists(
    atPath: applicationSupportRoot
        .appendingPathComponent("audit/\(NativeAuditEventStore.fileName)").path
))
```

Do not assign pending or other AppState internals after requesting the plan.

- [ ] **Step 2: Run the AppState test**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testAppStateDemandTaskTransferConfirmationKeepsStalePendingEvidence
```

Expected after Task 3: PASS without production AppState changes. If it fails, diagnose and make only the smallest actual control-flow fix.

- [ ] **Step 3: Verify lifecycle order remains fresh**

In `testNativeStoresCanProveEndToEndWorkspaceLifecycle`, keep `DemandTaskTransferPlan.resolve` immediately before `NativeDemandTaskTransferStore.transfer`, after the scope append and before worktree setup. No edit is needed if this order is already present.

- [ ] **Step 4: Add changelog evidence**

At the top of `[Unreleased] / Added`, add:

```markdown
- Native demand-task transfer now binds the reviewed `需求/tasks.md` candidates and root `tasks.md` duplicate set to exact regular UTF-8 revisions, blocking unsafe evidence and rejecting either document changing before atomic append and success audit.
```

- [ ] **Step 5: Run focused and complete verification**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testAppStateDemandTaskTransferConfirmationKeepsStalePendingEvidence|testDemandTaskTransferPlan.*|testMainStageBlocksUnsafeDemandTaskTransferEvidence|testNativeDemandTaskTransferStore.*|testNativeStoresCanProveEndToEndWorkspaceLifecycle)'
```

Then run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox --package-path native/Nexus
```

Expected: focused tests and complete Native Swift suite pass with zero failures.

Run `git diff --check`; expected no output.

- [ ] **Step 6: Commit Task 4**

```bash
git add native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift CHANGELOG.md
git commit -m "Verify Native demand transfer conflict feedback"
```

If AppState required an actual production correction, include `native/Nexus/Sources/NexusApp/AppState.swift`.

---

## Final Review

Review the complete slice from the pre-design base through the final implementation commit. Confirm:

- candidates and duplicate identities come from the same two snapshots whose revisions the plan stores;
- missing intake, unsafe intake, and unsafe output block the main path instead of disappearing;
- missing output remains a valid first-create state;
- intake/output changed, created, deleted, symlinked, invalid-byte, and duplicate-submit paths are covered;
- no directory, file, response, feedback, or audit mutation occurs before both comparisons pass;
- root task duplicate parsing reuses `NativeWorkspaceTaskParser` and does not union stale workspace tasks;
- AppState keeps stale pending state, exact external evidence, and one actionable error without success feedback;
- successful transfer row formatting, priority mapping, lifecycle order, and audit metadata remain unchanged;
- stage order, task status, scope, delivery, lifecycle, Rust, bridge DTOs, and legacy UI are untouched except the intended compact preview state;
- the narrow multi-file TOCTOU residual risk remains documented and is not expanded.

After clean task reviews and whole-branch review, push `main` through the configured GitHub SSH 443 key, fetch `origin/main`, and verify `HEAD == origin/main`.
