# Feature-Centered Demand Workflow Task 3 Final Report

## Status

DONE

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
  - PASS: 76 tests, 0 failures.
- `npm run native:test`
  - PASS: 306 tests, 0 failures.
- `npm run native:m1-acceptance`
  - PASS: 3 tests, 0 failures.
- `git diff --check`
  - PASS.
- Final task re-review of `808d071..8e49ae6`
  - APPROVED: no Critical, Important, or Minor findings.

## Review Closure

- Four review/fix rounds closed strict path binding, conflict-safe publication and recovery, render injection, exact Markdown layout, cross-workspace confirmation, description editing, and busy-state token isolation.
- Task 4 proposal parsing and merge remain intentionally out of scope for this task.
