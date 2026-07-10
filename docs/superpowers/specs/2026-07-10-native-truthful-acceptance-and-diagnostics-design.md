# Native Truthful Acceptance And Diagnostics Design

## Context

Native M1 requires every workspace status to come from local files and Git, and every local write to be explicit, conflict-safe, auditable, and testable. The current M1 acceptance card is rendered for one selected workspace but derives stage coverage and worktree-state coverage from the whole workspace list. Distribution readiness then evaluates the first workspace in that list. Separately, the Native environment check creates and removes a `.nexus-write-check` file to test directory writability.

## Decision

Use two explicitly named evidence scopes without adding a duplicate workspace model:

- Existing `WorkspaceMainStage` answers whether one workspace has a truthful current stage, one primary action, and routed evidence. It must remain the only status shown in the selected workspace's main action card.
- `MainWorkflowAcceptanceEvidence` remains the global M1 coverage artifact. It derives stage and worktree coverage from all scanned workspaces and is used by distribution readiness, not by an individual workspace's action card.

The workspace action card will display workspace evidence only. The global acceptance strip remains available in the distribution/readiness surface, where a cross-workspace coverage claim is meaningful.

Environment path checks must not create or delete files. A directory is reported writable only from filesystem metadata and `FileManager.isWritableFile(atPath:)`; the result is advisory because an actual confirmed write can still fail later. No marker file is created and no audit event is needed because the check has no side effects.

## Alternatives Considered

- Keep the current global aggregation and rename it. Rejected because the selected-workspace card would still present another workspace's evidence as its own.
- Make every M1 check workspace-local. Rejected because global stage/worktree coverage is a release-readiness property and needs a separate global artifact.
- Keep the write-marker probe but audit it. Rejected because a diagnostic should not mutate a user directory or leave cleanup failures behind.

## Behavior And Errors

- An incomplete selected workspace stays blocked even when other workspaces collectively cover every M1 stage.
- A global M1 coverage result stays deterministic regardless of list ordering and never uses `workspaces.first` as a proxy.
- Missing or non-directory configured paths remain blocked; existing non-writable directories remain warnings as before.
- A permission check is not a write guarantee. Every later write path retains its own confirmation, strict preflight, conflict protection, and audit behavior.

## Verification

- A failing API test proves that global acceptance is no longer exposed as if it belonged to a selected workspace.
- A failing test proves distribution readiness is stable when the workspace array is reordered.
- A failing test proves an environment check preserves a pre-existing user-owned `.nexus-write-check` file byte for byte.
- Run focused tests, the complete Swift suite, `npm test`, and `npm run build`.
