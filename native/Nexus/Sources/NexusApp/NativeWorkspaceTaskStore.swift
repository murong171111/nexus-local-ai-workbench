import Foundation
import NexusBridge

enum NativeWorkspaceTaskStore {
    static func update(
        request: UpdateWorkspaceTaskRequest,
        expectedTitle: String,
        expectedStatus: String,
        expectedSourceLine: Int?,
        fileManager: FileManager = .default
    ) throws -> UpdateWorkspaceTaskResponse {
        guard request.confirmed else {
            throw NativeWorkspaceTaskStoreError.unconfirmed
        }

        let taskID = request.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskID.isEmpty else {
            throw NativeWorkspaceTaskStoreError.missingTaskID
        }
        let status = NativeWorkspaceTaskParser.sanitizedCell(request.status)
        guard !status.isEmpty else {
            throw NativeWorkspaceTaskStoreError.missingStatus
        }

        let workspaceURL = expandedURL(for: request.workspacePath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: workspaceURL.path, isDirectory: &isDirectory) else {
            throw NativeWorkspaceTaskStoreError.workspaceMissing(workspaceURL.path)
        }
        guard isDirectory.boolValue else {
            throw NativeWorkspaceTaskStoreError.workspaceNotDirectory(workspaceURL.path)
        }

        let tasksURL = workspaceURL.appendingPathComponent("tasks.md", isDirectory: false)
        let content = try readTasksDocument(at: tasksURL, fileManager: fileManager)
        let folder = workspaceURL.lastPathComponent
        let taskRows = NativeWorkspaceTaskParser.rows(from: content, folder: folder)
        let matches = taskRows.filter { $0.snapshot.id == taskID }
        guard !matches.isEmpty else {
            throw NativeWorkspaceTaskStoreError.taskNotFound(taskID)
        }
        guard matches.count == 1, let matchedRow = matches.first else {
            throw NativeWorkspaceTaskStoreError.ambiguousTaskID(taskID, matches.count)
        }

        let normalizedExpectedTitle = NativeWorkspaceTaskParser.sanitizedCell(expectedTitle)
        let normalizedExpectedStatus = NativeWorkspaceTaskParser.sanitizedCell(expectedStatus)
        let currentTask = matchedRow.snapshot
        guard currentTask.title == normalizedExpectedTitle,
              currentTask.status == normalizedExpectedStatus else {
            throw NativeWorkspaceTaskStoreError.staleConfirmation(
                taskID: taskID,
                expected: taskSnapshotSummary(
                    title: normalizedExpectedTitle,
                    status: normalizedExpectedStatus,
                    sourceLine: expectedSourceLine
                ),
                current: taskSnapshotSummary(
                    title: currentTask.title,
                    status: currentTask.status,
                    sourceLine: currentTask.sourceLine
                )
            )
        }

        var rawLines = content.components(separatedBy: "\n")
        let hadTrailingNewline = content.hasSuffix("\n")
        if hadTrailingNewline {
            rawLines.removeLast()
        }

        let lineIndex = matchedRow.sourceLine - 1
        guard rawLines.indices.contains(lineIndex) else {
            throw NativeWorkspaceTaskStoreError.updatedTaskUnparseable
        }

        var cells = matchedRow.cells
        while cells.count < 3 {
            cells.append("")
        }
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
        if hadTrailingNewline {
            nextContent.append("\n")
        }
        try nextContent.write(to: tasksURL, atomically: true, encoding: .utf8)

        let response = UpdateWorkspaceTaskResponse(
            path: tasksURL.path,
            task: task,
            previousStatus: previousStatus,
            updated: true
        )
        let audit = appendAuditEvent(request: request, response: response)
        return UpdateWorkspaceTaskResponse(
            path: response.path,
            task: response.task,
            previousStatus: response.previousStatus,
            updated: response.updated,
            auditEventID: audit?.event.id,
            auditEventPath: audit?.path
        )
    }

    private static func expandedURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func taskSnapshotSummary(
        title: String,
        status: String,
        sourceLine: Int?
    ) -> String {
        "\(title) [\(status)] at L\(sourceLine.map(String.init) ?? "?")"
    }

    private static func readTasksDocument(
        at url: URL,
        fileManager: FileManager
    ) throws -> String {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
                && error.code == NSFileReadNoSuchFileError {
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

    private static func appendAuditEvent(
        request: UpdateWorkspaceTaskRequest,
        response: UpdateWorkspaceTaskResponse
    ) -> AppendAuditEventResponse? {
        guard let auditRoot = request.auditRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
              !auditRoot.isEmpty else {
            return nil
        }
        return try? NativeAuditEventStore.append(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: request.actor ?? "Nexus Native",
                action: "workspace_task.updated",
                target: response.path,
                summary: "Updated task \(response.task.title) from \(response.previousStatus) to \(response.task.status)",
                metadata: [
                    "workspace": request.workspacePath,
                    "taskId": request.taskId,
                    "taskTitle": response.task.title,
                    "previousStatus": response.previousStatus,
                    "status": response.task.status
                ]
            )
        )
    }
}

private enum NativeWorkspaceTaskStoreError: LocalizedError {
    case unconfirmed
    case missingTaskID
    case missingStatus
    case workspaceMissing(String)
    case workspaceNotDirectory(String)
    case tasksMissing(String)
    case tasksNotFile(String)
    case tasksUnreadable(String, String)
    case updatedTaskUnparseable
    case taskNotFound(String)
    case ambiguousTaskID(String, Int)
    case staleConfirmation(taskID: String, expected: String, current: String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "workspace task update requires explicit confirmation"
        case .missingTaskID:
            return "task id is required"
        case .missingStatus:
            return "task status is required"
        case .workspaceMissing(let path):
            return "workspace does not exist: \(path)"
        case .workspaceNotDirectory(let path):
            return "workspace is not a directory: \(path)"
        case .tasksMissing(let path):
            return "tasks.md does not exist: \(path)"
        case .tasksNotFile(let path):
            return "tasks.md is not a file: \(path)"
        case .tasksUnreadable(let path, let reason):
            return "tasks.md is unreadable: \(path): \(reason)"
        case .updatedTaskUnparseable:
            return "updated task row could not be parsed"
        case .taskNotFound(let taskID):
            return "task not found: \(taskID)"
        case .ambiguousTaskID(let taskID, let count):
            return "task id \(taskID) matches \(count) rows"
        case .staleConfirmation(let taskID, let expected, let current):
            return "task \(taskID) changed since confirmation: expected \(expected), found \(current)"
        }
    }
}
