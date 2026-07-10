# Native Delivery Record Write Safety Design

## Context

`NativeDeliveryRecordStore` owns three confirmed M1 writes to `交付记录.md`: Delivery Gate snapshots, validation/PR snapshots, and archive checklists. All three currently route through one helper that reads with `try?`, falls back to a new header on any read failure, then rewrites the complete file atomically.

That behavior can silently replace an unreadable file, follow a symlink, or overwrite manual edits made after the confirmation sheet opened. The append succeeds before optional audit feedback, but the confirmed plan carries no file revision and therefore cannot prove that the file being changed is the file the user reviewed.

This is the seventh delivery slice of the Native M1 Truthful Workflow goal.

## Goal

Every Native delivery-record append must target a regular UTF-8 file or a still-missing file, validate that its exact content state has not changed since the confirmation plan was created, append exactly one reviewed block, and emit success audit feedback only after the file write succeeds.

## Non-Goals

- Add a general file revision registry, lock service, file coordinator, or reusable compare-and-swap framework.
- Merge external edits automatically after the confirmation sheet opens.
- Change Delivery Gate, validation/PR, archive eligibility, SQL, task, risk, git, or lifecycle rules.
- Change the optional audit failure semantics.
- Change the public Rust bridge or legacy delivery APIs.
- Make `交付记录.md` mandatory before the first confirmed append; a still-missing file may be created with the standard header.

## Approaches Considered

### 1. Append to whatever content is current

Opening the latest file and appending preserves unrelated external edits, but the user would be applying a plan against a document state they did not confirm. It also does not protect a file replacement between plan creation and confirmation.

### 2. Capture and compare the exact document revision

This is the selected approach. Each write plan captures whether the delivery record is missing or a regular UTF-8 file, plus the existing file's SHA-256 and byte count. Confirmation strictly re-reads the current state and requires an exact match before constructing the next content.

### 3. Lock the file or build a generalized CAS layer

A descriptor lock or shared revision service can narrow the final read/write race, but it adds cross-process coordination and a new abstraction spanning unrelated stores. This slice keeps the same Foundation atomic single-file write boundary used elsewhere and records the remaining TOCTOU window as a known limitation.

## Design

### Document revision evidence

Add `NativeDeliveryRecordDocumentRevision` beside `NativeDeliveryRecordStore`. It is a small `Hashable` value with three states:

- `missing`: the path did not exist when the plan was created;
- `regularUTF8(sha256:byteCount:)`: the path was a regular file, readable as UTF-8, with an exact content digest;
- `invalid(reason:)`: the path existed as a symlink, directory, other non-regular object, or could not be read as UTF-8.

`NativeDeliveryRecordStore.inspectRevision(at:fileManager:)` obtains file attributes without following a successful write path, validates `.typeRegular`, reads `Data`, validates UTF-8 decoding, and hashes the exact bytes with CryptoKit. Missing-path errors map only to `missing`; every other failure maps to `invalid` with a user-facing reason.

The revision stores no document content. It is evidence for conflict validation, not a cache.

### Plan capture

`DeliveryRecordWritePlan`, `ArchiveChecklistWritePlan`, and `ValidationPrWritePlan` each gain an `expectedRevision`. Their `resolve` methods accept a `FileManager` defaulting to `.default` and capture the delivery path once when the confirmation plan is created.

An invalid expected revision makes `canWrite` false and surfaces its reason through the plan summary. A missing or regular UTF-8 revision remains writable when the existing gate rules permit it.

AppState continues to create the pending plan before showing the sheet. The pending plan therefore contains both the exact Markdown block shown to the user and the delivery-document revision observed at that time. No new UI control or public bridge model is required.

### Confirmation preflight

All three public append methods pass their plan's `expectedRevision` into the shared append function. The shared function preserves this order:

1. require explicit confirmation;
2. require the plan to be writable;
3. reject an invalid expected revision;
4. inspect the current path strictly;
5. reject a non-regular or unreadable current path;
6. compare current and expected revisions exactly;
7. reject a changed, created, or deleted file as `staleDocument`;
8. build and atomically write the next content;
9. append optional success audit feedback.

The stale error includes the path and concise expected/current revision labels. No file or audit event changes on preflight or conflict failure.

### Append behavior

When both revisions are `missing`, the next content is the standard `# 交付记录` header plus the reviewed block. When both revisions are the same regular UTF-8 value, the store reuses the just-read current content, preserves its newline shape, and appends the reviewed block once.

The helper no longer uses `try?` and never treats an arbitrary read failure as a missing file. The final write remains Foundation's atomic single-file replacement. A second submission of the same pending plan sees the first write's new revision and fails stale instead of duplicating the block.

### AppState behavior

The existing AppState catch paths already keep each pending plan on failure and expose `lastError`. Success still clears only the matching pending plan, refreshes Native state, focuses the workspace, and records local-write feedback.

Tests exercise one AppState conflict path to prove a manual edit after request keeps the pending sheet and does not emit success audit feedback. The three direct store paths prove the common store behavior for each write kind.

## Error Handling

Add explicit localized errors for:

- delivery record expected revision is invalid;
- current delivery record is not a regular file;
- current delivery record is unreadable or not UTF-8;
- current delivery record differs from the revision shown at confirmation.

Keep the existing unconfirmed and plan-not-writable errors. Missing-to-missing creation remains valid; missing-to-existing and existing-to-missing are stale conflicts.

## Test Strategy

1. Create a regular delivery record, build a Delivery Gate plan, edit the file manually, then confirm. Assert stale rejection, byte-for-byte unchanged manual content, no appended snapshot, and no audit file.
2. Build a plan while the path is missing, create the file before confirmation, and assert stale rejection without changing the new file.
3. Point the path at a symlink and assert the plan is not writable or the store rejects it before touching the target or audit log.
4. Write invalid UTF-8 and assert no fallback header replacement and no audit event.
5. Submit the same confirmed plan twice. Assert the first append and audit succeed and the second is stale without a duplicate block or second audit event.
6. Keep Delivery Gate, archive checklist, and validation/PR success tests green with exact revision evidence.
7. Exercise AppState request/confirm with an isolated Application Support root: after an external delivery-record edit, pending state remains, `lastError` names the conflict, updating resets, and no success audit is emitted.
8. Keep the real Native lifecycle proof green through delivery, validation, archive checklist, lifecycle archive, and audit-chain verification.

## Success Criteria

1. No delivery-record write follows or replaces a symlink, directory, unreadable file, or invalid UTF-8 content.
2. Any file creation, deletion, or content change after plan creation rejects confirmation before mutation.
3. A valid missing or unchanged regular UTF-8 file receives exactly one reviewed block.
4. Reusing a stale pending plan cannot duplicate a block or success audit event.
5. Delivery, validation/PR, and archive checklist writes retain confirmation, refresh, feedback, and audit behavior.
6. The end-to-end Native create-to-archive lifecycle remains green with real file-backed delivery evidence.

## Residual Risk

The revision check and Foundation atomic replacement are separate operations. Another process can still change the file in the narrow interval after validation and before replacement. Closing that TOCTOU window requires descriptor-level coordination or a general CAS mechanism and remains outside this slice.
