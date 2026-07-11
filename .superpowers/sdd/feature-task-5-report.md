# Feature-Centered Demand Workflow Task 5 Report

## Status

DONE

## Implemented

1. Added deterministic context packs capped at 6,144 UTF-8 bytes. Selected feature, linked tasks, blockers, service/branch/Git state, latest checks, evidence paths, and requirement input are required facts; only oldest confirmed changes and optional evidence summaries are omitted before an explicit overflow.
2. Regenerate revision-bound `handoff.md` immediately before the Codex copy/open action. It records the generator, selected feature, and exact `FEATURES.md`, `tasks.md`, and `changes.md` source revisions, and retries once when a source changes during generation.
3. Added `SessionChangeBaseline`, repository/source snapshots, deterministic `changes.draft.md`, missing-baseline disclosure, optional Codex summaries, and revision-bound confirmed appends that preserve unknown `changes.md` prose.
4. Added descriptor-relative, `O_NOFOLLOW`, strict UTF-8, final revision revalidation, and atomic publication for handoff, baseline, draft, and confirmed change writes. Draft archival and audit failures remain visible separately from the successful main write.
5. Connected AppState generation, workspace-bound confirmation state, stale-source retries, and the Feature workspace review UI: generate summary, preview, confirmation checkbox, and confirmed `changes.md` write.
6. Fixed the asynchronous demand-input race so a requirement or link saved while source probing is in progress is included in the generated Codex handoff.

## TDD Evidence

- RED: the initial focused command failed to compile on the missing context pack, session change, and AppState APIs.
- Focused affected regressions: 2 tests, 0 failures.
- `FeatureWorkflowTests`: 126 tests, 0 failures.
- `npm run native:test`: 356 tests, 0 failures.
- `npm run native:m1-acceptance`: 3 tests, 0 failures.
- `git diff --check`: 0 whitespace errors.

## Changed Files

- `native/Nexus/Sources/NexusApp/NativeContextPackBuilder.swift`
- `native/Nexus/Sources/NexusApp/NativeSessionChangeStore.swift`
- `native/Nexus/Sources/NexusApp/AppState.swift`
- `native/Nexus/Sources/NexusApp/Views/FeatureWorkspaceView.swift`
- `native/Nexus/Tests/NexusAppTests/FeatureWorkflowTests.swift`

## Self-Review

The confirmed facts and their source revisions come from the same snapshots. Stale source, draft, or destination revisions fail without replacing external edits. Required context is never silently truncated or discarded, and missing baseline state never claims an earlier-session diff. Existing Native M1 behavior remains covered by the full suite and focused acceptance gate.

## Concerns

None at this checkpoint. Task 6 will add evidence evaluation and the more active automatic feature-completion policy; Task 5 only transports and records the evidence inputs.
