import Foundation
import NexusBridge

struct WorkspaceLifecycle: Hashable {
    let stage: String
    let label: String
    let detail: String
    let progress: Int
    let nextAction: String
    let documentKey: String

    var normalizedProgress: Double {
        Double(min(max(progress, 0), 100)) / 100
    }
}

extension WorkspaceLifecycle {
    init(
        snapshot: WorkspaceLifecycleSnapshot?,
        state: String,
        targetBranch: String,
        services: [ServiceStatus],
        risks: [RiskAlert],
        tasks: [WorkspaceTask]
    ) {
        if let snapshot {
            self.init(
                stage: snapshot.stage,
                label: snapshot.label,
                detail: snapshot.detail,
                progress: snapshot.progress,
                nextAction: snapshot.nextAction,
                documentKey: snapshot.documentKey
            )
            return
        }

        let openTasks = tasks.filter(\.isActive).count
        let hasMissingWorktree = services.contains { !$0.worktreeExists }
        let hasDeliveryRisk = risks.contains { risk in
            let normalized = "\(risk.title) \(risk.detail)".lowercased()
            return normalized.contains("交付") || normalized.contains("delivery")
        }
        if state.lowercased().contains("blocked") || state.contains("阻塞") {
            self.init(
                stage: "blocked",
                label: "阻塞 / Blocked",
                detail: "工作区处于阻塞状态，需要先确认阻塞原因。",
                progress: 25,
                nextAction: "先处理阻塞项。",
                documentKey: "tasks"
            )
        } else if targetBranch.contains("待确认") || services.isEmpty {
            self.init(
                stage: "scoping",
                label: "范围确认 / Scoping",
                detail: "服务范围或目标分支仍待确认。",
                progress: 15,
                nextAction: "补齐服务范围和目标分支。",
                documentKey: services.isEmpty ? "services" : "branches"
            )
        } else if hasMissingWorktree {
            self.init(
                stage: "setup",
                label: "环境准备 / Setup",
                detail: "仍有服务缺少 workspace-local worktree。",
                progress: 35,
                nextAction: "创建缺失 worktree 后再进入开发。",
                documentKey: "worktreeScript"
            )
        } else if hasDeliveryRisk {
            self.init(
                stage: "delivery",
                label: "交付整理 / Delivery",
                detail: "交付记录需要补齐。",
                progress: 80,
                nextAction: "补齐交付记录、SQL、验证和风险说明。",
                documentKey: "delivery"
            )
        } else if openTasks == 0 && risks.isEmpty {
            self.init(
                stage: "done",
                label: "待归档 / Done",
                detail: "暂无开放任务和风险，可以归档或保留观察。",
                progress: 95,
                nextAction: "确认 PR/发布状态后归档工作区。",
                documentKey: "delivery"
            )
        } else {
            self.init(
                stage: "developing",
                label: "开发中 / Developing",
                detail: "\(openTasks) 个活跃任务需要继续处理。",
                progress: 60,
                nextAction: "继续编码、验证，并保持交付记录同步。",
                documentKey: "tasks"
            )
        }
    }
}

struct LifecycleTransition: Identifiable, Hashable {
    let state: String
    let label: String
    let focus: String
    let nextAction: String
    let systemImage: String

    var id: String { state }

    static let developing = LifecycleTransition(
        state: "developing",
        label: "进入开发 / Develop",
        focus: "编码、验证，并持续同步交付记录",
        nextAction: "继续开发并运行必要验证",
        systemImage: "hammer"
    )

    static let restoreDevelopment = LifecycleTransition(
        state: "developing",
        label: "恢复开发 / Restore",
        focus: "从归档历史恢复为活跃开发",
        nextAction: "重新运行本地检查，确认分支、worktree、任务和交付记录仍可继续",
        systemImage: "arrow.uturn.backward.circle"
    )

    static let delivery = LifecycleTransition(
        state: "delivery",
        label: "进入交付 / Delivery",
        focus: "补齐交付记录、SQL、验证和风险说明",
        nextAction: "更新交付记录并完成验证",
        systemImage: "doc.text"
    )

    static let done = LifecycleTransition(
        state: "done",
        label: "标记完成 / Done",
        focus: "确认 PR、CI、发布和遗留风险",
        nextAction: "确认可以归档或进入观察",
        systemImage: "checkmark.seal"
    )

    static let blocked = LifecycleTransition(
        state: "blocked",
        label: "标记阻塞 / Block",
        focus: "解除阻塞项",
        nextAction: "先处理阻塞原因，再恢复生命周期",
        systemImage: "pause.circle"
    )

    static let archived = LifecycleTransition(
        state: "archived",
        label: "归档 / Archive",
        focus: "保留历史上下文",
        nextAction: "需要再次开发时从 handoff 恢复上下文",
        systemImage: "archivebox"
    )
}

struct LifecycleStatusUpdate: Identifiable, Hashable {
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let workspacePath: String
    let currentStage: String
    let currentLabel: String
    let nextState: String
    let nextLabel: String
    let focus: String
    let nextAction: String

    var id: String {
        "\(workspaceID):\(nextState)"
    }
}
