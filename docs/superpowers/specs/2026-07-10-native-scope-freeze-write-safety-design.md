# Native Scope Freeze Write Safety Design

Date: 2026-07-10

## Context

`NativeScopeFreezeStore` owns the confirmed M1 append to `需求/scope.md`. The current helper reads with `try?`, treats every read failure as empty content, then rewrites the complete path atomically. A missing file, symlink, directory, invalid UTF-8 document, permission failure, or external edit after the confirmation sheet opens can therefore be mistaken for an empty document or overwritten with stale evidence.

This is the eighth delivery slice of the Native M1 Truthful Workflow goal. It follows the same strict confirmation contract already used by lifecycle, task-status, and delivery-record writes: the user confirms one visible version, and Nexus rejects a different version instead of silently merging or replacing it.

## Scope

This slice will:

- capture the exact `scope.md` revision when `ScopeFreezeWritePlan` is resolved;
- block a plan whose scope path is missing, non-regular, unreadable, or invalid UTF-8;
- reject a changed, deleted, replaced, or newly unsafe scope document after confirmation;
- keep the existing successful append, atomic write, audit action, and AppState feedback behavior;
- prove stale AppState confirmation keeps its pending plan and emits no success audit;
- keep the real create-to-archive lifecycle test passing.

This slice will not:

- change demand-intake templates or scope-gate product rules;
- protect the separate `需求/tasks.md` to root `tasks.md` transfer contract;
- introduce automatic merge, retry, file locking, or a general compare-and-swap framework;
- change Rust, Tauri, TypeScript, bridge DTOs, or SwiftUI layout.

## Considered Approaches

### 1. Domain-specific exact scope revision (selected)

Add a small `NativeScopeDocumentRevision` beside `NativeScopeFreezeStore`. It records missing, exact regular UTF-8 SHA-256 plus byte count, or an invalid reason. The plan captures it and the store re-inspects immediately before appending.

This matches the existing domain-specific write-safety pattern, keeps the change local, and makes stale evidence explicit without refactoring already verified delivery code.

### 2. Extract a shared UTF-8 document revision framework

Move delivery-record revision logic into a generic utility and use it for scope writes. This removes some duplication, but expands the blast radius into an already completed slice and starts a shared abstraction before all remaining write contracts are understood.

### 3. Re-resolve scope evidence at confirmation time

Recomputing the plan just before writing would avoid some stale writes, but it would silently substitute new evidence for the version the user reviewed. It also would not distinguish unsafe file objects from ordinary missing state. This does not satisfy confirmation fidelity.

## Revision Contract

`NativeScopeDocumentRevision` has three states:

- `missing` when no filesystem entry exists at the expanded scope path;
- `regularUTF8(sha256:byteCount:)` for the exact bytes of a regular UTF-8 file;
- `invalid(reason:)` for symlinks, directories, other non-regular objects, unreadable data, or invalid UTF-8.

The digest is computed from the original bytes, not a normalized Swift string. Newline or encoding-byte changes therefore invalidate an open confirmation plan even when rendered Markdown looks similar.

`ScopeFreezeWritePlan.resolve` captures the revision through a defaulted `FileManager` parameter. Missing or invalid evidence produces a blocked plan with a concrete reason. A writable plan must have both the existing ready scope conditions and a regular UTF-8 expected revision.

## Confirmed Write Flow

`NativeScopeFreezeStore.write` uses this order:

1. require explicit confirmation;
2. reject missing or invalid expected revision;
3. require `plan.canWrite`;
4. strictly inspect the current expanded path;
5. reject missing or invalid current evidence;
6. require exact revision equality;
7. append the already reviewed freeze block to the current content;
8. write atomically to the same expanded URL that was inspected;
9. append optional `scope.freeze_confirmed` audit evidence.

No success response or audit event is created before the document write succeeds. A second submission of the same plan is stale because the first append changes the revision.

## Conflict Policy

All post-confirmation scope changes use strict rejection:

- regular file changed: reject;
- regular file deleted: reject;
- regular file replaced by symlink, directory, or invalid UTF-8: reject;
- missing or unsafe evidence at plan time: block before confirmation;
- duplicate second submission: reject;
- unchanged regular UTF-8 file: append once.

Nexus does not auto-merge external scope edits. The user must review the changed file and request a fresh confirmation plan.

## AppState Behavior

The existing `confirmPendingScopeFreezeWrite` success/catch ordering should already preserve the desired conflict behavior:

- success clears `pendingScopeFreezeWrite`, refreshes, focuses the workspace, and publishes local-write feedback;
- failure keeps the pending plan, exposes the localized error, and restores `isInitializingDemandIntake` through `defer`.

A real AppState test will lock this behavior. Production AppState code changes are allowed only if that test proves a defect.

## Tests

Focused tests will cover:

- plan revisions for regular, missing, symlink, and invalid UTF-8 scope paths;
- changed, deleted, newly symlinked, and newly invalid UTF-8 evidence after plan creation;
- unchanged successful append with exactly one audit event;
- duplicate second submission with no duplicate block or audit event;
- AppState stale confirmation retaining pending state, exact external content, error feedback, and idle state;
- the existing Native end-to-end lifecycle proof using a fresh scope plan before its append;
- the complete Swift package test suite and `git diff --check`.

Tests use real temporary files and do not write into the user's home directory.

## Error Messages

Localized errors distinguish:

- missing scope document;
- expected evidence that was already invalid when the plan was created;
- current evidence that is now unsafe;
- exact revision mismatch after confirmation;
- existing unconfirmed and not-writable plan failures.

The stale error includes `changed since confirmation` so AppState and users receive one clear next step: review `scope.md` and request confirmation again.

## Residual Risk

There remains a narrow time-of-check/time-of-use window between strict inspection and Foundation's atomic replacement. Closing it would require descriptor-level coordination or a filesystem compare-and-swap protocol. That complexity is outside M1 and is not introduced by this slice; the accepted M1 contract is exact preflight plus immediate atomic write.

## Acceptance Criteria

- A plan cannot write from missing or unsafe scope evidence.
- Any detectable external change after confirmation is preserved and rejected.
- A successful unchanged plan appends exactly one freeze block and one optional success audit.
- A duplicate submission cannot append twice.
- AppState keeps stale pending evidence and exposes the conflict without success feedback.
- Existing scope-gate and end-to-end lifecycle behavior remains green.
- The full Native Swift suite passes and the completed slice is independently reviewed before push.
