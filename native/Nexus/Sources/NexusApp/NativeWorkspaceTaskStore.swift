import Foundation
import NexusBridge

enum NativeWorkspaceTaskStore {
    static func update(
        request: UpdateWorkspaceTaskRequest,
        fileManager: FileManager = .default
    ) throws -> UpdateWorkspaceTaskResponse {
        guard request.confirmed else {
            throw NativeWorkspaceTaskStoreError.unconfirmed
        }

        let taskID = request.taskId.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !taskID.isEmpty else {
            throw NativeWorkspaceTaskStoreError.missingTaskID
        }
        let status = markdownTableCell(request.status)
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
        guard fileManager.fileExists(atPath: tasksURL.path) else {
            throw NativeWorkspaceTaskStoreError.tasksMissing(tasksURL.path)
        }

        let content = try String(contentsOf: tasksURL, encoding: .utf8)
        let folder = workspaceURL.lastPathComponent
        var taskIndex = 0
        var updatedTask: WorkspaceTaskSnapshot?
        var previousStatus = ""
        var lines: [String] = []

        var rawLines = content.components(separatedBy: "\n")
        let hadTrailingNewline = content.hasSuffix("\n")
        if hadTrailingNewline {
            rawLines.removeLast()
        }

        for (lineIndex, line) in rawLines.enumerated() {
            let sourceLine = lineIndex + 1
            guard var cells = markdownTableRowCells(line) else {
                lines.append(line)
                continue
            }

            guard let currentTask = workspaceTask(folder: folder, index: taskIndex, sourceLine: sourceLine, row: cells) else {
                lines.append(line)
                taskIndex += 1
                continue
            }

            if currentTask.id == taskID {
                while cells.count < 3 {
                    cells.append("")
                }
                previousStatus = cells.indices.contains(1) ? cells[1] : ""
                cells[1] = status
                if let detail = request.detail {
                    cells[2] = markdownTableCell(detail)
                }
                guard let task = workspaceTask(folder: folder, index: taskIndex, sourceLine: sourceLine, row: cells) else {
                    throw NativeWorkspaceTaskStoreError.updatedTaskUnparseable
                }
                updatedTask = task
                lines.append(formatMarkdownTableRow(cells))
            } else {
                lines.append(line)
            }
            taskIndex += 1
        }

        guard let task = updatedTask else {
            throw NativeWorkspaceTaskStoreError.taskNotFound(taskID)
        }

        var nextContent = lines.joined(separator: "\n")
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

    private static func markdownTableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func markdownTableRowCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"),
              trimmed.contains("|"),
              !isMarkdownTableDivider(trimmed) else {
            return nil
        }

        let cells = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "`", with: "") }
        guard !cells.isEmpty,
              !["服务", "任务", "需求", "场景", "时间", "工作区"].contains(cells[0]) else {
            return nil
        }
        return cells
    }

    private static func isMarkdownTableDivider(_ line: String) -> Bool {
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

    private static func formatMarkdownTableRow(_ cells: [String]) -> String {
        "| \(cells.map(markdownTableCell).joined(separator: " | ")) |"
    }

    private static func workspaceTask(
        folder: String,
        index: Int,
        sourceLine: Int,
        row: [String]
    ) -> WorkspaceTaskSnapshot? {
        guard let rawTitle = row.first else { return nil }
        let title = rawTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { return nil }
        let status = row.indices.contains(1)
            ? row[1].trimmingCharacters(in: .whitespacesAndNewlines)
            : "待办"
        let detail = row.indices.contains(2)
            ? row[2].trimmingCharacters(in: .whitespacesAndNewlines)
            : ""
        let sourceEventID = markerValue(in: detail, marker: "event=")
        return WorkspaceTaskSnapshot(
            id: sourceEventID.map { "\(folder):\($0)" } ?? "\(folder):task-\(index)",
            title: title,
            status: status,
            detail: detail,
            priority: taskPriority(status: status, detail: detail),
            source: sourceEventID == nil ? "workspace" : "agent",
            sourceEventId: sourceEventID,
            sourceLine: sourceLine
        )
    }

    private static func taskPriority(status: String, detail: String) -> String {
        if let priority = markerValue(in: detail, marker: "priority=")?.lowercased(),
           ["high", "medium", "normal", "low"].contains(priority) {
            return priority
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
            character.isWhitespace || character == "·" || character == ";" || character == "," || character == "|"
        } ?? rest.endIndex
        let value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
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
    case updatedTaskUnparseable
    case taskNotFound(String)

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
        case .updatedTaskUnparseable:
            return "updated task row could not be parsed"
        case .taskNotFound(let taskID):
            return "task not found: \(taskID)"
        }
    }
}
