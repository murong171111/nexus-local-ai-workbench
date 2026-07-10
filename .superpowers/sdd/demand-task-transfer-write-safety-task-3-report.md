# Demand Task Transfer Write Safety Task 3 Report

## Status

DONE against baseline `ad906fd75169b1acf80586a3a6f5c30d8210a516`.

## RED

Added these tests before changing production code:

- `testNativeDemandTaskTransferStoreRejectsChangedDeletedAndUnsafeEvidence`
- `testNativeDemandTaskTransferStoreCreatesMissingOutputWhenStillMissing`
- `testNativeDemandTaskTransferStoreRejectsSecondSubmissionWithoutDuplicateAudit`

Ran the brief's three-test command. It exited 1 with 3 tests executed and 30 failures (2 reported as unexpected throws). The failures demonstrated that the old store:

- transferred after intake changes, deletion, symlink replacement, and invalid UTF-8 replacement;
- merged or recreated stale execution evidence and emitted audit events;
- failed the expanded missing-output path write;
- accepted a second submission, leaving two candidate rows and two `demand_tasks.transferred` events.

## GREEN

The same three-test command passed with 3 tests, 0 failures.

The direct store command from the brief passed with 4 tests, 0 failures:

- the nine-case conflict matrix;
- missing-output creation;
- duplicate-submission rejection;
- the existing transfer success and main-stage test.

`git diff --check` passed with no output.

## Implementation

`NativeDemandTaskTransferStore.transfer` now follows the required order:

1. Require confirmation.
2. Validate the expected intake revision.
3. Validate the expected execution revision.
4. Require an unblocked plan with transferable items.
5. Inspect both current documents using stable expanded URLs.
6. Reject path-specific invalid current evidence.
7. Compare the intake revision.
8. Compare the execution revision.
9. Build output from the confirmed execution snapshot or the standard missing-file header.
10. Atomically write to the same expanded execution URL used for inspection.
11. Create the response and optional audit event after the write.

Removed `readOrCreateExecutionTasksDocument`; transfer no longer creates a parent directory or performs a second output read before writing.

## Safety Checks

- All nine conflict cases assert exact intake and execution bytes or exact deletion state.
- Intake and execution symlink cases assert both the unchanged destination and unchanged external target bytes.
- Every rejected conflict asserts that no audit file exists.
- Missing-output success asserts one header, one Requirement Tasks section, one candidate row, and one audit event.
- Duplicate submission asserts one candidate row and one transfer audit event.

## Files

- `native/Nexus/Sources/NexusApp/NativeDemandTaskTransferStore.swift`
- `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`
- `.superpowers/sdd/demand-task-transfer-write-safety-task-3-report.md`

No plan, model, UI, `AppState`, or `CHANGELOG` files were changed.

## Commit

Commit message: `Protect Native demand task transfers`

The commit hash is reported after the report is included in the commit.

## Concerns

- Task 4 is intentionally not implemented.
- This task performs both comparisons before mutation, but it does not add file locking or compare-and-swap across the interval between final inspection and atomic replacement.
- Existing optional, best-effort audit behavior is preserved.
