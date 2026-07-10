# Native Demand Intake Initialization Safety Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bind demand-intake initialization to an immutable strict filesystem plan, create only reviewed missing files without overwrite, roll back partial writes, and prevent AppState from bypassing Native errors through the bridge.

**Architecture:** `NativeDemandIntakeEntryState` describes workspace, demand-directory, and fixed-file evidence. A `NativeDemandIntakeInitializationPlan` freezes entry states, form values, templates, and created-file order; the store rechecks all entries before a no-overwrite transaction, while AppState and the existing SwiftUI section retain that exact plan through confirmation.

**Tech Stack:** Swift 5.10, Foundation, CryptoKit, SwiftUI, XCTest, SwiftPM.

## Global Constraints

- Keep all workflow behavior Swift Native-only; do not modify React, Tauri, Rust, TypeScript, or bridge DTOs.
- Workspace and demand directory must be real directories, never symlinks.
- Fixed demand documents must be missing or regular UTF-8, never symlinks, directories, unreadable data, or invalid UTF-8.
- Confirmation freezes normalized form values, exact entry states, templates, and ordered created files.
- Reject every detectable post-confirmation entry change before mutation.
- Use Foundation no-overwrite creation; never replace an externally created file.
- Roll back only entries created by the current call after any in-process failure.
- Existing regular files remain byte-for-byte unchanged.
- No-op and duplicate plans produce no file write, audit, or success feedback.
- Native status/write failures must not retry through the bridge.
- Preserve fixed filenames, template content, successful response/audit metadata, and existing requirement workflow rules.
- Do not add locks, a registry, generic CAS/transaction frameworks, or dependencies beyond Foundation/CryptoKit.

---

### Task 1: Build Strict Status And Immutable Initialization Plans

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeDemandIntakeStore.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Produces: `NativeDemandIntakeEntryState`.
- Produces: `NativeDemandIntakeFilePlan`.
- Produces: `NativeDemandIntakeInitializationPlan`.
- Produces: `NativeDemandIntakeStore.inspectEntry(at:fileManager:)`.
- Produces: `NativeDemandIntakeStore.makeInitializationPlan(workspacePath:demandName:lanhuLink:notes:fileManager:)`.
- Preserves: public `DemandIntakeStatus` and bridge response DTOs.

- [ ] **Step 1: Add a failing strict-status test**

Add `testNativeDemandIntakeStoreStatusRejectsUnsafeEntryEvidence`. Build independent temporary workspaces containing:

- a symlink at `需求/` pointing to an external directory;
- a symlink at `需求/tasks.md` pointing to an external UTF-8 file;
- a directory at `需求/tasks.md`;
- invalid UTF-8 bytes at `需求/tasks.md`.

For real workspace directories, call `status` and assert unsafe evidence never counts ready:

```swift
XCTAssertFalse(linkedDirectoryStatus.exists)
XCTAssertFalse(linkedDirectoryStatus.ready)
XCTAssertEqual(linkedDirectoryStatus.missingCount, 5)
XCTAssertFalse(linkedFileStatus.files.first { $0.key == "tasks" }?.exists ?? true)
XCTAssertFalse(directoryFileStatus.files.first { $0.key == "tasks" }?.exists ?? true)
XCTAssertFalse(invalidFileStatus.files.first { $0.key == "tasks" }?.exists ?? true)
```

Also pass a workspace symlink to `status` and assert its error contains `workspace path is not a real directory`.

- [ ] **Step 2: Add a failing immutable-plan test**

Add `testNativeDemandIntakeInitializationPlanCapturesStatesTemplatesAndNoOp`. Cover:

- missing `需求/` and all five files;
- existing real `需求/`, one existing regular file, and four missing files;
- unsafe demand directory;
- unsafe fixed file;
- all five regular files.

Assert:

```swift
XCTAssertEqual(missingPlan.expectedDemandDirectoryState, .missing)
XCTAssertEqual(
    missingPlan.createdFiles,
    ["requirement.md", "questions.md", "scope.md", "tasks.md", "delivery.md"]
)
XCTAssertTrue(missingPlan.canInitialize)
XCTAssertTrue(missingPlan.filePlans.first { $0.key == "requirement" }?.template.contains("会员权益页") == true)
XCTAssertTrue(missingPlan.filePlans.first { $0.key == "requirement" }?.template.contains("https://lanhu.example/design") == true)

XCTAssertEqual(partialPlan.createdFiles, ["requirement.md", "scope.md", "tasks.md", "delivery.md"])
XCTAssertNil(partialPlan.blockerSummary)
XCTAssertTrue(partialPlan.canInitialize)

XCTAssertTrue(unsafeDirectoryPlan.blockerSummary?.contains("not a real directory") == true)
XCTAssertTrue(unsafeFilePlan.blockerSummary?.contains("not a regular UTF-8 file") == true)
XCTAssertFalse(unsafeFilePlan.canInitialize)

XCTAssertTrue(completePlan.createdFiles.isEmpty)
XCTAssertTrue(completePlan.blockerSummary?.contains("already complete") == true)
XCTAssertFalse(completePlan.canInitialize)
```

Verify normalized demand name/link/notes and templates do not change if caller variables change after plan creation.

- [ ] **Step 3: Run the two tests and record RED**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeDemandIntakeStoreStatusRejectsUnsafeEntryEvidence|testNativeDemandIntakeInitializationPlanCapturesStatesTemplatesAndNoOp)'
```

Expected: missing APIs plus current symlink/file-existence assertions fail.

- [ ] **Step 4: Add entry states and strict inspection**

In `NativeDemandIntakeStore.swift`, import CryptoKit and add:

```swift
enum NativeDemandIntakeEntryState: Hashable {
    case missing
    case directory
    case regularUTF8(sha256: String, byteCount: Int)
    case invalid(reason: String)

    var label: String {
        switch self {
        case .missing:
            return "missing"
        case .directory:
            return "directory"
        case .regularUTF8(let sha256, let byteCount):
            return "regular UTF-8 \(byteCount) bytes sha256=\(sha256)"
        case .invalid(let reason):
            return "invalid: \(reason)"
        }
    }
}
```

Add `inspectEntry(at:fileManager:)`. It must expand `~`, use `attributesOfItem`, return `.missing` only for no-such-file, require real `.typeDirectory` or `.typeRegular`, reject symlinks, require regular-file UTF-8, and hash original bytes.

Change `checkedWorkspaceURL` to require `inspectEntry == .directory`. Change `status(for:)` so demand existence requires `.directory` and each file exists only for `.regularUTF8`.

- [ ] **Step 5: Add the immutable plan models and resolver**

Add:

```swift
struct NativeDemandIntakeFilePlan: Hashable, Identifiable {
    let key: String
    let label: String
    let filename: String
    let path: String
    let expectedState: NativeDemandIntakeEntryState
    let template: String
    var id: String { key }
}

struct NativeDemandIntakeInitializationPlan: Hashable {
    let workspacePath: String
    let demandDirectoryPath: String
    let demandName: String
    let lanhuLink: String
    let notes: String
    let expectedWorkspaceState: NativeDemandIntakeEntryState
    let expectedDemandDirectoryState: NativeDemandIntakeEntryState
    let filePlans: [NativeDemandIntakeFilePlan]
    let blockerSummary: String?

    var createdFiles: [String] {
        filePlans.compactMap { $0.expectedState == .missing ? $0.filename : nil }
    }
    var canInitialize: Bool { blockerSummary == nil && !createdFiles.isEmpty }
    var summary: String {
        if let blockerSummary {
            return blockerSummary
        }
        let preservedCount = filePlans.count - createdFiles.count
        return "will create \(createdFiles.joined(separator: ", ")); preserve \(preservedCount) existing files"
    }
}
```

`makeInitializationPlan` normalizes form values with the existing fallbacks, inspects the workspace/demand/files in fixed order, generates each template immediately, and chooses the first blocker in workspace → demand directory → file order. Existing regular files are safe; a complete plan gets the no-op blocker `demand intake is already complete; no files will be created`.

- [ ] **Step 6: Run status/plan tests and commit Task 1**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeDemandIntakeStoreReportsStatusFromWorkspaceFiles|testNativeDemandIntakeStoreStatusRejectsUnsafeEntryEvidence|testNativeDemandIntakeInitializationPlanCapturesStatesTemplatesAndNoOp)'
```

Commit:

```bash
git add native/Nexus/Sources/NexusApp/NativeDemandIntakeStore.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Plan strict Native demand intake initialization"
```

---

### Task 2: Execute A No-Overwrite Transaction With Rollback

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeDemandIntakeStore.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: Task 1 plan and strict entry state.
- Produces: `NativeDemandIntakeStore.initialize(plan:confirmed:auditRoot:actor:fileManager:fileWriter:)`.
- Preserves: immediate convenience overload for existing direct Native callers.
- Preserves: public response and successful audit metadata.

- [ ] **Step 1: Add a failing stale-entry matrix**

Add `testNativeDemandIntakeStoreRejectsChangedEntriesBeforeMutation`. Build a valid partial plan, then independently mutate:

- workspace directory replaced by symlink;
- missing demand directory externally created;
- existing file changed;
- existing file deleted;
- missing file externally created;
- existing file replaced by symlink;
- missing file replaced by broken symlink;
- existing file changed to invalid UTF-8.

Call `initialize(plan:confirmed:)`. Assert every call fails with `changed since confirmation` or the unsafe reason, no Nexus template replaces external bytes/targets, no new sibling file appears, and no audit file exists.

- [ ] **Step 2: Add deterministic race and rollback tests**

Add `testNativeDemandIntakeStorePreservesExternalNoOverwriteRaceAndRollsBack` using the injected writer. On the third requested file:

1. create external content at the destination;
2. call `data.write(to: url, options: [.atomic, .withoutOverwriting])` so it fails;
3. assert the first two Nexus files were removed;
4. assert the external third file remains exact;
5. assert later files and audit do not exist;
6. assert newly created `需求/` remains only because the external file prevents safe directory removal, and the error lists that recovery path.

Add `testNativeDemandIntakeStoreRollsBackPartialWriteFailure`. Inject a writer that performs the default no-overwrite write for the first two files and throws a sentinel error before the third. Assert all Nexus-created files and the newly created empty `需求/` directory are removed and no audit exists.

- [ ] **Step 3: Add successful, no-op, and duplicate tests**

Extend `testNativeDemandIntakeStoreInitializesMissingFilesWithoutOverwriting` to create a plan first and assert existing `questions.md` exact bytes remain.

Add `testNativeDemandIntakeStoreRejectsNoOpAndSecondSubmissionWithoutAudit`:

1. initialize one all-missing plan successfully;
2. submit the same plan again and assert stale/no-op rejection;
3. resolve a fresh complete plan and assert `canInitialize == false` and direct initialize rejects;
4. assert exactly one audit event.

- [ ] **Step 4: Run the new tests and record RED**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeDemandIntakeStoreRejectsChangedEntriesBeforeMutation|testNativeDemandIntakeStorePreservesExternalNoOverwriteRaceAndRollsBack|testNativeDemandIntakeStoreRollsBackPartialWriteFailure|testNativeDemandIntakeStoreInitializesMissingFilesWithoutOverwriting|testNativeDemandIntakeStoreRejectsNoOpAndSecondSubmissionWithoutAudit)'
```

Expected: current implementation mutates before full validation, may overwrite the race winner, leaves partial files, and audits no-op submissions.

- [ ] **Step 5: Implement exact preflight and transaction**

Define:

```swift
typealias NativeDemandIntakeFileWriter = (Data, URL) throws -> Void
```

Add `initialize(plan:..., fileWriter:)`, defaulting to:

```swift
{ data, url in
    try data.write(to: url, options: [.atomic, .withoutOverwriting])
}
```

Implement the exact flow from the design: confirmation, writable plan, workspace/demand/five exact comparisons, optional direct-child demand directory creation, ordered file creation, strict final status, response, then audit.

The compatibility overload constructs a plan and delegates immediately. It must not contain a second write path.

- [ ] **Step 6: Implement rollback and recovery errors**

Track `createdURLs` only after writer success and `createdDemandDirectory` only after directory creation success. In `catch`, remove created files in reverse order. Remove the new demand directory only if empty. If cleanup fails or external content keeps it nonempty, throw a recovery error containing all remaining Nexus-created or Nexus-owned recovery paths; otherwise rethrow the original error.

- [ ] **Step 7: Run store tests and commit Task 2**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/testNativeDemandIntakeStore.*'
```

Commit:

```bash
git add native/Nexus/Sources/NexusApp/NativeDemandIntakeStore.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Protect Native demand intake initialization"
```

---

### Task 3: Bind AppState And SwiftUI To The Confirmed Native Plan

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/DemandIntakeActions.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: Task 1 plan and Task 2 initialize entry point.
- Produces: `AppState.demandIntakeInitializationPlan(...)`.
- Produces: `AppState.initializeDemandIntake(plan:confirmed:)` with no bridge fallback.
- Preserves: current successful feedback copy and status cache.

- [ ] **Step 1: Add failing action-policy tests**

Extend `testDemandIntakeM1ActionPolicyKeepsAIInvocationOutOfPrimaryFlow` with a missing-file writable plan and a complete/no-op plan. Change policy input to accept `initializationPlan`.

Assert:

- initialize is primary and enabled only when confirmation is checked, plan can initialize, and not busy;
- unsafe plan keeps initialize primary but disabled;
- complete status makes `openRequirement` the sole primary action and initialize disabled;
- copy handoff is never primary.

- [ ] **Step 2: Add failing AppState Native-only error tests**

Add `@MainActor testAppStateDemandIntakeInitializationUsesConfirmedPlanWithoutBridgeFallback`:

1. create a real partial workspace and AppState with `PreviewNexusBridge`;
2. obtain a plan through AppState;
3. externally create one expected-missing file;
4. call AppState initialize with the stored plan;
5. assert response nil, Native `changed since confirmation` error remains, busy false, external file exact, no sibling template/audit/feedback.

Add `@MainActor testAppStateDemandIntakeStatusFailureDoesNotFallBackToPreviewBridge` using a missing or symlink workspace. Call refresh and assert `lastError` is the Native workspace-path error and the cached status is conservative missing evidence. Current code will replace it with Preview bridge unavailable text.

- [ ] **Step 3: Run tests and record RED**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testDemandIntakeM1ActionPolicyKeepsAIInvocationOutOfPrimaryFlow|testAppStateDemandIntakeInitializationUsesConfirmedPlanWithoutBridgeFallback|testAppStateDemandIntakeStatusFailureDoesNotFallBackToPreviewBridge)'
```

- [ ] **Step 4: Make AppState Native-only for demand intake**

Add synchronous plan resolution through `NativeDemandIntakeStore.makeInitializationPlan`.

Replace initialization's nested Native/bridge fallback with one call to `NativeDemandIntakeStore.initialize(plan:confirmed:auditRoot:actor:)`. Replace status refresh's bridge fallback with Native error handling that sets `lastError` and `fallbackDemandIntakeStatus`. Do not change unrelated bridge fallbacks.

- [ ] **Step 5: Update action policy and SwiftUI confirmation state**

Add `initializationPlan: NativeDemandIntakeInitializationPlan?` to the policy. Determine primary/enabled actions from real changes and plan safety.

In `WorkspaceDemandIntakeView` add:

```swift
@State private var initializationPlan: NativeDemandIntakeInitializationPlan?
```

When `confirmed` changes true, capture a plan from current form values; when false, clear it. Disable the three form fields while confirmed. Show `initializationPlan?.summary` below the checkbox. Pass the stored plan to AppState; do not re-resolve on click. Clear confirmation/plan only after success.

- [ ] **Step 6: Run focused tests and commit Task 3**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testDemandIntakeM1ActionPolicyKeepsAIInvocationOutOfPrimaryFlow|testAppStateDemandIntakeInitializationUsesConfirmedPlanWithoutBridgeFallback|testAppStateDemandIntakeStatusFailureDoesNotFallBackToPreviewBridge|testNativeDemandIntakeStore.*)'
```

Commit:

```bash
git add native/Nexus/Sources/NexusApp/AppState.swift \
    native/Nexus/Sources/NexusApp/DemandIntakeActions.swift \
    native/Nexus/Sources/NexusApp/Views/RootView.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Use confirmed Native demand intake plans"
```

---

### Task 4: Verify Lifecycle Compatibility And Complete Evidence

**Files:**
- Modify: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: completed strict Native initialization path.
- Produces: end-to-end and release-note evidence.

- [ ] **Step 1: Keep E2E on the convenience overload**

`testNativeStoresCanProveEndToEndWorkspaceLifecycle` may continue using the convenience overload because it resolves and executes immediately. Assert the response creates all five files and records one `demand_intake.initialized` audit before scope/transfer/worktree.

- [ ] **Step 2: Add changelog evidence**

At the top of `[Unreleased] / Added`, add:

```markdown
- Native demand-intake initialization now freezes a strict workspace/directory/file plan at confirmation, rejects symlinks and external changes, creates fixed Markdown files without overwrite, rolls back partial writes, and never retries Native safety failures through the legacy bridge.
```

- [ ] **Step 3: Run focused and complete verification**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testAppStateDemandIntake.*|testDemandIntakeM1ActionPolicy.*|testNativeDemandIntake.*|testNativeStoresCanProveEndToEndWorkspaceLifecycle|testRealDemandFilesKeepNativeStageSurfacesAligned)'
```

Then run the complete suite:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox --package-path native/Nexus
```

Run `git diff --check`. All must pass with zero failures/output.

- [ ] **Step 4: Commit Task 4**

```bash
git add native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift CHANGELOG.md
git commit -m "Verify Native demand intake safety"
```

---

## Final Review

Review the complete slice from the pre-design base through final implementation. Confirm:

- status and plans reject workspace/demand/file symlinks and unsafe objects;
- form values, templates, entry states, and file list are frozen at confirmation;
- all seven entries are compared before mutation;
- no-overwrite creation preserves an external race winner;
- rollback removes only Nexus-created files/directory and reports remaining recovery paths;
- existing files remain exact;
- no-op/duplicate plans do not write or audit;
- AppState status and initialize errors never fall back to bridge/Preview;
- UI stores one immutable plan, freezes form inputs, and shows one credible primary action;
- E2E audit order and fixed template contents remain compatible;
- unrelated demand readiness, scope, transfer, task, worktree, delivery, lifecycle, Rust, bridge DTOs, and legacy UI remain unchanged;
- the documented residual directory race is not expanded.

After clean task reviews and whole-branch review, push `main` through the configured GitHub SSH 443 key, fetch `origin/main`, and verify `HEAD == origin/main`.
