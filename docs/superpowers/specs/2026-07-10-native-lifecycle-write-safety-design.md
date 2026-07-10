# Native Lifecycle Write Safety Design

## Context

`NativeWorkspaceLifecycleStore.update` currently writes `workspace.md` and then `STATUS.md`. Each individual `String.write(..., atomically: true)` replaces one file atomically, but the pair is not a transaction: if the second write fails, `workspace.md` already contains the new state while `STATUS.md` still contains the old state. The file-backed scanner now reports that split state as blocked, but the Native write path should not create it.

The confirmation sheet already captures `LifecycleStatusUpdate.currentStage`, but the store does not receive or verify it. An external edit between opening the sheet and confirming can therefore be overwritten silently. Audit append already happens after both writes, so failed second writes create no success event but may still leave the files inconsistent.

This is the fifth delivery slice of the Native M1 Truthful Workflow goal.

## Goal

Native lifecycle updates must reject stale or contradictory file evidence and restore both lifecycle documents after any in-process write failure, with success audit events emitted only after both documents commit.

## Non-Goals

- Add a transaction journal or startup recovery for process termination, machine crash, or power loss between the two file replacements.
- Change Rust bridge lifecycle write behavior; Native Swift is the active product path and this store is internal to `NexusApp`.
- Change lifecycle transition eligibility, workflow gate order, or confirmation UI layout.
- Make audit append mandatory when no audit root is configured, or change the existing optional audit-failure response semantics.
- Generalize the transaction helper for unrelated stores before a second real caller needs it.

## Approaches Considered

### 1. Preflight validation only

Validate both document paths and the expected state before writing. This prevents predictable failures and stale confirmations but still leaves a partial update if the second write fails after preflight.

### 2. Expected-state validation plus snapshot rollback

This is the selected approach. Read strict snapshots of both documents, resolve their current canonical state, compare it with the state captured by the confirmation sheet, write both documents atomically one at a time, and restore both snapshots if either write throws. Keep a narrow injectable writer closure so the second-write failure and rollback can be proved deterministically in XCTest.

### 3. Persistent transaction journal and recovery

Write a journal containing both originals and targets, replace both files, and recover unfinished transactions on the next scan. This covers process death but adds a third persistence protocol, recovery ordering, cleanup, and migration behavior. The current goal requires conflict protection and verifiable local-write failure handling, not crash recovery without observed failures.

## Design

### Store contract

Change the internal Native store entry point to require the lifecycle stage observed when confirmation was prepared:

```swift
static func update(
    request: UpdateWorkspaceLifecycleRequest,
    expectedState: String,
    fileManager: FileManager = .default,
    writeFile: LifecycleFileWriter = atomicLifecycleFileWrite
) throws -> UpdateWorkspaceLifecycleResponse
```

`LifecycleFileWriter` is an internal closure type used only by the store and tests. Production keeps Foundation atomic file replacement. `AppState.confirmPendingLifecycleStatusUpdate` passes `update.currentStage`; direct Native store tests and lifecycle proof setup pass the state they just observed.

The shared bridge request model stays unchanged so this Native-only safety contract cannot be silently ignored by the legacy Rust implementation.

### Strict read and current-state resolution

Before computing new content, the store snapshots each document as either missing or present with exact UTF-8 content. A path that exists as a directory or cannot be read is an error; it no longer silently falls back to a blank template.

Current state comes from:

- `workspace.md`: `当前状态` or `状态`.
- `STATUS.md`: `当前状态` or `状态`.

Both values use the store's existing English and Chinese alias normalization. Resolution is conservative:

- Two equivalent recognized values resolve to their canonical state.
- One recognized value and one missing value resolve to the recognized state.
- Two missing values resolve to `unknown`.
- Two different recognized values throw a file-conflict error naming both values.
- Any unsupported non-empty value throws an unsupported-current-state error naming its file and raw value.

The required `expectedState` accepts canonical/alias lifecycle values plus `unknown`. If its normalized value differs from the current resolved value, the operation throws a stale-confirmation error containing expected and actual states. No document or audit file is changed.

### Write and rollback flow

After validation, the store builds both complete target strings in memory. It then:

1. Atomically replaces `workspace.md`.
2. Atomically replaces `STATUS.md`.
3. Builds the response and appends the existing optional success audit event.

If either replacement throws, the store restores both pre-write snapshots before returning an error. Present files are rewritten with their exact original content; files that were originally missing are removed if the failed attempt created them. Restoring both paths also covers a writer that modifies a file and then throws.

If restoration succeeds, the caller receives a write-failed error and neither lifecycle document contains the requested transition. If restoration itself fails, the caller receives a rollback-failed error that includes both the original write error and rollback error, so the UI cannot report a clean failure while hiding uncertain disk state. No success audit event is appended on either path.

This is an in-process compensating transaction, not crash-safe multi-file atomicity. Each individual replacement remains atomic, and the existing scanner will still expose any externally created or crash-created split state conservatively.

### App feedback

The existing `AppState` catch path already keeps the pending update and assigns `lastError`, so conflict, stale-confirmation, write, and rollback errors remain visible without adding UI controls. On success, refresh and local-write feedback remain unchanged.

## Error Handling

Add explicit localized errors for:

- lifecycle document path is not a regular file;
- lifecycle document cannot be read as UTF-8;
- unsupported current state with source and raw value;
- conflicting current file states with both values;
- stale confirmation with expected and current canonical states;
- write failure after successful restoration;
- rollback failure with both underlying error descriptions.

Do not swallow document-read or rollback errors. Keep the existing target-state validation and explicit-confirmation errors first in the flow.

## Test Strategy

Extend `ModelBehaviorTests` with real temporary workspaces:

1. Open a confirmation at `developing`, externally change both documents to `delivery`, then submit the old expected state. Assert a stale-confirmation error, byte-for-byte unchanged documents, and no lifecycle audit event.
2. Start with both documents at `developing`; inject a writer that throws on the second target write and succeeds during restoration. Assert the update throws, both files equal their exact originals, and no audit event exists.
3. Start with `workspace.md=developing` and `STATUS.md=archived`. Assert the store rejects the existing conflict before invoking the writer and names both source values.
4. Keep the existing confirmed success test, AppState lifecycle path, and real create-to-archive-to-restore proof green with explicit expected states.

The second test must prove RED before implementation: the current store has no writer seam or compensating transaction and leaves `workspace.md` changed when `STATUS.md` fails.

## Success Criteria

1. A confirmation cannot overwrite a lifecycle state that changed after the sheet was prepared.
2. Existing contradictory or unsupported lifecycle records cannot be silently normalized by a write.
3. A deterministic second-file write failure leaves both lifecycle documents byte-for-byte unchanged.
4. Failed, conflicted, or stale writes append no `workspace_lifecycle.updated` success audit event.
5. Successful updates still rewrite both files, return audit feedback, refresh the workspace, and preserve the Native end-to-end lifecycle proof.

