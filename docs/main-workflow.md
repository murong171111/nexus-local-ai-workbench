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
- branch mismatch is a blocker or warning depending on stage
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
- each worktree is on the target branch or explicitly marked as exception
- no setup command is hidden from the user

Blocked when:

- source repo missing
- target branch missing and creation is not confirmed
- existing worktree branch mismatches target branch
- worktree creation failed for any required service

Native M1 UI:

- setup sheet lists service, source path, target path, target branch, and expected command
- result distinguishes created, skipped, and failed
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

- view archive or restore to active review

Blocked when:

- active tasks remain
- blocker risk remains
- SQL artifacts are missing
- delivery record is incomplete
- dirty service remains

Native M1 UI:

- archived workspace remains visible under Archive
- archived workspace does not count toward active risk/task/worktree totals
- restore requires confirmation

## Main Path UI Contract

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
- Main window: `RootView` is already organized around sidebar, workspace list, and inspector/detail surfaces.
- Workspace list: `WorkspaceListView` and `WorkspaceCard` show workspace identity, branch, lifecycle, service/task/worktree signals, and risk.
- Workspace detail: `WorkspaceDetailView` already composes Detail Map, Command Center, Codex Sessions, Demand Intake, Lifecycle, Workflow, Services, Risk Review, Documents, and Activity.
- Documents: `WorkspaceDocumentsHubView` already opens standard workspace documents and scanned SQL artifacts with preview/source behavior.
- Demand intake: `WorkspaceDemandIntakeView` already initializes and opens the fixed `需求/` archive files, and the Native shell now reads `需求/*.md` for requirement content, unresolved P0 questions, scope freeze markers, and requirement-task readiness.
- Git/worktree: `ServiceGitStatusSectionView` and `WorktreeSetupSheet` already expose service-level status and confirmed worktree setup.

M1 should refine these surfaces around a single Swift-owned stage model before splitting files aggressively.

### Workspace List

Target files:

- `native/Nexus/Sources/NexusApp/Views/RootView.swift`
- future split views under `native/Nexus/Sources/NexusApp/Views/WorkspaceList`
- future domain models under `native/Nexus/Sources/NexusApp/Domain`

Plan:

- Introduce a Swift-owned `WorkspaceMainStage` model.
- Derive list badges from main-stage state instead of many independent metrics.
- Keep filters: all, active, risk, blocked, archived.
- Make archived exclusion explicit in task/risk/worktree counts.

### Workspace Detail

Target files:

- current `WorkspaceDetailView`
- current `WorkspaceCommandCenterView`
- future `WorkspaceStageSummaryView`

Plan:

- Add a stage summary above Command Center.
- Make primary action come from the stage model.
- Move secondary handoff/local tools below the stage evidence.
- Keep detail map, but make it navigation only.

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
- Keep SQL artifacts as review-only dynamic entries.
- Add clear distinction between Markdown preview and SQL source review.

### Demand Intake

Target files:

- current `WorkspaceDemandIntakeView`
- future `DemandIntakeReadiness` model

Plan:

- Keep fixed `需求/` initialization.
- Add readiness fields for P0 questions, scope status, and task transfer. `[started with Swift-owned Markdown evidence for requirement content, P0, visible scope status, and intake task rows]`
- Add Swift-owned Scope Freeze evidence for `需求/scope.md` in-scope, out-of-scope, pending P0, and freeze marker checks. `[started]`
- Add "transfer requirement tasks" as a confirmed write action. `[started with Swift-owned transfer from 需求/tasks.md to root tasks.md, skipping existing, template, completed, and deferred rows]`
- Keep AI invocation out of Nexus M1.

### Git / Worktree Status

Target files:

- current `ServiceGitStatusSectionView`
- current `WorktreeSetupSheet`
- future Swift-native git inspector

Plan:

- Replace generic service rows with five explicit states:
  - missing source repo
  - missing worktree
  - branch mismatch
  - dirty
  - clean
- Keep all mutation behind confirmation.
- Keep source repositories read-only unless the user explicitly opens them outside Nexus.

### Audit / Delivery

Target files:

- current `WorkflowStatusView`
- current `RiskReviewView`
- future Swift-native delivery gate model

Plan:

- Build a single `DeliveryGate` model.
- Reuse it for delivery and archive.
- Keep SQL formal/rollback guard as a hard blocker.
- Show PR/CI evidence as optional until GitHub integration is explicitly added.

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

- A real workspace can move through every stage in the Native Mac app.
- Every stage has one primary action and one evidence source.
- Demand intake blocks development until scope and P0 questions are handled.
- Root `tasks.md` is the only execution task source.
- Worktree status distinguishes source repo, worktree, branch, dirty, and clean states.
- Delivery and archive use the same hard SQL and task/risk/git gates.
- Legacy React/Tauri/Rust/TypeScript code has no new product workflow features added after this roadmap.
