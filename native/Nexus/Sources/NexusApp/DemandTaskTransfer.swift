import Foundation
import NexusBridge

struct DemandTaskTransferItem: Identifiable, Hashable {
    let title: String
    let intakeStatus: String
    let priority: String
    let source: String
    let detail: String
    let sourceLine: Int

    var id: String {
        "\(sourceLine):\(normalizedTitle)"
    }

    var normalizedTitle: String {
        Self.normalizeTitle(title)
    }

    var executionStatus: String {
        "待办"
    }

    var executionPriorityMarker: String {
        switch priority.uppercased() {
        case "P0":
            "high"
        case "P1":
            "medium"
        case "P3":
            "low"
        default:
            "normal"
        }
    }

    var executionDetail: String {
        [
            "priority=\(executionPriorityMarker)",
            "source=需求/tasks.md",
            "L\(sourceLine)",
            source.isEmpty ? nil : "来源: \(source)",
            detail.isEmpty ? nil : detail,
            intakeStatus.isEmpty ? nil : "预检状态: \(intakeStatus)"
        ]
            .compactMap { $0 }
            .joined(separator: "; ")
    }

    var markdownRow: String {
        "| \(Self.markdownTableCell(title)) | \(executionStatus) | \(Self.markdownTableCell(executionDetail)) |"
    }

    static func normalizeTitle(_ title: String) -> String {
        title
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: " ", with: "")
            .replacingOccurrences(of: "　", with: "")
    }

    private static func markdownTableCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "|", with: "\\|")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct DemandTaskTransferPlan: Identifiable, Hashable {
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let workspacePath: String
    let intakeTasksPath: String
    let executionTasksPath: String
    let candidates: [DemandTaskTransferItem]
    let existingTitles: Set<String>
    let expectedIntakeRevision: NativeDemandTaskDocumentRevision
    let expectedExecutionRevision: NativeDemandTaskDocumentRevision
    let blockerSummary: String?
    let blockerPath: String?

    var id: String {
        workspaceID
    }

    var transferableItems: [DemandTaskTransferItem] {
        candidates.filter { !existingTitles.contains($0.normalizedTitle) }
    }

    var duplicateCount: Int {
        candidates.count - transferableItems.count
    }

    var hasTransferableItems: Bool {
        !isBlocked && !transferableItems.isEmpty
    }

    var isBlocked: Bool {
        blockerSummary != nil
    }

    var summary: String {
        if let blockerSummary {
            return blockerSummary
        }
        if candidates.isEmpty {
            return "需求/tasks.md 中还没有可转入的真实需求点。"
        }
        if transferableItems.isEmpty {
            return "需求任务已在 root tasks.md 中存在，无需重复转入。"
        }
        if duplicateCount > 0 {
            return "将转入 \(transferableItems.count) 个需求点，跳过 \(duplicateCount) 个已存在任务。"
        }
        return "将转入 \(transferableItems.count) 个需求点到 root tasks.md。"
    }

    static func resolve(
        workspace: WorkspaceSummary,
        status: DemandIntakeStatus,
        fileManager: FileManager = .default
    ) -> DemandTaskTransferPlan {
        let intakeTasksPath = status.files.first { $0.key == "tasks" }?.path
            ?? "\(workspace.path)/需求/tasks.md"
        let executionTasksPath = workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md"
        let intakeSnapshot = NativeDemandTaskTransferStore.inspectDocument(
            at: intakeTasksPath,
            fileManager: fileManager
        )
        let executionSnapshot = NativeDemandTaskTransferStore.inspectDocument(
            at: executionTasksPath,
            fileManager: fileManager
        )
        let candidates = demandTaskCandidates(in: intakeSnapshot.content ?? "")
        let existingTitles = Set(
            (executionSnapshot.content.map {
                NativeWorkspaceTaskParser.rows(from: $0, folder: workspace.id)
            } ?? [])
                .map { DemandTaskTransferItem.normalizeTitle($0.snapshot.title) }
        )
        let blocker = blocker(
            intakePath: intakeTasksPath,
            intakeRevision: intakeSnapshot.revision,
            executionPath: executionTasksPath,
            executionRevision: executionSnapshot.revision
        )

        return DemandTaskTransferPlan(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            intakeTasksPath: intakeTasksPath,
            executionTasksPath: executionTasksPath,
            candidates: candidates,
            existingTitles: existingTitles,
            expectedIntakeRevision: intakeSnapshot.revision,
            expectedExecutionRevision: executionSnapshot.revision,
            blockerSummary: blocker.summary,
            blockerPath: blocker.path
        )
    }

    private static func blocker(
        intakePath: String,
        intakeRevision: NativeDemandTaskDocumentRevision,
        executionPath: String,
        executionRevision: NativeDemandTaskDocumentRevision
    ) -> (summary: String?, path: String?) {
        if case .regularUTF8 = intakeRevision {
            // A missing root tasks.md is a safe, new-document state.
        } else {
            return (blockerSummary(for: intakeRevision, path: intakePath), intakePath)
        }
        if case .regularUTF8 = executionRevision {
            return (nil, nil)
        }
        if case .missing = executionRevision {
            return (nil, nil)
        }
        return (blockerSummary(for: executionRevision, path: executionPath), executionPath)
    }

    private static func blockerSummary(
        for revision: NativeDemandTaskDocumentRevision,
        path: String
    ) -> String {
        switch revision {
        case .missing:
            let expandedPath = (path as NSString).expandingTildeInPath
            return "demand task document is missing: \(expandedPath)"
        case .regularUTF8:
            return ""
        case .invalid(let reason):
            return reason
        }
    }

    private static func demandTaskCandidates(in text: String) -> [DemandTaskTransferItem] {
        tableRowsWithLineNumbers(in: text).compactMap { sourceLine, cells in
            guard let title = cells.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  !isDemandTaskHeader(title),
                  !isTemplateDemandTaskTitle(title),
                  !isPlaceholderOnly(title) else {
                return nil
            }

            let status = cells[safe: 1]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "待办"
            guard !isDoneOrDeferred(status) else {
                return nil
            }

            return DemandTaskTransferItem(
                title: title,
                intakeStatus: status.isEmpty ? "待办" : status,
                priority: cells[safe: 2]?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
                    ? cells[2].trimmingCharacters(in: .whitespacesAndNewlines)
                    : "P2",
                source: cells[safe: 3]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                detail: cells[safe: 4]?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "",
                sourceLine: sourceLine
            )
        }
    }

    private static func tableRowsWithLineNumbers(in text: String) -> [(Int, [String])] {
        text.components(separatedBy: .newlines).enumerated().compactMap { offset, rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("|"), line.hasSuffix("|"), !line.contains("| ---") else {
                return nil
            }
            let cells = line
                .dropFirst()
                .dropLast()
                .split(separator: "|", omittingEmptySubsequences: false)
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            return (offset + 1, cells)
        }
    }

    private static func isDemandTaskHeader(_ title: String) -> Bool {
        title == "需求点" || title == "任务"
    }

    private static func isTemplateDemandTaskTitle(_ title: String) -> Bool {
        ["整理 requirement.md", "整理 questions.md", "冻结 scope.md"].contains(title)
    }

    private static func isDoneOrDeferred(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized.contains("完成")
            || normalized.contains("done")
            || normalized.contains("延期")
            || normalized.contains("deferred")
    }

    private static func isPlaceholderOnly(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return ["待整理", "待确认", "待补充", "todo", "tbd", "placeholder"].contains { normalized.contains($0) }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
