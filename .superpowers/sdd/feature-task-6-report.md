# Feature-Centered Demand Workflow Task 6 Report

## Status

DONE

## Implemented

1. Added a pure `FeatureCompletionEvaluator` for code, SQL, documentation, and manual policies. Read failures, blockers, incomplete tasks, missing attribution, failed tests, and stale test timing prevent completion; manual policy never completes automatically.
2. Added read-only `NativeFeatureEvidenceStore` collection from explicitly attributed task rows, feature-declared services and paths, Git messages/status, risks, and optional structured `feature-evidence.json` receipts. Missing optional receipts are allowed; malformed timestamps, unsafe/missing artifacts, Git failures, and malformed receipts become visible read errors.
3. Added revision-bound, explicitly triggered batch completion in `NativeFeatureStore`. It atomically completes eligible features or marks done evidence stale, rejects passive/stale writes, and records exact evidence, policy, actor, source revision, and previous/next status in one audit event per transition.
4. Connected successful user local checks and configured scheduled checks to evidence evaluation. Ordinary scanning remains read-only. Local-check results surface completed feature IDs and evidence-stale review signals without downgrading existing attention status.
5. Added compact feature-row conclusions, collapsed exact evidence details, a primary `证据待复核` signal, and reasoned completion reversal through the existing confirmation flow. Reversal writes `feature.completion_reverted` and returns the feature to `verifying`.
6. Bound evidence collection to the exact `FEATURES.md` revision used to create the write plan, so configuration edits between collection and planning are rejected.

## Evidence Contract

- Code: an explicitly attributed change, one or more attributed test receipts, no failed/missing tests, and a latest passing test at or after the latest related change.
- SQL: explicitly attributed formal and rollback SQL paths, plus any declared test gates.
- Documentation: an explicitly attributed existing document path, plus any declared test gates.
- Manual: user confirmation only.
- Done feature: later related changes, failed evidence, blockers, or read failures mark evidence stale without reopening the feature.

`feature-evidence.json` is optional and is not created for empty workspaces. Receipt version 1 records `id`, `kind`, `featureIDs`, `status`, `recordedAt`, and optional local `path`.

## TDD And Regression Evidence

- RED: evaluator, evidence store, batch APIs, AppState trigger, reversal mutation, automation signal, and UI presentation tests each failed on their missing interfaces before implementation.
- Focused evidence/completion matrix: 21 tests, 0 failures.
- `FeatureWorkflowTests`: 147 tests, 0 failures (included in the final Native suite).
- `npm run native:test`: 377 tests, 0 failures.
- `npm run native:m1-acceptance`: 3 tests, 0 failures.
- `git diff --check`: 0 whitespace errors.

## Changed Files

- `native/Nexus/Sources/NexusApp/FeatureCompletionEvaluator.swift`
- `native/Nexus/Sources/NexusApp/NativeFeatureEvidenceStore.swift`
- `native/Nexus/Sources/NexusApp/FeatureModels.swift`
- `native/Nexus/Sources/NexusApp/NativeFeatureStore.swift`
- `native/Nexus/Sources/NexusApp/AppState.swift`
- `native/Nexus/Sources/NexusApp/NativeLocalAutomationCheck.swift`
- `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

## Residual Scope

Task 7 owns new-workspace template minimization and legacy feature migration. Task 8 owns end-to-end documentation, including the user/Codex receipt-writing contract.
