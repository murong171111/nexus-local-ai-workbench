# Native Demand Intake Initialization Safety Design

Date: 2026-07-10

## Context

`NativeDemandIntakeStore.initialize` creates the fixed `需求/` directory and up to five standard Markdown files. The current operation confirms only a Boolean, checks paths with `fileExists`, creates the directory before validating all entries, and writes each missing file with replacement-capable atomic writes. AppState catches every Native error and retries through the legacy bridge.

This produces several violations of the Native M1 write contract:

- a workspace or `需求/` symlink can redirect writes outside the reviewed workspace;
- a broken file symlink can be treated as missing;
- a file created after the user confirms can be replaced by a generated template;
- a later write failure can leave a partially initialized directory without success audit;
- an unsafe Native failure can be retried by the bridge and bypass Native validation;
- a no-op initialize call can emit success feedback/audit despite creating nothing;
- the confirmation toggle is not bound to an immutable list of files and form values.

This is the tenth delivery slice of the Native M1 Truthful Workflow goal.

## Scope

This slice will:

- strictly inspect the workspace, `需求/`, and five fixed file paths;
- make Native status count only real directory and regular UTF-8 file evidence;
- create an immutable initialization plan when the user enables confirmation;
- freeze normalized demand name, link, notes, expected entry states, templates, and created-file list in that plan;
- reject any entry changing after confirmation;
- create new files with a race-safe no-overwrite primitive;
- roll back files and a newly created demand directory after an in-process failure;
- disable no-op initialization when all files already exist;
- keep existing regular UTF-8 files byte-for-byte unchanged;
- stop AppState from retrying Native status or write failures through the bridge;
- preserve success audit and feedback only after the complete write succeeds.

This slice will not:

- rewrite, repair, or normalize existing demand documents;
- change requirement readiness, scope parsing, demand-task transfer, task status, worktree, delivery, or lifecycle rules;
- add dynamic demand subdirectories;
- introduce locks, a registry, a generic CAS framework, or non-Apple dependencies;
- change Rust, Tauri, TypeScript, or bridge DTOs.

## Considered Approaches

### 1. Immutable Native plan plus no-overwrite transaction (selected)

Capture all seven relevant entries when the user checks confirmation: workspace directory, demand directory, and five fixed files. Execute only if every current entry still matches. Create missing files with Foundation's no-overwrite option and roll back anything this call created if a later step fails.

This binds the visible confirmation to one exact local state and protects the multi-file operation without a general transaction framework.

### 2. Strengthen only the store at click time

Strict inspection immediately before writing prevents symlink traversal and reduces races, but it does not prove that the generated file list or form values match what the user confirmed. The operation could silently adapt to external changes between confirmation and click.

### 3. Lock the workspace during initialization

A lock file or descriptor-based protocol could reduce inter-process races, but every external writer would need to honor it. It adds coordination complexity without fixing bridge fallback or confirmation fidelity. M1 uses exact state comparison plus no-overwrite creation instead.

## Entry State Contract

`NativeDemandIntakeEntryState` represents filesystem evidence:

- `missing`;
- `directory`;
- `regularUTF8(sha256:byteCount:)`;
- `invalid(reason:)`.

Inspection expands `~`, uses `attributesOfItem(atPath:)`, rejects symlinks and other non-regular objects, reads regular-file bytes, requires UTF-8, and hashes original bytes. Directories never follow symlinks.

Valid plan states are:

- workspace: `directory` only;
- demand path: `missing` or `directory`;
- each fixed file: `missing` or `regularUTF8`.

Any invalid state blocks planning with the exact path and reason.

## Initialization Plan

`NativeDemandIntakeInitializationPlan` contains:

- workspace path and expanded workspace URL path;
- normalized demand name, link, and notes;
- expected workspace and demand-directory states;
- five `NativeDemandIntakeFilePlan` values containing key, label, filename, path, expected state, and generated template;
- ordered `createdFiles` derived only from expected `missing` states;
- `blockerSummary` and `canInitialize`.

The plan is writable only when:

- all entries are safe;
- at least one fixed file is missing;
- form values and templates are frozen in the plan.

Existing regular files are included with exact revisions even though they are preserved. If a human edits one after confirmation, Nexus rejects the stale plan and asks for a new review rather than returning status derived from a different version.

## UI Confirmation

The existing checkbox remains the confirmation control. When it changes to checked:

1. AppState resolves an initialization plan from current form values and the real filesystem;
2. the view stores that plan in `@State`;
3. form fields become disabled until confirmation is unchecked;
4. the plan summary shows the exact ordered files that will be created or the blocking reason;
5. initialize action uses only the stored plan.

Unchecking clears the plan and re-enables form editing. A successful write also clears confirmation and the plan. No new sheet or card is introduced.

When no files are missing, initialize is disabled and the existing requirement-document action becomes the primary action. This prevents no-op writes and audits while preserving one credible main action.

## Store Preflight And Write Flow

`NativeDemandIntakeStore.initialize(plan:confirmed:)` executes in this order:

1. require explicit confirmation;
2. reject a blocked or no-change plan;
3. re-inspect workspace and require exact expected state;
4. re-inspect demand directory and require exact expected state;
5. re-inspect all five files and require exact expected states;
6. if demand directory was expected missing, create that direct child without intermediate directories;
7. create each expected-missing file in standard order using Foundation's `Data.write(options: [.withoutOverwriting])`;
8. record each file only after its write succeeds;
9. build strict status from the resulting filesystem;
10. create response;
11. append optional `demand_intake.initialized` success audit.

No directory or file mutation occurs before all seven comparisons pass.

## Rollback

If directory creation or any file write/status read fails after mutation starts:

1. remove only files successfully created by this operation, in reverse order;
2. if this operation created `需求/`, remove it only after created files are removed and it is empty;
3. never remove or rewrite entries that existed in the plan;
4. throw the original error when rollback succeeds;
5. if rollback itself fails, throw a recovery error listing remaining created paths.

No success response, audit, or AppState feedback is produced on failure.

## Race Policy

Strict rejection applies to every post-confirmation state change:

- demand directory appears, disappears, or changes type: reject;
- missing file appears: reject;
- existing file changes, disappears, or changes type: reject;
- symlink, directory, unreadable, or invalid UTF-8 entry: reject;
- second submission: reject because the first write changed missing states to regular files;
- unchanged safe plan: create each missing file once.

The no-overwrite write option closes the remaining race between final comparison and file creation. If an external writer wins that race, Nexus gets an error, rolls back its own earlier files, and preserves the external entry.

## Native-Only AppState Behavior

Demand-intake status and initialization are Swift-owned M2 local-core domains. AppState will no longer retry Native errors through `bridge.readDemandIntakeStatus` or `bridge.initializeDemandIntake`.

- status success updates the cached status;
- status failure exposes the Native error and stores the conservative all-missing fallback without claiming bridge evidence;
- initialization failure preserves the confirmed plan in the view, exposes the Native error, restores busy state, and emits no success feedback;
- initialization success refreshes Native state and publishes the existing success feedback.

This prevents permission, path, conflict, or safety failures from being converted into legacy/Preview success.

## Status Semantics

`NativeDemandIntakeStore.status` uses the same strict inspector:

- `需求/` exists only for a real directory;
- a fixed document exists only for a regular UTF-8 file;
- symlinks, directories, invalid UTF-8, and unreadable entries do not count as ready evidence;
- plan resolution provides the precise blocker reason when initialization is considered.

The public bridge DTO remains unchanged; strict diagnostic detail stays Native-only.

## Tests

Focused tests will cover:

- strict workspace, demand-directory, and file entry states;
- status excluding symlink, directory, invalid UTF-8, and unreadable evidence;
- plan created-file ordering, frozen templates, no-op block, and unsafe blockers;
- confirmation-time demand-directory and five-file changes;
- workspace/demand/file symlink rejection;
- external file creation after preflight with no overwrite;
- rollback after the second or later file write fails;
- existing files preserved exactly;
- duplicate second submission rejected without duplicate audit;
- action policy choosing initialize only when real changes are needed;
- UI/AppState using the stored plan and never falling back to the bridge;
- existing Native lifecycle end-to-end initialization order;
- complete Swift package tests and `git diff --check`.

Tests use temporary directories and injected Foundation/FileManager seams only where deterministic race or rollback failure requires them. No test writes in the user's home directory.

## Residual Risk

The demand directory can still be changed by another process between its final inspection and the first child creation. Each child uses a no-overwrite operation and final status is strict, so external files are not overwritten; rollback removes only paths created by Nexus. Fully eliminating directory replacement races would require descriptor-relative `openat` operations or filesystem coordination, outside M1.

## Acceptance Criteria

- Confirmation freezes form values, exact entry states, templates, and created-file list.
- Unsafe objects never count as ready demand evidence or receive Native writes.
- Any detectable state change after confirmation is rejected before mutation.
- An external file winning the final creation race is preserved.
- Partial initialization rolls back all Nexus-created files and its new empty directory.
- Existing regular UTF-8 files are never modified.
- No-op and duplicate submissions produce no write, audit, or success feedback.
- Native write/status errors never fall back to bridge or Preview behavior.
- Successful initialization creates only the reviewed missing files in fixed order and audits after completion.
- The full Native Swift suite passes and the slice receives independent task and whole-branch review before push.
