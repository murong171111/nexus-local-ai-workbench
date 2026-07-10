# Feature-Centered Demand And Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the document-first demand experience with an in-app, feature-centered workflow that hands compact context to Codex, safely imports feature proposals, preserves cross-session changes, and aggressively auto-completes machine-verifiable features from fresh local evidence.

**Architecture:** Keep Markdown and Git as portable facts. Add focused Native stores for demand drafts, confirmed features, proposal diffs, context packs, session changes, and completion evidence; keep `AppState` as coordinator and split new SwiftUI feature surfaces out of `RootView.swift`. Existing workspaces continue to scan without migration, while new facts and generated projections are introduced behind strict revision and audit contracts.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, Foundation, CryptoKit SHA-256 revisions, existing `NexusBridge` DTOs, XCTest through SwiftPM, local Git command evidence through existing Native stores.

## Global Constraints

- New product workflow work stays in Swift Native; do not add React, Tauri, Rust, or TypeScript workflow behavior.
- Real workspace files and Git remain authoritative; Preview data never substitutes for failed local reads.
- `FEATURES.md` is confirmed feature scope; `FEATURES.draft.md`, `changes.draft.md`, and `需求/intake-draft.md` are non-authoritative drafts.
- Confirmed writes capture exact revisions, reject symlinks/directories/invalid UTF-8/stale evidence, replace atomically, and return audit feedback without erasing a successful primary write.
- Automatic completion is default for `code`, `sql`, and `documentation`; `manual` never auto-completes.
- Explicit feature/task/test/commit/path attribution is required for automatic completion; semantic guesses cannot satisfy evidence.
- Existing workspace documents remain readable and are never automatically deleted or rewritten in bulk.
- Console interaction changes are limited to the workspace header, five-stage rail, focus band, demand/feature main area, current-signal column, and collapsed evidence entry.
- Board, Settings, Agent Inbox, search, menu bar, and secondary system surfaces are out of scope except for compatibility fixes required to compile.
- Every task follows red-green-refactor, ends with a focused commit, and keeps `npm run native:m1-acceptance` green.

## File Structure

**New domain and storage files**

- `native/Nexus/Sources/NexusApp/ConsoleInteractionModels.swift`: five-stage presentation and testable routing targets.
- `native/Nexus/Sources/NexusApp/DemandInputModels.swift`: free-form demand and attachment-plan value types.
- `native/Nexus/Sources/NexusApp/NativeDemandInputStore.swift`: draft parsing, debounced-safe persistence primitives, and confirmed attachment copies.
- `native/Nexus/Sources/NexusApp/FeatureModels.swift`: stable feature IDs, statuses, verification policies, documents, revisions, and write plans.
- `native/Nexus/Sources/NexusApp/NativeFeatureStore.swift`: strict Markdown parse/render/read and confirmed feature writes.
- `native/Nexus/Sources/NexusApp/FeatureProposalDiff.swift`: deterministic draft-to-confirmed comparison and merge plan.
- `native/Nexus/Sources/NexusApp/FeatureCompletionEvaluator.swift`: pure policy evaluation and evidence freshness.
- `native/Nexus/Sources/NexusApp/NativeFeatureEvidenceStore.swift`: task, Git, test, SQL, risk, and delivery evidence collection.
- `native/Nexus/Sources/NexusApp/NativeContextPackBuilder.swift`: bounded selected-feature/workspace handoff generation.
- `native/Nexus/Sources/NexusApp/NativeSessionChangeStore.swift`: session baselines, change drafts, and confirmed `changes.md` appends.
- `native/Nexus/Sources/NexusApp/LegacyFeatureMigrationAdapter.swift`: read-only proposals from existing demand/requirements/task documents.

**New UI files**

- `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`: demand editor, feature list, evidence summary, and current signals.
- `native/Nexus/Sources/NexusApp/Views/FeatureProposalReviewView.swift`: proposal diff and confirmation sheet.
- `native/Nexus/Sources/NexusApp/Views/FeatureEditView.swift`: add/edit/cancel/manual-complete forms.

**Existing coordination files**

- `native/Nexus/Sources/NexusApp/AppState.swift`: published drafts/features/proposals, async store coordination, refresh, handoff, and feedback.
- `native/Nexus/Sources/NexusApp/Views/RootView.swift`: Console composition, ScrollViewReader routing, stage rail, focus band, and evidence disclosure.
- `native/Nexus/Sources/NexusApp/NativeWorkspaceCreationStore.swift`: versioned minimal template after compatibility is proven.
- `native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift`: optional `FEATURES.md` and generated-projection discovery.
- `native/Nexus/Sources/NexusApp/NativeWorkspaceTaskParser.swift`: explicit `feature=F-001` task metadata.
- `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`: focused unit, store, AppState, and real-Git feature tests.
- `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`: only existing M1 lifecycle assertions that must include feature compatibility.

---

### Task 1: Truthful Console Routing And Interaction Hierarchy

**Files:**
- Create: `native/Nexus/Sources/NexusApp/ConsoleInteractionModels.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/RootView.swift:2514-3060`
- Create: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

**Interfaces:**
- Consumes: existing `WorkspaceMainStage`, `WorkspaceMainStageAction`, `WorkflowPathStatus`.
- Produces: `WorkspaceConsoleTarget`, `WorkspaceConsoleStageGroup`, `WorkspaceConsoleLayoutPolicy`, and `WorkspaceConsoleLayoutAuditSummary` for later feature UI tasks.

- [ ] **Step 1: Write failing routing and layout tests**

```swift
import XCTest
@testable import NexusApp

final class FeatureWorkflowTests: XCTestCase {
    func testConsoleRoutesDemandPrimaryActionToVisibleEditor() {
        XCTAssertEqual(
            WorkspaceConsoleTarget.resolve(action: .demandIntake),
            .demandInput
        )
    }

    func testConsoleLayoutKeepsOnePrimaryActionAndFilesCollapsed() {
        let summary = WorkspaceConsoleLayoutPolicy().auditSummary
        XCTAssertEqual(summary.stageGroups, [.created, .demandAndFeatures, .development, .delivery, .archive])
        XCTAssertEqual(summary.prominentPrimaryActionCount, 1)
        XCTAssertTrue(summary.filesAreCollapsed)
        XCTAssertTrue(summary.currentSignalsAreSecondary)
    }
}
```

- [ ] **Step 2: Run the focused tests and verify red**

Run:

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testConsole'
```

Expected: compile failure because `WorkspaceConsoleTarget` and `WorkspaceConsoleLayoutPolicy` do not exist.

- [ ] **Step 3: Add the testable interaction model**

```swift
enum WorkspaceConsoleTarget: String, Hashable {
    case demandInput
    case features
    case evidence

    static func resolve(action: WorkspaceMainStageAction) -> WorkspaceConsoleTarget? {
        switch action {
        case .demandIntake, .transferDemandTasks:
            return .demandInput
        case .task:
            return .features
        case .document, .path:
            return .evidence
        default:
            return nil
        }
    }
}

enum WorkspaceConsoleStageGroup: String, CaseIterable, Hashable {
    case created
    case demandAndFeatures
    case development
    case delivery
    case archive
}

struct WorkspaceConsoleLayoutPolicy: Hashable {
    let stageGroups = WorkspaceConsoleStageGroup.allCases
    let prominentPrimaryActionCount = 1
    let filesAreCollapsed = true
    let currentSignalsAreSecondary = true

    var auditSummary: WorkspaceConsoleLayoutAuditSummary {
        WorkspaceConsoleLayoutAuditSummary(
            stageGroups: stageGroups,
            prominentPrimaryActionCount: prominentPrimaryActionCount,
            filesAreCollapsed: filesAreCollapsed,
            currentSignalsAreSecondary: currentSignalsAreSecondary
        )
    }
}
```

Add `WorkspaceConsoleLayoutAuditSummary` with the four stored properties used by the test.

- [ ] **Step 4: Recompose Console around ScrollViewReader and focus**

In `WorkspaceConsoleView`, add:

```swift
@State private var navigationTarget: WorkspaceConsoleTarget?
@FocusState private var demandInputFocused: Bool
```

Wrap content in `ScrollViewReader`. For this first slice, embed the existing `WorkspaceDemandIntakeView(workspace:)` in the Console main column and assign `.id(WorkspaceConsoleTarget.demandInput)` to it; Task 2 replaces that embedded view in place with the new free-form editor. Replace both current demand branches with:

```swift
private func routeToDemandInput(_ proxy: ScrollViewProxy) {
    navigationTarget = .demandInput
    withAnimation(.easeInOut(duration: 0.2)) {
        proxy.scrollTo(WorkspaceConsoleTarget.demandInput, anchor: .top)
    }
    demandInputFocused = true
}
```

Replace the four `ConsoleFocusRow` grid and always-visible `WorkspaceConsoleFileDock` with the approved five-stage rail, one focus band, secondary current-signal column, and collapsed `证据与文件` disclosure. Keep existing document open closures inside the disclosure.

- [ ] **Step 5: Run tests and Native build**

Run:

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testConsole'
swift build --disable-sandbox --package-path native/Nexus
```

Expected: tests pass; Native app compiles; demand action no longer routes through `loadDocument`.

- [ ] **Step 6: Commit**

```bash
git add native/Nexus/Sources/NexusApp/ConsoleInteractionModels.swift native/Nexus/Sources/NexusApp/Views/RootView.swift native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift
git commit -m "Refocus Native Console on demand workflow"
```

### Task 2: Persistent Free-Form Demand Input And Materials

**Files:**
- Create: `native/Nexus/Sources/NexusApp/DemandInputModels.swift`
- Create: `native/Nexus/Sources/NexusApp/NativeDemandInputStore.swift`
- Create: `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

**Interfaces:**
- Consumes: `WorkspaceConsoleTarget.demandInput`, `NativeAuditEventStore.appendFeedback`, workspace path and Codex URL settings.
- Produces: `DemandInputDraft`, `DemandInputRevision`, `DemandAttachmentPlan`, `NativeDemandInputStore.load/save/copyAttachments`, and `AppState.openFeatureIntakeInCodex`.

- [ ] **Step 1: Write failing draft round-trip and attachment safety tests**

```swift
func testDemandInputDraftRoundTripsWithoutCreatingLegacyTemplates() throws {
    let root = temporaryWorkspace("demand-input")
    let draft = DemandInputDraft(
        requirement: "应用内描述需求并交给 Codex 梳理。",
        links: ["https://example.com/spec"],
        attachments: []
    )

    let response = try NativeDemandInputStore.save(
        draft: draft,
        workspacePath: root.path,
        expectedRevision: .missing
    )

    XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: root.path).draft, draft)
    XCTAssertTrue(response.path.hasSuffix("/需求/intake-draft.md"))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("需求/questions.md").path))
}

func testDemandAttachmentPlanRejectsDestinationCreatedAfterConfirmation() throws {
    let fixture = try demandAttachmentFixture()
    let plan = try NativeDemandInputStore.makeAttachmentPlan(
        workspacePath: fixture.workspace.path,
        sourceURLs: [fixture.source]
    )
    try "external".write(to: plan.items[0].destinationURL, atomically: true, encoding: .utf8)
    XCTAssertThrowsError(try NativeDemandInputStore.copyAttachments(plan: plan, confirmed: true))
}
```

- [ ] **Step 2: Run the focused tests and verify red**

Run:

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testDemand'
```

Expected: compile failure for missing demand-input types.

- [ ] **Step 3: Implement draft Markdown and strict revisions**

Define:

```swift
struct DemandInputDraft: Hashable {
    var requirement: String
    var links: [String]
    var attachments: [String]
}

enum DemandInputRevision: Hashable {
    case missing
    case regularUTF8(sha256: String, byteCount: Int)
    case invalid(reason: String)
}

struct DemandInputSnapshot: Hashable {
    let draft: DemandInputDraft
    let revision: DemandInputRevision
    let path: String
}
```

Render exactly:

```markdown
# Demand Intake Draft

## Requirement

<free-form text>

## Links

- <url>

## Attachments

- `需求/attachments/<file>`
```

`save` must compare `expectedRevision`, create `需求/` only when needed, reject unsafe existing entries, and atomically replace only `intake-draft.md`.

- [ ] **Step 4: Implement confirmed attachment plans**

Use:

```swift
struct DemandAttachmentPlan: Hashable {
    let workspacePath: String
    let expectedDraftRevision: DemandInputRevision
    let items: [DemandAttachmentPlanItem]
}
```

Each item captures source regular-file size/SHA-256 and a missing destination. Revalidate both before `FileManager.copyItem`. Reject duplicate sanitized names, symlinks, directories, destination appearance, and source changes. Return copied paths and per-item errors without overwriting external files.

- [ ] **Step 5: Add AppState draft coordination and Codex handoff**

Add published state keyed by workspace ID and methods:

```swift
func loadDemandInput(for workspace: WorkspaceSummary) async
func saveDemandInputDraft(_ draft: DemandInputDraft, in workspace: WorkspaceSummary) async
func attachDemandMaterials(_ urls: [URL], to workspace: WorkspaceSummary, confirmed: Bool) async
func openFeatureIntakeInCodex(for workspace: WorkspaceSummary) async
```

The handoff includes the draft, material paths, workspace identity, service/branch summary, recent known changes paths, and this output contract:

```text
Write a proposal to <workspace>/FEATURES.draft.md.
Do not modify FEATURES.md.
Use stable provisional IDs DRAFT-001, DRAFT-002, ... and propose Verification values code, sql, documentation, or manual.
```

If the Codex URL cannot open, keep the prompt on the pasteboard and surface recovery feedback.

- [ ] **Step 6: Build the demand editor UI**

In `FeatureWorkspaceView`, add the requirement `TextEditor`, link rows, attachment picker, autosave indicator, and the single primary action `生成上下文并打开 Codex`. Pass the `FocusState<Bool>.Binding` from Console so Task 1 routing focuses the editor. Keep document editing behind the evidence disclosure.

- [ ] **Step 7: Run focused and regression tests**

Run:

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testDemand'
swift test --disable-sandbox --package-path native/Nexus --filter 'ModelBehaviorTests/testAppStateDemandIntake'
```

Expected: demand tests pass; existing Native demand initialization remains green.

- [ ] **Step 8: Commit**

```bash
git add native/Nexus/Sources/NexusApp/DemandInputModels.swift native/Nexus/Sources/NexusApp/NativeDemandInputStore.swift native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Sources/NexusApp/Views/RootView.swift native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift
git commit -m "Add in-app Native demand input"
```

### Task 3: Authoritative Feature Document And Confirmed CRUD

**Files:**
- Create: `native/Nexus/Sources/NexusApp/FeatureModels.swift`
- Create: `native/Nexus/Sources/NexusApp/NativeFeatureStore.swift`
- Create: `native/Nexus/Sources/NexusApp/Views/FeatureEditView.swift`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- Modify: `native/Nexus/Sources/NexusApp/NativeWorkspaceTaskParser.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

**Interfaces:**
- Consumes: Native strict-write and audit patterns; root task metadata.
- Produces: `WorkspaceFeature`, `FeatureDocument`, `FeatureDocumentRevision`, `FeatureWritePlan`, `FeatureWriteResponse`, `NativeFeatureStore.inspect/load/makePlan/write`.

- [ ] **Step 1: Write failing parser and stale-write tests**

```swift
func testFeatureDocumentPreservesUnknownProseAndStableIDs() throws {
    let source = featureDocumentFixture()
    let document = try NativeFeatureStore.parse(source)
    XCTAssertEqual(document.features.map(\.id), ["F-001", "F-002"])
    XCTAssertEqual(document.features[0].verification, .code)
    XCTAssertTrue(NativeFeatureStore.render(document).contains("保留这段人工说明。"))
}

func testFeatureWriteRejectsExternalChangeAfterConfirmation() throws {
    let fixture = try confirmedFeatureFixture()
    let plan = try NativeFeatureStore.makePlan(
        workspacePath: fixture.workspace.path,
        mutation: .setStatus(id: "F-001", status: .done, completionNote: "manual")
    )
    try fixture.externalEdit()
    XCTAssertThrowsError(try NativeFeatureStore.write(plan: plan, confirmed: true))
    XCTAssertEqual(try String(contentsOf: fixture.featuresURL), fixture.externallyEditedContent)
}
```

- [ ] **Step 2: Run tests and verify red**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testFeature'
```

Expected: missing feature types.

- [ ] **Step 3: Implement exact feature types**

```swift
enum FeatureStatus: String, CaseIterable, Hashable {
    case draft, todo, inProgress = "in_progress", verifying, done, blocked, cancelled
}

enum FeatureVerificationPolicy: String, CaseIterable, Hashable {
    case code, sql, documentation, manual
}

struct WorkspaceFeature: Identifiable, Hashable {
    let id: String
    var title: String
    var status: FeatureStatus
    var verification: FeatureVerificationPolicy
    var autoComplete: Bool
    var sources: [String]
    var services: [String]
    var taskIDs: [String]
    var evidenceIDs: [String]
    var description: String
    var completedAt: String?
    var completedBy: String?
    var completionNote: String?
    var evidenceStale: Bool
    var preservedLines: [String]
}
```

Add `FeatureDocument` with preamble and ordered features, plus the same `missing/regularUTF8/invalid` revision shape used by other stores.

- [ ] **Step 4: Implement strict parse/render**

Recognize `## <ID> <title>` blocks and the exact metadata labels from the spec. Reject duplicate IDs, non-`F-[0-9]{3,}` confirmed IDs, missing title/status/verification/auto-complete, invalid enum values, and duplicate recognized metadata. Preserve unrecognized lines in block order. Render lists sorted and deduplicated while preserving feature order.

- [ ] **Step 5: Implement confirmed mutations**

```swift
enum FeatureMutation: Hashable {
    case add(WorkspaceFeature)
    case update(expected: WorkspaceFeature, replacement: WorkspaceFeature)
    case setStatus(id: String, status: FeatureStatus, completionNote: String?)
    case cancel(id: String, reason: String)
}
```

`makePlan` captures the current document and revision. `write` re-reads and compares the revision and expected feature, applies exactly one mutation, atomically writes, and appends `feature.added`, `feature.updated`, `feature.status_changed`, or `feature.cancelled`. Return `auditError` separately from the successful write.

- [ ] **Step 6: Parse explicit task attribution**

Extend `NativeWorkspaceTaskParser` to expose `featureID` from `feature=F-001` in task detail. Do not infer a feature from task title. Add a parser test proving multiple feature IDs or malformed IDs remain unlinked and visible as warnings.

- [ ] **Step 7: Add AppState CRUD and feature list UI**

Add:

```swift
@Published var featuresByWorkspace: [WorkspaceSummary.ID: FeatureDocument] = [:]
@Published var pendingFeatureWrite: FeatureWritePlan?

func refreshFeatures(for workspace: WorkspaceSummary) async
func requestFeatureWrite(_ mutation: FeatureMutation, in workspace: WorkspaceSummary)
func confirmPendingFeatureWrite(confirmed: Bool) async
```

Render stable feature rows, add/edit sheets, cancel, manual complete, undo complete, and exact audit warning feedback. Keep one prominent action from the current feature state.

- [ ] **Step 8: Run tests and full Native suite**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testFeature'
npm run native:test
```

Expected: feature tests and all existing Native tests pass.

- [ ] **Step 9: Commit**

```bash
git add native/Nexus/Sources/NexusApp/FeatureModels.swift native/Nexus/Sources/NexusApp/NativeFeatureStore.swift native/Nexus/Sources/NexusApp/Views/FeatureEditView.swift native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift native/Nexus/Sources/NexusApp/NativeWorkspaceTaskParser.swift native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift
git commit -m "Add confirmed Native feature facts"
```

### Task 4: Codex Feature Proposal Diff And Confirmed Merge

**Files:**
- Create: `native/Nexus/Sources/NexusApp/FeatureProposalDiff.swift`
- Create: `native/Nexus/Sources/NexusApp/Views/FeatureProposalReviewView.swift`
- Modify: `native/Nexus/Sources/NexusApp/NativeFeatureStore.swift`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

**Interfaces:**
- Consumes: Task 3 `FeatureDocument`, `WorkspaceFeature`, and strict revisions.
- Produces: `FeatureProposalDiff`, `FeatureProposalItem`, `FeatureProposalMergePlan`, `NativeFeatureStore.makeMergePlan/merge`.

- [ ] **Step 1: Write failing deterministic diff tests**

```swift
func testFeatureProposalDiffSeparatesAddsChangesAndCancellations() throws {
    let confirmed = FeatureDocument.fixture(ids: ["F-001", "F-002"])
    let draft = FeatureDocument.proposalFixture(
        changed: "F-001",
        omitted: "F-002",
        addedDrafts: ["DRAFT-001"]
    )
    let diff = FeatureProposalDiff.resolve(confirmed: confirmed, draft: draft)
    XCTAssertEqual(diff.items.map(\.kind), [.change, .cancel, .add])
    XCTAssertEqual(diff.items.last?.assignedFeatureID, "F-003")
}

func testFeatureProposalMergeRejectsChangedDraftRevision() throws {
    let fixture = try featureProposalFixture()
    let plan = try NativeFeatureStore.makeMergePlan(workspacePath: fixture.workspace.path)
    try fixture.changeDraft()
    XCTAssertThrowsError(try NativeFeatureStore.merge(plan: plan, confirmed: true))
}
```

- [ ] **Step 2: Run tests and verify red**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testFeatureProposal'
```

Expected: missing proposal types.

- [ ] **Step 3: Implement deterministic diff and ID assignment**

```swift
enum FeatureProposalKind: String, Hashable { case add, change, cancel, unchanged }

struct FeatureProposalItem: Identifiable, Hashable {
    let id: String
    let kind: FeatureProposalKind
    let confirmed: WorkspaceFeature?
    let proposed: WorkspaceFeature?
    let assignedFeatureID: String?
}
```

Sort existing items by confirmed order and additions by draft order. Assign new IDs from `max(existing numeric ID) + 1` without filling gaps or reusing cancelled IDs. Omission is a cancellation proposal, never immediate deletion.

- [ ] **Step 4: Implement strict merge plan**

Capture both `FEATURES.md` and `FEATURES.draft.md` revisions plus the selected proposal item IDs and user-edited replacements. Revalidate both documents at write time. Apply accepted items only, write `FEATURES.md`, and append one `feature.proposal_merged` audit event containing counts and source revisions. Preserve an invalid or rejected draft.

- [ ] **Step 5: Add proposal discovery and review UI**

Add AppState methods:

```swift
func refreshFeatureProposal(for workspace: WorkspaceSummary) async
func requestFeatureProposalMerge(in workspace: WorkspaceSummary)
func confirmPendingFeatureProposalMerge(confirmed: Bool) async
```

The review sheet shows add/change/cancel groups, supports inline edits and deselection, and keeps confirmation disabled on parse errors. After success, refresh features, show audit feedback, and archive the accepted draft as `FEATURES.draft.accepted-<timestamp>.md` only if its revision still matches.

- [ ] **Step 6: Run focused and Native tests**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testFeatureProposal'
npm run native:test
```

Expected: proposal and full Native tests pass.

- [ ] **Step 7: Commit**

```bash
git add native/Nexus/Sources/NexusApp/FeatureProposalDiff.swift native/Nexus/Sources/NexusApp/Views/FeatureProposalReviewView.swift native/Nexus/Sources/NexusApp/NativeFeatureStore.swift native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift
git commit -m "Review Codex feature proposals in Native"
```

### Task 5: Bounded Context Packs And Confirmed Session Changes

**Files:**
- Create: `native/Nexus/Sources/NexusApp/NativeContextPackBuilder.swift`
- Create: `native/Nexus/Sources/NexusApp/NativeSessionChangeStore.swift`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

**Interfaces:**
- Consumes: confirmed features, tasks, service/branch snapshots, Git rows, local-check response, `changes.md`, Codex session links.
- Produces: `NativeContextPackInput`, `NativeContextPack`, `SessionChangeBaseline`, `SessionChangeDraft`, `SessionChangeWritePlan`.

- [ ] **Step 1: Write failing context budget and session conflict tests**

```swift
func testContextPackPrioritizesCurrentFeatureAndFitsBudget() throws {
    let pack = NativeContextPackBuilder.build(
        input: .oversizedFixture(selectedFeatureID: "F-003"),
        maximumUTF8Bytes: 6_144
    )
    XCTAssertLessThanOrEqual(pack.markdown.utf8.count, 6_144)
    XCTAssertTrue(pack.markdown.contains("F-003"))
    XCTAssertTrue(pack.markdown.contains("按需读取"))
    XCTAssertFalse(pack.markdown.contains("FULL DELIVERY BODY"))
}

func testSessionChangeAppendRejectsChangedChangesDocument() throws {
    let fixture = try sessionChangeFixture()
    let plan = try NativeSessionChangeStore.makeWritePlan(draft: fixture.draft)
    try fixture.externalEditChanges()
    XCTAssertThrowsError(try NativeSessionChangeStore.append(plan: plan, confirmed: true))
}
```

- [ ] **Step 2: Run tests and verify red**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/(testContextPack|testSessionChange)'
```

Expected: missing context/session types.

- [ ] **Step 3: Implement deterministic context budgeting**

Build sections in this priority order:

1. workspace identity/path;
2. selected feature and active linked tasks;
3. blockers and next action;
4. service/branch and Git summary;
5. latest relevant check;
6. newest three confirmed change entries;
7. evidence file paths.

Never truncate a UTF-8 scalar or Markdown line. If the budget is exceeded, remove oldest changes, then optional evidence summaries, while always retaining paths and selected-feature content. Return included source revisions and omitted-section names.

- [ ] **Step 4: Implement handoff write and AppState use**

Write `handoff.md` atomically as a generated projection with header metadata:

```markdown
<!-- generated-by: Nexus Native -->
<!-- selected-feature: F-003 -->
<!-- source-revisions: FEATURES.md=<sha>;tasks.md=<sha>;changes.md=<sha> -->
```

Regenerate immediately before copy/open Codex. Update Task 2 handoff to consume this pack rather than assembling broad strings in `AppState`.

- [ ] **Step 5: Implement session baseline and change draft**

```swift
struct SessionChangeBaseline: Codable, Hashable {
    let sessionID: String
    let workspacePath: String
    let startedAt: String
    let repositoryHeads: [String: String]
    let featureRevision: String?
    let taskRevision: String?
}
```

Generate `changes.draft.md` from head/diff deltas, feature/task status changes, latest tests, SQL/delivery file revisions, and optional Codex summary. A confirmed append captures the current `changes.md` and draft revisions, appends one timestamped section, and writes `session.changes_confirmed` audit feedback.

- [ ] **Step 6: Add session change review controls**

Feature workspace shows `生成本次变化摘要`, a preview, confirmation checkbox, and `写入 changes.md`. Missing hooks use the current saved baseline; missing baseline starts a new session and explains that no earlier diff can be claimed.

- [ ] **Step 7: Run focused and regression tests**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/(testContextPack|testSessionChange)'
npm run native:test
```

Expected: tests pass and existing Codex-session tests remain green.

- [ ] **Step 8: Commit**

```bash
git add native/Nexus/Sources/NexusApp/NativeContextPackBuilder.swift native/Nexus/Sources/NexusApp/NativeSessionChangeStore.swift native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift
git commit -m "Add bounded Native Codex context"
```

### Task 6: Explicit Evidence And Aggressive Automatic Completion

**Files:**
- Create: `native/Nexus/Sources/NexusApp/FeatureCompletionEvaluator.swift`
- Create: `native/Nexus/Sources/NexusApp/NativeFeatureEvidenceStore.swift`
- Modify: `native/Nexus/Sources/NexusApp/NativeFeatureStore.swift`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- Modify: `native/Nexus/Sources/NexusApp/NativeLocalAutomationCheck.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

**Interfaces:**
- Consumes: `WorkspaceFeature`, feature-linked tasks, Git commits/status, test receipts, SQL paths, risk/delivery evidence.
- Produces: `FeatureEvidence`, `FeatureCompletionEvaluation`, `FeatureCompletionDecision`, and confirmed auto-completion batch plan.

- [ ] **Step 1: Write failing policy matrix tests**

```swift
func testCodeFeatureAutoCompletesOnlyWithFreshExplicitEvidence() {
    let ready = FeatureCompletionEvaluator.evaluate(
        feature: .fixture(id: "F-001", verification: .code, autoComplete: true),
        evidence: .codeReadyFixture(featureID: "F-001")
    )
    XCTAssertEqual(ready.decision, .autoComplete)

    var stale = FeatureEvidence.codeReadyFixture(featureID: "F-001")
    stale.latestTestAt = stale.latestRelatedChangeAt.addingTimeInterval(-1)
    XCTAssertEqual(
        FeatureCompletionEvaluator.evaluate(feature: .fixture(id: "F-001", verification: .code), evidence: stale).decision,
        .keepVerifying
    )
}

func testManualFeatureNeverAutoCompletes() {
    let result = FeatureCompletionEvaluator.evaluate(
        feature: .fixture(id: "F-002", verification: .manual, autoComplete: true),
        evidence: .allSignalsPassFixture(featureID: "F-002")
    )
    XCTAssertEqual(result.decision, .requiresManualCompletion)
}
```

Add analogous SQL, documentation, read-failure, blocker, no-attribution, and done-but-stale tests.

- [ ] **Step 2: Run tests and verify red**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/test.*Feature.*Complete'
```

Expected: missing evaluator and evidence types.

- [ ] **Step 3: Implement pure evaluation types**

```swift
enum FeatureCompletionDecision: String, Hashable {
    case noChange
    case startProgress
    case keepVerifying
    case autoComplete
    case requiresManualCompletion
    case markEvidenceStale
}

struct FeatureEvidence: Hashable {
    let featureID: String
    let linkedTaskIDs: [String]
    let incompleteTaskIDs: [String]
    let relatedChangeIDs: [String]
    let latestRelatedChangeAt: Date?
    let requiredTestIDs: [String]
    let failedOrMissingTestIDs: [String]
    let latestTestAt: Date?
    let formalSQLPaths: [String]
    let rollbackSQLPaths: [String]
    let documentationPaths: [String]
    let blockers: [String]
    let readErrors: [String]
}
```

The evaluator is deterministic and performs no filesystem or audit writes.

- [ ] **Step 4: Implement explicit evidence collection**

Collect only evidence carrying `feature=F-001`, a feature-declared evidence ID, or a confirmed feature path. Use existing Native task, Git, delivery, SQL, risk, and local-check APIs. Treat command/read failures as `readErrors`; never fall back to preview or broad repository success.

- [ ] **Step 5: Implement auto-completion batch writes**

`NativeFeatureStore.makeAutoCompletionPlan` captures the feature revision and evaluations. `applyAutoCompletions` re-reads, verifies each feature is unchanged, updates eligible statuses and completion metadata, and appends one audit event per feature:

```text
feature.auto_completed
feature.evidence_stale
feature.completion_reverted
```

The actor identifies the trigger (`Nexus Local Check`, `Nexus Refresh`, or scheduled automation). Previously confirmed per-feature `autoComplete=true` is the authorization; no passive scanner write is allowed.

- [ ] **Step 6: Trigger evaluation from explicit checks**

After a successful user-triggered local check or configured automation run, refresh evidence and apply the batch. Ordinary workspace scanning remains read-only. Show each completed feature and exact evidence; surface audit failures without reverting completion.

- [ ] **Step 7: Add evidence detail and reversal UI**

Feature rows show task, change, test, SQL/document, blocker, freshness, and read-error evidence. Add `撤销完成` with confirmation and reason. A done feature with later related changes remains done and displays `证据待复核` as a primary review signal.

- [ ] **Step 8: Run focused, Native, and M1 tests**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/test.*Feature.*Complete'
npm run native:test
npm run native:m1-acceptance
```

Expected: policy matrix, Native suite, and real M1 lifecycle pass.

- [ ] **Step 9: Commit**

```bash
git add native/Nexus/Sources/NexusApp/FeatureCompletionEvaluator.swift native/Nexus/Sources/NexusApp/NativeFeatureEvidenceStore.swift native/Nexus/Sources/NexusApp/NativeFeatureStore.swift native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift native/Nexus/Sources/NexusApp/NativeLocalAutomationCheck.swift native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift
git commit -m "Auto-complete Native features from evidence"
```

### Task 7: Minimal New Workspace Template And Read-Only Legacy Migration

**Files:**
- Create: `native/Nexus/Sources/NexusApp/LegacyFeatureMigrationAdapter.swift`
- Modify: `native/Nexus/Sources/NexusApp/NativeWorkspaceCreationStore.swift`
- Modify: `native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift`
- Modify: `native/Nexus/Sources/NexusApp/Models.swift`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift`
- Modify: `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- Test: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: Task 3 feature models and Task 4 proposal review.
- Produces: `WorkspaceTemplateVersion`, `LegacyFeatureMigrationProposal`, minimal v2 creation receipt, and optional scanner feature paths.

- [ ] **Step 1: Write failing template and migration tests**

```swift
func testV2WorkspaceTemplateDoesNotCreateEmptyProjectionFiles() throws {
    let response = try createV2WorkspaceFixture()
    let root = URL(fileURLWithPath: response.path)
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("workspace.md").path))
    XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("FEATURES.md").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("bootstrap-report.md").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("scripts/worktree-commands.sh").path))
    XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("需求/questions.md").path))
}

func testLegacyMigrationOnlyBuildsProposalAndLeavesFilesUntouched() throws {
    let fixture = try legacyWorkspaceFixture()
    let before = try fixture.allFileBytes()
    let proposal = try LegacyFeatureMigrationAdapter.propose(workspacePath: fixture.root.path)
    XCTAssertFalse(proposal.features.isEmpty)
    XCTAssertEqual(try fixture.allFileBytes(), before)
    XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.root.appendingPathComponent("FEATURES.md").path))
}
```

- [ ] **Step 2: Run tests and verify red**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/(testV2Workspace|testLegacyMigration)'
```

Expected: missing template version and migration adapter.

- [ ] **Step 3: Add versioned minimal template**

Add `WorkspaceTemplateVersion.v2FeatureCentered` to creation requests/drafts while preserving `.v1Legacy` decoding. The v2 creation set is:

```text
workspace.md
FEATURES.md
tasks.md
services.md
branches.md
changes.md
交付记录.md
repos/
sql/
logs/
```

`FEATURES.md`, `tasks.md`, and `changes.md` contain only their header/schema marker. `STATUS.md`, `handoff.md`, attachment directories, worktree commands, bootstrap report, and old demand templates are lazy. Keep creation confirmation, visibility receipt, audit, and partial-failure reporting.

- [ ] **Step 4: Keep scanner compatibility**

Scanner accepts either template, discovers optional `FEATURES.md`, and computes current status from facts when projections are absent. Missing generated projections are not health failures for v2. Existing v1 tests continue to use v1 fixtures until individually migrated.

- [ ] **Step 5: Implement read-only migration proposal**

Read existing `需求/requirement.md`, `需求/scope.md`, `需求/tasks.md`, `requirements.md`, `acceptance.md`, and root tasks. Produce provisional features with source paths, manual verification when evidence is ambiguous, and no writes. Feed the proposal into the Task 4 review flow; only confirmed merge creates `FEATURES.md`.

- [ ] **Step 6: Add migration UI and explicit version choice**

New workspace creation defaults to v2 and explains the smaller fact set. Existing workspaces without Features show `从现有文档生成建议` as a secondary action. The preview lists source files and promises no deletion.

- [ ] **Step 7: Run template, scanner, creation, and M1 tests**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/(testV2Workspace|testLegacyMigration)'
swift test --disable-sandbox --package-path native/Nexus --filter 'ModelBehaviorTests/testNativeWorkspaceCreationStore'
npm run native:m1-acceptance
```

Expected: both template contracts, creation safety, scanner compatibility, and M1 pass.

- [ ] **Step 8: Commit**

```bash
git add native/Nexus/Sources/NexusApp/LegacyFeatureMigrationAdapter.swift native/Nexus/Sources/NexusApp/NativeWorkspaceCreationStore.swift native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift native/Nexus/Sources/NexusApp/Models.swift native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Add feature-centered workspace template"
```

### Task 8: Real End-To-End Acceptance, Documentation, And Final Verification

**Files:**
- Modify: `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`
- Modify: `tests/native-verification-policy.test.mjs`
- Modify: `package.json`
- Modify: `docs/main-workflow.md`
- Modify: `docs/native-swift-only-roadmap.md`
- Modify: `docs/release-process.md`

**Interfaces:**
- Consumes: every prior task.
- Produces: stable `npm run native:feature-acceptance` and documented release acceptance.

- [ ] **Step 1: Write the real-files-and-Git acceptance test**

Add:

```swift
func testFeatureCenteredWorkflowPreservesDeliveryAndCrossSessionContext() async throws {
    let fixture = try FeatureWorkflowAcceptanceFixture.make()
    defer { fixture.remove() }

    _ = try NativeDemandInputStore.save(
        draft: DemandInputDraft(
            requirement: "应用内输入需求并由 Codex 梳理功能点。",
            links: ["https://example.com/prototype"],
            attachments: []
        ),
        workspacePath: fixture.workspace.path,
        expectedRevision: .missing
    )
    let attachmentPlan = try NativeDemandInputStore.makeAttachmentPlan(
        workspacePath: fixture.workspace.path,
        sourceURLs: [fixture.prototypeURL]
    )
    _ = try NativeDemandInputStore.copyAttachments(plan: attachmentPlan, confirmed: true)

    try fixture.writeFeatureProposal()
    let mergePlan = try NativeFeatureStore.makeMergePlan(workspacePath: fixture.workspace.path)
    let merge = try NativeFeatureStore.merge(plan: mergePlan, confirmed: true)
    XCTAssertEqual(merge.document.features.map(\.id), ["F-001"])

    try fixture.writeFeatureLinkedTasks(featureID: "F-001")
    try fixture.commitRelatedCode(featureID: "F-001")
    try fixture.writePassingTestReceipt(featureID: "F-001")
    let readyEvidence = try NativeFeatureEvidenceStore.collect(
        feature: merge.document.features[0],
        workspace: fixture.scannedWorkspace()
    )
    XCTAssertEqual(
        FeatureCompletionEvaluator.evaluate(
            feature: merge.document.features[0],
            evidence: readyEvidence
        ).decision,
        .autoComplete
    )

    let completionPlan = try NativeFeatureStore.makeAutoCompletionPlan(
        workspacePath: fixture.workspace.path,
        evaluations: ["F-001": .autoComplete]
    )
    _ = try NativeFeatureStore.applyAutoCompletions(plan: completionPlan, trigger: "Nexus Local Check")
    XCTAssertEqual(try NativeFeatureStore.load(workspacePath: fixture.workspace.path).document.features[0].status, .done)

    try fixture.commitRelatedCode(featureID: "F-001")
    let staleEvidence = try NativeFeatureEvidenceStore.collect(
        feature: try NativeFeatureStore.load(workspacePath: fixture.workspace.path).document.features[0],
        workspace: fixture.scannedWorkspace()
    )
    XCTAssertEqual(
        FeatureCompletionEvaluator.evaluate(
            feature: try NativeFeatureStore.load(workspacePath: fixture.workspace.path).document.features[0],
            evidence: staleEvidence
        ).decision,
        .markEvidenceStale
    )

    let changePlan = try NativeSessionChangeStore.makeWritePlan(draft: fixture.sessionChangeDraft())
    _ = try NativeSessionChangeStore.append(plan: changePlan, confirmed: true)
    let pack = NativeContextPackBuilder.build(input: try fixture.contextInput(), maximumUTF8Bytes: 6_144)
    XCTAssertLessThanOrEqual(pack.markdown.utf8.count, 6_144)
    XCTAssertTrue(pack.markdown.contains("F-001"))
    XCTAssertTrue(pack.markdown.contains("按需读取"))

    let archived = try fixture.completeDeliveryArchiveAndRestore()
    XCTAssertEqual(archived.lifecycle.stage, "developing")
    XCTAssertTrue(try fixture.auditActions().contains("feature.auto_completed"))
    XCTAssertTrue(try fixture.auditActions().contains("session.changes_confirmed"))
}
```

Add `FeatureWorkflowAcceptanceFixture` in the same test file. It owns one temporary root, a v2 workspace, one real source Git repository, one linked worktree, a prototype fixture, Native audit root, and deterministic timestamps. Its methods use the same `git init/config/add/commit/worktree` helper pattern as `testNativeStoresCanProveEndToEndWorkspaceLifecycle`; they write actual task/test/delivery/SQL fixtures and return scanner results rather than mocked workspace models.

- [ ] **Step 2: Run the test and fix only integration defects**

```bash
swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testFeatureCenteredWorkflowPreservesDeliveryAndCrossSessionContext'
```

Expected: pass after correcting integration mismatches; do not weaken evidence assertions.

- [ ] **Step 3: Add the stable acceptance command and policy test**

Add to `package.json`:

```json
"native:feature-acceptance": "swift test --disable-sandbox --package-path native/Nexus --filter 'FeatureWorkflowTests/testFeatureCenteredWorkflowPreservesDeliveryAndCrossSessionContext'"
```

Extend `tests/native-verification-policy.test.mjs` to assert the script exists and `docs/release-process.md` references it.

- [ ] **Step 4: Update product and roadmap documentation**

Document the feature-centered flow, v1/v2 template compatibility, compact context rule, automatic-completion evidence, Console interaction hierarchy, and remaining out-of-scope surfaces. Mark roadmap items complete only where the real acceptance test proves them.

- [ ] **Step 5: Run complete verification**

```bash
env PATH=/Users/ks_cj/.local/bin:/Users/ks_cj/.cargo/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin \
  CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-swift-module-cache \
  SWIFTPM_MODULECACHE_OVERRIDE=/private/tmp/nexus-swift-module-cache \
  npm run verify
npm run native:m1-acceptance
npm run native:feature-acceptance
git diff --check
```

Expected: Node, frontend, Rust, Widget, all Native tests/builds, original M1 acceptance, new feature acceptance, and whitespace checks pass. The existing Vite chunk-size warning and SwiftPM cache warnings may remain; no new warnings are accepted.

- [ ] **Step 6: Manually inspect the Native UI at wide and narrow sizes**

Verify:

- Console has one prominent primary action.
- `开始预检` scrolls and focuses the editor.
- demand input and attachment names fit without overlap.
- feature rows remain stable through loading and status changes.
- current signals move below the main content on narrow windows.
- evidence files remain accessible through disclosure.
- keyboard traversal and VoiceOver labels expose action and state without relying on color.

- [ ] **Step 7: Commit**

```bash
git add native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift tests/native-verification-policy.test.mjs package.json docs/main-workflow.md docs/native-swift-only-roadmap.md docs/release-process.md
git commit -m "Prove feature-centered Native workflow"
```

## Completion Gate

Before the branch is considered ready:

- every task above has its own commit and focused passing tests;
- `git status --short` is empty;
- `npm run verify`, `npm run native:m1-acceptance`, and `npm run native:feature-acceptance` pass from the final commit;
- no existing workspace fixture is automatically deleted or migrated;
- the exact final commit is pushed only after the user-approved integration path is chosen.
