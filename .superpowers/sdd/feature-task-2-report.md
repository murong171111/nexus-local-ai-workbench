# Feature-Centered Demand Workflow Task 2 Final Report

## Status

COMPLETE_WITH_ACCEPTED_LIMITATION

## Final Commit

- `Serialize Native audit appends`

## Final Fixes

1. `AppState.saveDemandInputDraft` now enqueues an unstructured MainActor tail task per workspace. Each operation captures its workspace and draft, waits for the preceding operation to finish its disk result and state update, then reads the latest AppState baseline before starting detached store I/O.
2. Queued saves continue after caller cancellation. Per-workspace request counts keep busy state active until the final queued operation completes; `demandInputSavingWorkspaceID` remains published for compatibility, while `FeatureWorkspaceView` uses the workspace-aware active query.
3. The save implementation is isolated in `performDemandInputSave`. Different workspaces have independent tails and can advance while another workspace is waiting at its detached I/O boundary.
4. `featureIntakePrompt` is async. Its `changes.md` candidate probes run in `Task.detached`, while prompt rendering remains value-only. `openFeatureIntakeInCodex` awaits the prompt before performing MainActor clipboard and `NSWorkspace.open` work.
5. `NativeAuditEventStore.appendAsync` runs directory creation, seek, and write through `Task.detached`. `recordNativeAuditEvent` awaits it and only then updates `lastError`. `AuditEventInput` was already `Sendable`, so no bridge model change was required.
6. `NativeAuditEventStore.append` now holds one process-local static `NSLock` across directory creation, existence checks, file creation, seek, and write. `loadRecent` uses the same lock while reading and decoding, so App-process readers cannot observe a partial JSONL line. The `beforeAppend` test seam remains outside the lock; no cross-process locking guarantee is claimed.

## Regression Coverage

- The first same-workspace save is blocked at detached I/O while a second save is queued and its caller is cancelled. The first completes before the second starts, the second uses the new revision, and final disk/AppState/status/recovery/busy state belongs to the second draft.
- A blocked save in one workspace does not stop another workspace save from completing.
- A blocked production `changes.md` path probe leaves MainActor responsive and preserves the compact prompt plus `FEATURES.draft.md`-only contract.
- A blocked production async audit append leaves MainActor responsive and writes a readable audit event after release.
- Twenty parallel `appendAsync` calls preserve all unique actions, and every non-empty on-disk JSONL line decodes successfully.
- Existing exact markers, autosave token behavior, recovery state, attachment background I/O, source validation, and fingerprint cleanup tests remain green.

## Final Verification

- `swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests'`
  - PASS: 44 tests, 0 failures.
- `swift build --disable-sandbox --package-path native/Nexus`
  - PASS.
- `npm run native:m1-acceptance`
  - PASS: 3 tests, 0 failures.
- `git diff --check`
  - PASS before commit.

## Concerns

- Accepted pre-existing limitation: the final descriptor-relative fingerprint check and `unlinkat` cannot be atomic with available filesystem operations. A same-inode write in the final check-to-unlink interval remains possible; no compare-and-swap guarantee is claimed.
