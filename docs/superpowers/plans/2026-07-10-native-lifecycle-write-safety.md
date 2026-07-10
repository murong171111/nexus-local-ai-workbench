# Native Lifecycle Write Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent stale or contradictory Native lifecycle confirmations from overwriting current files and restore both lifecycle documents after an in-process write failure.

**Architecture:** The internal Swift store will strictly snapshot both lifecycle documents, resolve one canonical current state, and require the confirmation sheet's observed stage before writing. A second task adds a narrow injected writer and compensating rollback around the two existing Foundation atomic replacements; audit append remains after the pair succeeds.

**Tech Stack:** Swift 5.9+, Foundation, XCTest, Swift Package Manager, existing NexusBridge request/response models.

## Global Constraints

- Keep `UpdateWorkspaceLifecycleRequest` and the legacy Rust bridge contract unchanged; expected-state protection belongs to the internal Swift Native store entry point.
- Require an observed `expectedState` for every `NativeWorkspaceLifecycleStore.update` call.
- Resolve current state from both `workspace.md` and `STATUS.md` using the store's existing English and Chinese aliases; accept `unknown` only as an expected current state, not as a requested target state.
- Reject unreadable/non-file documents, unsupported current values, conflicting file states, and stale confirmations before changing either file or appending audit.
- Continue using Foundation atomic replacement for each individual document; do not add a journal, registry, cache, dependency, or generalized transaction framework.
- On any in-process write failure, attempt to restore both exact pre-write snapshots; report rollback uncertainty explicitly if restoration fails.
- Append `workspace_lifecycle.updated` only after both target writes succeed; preserve existing optional audit-root and optional audit-append response semantics.
- Do not change lifecycle eligibility, workflow gate order, confirmation UI layout, scanner behavior, or Rust lifecycle writes.
- Keep AppState success refresh and local-write feedback unchanged; errors continue through `lastError` with the pending confirmation retained.

---

### Task 1: Reject Invalid, Conflicting, and Stale Lifecycle Evidence

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeWorkspaceLifecycleStore.swift:4-260`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift:3949`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift:1832-1901`

**Interfaces:**
- Consumes: `LifecycleStatusUpdate.currentStage`, existing `UpdateWorkspaceLifecycleRequest`, and lifecycle aliases already accepted by `normalizedLifecycleState(_:)`.
- Produces: `NativeWorkspaceLifecycleStore.update(request:expectedState:fileManager:)`; it throws before writing when the current canonical file state does not match the confirmed expected state.

- [ ] **Step 1: Add a failing test that proves an invalid second document currently leaves the first document changed**

Add this test immediately before the existing lifecycle store success test:

```swift
func testNativeWorkspaceLifecycleStoreRejectsInvalidStatusBeforeChangingWorkspace() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-native-lifecycle-invalid-status-\(UUID().uuidString)")
    let workspaceURL = root.appendingPathComponent("workspace")
    let workspaceDocumentURL = workspaceURL.appendingPathComponent("workspace.md")
    let statusDocumentURL = workspaceURL.appendingPathComponent("STATUS.md")
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    let originalWorkspace = "# Workspace\n\n- 当前状态: developing\n"
    try originalWorkspace.write(to: workspaceDocumentURL, atomically: true, encoding: .utf8)
    try FileManager.default.createDirectory(at: statusDocumentURL, withIntermediateDirectories: true)

    XCTAssertThrowsError(
        try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: "archived",
                confirmed: true
            )
        )
    )

    XCTAssertEqual(try String(contentsOf: workspaceDocumentURL, encoding: .utf8), originalWorkspace)
}
```

- [ ] **Step 2: Run the invalid-document test and prove the existing sequential write is unsafe**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testNativeWorkspaceLifecycleStoreRejectsInvalidStatusBeforeChangingWorkspace
```

Expected: FAIL at the final equality because the current store changes `workspace.md` to `archived` before its `STATUS.md` directory write throws.

- [ ] **Step 3: Strictly snapshot both lifecycle documents before either write**

Add this private snapshot type inside `NativeWorkspaceLifecycleStore`:

```swift
private struct LifecycleDocumentSnapshot {
    let url: URL
    let content: String?

    func contentOrFallback(_ fallback: String) -> String {
        content ?? fallback
    }
}
```

Add the strict reader:

```swift
private static func documentSnapshot(
    at url: URL,
    fileManager: FileManager
) throws -> LifecycleDocumentSnapshot {
    var isDirectory: ObjCBool = false
    guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
        return LifecycleDocumentSnapshot(url: url, content: nil)
    }
    guard !isDirectory.boolValue else {
        throw NativeWorkspaceLifecycleStoreError.documentNotFile(url.path)
    }
    do {
        return LifecycleDocumentSnapshot(
            url: url,
            content: try String(contentsOf: url, encoding: .utf8)
        )
    } catch {
        throw NativeWorkspaceLifecycleStoreError.documentUnreadable(
            url.path,
            error.localizedDescription
        )
    }
}
```

In `update`, replace both `try? String(contentsOf:)` fallbacks with snapshots read before computing `previousState` or writing:

```swift
let workspaceSnapshot = try documentSnapshot(at: workspaceDocumentURL, fileManager: fileManager)
let statusSnapshot = try documentSnapshot(at: statusDocumentURL, fileManager: fileManager)
let workspaceContent = workspaceSnapshot.contentOrFallback("# Workspace\n\n")
let statusContent = statusSnapshot.contentOrFallback("# STATUS\n\n")
```

Compute `nextStatusContent` before the first write and remove the later status read. Add error cases and descriptions:

```swift
case documentNotFile(String)
case documentUnreadable(String, String)
```

```swift
case .documentNotFile(let path):
    return "lifecycle document is not a file: \(path)"
case .documentUnreadable(let path, let reason):
    return "lifecycle document is unreadable: \(path): \(reason)"
```

- [ ] **Step 4: Verify strict preflight prevents the partial write**

Re-run the focused command from Step 2 with the original store call. Expected: PASS and the error text contains `lifecycle document is not a file`. Keep that call unchanged until Step 8 adds the required expected-state argument to every call site.

- [ ] **Step 5: Add failing stale-confirmation and existing-conflict coverage**

Add this test beside the invalid-document test:

```swift
func testNativeWorkspaceLifecycleStoreRejectsStaleAndConflictingEvidenceBeforeWriting() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-native-lifecycle-conflicts-\(UUID().uuidString)")
    let staleURL = root.appendingPathComponent("stale")
    let conflictURL = root.appendingPathComponent("conflict")
    let auditRoot = root.appendingPathComponent("audit")
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    for directory in [staleURL, conflictURL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    let staleWorkspace = "# Workspace\n\n- 当前状态: delivery\n"
    let staleStatus = "# STATUS\n\n- 状态: delivery\n- 当前焦点: External edit\n"
    try staleWorkspace.write(to: staleURL.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
    try staleStatus.write(to: staleURL.appendingPathComponent("STATUS.md"), atomically: true, encoding: .utf8)

    XCTAssertThrowsError(
        try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: staleURL.path,
                state: "archived",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedState: "developing"
        )
    ) { error in
        XCTAssertTrue(error.localizedDescription.contains("expected developing, found delivery"))
    }
    XCTAssertEqual(try String(contentsOf: staleURL.appendingPathComponent("workspace.md"), encoding: .utf8), staleWorkspace)
    XCTAssertEqual(try String(contentsOf: staleURL.appendingPathComponent("STATUS.md"), encoding: .utf8), staleStatus)

    let conflictWorkspace = "# Workspace\n\n- 当前状态: developing\n"
    let conflictStatus = "# STATUS\n\n- 状态: archived\n"
    try conflictWorkspace.write(to: conflictURL.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
    try conflictStatus.write(to: conflictURL.appendingPathComponent("STATUS.md"), atomically: true, encoding: .utf8)

    XCTAssertThrowsError(
        try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: conflictURL.path,
                state: "delivery",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedState: "blocked"
        )
    ) { error in
        XCTAssertTrue(error.localizedDescription.contains("workspace.md=developing"))
        XCTAssertTrue(error.localizedDescription.contains("STATUS.md=archived"))
    }

    XCTAssertEqual(try String(contentsOf: conflictURL.appendingPathComponent("workspace.md"), encoding: .utf8), conflictWorkspace)
    XCTAssertEqual(try String(contentsOf: conflictURL.appendingPathComponent("STATUS.md"), encoding: .utf8), conflictStatus)
    XCTAssertFalse(FileManager.default.fileExists(
        atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
    ))
}
```

- [ ] **Step 6: Run the new test and verify the store API/current-state guard is missing**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testNativeWorkspaceLifecycleStoreRejectsStaleAndConflictingEvidenceBeforeWriting
```

Expected: compile FAIL because `NativeWorkspaceLifecycleStore.update` does not accept `expectedState`; this missing API is the behavior under test, not a typo in the test.

- [ ] **Step 7: Require and validate the expected current lifecycle state**

Change the store signature:

```swift
static func update(
    request: UpdateWorkspaceLifecycleRequest,
    expectedState: String,
    fileManager: FileManager = .default
) throws -> UpdateWorkspaceLifecycleResponse {
```

Add these helpers:

```swift
private static func firstBulletValue(in text: String?, labels: [String]) -> String? {
    guard let text else { return nil }
    return labels.lazy.compactMap { extractBulletValue(in: text, label: $0) }.first
}

private static func normalizedCurrentState(_ raw: String, source: String) throws -> String {
    do {
        return try normalizedLifecycleState(raw)
    } catch {
        throw NativeWorkspaceLifecycleStoreError.unsupportedCurrentState(source, raw)
    }
}

private static func currentLifecycleState(
    workspaceContent: String?,
    statusContent: String?
) throws -> String {
    let workspaceRaw = firstBulletValue(
        in: workspaceContent,
        labels: ["当前状态", "状态"]
    )
    let statusRaw = firstBulletValue(
        in: statusContent,
        labels: ["当前状态", "状态"]
    )
    let workspaceState = try workspaceRaw.map {
        try normalizedCurrentState($0, source: "workspace.md")
    }
    let statusState = try statusRaw.map {
        try normalizedCurrentState($0, source: "STATUS.md")
    }

    if let workspaceState, let statusState, workspaceState != statusState {
        throw NativeWorkspaceLifecycleStoreError.conflictingCurrentStates(
            workspaceRaw ?? workspaceState,
            statusRaw ?? statusState
        )
    }
    return workspaceState ?? statusState ?? "unknown"
}

private static func normalizedExpectedState(_ value: String) throws -> String {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.lowercased() == "unknown" {
        return "unknown"
    }
    do {
        return try normalizedLifecycleState(trimmed)
    } catch {
        throw NativeWorkspaceLifecycleStoreError.unsupportedExpectedState(trimmed)
    }
}
```

After both snapshots are read, validate before building target content:

```swift
let currentState = try currentLifecycleState(
    workspaceContent: workspaceSnapshot.content,
    statusContent: statusSnapshot.content
)
let normalizedExpected = try normalizedExpectedState(expectedState)
guard currentState == normalizedExpected else {
    throw NativeWorkspaceLifecycleStoreError.staleConfirmation(
        expected: normalizedExpected,
        current: currentState
    )
}
let previousState = currentState
```

Add errors:

```swift
case unsupportedCurrentState(String, String)
case unsupportedExpectedState(String)
case conflictingCurrentStates(String, String)
case staleConfirmation(expected: String, current: String)
```

Add descriptions:

```swift
case .unsupportedCurrentState(let source, let state):
    return "unsupported current lifecycle state: \(source)=\(state)"
case .unsupportedExpectedState(let state):
    return "unsupported expected lifecycle state: \(state)"
case .conflictingCurrentStates(let workspaceState, let statusState):
    return "workspace lifecycle files conflict: workspace.md=\(workspaceState), STATUS.md=\(statusState)"
case .staleConfirmation(let expected, let current):
    return "workspace lifecycle changed since confirmation: expected \(expected), found \(current)"
```

- [ ] **Step 8: Pass the observed stage from every Native store call**

Update the invalid-document test from Step 1 and the existing store test calls to pass `expectedState: "developing"`.

In `AppState.confirmPendingLifecycleStatusUpdate`, pass:

```swift
),
expectedState: update.currentStage
```

In `testNativeStoresCanProveEndToEndWorkspaceLifecycle`, pass the latest scanned stage for archive:

```swift
),
expectedState: workspace.lifecycle.stage
```

Pass the known archived state for restore:

```swift
),
expectedState: "archived"
```

- [ ] **Step 9: Run focused conflict and success coverage**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeWorkspaceLifecycleStoreRejectsInvalidStatusBeforeChangingWorkspace|testNativeWorkspaceLifecycleStoreRejectsStaleAndConflictingEvidenceBeforeWriting|testNativeWorkspaceLifecycleStoreRequiresConfirmationAndRewritesStatusDocuments)'
```

Expected: 3 tests PASS. Existing success still writes both files and returns the matching lifecycle audit event.

- [ ] **Step 10: Commit the conflict-protection task**

```bash
git add native/Nexus/Sources/NexusApp/NativeWorkspaceLifecycleStore.swift \
    native/Nexus/Sources/NexusApp/AppState.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Protect Native lifecycle confirmations"
```

---

### Task 2: Roll Back Both Lifecycle Documents After Write Failure

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeWorkspaceLifecycleStore.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`
- Modify: `CHANGELOG.md:9`

**Interfaces:**
- Consumes: Task 1's exact `LifecycleDocumentSnapshot` values and validated `currentState`.
- Produces: `NativeWorkspaceLifecycleStore.update(request:expectedState:fileManager:writeFile:)`, where production uses Foundation atomic writes and tests can inject a deterministic second-write failure.

- [ ] **Step 1: Add a failing second-write rollback test**

Add this test beside Task 1's lifecycle safety tests:

```swift
func testNativeWorkspaceLifecycleStoreRollsBackBothDocumentsWhenSecondWriteFails() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-native-lifecycle-rollback-\(UUID().uuidString)")
    let workspaceURL = root.appendingPathComponent("workspace")
    let workspaceDocumentURL = workspaceURL.appendingPathComponent("workspace.md")
    let statusDocumentURL = workspaceURL.appendingPathComponent("STATUS.md")
    let auditRoot = root.appendingPathComponent("audit")
    defer {
        try? FileManager.default.removeItem(at: root)
    }
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    let originalWorkspace = "# Workspace\n\n- 当前状态: developing\n- 需求名称: Rollback Demo\n"
    let originalStatus = "# STATUS\n\n- 状态: developing\n- 当前焦点: Before write\n- 下一步: Keep original\n"
    try originalWorkspace.write(to: workspaceDocumentURL, atomically: true, encoding: .utf8)
    try originalStatus.write(to: statusDocumentURL, atomically: true, encoding: .utf8)

    var writeCount = 0
    XCTAssertThrowsError(
        try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: "archived",
                focus: "Should roll back",
                nextAction: "Keep both originals",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedState: "developing",
            writeFile: { content, url in
                writeCount += 1
                if writeCount == 2 {
                    throw NSError(
                        domain: "NativeWorkspaceLifecycleStoreTests",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "injected STATUS.md write failure"]
                    )
                }
                try content.write(to: url, atomically: true, encoding: .utf8)
            }
        )
    ) { error in
        XCTAssertTrue(error.localizedDescription.contains("injected STATUS.md write failure"))
    }

    XCTAssertEqual(writeCount, 4)
    XCTAssertEqual(try String(contentsOf: workspaceDocumentURL, encoding: .utf8), originalWorkspace)
    XCTAssertEqual(try String(contentsOf: statusDocumentURL, encoding: .utf8), originalStatus)
    XCTAssertFalse(FileManager.default.fileExists(
        atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
    ))
}
```

- [ ] **Step 2: Run the rollback test and prove the writer/transaction behavior is absent**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testNativeWorkspaceLifecycleStoreRollsBackBothDocumentsWhenSecondWriteFails
```

Expected: compile FAIL because the store does not yet accept `writeFile`; after adding only the closure parameter and sequential injected writes, it must fail the content assertions until rollback exists.

- [ ] **Step 3: Add the narrow writer seam and compensating rollback**

Extend the store signature with this defaulted final parameter:

```swift
writeFile: (String, URL) throws -> Void = { content, url in
    try content.write(to: url, atomically: true, encoding: .utf8)
}
```

Add restoration helpers:

```swift
private static func restore(
    _ snapshot: LifecycleDocumentSnapshot,
    fileManager: FileManager,
    writeFile: (String, URL) throws -> Void
) throws {
    if let content = snapshot.content {
        try writeFile(content, snapshot.url)
    } else if fileManager.fileExists(atPath: snapshot.url.path) {
        try fileManager.removeItem(at: snapshot.url)
    }
}

private static func restoreSnapshots(
    snapshots: [LifecycleDocumentSnapshot],
    fileManager: FileManager,
    writeFile: (String, URL) throws -> Void
) -> [String] {
    snapshots.compactMap { snapshot in
        do {
            try restore(snapshot, fileManager: fileManager, writeFile: writeFile)
            return nil
        } catch {
            return "\(snapshot.url.lastPathComponent): \(error.localizedDescription)"
        }
    }
}
```

Replace the two direct writes with:

```swift
do {
    try writeFile(nextWorkspaceContent, workspaceDocumentURL)
    try writeFile(nextStatusContent, statusDocumentURL)
} catch {
    let writeFailure = error.localizedDescription
    let restoreFailures = restoreSnapshots(
        snapshots: [statusSnapshot, workspaceSnapshot],
        fileManager: fileManager,
        writeFile: writeFile
    )
    if !restoreFailures.isEmpty {
        throw NativeWorkspaceLifecycleStoreError.rollbackFailed(
            writeFailure: writeFailure,
            rollbackFailures: restoreFailures
        )
    }
    throw NativeWorkspaceLifecycleStoreError.writeFailed(writeFailure)
}
```

Add error cases:

```swift
case writeFailed(String)
case rollbackFailed(writeFailure: String, rollbackFailures: [String])
```

Add descriptions:

```swift
case .writeFailed(let reason):
    return "workspace lifecycle write failed and original documents were restored: \(reason)"
case .rollbackFailed(let writeFailure, let rollbackFailures):
    return "workspace lifecycle write failed and rollback is incomplete: \(writeFailure); \(rollbackFailures.joined(separator: "; "))"
```

- [ ] **Step 4: Run all lifecycle safety and end-to-end lifecycle tests**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeWorkspaceLifecycleStoreRejectsInvalidStatusBeforeChangingWorkspace|testNativeWorkspaceLifecycleStoreRejectsStaleAndConflictingEvidenceBeforeWriting|testNativeWorkspaceLifecycleStoreRollsBackBothDocumentsWhenSecondWriteFails|testNativeWorkspaceLifecycleStoreRequiresConfirmationAndRewritesStatusDocuments|testNativeStoresCanProveEndToEndWorkspaceLifecycle)'
```

Expected: 5 tests PASS. The rollback test performs four writer calls: two target attempts followed by restoration of `STATUS.md` and `workspace.md`.

- [ ] **Step 5: Document the safe-write behavior**

Add this bullet at the top of the `[Unreleased]` `Added` list in `CHANGELOG.md`:

```markdown
- Native lifecycle writeback now rejects stale or contradictory Markdown state and restores both lifecycle documents after an in-process write failure before emitting success audit feedback.
```

- [ ] **Step 6: Run the complete Native Swift suite**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox --package-path native/Nexus
```

Expected: all Swift tests PASS, including scanner conflict behavior, lifecycle confirmation UI models, and create-to-archive-to-restore proof.

- [ ] **Step 7: Commit the independently verified rollback task**

```bash
git add native/Nexus/Sources/NexusApp/NativeWorkspaceLifecycleStore.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift \
    CHANGELOG.md
git commit -m "Rollback partial Native lifecycle writes"
```
