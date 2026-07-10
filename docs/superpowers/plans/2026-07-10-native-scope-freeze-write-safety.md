# Native Scope Freeze Write Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the confirmed Native scope-freeze append preserve the exact regular UTF-8 `需求/scope.md` version reviewed by the user and reject unsafe or changed evidence before write and success audit.

**Architecture:** A domain-specific `NativeScopeDocumentRevision` captures missing, exact regular UTF-8, or invalid scope evidence when `ScopeFreezeWritePlan` is created. `NativeScopeFreezeStore` strictly re-inspects and compares that revision before one Foundation atomic write, while AppState keeps its existing pending-plan and error ordering.

**Tech Stack:** Swift 5.10, Foundation, CryptoKit, XCTest, SwiftPM.

## Global Constraints

- New behavior remains Swift Native-only; do not modify React, Tauri, Rust, TypeScript, SwiftUI layout, or bridge DTOs.
- Use strict full-byte revision comparison; never merge an external scope edit into an already confirmed plan.
- A writable scope-freeze plan requires an existing regular UTF-8 `需求/scope.md`.
- Reject symlinks, directories, other non-regular objects, unreadable data, invalid UTF-8, deletion, replacement, and duplicate submission before mutation.
- Preserve current scope readiness rules, append Markdown, confirmation copy, response shape, audit action, and local-write feedback.
- Append `scope.freeze_confirmed` only after the scope document write succeeds.
- Do not add locks, retries, a registry, a generic CAS framework, or dependencies beyond Foundation/CryptoKit.
- Keep the separate demand-task transfer contract unchanged in this slice.

---

### Task 1: Capture Strict Scope Revision in Every Confirmation Plan

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeScopeFreezeStore.swift`
- Modify: `native/Nexus/Sources/NexusApp/DemandScopeEvidence.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Produces: `NativeScopeDocumentRevision`.
- Produces: `NativeScopeFreezeStore.inspectRevision(at:fileManager:)`.
- Produces: `ScopeFreezeWritePlan.expectedRevision`.
- Preserves: existing `ScopeFreezeWritePlan.status`, `summary`, `items`, `appendedMarkdown`, and `canWrite` behavior for safe regular files.

- [ ] **Step 1: Add the failing strict-plan revision test**

Add a test beside the existing scope-freeze write-plan tests:

```swift
func testScopeFreezeWritePlanCapturesStrictDocumentRevision() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-scope-revision-\(UUID().uuidString)")
    let regularURL = root.appendingPathComponent("regular/需求/scope.md")
    let missingURL = root.appendingPathComponent("missing/需求/scope.md")
    let linkedURL = root.appendingPathComponent("linked/需求/scope.md")
    let invalidURL = root.appendingPathComponent("invalid/需求/scope.md")
    let externalURL = root.appendingPathComponent("external-scope.md")
    defer { try? FileManager.default.removeItem(at: root) }
    for url in [regularURL, missingURL, linkedURL, invalidURL] {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
    }
    let original = "# Scope\n\n## In scope\n\n- Real.\n\n## Out of scope\n\n- None.\n"
    try original.write(to: regularURL, atomically: true, encoding: .utf8)
    try original.write(to: externalURL, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: linkedURL, withDestinationURL: externalURL)
    try Data([0x23, 0x20, 0xC3, 0x28, 0x0A]).write(to: invalidURL)

    func plan(id: String, path: URL) -> ScopeFreezeWritePlan {
        let workspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: id,
            path: path.deletingLastPathComponent().deletingLastPathComponent().path
        )
        let evidence = ScopeFreezeEvidence(
            status: .blocked,
            reason: "ready to freeze",
            evidence: [path.path],
            checks: [],
            scopePath: path.path,
            hasInScope: true,
            hasOutOfScope: true,
            scopeFrozen: false,
            scopeChangeDeclared: false,
            scopeChangeAudited: true,
            unresolvedP0Count: 0
        )
        return ScopeFreezeWritePlan.resolve(workspace: workspace, evidence: evidence)
    }

    let regular = plan(id: "scope-revision-regular", path: regularURL)
    let missing = plan(id: "scope-revision-missing", path: missingURL)
    let linked = plan(id: "scope-revision-linked", path: linkedURL)
    let invalid = plan(id: "scope-revision-invalid", path: invalidURL)

    guard case .regularUTF8(let sha256, let byteCount) = regular.expectedRevision else {
        return XCTFail("expected regular UTF-8 scope revision")
    }
    XCTAssertEqual(sha256.count, 64)
    XCTAssertEqual(byteCount, original.data(using: .utf8)?.count)
    XCTAssertTrue(regular.canWrite)
    XCTAssertEqual(missing.expectedRevision, .missing)
    XCTAssertFalse(missing.canWrite)
    XCTAssertTrue(missing.summary.contains("missing"))
    guard case .invalid(let linkedReason) = linked.expectedRevision else {
        return XCTFail("expected invalid symlink scope revision")
    }
    XCTAssertTrue(linkedReason.contains("not a regular file"))
    XCTAssertFalse(linked.canWrite)
    guard case .invalid(let invalidReason) = invalid.expectedRevision else {
        return XCTFail("expected invalid UTF-8 scope revision")
    }
    XCTAssertTrue(invalidReason.contains("not valid UTF-8"))
    XCTAssertFalse(invalid.canWrite)
    XCTAssertEqual(try String(contentsOf: externalURL, encoding: .utf8), original)
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
    --filter ModelBehaviorTests/testScopeFreezeWritePlanCapturesStrictDocumentRevision
```

Expected: compile failure because `NativeScopeDocumentRevision` and `expectedRevision` do not exist.

- [ ] **Step 3: Add the domain-specific revision and strict reader**

In `NativeScopeFreezeStore.swift`, import CryptoKit and add:

```swift
import CryptoKit

enum NativeScopeDocumentRevision: Hashable {
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
```

Add a private snapshot and module-visible revision inspection entry point:

```swift
private struct NativeScopeDocumentSnapshot {
    let revision: NativeScopeDocumentRevision
    let content: String?
}

static func inspectRevision(
    at path: String,
    fileManager: FileManager = .default
) -> NativeScopeDocumentRevision {
    inspectDocument(at: path, fileManager: fileManager).revision
}
```

The private `inspectDocument` must:

1. expand `~` once into a URL;
2. use `attributesOfItem(atPath:)` to distinguish a missing entry from other read failures;
3. require `.typeRegular` so symlinks and directories are invalid;
4. read the original `Data` bytes;
5. require UTF-8 decoding;
6. compute lowercase SHA-256 from the original bytes;
7. return the decoded content only for regular UTF-8 evidence.

Use these exact reason phrases so tests and AppState feedback remain stable:

```swift
"scope document is missing: \(url.path)"
"scope document is not a regular file: \(url.path)"
"scope document is not valid UTF-8: \(url.path)"
"scope document is unreadable: \(url.path): \(error.localizedDescription)"
```

- [ ] **Step 4: Capture and enforce revision in `ScopeFreezeWritePlan.resolve`**

Add:

```swift
let expectedRevision: NativeScopeDocumentRevision
```

Change the resolver signature to:

```swift
static func resolve(
    workspace: WorkspaceSummary,
    evidence: ScopeFreezeEvidence,
    fileManager: FileManager = .default
) -> ScopeFreezeWritePlan
```

Resolve the revision before the existing frozen/blocker/next branches:

```swift
let expectedRevision = NativeScopeFreezeStore.inspectRevision(
    at: evidence.scopePath,
    fileManager: fileManager
)
```

If it is `.missing` or `.invalid`, return one blocked plan with item id `unsafe-scope-document`, empty appended Markdown, and the exact reason in the summary/detail. Include `expectedRevision` in every existing constructor branch.

Make `canWrite` require a regular revision in addition to the existing conditions:

```swift
guard case .regularUTF8 = expectedRevision else { return false }
return status == .next
    && !appendedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
```

- [ ] **Step 5: Run scope plan tests and commit Task 1**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/testScopeFreezeWritePlan.*'
```

Expected: all selected plan tests pass.

Commit:

```bash
git add native/Nexus/Sources/NexusApp/NativeScopeFreezeStore.swift \
    native/Nexus/Sources/NexusApp/DemandScopeEvidence.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Capture Native scope document revisions"
```

---

### Task 2: Reject Changed or Unsafe Scope Evidence Before Append

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeScopeFreezeStore.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: Task 1 `NativeScopeDocumentRevision`, `expectedRevision`, and strict inspection.
- Produces: stale/unsafe scope rejection shared by the one confirmed scope append.
- Preserves: `NativeScopeFreezeWriteResponse` and optional post-write audit behavior.

- [ ] **Step 1: Add a failing real-file conflict matrix**

Add `testNativeScopeFreezeStoreRejectsChangedDeletedAndUnsafeEvidence`. Use real temporary scope files and one helper that builds a writable plan from a regular fixture. Cover these post-plan mutations independently:

- append an external note to the regular file;
- delete the regular file;
- replace the regular file with a symlink to an external target;
- overwrite the regular file with invalid UTF-8 bytes.

For each case, call `NativeScopeFreezeStore.write(plan:confirmed:auditRoot:actor:)` and assert:

- changed/deleted errors contain `changed since confirmation`;
- current symlink error contains `not a regular file`;
- current invalid bytes error contains `not valid UTF-8`;
- the exact external edit, symlink target, or invalid bytes remain unchanged;
- no `audit-events.jsonl` exists in that case's audit root.

- [ ] **Step 2: Add a failing duplicate-submission test**

Add `testNativeScopeFreezeStoreRejectsSecondSubmissionWithoutDuplicateAudit`:

1. build one writable plan from a regular scope file;
2. submit it once successfully;
3. submit the same plan again;
4. assert the second call reports `changed since confirmation`;
5. assert exactly one `## 范围冻结确认 / Scope Freeze Confirmation` block;
6. assert exactly one `scope.freeze_confirmed` audit event.

- [ ] **Step 3: Run the two tests and record RED**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeScopeFreezeStoreRejectsChangedDeletedAndUnsafeEvidence|testNativeScopeFreezeStoreRejectsSecondSubmissionWithoutDuplicateAudit)'
```

Expected: the current store overwrites changed evidence and appends twice, so the new assertions fail.

- [ ] **Step 4: Enforce strict write ordering**

Add `fileManager: FileManager = .default` to `write`. Before constructing content:

```swift
guard case .regularUTF8 = plan.expectedRevision else {
    throw NativeScopeFreezeStoreError.invalidExpectedRevision(plan.expectedRevision.label)
}
guard plan.canWrite else {
    throw NativeScopeFreezeStoreError.notWritable(plan.summary)
}

let current = inspectDocument(at: plan.scopePath, fileManager: fileManager)
if case .invalid(let reason) = current.revision {
    throw NativeScopeFreezeStoreError.invalidCurrentDocument(reason)
}
guard case .regularUTF8 = current.revision else {
    throw NativeScopeFreezeStoreError.staleDocument(
        path: plan.scopePath,
        expected: plan.expectedRevision.label,
        current: current.revision.label
    )
}
guard current.revision == plan.expectedRevision else {
    throw NativeScopeFreezeStoreError.staleDocument(
        path: plan.scopePath,
        expected: plan.expectedRevision.label,
        current: current.revision.label
    )
}
```

Replace the permissive `try?` helper with a helper that consumes the already inspected regular content and writes to the same expanded URL:

```swift
private static func appendMarkdownBlock(
    _ block: String,
    to currentContent: String,
    at url: URL
) throws {
    var content = currentContent
    if !content.isEmpty, !content.hasSuffix("\n") {
        content.append("\n")
    }
    content.append(block)
    if !content.hasSuffix("\n") {
        content.append("\n")
    }
    try content.write(to: url, atomically: true, encoding: .utf8)
}
```

The response and optional audit remain after this helper returns. Add localized error cases:

```swift
case invalidExpectedRevision(String)
case invalidCurrentDocument(String)
case staleDocument(path: String, expected: String, current: String)
```

The stale description must contain:

```swift
"scope document changed since confirmation: \(path); expected \(expected); current \(current)"
```

- [ ] **Step 5: Run direct store tests and commit Task 2**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeScopeFreezeStore.*|testScopeFreezeWritePlanAppendsOnlyFreezeConfirmationWhenReady)'
```

Expected: conflict, duplicate, and existing success tests pass.

Commit:

```bash
git add native/Nexus/Sources/NexusApp/NativeScopeFreezeStore.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Protect Native scope freeze appends"
```

---

### Task 3: Prove AppState Conflict Feedback and Native Lifecycle Compatibility

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift` only if the interaction test proves a defect
- Modify: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Task 2 stale error and existing AppState pending scope plan.
- Produces: verified stale confirmation behavior and end-to-end compatibility.
- Preserves: successful scope feedback and lifecycle ordering.

- [ ] **Step 1: Add the AppState stale-scope interaction test**

Add `@MainActor func testAppStateScopeFreezeConfirmationKeepsStalePendingEvidence() async throws` beside the task and delivery confirmation interaction tests.

The test must:

1. create a real temporary workspace with `workspace.md`, `STATUS.md`, root `tasks.md`, and the five ready `需求/*.md` documents;
2. leave `需求/scope.md` ready to freeze but not frozen;
3. scan it with `scannedWorkspace`;
4. build `AppState` with `PreviewNexusBridge`, isolated `UserDefaults`, and temporary `applicationSupportRoot`;
5. call `requestScopeFreezeWrite(in:)` and store the non-nil writable pending plan;
6. append an external note to `需求/scope.md`;
7. call `confirmPendingScopeFreezeWrite(confirmed: true)`;
8. assert:

```swift
XCTAssertEqual(appState.pendingScopeFreezeWrite, pending)
XCTAssertTrue(appState.lastError?.contains("changed since confirmation") == true)
XCTAssertFalse(appState.isInitializingDemandIntake)
XCTAssertEqual(try String(contentsOf: scopeURL, encoding: .utf8), externallyEdited)
XCTAssertFalse(FileManager.default.fileExists(
    atPath: applicationSupportRoot
        .appendingPathComponent("audit/\(NativeAuditEventStore.fileName)").path
))
```

Do not assign AppState internals after requesting the plan.

- [ ] **Step 2: Run the AppState test**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testAppStateScopeFreezeConfirmationKeepsStalePendingEvidence
```

Expected after Task 2: PASS without production AppState changes. If it fails, diagnose the actual control-flow defect and make only the smallest correction to success/catch/pending ordering.

- [ ] **Step 3: Verify the real lifecycle uses a fresh scope plan**

In `testNativeStoresCanProveEndToEndWorkspaceLifecycle`, keep `ScopeFreezeWritePlan.resolve` immediately before `NativeScopeFreezeStore.write`. Do not move the plan earlier or reuse it after any scope mutation. No test edit is needed if this order is already present.

- [ ] **Step 4: Add changelog evidence**

At the top of `[Unreleased] / Added`, add:

```markdown
- Native scope-freeze confirmation now captures the exact regular UTF-8 `需求/scope.md` revision shown to the user, rejecting unsafe files, external edits, deletion, and duplicate submission before atomic append and success audit.
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
    --filter 'ModelBehaviorTests/(testAppStateScopeFreezeConfirmationKeepsStalePendingEvidence|testNativeScopeFreezeStore.*|testScopeFreezeWritePlan.*|testNativeStoresCanProveEndToEndWorkspaceLifecycle)'
```

Then run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox --package-path native/Nexus
```

Expected: all selected tests and the complete Native Swift suite pass with zero failures.

Run:

```bash
git diff --check
```

Expected: no output.

- [ ] **Step 6: Commit verified AppState and lifecycle evidence**

```bash
git add native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift CHANGELOG.md
git commit -m "Verify Native scope freeze conflict feedback"
```

If the AppState test required a production correction, add `native/Nexus/Sources/NexusApp/AppState.swift` to the same commit.

---

## Final Review

Review the complete slice from the pre-design base through the final implementation commit. Confirm:

- every scope-freeze plan captures the strict revision at request time;
- writable plans require existing regular UTF-8 evidence;
- missing, invalid, changed, deleted, symlink, invalid-byte, and duplicate-submit paths are covered;
- external content, symlink targets, and invalid bytes remain untouched;
- response and optional audit are produced only after atomic write succeeds;
- AppState keeps stale pending evidence and exposes one actionable error;
- real lifecycle proof still freezes scope before task transfer and worktree setup;
- demand-task transfer, Rust, bridge DTOs, legacy UI, and scope readiness rules remain unchanged;
- the narrow inspection-to-atomic-write TOCTOU window remains documented as accepted M1 residual risk.

After a clean independent review, push `main` through the configured GitHub SSH 443 key, fetch `origin/main`, and verify `HEAD == origin/main`.
