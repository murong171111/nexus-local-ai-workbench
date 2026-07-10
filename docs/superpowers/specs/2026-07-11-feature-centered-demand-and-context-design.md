# Feature-Centered Demand And Context Design

## Context

Nexus Native M1 now derives workflow state from real workspace files and Git, protects confirmed writes against stale evidence, and proves the complete lifecycle with repeatable tests. The next product problem is usability rather than truthfulness.

The current workspace template creates many Markdown files before they contain useful evidence. The Console exposes those files directly, so the page is dense and a new Codex conversation can receive more context than it needs. The primary action "开始预检" is also misleading in one Console path: it opens `需求/requirement.md` in the lower document viewer without moving focus or presenting an editable next step. The user sees little visible change and does not know what to do.

The desired workflow is feature-centered:

1. The user writes one free-form requirement and attaches prototype images or document links.
2. Nexus generates a compact Codex handoff and opens a real Codex conversation.
3. Codex asks only necessary follow-up questions and writes a feature proposal draft.
4. Nexus validates and displays the proposal as a reviewable diff.
5. The user confirms, edits, removes, or adds features in the app.
6. Features link to tasks, Git changes, tests, SQL, risks, and delivery evidence.
7. Machine-verifiable features complete automatically when strict evidence is satisfied; subjective acceptance remains manual.
8. Each Codex session can produce a confirmed change summary so a later conversation understands work completed elsewhere.

## Goals

- Make demand intake an obvious in-app workflow rather than a document scavenger hunt.
- Accept a free-form description plus local images and links without requiring a long form.
- Introduce stable feature identities and one authoritative feature scope.
- Allow later feature additions through the same draft and confirmation flow.
- Keep service, branch, SQL, delivery, decision, and historical evidence available for project delivery.
- Reduce default Codex handoff size without hiding or deleting complete workspace evidence.
- Allow aggressive automatic completion for evidence policies that can be verified locally.
- Preserve explicit confirmation, stale-write protection, audit feedback, and file portability.
- Keep existing workspaces readable without automatic destructive migration.

## Non-Goals

- Nexus does not become a chat client or invoke an AI model directly in the first delivery.
- Nexus does not infer subjective product quality from code or tests.
- Existing workspace documents are not deleted or rewritten in bulk.
- SQLite does not become the source of truth for feature scope.
- The first delivery does not replace every existing demand, task, delivery, or lifecycle surface.
- The first delivery does not redesign Board, Settings, Agent Inbox, search, or secondary system surfaces.
- The first delivery does not implement semantic code-to-feature attribution without explicit feature IDs.

## Chosen Direction

Use a feature-centered file model with generated projections.

- `FEATURES.md` is the authoritative product scope and feature status file.
- `tasks.md` remains the authoritative execution task file.
- `services.md`, `branches.md`, `changes.md`, `交付记录.md`, and `sql/` remain delivery facts.
- `handoff.md` and `STATUS.md` become generated projections that can be rebuilt from facts.
- Raw demand materials and Codex proposals are created only when needed.
- Old demand and standard documents remain compatibility evidence and are hidden behind secondary disclosure by default.

This direction was selected over two alternatives:

- Keeping all current demand documents authoritative would minimize migration but preserve duplicated scope and completion states.
- Making SQLite authoritative would simplify UI queries but reduce portability, Git review, and direct Codex access.

## Product Flow

### 1. Enter Demand

The Console primary action routes to and focuses an in-app demand editor. It must produce a visible state transition; it must not only load a document below the fold.

The editor contains:

- one free-form requirement field;
- prototype image attachments;
- document and product links;
- optional short notes;
- one primary action: `生成上下文并打开 Codex`.

The UI does not require separate fields for audience, current process, or completion criteria. Codex may ask for those details in conversation when the requirement actually needs them.

Attachments are copied or referenced under `需求/attachments/` only after explicit confirmation. Missing attachments remain visible warnings and do not silently disappear.

### 2. Handoff To Codex

Nexus builds a compact prompt containing:

- workspace identity and path;
- the raw requirement and material paths/links;
- current service and target-branch summary;
- related active feature or task when this is a later addition;
- the latest confirmed session changes;
- instructions for writing a feature proposal draft.

Nexus opens the configured Codex URL and copies the prompt. If opening Codex fails, the prompt remains available for copying and the user can continue manually.

Codex writes `FEATURES.draft.md`; it does not modify `FEATURES.md` directly.

### 3. Review Feature Proposal

Nexus watches or refreshes the known draft path. A valid draft opens a review screen showing:

- new features;
- changed features;
- proposed cancellations;
- verification policies;
- links to source materials;
- warnings for missing or ambiguous fields.

The user can edit, remove, or add draft features. Confirmation captures exact revisions of the draft and current `FEATURES.md`. If either changes before write, Nexus rejects the confirmation and rebuilds the diff.

Confirmed features receive stable IDs. IDs are never reused. Removing an accepted feature changes it to cancelled or archived rather than erasing history.

### 4. Track And Complete Features

The Feature workspace becomes the primary demand and progress surface. Each feature displays:

- stable ID and title;
- concise description and source material;
- status and verification policy;
- linked task IDs;
- linked services;
- completion evidence;
- evidence freshness;
- automatic-completion setting;
- audit history.

Users can add a later feature directly in Nexus or start another Codex proposal conversation. Both paths produce a draft and require scope confirmation before the feature becomes authoritative.

## File Responsibilities

### Long-Lived Facts

New workspaces should converge toward these facts:

| Path | Responsibility |
| --- | --- |
| `workspace.md` | Workspace identity, roots, and stable configuration. |
| `FEATURES.md` | Confirmed feature scope, statuses, policies, and evidence links. |
| `tasks.md` | Executable development tasks linked to feature IDs. |
| `services.md` | Service scope and source-repository mapping. |
| `branches.md` | Target-branch policy and branch evidence. |
| `changes.md` | Confirmed cross-session change summaries, appended chronologically. |
| `交付记录.md` | Delivery, validation, risk, release, and manual acceptance evidence. |
| `sql/` | Formal and rollback SQL artifacts. |

`decisions.md` remains a fact file when architectural decisions are recorded. It is not loaded into every conversation by default.

### Lazy Inputs And Drafts

| Path | Responsibility |
| --- | --- |
| `需求/intake-draft.md` | Auto-saved free-form requirement and source links before Codex proposal confirmation. |
| `需求/attachments/` | Prototype images and raw input materials, created only when used. |
| `FEATURES.draft.md` | Codex or in-app feature proposal awaiting confirmation. |
| `changes.draft.md` | Session change proposal awaiting confirmation. |

Drafts are never authoritative. `需求/intake-draft.md` is updated through a debounced local draft write and remains available for later feature additions. Successful feature or change confirmation may archive or remove the accepted proposal draft after preserving an audit event. Invalid drafts are retained for recovery.

### Generated Projections

| Path | Responsibility |
| --- | --- |
| `STATUS.md` | Rebuildable status summary derived from features, tasks, Git, and delivery facts. |
| `handoff.md` | Rebuildable compact Codex context pack. |
| `scripts/worktree-commands.sh` | Generated when a worktree action is reviewed, not during empty workspace creation. |
| `bootstrap-report.md` | Optional creation receipt rather than a required context document. |

Generated projections must identify their source revisions and must not be treated as stronger evidence than their underlying facts.

### Existing Workspace Compatibility

Existing `需求/*.md`, `requirements.md`, `acceptance.md`, `plan.md`, `delivery.md`, and other standard documents continue to load. Nexus may derive a feature migration proposal from them, but migration requires a visible diff and confirmation.

No compatibility migration deletes source documents. A later, separately approved cleanup can archive redundant documents after the new workflow has proven stable.

## `FEATURES.md` Contract

The initial format remains Markdown so it is readable in Git, Codex, editors, and Nexus without a database. Each feature uses a stable heading and a fixed metadata block.

```markdown
# Features

## F-001 Order snapshot

- Status: in_progress
- Verification: code
- Auto complete: true
- Source: 需求/attachments/order-flow.png
- Services: order-service
- Tasks: T-003, T-004
- Evidence: test_order_snapshot
- Completed at:
- Completed by:

Record an immutable transaction snapshot when an order is saved.
```

Required fields are ID, title, status, verification policy, and auto-complete policy. Optional lists are normalized but preserved in stable order. Unknown user-authored prose outside recognized metadata remains intact.

The store captures a strict SHA-256 revision before confirmed writes. It rejects symlinks, directories, invalid UTF-8, duplicate IDs, malformed required fields, and stale revisions. Atomic replacement follows the existing Native confirmed-write pattern.

## Feature States

The public states are:

- `draft`: proposal only, not committed scope;
- `todo`: confirmed scope with no active linked task;
- `in_progress`: a linked task is active or the user starts the feature;
- `verifying`: implementation exists but required evidence is incomplete;
- `done`: evidence policy completed automatically or the user completed it manually;
- `blocked`: an explicit blocker prevents progress;
- `cancelled`: retained historical scope that will not be delivered.

Evidence freshness is separate from lifecycle status. A done feature affected by later related changes remains `done` but receives `evidence_stale=true` and becomes a primary review signal. This avoids silently rewriting accepted history while still surfacing regression risk.

## Verification Policies

Each confirmed feature chooses one policy. Codex can propose it; the user confirms it with the feature.

### Code

Automatic completion requires:

- every required linked task is complete;
- at least one explicitly linked commit or relevant tracked change exists;
- required tests pass after the latest related code change;
- no linked blocker or unresolved high-risk signal exists;
- evidence reads succeed.

### SQL

Automatic completion requires:

- required linked tasks are complete;
- formal and rollback SQL artifacts exist;
- SQL validation evidence is recorded after the latest SQL change;
- no linked blocker exists.

### Documentation

Automatic completion requires:

- required linked tasks are complete;
- declared document paths changed;
- configured document checks pass.

### Manual

The feature never completes automatically. The user records completion with an optional note.

Automatic completion is enabled by default for code, SQL, and documentation policies. It can be disabled per feature. Manual completion and completion reversal remain available for every policy.

Every automatic or manual transition writes an audit event with feature ID, policy, evidence identities, actor, source revision, and previous/next status.

## Evidence Attribution

Automatic completion must not claim unrelated repository activity as proof. The first implementation uses explicit attribution:

- task rows contain `feature=F-001`;
- test evidence lists a feature ID or is named in the feature's `Evidence` field;
- commit or change evidence includes the feature ID or is manually linked;
- SQL and document paths are listed by the feature or its tasks.

Semantic inference may suggest links later, but inferred links cannot satisfy strict automatic completion until confirmed.

## Context Pack

`handoff.md` is generated for a selected feature or workspace action. Its target size is 2-6 KB and it contains:

- workspace path, selected services, and target branch;
- selected feature and active linked tasks;
- the latest three confirmed `changes.md` entries;
- current Git cleanliness and latest relevant checks;
- blockers and immediate next action;
- paths to complete evidence files.

It does not concatenate full Markdown documents. Codex retains access to the workspace and can read complete files on demand.

Every context pack declares its generation time, selected feature, and source revisions. A stale pack is regenerated before a new handoff rather than appended indefinitely.

## Session Change Capture

At the end of a Codex session, Nexus can assemble `changes.draft.md` from:

- Git diff and commits since the recorded session start;
- task and feature status changes;
- test results;
- SQL and delivery evidence changes;
- a Codex-provided summary when available.

The user reviews and confirms the draft before it is appended to `changes.md`. Confirmation rejects changed source revisions. If session hooks are unavailable, the user can request a draft manually from the current Git and workspace state.

## Native Components

The implementation should keep the following boundaries:

- `NativeFeatureStore`: strict parse, revision capture, confirmed CRUD, draft merge, and audit feedback.
- `FeatureProposalDiff`: deterministic new/change/cancel comparison between draft and confirmed features.
- `FeatureCompletionEvaluator`: pure evidence-policy evaluation with no writes.
- `NativeFeatureEvidenceStore`: local task, Git, test, SQL, risk, and delivery evidence collection.
- `NativeContextPackBuilder`: bounded handoff generation from selected facts.
- `NativeSessionChangeStore`: session baseline, draft generation, confirmed append, and conflict protection.
- `FeatureWorkspaceView`: demand input, proposal review, feature list, evidence detail, and primary action.
- `LegacyFeatureMigrationAdapter`: read-only proposal generation from existing workspace documents.

`AppState` coordinates these units and refreshes the workspace after successful writes. It does not own parsers or completion rules.

## Error And Conflict Behavior

- A missing or malformed draft shows exact parse errors and never overwrites `FEATURES.md`.
- A stale draft or confirmed feature revision rejects the write and rebuilds the review diff.
- Duplicate or reused feature IDs block confirmation.
- A missing attachment is visible as a warning and remains in the proposal for correction.
- A failed Codex launch preserves the prompt and offers copy/import recovery.
- Failed Git, test, SQL, or risk evidence leaves the feature in `verifying`; it never becomes success by fallback.
- Audit failure preserves the completed primary write and returns an explicit audit warning, matching the existing Native contract.
- A later related change marks done evidence stale. Unrelated changes do not reopen or invalidate the feature.
- A failed session-change draft does not alter `changes.md`.

## UI Hierarchy

The Console retains one primary action per current stage.

For demand intake, the visible hierarchy is:

1. current question or required feature action;
2. free-form input or selected feature evidence;
3. one primary button;
4. compact feature progress;
5. secondary files and technical evidence behind disclosure.

The Documents Hub remains available for advanced review but is no longer the default demand-intake workflow. The top action must scroll to and focus the relevant in-app control, display a loading or transition state, and announce success or failure visibly.

## Console Interaction Scope

This initiative includes a focused Console interaction redesign because the feature-centered flow cannot be understandable inside the current document-heavy composition. It does not authorize an application-wide visual rewrite.

### Workspace Header

The header keeps only workspace identity, compact path, branch, and risk state. Repeated stage reasons, evidence, and next-step metrics do not appear as separate header cards.

### Five-Stage Rail

The visible workflow rail is compressed to five user-facing stages:

1. `已建档`;
2. `需求与功能点`;
3. `开发`;
4. `交付`;
5. `归档`.

Internal states such as scope freeze, service/branch confirmation, worktree readiness, validation, and done remain truthful gates inside these stages. The visual rail is navigation and progress orientation, not a replacement for domain state.

### Focus Band

One full-width band answers:

- what the user should do now;
- why it is the next action;
- what will happen after activation;
- one primary command.

Activating the demand command scrolls to the input, places keyboard focus in the requirement editor, and announces the transition. If the editor is already visible, activation focuses it and does not duplicate content.

### Main Content

The main column contains the active demand editor or feature list. A compact secondary column contains only the current action, blockers, and exceptional project signals. It does not repeat the complete readiness matrix.

The secondary column moves below the main content on narrow windows. Stable grid constraints prevent feature titles, status badges, loading state, or attachment names from shifting the overall layout.

### Evidence And Files

The current always-visible file matrix is replaced with one collapsed `证据与文件` entry showing categories and attention counts. Expanding it provides direct access to Features, Tasks, Services, Branches, Changes, Delivery, SQL, legacy demand files, and generated projections.

Opening a document remains an explicit secondary action and never replaces the current feature workflow unless the current blocker specifically requires document review.

### Interaction Feedback

Every primary action has visible idle, loading, success, blocked, conflict, and audit-warning states. Successful actions either advance the focused workflow or explain why the stage did not advance. A button may not complete with no visible page response.

Keyboard focus order follows stage rail, focus action, main editor/list, current signals, and evidence disclosure. Icon-only controls require help text and accessibility labels. State is never communicated by color alone.

## Delivery Slices

### Slice 1: Truthful Demand Entry

- Fix `开始预检` routing and focus.
- Reshape the Console header, five-stage rail, focus band, current-signal column, and collapsed evidence entry.
- Add the free-form input, links, and confirmed attachment handling.
- Generate the compact Codex prompt from existing facts.
- Preserve current demand files and readiness behavior.

### Slice 2: Feature Facts

- Add the `FEATURES.md` parser, revision model, and confirmed CRUD.
- Add feature list and in-app add/edit/cancel/manual-complete flows.
- Link root tasks to stable feature IDs.

### Slice 3: Codex Proposal Review

- Define and validate `FEATURES.draft.md`.
- Add deterministic diff and confirmed merge.
- Add launch, copy, refresh, and import recovery.

### Slice 4: Context And Session Continuity

- Generate bounded `handoff.md` for workspace and selected feature.
- Capture session baselines and confirmed `changes.md` entries.
- Add legacy document paths as on-demand context links.

### Slice 5: Aggressive Automatic Completion

- Add explicit evidence attribution and policy evaluation.
- Auto-complete code, SQL, and documentation features when strict evidence passes.
- Add stale-evidence detection, reversal, and audit presentation.

### Slice 6: Workspace Template Convergence

- Add a versioned minimal template for new workspaces.
- Move empty projections to lazy generation.
- Add read-only migration proposals for old workspaces.
- Defer any deletion or bulk rewrite to a later explicit decision.

## Testing

### Unit Tests

- Markdown parsing, normalization, unknown-prose preservation, and stable IDs.
- Duplicate, malformed, symlink, directory, invalid UTF-8, and stale-revision rejection.
- Proposal diff behavior for add, edit, cancel, and unchanged features.
- Verification policies across success, missing evidence, failed reads, and stale evidence.
- Context-pack ordering, required fields, source revisions, and size budget.
- Session-change baseline and append conflict behavior.

### App-State And UI Tests

- `开始预检` routes to and focuses the demand editor.
- Console stage, focus, feature, signal, and file surfaces follow the approved hierarchy on wide and narrow windows.
- Visible loading, success, parse-error, conflict, and audit-warning feedback.
- Primary actions expose keyboard focus and accessibility labels, and state remains understandable without color.
- Proposal confirmation refreshes the feature list and clears only the accepted draft.
- Manual CRUD and completion keep one primary action.
- Automatic completion and reversal display exact evidence.
- Old workspaces remain usable without migration.

### Real Files And Git Tests

- Create a temporary workspace and Git repositories.
- Enter demand, generate/import a proposal, confirm features, and link tasks.
- Produce related commits and test evidence.
- Prove automatic completion and later evidence staleness.
- Confirm session changes and generate a bounded next-conversation handoff.
- Preserve service, branch, SQL, delivery, archive, and lifecycle acceptance.

## Acceptance Criteria

- Clicking `开始预检` visibly presents an editable in-app next step.
- A user can begin with only a description and optional prototype/link materials.
- Codex can return a feature draft without directly modifying confirmed scope.
- A user can confirm, edit, add, cancel, complete, and reopen features in Nexus.
- Later feature additions use the same proposal and confirmation contract.
- New Codex conversations receive a compact current context and on-demand evidence paths.
- Confirmed session changes make work from other conversations visible.
- Machine-verifiable features complete automatically only from explicit fresh evidence.
- Subjective/manual features never auto-complete.
- Existing workspaces and delivery evidence remain readable without destructive migration.
- Every local write retains confirmation where required, conflict protection, audit feedback, and verifiable tests.
