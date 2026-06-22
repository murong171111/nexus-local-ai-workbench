import Foundation

struct TaskStatusPostWriteCheck: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let evidencePath: String?
}

struct TaskStatusUpdate: Identifiable, Hashable {
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let workspacePath: String
    let taskID: String
    let taskTitle: String
    let taskSourceLine: Int?
    let currentStatus: String
    let nextStatus: String
    let postWriteChecks: [TaskStatusPostWriteCheck]

    var id: String {
        "\(workspaceID):\(taskID):\(nextStatus)"
    }

    var tasksPath: String {
        "\(workspacePath)/tasks.md"
    }

    var evidencePaths: [String] {
        postWriteChecks.compactMap(\.evidencePath)
    }

    var requiresLocalCheckAfterWrite: Bool {
        postWriteChecks.contains { $0.id == "local-check" }
    }

    static func postWriteChecks(
        for task: WorkspaceTask,
        workspace: WorkspaceSummary,
        nextStatus: String
    ) -> [TaskStatusPostWriteCheck] {
        let tasksPath = workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md"
        var checks = [
            TaskStatusPostWriteCheck(
                id: "task-row",
                label: "任务行 / Task row",
                detail: task.sourceLine.map { "确认 root tasks.md 第 \($0) 行已从 \(task.status) 写回为 \(nextStatus)。" }
                    ?? "确认 root tasks.md 中的任务已从 \(task.status) 写回为 \(nextStatus)。",
                status: .review,
                systemImage: "checklist",
                evidencePath: tasksPath
            ),
            TaskStatusPostWriteCheck(
                id: "next-task",
                label: "下一任务 / Next task",
                detail: "写回后 Task Center 会优先聚焦同一工作区的下一条活跃任务；没有下一条时回到交付检查。",
                status: .next,
                systemImage: "arrow.forward.circle",
                evidencePath: tasksPath
            )
        ]

        if closesActiveTaskStatus(nextStatus) {
            checks.append(
                TaskStatusPostWriteCheck(
                    id: "local-check",
                    label: "本地检查 / Local check",
                    detail: "关闭活跃任务后重新运行本地检查，刷新主阶段、任务统计、风险和交付门禁。",
                    status: .next,
                    systemImage: "checkmark.seal",
                    evidencePath: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md"
                )
            )
        }

        return checks
    }

    private static func closesActiveTaskStatus(_ status: String) -> Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return [
            "done",
            "completed",
            "complete",
            "closed",
            "deferred",
            "已完成",
            "完成",
            "延期",
            "关闭",
            "已关闭"
        ].contains(normalized)
    }
}
