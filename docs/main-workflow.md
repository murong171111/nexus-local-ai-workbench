# Nexus Main Workflow

Date: 2026-06-11

This document is the product contract for the Swift Native M1 workflow. It turns Nexus from a collection of useful panels into one requirement lifecycle that the Mac app can guide from start to finish.

## Principle

At any time, a workspace detail view must answer four questions:

1. What stage is this requirement in?
2. Why is it blocked or ready?
3. What is the single best next action?
4. Which file or local check proves the answer?

If a feature cannot answer one of those questions, it is secondary to M1.

## Stage Model

```text
created
  -> demand_intake
  -> scope_freeze
  -> service_branch_confirm
  -> worktree_setup
  -> development
  -> delivery_check
  -> archived
```

Each stage produces:

- `stage`: stable identifier.
- `label`: Chinese-first UI label with compact English hint.
- `status`: `blocked`, `pending`, `ready`, `active`, or `done`.
- `reason`: short explanation.
- `primaryAction`: one recommended action.
- `evidence`: file paths, git status, audit event, or local-check result.
- `nextStageAllowed`: whether the next stage can become primary.

## Stage Details

### 1. Created

Purpose: the workspace folder exists, but development has not started.

Evidence:

- workspace folder exists under the configured workspaces root
- standard Markdown files exist or have recoverable missing-document actions
- `STATUS.md` and `workspace.md` identify the requirement

Primary action:

- initialize or review demand intake

Blocked when:

- workspace path is unreadable
- required standard docs are missing and cannot be created safely
- folder collision or invalid workspace root is detected during creation

Native M1 UI:

- workspace list shows the new workspace immediately
- detail top card says this is a created workspace, not a development-ready workspace
- post-create receipt routes to Demand Intake first

### 2. Demand Intake

Purpose: turn Lanhu/design/user notes into a stable requirement archive before code starts.

Evidence:

- `需求/requirement.md`
- `需求/questions.md`
- `需求/scope.md`
- `需求/tasks.md`
- `需求/delivery.md`

Primary action:

- initialize `需求/` if missing
- otherwise copy Codex demand-intake prompt or open the missing/incomplete document

Readiness:

- fixed `需求/` directory exists
- five standard files exist directly under `需求/`
- `requirement.md` has meaningful requirement content
- P0 questions in `questions.md` are resolved or explicitly accepted as blockers
- `scope.md` exists and its current freeze status is visible, but final freeze is owned by the Scope Freeze stage
- `需求/tasks.md` has requirement points ready to transfer

Blocked when:

- any standard file is missing
- P0 questions remain unresolved
- requirement points have not been turned into executable tasks

Native M1 UI:

- Demand Intake section appears before worktree actions
- file rows open in the document viewer
- button copies a prompt instead of invoking AI
- readiness is more than file count

### 3. Scope Freeze

Purpose: stop development from starting while the requirement is still drifting.

Evidence:

- `需求/scope.md`
- `services.md`
- `branches.md`
- optional scope-change entries

Primary action:

- freeze scope or open `需求/scope.md`

Readiness:

- scope includes "in", "out", and "pending" sections
- pending P0 scope items are empty or explicitly deferred
- declared scope changes include reason and affected service/task/SQL/delivery impact
- impacted services are confirmed or marked as intentionally unknown
- target branch strategy is confirmed or marked pending with a blocker

Blocked when:

- scope lacks a freeze marker
- P0 questions are still open
- service impact is unknown but worktree setup is requested

Native M1 UI:

- a scope tile explains whether development can begin
- any later scope change creates a review signal
- scope changes route back to demand questions, tasks, and delivery readiness

### 4. Service / Branch Confirmation

Purpose: connect the requirement to concrete repositories and target branch rules.

Evidence:

- `services.md`
- `branches.md`
- source repository scan
- workspace service rows

Primary action:

- open service/branch docs or confirm missing items

Readiness:

- services are confirmed or intentionally pending
- target branch is not placeholder text
- source repositories exist for confirmed services
- branch naming policy is recorded

Blocked when:

- service scope is unknown
- target branch is unknown
- confirmed source repo is missing
- remote branch does not exist and branch creation policy is not recorded

Native M1 UI:

- service rows distinguish source repo and workspace worktree
- a service/branch evidence card explains target branch, service scope, source repo, and branch policy readiness
- Command Center includes an explicit service/branch step between scope freeze and worktree setup
- target branch availability is checked against source repository refs; current worktree branch mismatch is informational unless recorded as an exception risk
- source repo remains read-only by default

### 5. Worktree Setup

Purpose: prepare isolated workspace-local edit directories.

Evidence:

- `repos/<service>`
- source repository path
- git branch status
- worktree setup result
- local audit event

Primary action:

- review and confirm worktree setup

Readiness:

- all confirmed services have workspace-local worktrees
- each confirmed service source repository has the target branch or a remote-tracking ref
- no setup command is hidden from the user

Blocked when:

- source repo missing
- target branch missing and creation is not confirmed
- target branch is missing from the service source repository
- worktree creation failed for any required service

Native M1 UI:

- a worktree setup evidence card explains missing worktrees, target branch availability, source repo availability, and setup command visibility
- Command Center worktree step uses the same evidence instead of only counting missing worktrees
- setup sheet lists service, source path, target path, target branch, and expected command
- result distinguishes created, skipped, and failed
- failed services are classified into recovery actions for source repo, branch, fetch, branch occupancy, or worktree command review
- failed services can be retried individually in later slices

### 6. Development Tasks

Purpose: execute scoped work using one task source.

Evidence:

- root `tasks.md`
- `需求/tasks.md` as intake source
- task status writeback audit
- document line locators

Primary action:

- continue the next active task or transfer requirement tasks into root `tasks.md`

Task ownership:

- `需求/tasks.md` is the requirement-intake list
- root `tasks.md` is the execution list
- Task Center and delivery blockers use root `tasks.md`

Blocked when:

- requirement tasks exist but have not been transferred
- root `tasks.md` has blocker tasks
- development is requested before scope freeze

Native M1 UI:

- Task Center never treats two files as equal execution sources
- transfer action requires confirmation and appends audit
- task row can open `tasks.md` at the source line
- task status writeback confirmation shows post-write checks for the edited row, next active task focus, and local-check refresh when a task is closed
- a development-task evidence card summarizes active, blocked, completed, and deferred root `tasks.md` rows
- Command Center task step opens the next active task source locator instead of only opening the document

### 7. Delivery Check

Purpose: prove the change is ready to hand off, merge, or archive.

Evidence:

- `交付记录.md`
- root `tasks.md`
- git status for every worktree service
- SQL files under `sql/`
- local check result
- PR/CI notes when available

Primary action:

- run delivery check, open the blocking document, or copy delivery/PR Codex handoff

Readiness:

- no active blocker tasks
- no blocker risks
- service worktrees exist and match branch rules
- no unexpected dirty service remains
- delivery record contains real code/logic/config/SQL/verification notes
- SQL declaration has paired formal and rollback SQL artifacts

SQL rule:

If `交付记录.md` declares a real SQL change anywhere, including SQL metadata such as DDL/DML, affected tables, new columns, backfill scripts, or data repair notes, `sql/` must contain both formal SQL and rollback SQL. SQL written only inside `交付记录.md` is not enough.

Native M1 UI:

- a delivery-gate evidence card summarizes task, risk, service/worktree, delivery-record, SQL, dirty-service, and local-check status before the detailed checklist, then renders an ordered resolution plan for blockers, pending checks, review items, and passed evidence
- a validation/PR evidence card sits between delivery and archive, summarizing local-check, delivery-record, task/risk, PR/CI, and lifecycle readiness without requiring direct GitHub integration
- archive eligibility renders a confirmation plan that reuses delivery blockers while delivery is incomplete, then orders delivery-record review, validation/PR review, lifecycle writeback, and final archive confirmation once delivery passes
- checklist groups blockers before passed evidence
- each row opens the nearest document or local check
- validation/PR handoff is separate from general workspace handoff

### 8. Archived

Purpose: remove completed work from active attention while keeping it searchable.

Evidence:

- lifecycle state
- delivery readiness pass
- audit entry for archive action

Primary action:

- view archived evidence by default
- restore to active development only through confirmed lifecycle writeback

Blocked when:

- active tasks remain
- blocker risk remains
- SQL artifacts are missing
- delivery record is incomplete
- dirty service remains

Native M1 UI:

- archived workspace remains visible under Archive
- archived workspace does not count toward active risk/task/worktree totals
- archive confirmation plan makes the final checklist explicit before lifecycle writeback to `archived`
- archive lifecycle writeback shows a post-write checklist for active-count refresh, delivery evidence, and handoff recovery context
- archived detail is read-only by default, with handoff and delivery evidence as the primary review path
- restore requires confirmation, writes lifecycle back to `developing`, and shows a post-write checklist that requires local check plus branch, worktree, task/risk, and delivery-record review

## Main Path UI Contract

The Native shell has two primary surfaces:

- `Console`: focused execution for the selected workspace. This remains the place for document preview, confirmed writes, handoffs, and local actions.
- `Board`: stage overview for the currently filtered workspace set. Board columns are derived from the same `WorkspaceMainStage` evidence as Console, support local All/Attention/Delivery/Archive scopes, and clicking a card returns to Console with that workspace focused.

Board must not become a second workflow source. It should show stage, risk, branch, service/task hints, and the recommended next action, then route users back to Console for the actual operation.

Workspace detail should use this order:

1. Stage summary
   - current stage
   - status
   - reason
   - primary action

2. Evidence strip
   - demand intake status
   - scope status
   - service/branch status
   - worktree status
   - task status
   - delivery/SQL status

3. Stage-specific panel
   - only the current stage expands by default
   - other panels are collapsed or lower priority

4. Documents
   - files grouped by purpose, not as an undifferentiated list

5. Activity and audit
   - local writes, handoffs, checks, and lifecycle updates

Command Center remains useful only if it follows this order. It should not become another dense action dashboard.

## Swift Native M1 Implementation Plan

### Current Native Baseline

The current Native shell already has enough structure to receive the M1 workflow without starting from scratch:

- App entry: `native/Nexus/Sources/NexusApp/NexusApp.swift` owns the app scene, menu bar extra, and settings scene.
- Main state: `AppState` owns workspace selection, document preview, demand intake state, worktree setup state, search, automation, agent events, settings, and feedback surfaces.
- Main window: `RootView` is now organized around a top command bar plus two primary surfaces: Console for focused execution and Board for stage overview.
- Console and Board: `WorkspaceConsoleView` keeps the selected workspace's current stage, blocker reason, next action, evidence files, document preview, and local action routing in one surface, while `WorkspaceBoardView` groups all workspaces by `WorkspaceMainStage` and routes selected cards back to Console.
- Workspace list: the legacy `WorkspaceListView` and `WorkspaceCard` remain useful reference surfaces for identity, branch, lifecycle, service/task/worktree signals, and risk, but M1 attention should move through Console and Board.
- Workspace detail: `WorkspaceDetailView` already composes a Main Workflow summary, Detail Map, Command Center, Codex Sessions, Demand Intake, Lifecycle, Workflow, Services, Risk Review, Documents, and Activity.
- Documents: `WorkspaceDocumentsHubView` already opens standard workspace documents and scanned SQL artifacts with preview/source behavior.
- Demand intake: `WorkspaceDemandIntakeView` already initializes and opens the fixed `需求/` archive files, and the Native shell now reads `需求/*.md` for requirement content, unresolved P0 questions, visible scope status, and requirement-task readiness.
- Service/branch: `ServiceBranchEvidence` now reads the Swift workspace summary and Markdown paths to gate target branch, service scope, source repo availability, target branch availability, and branch policy before worktree setup.
- Git/worktree: `WorktreeSetupEvidence` gates the handoff from service/branch confirmation into development, including a service-level create/skip/blocked setup plan, while `ServiceGitStatusSectionView` and `WorktreeSetupSheet` expose service-level status, evidence, and confirmed worktree setup.
- Development tasks: `DevelopmentTaskEvidence` now gates development after worktree setup, treats root `tasks.md` as the execution source, chooses the next active or blocked task, exposes a task plan for resolve/continue/queued/closed work, and reuses task source locators for main workflow actions.
- Delivery check: `DeliveryGateEvidence` now gates delivery after development tasks, combining task, risk, service/worktree, delivery-record, SQL, dirty-service, and local-check signals into one Swift-owned next action.
- Acceptance: `MainWorkflowAcceptanceEvidence` is available from `AppState` and surfaced in the Workspace Detail main workflow summary so M1 gate coverage is visible from current Native evidence.

M1 should refine these surfaces around a single Swift-owned stage model before splitting files aggressively.

### Workspace List

Target files:

- `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- future split views under `native/Nexus/Sources/NexusApp/Views/WorkspaceList`
- future domain models under `native/Nexus/Sources/NexusApp/Domain`

Plan:

- Introduce a Swift-owned `WorkspaceMainStage` model.
- Derive list badges from main-stage state instead of many independent metrics. `[started with WorkspaceListStageBadge including primary evidence]`
- Keep filters: all, active, risk, blocked, archived.
- Make archived exclusion explicit in task/risk/worktree counts. `[started with WorkspaceListSummary]`

### Workspace Detail

Target files:

- current `WorkspaceDetailView`
- current `WorkspaceCommandCenterView`
- future `WorkspaceStageSummaryView`

Plan:

- Add a stage summary above Command Center. `[started with WorkspaceMainStageSummaryView]`
- Make primary action come from the stage model. `[started]`
- Make stage evidence route back to the matching document or confirmed lifecycle action. `[started with WorkspaceMainStageEvidenceLink]`
- Move secondary handoff/local tools below the stage evidence. `[started with CommandCenterLayoutPolicy]`
- Keep detail map, but make it navigation only. `[started with WorkspaceDetailNavigationMap]`

### Documents

Target files:

- current `WorkspaceDocumentsHubView`
- future `WorkspaceDocumentRole` model

Plan:

- Add document responsibility metadata:
  - purpose
  - update timing
  - gate participation
  - create policy
- Surface the metadata in Native Documents Hub cards. `[started with WorkspaceDocumentRole]`
- Keep SQL artifacts as review-only dynamic entries. `[started with WorkspaceDocumentPresentation]`
- Add clear distinction between Markdown preview and SQL source review. `[started with source-only SQL presentation]`

### Demand Intake

Target files:

- current `WorkspaceDemandIntakeView`
- future `DemandIntakeReadiness` model

Plan:

- Keep fixed `需求/` initialization.
- Add readiness fields for P0 questions, scope status, and task transfer. `[started with Swift-owned Markdown evidence for requirement content, P0, visible scope status, and intake task rows]`
- Add Swift-owned Scope Freeze evidence for `需求/scope.md` in-scope, out-of-scope, pending P0, freeze marker, and audited scope-change checks. `[started with confirmed freeze write plan that appends only a freeze confirmation block after prerequisites pass]`
- Add "transfer requirement tasks" as a confirmed write action. `[started with Swift-owned transfer from 需求/tasks.md to root tasks.md, skipping existing, template, completed, and deferred rows]`
- Keep AI invocation out of Nexus M1. `[started with DemandIntakeM1ActionPolicy]`

### Development Tasks

Target files:

- current `WorkspaceCommandCenterView`
- current `WorkflowStatusView`
- future Swift-native task inspector

Plan:

- Keep root `tasks.md` as the only execution task source. `[started with DevelopmentTaskEvidence]`
- Route the main workflow and Command Center task step to the next active or blocked task locator. `[started]`
- Keep complete/defer mutations behind the existing confirmation sheets. `[started with TaskStatusMutationPolicy]`
- Keep `需求/tasks.md` visible as intake evidence, not as an execution queue. `[started with DevelopmentTaskSource]`

### Git / Worktree Status

Target files:

- current `ServiceGitStatusSectionView`
- current `WorktreeSetupSheet`
- future Swift-native git inspector

Plan:

- Replace generic service rows with five explicit states. `[started with ServiceWorktreeRowState]`
  - missing source repo
  - missing worktree
  - target branch missing
  - dirty
  - clean
- Keep all mutation behind confirmation. `[started with WorktreeSetupMutationPolicy]`
- Keep source repositories read-only unless the user explicitly opens them outside Nexus. `[started with SourceRepositoryAccess]`

### Audit / Delivery

Target files:

- current `WorkflowStatusView`
- current `RiskReviewView`
- future Swift-native delivery gate model

Plan:

- Build a single `DeliveryGate` model. `[started with DeliveryGateEvidence and confirmed delivery-record snapshot writes]`
- Reuse it for delivery and archive. `[started with ArchiveGateEvidence in Command Center and Workflow, plus confirmed archive checklist writes into 交付记录.md]`
- Keep SQL formal/rollback guard as a hard blocker. `[started through SQL health check evidence]`
- Show PR/CI evidence as optional until GitHub integration is explicitly added. `[started with ValidationPrEvidence and confirmed validation/PR snapshot writes into 交付记录.md]`

## Document Responsibility Map

| File | Purpose | Updates When | Gate |
| --- | --- | --- | --- |
| `workspace.md` | Requirement identity and lifecycle context. | workspace creation, lifecycle writeback. | created, archived |
| `STATUS.md` | Current state summary. | status/lifecycle changes. | all stages |
| `services.md` | Service scope. | scope/service confirmation changes. | service_branch_confirm, worktree_setup |
| `branches.md` | Target branch and branch policy. | branch confirmation or exception. | service_branch_confirm, worktree_setup |
| `需求/requirement.md` | Requirement interpretation. | demand intake. | demand_intake |
| `需求/questions.md` | Missing information and P0/P1/P2 questions. | demand intake and product confirmation. | demand_intake, scope_freeze |
| `需求/scope.md` | Frozen scope and scope changes. | scope freeze and change review. | scope_freeze |
| `需求/tasks.md` | Requirement points before engineering execution. | demand intake. | development entry |
| `tasks.md` | Engineering execution tasks. | task transfer and development. | development, delivery_check |
| `交付记录.md` | Delivery evidence and change summary. | code, SQL, config, verification, PR prep. | delivery_check, archived |
| `sql/` | Formal SQL, rollback SQL, SQL notes. | any real SQL change. | delivery_check, archived |
| `codex-sessions.json` | Return links to related Codex sessions. | user binds/opens/copies/deletes sessions. | handoff support |

## Legacy Interaction Rules

The main workflow may reference legacy code only as evidence:

- React/Tauri UI can show how an interaction behaved previously.
- Rust code can show parsing or readiness rules that need Swift replacement.
- TypeScript models can be used as migration fixtures.

The main workflow must not require new legacy features to become true.

## Acceptance Criteria

M1 is complete when:

- A real workspace can move through every stage in the Native Mac app. `[started with MainWorkflowAcceptanceEvidence stage coverage]`
- Every stage has one primary action and one routed evidence source. `[started with WorkspaceStageAnswer primaryEvidenceLink and MainWorkflowAcceptanceEvidence complete-answer checks]`
- Demand intake blocks development until scope and P0 questions are handled. `[started with MainWorkflowAcceptanceEvidence demand gate check]`
- Root `tasks.md` is the only execution task source. `[started with MainWorkflowAcceptanceEvidence task source check]`
- Worktree status distinguishes source repo, worktree, branch, dirty, and clean states. `[started with MainWorkflowAcceptanceEvidence worktree state coverage]`
- Delivery and archive use the same hard SQL and task/risk/git gates, and archive actions are routed through confirmed lifecycle writeback. `[started with MainWorkflowAcceptanceEvidence delivery/archive gate check]`
- Legacy React/Tauri/Rust/TypeScript code has no new product workflow features added after this roadmap. `[started with MainWorkflowAcceptanceEvidence legacy boundary check]`
