# Feature-Centered Demand Workflow Task 3 Review Fix Report

## Status

IMPLEMENTED_FOCUSED_VERIFIED

## Findings

1. Critical TOCTOU: `NativeFeatureStore` now opens the workspace with `O_DIRECTORY | O_NOFOLLOW`, accesses `FEATURES.md` with `openat(..., O_NOFOLLOW)`, validates opened objects with `fstat`, and keeps one workspace FD through read, staging, final validation, and publish. Workspace-path and leaf-replacement race tests prove writes do not follow symlinks or reach another directory.
2. Final revision race: writes stage and verify data under the workspace FD, revalidate immediately before publish, use no-overwrite `linkat` for missing files, and use `RENAME_SWAP` plus fingerprint-checked cleanup/rollback for existing files. Deterministic tests preserve external content changed after the final check for both missing and existing revisions. This is conflict detection and recovery, not a claimed cross-process CAS.
3. Cross-workspace pending plan: pending plans are filtered by workspace ID/path and invalidated when `selectedWorkspaceID` changes. Confirmation titles include the workspace name, and AppState tests prove an A plan cannot appear or write in B.
4. Competing confirmation callbacks: the dialog binding setter no longer starts a cancellation task. Explicit confirm/cancel buttons are the only decision entry, and a small consumption policy makes a pending plan single-use.
5. Markdown preservation: metadata-only edits reuse `original.preservedLines` when the normalized description is unchanged. The round-trip test covers blank lines and an indented code block.
6. Non-F feature headings: identifier-shaped headings use the `PREFIX-NNN` contract before the `F-[0-9]{3,}` namespace check. `G-001` is rejected while ordinary level-two headings remain preamble.
7. Marker-like malformed attribution: whitespace variants around `feature =` are unlinked with warnings. Only exactly one literal `feature=F-[0-9]{3,}` is accepted.

## TDD Evidence

- RED: the nine new regression tests failed to compile against the missing hooks/policies, including extra `NativeFeatureStore.write` arguments and missing `FeatureEditState`, `FeatureConfirmationPolicy`, and workspace-scoped pending access.
- GREEN: `FeatureWorkflowTests` compiled and passed 65/65 after the implementation.

## Verification

- `swift test --disable-sandbox --package-path native/Nexus --filter FeatureWorkflowTests`
  - PASS: 65 tests, 0 failures.
- `git diff --check`
  - PASS before report update; rerun required before commit.
- `npm run native:test`
  - STARTED: all 65 `FeatureWorkflowTests` passed, then the suite made no progress in an unrelated `ModelBehaviorTests` path. Stack sampling showed `NativeWidgetSnapshotStore.write` blocked in Foundation `Data.write`/`open`. Terminated on user instruction; no full-suite count claimed.
- `npm run native:m1-acceptance`
  - STARTED, then terminated on user instruction after no test completion output. No M1 pass count claimed in this run.

## Remaining

- Re-run `npm run native:test` and `npm run native:m1-acceptance` in an environment where the existing widget snapshot file open completes.
