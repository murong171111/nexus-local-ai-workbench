# Native Demand Task Transfer Write Safety Design

Date: 2026-07-10

## Context

`DemandTaskTransferPlan` reads two user-owned Markdown documents:

- `需求/tasks.md` supplies the requirement candidates that the user is confirming;
- root `tasks.md` supplies the existing execution-task identities used for duplicate filtering and receives the append.

The current plan reads both with `try?` and converts every failure to empty text. It also unions root-task titles with an already scanned `workspace.tasks` snapshot. At confirmation time, `NativeDemandTaskTransferStore` re-reads only root `tasks.md`, then appends the candidates captured earlier. This creates four unsafe outcomes:

- missing, symlinked, unreadable, or invalid UTF-8 intake evidence can look like an empty task list;
- intake tasks changed after confirmation can still transfer stale candidates;
- root tasks changed after confirmation can invalidate duplicate filtering while still being silently merged;
- submitting one plan twice can append the same tasks and success audit twice.

This is the ninth delivery slice of the Native M1 Truthful Workflow goal.

## Scope

This slice will:

- capture strict byte revisions and decoded content for both intake and execution task documents in one plan resolution;
- require an existing regular UTF-8 `需求/tasks.md`;
- allow root `tasks.md` to be either missing or regular UTF-8 when the plan is created;
- derive duplicate identities only from the exact root-task snapshot attached to the plan;
- reuse `NativeWorkspaceTaskParser` for root task titles so scanner, status writeback, and demand transfer share one root-task interpretation;
- reject either document changing, appearing, disappearing, or becoming unsafe after confirmation;
- expose unsafe evidence as a blocked development-stage answer with one file-opening action;
- preserve pending AppState confirmation, external content, and error feedback on conflict;
- keep the existing successful append format and audit action.

This slice will not:

- change demand-task candidate selection, priority mapping, or Markdown row format;
- update intake-task statuses after transfer;
- auto-merge root task edits or re-resolve candidates after the user confirms;
- reorder service/branch or worktree stages;
- change task-status writeback, scope freeze, delivery, lifecycle, Rust, Tauri, TypeScript, or bridge DTOs;
- introduce locks, retries, a registry, a generic CAS framework, or new dependencies.

## Considered Approaches

### 1. Two strict domain snapshots with exact rejection (selected)

Add one demand-transfer document revision type used for both paths. Resolve the plan from two strict snapshots and persist both revisions. The store re-inspects both immediately before writing and requires exact equality.

This is the smallest contract that preserves confirmation fidelity for both the source rows and duplicate-filtering target.

### 2. Protect only root `tasks.md`

An output-only revision prevents overwriting or duplicate merging after an external root-task edit, but still transfers stale or removed intake candidates. The user would confirm version A while Nexus writes tasks no longer present in version B.

### 3. Re-resolve and merge at confirmation time

Re-reading both documents and recomputing candidates just before write reduces duplicates, but silently substitutes a new plan for the one the user reviewed. It also makes the visible transfer count and rows untrustworthy. This violates explicit confirmation.

## Document Revision Contract

`NativeDemandTaskDocumentRevision` has three states:

- `missing` when no entry exists at the expanded path;
- `regularUTF8(sha256:byteCount:)` for the exact original bytes of a regular UTF-8 file;
- `invalid(reason:)` for symlinks, directories, other non-regular objects, unreadable data, or invalid UTF-8.

`NativeDemandTaskDocumentSnapshot` carries the revision plus decoded content only for regular UTF-8 evidence. SHA-256 is computed from original bytes, so newline-only or encoding-byte changes invalidate an open plan.

The snapshot remains domain-specific and lives beside `NativeDemandTaskTransferStore`. No shared filesystem framework is introduced.

## Plan Resolution

`DemandTaskTransferPlan.resolve` inspects the intake and execution paths exactly once each and parses those snapshot contents:

1. resolve the two paths from `DemandIntakeStatus` and `WorkspaceSummary`;
2. strictly inspect `需求/tasks.md`;
3. strictly inspect root `tasks.md`;
4. parse candidates only from the intake snapshot content;
5. parse existing root titles only from the execution snapshot content through `NativeWorkspaceTaskParser`;
6. store both revisions, candidates, existing titles, and any blocker.

It does not union `workspace.tasks` into duplicate detection because that value may come from a different scan revision. Root task identity for this confirmation comes from the exact execution snapshot only.

### Safe states

- intake regular UTF-8 + execution regular UTF-8: resolve candidates and duplicates normally;
- intake regular UTF-8 + execution missing: allow first creation with the standard root Tasks header.

### Blocked states

- intake missing or invalid;
- execution invalid;
- any impossible snapshot/content inconsistency.

The plan gains a `blockerSummary` and `blockerPath`. `hasTransferableItems` is true only when no blocker exists and at least one candidate is not present in the exact execution snapshot.

No candidates and all candidates already present keep their existing non-transfer behavior; they are not treated as unsafe blockers.

## Main Path And Preview

An unsafe plan must not disappear from the main path and let development continue. `PrimaryWorkflowStageResolver` checks `blockerSummary` before `hasTransferableItems` and returns a blocked Development stage:

- title: task evidence unavailable;
- reason: exact blocker summary;
- one primary action: open the unsafe intake or execution task file;
- evidence: both `需求/tasks.md` and `tasks.md`.

The existing compact transfer preview uses the same model state:

- unsafe: blocked tone/title, transfer disabled, file actions remain available;
- transferable: existing ready-to-transfer state;
- no candidates: existing intake-needs-work state;
- all duplicates: existing already-transferred state.

No new card, sheet, or navigation surface is added.

## Confirmed Write Flow

`NativeDemandTaskTransferStore.transfer` uses this exact order:

1. require explicit confirmation;
2. reject an invalid expected intake revision;
3. reject an invalid expected execution revision;
4. require a blocker-free plan with transferable items;
5. strictly inspect current intake evidence;
6. strictly inspect current execution evidence;
7. reject unsafe current evidence;
8. require exact intake revision equality;
9. require exact execution revision equality;
10. build output from the current execution snapshot or the standard missing-file header;
11. append the already reviewed rows once;
12. atomically write to the same expanded execution URL that was inspected;
13. append optional `demand_tasks.transferred` success audit evidence.

Input evidence is never written. No directory or output mutation occurs before both comparisons succeed.

## Conflict Policy

Strict rejection applies to both documents:

- intake changed, deleted, or replaced: reject;
- root tasks changed, created, deleted, or replaced: reject;
- either current path becomes a symlink, directory, unreadable, or invalid UTF-8: reject;
- duplicate second submission: reject because root `tasks.md` changed after the first append;
- missing root tasks stays missing: create once;
- unchanged regular evidence: append once.

Nexus never auto-merges root-task edits or transfers candidates from a newer intake version under an older confirmation sheet. The user reviews the changed evidence and requests a fresh plan.

## AppState Behavior

The existing `confirmPendingDemandTaskTransfer` ordering should keep the pending plan on store failure and restore `isUpdatingTask` through `defer`. A real AppState test will assert:

- pending plan unchanged;
- `lastError` contains the changed-since-confirmation reason;
- `isUpdatingTask == false`;
- both source and target files retain exact external content;
- no success audit and no local-write success feedback.

Production AppState code changes are allowed only if the test proves a defect.

## Tests

Focused real-file tests will cover:

- strict plan snapshots for regular intake, missing output, regular output, missing intake, symlink, and invalid UTF-8;
- root duplicate titles derived from the exact execution snapshot rather than stale `workspace.tasks`;
- unsafe plans block the main stage and transfer preview action;
- intake changed/deleted/newly unsafe after confirmation;
- output changed/created/deleted/newly unsafe after confirmation;
- missing-to-missing first creation;
- duplicate second submission without duplicate row or audit;
- AppState conflict feedback and pending-plan retention;
- existing end-to-end Native lifecycle transfer order;
- complete Swift package tests and `git diff --check`.

Tests use temporary directories and original bytes. No test writes under the user's home directory.

## Residual Risk

There remains a narrow time-of-check/time-of-use window between final strict inspection and Foundation's atomic output replacement. Input could also change after final comparison while output is being written. Eliminating these windows requires descriptor-level locking or filesystem coordination across two files. M1 accepts exact immediate preflight plus atomic output write; this slice does not expand that residual risk.

## Acceptance Criteria

- The visible candidate rows and duplicate count derive from the exact two revisions stored in the plan.
- Unsafe input or output evidence blocks the main path with one relevant file action.
- Any detectable post-confirmation change to either document is preserved and rejected.
- Missing root tasks can be created only when it remains missing.
- An unchanged plan appends each reviewed candidate exactly once and audits only after write success.
- Duplicate submission cannot append or audit twice.
- AppState keeps stale pending evidence and exposes the conflict without success feedback.
- Existing candidate filtering, priority mapping, lifecycle proof, and task status behavior remain green.
- The full Native Swift suite passes and the slice receives independent task and whole-branch review before push.
