# Native Task Write Conflict Protection Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Native task scanning and task-status writeback share one Markdown identity contract, then reject non-regular, ambiguous, or stale task evidence before writing.

**Architecture:** A small `NativeWorkspaceTaskParser` will own task table recognition, IDs, source/event metadata, priority, source lines, cells, and formatting for both scanner and store. The store will require exactly one parsed candidate and, in a later task, compare its confirmed title/status/source line before one Foundation atomic file write and success audit append.

**Tech Stack:** Swift 5.9+, Foundation, XCTest, Swift Package Manager, existing NexusBridge task snapshot/request/response models.

## Global Constraints

- Keep public `UpdateWorkspaceTaskRequest`, NexusBridge, and Rust task APIs unchanged.
- Use the established `<folder>:task-<index>` and `<folder>:<event-id>` identity contract for Native scanner and store.
- Preserve valid fourth-column Native priority before `priority=` and status/detail fallback.
- Parse root `tasks.md` once through the shared Native parser; do not maintain separate scanner/store task parsers.
- Require one and only one task row for the requested ID before mutation.
- Require expected title, status, and optional source line for every Native store call after Task 3.
- Reject missing, non-regular, unreadable, ambiguous, or stale evidence before file mutation or success audit.
- Preserve unrelated task rows and current detail unless `request.detail` explicitly replaces it.
- Keep Foundation atomic single-file write and optional audit semantics; do not add hashes, locks, registries, journals, dependencies, or a general CAS framework.
- Do not change task status vocabulary, Task Center filters, confirmation UI layout, workflow gates, or Preview/Rust behavior.

---

### Task 1: Share One Native Task Parser Between Scanner and Store Contract

**Files:**
- Create: `native/Nexus/Sources/NexusApp/NativeWorkspaceTaskParser.swift`
- Modify: `native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift:93-103,284-316,736-744`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift:2216-2277`

**Interfaces:**
- Produces: `NativeWorkspaceTaskParser.rows(from:folder:)`, `snapshots(from:folder:)`, `snapshot(folder:index:sourceLine:cells:)`, `sanitizedCell(_:)`, and `formattedRow(_:)`.
- Consumes: `WorkspaceTaskSnapshot` and the established Rust/store ID, marker, source, and priority rules.

- [ ] **Step 1: Strengthen the scanner test with the canonical task identity contract**

In `testNativeWorkspaceScannerBuildsDashboardFromLocalFiles`, change the second task detail to include a stable Agent marker:

```swift
| 删除 bridge 兜底 | 待办 | 等 Git/worktree 规则补齐 event=agent-1 | medium |
```

Replace the final task-source assertion with:

```swift
XCTAssertEqual(
    snapshot.tasks?.map(\.id),
    [
        "2026-06-23-native-dashboard:task-0",
        "2026-06-23-native-dashboard:agent-1"
    ]
)
XCTAssertEqual(snapshot.tasks?.map(\.source), ["workspace", "agent"])
XCTAssertEqual(snapshot.tasks?.map(\.sourceEventId), [nil, "agent-1"])
XCTAssertEqual(snapshot.tasks?.map(\.sourceLine), [5, 6])
XCTAssertEqual(snapshot.tasks?.map(\.priority), ["high", "medium"])
```

- [ ] **Step 2: Run the focused scanner test and prove the current parser contract is wrong**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testNativeWorkspaceScannerBuildsDashboardFromLocalFiles
```

Expected: FAIL because scanner IDs use source-line/title slugs, both sources are `workspace`, and `sourceEventId` is nil.

- [ ] **Step 3: Add the complete shared Native parser**

Create `native/Nexus/Sources/NexusApp/NativeWorkspaceTaskParser.swift`:

```swift
import Foundation
import NexusBridge

struct NativeWorkspaceTaskRow {
    let index: Int
    let sourceLine: Int
    let cells: [String]
    let snapshot: WorkspaceTaskSnapshot
}

enum NativeWorkspaceTaskParser {
    static func rows(from content: String, folder: String) -> [NativeWorkspaceTaskRow] {
        var result: [NativeWorkspaceTaskRow] = []
        var taskIndex = 0

        for (lineIndex, line) in content.components(separatedBy: "\n").enumerated() {
            guard let cells = tableRowCells(line) else { continue }
            let index = taskIndex
            taskIndex += 1
            let sourceLine = lineIndex + 1
            guard let snapshot = snapshot(
                folder: folder,
                index: index,
                sourceLine: sourceLine,
                cells: cells
            ) else {
                continue
            }
            result.append(
                NativeWorkspaceTaskRow(
                    index: index,
                    sourceLine: sourceLine,
                    cells: cells,
                    snapshot: snapshot
                )
            )
        }
        return result
    }

    static func snapshots(from content: String, folder: String) -> [WorkspaceTaskSnapshot] {
        rows(from: content, folder: folder).map(\.snapshot)
    }

    static func snapshot(
        folder: String,
        index: Int,
        sourceLine: Int,
        cells: [String]
    ) -> WorkspaceTaskSnapshot? {
        guard let rawTitle = cells.first else { return nil }
        let title = sanitizedCell(rawTitle)
        guard !title.isEmpty else { return nil }
        let status = cells.indices.contains(1)
            ? sanitizedCell(cells[1])
            : "待办"
        let detail = cells.indices.contains(2)
            ? sanitizedCell(cells[2])
            : ""
        let sourceEventID = markerValue(in: detail, marker: "event=")
        return WorkspaceTaskSnapshot(
            id: sourceEventID.map { "\(folder):\($0)" } ?? "\(folder):task-\(index)",
            title: title,
            status: status,
            detail: detail,
            priority: priority(cells: cells, status: status, detail: detail),
            source: sourceEventID == nil ? "workspace" : "agent",
            sourceEventId: sourceEventID,
            sourceLine: sourceLine
        )
    }

    static func sanitizedCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func formattedRow(_ cells: [String]) -> String {
        "| \(cells.map(sanitizedCell).joined(separator: " | ")) |"
    }

    private static func tableRowCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"),
              trimmed.contains("|"),
              !isTableDivider(trimmed) else {
            return nil
        }
        let cells = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { sanitizedCell(String($0)) }
        guard !cells.isEmpty,
              !["服务", "任务", "需求", "场景", "时间", "工作区"].contains(cells[0]) else {
            return nil
        }
        return cells
    }

    private static func isTableDivider(_ line: String) -> Bool {
        let cells = line
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { character in
                character == "-" || character == ":" || character == " "
            }
        }
    }

    private static func priority(cells: [String], status: String, detail: String) -> String {
        if cells.indices.contains(3) {
            let explicit = sanitizedCell(cells[3]).lowercased()
            if ["high", "medium", "normal", "low"].contains(explicit) {
                return explicit
            }
        }
        if let marked = markerValue(in: detail, marker: "priority=")?.lowercased(),
           ["high", "medium", "normal", "low"].contains(marked) {
            return marked
        }
        let joined = "\(status) \(detail)".lowercased()
        if joined.contains("阻塞") || joined.contains("blocked") {
            return "high"
        }
        if joined.contains("进行中") || joined.contains("doing") {
            return "medium"
        }
        return "normal"
    }

    private static func markerValue(in text: String, marker: String) -> String? {
        guard let markerRange = text.range(of: marker) else { return nil }
        let rest = text[markerRange.upperBound...]
        let end = rest.firstIndex { character in
            character.isWhitespace || character == "·" || character == ";"
                || character == "," || character == "|"
        } ?? rest.endIndex
        let value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
```

- [ ] **Step 4: Route scanner task reads through the shared parser**

In `workspaceSnapshot`, replace the current task parser call with:

```swift
let tasks = NativeWorkspaceTaskParser.snapshots(
    from: read(root.appendingPathComponent("tasks.md", isDirectory: false)),
    folder: root.lastPathComponent
)
```

Delete the now-unused private `taskSnapshots(from:)`, `stripCheckbox(_:)`, and `slug(_:)` functions from `NativeWorkspaceScanner`.

- [ ] **Step 5: Run scanner and package tests**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeWorkspaceScannerBuildsDashboardFromLocalFiles|testNativeWorkspaceScannerBuildsConservativeLifecycleFromMarkdownEvidence)'
```

Expected: 2 tests PASS. The dashboard test proves canonical IDs, Agent source/event metadata, source lines, and explicit priority.

- [ ] **Step 6: Commit the shared parser task**

```bash
git add native/Nexus/Sources/NexusApp/NativeWorkspaceTaskParser.swift \
    native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Unify Native task identity parsing"
```

---

### Task 2: Reject Non-Regular and Ambiguous Task Targets

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeWorkspaceTaskStore.swift`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift:1750-1840`

**Interfaces:**
- Consumes: Task 1 `NativeWorkspaceTaskParser.rows`, `snapshot`, `sanitizedCell`, and `formattedRow`.
- Produces: strict regular-file read plus exactly-one-candidate mutation using the canonical scanned ID.

- [ ] **Step 1: Add failing symlink and duplicate-ID tests**

Add these tests beside `testNativeWorkspaceTaskStoreRequiresConfirmationAndRewritesStatus`:

```swift
func testNativeWorkspaceTaskStoreRejectsSymlinkBeforeWriting() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-native-task-symlink-\(UUID().uuidString)")
    let workspaceURL = root.appendingPathComponent("workspace")
    let tasksURL = workspaceURL.appendingPathComponent("tasks.md")
    let targetURL = root.appendingPathComponent("external-tasks.md")
    let auditRoot = root.appendingPathComponent("audit")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    let original = "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| External | 进行中 | keep |\n"
    try original.write(to: targetURL, atomically: true, encoding: .utf8)
    try FileManager.default.createSymbolicLink(at: tasksURL, withDestinationURL: targetURL)

    XCTAssertThrowsError(
        try NativeWorkspaceTaskStore.update(
            request: UpdateWorkspaceTaskRequest(
                workspacePath: workspaceURL.path,
                taskId: "workspace:task-0",
                status: "已完成",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        )
    ) { error in
        XCTAssertTrue(error.localizedDescription.contains("tasks.md is not a file"))
    }
    XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), original)
    XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: tasksURL.path), targetURL.path)
    XCTAssertFalse(FileManager.default.fileExists(
        atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
    ))
}

func testNativeWorkspaceTaskStoreRejectsDuplicateAgentTaskID() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-native-task-duplicate-id-\(UUID().uuidString)")
    let workspaceURL = root.appendingPathComponent("workspace")
    let tasksURL = workspaceURL.appendingPathComponent("tasks.md")
    let auditRoot = root.appendingPathComponent("audit")
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
    let original = """
    # Tasks

    | 任务 | 状态 | 说明 |
    | --- | --- | --- |
    | First | 进行中 | event=agent-1 |
    | Second | 待办 | event=agent-1 |
    """ + "\n"
    try original.write(to: tasksURL, atomically: true, encoding: .utf8)

    XCTAssertThrowsError(
        try NativeWorkspaceTaskStore.update(
            request: UpdateWorkspaceTaskRequest(
                workspacePath: workspaceURL.path,
                taskId: "workspace:agent-1",
                status: "已完成",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        )
    ) { error in
        XCTAssertTrue(error.localizedDescription.contains("matches 2 rows"))
    }
    XCTAssertEqual(try String(contentsOf: tasksURL, encoding: .utf8), original)
    XCTAssertFalse(FileManager.default.fileExists(
        atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
    ))
}
```

- [ ] **Step 2: Run both tests and prove current file/ID handling is unsafe**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeWorkspaceTaskStoreRejectsSymlinkBeforeWriting|testNativeWorkspaceTaskStoreRejectsDuplicateAgentTaskID)'
```

Expected: FAIL because the symlink is followed/replaced and duplicate Agent IDs update multiple rows instead of throwing.

- [ ] **Step 3: Strictly read one regular tasks document**

Add:

```swift
private static func readTasksDocument(
    at url: URL,
    fileManager: FileManager
) throws -> String {
    let attributes: [FileAttributeKey: Any]
    do {
        attributes = try fileManager.attributesOfItem(atPath: url.path)
    } catch let error as NSError
        where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
        throw NativeWorkspaceTaskStoreError.tasksMissing(url.path)
    } catch {
        throw NativeWorkspaceTaskStoreError.tasksUnreadable(url.path, error.localizedDescription)
    }
    guard attributes[.type] as? FileAttributeType == .typeRegular else {
        throw NativeWorkspaceTaskStoreError.tasksNotFile(url.path)
    }
    do {
        return try String(contentsOf: url, encoding: .utf8)
    } catch {
        throw NativeWorkspaceTaskStoreError.tasksUnreadable(url.path, error.localizedDescription)
    }
}
```

Replace the `fileExists` guard and direct read with:

```swift
let content = try readTasksDocument(at: tasksURL, fileManager: fileManager)
```

Add errors/descriptions:

```swift
case tasksNotFile(String)
case tasksUnreadable(String, String)
```

```swift
case .tasksNotFile(let path):
    return "tasks.md is not a file: \(path)"
case .tasksUnreadable(let path, let reason):
    return "tasks.md is unreadable: \(path): \(reason)"
```

- [ ] **Step 4: Resolve exactly one shared-parser candidate before mutation**

After reading content:

```swift
let folder = workspaceURL.lastPathComponent
let taskRows = NativeWorkspaceTaskParser.rows(from: content, folder: folder)
let matches = taskRows.filter { $0.snapshot.id == taskID }
guard !matches.isEmpty else {
    throw NativeWorkspaceTaskStoreError.taskNotFound(taskID)
}
guard matches.count == 1, let matchedRow = matches.first else {
    throw NativeWorkspaceTaskStoreError.ambiguousTaskID(taskID, matches.count)
}
```

Replace the current parse-and-rewrite loop with one source-line replacement:

```swift
var rawLines = content.components(separatedBy: "\n")
let hadTrailingNewline = content.hasSuffix("\n")
if hadTrailingNewline { rawLines.removeLast() }
let lineIndex = matchedRow.sourceLine - 1
guard rawLines.indices.contains(lineIndex) else {
    throw NativeWorkspaceTaskStoreError.updatedTaskUnparseable
}

var cells = matchedRow.cells
while cells.count < 3 { cells.append("") }
let previousStatus = matchedRow.snapshot.status
cells[1] = status
if let detail = request.detail {
    cells[2] = NativeWorkspaceTaskParser.sanitizedCell(detail)
}
guard let task = NativeWorkspaceTaskParser.snapshot(
    folder: folder,
    index: matchedRow.index,
    sourceLine: matchedRow.sourceLine,
    cells: cells
) else {
    throw NativeWorkspaceTaskStoreError.updatedTaskUnparseable
}
rawLines[lineIndex] = NativeWorkspaceTaskParser.formattedRow(cells)

var nextContent = rawLines.joined(separator: "\n")
if hadTrailingNewline { nextContent.append("\n") }
try nextContent.write(to: tasksURL, atomically: true, encoding: .utf8)
```

Delete the duplicated store-private Markdown row, divider, formatter, task snapshot, priority, and marker helpers. Keep only store orchestration and audit behavior.

Add:

```swift
case ambiguousTaskID(String, Int)
```

```swift
case .ambiguousTaskID(let taskID, let count):
    return "task id \(taskID) matches \(count) rows"
```

- [ ] **Step 5: Run strict/ambiguous and existing success tests**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeWorkspaceTaskStoreRejectsSymlinkBeforeWriting|testNativeWorkspaceTaskStoreRejectsDuplicateAgentTaskID|testNativeWorkspaceTaskStoreRequiresConfirmationAndRewritesStatus)'
```

Expected: 3 tests PASS; the success test still updates ordinary and Agent rows and records two audit events.

- [ ] **Step 6: Commit the strict unique-target task**

```bash
git add native/Nexus/Sources/NexusApp/NativeWorkspaceTaskStore.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift
git commit -m "Reject ambiguous Native task writes"
```

---

### Task 3: Reject Stale Task Confirmation Snapshots

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeWorkspaceTaskStore.swift`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift:3899-3910`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift:1750-1840,5800-5850`
- Modify: `CHANGELOG.md:9`

**Interfaces:**
- Consumes: Task 2's unique `NativeWorkspaceTaskRow` and existing `TaskStatusUpdate.taskTitle/currentStatus/taskSourceLine`.
- Produces: `NativeWorkspaceTaskStore.update(request:expectedTitle:expectedStatus:expectedSourceLine:fileManager:)`.

- [ ] **Step 1: Add failing stale-status and shifted-row tests**

Add:

```swift
func testNativeWorkspaceTaskStoreRejectsStaleStatusAndShiftedTaskID() throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-native-task-stale-\(UUID().uuidString)")
    let staleURL = root.appendingPathComponent("stale")
    let shiftedURL = root.appendingPathComponent("shifted")
    let auditRoot = root.appendingPathComponent("audit")
    defer { try? FileManager.default.removeItem(at: root) }
    for directory in [staleURL, shiftedURL] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    let staleContent = "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| Original | 阻塞 | externally changed |\n"
    try staleContent.write(to: staleURL.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8)
    XCTAssertThrowsError(
        try NativeWorkspaceTaskStore.update(
            request: UpdateWorkspaceTaskRequest(
                workspacePath: staleURL.path,
                taskId: "stale:task-0",
                status: "已完成",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedTitle: "Original",
            expectedStatus: "进行中",
            expectedSourceLine: 5
        )
    ) { error in
        XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        XCTAssertTrue(error.localizedDescription.contains("进行中"))
        XCTAssertTrue(error.localizedDescription.contains("阻塞"))
    }
    XCTAssertEqual(try String(contentsOf: staleURL.appendingPathComponent("tasks.md"), encoding: .utf8), staleContent)

    let shiftedContent = """
    # Tasks

    | 任务 | 状态 | 说明 |
    | --- | --- | --- |
    | Inserted | 进行中 | new first row |
    | Original | 进行中 | expected task moved |
    """ + "\n"
    try shiftedContent.write(to: shiftedURL.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8)
    XCTAssertThrowsError(
        try NativeWorkspaceTaskStore.update(
            request: UpdateWorkspaceTaskRequest(
                workspacePath: shiftedURL.path,
                taskId: "shifted:task-0",
                status: "已完成",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedTitle: "Original",
            expectedStatus: "进行中",
            expectedSourceLine: 5
        )
    ) { error in
        XCTAssertTrue(error.localizedDescription.contains("Original"))
        XCTAssertTrue(error.localizedDescription.contains("Inserted"))
    }
    XCTAssertEqual(try String(contentsOf: shiftedURL.appendingPathComponent("tasks.md"), encoding: .utf8), shiftedContent)
    XCTAssertFalse(FileManager.default.fileExists(
        atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
    ))
}
```

- [ ] **Step 2: Run the stale test and prove the expected-snapshot API is absent**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter ModelBehaviorTests/testNativeWorkspaceTaskStoreRejectsStaleStatusAndShiftedTaskID
```

Expected: compile FAIL because the store does not accept the three expected snapshot arguments.

- [ ] **Step 3: Require and validate the confirmation snapshot**

Change the signature:

```swift
static func update(
    request: UpdateWorkspaceTaskRequest,
    expectedTitle: String,
    expectedStatus: String,
    expectedSourceLine: Int?,
    fileManager: FileManager = .default
) throws -> UpdateWorkspaceTaskResponse {
```

After resolving the unique `matchedRow`, validate:

```swift
let normalizedExpectedTitle = NativeWorkspaceTaskParser.sanitizedCell(expectedTitle)
let normalizedExpectedStatus = NativeWorkspaceTaskParser.sanitizedCell(expectedStatus)
let currentTask = matchedRow.snapshot
let sourceLineMatches = expectedSourceLine.map { $0 == currentTask.sourceLine } ?? true
guard currentTask.title == normalizedExpectedTitle,
      currentTask.status == normalizedExpectedStatus,
      sourceLineMatches else {
    let expected = "\(normalizedExpectedTitle) [\(normalizedExpectedStatus)] at L\(expectedSourceLine.map(String.init) ?? "?")"
    let current = "\(currentTask.title) [\(currentTask.status)] at L\(currentTask.sourceLine.map(String.init) ?? "?")"
    throw NativeWorkspaceTaskStoreError.staleConfirmation(
        taskID: taskID,
        expected: expected,
        current: current
    )
}
```

Add:

```swift
case staleConfirmation(taskID: String, expected: String, current: String)
```

```swift
case .staleConfirmation(let taskID, let expected, let current):
    return "task \(taskID) changed since confirmation: expected \(expected), found \(current)"
```

- [ ] **Step 4: Pass expected evidence from every Native caller**

In `AppState.confirmPendingTaskStatusUpdate`, pass:

```swift
),
expectedTitle: update.taskTitle,
expectedStatus: update.currentStatus,
expectedSourceLine: update.taskSourceLine
```

Update the existing store test:

- unconfirmed and completed ordinary row: title `核对任务中心`, status `进行中`, line `5`;
- deferred Agent row: title `Review permission request`, status `待办`, line `6`.

Update Task 2's symlink and duplicate-ID calls with the expected evidence shown in their fixtures; preflight/ambiguity must still win before stale validation.

In `testNativeStoresCanProveEndToEndWorkspaceLifecycle`, replace the index loop with real scanned snapshots:

```swift
workspace = try scannedWorkspace(
    folder: folder,
    workspacesRoot: workspacesRoot,
    sourceRoot: sourceRoot
)
for task in workspace.tasks {
    _ = try NativeWorkspaceTaskStore.update(
        request: UpdateWorkspaceTaskRequest(
            workspacePath: workspaceURL.path,
            taskId: task.id,
            status: "已完成",
            detail: "Native E2E proof completed.",
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        ),
        expectedTitle: task.title,
        expectedStatus: task.status,
        expectedSourceLine: task.sourceLine
    )
}
```

- [ ] **Step 5: Run all task writeback and end-to-end tests**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox \
    --package-path native/Nexus \
    --filter 'ModelBehaviorTests/(testNativeWorkspaceScannerBuildsDashboardFromLocalFiles|testNativeWorkspaceTaskStore.*|testNativeStoresCanProveEndToEndWorkspaceLifecycle)'
```

Expected: scanner contract, strict/ambiguous handling, stale confirmation, existing success, and Native lifecycle proof all PASS.

- [ ] **Step 6: Add the changelog entry**

Add at the top of `[Unreleased]` `Added`:

```markdown
- Native task scanning and writeback now share one Markdown identity parser, rejecting non-regular, ambiguous, or stale task evidence before atomic status updates and success audit feedback.
```

- [ ] **Step 7: Run the complete Native Swift suite**

Run:

```bash
env HOME=/private/tmp/nexus-review-home \
    XDG_CACHE_HOME=/private/tmp/nexus-review-cache \
    CLANG_MODULE_CACHE_PATH=/private/tmp/nexus-review-cache \
    SWIFT_MODULECACHE_PATH=/private/tmp/nexus-review-cache \
    swift test --disable-sandbox --package-path native/Nexus
```

Expected: all Native Swift tests PASS with no task identity, lifecycle proof, Task Center, or workflow regressions.

- [ ] **Step 8: Commit the verified conflict-protection task**

```bash
git add native/Nexus/Sources/NexusApp/NativeWorkspaceTaskStore.swift \
    native/Nexus/Sources/NexusApp/AppState.swift \
    native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift \
    CHANGELOG.md
git commit -m "Protect Native task status writes"
```

---

## Final Review Fix Addendum

### Scope

Address the final review findings without changing the historical Task 1-3 steps: source line is locating/diagnostic evidence rather than an independent write CAS condition; Task Center presentation identity must distinguish duplicate canonical IDs by source line; the AppState confirmation interaction needs direct stale/success coverage; and the scanner-to-store round trip must retain Agent evidence and fourth-column priority.

### Steps

- [x] Add `testNativeWorkspaceTaskStoreAllowsNonTaskLineDriftWhenTaskEvidenceUnchanged`. Start from a confirmation snapshot at L5, add only non-task blank/text lines before the table, and prove `task-0` updates the unchanged title/status at its current line. Keep `testNativeWorkspaceTaskStoreRejectsStaleStatusAndShiftedTaskID` green so inserted task-row title/status changes still reject.
- [x] Run that test RED, remove source-line equality from `NativeWorkspaceTaskStore.update`, and preserve expected/current source lines in `staleConfirmation` diagnostics.
- [x] Add `testTaskCenterItemIdentitySeparatesDuplicateCanonicalTaskIDsBySourceLine` using scanner-produced duplicate `event=` rows. Prove equal canonical write IDs and distinct Task Center IDs; include a stable `L?` fallback when source line is unavailable.
- [x] Run that test RED, include `WorkspaceTask.sourceLineLabel` in `TaskCenterItem.id`, and keep task filtering and confirmation UI unchanged.
- [x] Add an `@MainActor async` AppState request/confirm interaction test. For stale evidence, assert pending remains, stale error appears, updating resets, file/audit stay unchanged. Restore valid evidence and assert success clears pending/error/updating state, refreshes the task status, produces local feedback, and focuses the next active task. Do not modify `AppState.swift` unless this test proves a behavior defect.
- [x] Add a scanner-produced Agent task round trip: update through the store, rescan, and assert stable Agent ID/source event/source line, changed status, and retained fourth-column priority.
- [x] Run focused task-store, Task Center, AppState, scanner, and lifecycle tests; then run `swift test --disable-sandbox --package-path native/Nexus` with the established temporary cache environment.
- [x] Append RED/GREEN and full-suite evidence to `.superpowers/sdd/task-write-conflict-final-fixes-report.md`, then commit only tracked changes with `Fix Native task review findings`.
