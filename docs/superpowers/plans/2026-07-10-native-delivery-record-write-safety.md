# Native Delivery Record Write Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Delivery Gate, validation/PR, and archive-checklist appends reject non-regular, unreadable, or changed `交付记录.md` evidence before atomic write and success audit.

**Architecture:** A small `NativeDeliveryRecordDocumentRevision` value captures missing, exact regular UTF-8, or invalid document state when each confirmation plan is created. The existing shared `NativeDeliveryRecordStore.append` path strictly re-inspects and compares that revision before one Foundation atomic write, so all three write kinds inherit the same conflict behavior without a general CAS abstraction.

**Tech Stack:** Swift 5.10, Foundation, CryptoKit, XCTest, SwiftPM.

## Global Constraints

- New workflow behavior remains Swift Native-only; do not modify React, Tauri, Rust, TypeScript, or public bridge DTOs.
- Use strict full-content revision comparison; do not merge external delivery-record edits after confirmation.
- Keep missing-to-missing first creation valid with the standard `# 交付记录` header.
- Reject symlinks, directories, non-regular objects, unreadable data, and invalid UTF-8 before mutation.
- Keep optional audit append semantics unchanged and append audit only after the delivery file write succeeds.
- Do not add locks, a registry, a general CAS framework, or dependencies beyond Foundation/CryptoKit.
- Preserve current Delivery Gate, validation/PR, archive, SQL, task, risk, git, and lifecycle rules.

---

### Task 1: Capture Delivery Document Revision in Every Confirmation Plan

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeDeliveryRecordStore.swift`
- Modify: `native/Nexus/Sources/NexusApp/DeliveryLifecycleEvidence.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Produces: `NativeDeliveryRecordDocumentRevision`.
- Produces: `NativeDeliveryRecordStore.inspectRevision(at:fileManager:)`.
- Produces: `expectedRevision` on `DeliveryRecordWritePlan`, `ArchiveChecklistWritePlan`, and `ValidationPrWritePlan`.
- Consumes: existing plan `deliveryPath`, `summary`, and `canWrite` behavior.

- [ ] **Step 1: Add a failing plan-revision test**

Add a test that creates three workspace paths and resolves real delivery plans:

```swift
func testDeliveryRecordWritePlansCaptureStrictDocumentRevisions() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-delivery-revision-\(UUID().uuidString)")
    let missing = root.appendingPathComponent("missing")
    let regular = root.appendingPathComponent("regular")
    let linked = root.appendingPathComponent("linked")
    let external = root.appendingPathComponent("external.md")
    defer { try? FileManager.default.removeItem(at: root) }
    for directory in [missing, regular, linked] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    let original = "# 交付记录\n\n人工记录。\n"
    try original.write(to: regular.appendingPathComponent("交付记录.md"), atomically: true, encoding: .utf8)
    try original.write(to: external, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(
        at: linked.appendingPathComponent("交付记录.md"),
        withDestinationURL: external
    )
    let healthChecks = [
        WorkspaceHealthCheck(
            id: "delivery-record",
            label: "交付记录",
            detail: "交付记录可用",
            status: "pass",
            action: "delivery"
        ),
        WorkspaceHealthCheck(
            id: "sql-directory",
            label: "SQL",
            detail: "未声明 SQL 变更。",
            status: "pass",
            action: "sql"
        )
    ]

    let missingWorkspace = workspaceForWorkflowSummary(
        stage: "developing",
        id: "delivery-revision-missing",
        path: missing.path,
        healthChecks: healthChecks
    )
    let regularWorkspace = workspaceForWorkflowSummary(
        stage: "developing",
        id: "delivery-revision-regular",
        path: regular.path,
        healthChecks: healthChecks
    )
    let linkedWorkspace = workspaceForWorkflowSummary(
        stage: "developing",
        id: "delivery-revision-linked",
        path: linked.path,
        healthChecks: healthChecks
    )

    let missingPlan = DeliveryRecordWritePlan.resolve(
        workspace: missingWorkspace,
        gate: DeliveryGateEvidence.resolve(workspace: missingWorkspace)
    )
    let regularPlan = DeliveryRecordWritePlan.resolve(
        workspace: regularWorkspace,
        gate: DeliveryGateEvidence.resolve(workspace: regularWorkspace)
    )
    let linkedPlan = DeliveryRecordWritePlan.resolve(
        workspace: linkedWorkspace,
        gate: DeliveryGateEvidence.resolve(workspace: linkedWorkspace)
    )

    XCTAssertEqual(missingPlan.expectedRevision, .missing)
    guard case .regularUTF8(let sha256, let byteCount) = regularPlan.expectedRevision else {
        return XCTFail("expected regular UTF-8 revision")
    }
    XCTAssertEqual(sha256.count, 64)
    XCTAssertEqual(byteCount, original.data(using: .utf8)?.count)
    guard case .invalid(let reason) = linkedPlan.expectedRevision else {
        return XCTFail("expected invalid symlink revision")
    }
    XCTAssertTrue(reason.contains("not a regular file"))
    XCTAssertFalse(linkedPlan.canWrite)
    XCTAssertTrue(linkedPlan.summary.contains("not a regular file"))
    XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), original)
}
```

- [ ] **Step 2: Run the focused test and record RED**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testDeliveryRecordWritePlansCaptureStrictDocumentRevisions
```

Expected: compile failure because `expectedRevision`, `NativeDeliveryRecordDocumentRevision`, and `inspectRevision` do not exist.

- [ ] **Step 3: Add the revision model and strict inspection**

In `NativeDeliveryRecordStore.swift`, import CryptoKit and add:

```swift
import CryptoKit

enum NativeDeliveryRecordDocumentRevision: Hashable {
    case missing
    case regularUTF8(sha256: String, byteCount: Int)
    case invalid(reason: String)

    var blockerSummary: String? {
        guard case .invalid(let reason) = self else { return nil }
        return reason
    }

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
```

Add a nonthrowing inspection API used while preparing plans:

```swift
static func inspectRevision(
    at path: String,
    fileManager: FileManager = .default
) -> NativeDeliveryRecordDocumentRevision {
    inspectDocument(at: path, fileManager: fileManager).revision
}
```

Add one private snapshot reader:

```swift
private struct DeliveryRecordDocumentSnapshot {
    let revision: NativeDeliveryRecordDocumentRevision
    let content: String?
}

private static func inspectDocument(
    at path: String,
    fileManager: FileManager
) -> DeliveryRecordDocumentSnapshot {
    let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    let attributes: [FileAttributeKey: Any]
    do {
        attributes = try fileManager.attributesOfItem(atPath: url.path)
    } catch let error as NSError
        where error.domain == NSCocoaErrorDomain
            && error.code == NSFileReadNoSuchFileError {
        return DeliveryRecordDocumentSnapshot(revision: .missing, content: nil)
    } catch {
        return DeliveryRecordDocumentSnapshot(
            revision: .invalid(reason: "delivery record is unreadable: \(url.path): \(error.localizedDescription)"),
            content: nil
        )
    }
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
        return DeliveryRecordDocumentSnapshot(
            revision: .invalid(reason: "delivery record is not a regular file: \(url.path)"),
            content: nil
        )
    }
    do {
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            return DeliveryRecordDocumentSnapshot(
                revision: .invalid(reason: "delivery record is not valid UTF-8: \(url.path)"),
                content: nil
            )
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return DeliveryRecordDocumentSnapshot(
            revision: .regularUTF8(sha256: digest, byteCount: data.count),
            content: content
        )
    } catch {
        return DeliveryRecordDocumentSnapshot(
            revision: .invalid(reason: "delivery record is unreadable: \(url.path): \(error.localizedDescription)"),
            content: nil
        )
    }
}
```

Keep the snapshot private; only the revision crosses into plans.

- [ ] **Step 4: Capture the revision in all three plan types**

Add:

```swift
let expectedRevision: NativeDeliveryRecordDocumentRevision
```

to `DeliveryRecordWritePlan`, `ArchiveChecklistWritePlan`, and `ValidationPrWritePlan`.

Change the three declarations exactly:

```swift
static func resolve(
    workspace: WorkspaceSummary,
    gate: DeliveryGateEvidence,
    fileManager: FileManager = .default
) -> DeliveryRecordWritePlan

static func resolve(
    workspace: WorkspaceSummary,
    archiveGate: ArchiveGateEvidence,
    fileManager: FileManager = .default
) -> ArchiveChecklistWritePlan

static func resolve(
    workspace: WorkspaceSummary,
    evidence: ValidationPrEvidence,
    fileManager: FileManager = .default
) -> ValidationPrWritePlan
```

At the beginning of each method body, after computing `deliveryPath`, add:

```swift
let expectedRevision = NativeDeliveryRecordStore.inspectRevision(
    at: deliveryPath,
    fileManager: fileManager
)
let revisionBlocker = expectedRevision.blockerSummary
```

Pass it into every return path. For writable, non-archived branches, prefer its blocker over the existing summary:

```swift
summary: revisionBlocker
    ?? "确认后只会向交付记录追加当前 Delivery Gate 快照，不覆盖人工记录。",
expectedRevision: expectedRevision
```

For archive and validation, use their current writable summary after `??`. Add `expectedRevision: expectedRevision` to every initializer, including archived and empty-plan branches. Update each `canWrite`:

```swift
expectedRevision.blockerSummary == nil
    && status != .archived
    && !appendedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
```

Archive-only branches retain their archived summary while still storing the captured revision.

- [ ] **Step 5: Run plan and existing plan-model tests**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testDeliveryRecordWritePlansCaptureStrictDocumentRevisions|testDeliveryRecordWritePlan.*|testArchiveChecklistWritePlan.*|testValidationPrWritePlan.*)'
```

Expected: all selected plan tests pass. Existing success fixtures capture regular revisions; archived fixtures remain read-only.

- [ ] **Step 6: Commit revision capture**

```bash
git add native/Nexus/Sources/NexusApp/NativeDeliveryRecordStore.swift \
    native/Nexus/Sources/NexusApp/DeliveryLifecycleEvidence.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Capture Native delivery document revisions"
```

---

### Task 2: Reject Changed or Unsafe Delivery Records Before Append

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeDeliveryRecordStore.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: Task 1 `expectedRevision` and `inspectDocument`.
- Produces: common strict append behavior for all `NativeDeliveryRecordWriteKind` values.
- Preserves: existing public append methods and `NativeDeliveryRecordWriteResponse`.

- [ ] **Step 1: Add RED tests for stale and unsafe evidence**

Add `testNativeDeliveryRecordStoreRejectsChangedCreatedDeletedAndInvalidEvidence` with five isolated directories:

1. Build a regular-file Delivery Gate plan, manually replace the content, confirm, and assert a `changed since confirmation` error, exact manual content, no snapshot heading, and no audit file.
2. Build a plan while missing, create `交付记录.md`, confirm, and assert stale rejection with exact created content.
3. Build a regular-file plan, delete `交付记录.md`, confirm, and assert stale rejection without recreating the file or writing audit.
4. Build a plan against a symlink and call the store directly; assert `not a regular file`, unchanged target/link, and no audit.
5. Build a plan against invalid UTF-8 bytes and call the store directly; assert `not valid UTF-8`, exact bytes, and no audit.

Use the real `DeliveryRecordWritePlan.resolve` and `NativeDeliveryRecordStore.appendDeliverySnapshot`; do not call private helpers.

Add `testNativeDeliveryRecordStoreRejectsSecondSubmissionWithoutDuplicateAudit`:

```swift
let plan = DeliveryRecordWritePlan.resolve(workspace: workspace, gate: gate)
let first = try NativeDeliveryRecordStore.appendDeliverySnapshot(
    plan: plan,
    confirmed: true,
    auditRoot: auditRoot.path,
    actor: "Nexus Test"
)
XCTAssertThrowsError(
    try NativeDeliveryRecordStore.appendDeliverySnapshot(
        plan: plan,
        confirmed: true,
        auditRoot: auditRoot.path,
        actor: "Nexus Test"
    )
) { error in
    XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
}
let content = try String(contentsOf: deliveryURL, encoding: .utf8)
let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 10)
XCTAssertEqual(content.components(separatedBy: "## Nexus Delivery Gate Snapshot").count - 1, 1)
XCTAssertEqual(events.filter { $0.action == "delivery_record.snapshot_appended" }.count, 1)
XCTAssertNotNil(first.auditEventID)
```

- [ ] **Step 2: Run the new tests and prove current writes are unsafe**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeDeliveryRecordStoreRejectsChangedCreatedDeletedAndInvalidEvidence|testNativeDeliveryRecordStoreRejectsSecondSubmissionWithoutDuplicateAudit)'
```

Expected: failures because the shared helper still uses `try?`, overwrites changed evidence, and appends the same plan twice.

- [ ] **Step 3: Pass expected revision into the shared append path**

In each public append method add:

```swift
expectedRevision: plan.expectedRevision,
```

to the shared call. Add the parameter to `append`:

```swift
expectedRevision: NativeDeliveryRecordDocumentRevision,
```

Preserve explicit confirmation first, then reject invalid expected evidence before the current `canWrite` guard:

```swift
guard confirmed else {
    throw NativeDeliveryRecordStoreError.unconfirmed
}
if case .invalid(let reason) = expectedRevision {
    throw NativeDeliveryRecordStoreError.invalidExpectedRevision(reason)
}
guard canWrite else {
    throw NativeDeliveryRecordStoreError.notWritable(notWritableSummary)
}
```

- [ ] **Step 4: Replace permissive read fallback with strict comparison**

Replace `appendMarkdownBlock` with:

```swift
private static func appendMarkdownBlock(
    _ block: String,
    toFile path: String,
    expectedRevision: NativeDeliveryRecordDocumentRevision,
    fileManager: FileManager
) throws {
    let current = inspectDocument(at: path, fileManager: fileManager)
    if case .invalid(let reason) = current.revision {
        throw NativeDeliveryRecordStoreError.invalidCurrentDocument(reason)
    }
    guard current.revision == expectedRevision else {
        throw NativeDeliveryRecordStoreError.staleDocument(
            path: path,
            expected: expectedRevision.label,
            current: current.revision.label
        )
    }

    var content = current.content ?? "# 交付记录\n"
    if !content.isEmpty, !content.hasSuffix("\n") {
        content.append("\n")
    }
    content.append(block)
    if !content.hasSuffix("\n") {
        content.append("\n")
    }
    try content.write(toFile: path, atomically: true, encoding: .utf8)
}
```

Thread the existing `FileManager.default` through the shared append call with an internal defaulted parameter on each public method only if tests need injection. Do not add a write closure or lock abstraction.

Add errors:

```swift
case invalidExpectedRevision(String)
case invalidCurrentDocument(String)
case staleDocument(path: String, expected: String, current: String)
```

with descriptions:

```swift
case .invalidExpectedRevision(let reason):
    return reason
case .invalidCurrentDocument(let reason):
    return reason
case .staleDocument(let path, let expected, let current):
    return "delivery record changed since confirmation: \(path): expected \(expected), found \(current)"
```

Call this strict helper before building the success response. Keep audit append after the helper returns.

- [ ] **Step 5: Run all direct delivery-store tests**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeDeliveryRecordStore.*|testDeliveryRecordWritePlanAppendsCurrentGateSnapshot|testArchiveChecklistWritePlanAppendsFinalChecklistWithoutLifecycleWriteback|testValidationPrWritePlanAppendsReviewSnapshotWithoutCallingGithub)'
```

Expected: stale, unsafe, duplicate-submit, and all three valid write kinds pass.

- [ ] **Step 6: Commit strict shared append behavior**

```bash
git add native/Nexus/Sources/NexusApp/NativeDeliveryRecordStore.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Protect Native delivery record appends"
```

---

### Task 3: Prove AppState Conflict Feedback and End-to-End Delivery

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift` only if the RED interaction test proves a defect
- Modify: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: existing pending plan state and Task 2 stale error.
- Produces: verified AppState stale behavior and refreshed success behavior.
- Preserves: current confirmation sheets and local-write feedback copy.

- [ ] **Step 1: Add an AppState stale-delivery interaction test**

Add an `@MainActor async throws` test that:

1. creates a real temporary workspace with `workspace.md`, `STATUS.md`, `tasks.md`, and regular `交付记录.md`;
2. scans it into `WorkspaceSummary`;
3. creates `AppState` with `PreviewNexusBridge` and a temporary `applicationSupportRoot`;
4. calls `requestDeliveryRecordWrite(in:)`;
5. stores the pending plan and manually appends an external note to `交付记录.md`;
6. calls `confirmPendingDeliveryRecordWrite(confirmed: true)`;
7. asserts:

```swift
XCTAssertEqual(appState.pendingDeliveryRecordWrite, pending)
XCTAssertTrue(appState.lastError?.contains("changed since confirmation") == true)
XCTAssertFalse(appState.isUpdatingDeliveryRecord)
XCTAssertEqual(try String(contentsOf: deliveryURL, encoding: .utf8), externallyEdited)
XCTAssertFalse(FileManager.default.fileExists(
    atPath: applicationSupportRoot
        .appendingPathComponent("audit/\(NativeAuditEventStore.fileName)").path
))
```

Use workspace fixtures that make `DeliveryRecordWritePlan.canWrite` true. Do not mutate AppState internals after requesting the plan.

- [ ] **Step 2: Run the AppState test**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testAppStateDeliveryRecordConfirmationKeepsStalePendingEvidence
```

Expected after Task 2: PASS without production AppState changes. If it fails because AppState clears pending or loses the error, make the smallest correction in the existing catch/success ordering and rerun.

- [ ] **Step 3: Keep the real lifecycle proof on fresh revisions**

In `testNativeStoresCanProveEndToEndWorkspaceLifecycle`, keep each plan resolution after the prior delivery append:

```swift
let deliveryPlan = DeliveryRecordWritePlan.resolve(workspace: workspace, gate: deliveryGate)
_ = try NativeDeliveryRecordStore.appendDeliverySnapshot(
    plan: deliveryPlan,
    confirmed: true,
    auditRoot: auditRoot.path,
    actor: "Nexus Test"
)

let validation = ValidationPrEvidence.resolve(workspace: workspace, deliveryGate: deliveryGate)
let validationPlan = ValidationPrWritePlan.resolve(workspace: workspace, evidence: validation)
_ = try NativeDeliveryRecordStore.appendValidationPrSnapshot(
    plan: validationPlan,
    confirmed: true,
    auditRoot: auditRoot.path,
    actor: "Nexus Test"
)

let archive = ArchiveGateEvidence.resolve(
    workspace: workspace,
    deliveryGate: deliveryGate,
    validationPr: validation
)
let archivePlan = ArchiveChecklistWritePlan.resolve(workspace: workspace, archiveGate: archive)
_ = try NativeDeliveryRecordStore.appendArchiveChecklist(
    plan: archivePlan,
    confirmed: true,
    auditRoot: auditRoot.path,
    actor: "Nexus Test"
)
```

This order is already expected; the test must prove each new plan captures the revision produced by the previous successful append.

- [ ] **Step 4: Add changelog evidence**

At the top of `[Unreleased] / Added`, add:

```markdown
- Native delivery, validation/PR, and archive-checklist writes now capture the exact regular UTF-8 delivery-record revision shown at confirmation, rejecting unsafe files, external edits, and duplicate submissions before atomic append and success audit.
```

- [ ] **Step 5: Run focused and complete Native verification**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testAppStateDeliveryRecordConfirmationKeepsStalePendingEvidence|testNativeDeliveryRecordStore.*|testDeliveryRecordWritePlan.*|testArchiveChecklistWritePlan.*|testValidationPrWritePlan.*|testNativeStoresCanProveEndToEndWorkspaceLifecycle)'
```

Expected: all selected revision, conflict, AppState, three-kind write, and lifecycle tests pass.

Then run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox --package-path native/Nexus
```

Expected: complete Native Swift suite passes with zero failures.

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 6: Commit verified AppState and lifecycle evidence**

```bash
git add native/Nexus/Sources/NexusApp/AppState.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift \
    CHANGELOG.md
git commit -m "Verify Native delivery conflict feedback"
```

If `AppState.swift` is unchanged, omit it from `git add`.

---

## Final Review

Review the complete slice from the pre-design base through the final implementation commit. Confirm:

- all three plan types capture the revision at request time;
- missing, regular UTF-8, invalid, changed, created, deleted, and duplicate-submit paths are covered;
- symlink targets and invalid bytes remain untouched;
- the shared store validates before constructing success response or audit;
- AppState keeps stale pending state and exposes the error;
- the real lifecycle resolves a fresh plan after every append;
- no bridge, Rust, legacy UI, delivery-gate, or lifecycle semantics changed.

After a clean independent review, push `main` through the configured GitHub SSH 443 key, fetch `origin/main`, and verify `HEAD == origin/main`.
