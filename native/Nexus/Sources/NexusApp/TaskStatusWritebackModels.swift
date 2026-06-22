import Foundation

struct TaskStatusPostWriteCheck: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let evidencePath: String?
}

enum TaskStatusMutationKind: String, Hashable {
    case progress
    case close
}

struct TaskStatusMutationPolicy: Hashable {
    let kind: TaskStatusMutationKind
    let requiresConfirmationSheet: Bool
    let targetDocumentName: String
    let reason: String

    static func resolve(nextStatus: String) -> TaskStatusMutationPolicy {
        if closesActiveTaskStatus(nextStatus) {
            return TaskStatusMutationPolicy(
                kind: .close,
                requiresConfirmationSheet: true,
                targetDocumentName: "root tasks.md",
                reason: "完成、延期或关闭任务会改变开发主路径和交付门禁，必须先经过确认 sheet。"
            )
        }

        return TaskStatusMutationPolicy(
            kind: .progress,
            requiresConfirmationSheet: true,
            targetDocumentName: "root tasks.md",
            reason: "任务状态写回只能更新执行队列 root tasks.md，并且需要确认 sheet 记录写入意图。"
        )
    }

    private static func closesActiveTaskStatus(_ status: String) -> Bool {
        TaskStatusUpdate.closesActiveTaskStatus(status)
    }
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

    var mutationPolicy: TaskStatusMutationPolicy {
        TaskStatusMutationPolicy.resolve(nextStatus: nextStatus)
    }

    var requiresConfirmationSheet: Bool {
        mutationPolicy.requiresConfirmationSheet
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

    static func closesActiveTaskStatus(_ status: String) -> Bool {
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
