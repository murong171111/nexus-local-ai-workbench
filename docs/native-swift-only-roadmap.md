# Native Swift-Only Roadmap

Date: 2026-06-11

This roadmap supersedes the previous "SwiftUI + Rust Core as the medium-term architecture" direction for new product work. Nexus is moving to an Apple-native Mac product line: Swift, SwiftUI, AppKit, WidgetKit, Foundation, and Apple platform storage/integration APIs. Existing React, Tauri, Rust, and TypeScript code remains in the repository as legacy preview and reference code during the transition, but new product features should not be added there.

## Goal

Make the Native Mac app the only product direction for Nexus:

- Use SwiftUI for primary screens, navigation, workspace lists, document views, and workflow surfaces.
- Use AppKit where the Mac requires mature desktop behavior: windows, menus, file panels, open/reveal actions, services, URL handling, and process launch handoff.
- Use WidgetKit for widget surfaces and deep-link status entry points.
- Use Foundation, FileManager, Process, OSLog, Codable, UserDefaults, and Apple-supported local persistence for workspace scanning, local state, audit events, and settings.
- Keep Markdown and JSON files in each workspace as human-readable source of truth.
- Keep future iPad/iPhone as companion surfaces, not as local git/worktree authorities.

## Development Freeze

The freeze starts now for new features:

| Area | Status | Allowed Work |
| --- | --- | --- |
| React / TypeScript / Vite | Legacy preview | Critical bug fixes, documentation, data export/reference only. No new workflow features. |
| Tauri shell | Legacy packaging bridge | Critical packaging fixes only until Native Mac has local install parity. No new product surfaces. |
| Rust crates / FFI | Legacy bridge/reference | Security/build fixes and read-only reference while Swift equivalents are built. No new product rules or workflow logic. |
| Swift / SwiftUI / AppKit | Primary | All new product workflow, local state, document, git/worktree, audit, and Mac integration work. |
| WidgetKit | Primary companion | Status snapshots and deep links backed by the Native app contract. |

The freeze does not require deleting old code in this round. It changes where future development goes.

## Architecture Target

```text
Nexus
├─ native/Nexus
│  ├─ NexusApp              SwiftUI + AppKit Mac app
│  ├─ NexusDomain           Swift workspace, workflow, document, git, audit logic
│  ├─ NexusStorage          settings, local index/cache, audit/event stores
│  └─ NexusIntegrations     Finder, Terminal, IDE, Codex URL, Widget snapshot
├─ native/NexusWidget       WidgetKit extension
├─ docs                     product, workflow, migration, release records
└─ legacy
   ├─ src                   React/Tauri preview UI reference
   ├─ src-tauri             Tauri package reference
   └─ crates                Rust Core/FFI reference until replaced
```

The folder names can change during migration. The required boundary is stable: product behavior moves into Swift-native code, while legacy shells stop receiving new features.

## Source Of Truth

Nexus should keep user-owned project knowledge in workspace files:

- `workspace.md`, `STATUS.md`, `services.md`, `branches.md`
- `需求/requirement.md`, `需求/questions.md`, `需求/scope.md`, `需求/tasks.md`, `需求/delivery.md`
- `tasks.md`, `交付记录.md`, `codex-sessions.json`
- `sql/*.sql`, rollback SQL, SQL Markdown notes
- `logs/`, `scripts/`, `repos/<service>`

Swift local state is allowed for convenience only:

- settings and team profile imports
- pinned and selected UI state
- search/index cache
- audit/event JSONL or SQLite cache
- widget snapshot output

If Markdown and cache disagree, Markdown wins.

## Native M1 Scope

M1 is not "feature parity with everything that exists." M1 is the stable main path for a real requirement:

```text
Create Workspace
  -> Demand Intake
  -> Scope Freeze
  -> Service / Branch Confirmation
  -> Git / Worktree Readiness
  -> Development Tasks
  -> Delivery Check
  -> Archive
```

Native M1 must include:

1. Workspace list
   - Reads real workspace folders from the configured root.
   - Shows name, branch, stage, risk, service count, task count, worktree status, and delivery state.
   - Supports active/risk/blocked/archived filters.
   - Keeps archived workspaces out of active attention counts.

2. Workspace detail
   - Starts with one primary next step, not a grid of equal actions.
   - Shows the current main-path stage and why it is blocked or ready.
   - Routes each blocker to its nearest file, check, or confirmation action.
   - Keeps secondary sections below the main path.

3. Documents
   - Opens standard Markdown documents in-app.
   - Opens SQL artifacts and SQL Markdown notes from `sql/`.
   - Provides preview/source mode for Markdown and source mode for SQL.
   - Does not auto-create dynamic SQL files.
   - Can create missing standard documents only after explicit confirmation.

4. Demand intake
   - Reads and initializes the fixed `需求/` directory.
   - Does not create `需求/<需求名>/`.
   - Shows readiness beyond file existence: P0 questions, frozen scope, requirement tasks, and task transfer.
   - Generates copyable Codex prompts without directly invoking AI.

5. Git and worktree status
   - Reads source repository status and workspace-local `repos/<service>` status.
   - Distinguishes missing source repo, missing worktree, branch mismatch, dirty service, and clean service.
   - Generates reviewable worktree actions.
   - Executes local writes only after explicit confirmation.

6. Delivery readiness
   - Blocks delivery when active tasks, blocker risks, missing worktree, branch mismatch, dirty services, or missing delivery evidence remain.
   - Treats `交付记录.md` as the SQL declaration source.
   - Requires both formal SQL and rollback SQL in `sql/` when a real SQL change is declared.

7. Audit and handoff
   - Records user-visible local writes and handoffs.
   - Keeps Codex session links in `codex-sessions.json`.
   - Copies minimal handoff context tied to the current main-path stage.

## First-Round Deliverables

This round does not delete legacy code. It creates the Native-only route and the main workflow contract:

- `docs/native-swift-only-roadmap.md`
- `docs/main-workflow.md`
- `docs/main-workflow-audit.zh-CN.md` as supporting audit context
- ROADMAP entry pointing future work to the new Native Swift-only direction

## Overall Route After Direction Lock

After this documentation round, Nexus should move in this order. The route is intentionally sequential: later slices should not pull attention away from the main workflow before M1 proves the product can guide one real requirement end to end.

### 1. Direction Lock

- Treat this document and `docs/main-workflow.md` as the current source of roadmap truth.
- Keep React, Tauri, Rust, and TypeScript frozen for product workflow features.
- Keep old code in place as reference and migration evidence.
- Avoid deleting or reshaping legacy directories until the deletion conditions are met.

### 2. Swift Native M1

- Build the daily-use Native shell around the main requirement path.
- Cover workspace list, workspace detail, document entry points, demand intake, service/branch confirmation, git/worktree status, delivery readiness, and archive eligibility.
- Make every workspace detail show the current stage, reason, evidence, and one recommended next action.

### 3. Main Workflow Rules

- Make demand intake the first gate after workspace creation.
- Prevent the primary path from recommending worktree/development before P0 questions and scope freeze are handled.
- Define root `tasks.md` as the execution source and `需求/tasks.md` as demand-intake input.
- Use the same delivery gate for delivery and archive.

### 4. Swift Local Core

- Move workspace scanning, document inventory, Markdown parsing, git/worktree inspection, readiness, risk, delivery, archive, audit, settings, search/index, and widget snapshot logic into Swift-owned domain/storage/integration modules.
- Use Foundation, FileManager, Process, Codable, OSLog, UserDefaults, SQLite-capable storage, and AppKit integration before introducing non-Apple runtime dependencies.
- Treat Rust/TypeScript behavior as migration fixtures, not new implementation targets.

#### Native Model Layering Guardrail

The Native app should keep basic data shapes separate from workflow interpretation. `native/Nexus/Sources/NexusApp/Models.swift` is the home for stable value types such as filters, status enums, workspace/task/service records, feedback records, session links, and scan-result mapping helpers. It should not regain stage-gate logic, handoff planning, or UI summary rules.

Current Swift-owned workflow files are the boundary reference:

| File | Responsibility |
| --- | --- |
| `PrimaryWorkflowStageResolver.swift` | Computes the single main-path stage, status, reason, primary action, and evidence list for a workspace. |
| `DemandScopeEvidence.swift` | Owns demand-intake readiness and scope-freeze evidence before development starts. |
| `ServiceWorktreeEvidence.swift` | Owns service/branch confirmation, worktree setup plans, setup recovery actions, and worktree gate evidence. |
| `DevelopmentTaskEvidence.swift` | Owns root `tasks.md` execution evidence, blocker routing, current-task selection, and task-plan explanation. |
| `DeliveryLifecycleEvidence.swift` | Owns delivery readiness, validation/PR review, archive eligibility, and restore/confirmation plans. |
| `DemandTaskTransfer.swift` | Owns confirmed transfer from `需求/tasks.md` demand points into root `tasks.md` execution tasks. |
| `WorkspaceEvidenceDocuments.swift` | Owns SQL summary and standard document responsibility mapping: what each evidence file proves and when it participates in a gate. |
| `WorkspaceWorkflowSummary.swift` | Owns compact workspace-level task and delivery summaries used by detail surfaces. |
| `WorkspaceBoardModels.swift` | Owns stage-board columns, board scopes, attention filtering, and board sorting priority. |
| `MenuBarStatusModels.swift` | Owns menu bar and global attention summary text. |
| `AgentWorkflowModels.swift` | Owns Agent Inbox action surfaces, response templates, and Agent workflow summaries. |
| `WorkspaceLifecycleModels.swift` | Owns lifecycle state, lifecycle transitions, lifecycle writeback requests, and fallback lifecycle inference. |

When adding a new workflow rule, first choose the nearest owner above. Add a new file only when the rule introduces a new product boundary that can be named in the main path. Keep SwiftUI views as renderers and command routers; they should consume these models instead of re-deriving stage, blocker, evidence, or next-action decisions.

### 5. Native Confirmed Writes

- Add write capabilities only after the corresponding read/status model is stable.
- Prioritize workspace creation, demand intake initialization, scope freeze, requirement-task transfer, task status, lifecycle status, delivery evidence, archive, and restore.
- Every write must show what will change, require confirmation, preserve existing human-written files, and append audit evidence.

### 6. Codex And Agent Collaboration

- Keep AI collaboration as stage-aware handoff, review, and continuation support.
- Bind multiple Codex sessions to a workspace, but identify the current continuation session separately from historical analysis/PR sessions.
- Generate minimal context from the current stage, blocker, evidence files, and latest local checks.
- Do not make Nexus directly invoke AI in M1.

### 7. Mac System Experience

- Add menu bar status, WidgetKit snapshots, local notifications, Finder/Terminal/IDE/Codex launches, deep links, and team profile sharing after the main path is stable.
- Keep these surfaces as entry points back into the Native main workflow, not separate workflow owners.

### 8. Legacy Retirement

- Stop adding preview-era product scope immediately.
- Remove legacy release paths only after Native covers M1 and can be locally installed without Tauri.
- Delete React/Tauri/Rust/TypeScript in controlled slices after replacement coverage, Swift tests, release docs, and one real end-to-end workspace lifecycle prove readiness.

### 9. Distribution And Companion Platforms

- Handle signing, notarization, update channels, and release automation after Native M1/M2 are stable.
- Keep iPad/iPhone as companion views for status, document review, risks, tasks, notifications, and approvals.
- Do not move local git/worktree authority away from Mac unless a future remote execution model is explicitly designed.

## Parallel Workstreams

The following workstreams can run in parallel, but they must converge on the same M1 main path.

| Workstream | Responsibility | First Output |
| --- | --- | --- |
| Product Workflow | Define stages, gates, blockers, and next actions. | `docs/main-workflow.md` stage model and acceptance criteria. |
| Native Architecture | Define Swift module boundaries and legacy freeze rules. | This roadmap plus future ADR update. |
| Swift UI | Turn the M1 path into workspace list/detail/document/demand/git views. | SwiftUI implementation plan and follow-up patches. |
| Workspace Document | Define document ownership and source-of-truth rules. | Document responsibility map and standard file lifecycle. |
| Git Codex | Define git/worktree state, Codex session links, and handoff payloads. | Git/worktree readiness model and handoff contract. |
| Audit Delivery | Define audit records, delivery gates, SQL guardrails, and archive gate. | Delivery/Archive gate plan. |
| QA Docs | Define verification commands and evidence for each slice. | PR checklist and documentation coverage matrix. |

## Legacy Boundary

Legacy code stays until the Native Mac app can replace the current packaged experience.

Allowed legacy changes:

- Fix a build, packaging, or critical startup issue.
- Keep sample data safe for public release.
- Keep CI green while migration is active.
- Export behavior examples or fixtures for Swift implementation.
- Remove dead code only after the deletion conditions below are met.

Blocked legacy changes:

- New React views or new dashboard interactions.
- New Tauri commands for product workflow.
- New Rust workflow rules, parsers, or git/worktree features.
- New TypeScript state models for workspace lifecycle.
- New CSS/design work outside critical readability or bug fixes.

## Deletion Conditions

Old Web/Tauri/Rust/TypeScript code can be deleted only after all conditions are true:

1. Native Mac app covers M1 main path end to end.
2. Native Mac app can be built and locally installed without relying on the Tauri bundle.
3. Native code owns workspace scanning, document reading, demand intake, git/worktree status, delivery readiness, Codex sessions, settings, audit events, and widget snapshot writing.
4. Existing sample data and tests have Swift-native replacements.
5. CI validates the Swift-native app and WidgetKit path directly.
6. Release documentation no longer points users to Tauri.
7. At least one real workspace has completed create -> demand intake -> worktree -> delivery -> archive using the Native app.

Until then, legacy code is frozen reference, not the product direction.

## Milestones

### M0: Direction Lock

- New roadmap and main workflow documents exist.
- ROADMAP points new work to Swift Native-only.
- Existing ADR contradiction is documented instead of hidden.
- Legacy freeze rules are explicit.

### M1: Main Workflow Native

- Workspace list and detail use Swift-native domain state.
- Demand intake and document preview are Native-first.
- Git/worktree and delivery readiness use Native-owned rules.
- Main path shows one current stage, one blocker summary, and one recommended next step.

### M2: Native Local Core

- Replace Rust bridge dependencies for workspace scanning, document inventory, demand intake, readiness, git/worktree status, audit, and settings. `[started with NativeLocalCoreEvidence surfaced in Settings]`
- Keep import/export compatibility for existing workspace files.
- Move verification toward Swift tests.

### M3: Native Distribution Readiness

- Native app becomes the install target.
- WidgetKit is attached to the native app target.
- Tauri is removed after deletion conditions are met.
- Signing, notarization, updater, and release notes can be addressed after M1/M2 are stable.

## Verification Policy

For documentation-only changes:

- `git diff --check`
- targeted Markdown review

For Swift Native changes:

- `swift build --package-path native/Nexus`
- relevant Swift tests when added
- WidgetKit typecheck when widget contracts change

For legacy maintenance only:

- run the smallest command that covers the touched legacy surface
- do not use `npm run verify` as a reason to keep adding product logic to React/Tauri

## Decision Rule

Before any future implementation starts, ask:

> Can this feature be implemented in Swift Native as part of the M1 main path?

If yes, implement it in Swift Native.

If no, either defer it or classify it as legacy maintenance. Do not add it to React, Tauri, Rust, or TypeScript as a new product feature.
