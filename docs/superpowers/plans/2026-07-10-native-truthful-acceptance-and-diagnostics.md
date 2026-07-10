# Native Truthful Acceptance And Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Keep selected-workspace workflow status separate from global M1 coverage, and make Native environment diagnostics read-only.

**Architecture:** Keep the existing `WorkspaceMainStage` as the selected-workspace evidence model and remove global acceptance from that card. Rename AppState's acceptance API to make its global scope explicit, and make distribution readiness consume that order-independent global result. Replace the environment write-marker probe with metadata-based writability inspection.

**Tech Stack:** Swift 6, SwiftUI, XCTest, Swift Package Manager.

## Global Constraints

- Native M1 state is derived from real workspace files and Git evidence.
- The selected workspace exposes one primary action and its own routed evidence only.
- Diagnostics must not create, modify, or remove files.
- Existing confirmed write flows retain their own conflict protection and audit logging.

---

### Task 1: Separate Selected Workspace Evidence From Global Coverage

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/MainWorkflowAcceptanceEvidence.swift`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Preserves: `WorkspaceMainStage` as the selected-workspace status and action source.
- Produces: `AppState.globalMainWorkflowAcceptanceEvidence()` for global M1 coverage.

- [x] **Step 1: Write failing ownership tests**

Add a compile-time API test that calls `globalMainWorkflowAcceptanceEvidence()` without a selected workspace argument. Add a distribution-readiness test that reverses the workspace list and expects the same M1 result.

- [x] **Step 2: Run the focused tests and confirm RED**

Run:

```zsh
swift test --package-path native/Nexus --filter 'ModelBehaviorTests/(testAppStateBuildsGlobalMainWorkflowAcceptanceEvidence|testNativeDistributionM1ReadinessDoesNotDependOnWorkspaceOrder)'
```

Expected: compile FAIL because the explicit global API does not exist and distribution readiness reads `workspaces.first`.

- [x] **Step 3: Implement the smallest scoped models and routing**

Remove `MainWorkflowAcceptanceEvidence` from `WorkspaceMainStageSummaryView`, including its M1 metric and acceptance strip. Rename AppState's method to `globalMainWorkflowAcceptanceEvidence()` and resolve all global inputs without a selected-workspace argument. Make `nativeDistributionReadinessEvidence` consume that result instead of selecting the first workspace.

- [x] **Step 4: Run focused and complete Native tests**

Run:

```zsh
swift test --package-path native/Nexus --filter 'ModelBehaviorTests/(testAppStateBuildsGlobalMainWorkflowAcceptanceEvidence|testNativeDistributionM1ReadinessDoesNotDependOnWorkspaceOrder)'
swift test --package-path native/Nexus
```

Expected: both commands pass with zero failures.

### Task 2: Make Environment Diagnostics Read-Only

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Preserves: `NativeEnvironmentHealth` path check labels and blocker/warning policy.
- Removes: `canWriteMarker(in:)` and every `.nexus-write-check` write.

- [x] **Step 1: Write the failing preservation test**

Create a temporary configured workspace/source/docs directory set with a pre-existing user-owned `.nexus-write-check` in each directory. Run `checkNativeEnvironment()` and assert every file still exists with its original content.

- [x] **Step 2: Run the focused test and confirm RED**

Run:

```zsh
swift test --package-path native/Nexus --filter ModelBehaviorTests/testNativeEnvironmentHealthPreservesExistingWriteMarkerFiles
```

Expected: FAIL because the existing diagnostic overwrites and removes every pre-existing marker.

- [x] **Step 3: Replace the marker probe**

Use directory metadata plus `FileManager.isWritableFile(atPath:)` in `environmentPathCheck`. Remove `canWriteMarker(in:)`.

- [x] **Step 4: Run focused and complete Native tests**

Run:

```zsh
swift test --package-path native/Nexus --filter ModelBehaviorTests/testNativeEnvironmentHealthPreservesExistingWriteMarkerFiles
swift test --package-path native/Nexus
```

Expected: both commands pass with zero failures.

### Task 3: Record And Verify The Slice

**Files:**
- Modify: `CHANGELOG.md`
- Modify: `docs/superpowers/specs/2026-07-10-native-truthful-acceptance-and-diagnostics-design.md`
- Modify: `docs/superpowers/plans/2026-07-10-native-truthful-acceptance-and-diagnostics.md`

- [x] **Step 1: Add a concise changelog entry**

Record that selected-workspace stage guidance no longer borrows global coverage and environment diagnostics are read-only.

- [x] **Step 2: Run project verification available in this environment**

Run:

```zsh
swift test --package-path native/Nexus
npm test
npm run build
```

Expected: all commands pass. Record any full-verify dependency blocker separately rather than claiming `npm run verify` passed.

- [ ] **Step 3: Commit and push the verified slice**

```zsh
git add CHANGELOG.md native/Nexus/Sources/NexusApp/MainWorkflowAcceptanceEvidence.swift native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Sources/NexusApp/Views/RootView.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift docs/superpowers/specs/2026-07-10-native-truthful-acceptance-and-diagnostics-design.md docs/superpowers/plans/2026-07-10-native-truthful-acceptance-and-diagnostics.md
git commit -m "Clarify Native workflow evidence"
git push origin main
```
