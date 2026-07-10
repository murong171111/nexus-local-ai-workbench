# Task 1 Report: Native lifecycle write-safety

## Status

- Completed Task 1 only.
- Implemented strict lifecycle document preflight before any write.
- Added required expected-state confirmation and existing-conflict protection.
- Did not implement rollback behavior from Task 2.

## Files

- Modified `native/Nexus/Sources/NexusApp/NativeWorkspaceLifecycleStore.swift`
- Modified `native/Nexus/Sources/NexusApp/AppState.swift`
- Modified `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

## RED Evidence

### Runtime RED: invalid `STATUS.md` caused a partial write before the fix

Command:

```bash
env HOME=/private/tmp/nexus-review-home XDG_CACHE_HOME=/private/tmp/nexus-review-cache CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testNativeWorkspaceLifecycleStoreRejectsInvalidStatusBeforeChangingWorkspace
```

Result:

- Exit code `1`
- Failure proved `workspace.md` changed from `developing` to `archived` before the invalid `STATUS.md` directory path threw
- Key assertion failure:

```text
XCTAssertEqual failed: ("# Workspace

- 当前状态: archived
") is not equal to ("# Workspace

- 当前状态: developing
")
```

### Compile RED: missing `expectedState` API

Command:

```bash
env HOME=/private/tmp/nexus-review-home XDG_CACHE_HOME=/private/tmp/nexus-review-cache CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testNativeWorkspaceLifecycleStoreRejectsStaleAndConflictingEvidenceBeforeWriting
```

Result:

- Exit code `1`
- Compile failure matched the brief:

```text
error: extra argument 'expectedState' in call
```

## Commands And Results

1. Added invalid-document regression test and ran the focused command above.
   - Result: runtime RED reproduced the partial write.
2. Implemented strict lifecycle document snapshots and unreadable/not-file errors.
3. Re-ran the invalid-document test.
   - Result: PASS, no partial write.
4. Added stale-confirmation and conflicting-evidence coverage and ran the focused command above.
   - Result: compile RED for missing `expectedState`.
5. Added `expectedState` to the store API, enforced current-state reconciliation, and updated every listed Native caller.
6. Ran:

```bash
env HOME=/private/tmp/nexus-review-home XDG_CACHE_HOME=/private/tmp/nexus-review-cache CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache swift test --disable-sandbox --package-path native/Nexus --filter 'ModelBehaviorTests/(testNativeWorkspaceLifecycleStoreRejectsInvalidStatusBeforeChangingWorkspace|testNativeWorkspaceLifecycleStoreRejectsStaleAndConflictingEvidenceBeforeWriting|testNativeWorkspaceLifecycleStoreRequiresConfirmationAndRewritesStatusDocuments)'
```

- Result: PASS, 3 tests, 0 failures.

7. Ran:

```bash
env HOME=/private/tmp/nexus-review-home XDG_CACHE_HOME=/private/tmp/nexus-review-cache CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testNativeStoresCanProveEndToEndWorkspaceLifecycle
```

- Result: PASS, 1 test, 0 failures.

## Commit Hashes

- Base commit before Task 1 work: `fc3933a98f922ba81afbbbeb4a4b58de440d7daf`
- Task 1 commit: `<pending>`

## Self-Review

- Verified both lifecycle documents are snapshotted and validated before any write.
- Verified stale confirmations fail before file mutation and before audit append.
- Verified conflicting `workspace.md` / `STATUS.md` state is rejected with both sources named in the error.
- Verified expected-state is threaded through the AppState confirmation path and the native end-to-end lifecycle tests.
- Verified work stayed scoped to the requested files plus this report.

## Concerns

- `swift test` emitted existing SwiftPM cache warnings about inaccessible user-level cache paths in this sandboxed environment. They did not block compilation or test execution.
