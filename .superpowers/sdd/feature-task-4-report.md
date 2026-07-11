# Feature-Centered Demand Workflow Task 4 Review Hardening Report

## Status

DONE

## Review Findings Resolved

1. Proposal reviews now carry the confirmed and draft strict revisions. Merge requests pass the reviewed revisions into planning, reject either stale document, refresh the review, and use per-workspace refresh generations so older asynchronous results cannot overwrite newer reviews.
2. Merge reopens the fixed workspace FD, reloads both documents, rebuilds the deterministic diff, and verifies captured documents/items before writing. Selections are limited to actionable IDs; replacements are limited to selected add/change IDs; forged items, assigned IDs, selections, and replacement keys are rejected without changing `FEATURES.md`.
3. Diff ignores lifecycle and completion history. Change applies only Task 4 scope fields while preserving current status, completion fields, and evidence staleness. Add always writes a clean `todo` feature with no completion history and `evidenceStale=false`.
4. Proposal parsing rejects malformed `DRAFT-` headings, including nonnumeric IDs, short IDs, and missing titles. Confirmed parsing retains Task 3 ordinary H2 behavior and strict malformed numeric `F-` rejection.
5. Proposal confirmation now synchronously takes the pending operation before starting asynchronous I/O. Dialog dismissal and explicit cancellation synchronously cancel only an untaken pending operation, leaving in-flight busy/token state intact.
6. Archive recovery has a post-rename/pre-verify hook. Rollback requires the live draft to remain missing and the archive to retain the original draft identity and fingerprint; otherwise recovery is required and external archive/recovery files are not moved.

## TDD Evidence

- Revision binding/generation RED: compilation failed on missing review revisions and refresh hook. GREEN: focused proposal tests passed 17/17.
- Plan forgery RED: four forged-plan tests wrote target bytes and produced 8 failures. GREEN: 4/4 passed with target bytes unchanged.
- Scope-only RED: three tests produced 7 failures, including lost history and forged add lifecycle. GREEN: 3/3 passed.
- Malformed heading RED: malformed `DRAFT-ABC` and missing-title headings were accepted. GREEN: 1/1 passed.
- Dialog RED: compilation failed on missing `writeConfirmedFeatureProposal`. GREEN: dismissal, cancellation, and workspace/token tests passed 3/3.
- Archive recovery RED: compilation failed on the missing post-rename hook. GREEN: hook rollback, external replacement, and directory draft tests passed 3/3.

## Final Verification

1. `swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testFeatureProposal'`
   - PASS: 30 tests, 0 failures.
2. `swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests'`
   - PASS: 107 tests, 0 failures.
3. `npm run native:test`
   - PASS: 337 tests, 0 failures.
4. `npm run native:m1-acceptance`
   - PASS: 3 tests, 0 failures.
5. `git diff --check`
   - PASS: 0 whitespace errors.
6. Final re-review of `6d153c7..f35acdf`
   - APPROVED: no Critical, Important, or Minor findings.

## Files Changed In Review Revision

- `native/Nexus/Sources/NexusApp/AppState.swift`: +38/-18.
- `native/Nexus/Sources/NexusApp/FeatureProposalDiff.swift`: +7/-1.
- `native/Nexus/Sources/NexusApp/NativeFeatureStore.swift`: +98/-29.
- `native/Nexus/Sources/NexusApp/Views/FeatureProposalReviewView.swift`: +4/-3.
- `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`: regression coverage added.
- `.superpowers/sdd/feature-task-4-report.md`: review hardening report updated.

## Self-Review

No Critical, Important, or requested Minor findings remain. The independent final re-review approved the hardened merge. Changes are limited to Task 4 implementation files, `FeatureWorkflowTests`, and this report; no Task 5+ behavior or dependency was added.

## Concerns

None.
