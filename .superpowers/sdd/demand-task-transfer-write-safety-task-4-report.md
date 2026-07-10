# Demand Task Transfer Write Safety Task 4 Report

## Status

Task-specific verification is complete against baseline `287a56cff3ddcee7727036331722603eaab217a9`.

`AppState.swift` was not changed: the new AppState interaction test passes against Task 3's existing Store-level stale-evidence protection.

## Coverage

Added `testAppStateDemandTaskTransferConfirmationKeepsStalePendingEvidence`.

The test creates a real temporary workspace with `workspace.md`, `STATUS.md`, root `tasks.md`, and all five ready `需求/*.md` documents, then scans it through `NativeWorkspaceScanner` into `WorkspaceSummary`. It creates `AppState` with `PreviewNexusBridge`, isolated `UserDefaults`, and temporary application support, and uses only public request/confirm APIs:

1. `requestDemandTaskTransfer(in:)` captures the writable pending plan.
2. An external edit appends a root-task row after confirmation opens.
3. `confirmPendingDemandTaskTransfer(confirmed: true)` rejects the stale root-task revision.

The assertions prove the pending plan remains identical, the error contains `changed since confirmation`, `isUpdatingTask` returns to false, root `tasks.md` remains the exact external edit, `需求/tasks.md` remains the original intake content, no success `localWriteFeedback` is emitted, and no audit file is created.

The existing `testNativeStoresCanProveEndToEndWorkspaceLifecycle` continues to resolve and transfer the demand-task plan after scope append and before worktree setup. No order-only edit was needed.

## Changelog

Added the requested Unreleased/Added note describing exact UTF-8 revision binding for intake candidates and root-task duplicate evidence.

## Commands And Results

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testAppStateDemandTaskTransferConfirmationKeepsStalePendingEvidence
```

Result: 1 test, 0 failures.

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testAppStateDemandTaskTransferConfirmationKeepsStalePendingEvidence|testDemandTaskTransferPlan.*|testMainStageBlocksUnsafeDemandTaskTransferEvidence|testNativeDemandTaskTransferStore.*|testNativeStoresCanProveEndToEndWorkspaceLifecycle)'
```

Result: 9 tests, 0 failures.

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox --package-path native/Nexus
```

Result: 207 tests, 3 failures in two unrelated Board tests:

- `testWorkspaceBoardColumnsFollowMainWorkflowOrder`
- `testWorkspaceBoardScopeFiltersWithoutChangingColumnOrder`

Both failures reproduce in a clean `git archive 287a56c` baseline with the same 2 tests and 3 failures, so this task does not alter or mask them.

```bash
git diff --check
```

Result: no output.

## Files

- `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`
- `CHANGELOG.md`
- `.superpowers/sdd/demand-task-transfer-write-safety-task-4-report.md`

`native/Nexus/Sources/NexusApp/AppState.swift` remains unchanged.

## Commit

Commit message: `Verify Native demand transfer conflict feedback`

The resulting commit hash is reported after this report is included in the commit.

## Concerns

- The complete Native Swift suite remains blocked by the two pre-existing Board tests above; their failures are documented rather than changed in this task.
- Demand-task transfer compares both evidence revisions before mutation but retains the existing narrow multi-file TOCTOU interval between final inspection and atomic replacement; no locking or compare-and-swap behavior was added.
