# Native Demand Handoff Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the demand-to-Codex-to-feature-review flow continuous and machine-readable.

**Architecture:** Keep `FEATURES.md` authoritative and reuse the existing proposal parser. Strengthen the generated handoff contract, infer a small presentation phase in `FeatureWorkspaceView`, review proposals directly in the main page, and refresh proposal state when the app becomes active again.

**Tech Stack:** Swift 5.9, SwiftUI, XCTest, existing native stores only.

## Global Constraints

- Do not add dependencies or change the proposal parser format.
- Never merge a Codex proposal without explicit user confirmation.
- Keep the original demand editable after handoff, but collapse it outside the editing phase.

---

### Task 1: Machine-readable proposal contract

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeContextPackBuilder.swift`
- Modify: `native/Nexus/Sources/NexusApp/NativeFeatureStore.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

**Interfaces:**
- Consumes: `NativeFeatureProposalContext`
- Produces: an output contract containing the exact `## DRAFT-NNN` metadata shape accepted by `NativeFeatureStore.parseProposal`

- [x] Add prompt assertions for heading level, required metadata, explicit review-only behavior, and scoped first-pass analysis.
- [x] Run the focused prompt test and confirm it fails on the missing contract.
- [x] Add the minimum contract lines to `NativeContextPackBuilder`.
- [x] Run the focused prompt tests and confirm they pass.

### Task 2: Continuous workspace presentation

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- Modify: `native/Nexus/Sources/NexusApp/PrimaryWorkflowStageResolver.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: confirmed features, local handoff state, and `FeatureProposalReview`
- Produces: `editing`, `waiting`, `proposalReady`, `proposalInvalid`, or `confirmed` presentation

- [x] Add failing policy tests for initial editing, post-handoff waiting, valid proposal review, malformed proposal recovery, and confirmed features.
- [x] Run the focused policy tests and confirm they fail.
- [x] Add the minimal presentation policy and render the demand editor expanded only while editing.
- [x] Refresh features and proposal on `scenePhase == .active`; render a valid proposal directly in the main page.
- [x] Show malformed proposal errors with a direct regenerate action.
- [x] Run the focused policy tests and confirm they pass.

### Task 3: Inline review and explicit confirmation

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/NativeFeatureStore.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

**Interfaces:**
- Consumes: parsed proposal items and user edits
- Produces: a revision-bound merge plan written only after explicit confirmation

- [x] Review, edit, select, cancel, add, and remove proposal items in the main page.
- [x] Reject empty proposals instead of interpreting them as cancel-all.
- [x] Keep locally added proposal items out of `FEATURES.md` until confirmation.
- [x] Preserve legacy workflow gates unless `workspace.md` explicitly declares template version 2.
- [x] Guard return refresh and Codex handoff state against workspace-switch races.

### Task 4: Action hierarchy, verification, and local app

**Files:**
- Modify only if required by verification findings.

**Interfaces:**
- Consumes: Tasks 1 and 2
- Produces: a tested `Nexus.app` bundle

- [x] Keep one prominent action in the feature-centered demand flow and collapse secondary status/evidence.
- [x] Run the complete Swift test suite (397 existing tests passed).
- [x] Build the Release app bundle.
- [x] Build the app bundle and inspect the affected screen at desktop size.
- [x] Install the matching app bundle at `/Applications/Nexus.app` and verify its executable hash.
- [x] Record the unrelated, concurrently added branch-preparation test separately instead of changing or deleting it.
