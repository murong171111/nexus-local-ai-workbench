# Native Task Write Conflict Protection Design

## Context

`TaskStatusUpdate` already records the task title, current status, and source line shown in the confirmation sheet. `NativeWorkspaceTaskStore.update` receives only the requested `taskId` and new status. Ordinary task IDs are derived from table order (`task-0`, `task-1`, and so on), so inserting a row after the sheet opens can make the old ID identify a different task. Agent task IDs derive from `event=` markers; duplicate markers can make the current loop update multiple rows and return only the last one.

The store checks that `tasks.md` exists but follows symlinks and other non-regular filesystem objects. It writes the entire file atomically and emits the optional success audit afterward, but it has no optimistic conflict check against the task evidence the user confirmed.

This is the sixth delivery slice of the Native M1 Truthful Workflow goal.

## Goal

Native task-status writeback must update exactly the task row the user confirmed, reject stale or ambiguous task evidence before mutation, and accept only a regular UTF-8 `tasks.md` file.

## Non-Goals

- Change the public `UpdateWorkspaceTaskRequest` or the legacy Rust bridge behavior.
- Add a file revision registry, hash field, lock service, or generalized compare-and-swap framework.
- Reject unrelated edits elsewhere in `tasks.md` when the confirmed task row is still identifiable and unchanged.
- Change task ID generation, task status vocabulary, Task Center filtering, or confirmation UI layout.
- Make optional audit append mandatory or alter existing audit failure response semantics.

## Approaches Considered

### 1. Compare only the previous status

This blocks a direct status change but can still update the wrong row when an inserted task inherits the old order-based ID and happens to have the same status.

### 2. Compare the confirmed task identity snapshot

This is the selected approach. The internal Swift store requires expected title, status, and optional source line. It first proves the ID has exactly one candidate, then compares that candidate with the confirmation snapshot before constructing or writing new content.

### 3. Compare a hash of the complete tasks document

An exact file revision catches every edit but makes an unrelated task change invalidate the current confirmation. That conflict boundary is broader than the user's write intent and would require another revision contract.

## Design

### Internal store contract

Keep `UpdateWorkspaceTaskRequest` unchanged and extend only the internal Native entry point:

```swift
static func update(
    request: UpdateWorkspaceTaskRequest,
    expectedTitle: String,
    expectedStatus: String,
    expectedSourceLine: Int?,
    fileManager: FileManager = .default
) throws -> UpdateWorkspaceTaskResponse
```

`AppState.confirmPendingTaskStatusUpdate` passes `TaskStatusUpdate.taskTitle`, `currentStatus`, and `taskSourceLine`. Direct Native tests and lifecycle proof setup pass values from the task snapshot they just observed.

### Strict document preflight

Before reading or parsing, the store obtains filesystem attributes for `tasks.md`:

- missing path keeps the existing `tasksMissing` error;
- an existing object whose type is not `.typeRegular` throws `tasksNotFile`;
- UTF-8 read failure throws `tasksUnreadable` with the path and underlying reason.

No task row, audit file, symlink target, or workspace document changes on preflight failure.

### Unique candidate resolution

Parse the complete file with the same table-row, task-index, source-line, and `event=` rules used by the write loop. Collect every `WorkspaceTaskSnapshot` whose ID equals `request.taskId`.

- Zero candidates throws the existing `taskNotFound` error.
- More than one candidate throws `ambiguousTaskID` and names the ID and count.
- Exactly one candidate proceeds to optimistic validation.

This prevents duplicate Agent event markers from updating multiple rows and ensures validation is performed before any in-memory mutation is accepted for writing.

### Confirmation snapshot validation

Sanitize the expected title and status with the same Markdown-cell rules used for table writes. The unique current candidate must satisfy:

- title equals `expectedTitle`;
- status equals `expectedStatus`;
- when `expectedSourceLine` is non-nil, source line equals that value.

Any mismatch throws `staleConfirmation` containing expected and current title, status, and line. An inserted row that shifts an order-based ID therefore cannot receive the old task's status update.

When the expected source line is nil, title and status still protect bridge-compatible task snapshots that did not carry a line. Changes to task detail alone do not block a status-only update because the store preserves current detail unless `request.detail` explicitly replaces it.

### Write and audit flow

After preflight and validation, reuse the existing row formatter and Foundation atomic file write. Because exactly one row owns the ID, the loop updates one row only. Build the response and append `workspace_task.updated` after the atomic write succeeds.

On stale, ambiguous, non-regular, unreadable, or missing evidence, throw before the write and before success audit append. The existing AppState catch path keeps the pending confirmation and exposes `lastError`; the success refresh, next-task focus, and local-write feedback stay unchanged.

## Error Handling

Add explicit localized errors for:

- `tasks.md` is not a regular file;
- `tasks.md` cannot be read as UTF-8;
- a task ID matches multiple rows;
- the confirmed title/status/source line no longer matches the unique current row.

Keep explicit confirmation, workspace validation, target-status validation, `taskNotFound`, and updated-row parsing behavior unchanged.

## Test Strategy

Extend `ModelBehaviorTests` with real temporary task files:

1. Open confirmation for a task at `进行中`, externally change it to `阻塞`, then submit the old expected status. Assert a stale error, byte-for-byte unchanged file, and no audit event.
2. Open confirmation for `task-0`, insert a new first row, then submit the old title/status/line. Assert the new row is not modified and no audit exists.
3. Create two Agent rows with the same `event=` marker. Assert the ambiguous ID is rejected and neither row changes.
4. Point `tasks.md` at an external file with a symlink. Assert preflight rejection, unchanged link target and workspace state, and no audit.
5. Keep the existing confirmed two-task writeback, AppState call path, and real end-to-end lifecycle proof green with explicit expected snapshots.

## Success Criteria

1. A task status changed after confirmation cannot be overwritten by the stale sheet.
2. Inserting or reordering task rows cannot make an old order-based ID update another title.
3. Duplicate stable-looking Agent IDs cannot update multiple rows.
4. Non-regular or unreadable `tasks.md` cannot be followed, replaced, or audited as a successful write.
5. A valid confirmed task still updates exactly one row atomically, returns audit feedback, refreshes Task Center, and preserves the Native lifecycle proof.
