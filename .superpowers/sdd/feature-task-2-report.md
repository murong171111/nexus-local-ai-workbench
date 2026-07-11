# Feature-Centered Demand Workflow Task 2 Final Report

## Status

COMPLETE_WITH_ACCEPTED_LIMITATION

## Final Commit

- `Move Native demand IO off main actor`

## Final Fixes

1. Existing-draft replacement now has a scoped seam after the final revision check and before `RENAME_SWAP`. After the swap, Nexus opens the displaced old draft through the demand-directory descriptor with `O_NOFOLLOW`, verifies device/inode plus expected byte count and SHA-256, and only then removes it. A content mismatch swaps the entries back, restores the externally changed old draft, and reports a publication conflict.
2. Conditional cleanup for staged temporary files, first-published drafts, and attachments now requires both the expected device/inode and expected content fingerprint. Same-inode external writes are preserved and reported as conflicts. A temporary-file write or verification failure also preserves the name unless the complete expected bytes can still be proven.
3. `DemandInputDraft`, revisions, snapshots, attachment plans, and responses are `Sendable` value snapshots. AppState runs demand load, save, post-save load, attachment planning, source reads, hashing, writes, fsync, copy, and audit I/O in `Task.detached(priority: .userInitiated)`.
4. AppState updates Published, recovery, busy, partial-response, error, and handoff state only after awaiting background work. `beforeAttachmentResponse` and `currentDraft` remain MainActor operations; the local `beforeDestinationWrite` seam is the only blocking test hook passed to the detached copy.
5. Prompt construction no longer performs a synchronous demand-store fallback read on MainActor. `openFeatureIntakeInCodex` first awaits the background load and then builds the prompt from AppState state.

## Regression Coverage

- Existing draft changed in place, with the same inode, after final revision check and before swap: save fails, swaps back, and preserves the external bytes.
- First-published missing draft and attachment changed in place after publication: cleanup does not unlink the external update and reports conflict.
- Staged temporary file whose own write cannot produce the expected complete fingerprint: the same-inode conflicting temporary entry is preserved.
- Attachment copy blocked at a local background destination-write seam: MainActor remains responsive, concurrent requirement/link edits are merged, and requirement, links, and verified relative attachment path are saved.
- Existing exact markers, autosave token behavior, recovery state, busy state, partial attachment responses, source-FD validation, descriptor safety, relative paths, audit feedback, and Codex handoff tests remain green.

## Final Verification

- `swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests'`
  - PASS: 39 tests, 0 failures.
- `swift build --disable-sandbox --package-path native/Nexus`
  - PASS.
- `npm run native:m1-acceptance`
  - PASS: 3 tests, 0 failures.
- `git diff --check`
  - PASS before commit.

## Concerns

- Accepted limitation: the final descriptor-relative fingerprint check and `unlinkat` cannot be made atomic with the available filesystem operations. A same-inode write in that final check-to-unlink interval remains possible; no nonexistent compare-and-swap guarantee is claimed.
