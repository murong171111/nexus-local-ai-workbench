# Native Task Write Conflict Protection Design

## Context

`TaskStatusUpdate` already records the task title, current status, and source line shown in the confirmation sheet. `NativeWorkspaceTaskStore.update` receives only the requested `taskId` and new status. Ordinary task IDs are derived from table order (`task-0`, `task-1`, and so on), so inserting a task row after the sheet opens can make the old ID identify a different task. Agent task IDs derive from `event=` markers; duplicate markers can make the current loop update multiple rows and return only the last one.

There is also a more basic Native contract mismatch. `NativeWorkspaceTaskStore` and Rust Core use `folder:task-<index>` or `folder:<event-id>`, while `NativeWorkspaceScanner` currently emits `task-<source-line>-<title-slug>`, marks every task as workspace-sourced, and does not expose `event=` identity. A real task loaded by the Native scanner can therefore fail to match the Native write store at all.

The store checks that `tasks.md` exists but follows symlinks and other non-regular filesystem objects. It writes the entire file atomically and emits the optional success audit afterward, but it has no optimistic conflict check against the task evidence the user confirmed.

This is the sixth delivery slice of the Native M1 Truthful Workflow goal.

## Goal

Native scanning and task-status writeback must share one file-backed task identity contract. Writeback must then update exactly the row the user confirmed, reject stale or ambiguous evidence before mutation, and accept only a regular UTF-8 `tasks.md` file.

## Non-Goals

- Change the public `UpdateWorkspaceTaskRequest` or the legacy Rust bridge behavior.
- Add a file revision registry, hash field, lock service, or generalized compare-and-swap framework.
- Reject unrelated edits elsewhere in `tasks.md`, including non-task line drift, when the confirmed task row is still uniquely identifiable and its title/status are unchanged.
- Change the established Rust/store task ID format, task status vocabulary, Task Center filtering, or confirmation UI layout.
- Make optional audit append mandatory or alter existing audit failure response semantics.

## Approaches Considered

### 1. Compare only the previous status

This blocks a direct status change but can still update the wrong row when an inserted task inherits the old order-based ID and happens to have the same status.

### 2. Share one parser, then compare the confirmed task identity snapshot

This is the selected approach. A small Native parser becomes the single source for scanner and store task identity, matching the existing Rust/store contract. The internal Swift store then requires expected title, status, and optional source line, proves the ID has exactly one candidate, and compares title/status with the confirmation snapshot before constructing or writing new content. Source line remains locating and diagnostic evidence, not an independent identity or compare-and-swap condition.

### 3. Compare a hash of the complete tasks document

An exact file revision catches every edit but makes an unrelated task change invalidate the current confirmation. That conflict boundary is broader than the user's write intent and would require another revision contract.

## Design

### Shared Native task parser

Add `NativeWorkspaceTaskParser` inside `NexusApp`. It parses root `tasks.md` table rows once and returns row records containing the exact table cells plus a `WorkspaceTaskSnapshot`. Both `NativeWorkspaceScanner` and `NativeWorkspaceTaskStore` consume these records.

The parser matches the established Rust/store contract:

- ordinary row ID: `<workspace-folder>:task-<task-index>`;
- row with `event=<id>` in detail: `<workspace-folder>:<event-id>`;
- source: `agent` when an event marker exists, otherwise `workspace`;
- source event ID, one-based Markdown source line, status, and detail use the same rules as the current store and Rust Core;
- a valid fourth-column `high`/`medium`/`normal`/`low` priority remains authoritative for Native tables; otherwise `priority=` and status/detail fallback preserve the existing store rules;
- title remains the real first table cell after trimming/backtick removal, so scanner and writer compare the same evidence.

The parser also owns table-row recognition, Markdown cell sanitization, row formatting, event-marker extraction, and task-priority derivation. This removes the two divergent Swift implementations without changing the public bridge model or Rust behavior.

`NativeWorkspaceScanner` passes the workspace folder into the parser, maps the returned snapshots directly, and keeps task counts derived from those snapshots. A Native-scanned task ID is therefore immediately accepted by the Native write store.

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

`AppState.confirmPendingTaskStatusUpdate` passes `TaskStatusUpdate.taskTitle`, `currentStatus`, and `taskSourceLine`. Direct Native tests and lifecycle proof setup pass values from the task snapshot they just observed. The source line locates the row for rewriting and appears in stale diagnostics, while canonical ID plus title/status provide the write conflict evidence.

### Strict document preflight

Before reading or parsing, the store obtains filesystem attributes for `tasks.md`:

- missing path keeps the existing `tasksMissing` error;
- an existing object whose type is not `.typeRegular` throws `tasksNotFile`;
- UTF-8 read failure throws `tasksUnreadable` with the path and underlying reason.

No task row, audit file, symlink target, or workspace document changes on preflight failure.

### Unique candidate resolution

Parse the complete file through `NativeWorkspaceTaskParser`. Collect every parsed row whose snapshot ID equals `request.taskId`.

- Zero candidates throws the existing `taskNotFound` error.
- More than one candidate throws `ambiguousTaskID` and names the ID and count.
- Exactly one candidate proceeds to optimistic validation.

This prevents duplicate Agent event markers from updating multiple rows and ensures validation is performed before any in-memory mutation is accepted for writing.

### Confirmation snapshot validation

Sanitize the expected title and status through `NativeWorkspaceTaskParser` using the same Markdown-cell rules used for table writes. The unique current candidate must satisfy:

- title equals `expectedTitle`;
- status equals `expectedStatus`.

Any title/status mismatch throws `staleConfirmation` containing expected and current title, status, and line. Source line is retained in that message to explain where the confirmed and current evidence came from, but non-task line drift alone does not reject a write. An inserted task row that makes an order-based ID identify a different title or status therefore cannot receive the old task's status update.

When the expected source line is nil, title and status still protect bridge-compatible task snapshots that did not carry a line. Changes to task detail alone do not block a status-only update because the store preserves current detail unless `request.detail` explicitly replaces it.

### Write and audit flow

After preflight and validation, replace the unique parsed row at its source line using the shared formatter and Foundation atomic file write. Build the updated snapshot through the same parser contract. Because exactly one row owns the ID, one row changes. Build the response and append `workspace_task.updated` after the atomic write succeeds.

On stale, ambiguous, non-regular, unreadable, or missing evidence, throw before the write and before success audit append. The existing AppState catch path keeps the pending confirmation and exposes `lastError`; the success refresh, next-task focus, and local-write feedback stay unchanged.

## Error Handling

Add explicit localized errors for:

- `tasks.md` is not a regular file;
- `tasks.md` cannot be read as UTF-8;
- a task ID matches multiple rows;
- the confirmed title/status no longer matches the unique current row; expected and current source lines remain diagnostic context.

Keep explicit confirmation, workspace validation, target-status validation, `taskNotFound`, and updated-row parsing behavior unchanged.

## Test Strategy

Extend `ModelBehaviorTests` with real temporary task files:

1. Scan an Agent row, update its scanner-produced ID through the store, then rescan to assert stable Agent ID/event/source line, changed status, and preserved fourth-column priority.
2. Open confirmation for a task at `进行中`, externally change it to `阻塞`, then submit the old expected status. Assert a stale error, byte-for-byte unchanged file, and no audit event.
3. Open confirmation for `task-0`, insert a new first row, then submit the old title/status/line. Assert the new row is not modified and no audit exists.
4. Create two Agent rows with the same `event=` marker. Assert the ambiguous ID is rejected and neither row changes.
5. Point `tasks.md` at an external file with a symlink. Assert preflight rejection, unchanged link target and workspace state, and no audit.
6. Confirm non-task text/blank-line drift accepts the uniquely resolved unchanged task while a newly inserted task row with changed title/status remains stale.
7. Confirm duplicate canonical Agent IDs at distinct source lines have distinct Task Center presentation IDs without changing their canonical write IDs.
8. Exercise AppState request/confirm: stale confirmation keeps pending state, file, and audit unchanged; a subsequent valid confirmation refreshes status, clears pending/error/updating state, emits local feedback, and focuses the next active task.
9. Keep the existing confirmed two-task writeback and real end-to-end lifecycle proof green with explicit expected snapshots from the shared parser.

## Success Criteria

1. Native scanner task IDs, sources, event IDs, priorities, and source lines come from the same parser the write store uses.
2. A task status changed after confirmation cannot be overwritten by the stale sheet.
3. Non-task line drift does not reject an unchanged unique task, while inserting or reordering task rows cannot make an old order-based ID update another title/status.
4. Duplicate stable-looking Agent IDs cannot update multiple rows.
5. Non-regular or unreadable `tasks.md` cannot be followed, replaced, or audited as a successful write.
6. Task Center presentation identity separates duplicate canonical task IDs by source line while preserving canonical task IDs for writes.
7. A valid confirmed scanned task still updates exactly one row atomically, returns audit feedback, refreshes Task Center, focuses the next active task, and preserves the Native lifecycle proof.
