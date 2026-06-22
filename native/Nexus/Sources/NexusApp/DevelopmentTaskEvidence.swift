import Foundation

struct DevelopmentTaskCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
    let taskID: String?
}

enum DevelopmentTaskSourceRole: String, Hashable {
    case executionQueue
    case intakeEvidence

    var displayLabel: String {
        switch self {
        case .executionQueue:
            "执行队列 / Execution"
        case .intakeEvidence:
            "预检证据 / Intake"
        }
    }
}

struct DevelopmentTaskSource: Hashable, Identifiable {
    let role: DevelopmentTaskSourceRole
    let path: String
    let detail: String
    let participatesInExecutionQueue: Bool

    var id: DevelopmentTaskSourceRole { role }
}

enum DevelopmentTaskPlanAction: String, Hashable {
    case resolveBlocker
    case continueTask
    case queued
    case closed

    var displayLabel: String {
        switch self {
        case .resolveBlocker:
            return "处理阻塞 / Resolve"
        case .continueTask:
            return "当前推进 / Continue"
        case .queued:
            return "排队 / Queued"
        case .closed:
            return "已关闭 / Closed"
        }
    }

    var status: WorkflowPathStatus {
        switch self {
        case .resolveBlocker:
            return .blocked
        case .continueTask:
            return .next
        case .queued:
            return .review
        case .closed:
            return .ready
        }
    }

    var systemImage: String {
        switch self {
        case .resolveBlocker:
            return "pause.circle"
        case .continueTask:
            return "play.circle"
        case .queued:
            return "text.line.first.and.arrowtriangle.forward"
        case .closed:
            return "checkmark.circle"
        }
    }

    var sortRank: Int {
        switch self {
        case .resolveBlocker:
            return 0
        case .continueTask:
            return 1
        case .queued:
            return 2
        case .closed:
            return 3
        }
    }
}

struct DevelopmentTaskPlanItem: Hashable, Identifiable {
    let id: String
    let taskID: String
    let title: String
    let action: DevelopmentTaskPlanAction
    let priority: String
    let statusText: String
    let sourceLine: Int?
    let reason: String
    let writebackHint: String
}

struct DevelopmentTaskEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let evidence: [String]
    let sources: [DevelopmentTaskSource]
    let checks: [DevelopmentTaskCheck]
    let tasksPath: String
    let taskPlan: [DevelopmentTaskPlanItem]
    let activeTasks: [WorkspaceTask]
    let blockedTasks: [WorkspaceTask]
    let deferredTaskCount: Int
    let doneTaskCount: Int
    let nextTask: WorkspaceTask?

    var ready: Bool {
        status == .ready
    }

    var title: String {
        if !blockedTasks.isEmpty {
            return "处理阻塞任务 / Resolve tasks"
        }
        if nextTask != nil {
            return "继续开发任务 / Continue task"
        }
        return "开发任务已清理 / Tasks clear"
    }

    var primaryActionLabel: String {
        if !blockedTasks.isEmpty {
            return "处理阻塞"
        }
        if nextTask != nil {
            return "继续任务"
        }
        return "打开任务"
    }

    var primaryActionSystemImage: String {
        if !blockedTasks.isEmpty {
            return "pause.circle"
        }
        if nextTask != nil {
            return "play.circle"
        }
        return "checklist.checked"
    }

    var primaryAction: WorkspaceMainStageAction {
        if let nextTask {
            return .task(nextTask.id)
        }
        return .document("tasks")
    }

    var taskValue: String {
        if !blockedTasks.isEmpty {
            return "阻 \(blockedTasks.count) / 开 \(activeTasks.count)"
        }
        if !activeTasks.isEmpty {
            return "开 \(activeTasks.count)"
        }
        return "已清理"
    }

    static func resolve(workspace: WorkspaceSummary) -> DevelopmentTaskEvidence {
        let tasksPath = workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md"
        let intakeTasksPath = workspace.documentLinks["demandTasks"] ?? "\(workspace.path)/需求/tasks.md"
        let activeTasks = workspace.tasks
            .filter(\.isActive)
            .sorted(by: taskSort)
        let blockedTasks = activeTasks
            .filter(\.isBlocked)
            .sorted(by: taskSort)
        let deferredCount = workspace.tasks.filter(\.isDeferred).count
        let doneCount = workspace.tasks.filter(\.isDone).count
        let nextTask = blockedTasks.first ?? activeTasks.first
        let taskPlan = buildTaskPlan(tasks: workspace.tasks, nextTask: nextTask)
        let sources = [
            DevelopmentTaskSource(
                role: .executionQueue,
                path: tasksPath,
                detail: "开发执行任务只能来自 root tasks.md；完成、延期和进行中写回都指向这个文件。",
                participatesInExecutionQueue: true
            ),
            DevelopmentTaskSource(
                role: .intakeEvidence,
                path: intakeTasksPath,
                detail: "需求/tasks.md 保留需求预检拆解结果，只能经确认转入 root tasks.md 后参与开发执行。",
                participatesInExecutionQueue: false
            )
        ]

        let checks = [
            DevelopmentTaskCheck(
                id: "execution-source",
                label: "执行来源 / Source",
                detail: "root tasks.md 是开发执行任务源；需求/tasks.md 只作为预检任务输入。",
                status: .ready,
                systemImage: "checklist",
                path: tasksPath,
                taskID: nil
            ),
            DevelopmentTaskCheck(
                id: "blocked-tasks",
                label: "阻塞任务 / Blockers",
                detail: blockedTasks.isEmpty
                    ? "当前没有阻塞任务。"
                    : "\(blockedTasks.count) 个阻塞任务需要先处理：\(blockedTasks.prefix(3).map(\.title).joined(separator: ", "))。",
                status: blockedTasks.isEmpty ? .ready : .blocked,
                systemImage: blockedTasks.isEmpty ? "checkmark.circle" : "pause.circle",
                path: tasksPath,
                taskID: blockedTasks.first?.id
            ),
            DevelopmentTaskCheck(
                id: "active-tasks",
                label: "活跃任务 / Active",
                detail: activeTasks.isEmpty
                    ? "root tasks.md 没有活跃任务。"
                    : "\(activeTasks.count) 个活跃任务；下一条：\(nextTask?.title ?? "未定位")。",
                status: activeTasks.isEmpty ? .ready : .next,
                systemImage: activeTasks.isEmpty ? "checkmark.circle" : "play.circle",
                path: tasksPath,
                taskID: nextTask?.id
            ),
            DevelopmentTaskCheck(
                id: "closed-tasks",
                label: "已完成/延期 / Closed",
                detail: "\(doneCount) 个已完成，\(deferredCount) 个延期；延期任务不阻塞当前开发主路径。",
                status: .ready,
                systemImage: "tray.full",
                path: tasksPath,
                taskID: nil
            )
        ]

        let status: WorkflowPathStatus
        let reason: String
        if !blockedTasks.isEmpty {
            status = .blocked
            reason = "\(blockedTasks.count) 个任务仍处于阻塞状态。先定位 root tasks.md 中的阻塞任务，确认完成、延期或拆分处理。"
        } else if let nextTask {
            status = .next
            reason = "下一条开发任务：\(nextTask.title)。后续开发按照 root tasks.md 中未完成项推进。"
        } else {
            status = .ready
            reason = "root tasks.md 当前没有活跃任务，可以进入交付检查。"
        }

        return DevelopmentTaskEvidence(
            status: status,
            reason: reason,
            evidence: taskEvidence(sources: sources, nextTask: nextTask),
            sources: sources,
            checks: checks,
            tasksPath: tasksPath,
            taskPlan: taskPlan,
            activeTasks: activeTasks,
            blockedTasks: blockedTasks,
            deferredTaskCount: deferredCount,
            doneTaskCount: doneCount,
            nextTask: nextTask
        )
    }

    var executionSources: [DevelopmentTaskSource] {
        sources.filter(\.participatesInExecutionQueue)
    }

    var intakeEvidenceSources: [DevelopmentTaskSource] {
        sources.filter { !$0.participatesInExecutionQueue }
    }

    private static func buildTaskPlan(tasks: [WorkspaceTask], nextTask: WorkspaceTask?) -> [DevelopmentTaskPlanItem] {
        tasks
            .map { task -> DevelopmentTaskPlanItem in
                let action: DevelopmentTaskPlanAction
                let reason: String
                let writebackHint: String

                if task.isBlocked {
                    action = .resolveBlocker
                    reason = "该任务处于阻塞状态，必须先确认完成、延期或拆分，交付前不能忽略。"
                    writebackHint = "解除阻塞后在 root tasks.md 中标记为进行中、已完成或延期。"
                } else if task.isActive && task.id == nextTask?.id {
                    action = .continueTask
                    reason = "这是当前主路径推荐的下一条任务，优先级和行号排序最靠前。"
                    writebackHint = "完成后将该行状态写回为已完成；暂不做则写回延期并说明原因。"
                } else if task.isActive {
                    action = .queued
                    reason = "该任务仍在活跃队列，但排在当前任务之后。"
                    writebackHint = "保持待办；轮到它时再推进，或明确延期。"
                } else {
                    action = .closed
                    reason = task.isDeferred
                        ? "延期任务不阻塞当前开发主路径。"
                        : "已完成任务不阻塞当前开发主路径。"
                    writebackHint = "无需写回；需要恢复时再把状态改回待办或进行中。"
                }

                return DevelopmentTaskPlanItem(
                    id: task.id,
                    taskID: task.id,
                    title: task.title,
                    action: action,
                    priority: task.priorityLabel,
                    statusText: task.status,
                    sourceLine: task.sourceLine,
                    reason: reason,
                    writebackHint: writebackHint
                )
            }
            .sorted(by: taskPlanSort)
    }

    private static func taskPlanSort(lhs: DevelopmentTaskPlanItem, rhs: DevelopmentTaskPlanItem) -> Bool {
        if lhs.action.sortRank != rhs.action.sortRank {
            return lhs.action.sortRank < rhs.action.sortRank
        }
        switch (lhs.sourceLine, rhs.sourceLine) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    private static func taskEvidence(sources: [DevelopmentTaskSource], nextTask: WorkspaceTask?) -> [String] {
        var evidence = sources.map { source in
            switch source.role {
            case .executionQueue:
                return "tasks.md"
            case .intakeEvidence:
                return "需求/tasks.md"
            }
        }
        if let nextTask {
            evidence.append(nextTask.sourceLine.map { "tasks.md:L\($0)" } ?? nextTask.title)
        }
        return evidence
    }

    private static func taskSort(lhs: WorkspaceTask, rhs: WorkspaceTask) -> Bool {
        if lhs.priorityRank != rhs.priorityRank {
            return lhs.priorityRank < rhs.priorityRank
        }
        switch (lhs.sourceLine, rhs.sourceLine) {
        case let (left?, right?) where left != right:
            return left < right
        case (.some, nil):
            return true
        case (nil, .some):
            return false
        default:
            return lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }
}
