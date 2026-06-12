import Foundation
import NexusBridge

enum WorkspaceFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case active = "进行中"
    case risky = "有风险"
    case blocked = "阻塞"
    case archived = "归档"

    var id: String { rawValue }

    var subtitle: String {
        switch self {
        case .all:
            "All"
        case .active:
            "Active"
        case .risky:
            "Risk"
        case .blocked:
            "Blocked"
        case .archived:
            "Archive"
        }
    }

    var systemImage: String {
        switch self {
        case .all:
            "square.grid.2x2"
        case .active:
            "bolt"
        case .risky:
            "exclamationmark.triangle"
        case .blocked:
            "pause.circle"
        case .archived:
            "archivebox"
        }
    }

    func matches(_ workspace: WorkspaceSummary, query: String = "") -> Bool {
        let matchesFilter: Bool
        switch self {
        case .all:
            matchesFilter = true
        case .active:
            matchesFilter = !workspace.isArchived
                && (workspace.state == .developing || workspace.state == .analyzing)
        case .risky:
            matchesFilter = !workspace.isArchived
                && (workspace.riskLevel == .high || workspace.riskLevel == .medium)
        case .blocked:
            matchesFilter = !workspace.isArchived && workspace.state == .blocked
        case .archived:
            matchesFilter = workspace.isArchived
        }

        guard matchesFilter else { return false }

        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmedQuery.isEmpty else { return true }

        let haystack = [
            workspace.name,
            workspace.folder,
            workspace.branch,
            workspace.aiState,
            workspace.serviceSummary,
            workspace.worktreeState,
            workspace.sqlFiles.map(\.relativePath).joined(separator: " "),
            workspace.tasks.map(\.title).joined(separator: " "),
            workspace.tasks.map(\.detail).joined(separator: " ")
        ]
        .joined(separator: " ")
        .lowercased()

        return haystack.contains(trimmedQuery)
    }
}

enum SearchScope: String, CaseIterable, Identifiable {
    case all = "all"
    case workspace = "workspace"
    case state = "state"
    case workflow = "workflow"
    case sql = "sql"
    case documents = "documents"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            "全部"
        case .workspace:
            "工作区"
        case .state:
            "状态"
        case .workflow:
            "任务"
        case .sql:
            "SQL"
        case .documents:
            "文档"
        }
    }

    var subtitle: String {
        switch self {
        case .all:
            "All"
        case .workspace:
            "Workspace"
        case .state:
            "State"
        case .workflow:
            "Workflow"
        case .sql:
            "SQL"
        case .documents:
            "Docs"
        }
    }

    func matches(_ result: SearchResult) -> Bool {
        self == .all || result.groupID == rawValue
    }
}

enum TaskCenterFilter: String, CaseIterable, Identifiable {
    case all = "all"
    case high = "high"
    case agent = "agent"
    case deferred = "deferred"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            "全部"
        case .high:
            "高优先"
        case .agent:
            "Agent"
        case .deferred:
            "延期"
        }
    }

    var subtitle: String {
        switch self {
        case .all:
            "All"
        case .high:
            "P0"
        case .agent:
            "AI"
        case .deferred:
            "Later"
        }
    }

    func matches(_ item: TaskCenterItem) -> Bool {
        switch self {
        case .all:
            true
        case .high:
            item.task.isActive && item.task.priorityRank == 0
        case .agent:
            item.task.source == "agent"
        case .deferred:
            item.task.isDeferred
        }
    }
}

enum WorkflowPathStatus: String, CaseIterable, Hashable {
    case ready
    case review
    case blocked
    case pending
    case next
    case archived

    var displayLabel: String {
        switch self {
        case .ready:
            "就绪 / ready"
        case .review:
            "复核 / review"
        case .blocked:
            "阻塞 / block"
        case .pending:
            "待确认 / pending"
        case .next:
            "下一步 / next"
        case .archived:
            "归档 / archive"
        }
    }
}

enum WorkflowDeliveryRoute: String, Hashable {
    case runLocalCheck
    case updateDelivery
    case validationHandoff
    case openDelivery

    var displayLabel: String {
        switch self {
        case .runLocalCheck:
            "运行检查"
        case .updateDelivery:
            "交付交接"
        case .validationHandoff:
            "PR 交接"
        case .openDelivery:
            "打开文档"
        }
    }
}

struct WorkspaceWorkflowSummary: Hashable {
    let openTaskCount: Int
    let blockedTaskCount: Int
    let taskValue: String
    let taskStatus: WorkflowPathStatus
    let deliveryValue: String
    let deliveryStatus: WorkflowPathStatus
    let deliveryDetail: String
    let deliveryRoute: WorkflowDeliveryRoute

    init(workspace: WorkspaceSummary) {
        let openTasks = workspace.tasks.filter(\.isActive)
        let blockedTasks = openTasks.filter(\.isBlocked)
        openTaskCount = openTasks.count
        blockedTaskCount = blockedTasks.count

        if !blockedTasks.isEmpty {
            taskValue = "阻 \(blockedTasks.count) / 开 \(openTasks.count)"
            taskStatus = .blocked
        } else if !openTasks.isEmpty {
            taskValue = "开 \(openTasks.count)"
            taskStatus = .review
        } else {
            taskValue = "已清理"
            taskStatus = .ready
        }

        if workspace.isArchived {
            deliveryValue = "已归档"
            deliveryStatus = .archived
            deliveryDetail = "工作区已退出活跃交付流。"
            deliveryRoute = .openDelivery
        } else if workspace.lifecycle.stage == "done" {
            deliveryValue = "已完成"
            deliveryStatus = .ready
            deliveryDetail = "生命周期已标记完成。"
            deliveryRoute = .validationHandoff
        } else if workspace.lifecycle.stage == "delivery" {
            deliveryValue = "整理中"
            deliveryStatus = .review
            deliveryDetail = "工作区处于交付整理阶段。"
            deliveryRoute = .updateDelivery
        } else if let deliveryCheck = Self.deliveryCheck(in: workspace) {
            let normalizedStatus = deliveryCheck.status.lowercased()
            deliveryDetail = deliveryCheck.detail
            switch normalizedStatus {
            case "pass", "ok":
                deliveryValue = "记录可用"
                deliveryStatus = .ready
                deliveryRoute = .openDelivery
            case "warning", "review":
                deliveryValue = "需补充"
                deliveryStatus = .review
                deliveryRoute = .updateDelivery
            default:
                deliveryValue = "阻塞"
                deliveryStatus = .blocked
                deliveryRoute = .updateDelivery
            }
        } else if let deliveryRisk = Self.deliveryRisk(in: workspace) {
            deliveryValue = "需复核"
            deliveryStatus = .review
            deliveryDetail = deliveryRisk.detail
            deliveryRoute = .updateDelivery
        } else {
            deliveryValue = "待检查"
            deliveryStatus = .pending
            deliveryDetail = "尚未生成交付记录检查结果。"
            deliveryRoute = .runLocalCheck
        }
    }

    private static func deliveryCheck(in workspace: WorkspaceSummary) -> WorkspaceHealthCheck? {
        workspace.healthChecks.first { check in
            check.id == "delivery-record" || check.action == "delivery"
        }
    }

    private static func deliveryRisk(in workspace: WorkspaceSummary) -> RiskAlert? {
        workspace.risks.first { risk in
            let normalized = "\(risk.title) \(risk.detail)".lowercased()
            return normalized.contains("交付") || normalized.contains("delivery")
        }
    }
}

struct WorkspaceSqlSummary: Hashable {
    let value: String
    let detail: String
    let status: WorkflowPathStatus
    let actionLabel: String

    init(workspace: WorkspaceSummary) {
        let sqlFileCount = workspace.sqlFiles.count
        if let sqlCheck = Self.sqlCheck(in: workspace) {
            detail = sqlCheck.detail
            switch sqlCheck.status.lowercased() {
            case "pass", "ok":
                value = sqlFileCount > 0 ? "已匹配" : "无变更"
                status = .ready
                actionLabel = sqlFileCount > 0 ? "打开 SQL" : "复查 SQL"
            case "fail", "blocked", "blocker":
                value = "缺产物"
                status = .blocked
                actionLabel = "SQL 交接"
            default:
                value = "需复核"
                status = .review
                actionLabel = "SQL 交接"
            }
            return
        }

        if sqlFileCount > 0 {
            value = "\(sqlFileCount) 文件"
            detail = "已有 SQL 文件，但尚未生成 SQL 目录检查。运行本地检查确认正式/回滚匹配。"
            status = .review
            actionLabel = "复查 SQL"
        } else {
            value = "待检查"
            detail = "暂未生成 SQL 目录检查，运行本地检查后可刷新。"
            status = .pending
            actionLabel = "运行检查"
        }
    }

    private static func sqlCheck(in workspace: WorkspaceSummary) -> WorkspaceHealthCheck? {
        workspace.healthChecks.first { check in
            check.id == "sql-directory" || check.action == "sql"
        }
    }
}

struct DeliveryGateCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
    let action: WorkspaceMainStageAction
}

struct DeliveryGateEvidence: Hashable {
    let status: WorkflowPathStatus
    let title: String
    let reason: String
    let value: String
    let evidence: [String]
    let checks: [DeliveryGateCheck]
    let primaryActionLabel: String
    let primaryActionSystemImage: String
    let primaryAction: WorkspaceMainStageAction
    let blockerCount: Int
    let warningCount: Int

    var ready: Bool {
        status == .ready
    }

    static func resolve(workspace: WorkspaceSummary) -> DeliveryGateEvidence {
        if workspace.isArchived {
            return DeliveryGateEvidence(
                status: .archived,
                title: "已归档 / Archived",
                reason: "这个工作区已退出活跃交付流。需要恢复时先查看交付记录和 handoff。",
                value: "已归档",
                evidence: ["交付记录.md", "handoff.md"],
                checks: [],
                primaryActionLabel: "打开交付",
                primaryActionSystemImage: "archivebox",
                primaryAction: .document("delivery"),
                blockerCount: 0,
                warningCount: 0
            )
        }

        let checks = deliveryChecks(workspace: workspace)
        let blockers = checks.filter { $0.status == .blocked }
        let pending = checks.filter { $0.status == .pending }
        let reviews = checks.filter { $0.status == .review || $0.status == .next }

        let status: WorkflowPathStatus
        let title: String
        let value: String
        let primaryCheck: DeliveryGateCheck?
        if !blockers.isEmpty {
            status = .blocked
            title = "交付阻塞 / Delivery blocked"
            value = "阻 \(blockers.count)"
            primaryCheck = blockers.first
        } else if !pending.isEmpty {
            status = .pending
            title = "运行交付检查 / Check delivery"
            value = "待检查"
            primaryCheck = pending.first
        } else if !reviews.isEmpty {
            status = .review
            title = "整理交付 / Prepare delivery"
            value = "复核 \(reviews.count)"
            primaryCheck = reviews.first
        } else if workspace.lifecycle.stage == "done" {
            status = .ready
            title = "确认 PR 与 CI / Confirm PR and CI"
            value = "已完成"
            primaryCheck = nil
        } else {
            status = .ready
            title = "交付检查通过 / Delivery ready"
            value = "可交付"
            primaryCheck = nil
        }

        let reason: String
        let action: WorkspaceMainStageAction
        if let primaryCheck {
            reason = primaryCheck.detail
            action = primaryCheck.action
        } else if workspace.lifecycle.stage == "done" {
            reason = "生命周期已标记完成。下一步复核本地验证、PR、CI、发布和遗留风险。"
            action = .validationHandoff
        } else {
            reason = "任务、风险、服务/worktree、交付记录和 SQL 检查暂无硬阻塞。"
            action = .document("delivery")
        }

        return DeliveryGateEvidence(
            status: status,
            title: title,
            reason: reason,
            value: value,
            evidence: deliveryEvidence(workspace: workspace, checks: checks),
            checks: checks,
            primaryActionLabel: actionLabel(for: action, status: status),
            primaryActionSystemImage: actionSystemImage(for: action, status: status),
            primaryAction: action,
            blockerCount: blockers.count,
            warningCount: reviews.count + pending.count
        )
    }

    private static func deliveryChecks(workspace: WorkspaceSummary) -> [DeliveryGateCheck] {
        let worktree = WorktreeSetupEvidence.resolve(workspace: workspace)
        let tasks = DevelopmentTaskEvidence.resolve(workspace: workspace)
        let sql = WorkspaceSqlSummary(workspace: workspace)
        let delivery = deliveryRecordCheck(workspace: workspace)
        let risks = riskCheck(workspace: workspace)
        let dirty = dirtyServiceCheck(workspace: workspace)

        return [
            branchCheck(workspace: workspace),
            serviceWorktreeCheck(workspace: workspace, worktree: worktree),
            taskCheck(workspace: workspace, tasks: tasks),
            risks,
            delivery,
            sqlCheck(workspace: workspace, sql: sql),
            dirty
        ]
    }

    private static func branchCheck(workspace: WorkspaceSummary) -> DeliveryGateCheck {
        if hasConfirmedTargetBranch(workspace.branch) {
            return DeliveryGateCheck(
                id: "branch",
                label: "目标分支 / Branch",
                detail: "目标分支已确认：\(workspace.branch)。",
                status: .ready,
                systemImage: "arrow.triangle.branch",
                path: workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md",
                action: .document("branches")
            )
        }

        return DeliveryGateCheck(
            id: "branch",
            label: "目标分支 / Branch",
            detail: "目标分支仍待确认，交付检查无法判断代码是否在正确的开发线上。",
            status: .blocked,
            systemImage: "arrow.triangle.branch",
            path: workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md",
            action: .document("branches")
        )
    }

    private static func serviceWorktreeCheck(
        workspace: WorkspaceSummary,
        worktree: WorktreeSetupEvidence
    ) -> DeliveryGateCheck {
        if workspace.services.isEmpty {
            return DeliveryGateCheck(
                id: "services",
                label: "服务与 worktree / Services",
                detail: "服务范围待确认，无法判断交付涉及的代码范围。",
                status: .blocked,
                systemImage: "square.stack.3d.up",
                path: workspace.documentLinks["services"] ?? "\(workspace.path)/services.md",
                action: .document("services")
            )
        }

        if worktree.status == .ready {
            return DeliveryGateCheck(
                id: "services",
                label: "服务与 worktree / Services",
                detail: "\(workspace.services.count) 个服务均已有 workspace-local worktree，且分支与目标分支一致。",
                status: .ready,
                systemImage: "square.stack.3d.up",
                path: workspace.documentLinks["services"] ?? "\(workspace.path)/services.md",
                action: .document("services")
            )
        }

        return DeliveryGateCheck(
            id: "services",
            label: "服务与 worktree / Services",
            detail: worktree.reason,
            status: worktree.status == .blocked ? .blocked : .review,
            systemImage: worktree.primaryActionSystemImage,
            path: workspace.documentLinks["services"] ?? "\(workspace.path)/services.md",
            action: worktree.primaryAction
        )
    }

    private static func taskCheck(
        workspace: WorkspaceSummary,
        tasks: DevelopmentTaskEvidence
    ) -> DeliveryGateCheck {
        if !tasks.blockedTasks.isEmpty {
            return DeliveryGateCheck(
                id: "tasks",
                label: "任务状态 / Tasks",
                detail: "\(tasks.blockedTasks.count) 个任务仍处于阻塞状态，交付前需要完成、延期或拆分处理。",
                status: .blocked,
                systemImage: "checklist",
                path: tasks.tasksPath,
                action: tasks.primaryAction
            )
        }

        if !tasks.activeTasks.isEmpty {
            return DeliveryGateCheck(
                id: "tasks",
                label: "任务状态 / Tasks",
                detail: "\(tasks.activeTasks.count) 个任务仍在活跃队列，交付前需要确认是否完成或延期。",
                status: .review,
                systemImage: "checklist",
                path: tasks.tasksPath,
                action: tasks.primaryAction
            )
        }

        return DeliveryGateCheck(
            id: "tasks",
            label: "任务状态 / Tasks",
            detail: "root tasks.md 当前没有活跃任务。",
            status: .ready,
            systemImage: "checklist.checked",
            path: tasks.tasksPath,
            action: .document("tasks")
        )
    }

    private static func riskCheck(workspace: WorkspaceSummary) -> DeliveryGateCheck {
        if workspace.risks.isEmpty {
            return DeliveryGateCheck(
                id: "risks",
                label: "风险复核 / Risks",
                detail: "当前没有活动风险。",
                status: .ready,
                systemImage: "checkmark.shield",
                path: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md",
                action: .document("status")
            )
        }

        return DeliveryGateCheck(
            id: "risks",
            label: "风险复核 / Risks",
            detail: "\(workspace.risks.count) 个风险信号需要复核：\(workspace.risks.first?.title ?? "风险待复核")。",
            status: workspace.riskLevel == .high ? .blocked : .review,
            systemImage: "exclamationmark.triangle",
            path: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md",
            action: .riskPrompt
        )
    }

    private static func deliveryRecordCheck(workspace: WorkspaceSummary) -> DeliveryGateCheck {
        let path = workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md"
        if let check = workspace.healthChecks.first(where: { $0.id == "delivery-record" || $0.action == "delivery" }) {
            let normalized = check.status.lowercased()
            let status: WorkflowPathStatus
            switch normalized {
            case "pass", "ok":
                status = .ready
            case "warning", "review":
                status = .review
            default:
                status = .blocked
            }
            return DeliveryGateCheck(
                id: "delivery-record",
                label: "交付记录 / Delivery",
                detail: check.detail,
                status: status,
                systemImage: "doc.text",
                path: path,
                action: status == .ready ? .document("delivery") : .deliveryHandoff
            )
        }

        if let deliveryRisk = workspace.risks.first(where: { risk in
            let normalized = "\(risk.title) \(risk.detail)".lowercased()
            return normalized.contains("交付") || normalized.contains("delivery")
        }) {
            return DeliveryGateCheck(
                id: "delivery-record",
                label: "交付记录 / Delivery",
                detail: deliveryRisk.detail,
                status: .review,
                systemImage: "doc.text",
                path: path,
                action: .deliveryHandoff
            )
        }

        return DeliveryGateCheck(
            id: "delivery-record",
            label: "交付记录 / Delivery",
            detail: "尚未生成交付记录检查结果。运行本地检查确认代码、逻辑、配置、SQL 和验证记录是否完整。",
            status: .pending,
            systemImage: "doc.text.magnifyingglass",
            path: path,
            action: .localCheck
        )
    }

    private static func sqlCheck(
        workspace: WorkspaceSummary,
        sql: WorkspaceSqlSummary
    ) -> DeliveryGateCheck {
        let path = workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md"
        let action: WorkspaceMainStageAction = sql.status == .pending ? .localCheck : .document("sql")
        return DeliveryGateCheck(
            id: "sql",
            label: "SQL 产物 / SQL",
            detail: sql.detail,
            status: sql.status,
            systemImage: "cylinder.split.1x2",
            path: path,
            action: action
        )
    }

    private static func dirtyServiceCheck(workspace: WorkspaceSummary) -> DeliveryGateCheck {
        let dirty = dirtyServices(in: workspace)
        if dirty.isEmpty {
            return DeliveryGateCheck(
                id: "dirty-services",
                label: "服务 Git 状态 / Git",
                detail: "当前没有检测到未提交服务。",
                status: .ready,
                systemImage: "arrow.triangle.branch",
                path: workspace.documentLinks["services"] ?? "\(workspace.path)/services.md",
                action: .document("services")
            )
        }

        return DeliveryGateCheck(
            id: "dirty-services",
            label: "服务 Git 状态 / Git",
            detail: "\(dirty.count) 个服务存在未提交状态：\(dirty.map(\.name).joined(separator: ", "))。",
            status: .review,
            systemImage: "arrow.triangle.branch",
            path: workspace.documentLinks["services"] ?? "\(workspace.path)/services.md",
            action: .codex
        )
    }

    private static func deliveryEvidence(workspace: WorkspaceSummary, checks: [DeliveryGateCheck]) -> [String] {
        var values = [
            workspace.documentLinks["delivery"] ?? "交付记录.md",
            workspace.documentLinks["tasks"] ?? "tasks.md",
            "sql/",
            "repos/<service>"
        ]
        if let firstIssue = checks.first(where: { $0.status == .blocked || $0.status == .review || $0.status == .pending }) {
            values.append(firstIssue.label)
        }
        return values
    }

    private static func actionLabel(for action: WorkspaceMainStageAction, status: WorkflowPathStatus) -> String {
        switch action {
        case .lifecycle(let transition):
            switch transition.state {
            case "delivery":
                return "进入交付"
            case "done":
                return "标记完成"
            case "archived":
                return "归档"
            default:
                return transition.label
            }
        case .localCheck:
            return "运行检查"
        case .deliveryHandoff:
            return "交付交接"
        case .validationHandoff:
            return "PR 交接"
        case .riskPrompt:
            return "风险交接"
        case .worktree:
            return "创建 worktree"
        case .document(let key):
            if key == "sql" {
                return status == .blocked ? "SQL 交接" : "复查 SQL"
            }
            if key == "delivery" {
                return "打开交付"
            }
            if key == "tasks" {
                return "打开任务"
            }
            return "打开文档"
        case .task:
            return "打开任务"
        case .path:
            return "打开文档"
        case .codex:
            return "交接 Codex"
        case .demandIntake:
            return "打开预检"
        case .transferDemandTasks:
            return "转入任务"
        }
    }

    private static func actionSystemImage(for action: WorkspaceMainStageAction, status: WorkflowPathStatus) -> String {
        switch action {
        case .lifecycle(let transition):
            return transition.systemImage
        case .localCheck:
            return "checklist"
        case .deliveryHandoff, .validationHandoff, .riskPrompt, .codex:
            return "point.3.connected.trianglepath.dotted"
        case .worktree:
            return "wrench.and.screwdriver"
        case .document(let key):
            if key == "sql" {
                return "cylinder.split.1x2"
            }
            if key == "tasks" {
                return "checklist"
            }
            return status == .ready ? "doc.text.magnifyingglass" : "doc.text"
        case .task:
            return "text.line.first.and.arrowtriangle.forward"
        case .path:
            return "doc.text"
        case .demandIntake:
            return "text.badge.checkmark"
        case .transferDemandTasks:
            return "arrow.down.doc"
        }
    }

    private static func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("pending")
            && !normalized.contains("todo")
            && normalized != "-"
    }

    private static func dirtyServices(in workspace: WorkspaceSummary) -> [ServiceStatus] {
        workspace.services.filter { service in
            let normalized = "\(service.gitSummary) \(service.worktree)".lowercased()
            return normalized.contains("dirty")
                || normalized.contains("modified")
                || normalized.contains("uncommitted")
                || normalized.contains("未提交")
                || normalized.contains("有改动")
                || normalized.contains("不是 git")
                || normalized.contains("not git")
                || normalized.contains("检查失败")
                || normalized.contains("failed")
        }
    }
}

struct ArchiveGateCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
    let action: WorkspaceMainStageAction
}

struct ArchiveGateEvidence: Hashable {
    let status: WorkflowPathStatus
    let title: String
    let reason: String
    let value: String
    let evidence: [String]
    let checks: [ArchiveGateCheck]
    let primaryActionLabel: String
    let primaryActionSystemImage: String
    let primaryAction: WorkspaceMainStageAction
    let blockerCount: Int
    let warningCount: Int

    var ready: Bool {
        status == .ready
    }

    static func resolve(
        workspace: WorkspaceSummary,
        deliveryGate: DeliveryGateEvidence? = nil
    ) -> ArchiveGateEvidence {
        if workspace.isArchived {
            return ArchiveGateEvidence(
                status: .archived,
                title: "已归档 / Archived",
                reason: "这个工作区已退出活跃开发流。需要恢复时先查看交接、交付记录和审计上下文。",
                value: "已归档",
                evidence: archiveEvidence(workspace: workspace),
                checks: [],
                primaryActionLabel: "查看交接",
                primaryActionSystemImage: "doc.text",
                primaryAction: .document("handoff"),
                blockerCount: 0,
                warningCount: 0
            )
        }

        let delivery = deliveryGate ?? DeliveryGateEvidence.resolve(workspace: workspace)
        if delivery.status != .ready {
            let checks = delivery.checks.map { check in
                ArchiveGateCheck(
                    id: "delivery-\(check.id)",
                    label: check.label,
                    detail: check.detail,
                    status: check.status,
                    systemImage: check.systemImage,
                    path: check.path,
                    action: check.action
                )
            }
            return ArchiveGateEvidence(
                status: delivery.status,
                title: "归档前先完成交付 / Finish delivery first",
                reason: delivery.reason,
                value: delivery.value,
                evidence: delivery.evidence + ["归档依赖交付门禁"],
                checks: checks,
                primaryActionLabel: delivery.primaryActionLabel,
                primaryActionSystemImage: delivery.primaryActionSystemImage,
                primaryAction: delivery.primaryAction,
                blockerCount: delivery.blockerCount,
                warningCount: delivery.warningCount
            )
        }

        let lifecycleStage = workspace.lifecycle.stage.lowercased()
        if lifecycleStage == "done" {
            return ArchiveGateEvidence(
                status: .ready,
                title: "可以归档 / Ready to archive",
                reason: "交付门禁已通过，生命周期已标记完成。归档会通过确认弹窗写回 workspace.md 和 STATUS.md。",
                value: "可归档",
                evidence: archiveEvidence(workspace: workspace),
                checks: [
                    deliveryPassedCheck(workspace: workspace),
                    lifecycleCheck(
                        workspace: workspace,
                        detail: "生命周期已标记完成，可以进入归档确认。",
                        status: .ready,
                        action: .lifecycle(.archived)
                    )
                ],
                primaryActionLabel: "归档",
                primaryActionSystemImage: LifecycleTransition.archived.systemImage,
                primaryAction: .lifecycle(.archived),
                blockerCount: 0,
                warningCount: 0
            )
        }

        if lifecycleStage == "delivery" {
            return ArchiveGateEvidence(
                status: .next,
                title: "先标记完成 / Mark done first",
                reason: "交付门禁已通过，但归档前需要先把生命周期确认到完成状态，留出 PR、CI、发布和遗留风险复核窗口。",
                value: "待完成",
                evidence: archiveEvidence(workspace: workspace),
                checks: [
                    deliveryPassedCheck(workspace: workspace),
                    lifecycleCheck(
                        workspace: workspace,
                        detail: "当前处于交付整理阶段。先标记完成，再进入归档确认。",
                        status: .next,
                        action: .lifecycle(.done)
                    )
                ],
                primaryActionLabel: "标记完成",
                primaryActionSystemImage: LifecycleTransition.done.systemImage,
                primaryAction: .lifecycle(.done),
                blockerCount: 0,
                warningCount: 1
            )
        }

        return ArchiveGateEvidence(
            status: .next,
            title: "先进入交付 / Enter delivery first",
            reason: "交付门禁已通过，但生命周期仍是 \(workspace.lifecycle.label)。归档前先进入交付整理或完成确认，避免跳过最终复核。",
            value: "待交付",
            evidence: archiveEvidence(workspace: workspace),
            checks: [
                deliveryPassedCheck(workspace: workspace),
                lifecycleCheck(
                    workspace: workspace,
                    detail: "当前生命周期不是交付或完成状态。先进入交付整理，再做完成和归档确认。",
                    status: .next,
                    action: .lifecycle(.delivery)
                )
            ],
            primaryActionLabel: "进入交付",
            primaryActionSystemImage: LifecycleTransition.delivery.systemImage,
            primaryAction: .lifecycle(.delivery),
            blockerCount: 0,
            warningCount: 1
        )
    }

    private static func archiveEvidence(workspace: WorkspaceSummary) -> [String] {
        [
            workspace.documentLinks["delivery"] ?? "交付记录.md",
            workspace.documentLinks["handoff"] ?? "handoff.md",
            workspace.documentLinks["status"] ?? "STATUS.md",
            "workspace.md",
            "sql/"
        ]
    }

    private static func deliveryPassedCheck(workspace: WorkspaceSummary) -> ArchiveGateCheck {
        ArchiveGateCheck(
            id: "delivery-gate",
            label: "交付门禁 / Delivery gate",
            detail: "任务、风险、服务/worktree、交付记录、SQL 和未提交服务检查暂无硬阻塞。",
            status: .ready,
            systemImage: "checkmark.seal",
            path: workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md",
            action: .document("delivery")
        )
    }

    private static func lifecycleCheck(
        workspace: WorkspaceSummary,
        detail: String,
        status: WorkflowPathStatus,
        action: WorkspaceMainStageAction
    ) -> ArchiveGateCheck {
        ArchiveGateCheck(
            id: "lifecycle",
            label: "生命周期 / Lifecycle",
            detail: detail,
            status: status,
            systemImage: workspace.lifecycle.stage == "done" ? "checkmark.seal" : "arrow.right.circle",
            path: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md",
            action: action
        )
    }
}

enum WorkspaceMainStageID: String, CaseIterable, Hashable {
    case created
    case demandIntake = "demand_intake"
    case scopeFreeze = "scope_freeze"
    case serviceBranchConfirm = "service_branch_confirm"
    case worktreeSetup = "worktree_setup"
    case development
    case deliveryCheck = "delivery_check"
    case archived

    var label: String {
        switch self {
        case .created:
            "已建档 / Created"
        case .demandIntake:
            "需求预检 / Demand intake"
        case .scopeFreeze:
            "范围冻结 / Scope freeze"
        case .serviceBranchConfirm:
            "服务分支 / Service & branch"
        case .worktreeSetup:
            "Worktree 准备 / Worktree"
        case .development:
            "开发任务 / Development"
        case .deliveryCheck:
            "交付检查 / Delivery"
        case .archived:
            "归档 / Archive"
        }
    }

    var shortLabel: String {
        switch self {
        case .created:
            "建档"
        case .demandIntake:
            "预检"
        case .scopeFreeze:
            "范围"
        case .serviceBranchConfirm:
            "服务/分支"
        case .worktreeSetup:
            "Worktree"
        case .development:
            "开发"
        case .deliveryCheck:
            "交付"
        case .archived:
            "归档"
        }
    }

    var systemImage: String {
        switch self {
        case .created:
            "folder.badge.plus"
        case .demandIntake:
            "text.badge.checkmark"
        case .scopeFreeze:
            "scope"
        case .serviceBranchConfirm:
            "arrow.triangle.branch"
        case .worktreeSetup:
            "wrench.and.screwdriver"
        case .development:
            "hammer"
        case .deliveryCheck:
            "shippingbox"
        case .archived:
            "archivebox"
        }
    }
}

enum WorkspaceMainStageAction: Hashable {
    case lifecycle(LifecycleTransition)
    case demandIntake
    case document(String)
    case path(String)
    case task(String)
    case transferDemandTasks
    case worktree
    case riskPrompt
    case localCheck
    case deliveryHandoff
    case validationHandoff
    case codex
}

struct WorkspaceMainStage: Hashable {
    let id: WorkspaceMainStageID
    let status: WorkflowPathStatus
    let title: String
    let reason: String
    let primaryActionLabel: String
    let primaryActionSystemImage: String
    let primaryAction: WorkspaceMainStageAction
    let evidence: [String]
    let nextStageAllowed: Bool

    var evidenceSummary: String {
        evidence.isEmpty ? "No evidence yet" : evidence.joined(separator: " · ")
    }
}

struct DemandIntakeReadinessCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
}

struct DemandIntakeReadinessEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let evidence: [String]
    let checks: [DemandIntakeReadinessCheck]
    let unresolvedP0Count: Int
    let requirementHasContent: Bool
    let scopeFrozen: Bool
    let requirementTasksReady: Bool

    var ready: Bool {
        status == .ready
    }

    var blockerChecks: [DemandIntakeReadinessCheck] {
        checks.filter { $0.status == .blocked || $0.status == .review }
    }

    static func resolve(status: DemandIntakeStatus, workspace: WorkspaceSummary) -> DemandIntakeReadinessEvidence {
        if !status.exists {
            return DemandIntakeReadinessEvidence(
                status: .blocked,
                reason: "当前工作区还没有 需求/ 目录。先初始化需求预检，再整理蓝湖材料和补充说明。",
                evidence: ["需求/"],
                checks: [
                    DemandIntakeReadinessCheck(
                        id: "directory",
                        label: "需求目录 / Demand folder",
                        detail: "固定目录 需求/ 尚未创建。",
                        status: .blocked,
                        systemImage: "folder.badge.plus",
                        path: status.directoryPath
                    )
                ],
                unresolvedP0Count: 0,
                requirementHasContent: false,
                scopeFrozen: false,
                requirementTasksReady: false
            )
        }

        if !status.ready {
            let missingFiles = status.files.filter { !$0.exists }
            return DemandIntakeReadinessEvidence(
                status: .review,
                reason: "需求目录已存在，但仍缺 \(status.missingCount) 个固定文件。先补齐 requirement、questions、scope、tasks 和 delivery。",
                evidence: status.files.map { "需求/\($0.filename)" },
                checks: missingFiles.map { file in
                    DemandIntakeReadinessCheck(
                        id: "missing-\(file.key)",
                        label: file.label,
                        detail: "\(file.filename) 尚未创建。",
                        status: .blocked,
                        systemImage: "doc.badge.plus",
                        path: file.path
                    )
                },
                unresolvedP0Count: 0,
                requirementHasContent: false,
                scopeFrozen: false,
                requirementTasksReady: false
            )
        }

        let requirementFile = status.files.first { $0.key == "requirement" }
        let questionsFile = status.files.first { $0.key == "questions" }
        let scopeFile = status.files.first { $0.key == "scope" }
        let tasksFile = status.files.first { $0.key == "tasks" }
        let requirement = readText(at: requirementFile?.path)
        let questions = readText(at: questionsFile?.path)
        let scope = readText(at: scopeFile?.path)
        let tasks = readText(at: tasksFile?.path)

        let requirementHasContent = hasMeaningfulRequirementContent(requirement)
        let unresolvedP0Count = unresolvedP0Items(in: questions).count
        let scopeFrozen = isScopeFrozen(scope)
        let requirementTasksReady = hasRequirementTaskItems(tasks)

        let checks = [
            DemandIntakeReadinessCheck(
                id: "requirement-content",
                label: "需求内容 / Requirement",
                detail: requirementHasContent ? "requirement.md 已包含非占位需求内容。" : "requirement.md 仍像骨架模板，请先补充真实需求目标、流程和验收标准。",
                status: requirementHasContent ? .ready : .blocked,
                systemImage: requirementHasContent ? "doc.text.magnifyingglass" : "doc.badge.ellipsis",
                path: requirementFile?.path
            ),
            DemandIntakeReadinessCheck(
                id: "p0-questions",
                label: "P0 问题 / P0",
                detail: unresolvedP0Count == 0 ? "questions.md 中没有发现未解决 P0 阻塞项。" : "questions.md 中仍有 \(unresolvedP0Count) 个未解决 P0 项。",
                status: unresolvedP0Count == 0 ? .ready : .blocked,
                systemImage: unresolvedP0Count == 0 ? "checkmark.circle" : "exclamationmark.triangle",
                path: questionsFile?.path
            ),
            DemandIntakeReadinessCheck(
                id: "scope-freeze",
                label: "范围冻结 / Scope",
                detail: scopeFrozen ? "scope.md 已标记本次开发范围冻结。" : "scope.md 尚未冻结；需求预检完成后会进入独立的范围冻结阶段。",
                status: scopeFrozen ? .ready : .pending,
                systemImage: scopeFrozen ? "scope" : "scope",
                path: scopeFile?.path
            ),
            DemandIntakeReadinessCheck(
                id: "requirement-tasks",
                label: "需求列表 / Tasks",
                detail: requirementTasksReady ? "需求/tasks.md 已包含非模板需求点，可作为执行任务来源。" : "需求/tasks.md 仍只有预检模板任务，请先拆出真实需求点。",
                status: requirementTasksReady ? .ready : .review,
                systemImage: "checklist",
                path: tasksFile?.path
            )
        ]

        let blockingChecks = checks.filter { $0.status == .blocked }
        let reviewChecks = checks.filter { $0.status == .review }
        let resolvedStatus: WorkflowPathStatus
        let reason: String
        if blockingChecks.isEmpty && reviewChecks.isEmpty {
            resolvedStatus = .ready
            reason = scopeFrozen
                ? "需求预检内容已就绪，可以继续服务分支确认。"
                : "需求预检内容已就绪，下一步进入范围冻结。"
        } else if !blockingChecks.isEmpty {
            resolvedStatus = .blocked
            reason = blockingChecks.map(\.detail).joined(separator: " ")
        } else {
            resolvedStatus = .review
            reason = reviewChecks.map(\.detail).joined(separator: " ")
        }

        return DemandIntakeReadinessEvidence(
            status: resolvedStatus,
            reason: reason,
            evidence: status.files.map { "需求/\($0.filename)" },
            checks: checks,
            unresolvedP0Count: unresolvedP0Count,
            requirementHasContent: requirementHasContent,
            scopeFrozen: scopeFrozen,
            requirementTasksReady: requirementTasksReady
        )
    }

    private static func readText(at path: String?) -> String {
        guard let path else { return "" }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private static func hasMeaningfulRequirementContent(_ text: String) -> Bool {
        meaningfulLines(in: text).count >= 3
    }

    private static func unresolvedP0Items(in text: String) -> [String] {
        var inP0Section = false
        var items: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            if line.hasPrefix("##") {
                inP0Section = lowercased.contains("p0")
                continue
            }
            guard inP0Section || lowercased.contains("p0") else { continue }
            guard looksLikeOpenQuestion(line) else { continue }
            items.append(line)
        }

        return items
    }

    private static func looksLikeOpenQuestion(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        guard !line.isEmpty, !line.hasPrefix("| ---") else { return false }
        if lowercased.contains("清零前") || lowercased.contains("结论") {
            return false
        }
        let resolvedMarkers = ["[x]", "已解决", "已确认", "无", "暂无", "none", "resolved", "closed", "done"]
        if resolvedMarkers.contains(where: { lowercased.contains($0) }) {
            return false
        }
        return line.hasPrefix("-")
            || line.hasPrefix("*")
            || line.hasPrefix("|")
            || lowercased.contains("p0")
    }

    private static func isScopeFrozen(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            if lowercased.contains("[ ]") && line.contains("冻结") {
                return false
            }
            if lowercased.contains("[x]") && line.contains("冻结") {
                return true
            }
            if line.contains("范围已冻结") || line.contains("已冻结本次开发范围") {
                return true
            }
            if line.contains("冻结状态") && line.contains("已冻结") {
                return true
            }
            return lowercased.contains("scope frozen")
        }
    }

    private static func hasRequirementTaskItems(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("|") else { return false }
            guard !line.contains("---") else { return false }
            let templateRows = ["整理 requirement.md", "整理 questions.md", "冻结 scope.md", "需求点"]
            guard !templateRows.contains(where: { line.contains($0) }) else { return false }
            return !placeholderOnly(line)
        }
    }

    private static func meaningfulLines(in text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            guard !line.hasPrefix("#"), !line.hasPrefix("| ---"), !line.hasPrefix(">") else { return nil }
            guard !placeholderOnly(line) else { return nil }
            return line
        }
    }

    private static func placeholderOnly(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let placeholders = [
            "待整理",
            "待确认",
            "待补充",
            "暂无",
            "todo",
            "tbd",
            "placeholder"
        ]
        return placeholders.contains { lowercased.contains($0) }
    }
}

struct ScopeFreezeCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
}

struct ScopeFreezeEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let evidence: [String]
    let checks: [ScopeFreezeCheck]
    let scopePath: String
    let hasInScope: Bool
    let hasOutOfScope: Bool
    let scopeFrozen: Bool
    let unresolvedP0Count: Int

    var ready: Bool {
        status == .ready
    }

    static func resolve(status: DemandIntakeStatus, workspace: WorkspaceSummary) -> ScopeFreezeEvidence {
        let scopePath = status.files.first { $0.key == "scope" }?.path
            ?? "\(workspace.path)/需求/scope.md"
        let text = readText(at: scopePath)

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ScopeFreezeEvidence(
                status: .blocked,
                reason: "尚未读取到 需求/scope.md。先打开范围文档，确认本次做什么、不做什么和待确认项。",
                evidence: ["需求/scope.md"],
                checks: [
                    ScopeFreezeCheck(
                        id: "scope-file",
                        label: "范围文档 / Scope file",
                        detail: "scope.md 为空或不可读。",
                        status: .blocked,
                        systemImage: "doc.badge.ellipsis",
                        path: scopePath
                    )
                ],
                scopePath: scopePath,
                hasInScope: false,
                hasOutOfScope: false,
                scopeFrozen: false,
                unresolvedP0Count: 0
            )
        }

        let hasInScope = hasSectionContent(
            in: text,
            headingMarkers: ["已确认并实现", "本次实现", "本次做", "in scope", "included"]
        )
        let hasOutOfScope = hasSectionContent(
            in: text,
            headingMarkers: ["暂不实现", "不做", "out of scope", "excluded"]
        )
        let pendingP0Items = unresolvedPendingP0Items(in: text)
        let scopeFrozen = isScopeFrozen(text)

        let checks = [
            ScopeFreezeCheck(
                id: "in-scope",
                label: "本次实现 / In scope",
                detail: hasInScope ? "scope.md 已写明本次确认实现的范围。" : "scope.md 缺少非占位的“已确认并实现 / 本次做”内容。",
                status: hasInScope ? .ready : .review,
                systemImage: "checklist",
                path: scopePath
            ),
            ScopeFreezeCheck(
                id: "out-of-scope",
                label: "暂不实现 / Out",
                detail: hasOutOfScope ? "scope.md 已写明暂不实现或排除范围。" : "scope.md 缺少非占位的“暂不实现 / 不做”内容。",
                status: hasOutOfScope ? .ready : .review,
                systemImage: "minus.circle",
                path: scopePath
            ),
            ScopeFreezeCheck(
                id: "pending-p0",
                label: "待确认 P0 / Pending P0",
                detail: pendingP0Items.isEmpty ? "未发现仍开放的 P0 范围项。" : "仍有 \(pendingP0Items.count) 个 P0 范围项未解决或未显式延期。",
                status: pendingP0Items.isEmpty ? .ready : .blocked,
                systemImage: pendingP0Items.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                path: scopePath
            ),
            ScopeFreezeCheck(
                id: "freeze-marker",
                label: "冻结标记 / Freeze",
                detail: scopeFrozen ? "scope.md 已勾选或声明本次开发范围已冻结。" : "scope.md 尚未显式冻结；请勾选冻结项或写明范围已冻结。",
                status: scopeFrozen ? .ready : .blocked,
                systemImage: "scope",
                path: scopePath
            )
        ]

        let blockers = checks.filter { $0.status == .blocked }
        let reviews = checks.filter { $0.status == .review }
        let resolvedStatus: WorkflowPathStatus
        let reason: String
        if !blockers.isEmpty {
            resolvedStatus = .blocked
            reason = blockers.map(\.detail).joined(separator: " ")
        } else if !reviews.isEmpty {
            resolvedStatus = .review
            reason = reviews.map(\.detail).joined(separator: " ")
        } else {
            resolvedStatus = .ready
            reason = "scope.md 已写明本次做什么、不做什么，并且没有开放 P0 范围项，可以进入服务和分支确认。"
        }

        return ScopeFreezeEvidence(
            status: resolvedStatus,
            reason: reason,
            evidence: ["需求/scope.md"],
            checks: checks,
            scopePath: scopePath,
            hasInScope: hasInScope,
            hasOutOfScope: hasOutOfScope,
            scopeFrozen: scopeFrozen,
            unresolvedP0Count: pendingP0Items.count
        )
    }

    private static func readText(at path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private static func hasSectionContent(in text: String, headingMarkers: [String]) -> Bool {
        let lines = sectionLines(in: text, headingMarkers: headingMarkers)
        return lines.contains { line in
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !cleaned.hasPrefix("| ---") else { return false }
            return !placeholderOnly(cleaned)
        }
    }

    private static func unresolvedPendingP0Items(in text: String) -> [String] {
        sectionLines(in: text, headingMarkers: ["仍待确认", "待确认", "待定", "pending"])
            .filter { line in
                let lowercased = line.lowercased()
                guard lowercased.contains("p0") else { return false }
                guard !placeholderOnly(line) else { return false }
                let resolvedMarkers = ["[x]", "已解决", "已确认", "无", "暂无", "none", "resolved", "closed", "done", "延期", "deferred", "非阻塞", "accepted"]
                return !resolvedMarkers.contains { lowercased.contains($0) }
            }
    }

    private static func sectionLines(in text: String, headingMarkers: [String]) -> [String] {
        var isInsideTargetSection = false
        var lines: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            if line.hasPrefix("#") {
                isInsideTargetSection = headingMarkers.contains { marker in
                    lowercased.contains(marker.lowercased())
                }
                continue
            }
            if isInsideTargetSection {
                lines.append(line)
            }
        }

        return lines
    }

    private static func isScopeFrozen(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            if lowercased.contains("[ ]") && line.contains("冻结") {
                return false
            }
            if lowercased.contains("[x]") && line.contains("冻结") {
                return true
            }
            if line.contains("范围已冻结") || line.contains("已冻结本次开发范围") {
                return true
            }
            if line.contains("冻结状态") && line.contains("已冻结") {
                return true
            }
            return lowercased.contains("scope frozen")
        }
    }

    private static func placeholderOnly(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let placeholders = [
            "待整理",
            "待确认",
            "待补充",
            "暂无",
            "todo",
            "tbd",
            "placeholder"
        ]
        return placeholders.contains { lowercased.contains($0) }
    }
}

struct ServiceBranchCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
}

struct ServiceBranchEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let evidence: [String]
    let checks: [ServiceBranchCheck]
    let servicesPath: String
    let branchesPath: String
    let branchConfirmed: Bool
    let servicesConfirmed: Bool
    let branchPolicyRecorded: Bool
    let missingSourceServices: [String]

    var ready: Bool {
        status == .ready
    }

    var title: String {
        if !branchConfirmed {
            return "确认目标分支 / Confirm branch"
        }
        if !servicesConfirmed {
            return "确认服务范围 / Confirm services"
        }
        if !missingSourceServices.isEmpty {
            return "修正源仓库 / Source repos"
        }
        if !branchPolicyRecorded {
            return "记录分支策略 / Branch policy"
        }
        return "服务分支已确认 / Service & branch ready"
    }

    var primaryActionLabel: String {
        if !branchConfirmed || !branchPolicyRecorded {
            return "打开分支"
        }
        return "打开服务"
    }

    var primaryActionSystemImage: String {
        if !branchConfirmed || !branchPolicyRecorded {
            return "arrow.triangle.branch"
        }
        return "square.stack.3d.up"
    }

    var primaryAction: WorkspaceMainStageAction {
        if !branchConfirmed || !branchPolicyRecorded {
            return .document("branches")
        }
        return .document("services")
    }

    static func resolve(workspace: WorkspaceSummary) -> ServiceBranchEvidence {
        let servicesPath = workspace.documentLinks["services"] ?? "\(workspace.path)/services.md"
        let branchesPath = workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md"
        let servicesText = readText(at: servicesPath)
        let branchesText = readText(at: branchesPath)
        let branchesDocumentExists = FileManager.default.fileExists(atPath: branchesPath)

        let branchConfirmed = hasConfirmedTargetBranch(workspace.branch)
        let servicesConfirmed = !workspace.services.isEmpty || serviceScopeExplicitlyEmpty(servicesText)
        let missingSourceServices = workspace.services
            .filter { !$0.sourceExists }
            .map(\.name)
        let branchPolicyRecorded = branchConfirmed
            && (!branchesDocumentExists || hasBranchPolicy(in: branchesText, branch: workspace.branch))

        let checks = [
            ServiceBranchCheck(
                id: "target-branch",
                label: "目标分支 / Branch",
                detail: branchConfirmed ? "目标分支已确认：\(workspace.branch)。" : "目标分支仍是占位或为空，请补齐 branches.md 或 workspace.md。",
                status: branchConfirmed ? .ready : .blocked,
                systemImage: "arrow.triangle.branch",
                path: branchesPath
            ),
            ServiceBranchCheck(
                id: "service-scope",
                label: "服务范围 / Services",
                detail: servicesConfirmed
                    ? serviceScopeDetail(workspace: workspace)
                    : "服务范围为空且未写明本需求无代码服务；先确认涉及服务或明确无需服务 worktree。",
                status: servicesConfirmed ? .ready : .blocked,
                systemImage: "square.stack.3d.up",
                path: servicesPath
            ),
            ServiceBranchCheck(
                id: "source-repos",
                label: "源仓库 / Sources",
                detail: missingSourceServices.isEmpty
                    ? "已确认服务都有可用 source repo 记录。"
                    : "这些服务的 source repo 不可用：\(missingSourceServices.joined(separator: ", "))。",
                status: missingSourceServices.isEmpty ? .ready : .blocked,
                systemImage: missingSourceServices.isEmpty ? "externaldrive" : "externaldrive.badge.xmark",
                path: servicesPath
            ),
            ServiceBranchCheck(
                id: "branch-policy",
                label: "分支策略 / Policy",
                detail: branchPolicyRecorded
                    ? "分支策略已记录或已从工作区扫描结果继承。"
                    : "branches.md 尚未记录目标分支、基线或分支创建/沿用策略。",
                status: branchPolicyRecorded ? .ready : .review,
                systemImage: "point.3.connected.trianglepath.dotted",
                path: branchesPath
            )
        ]

        let blockers = checks.filter { $0.status == .blocked }
        let reviews = checks.filter { $0.status == .review }
        let resolvedStatus: WorkflowPathStatus
        let reason: String
        if !blockers.isEmpty {
            resolvedStatus = .blocked
            reason = blockers.map(\.detail).joined(separator: " ")
        } else if !reviews.isEmpty {
            resolvedStatus = .review
            reason = reviews.map(\.detail).joined(separator: " ")
        } else {
            resolvedStatus = .ready
            reason = "服务范围、目标分支、source repo 和分支策略已具备，可以进入 worktree 准备。"
        }

        return ServiceBranchEvidence(
            status: resolvedStatus,
            reason: reason,
            evidence: ["services.md", "branches.md", "source-repos/"],
            checks: checks,
            servicesPath: servicesPath,
            branchesPath: branchesPath,
            branchConfirmed: branchConfirmed,
            servicesConfirmed: servicesConfirmed,
            branchPolicyRecorded: branchPolicyRecorded,
            missingSourceServices: missingSourceServices
        )
    }

    private static func readText(at path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private static func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("未确认")
            && !normalized.contains("pending")
            && !normalized.contains("tbd")
            && !normalized.contains("todo")
    }

    private static func hasBranchPolicy(in text: String, branch: String) -> Bool {
        let normalizedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let meaningfulLines = text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { line in
            !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix("| ---") && !placeholderOnly(line)
        }

        return meaningfulLines.contains { line in
            let lowercased = line.lowercased()
            if !normalizedBranch.isEmpty && lowercased.contains(normalizedBranch) {
                return true
            }
            let markers = ["目标分支", "分支策略", "基线", "统一分支", "新建分支", "沿用分支", "branch", "baseline"]
            return markers.contains { lowercased.contains($0.lowercased()) }
        }
    }

    private static func serviceScopeExplicitlyEmpty(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let markers = ["无需服务", "无代码服务", "不涉及服务", "仅文档", "no service", "docs only", "documentation only"]
        return markers.contains { normalized.contains($0) }
    }

    private static func serviceScopeDetail(workspace: WorkspaceSummary) -> String {
        if workspace.services.isEmpty {
            return "services.md 已声明本需求无需代码服务。"
        }
        return "已确认 \(workspace.services.count) 个服务：\(workspace.services.map(\.name).joined(separator: ", "))。"
    }

    private static func placeholderOnly(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let placeholders = [
            "待整理",
            "待确认",
            "待补充",
            "暂无",
            "todo",
            "tbd",
            "placeholder"
        ]
        return placeholders.contains { lowercased.contains($0) }
    }
}

struct WorktreeSetupCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
}

struct WorktreeSetupEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let evidence: [String]
    let checks: [WorktreeSetupCheck]
    let setupScriptPath: String
    let missingServices: [String]
    let branchMismatchServices: [String]
    let missingSourceServices: [String]
    let branchConfirmed: Bool
    let setupScriptExists: Bool

    var ready: Bool {
        status == .ready
    }

    var hasMissingWorktrees: Bool {
        !missingServices.isEmpty
    }

    var title: String {
        if !branchConfirmed {
            return "确认目标分支 / Confirm branch"
        }
        if !missingSourceServices.isEmpty {
            return "修正源仓库 / Source repos"
        }
        if !branchMismatchServices.isEmpty {
            return "修正 worktree 分支 / Branch mismatch"
        }
        if !missingServices.isEmpty {
            return "准备隔离 worktree / Setup worktrees"
        }
        return "Worktree 已就绪 / Worktrees ready"
    }

    var primaryActionLabel: String {
        if !branchConfirmed {
            return "打开分支"
        }
        if !missingSourceServices.isEmpty {
            return "打开服务"
        }
        if !branchMismatchServices.isEmpty {
            return "打开服务"
        }
        if !missingServices.isEmpty {
            return "创建 worktree"
        }
        return setupScriptExists ? "打开脚本" : "打开服务"
    }

    var primaryActionSystemImage: String {
        if !branchConfirmed || !branchMismatchServices.isEmpty {
            return "arrow.triangle.branch"
        }
        if !missingSourceServices.isEmpty {
            return "square.stack.3d.up"
        }
        if !missingServices.isEmpty {
            return "wrench.and.screwdriver"
        }
        return setupScriptExists ? "terminal" : "checkmark.seal"
    }

    var primaryAction: WorkspaceMainStageAction {
        if !branchConfirmed || !branchMismatchServices.isEmpty {
            return .document("branches")
        }
        if !missingSourceServices.isEmpty {
            return .document("services")
        }
        if !missingServices.isEmpty {
            return .worktree
        }
        return setupScriptExists ? .document("worktreeScript") : .document("services")
    }

    static func resolve(workspace: WorkspaceSummary) -> WorktreeSetupEvidence {
        let setupScriptPath = workspace.documentLinks["worktreeScript"]
            ?? "\(workspace.path)/scripts/worktree-commands.sh"
        let setupScriptExists = FileManager.default.fileExists(atPath: setupScriptPath)
        let branchConfirmed = hasConfirmedTargetBranch(workspace.branch)
        let missingServices = workspace.services
            .filter { !$0.worktreeExists }
            .map(\.name)
        let missingSourceServices = workspace.services
            .filter { !$0.sourceExists }
            .map(\.name)
        let branchMismatchServices: [String] = branchConfirmed
            ? workspace.services.compactMap { service in
                guard service.worktreeExists, !branchMatches(service.branch, target: workspace.branch) else {
                    return nil
                }
                return "\(service.name)(\(service.branch))"
            }
            : []

        let checks = [
            WorktreeSetupCheck(
                id: "target-branch",
                label: "目标分支 / Branch",
                detail: branchConfirmed ? "目标分支已确认：\(workspace.branch)。" : "目标分支仍未确认，不能创建 workspace-local worktree。",
                status: branchConfirmed ? .ready : .blocked,
                systemImage: "arrow.triangle.branch",
                path: workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md"
            ),
            WorktreeSetupCheck(
                id: "source-repos",
                label: "源仓库 / Sources",
                detail: missingSourceServices.isEmpty
                    ? "已确认服务都有可用 source repo。"
                    : "这些服务的 source repo 不可用：\(missingSourceServices.joined(separator: ", "))。",
                status: missingSourceServices.isEmpty ? .ready : .blocked,
                systemImage: missingSourceServices.isEmpty ? "externaldrive" : "externaldrive.badge.xmark",
                path: workspace.documentLinks["services"] ?? "\(workspace.path)/services.md"
            ),
            WorktreeSetupCheck(
                id: "workspace-worktrees",
                label: "工作区 worktree / Worktrees",
                detail: missingServices.isEmpty
                    ? worktreeReadyDetail(workspace: workspace)
                    : "缺失 \(missingServices.count) 个 workspace-local worktree：\(missingServices.joined(separator: ", "))。",
                status: missingServices.isEmpty ? .ready : .next,
                systemImage: missingServices.isEmpty ? "checkmark.circle" : "wrench.and.screwdriver",
                path: setupScriptPath
            ),
            WorktreeSetupCheck(
                id: "branch-alignment",
                label: "分支一致 / Alignment",
                detail: branchMismatchServices.isEmpty
                    ? "已存在的 worktree 与目标分支一致，或尚待创建。"
                    : "这些 worktree 不在目标分支：\(branchMismatchServices.joined(separator: ", "))。",
                status: branchMismatchServices.isEmpty ? .ready : .blocked,
                systemImage: branchMismatchServices.isEmpty ? "checkmark.circle" : "arrow.triangle.branch",
                path: workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md"
            ),
            WorktreeSetupCheck(
                id: "setup-script",
                label: "创建脚本 / Commands",
                detail: setupScriptExists
                    ? "scripts/worktree-commands.sh 可用于复核预期命令；确认 sheet 也会列出执行计划。"
                    : "暂未找到 scripts/worktree-commands.sh；确认 sheet 仍会展示将执行的 worktree 计划。",
                status: setupScriptExists || missingServices.isEmpty ? .ready : .review,
                systemImage: setupScriptExists ? "terminal" : "doc.badge.ellipsis",
                path: setupScriptPath
            )
        ]

        let blockers = checks.filter { $0.status == .blocked }
        let reviews = checks.filter { $0.status == .review }
        let resolvedStatus: WorkflowPathStatus
        let reason: String
        if !blockers.isEmpty {
            resolvedStatus = .blocked
            reason = blockers.map(\.detail).joined(separator: " ")
        } else if !missingServices.isEmpty {
            resolvedStatus = .next
            reason = "\(missingServices.count) 个服务还没有 workspace-local worktree：\(missingServices.joined(separator: ", "))。先在确认 sheet 复核命令，再执行创建。"
        } else if !reviews.isEmpty {
            resolvedStatus = .review
            reason = reviews.map(\.detail).joined(separator: " ")
        } else {
            resolvedStatus = .ready
            reason = "确认服务均已有 workspace-local worktree，且已存在 worktree 的分支与目标分支一致。"
        }

        return WorktreeSetupEvidence(
            status: resolvedStatus,
            reason: reason,
            evidence: ["repos/<service>", "source-repos/", "scripts/worktree-commands.sh"],
            checks: checks,
            setupScriptPath: setupScriptPath,
            missingServices: missingServices,
            branchMismatchServices: branchMismatchServices,
            missingSourceServices: missingSourceServices,
            branchConfirmed: branchConfirmed,
            setupScriptExists: setupScriptExists
        )
    }

    private static func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("未确认")
            && !normalized.contains("pending")
            && !normalized.contains("tbd")
            && !normalized.contains("todo")
    }

    private static func branchMatches(_ branch: String, target: String) -> Bool {
        let normalizedBranch = normalizeBranch(branch)
        let normalizedTarget = normalizeBranch(target)
        guard !normalizedBranch.isEmpty, !normalizedTarget.isEmpty else {
            return true
        }
        guard !normalizedBranch.contains("missing"),
              !normalizedBranch.contains("待确认"),
              !normalizedBranch.contains("pending") else {
            return true
        }
        return normalizedBranch == normalizedTarget
            || normalizedBranch.hasSuffix("/\(normalizedTarget)")
    }

    private static func normalizeBranch(_ branch: String) -> String {
        branch
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "origin/", with: "")
    }

    private static func worktreeReadyDetail(workspace: WorkspaceSummary) -> String {
        if workspace.services.isEmpty {
            return "当前工作区没有需要创建的服务 worktree。"
        }
        return "\(workspace.services.count) 个服务均已有 workspace-local worktree。"
    }
}

struct DevelopmentTaskCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
    let taskID: String?
}

struct DevelopmentTaskEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let evidence: [String]
    let checks: [DevelopmentTaskCheck]
    let tasksPath: String
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
        let activeTasks = workspace.tasks
            .filter(\.isActive)
            .sorted(by: taskSort)
        let blockedTasks = activeTasks
            .filter(\.isBlocked)
            .sorted(by: taskSort)
        let deferredCount = workspace.tasks.filter(\.isDeferred).count
        let doneCount = workspace.tasks.filter(\.isDone).count
        let nextTask = blockedTasks.first ?? activeTasks.first

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
            evidence: taskEvidence(nextTask: nextTask),
            checks: checks,
            tasksPath: tasksPath,
            activeTasks: activeTasks,
            blockedTasks: blockedTasks,
            deferredTaskCount: deferredCount,
            doneTaskCount: doneCount,
            nextTask: nextTask
        )
    }

    private static func taskEvidence(nextTask: WorkspaceTask?) -> [String] {
        var evidence = ["tasks.md", "需求/tasks.md"]
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
        !transferableItems.isEmpty
    }

    var summary: String {
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
        status: DemandIntakeStatus
    ) -> DemandTaskTransferPlan {
        let intakeTasksPath = status.files.first { $0.key == "tasks" }?.path
            ?? "\(workspace.path)/需求/tasks.md"
        let executionTasksPath = workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md"
        let intakeText = readText(at: intakeTasksPath)
        let executionText = readText(at: executionTasksPath)
        let candidates = demandTaskCandidates(in: intakeText)
        let existingTitles = Set(
            workspace.tasks.map { DemandTaskTransferItem.normalizeTitle($0.title) }
                + rootTaskTitles(in: executionText)
        )

        return DemandTaskTransferPlan(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            intakeTasksPath: intakeTasksPath,
            executionTasksPath: executionTasksPath,
            candidates: candidates,
            existingTitles: existingTitles
        )
    }

    private static func readText(at path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
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

    private static func rootTaskTitles(in text: String) -> [String] {
        tableRowsWithLineNumbers(in: text).compactMap { _, cells in
            guard let title = cells.first?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !title.isEmpty,
                  !title.elementsEqual("任务") else {
                return nil
            }
            return DemandTaskTransferItem.normalizeTitle(title)
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

enum AgentActionSurfaceKind: String, Hashable {
    case approval
    case answer
    case toolReview

    var statusLabel: String {
        switch self {
        case .approval:
            "需确认 / approval"
        case .answer:
            "待回复 / answer"
        case .toolReview:
            "需复核 / review"
        }
    }

    var systemImage: String {
        switch self {
        case .approval:
            "hand.raised"
        case .answer:
            "text.bubble"
        case .toolReview:
            "terminal"
        }
    }
}

struct AgentActionResponse: Hashable, Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let payload: String
}

struct AgentActionSurface: Hashable {
    let kind: AgentActionSurfaceKind
    let title: String
    let detail: String
    let safetyNote: String
    let primaryResponse: AgentActionResponse
    let secondaryResponse: AgentActionResponse?

    init?(event: AgentEvent) {
        let normalizedKind = event.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let category = event.fallbackTaskDraft.category
        let command = Self.firstMetadataValue(
            in: event,
            matching: ["command", "cmd", "operation", "tool", "toolName"]
        )
        let target = event.workspaceFolder ?? event.metadata["workspaceFolder"] ?? event.metadata["workspace"] ?? "No workspace"

        switch category {
        case "approval":
            kind = .approval
            title = "审批请求 / Approval request"
            detail = command.map { "Agent 请求执行或继续：\($0)" }
                ?? "Agent 请求一个需要人工确认的操作。"
            safetyNote = "Nexus 只复制可审查回应，不会执行 metadata 中的命令，也不会替你授权。"
            primaryResponse = AgentActionResponse(
                id: "approval-approve",
                label: "复制批准回应 / Copy approve",
                systemImage: "checkmark.circle",
                payload: Self.responsePayload(
                    heading: "Nexus approval response",
                    event: event,
                    target: target,
                    decision: "Approved by user",
                    body: [
                        "Scope: only the operation described by this event.",
                        "Safety: do not run additional commands or broaden permissions without another explicit user confirmation.",
                        "Command: \(command ?? "not provided")"
                    ]
                )
            )
            secondaryResponse = AgentActionResponse(
                id: "approval-deny",
                label: "复制拒绝回应 / Copy deny",
                systemImage: "xmark.circle",
                payload: Self.responsePayload(
                    heading: "Nexus approval response",
                    event: event,
                    target: target,
                    decision: "Not approved",
                    body: [
                        "Do not execute the requested operation.",
                        "Explain the safer alternative or ask for a narrower request.",
                        "Command: \(command ?? "not provided")"
                    ]
                )
            )
        case "answer":
            kind = .answer
            title = "Agent 提问 / Question"
            detail = "把答复模板复制给当前 Agent，补充答案后再继续。"
            safetyNote = "模板会带上事件上下文，但答案仍需要你确认后再发送。"
            primaryResponse = AgentActionResponse(
                id: "answer-template",
                label: "复制答复模板 / Copy answer",
                systemImage: "text.bubble",
                payload: Self.responsePayload(
                    heading: "Nexus answer response",
                    event: event,
                    target: target,
                    decision: "Answer from user",
                    body: [
                        "Answer: <fill in the answer before sending>",
                        "Continue only after applying this answer to the current workspace context.",
                        "Question summary: \(event.summary)"
                    ]
                )
            )
            secondaryResponse = AgentActionResponse(
                id: "answer-more-context",
                label: "复制补充上下文请求 / Ask context",
                systemImage: "questionmark.circle",
                payload: Self.responsePayload(
                    heading: "Nexus answer response",
                    event: event,
                    target: target,
                    decision: "Need more context",
                    body: [
                        "Please clarify the missing information before making code, file, git, SQL, or delivery-document changes.",
                        "Keep the current workspace unchanged until the question is resolved."
                    ]
                )
            )
        case "tool-review" where normalizedKind == "tool_use" || normalizedKind == "tool-use" || normalizedKind == "tool":
            kind = .toolReview
            title = "工具调用复核 / Tool review"
            detail = command.map { "待复核工具或命令：\($0)" }
                ?? "Agent 记录了一个需要复核的工具调用。"
            safetyNote = "这里只给出复核结论模板；本地命令仍必须通过明确确认流程执行。"
            primaryResponse = AgentActionResponse(
                id: "tool-review-note",
                label: "复制复核结论 / Copy review",
                systemImage: "doc.on.clipboard",
                payload: Self.responsePayload(
                    heading: "Nexus tool review response",
                    event: event,
                    target: target,
                    decision: "Reviewed in Nexus",
                    body: [
                        "Result: <safe / needs changes / blocked>",
                        "Reason: <write the review reason before sending>",
                        "Tool or command: \(command ?? "not provided")"
                    ]
                )
            )
            secondaryResponse = nil
        default:
            return nil
        }
    }

    private static func firstMetadataValue(in event: AgentEvent, matching keys: [String]) -> String? {
        let normalizedKeys = keys.map { $0.lowercased() }
        return event.metadata
            .sorted { $0.key < $1.key }
            .first { item in
                let normalizedKey = item.key.lowercased()
                return !item.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && normalizedKeys.contains(where: { normalizedKey.contains($0) })
            }?
            .value
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func responsePayload(
        heading: String,
        event: AgentEvent,
        target: String,
        decision: String,
        body: [String]
    ) -> String {
        let bodyLines = body.map { "- \($0)" }.joined(separator: "\n")
        return """
        \(heading)

        Decision:
        - \(decision)

        Event:
        - Title: \(event.title)
        - Kind: \(event.kind)
        - Severity: \(event.severity)
        - Source: \(event.source)
        - Session: \(event.sessionId)
        - Workspace: \(target)
        - Event ID: \(event.id)

        Response:
        \(bodyLines)
        """
    }
}

struct AgentInboxSummary {
    let actionRequired: [AgentEvent]
    let recent: [AgentEvent]
    let totalCount: Int

    init(events: [AgentEvent]) {
        totalCount = events.count
        actionRequired = events.filter(Self.requiresAction)
        let actionIDs = Set(actionRequired.map(\.id))
        recent = events.filter { !actionIDs.contains($0.id) }
    }

    var isEmpty: Bool {
        totalCount == 0
    }

    var pendingLabel: String {
        actionRequired.isEmpty ? "0 pending" : "\(actionRequired.count) pending"
    }

    static func requiresAction(_ event: AgentEvent) -> Bool {
        if AgentActionSurface(event: event) != nil {
            return true
        }

        return event.severity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "error"
    }
}

struct AgentWorkflowSummary: Hashable {
    let pendingEventCount: Int
    let recentEventCount: Int
    let agentTaskCount: Int
    let openTaskCount: Int

    init(inbox: AgentInboxSummary, agentTaskCount: Int, openTaskCount: Int) {
        pendingEventCount = inbox.actionRequired.count
        recentEventCount = inbox.recent.count
        self.agentTaskCount = agentTaskCount
        self.openTaskCount = openTaskCount
    }

    var shouldShow: Bool {
        pendingEventCount > 0 || agentTaskCount > 0
    }

    var title: String {
        if pendingEventCount > 0 && agentTaskCount > 0 {
            return "事件与任务待跟进 / Active flow"
        }
        if pendingEventCount > 0 {
            return "先处理 Agent 事件 / Review inbox"
        }
        return "Agent 任务待跟进 / Agent tasks"
    }

    var detail: String {
        if pendingEventCount > 0 && agentTaskCount > 0 {
            return "先处理审批、问题或工具复核；已写入 tasks.md 的 Agent 任务从任务中心继续。"
        }
        if pendingEventCount > 0 {
            return "打开 Inbox 中的事件，复制回应模板或确认写入任务草稿。"
        }
        return "这些任务来自 Agent 事件，继续从 Task Center 处理、定位或交接 Codex。"
    }

    var metricLabel: String {
        "\(pendingEventCount) inbox / \(agentTaskCount) tasks"
    }
}

enum AutomationNotificationMinimumStatus: String, CaseIterable, Identifiable {
    case review = "review"
    case attention = "attention"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .review:
            "Review+"
        case .attention:
            "Attention"
        }
    }

    var detail: String {
        switch self {
        case .review:
            "提醒 review 和 attention 状态"
        case .attention:
            "只提醒最高优先级状态"
        }
    }

    func allows(_ status: String) -> Bool {
        let normalized = status.lowercased()
        switch self {
        case .review:
            return normalized == "review" || normalized == "attention"
        case .attention:
            return normalized == "attention"
        }
    }
}

enum AutomationNotificationSignalKind: String, CaseIterable, Identifiable {
    case risk = "risk"
    case delivery = "delivery"
    case task = "task"
    case worktree = "worktree"
    case git = "git"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .risk:
            "风险 / Risk"
        case .delivery:
            "交付 / Delivery"
        case .task:
            "任务 / Task"
        case .worktree:
            "Worktree"
        case .git:
            "未提交服务 / Dirty"
        }
    }
}

enum WorkspaceState: String, Hashable {
    case analyzing = "analyzing"
    case developing = "developing"
    case ready = "ready"
    case blocked = "blocked"
    case archived = "archived"

    var label: String {
        switch self {
        case .analyzing:
            "分析中 / Analyzing"
        case .developing:
            "开发中 / Developing"
        case .ready:
            "可交付 / Ready"
        case .blocked:
            "阻塞 / Blocked"
        case .archived:
            "已归档 / Archived"
        }
    }
}

enum RiskLevel: String, Hashable {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low:
            "低风险 / Low"
        case .medium:
            "中风险 / Medium"
        case .high:
            "高风险 / High"
        }
    }

    var symbol: String {
        switch self {
        case .low:
            "checkmark.circle"
        case .medium:
            "exclamationmark.circle"
        case .high:
            "exclamationmark.triangle"
        }
    }
}

struct AgentStatus: Hashable {
    let title: String
    let detail: String
    let connectedTools: [String]
}

struct MenuBarStatusSummary: Hashable {
    let workspaceCount: Int
    let activeWorkspaceCount: Int
    let archivedWorkspaceCount: Int
    let riskyWorkspaceCount: Int
    let blockedWorkspaceCount: Int
    let openTaskCount: Int
    let highPriorityTaskCount: Int
    let agentTaskCount: Int
    let missingWorktreeCount: Int
    let dirtyServiceCount: Int
    let activeWorkspaceName: String?
    let bridgeMode: String

    var menuTitle: String {
        if blockedWorkspaceCount > 0 {
            return "Nexus \(blockedWorkspaceCount)"
        }
        if riskyWorkspaceCount > 0 {
            return "Nexus \(riskyWorkspaceCount)"
        }
        if missingWorktreeCount > 0 {
            return "Nexus \(missingWorktreeCount)"
        }
        if dirtyServiceCount > 0 {
            return "Nexus \(dirtyServiceCount)"
        }
        if highPriorityTaskCount > 0 {
            return "Nexus \(highPriorityTaskCount)"
        }
        return "Nexus"
    }

    var systemImage: String {
        if blockedWorkspaceCount > 0 {
            return "pause.circle.fill"
        }
        if riskyWorkspaceCount > 0 || missingWorktreeCount > 0 || dirtyServiceCount > 0 {
            return "exclamationmark.triangle.fill"
        }
        if openTaskCount > 0 {
            return "checklist"
        }
        return "point.3.connected.trianglepath.dotted"
    }

    var statusLine: String {
        if blockedWorkspaceCount > 0 {
            return "\(blockedWorkspaceCount) blocked workspaces need attention"
        }
        if riskyWorkspaceCount > 0 {
            return "\(riskyWorkspaceCount) workspaces have risk signals"
        }
        if missingWorktreeCount > 0 {
            return "\(missingWorktreeCount) worktrees are missing"
        }
        if dirtyServiceCount > 0 {
            return "\(dirtyServiceCount) services have uncommitted changes"
        }
        if highPriorityTaskCount > 0 {
            return "\(highPriorityTaskCount) high-priority tasks are open"
        }
        if openTaskCount > 0 {
            return "\(openTaskCount) active tasks are ready"
        }
        return "Workspace state is clean"
    }

    var clipboardText: String {
        [
            "Nexus status",
            "Bridge: \(bridgeMode)",
            "Active workspace: \(activeWorkspaceName ?? "None")",
            "Workspaces: \(workspaceCount)",
            "Active workspaces: \(activeWorkspaceCount)",
            "Archived workspaces: \(archivedWorkspaceCount)",
            "Risky workspaces: \(riskyWorkspaceCount)",
            "Blocked workspaces: \(blockedWorkspaceCount)",
            "Active tasks: \(openTaskCount)",
            "High-priority tasks: \(highPriorityTaskCount)",
            "Active agent tasks: \(agentTaskCount)",
            "Missing worktrees: \(missingWorktreeCount)",
            "Dirty services: \(dirtyServiceCount)",
            "Status: \(statusLine)"
        ].joined(separator: "\n")
    }
}

struct ServiceStatus: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let branch: String
    let worktree: String
    let gitSummary: String
    let worktreeExists: Bool
    let sourceExists: Bool
}

struct CodexHandoffFeedback: Identifiable, Hashable {
    let id: UUID
    let title: String
    let detail: String
    let timestamp: String
    let systemImage: String
    let sectionTitle: String
    let clipboardLabel: String
    let guidance: String

    init(
        title: String,
        detail: String,
        timestamp: String,
        systemImage: String,
        sectionTitle: String = "剪贴板反馈 / Clipboard",
        clipboardLabel: String = "Context is on the clipboard",
        guidance: String = "需要继续时可粘贴剪贴板内容；如果 Codex 没有自动带入，也可以直接粘贴。"
    ) {
        self.id = UUID()
        self.title = title
        self.detail = detail
        self.timestamp = timestamp
        self.systemImage = systemImage
        self.sectionTitle = sectionTitle
        self.clipboardLabel = clipboardLabel
        self.guidance = guidance
    }
}

struct LocalWriteFeedback: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let timestamp: String
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let documentPath: String
    let documentLabel: String
    let systemImage: String
}

struct WorkspaceLinkFeedback: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
    let timestamp: String
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let link: String
    let systemImage: String
}

struct CodexSessionLink: Codable, Identifiable, Hashable {
    let id: String
    var title: String
    var url: String
    var notes: String
    var createdAt: String
    var lastOpenedAt: String?
}

struct CodexSessionLinkStore: Codable, Hashable {
    var schemaVersion: Int
    var sessions: [CodexSessionLink]

    static let currentSchemaVersion = 1
}

struct CodexSessionSuggestion: Identifiable, Hashable {
    let id: String
    let title: String
    let url: String
    let notes: String
    let source: String
    let eventTitle: String
    let eventTimestamp: String
}

struct ActivityEvent: Identifiable, Hashable {
    let id = UUID()
    let time: String
    let title: String
    let detail: String
}

struct RiskAlert: Identifiable, Hashable {
    let id = UUID()
    let title: String
    let detail: String
}

struct WorkspaceHealthCheck: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String
    let status: String
    let action: String
}

struct WorkspaceSessionAction: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String
    let priority: String
    let status: String
    let instructionType: String
    let documentKey: String
}

struct WorkspaceSqlFile: Identifiable, Hashable {
    let relativePath: String
    let path: String
    let kind: String

    var id: String { relativePath }

    var fileName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }

    var kindLabel: String {
        kind == "rollback" ? "回滚 SQL / Rollback" : "正式 SQL / Formal"
    }
}

struct WorkspaceSqlDocument: Identifiable, Hashable {
    let relativePath: String
    let path: String
    let kind: String

    var id: String { relativePath }

    var fileName: String {
        URL(fileURLWithPath: relativePath).lastPathComponent
    }

    var kindLabel: String {
        "SQL 说明文档 / Markdown"
    }
}

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

struct WorkspaceTask: Identifiable, Hashable {
    let id: String
    let title: String
    let status: String
    let detail: String
    let priority: String
    let source: String
    let sourceEventID: String?
    let sourceLine: Int?

    var isDone: Bool {
        let normalized = status.lowercased()
        return normalized.contains("完成")
            || normalized.contains("done")
            || normalized.contains("closed")
            || normalized.contains("resolved")
    }

    var isBlocked: Bool {
        let normalized = "\(status) \(detail)".lowercased()
        return normalized.contains("阻塞") || normalized.contains("blocked")
    }

    var isDeferred: Bool {
        let normalized = "\(status) \(detail)".lowercased()
        return normalized.contains("延期") || normalized.contains("deferred")
    }

    var isActive: Bool {
        !isDone && !isDeferred
    }

    var priorityRank: Int {
        if isDeferred { return 4 }
        if isBlocked { return 0 }
        switch priority.lowercased() {
        case "high":
            return 0
        case "medium":
            return 1
        case "low":
            return 3
        default:
            return 2
        }
    }

    var priorityLabel: String {
        switch priority.lowercased() {
        case "high":
            "P0"
        case "medium":
            "P1"
        case "low":
            "P3"
        default:
            "P2"
        }
    }

    var sourceLineLabel: String {
        sourceLine.map { "L\($0)" } ?? "L?"
    }
}

struct TaskCenterItem: Identifiable, Hashable {
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let workspaceFolder: String
    let task: WorkspaceTask

    var id: String {
        "\(workspaceID):\(task.id)"
    }
}

struct TaskStatusUpdate: Identifiable, Hashable {
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let workspacePath: String
    let taskID: String
    let taskTitle: String
    let currentStatus: String
    let nextStatus: String

    var id: String {
        "\(workspaceID):\(taskID):\(nextStatus)"
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

struct SearchResultGroup: Identifiable {
    let id: String
    let label: String
    let results: [SearchResult]
}

extension SearchResult {
    var stableID: String {
        "\(workspaceFolder)-\(documentKey)-\(documentPath)"
    }

    var displayKind: String {
        switch kind {
        case "workspace":
            "workspace"
        case "services":
            "services"
        case "tasks":
            "tasks"
        case "decisions":
            "decisions"
        case "delivery":
            "delivery"
        case "sql":
            "sql"
        case "status":
            "status"
        case "branches":
            "branch"
        default:
            kind
        }
    }

    var groupID: String {
        switch kind {
        case "workspace":
            "workspace"
        case "sql":
            "sql"
        case "services", "branches", "status":
            "state"
        case "tasks", "decisions", "delivery":
            "workflow"
        default:
            "documents"
        }
    }

    var groupLabel: String {
        switch groupID {
        case "workspace":
            "工作区 / Workspace"
        case "sql":
            "SQL 与数据变更 / SQL"
        case "state":
            "服务与状态 / State"
        case "workflow":
            "任务与交付 / Workflow"
        default:
            "文档 / Documents"
        }
    }
}

func groupSearchResults(_ results: [SearchResult]) -> [SearchResultGroup] {
    var groups: [SearchResultGroup] = []
    var indexByID: [String: Int] = [:]

    for result in results {
        if let index = indexByID[result.groupID] {
            var group = groups[index]
            group = SearchResultGroup(id: group.id, label: group.label, results: group.results + [result])
            groups[index] = group
        } else {
            indexByID[result.groupID] = groups.count
            groups.append(SearchResultGroup(id: result.groupID, label: result.groupLabel, results: [result]))
        }
    }

    return groups
}

struct WorkspaceSummary: Identifiable, Hashable {
    let id: String
    let name: String
    let folder: String
    let path: String
    let branch: String
    let state: WorkspaceState
    let riskLevel: RiskLevel
    let aiState: String
    let worktreeState: String
    let documentLinks: [String: String]
    let sqlFiles: [WorkspaceSqlFile]
    let sqlDocuments: [WorkspaceSqlDocument]
    let services: [ServiceStatus]
    let activities: [ActivityEvent]
    let risks: [RiskAlert]
    let healthChecks: [WorkspaceHealthCheck]
    let sessionActions: [WorkspaceSessionAction]
    let lifecycle: WorkspaceLifecycle
    let tasks: [WorkspaceTask]

    var serviceSummary: String {
        services.map(\.name).joined(separator: ", ")
    }

    var isArchived: Bool {
        state == .archived || lifecycle.stage.lowercased() == "archived"
    }

    var lifecycleTransitions: [LifecycleTransition] {
        switch lifecycle.stage {
        case "scoping", "setup":
            return [.developing, .blocked]
        case "developing", "ready":
            return [.delivery, .blocked]
        case "delivery":
            return [.done, .blocked]
        case "done":
            return [.archived, .delivery]
        case "blocked":
            return [.developing, .delivery]
        case "archived":
            return [.developing]
        default:
            return [.developing, .delivery, .blocked]
        }
    }

    func mainStage(
        demandIntakeStatus: DemandIntakeStatus? = nil,
        demandReadiness: DemandIntakeReadinessEvidence? = nil,
        scopeFreeze: ScopeFreezeEvidence? = nil,
        serviceBranch: ServiceBranchEvidence? = nil,
        worktreeSetup: WorktreeSetupEvidence? = nil,
        developmentTasks: DevelopmentTaskEvidence? = nil,
        deliveryGate: DeliveryGateEvidence? = nil,
        archiveGate: ArchiveGateEvidence? = nil,
        demandTaskTransfer: DemandTaskTransferPlan? = nil
    ) -> WorkspaceMainStage {
        if isArchived {
            return WorkspaceMainStage(
                id: .archived,
                status: .archived,
                title: "已归档 / Archived",
                reason: "这个工作区已退出活跃开发流。需要恢复时先查看交接和交付证据。",
                primaryActionLabel: "查看交接",
                primaryActionSystemImage: "doc.text",
                primaryAction: .document("handoff"),
                evidence: compactEvidence("handoff.md", documentLinks["delivery"] ?? "交付记录.md"),
                nextStageAllowed: false
            )
        }

        let demandGate = Self.demandGate(for: self, status: demandIntakeStatus, readiness: demandReadiness)
        if demandGate.status != .ready {
            return WorkspaceMainStage(
                id: .demandIntake,
                status: demandGate.status,
                title: "完成需求预检 / Demand intake",
                reason: demandGate.reason,
                primaryActionLabel: "打开预检",
                primaryActionSystemImage: "text.badge.checkmark",
                primaryAction: .demandIntake,
                evidence: demandGate.evidence,
                nextStageAllowed: false
            )
        }

        let scopeGate = scopeFreeze ?? demandIntakeStatus.map { ScopeFreezeEvidence.resolve(status: $0, workspace: self) }
        if let scopeGate, scopeGate.status != .ready {
            return WorkspaceMainStage(
                id: .scopeFreeze,
                status: scopeGate.status,
                title: "冻结开发范围 / Scope freeze",
                reason: scopeGate.reason,
                primaryActionLabel: "打开范围",
                primaryActionSystemImage: "scope",
                primaryAction: .path(scopeGate.scopePath),
                evidence: scopeGate.evidence,
                nextStageAllowed: false
            )
        }

        let serviceBranchGate = serviceBranch ?? ServiceBranchEvidence.resolve(workspace: self)
        if serviceBranchGate.status != .ready {
            return WorkspaceMainStage(
                id: .serviceBranchConfirm,
                status: serviceBranchGate.status,
                title: serviceBranchGate.title,
                reason: serviceBranchGate.reason,
                primaryActionLabel: serviceBranchGate.primaryActionLabel,
                primaryActionSystemImage: serviceBranchGate.primaryActionSystemImage,
                primaryAction: serviceBranchGate.primaryAction,
                evidence: serviceBranchGate.evidence,
                nextStageAllowed: false
            )
        }

        let worktreeGate = worktreeSetup ?? WorktreeSetupEvidence.resolve(workspace: self)
        if worktreeGate.status != .ready {
            return WorkspaceMainStage(
                id: .worktreeSetup,
                status: worktreeGate.status,
                title: worktreeGate.title,
                reason: worktreeGate.reason,
                primaryActionLabel: worktreeGate.primaryActionLabel,
                primaryActionSystemImage: worktreeGate.primaryActionSystemImage,
                primaryAction: worktreeGate.primaryAction,
                evidence: worktreeGate.evidence,
                nextStageAllowed: false
            )
        }

        if let demandTaskTransfer, demandTaskTransfer.hasTransferableItems {
            return WorkspaceMainStage(
                id: .development,
                status: .next,
                title: "转入执行任务 / Transfer tasks",
                reason: demandTaskTransfer.summary,
                primaryActionLabel: "转入 tasks.md",
                primaryActionSystemImage: "arrow.down.doc",
                primaryAction: .transferDemandTasks,
                evidence: compactEvidence("需求/tasks.md", "tasks.md"),
                nextStageAllowed: false
            )
        }

        let taskGate = developmentTasks ?? DevelopmentTaskEvidence.resolve(workspace: self)
        if taskGate.status != .ready {
            return WorkspaceMainStage(
                id: .development,
                status: taskGate.status,
                title: taskGate.title,
                reason: taskGate.reason,
                primaryActionLabel: taskGate.primaryActionLabel,
                primaryActionSystemImage: taskGate.primaryActionSystemImage,
                primaryAction: taskGate.primaryAction,
                evidence: taskGate.evidence,
                nextStageAllowed: false
            )
        }

        let delivery = deliveryGate ?? DeliveryGateEvidence.resolve(workspace: self)
        if delivery.status == .ready {
            let archive = archiveGate ?? ArchiveGateEvidence.resolve(workspace: self, deliveryGate: delivery)
            return WorkspaceMainStage(
                id: .archived,
                status: archive.status,
                title: archive.title,
                reason: archive.reason,
                primaryActionLabel: archive.primaryActionLabel,
                primaryActionSystemImage: archive.primaryActionSystemImage,
                primaryAction: archive.primaryAction,
                evidence: archive.evidence,
                nextStageAllowed: archive.ready
            )
        }

        return WorkspaceMainStage(
            id: .deliveryCheck,
            status: delivery.status,
            title: delivery.title,
            reason: delivery.reason,
            primaryActionLabel: delivery.primaryActionLabel,
            primaryActionSystemImage: delivery.primaryActionSystemImage,
            primaryAction: delivery.primaryAction,
            evidence: delivery.evidence,
            nextStageAllowed: delivery.ready
        )
    }

    private var normalizedPath: String {
        path.hasSuffix("/") ? String(path.dropLast()) : path
    }

    private func compactEvidence(_ values: String?...) -> [String] {
        values.compactMap { value in
            let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private static func demandGate(
        for workspace: WorkspaceSummary,
        status: DemandIntakeStatus?,
        readiness: DemandIntakeReadinessEvidence?
    ) -> (status: WorkflowPathStatus, reason: String, evidence: [String]) {
        if let readiness {
            return (readiness.status, readiness.reason, readiness.evidence)
        }

        if let status {
            let evidence = status.files.map { "需求/\($0.filename)" }
            if status.ready {
                return (.ready, "需求预检文件已就绪，可以继续冻结范围。", evidence)
            }
            if status.exists {
                return (
                    .review,
                    "需求目录已存在，但仍缺 \(status.missingCount) 个固定文件。先补齐 requirement、questions、scope、tasks 和 delivery。",
                    evidence
                )
            }
            return (
                .blocked,
                "当前工作区还没有 需求/ 目录。先初始化需求预检，再把蓝湖材料和补充说明沉淀到 Markdown。",
                ["需求/"]
            )
        }

        if let check = workspace.healthChecks.first(where: { $0.id == "demand-intake" || $0.action == "demandIntake" }) {
            switch check.status.lowercased() {
            case "pass", "ok", "ready":
                return (.ready, check.detail, ["需求/requirement.md", "需求/questions.md", "需求/scope.md"])
            case "fail", "blocked", "blocker":
                return (.blocked, check.detail, ["需求/"])
            default:
                return (.review, check.detail, ["需求/"])
            }
        }

        return (
            .pending,
            "尚未读取需求预检状态。刷新工作区后确认 需求/ 目录和固定文件是否齐全。",
            ["需求/"]
        )
    }

    private static func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("pending")
            && !normalized.contains("todo")
            && normalized != "-"
    }

    private static func deliveryStageTitle(for status: WorkflowPathStatus) -> String {
        switch status {
        case .ready:
            "交付检查通过 / Delivery ready"
        case .archived:
            "已归档 / Archived"
        case .blocked:
            "交付阻塞 / Delivery blocked"
        case .review, .next:
            "整理交付 / Prepare delivery"
        case .pending:
            "运行交付检查 / Check delivery"
        }
    }

    private static func deliveryStageSymbol(for status: WorkflowPathStatus) -> String {
        switch status {
        case .ready:
            "checkmark.seal"
        case .blocked:
            "xmark.octagon"
        case .archived:
            "archivebox"
        case .review, .next:
            "shippingbox"
        case .pending:
            "doc.text"
        }
    }

    private static func mainAction(for route: WorkflowDeliveryRoute) -> WorkspaceMainStageAction {
        switch route {
        case .runLocalCheck:
            .localCheck
        case .updateDelivery:
            .deliveryHandoff
        case .validationHandoff:
            .validationHandoff
        case .openDelivery:
            .document("delivery")
        }
    }

    init(
        id: String,
        name: String,
        folder: String,
        path: String,
        branch: String,
        state: WorkspaceState,
        riskLevel: RiskLevel,
        aiState: String,
        worktreeState: String,
        documentLinks: [String: String] = [:],
        sqlFiles: [WorkspaceSqlFile] = [],
        sqlDocuments: [WorkspaceSqlDocument] = [],
        services: [ServiceStatus],
        activities: [ActivityEvent],
        risks: [RiskAlert],
        healthChecks: [WorkspaceHealthCheck] = [],
        sessionActions: [WorkspaceSessionAction] = [],
        lifecycle: WorkspaceLifecycle,
        tasks: [WorkspaceTask] = []
    ) {
        self.id = id
        self.name = name
        self.folder = folder
        self.path = path
        self.branch = branch
        self.state = state
        self.riskLevel = riskLevel
        self.aiState = aiState
        self.worktreeState = worktreeState
        self.documentLinks = documentLinks
        self.sqlFiles = sqlFiles
        self.sqlDocuments = sqlDocuments
        self.services = services
        self.activities = activities
        self.risks = risks
        self.healthChecks = healthChecks
        self.sessionActions = sessionActions
        self.lifecycle = lifecycle
        self.tasks = tasks
    }

    init(snapshot: WorkspaceSnapshot) {
        let services = snapshot.gitRows.map { row in
            ServiceStatus(
                name: row.service,
                branch: row.worktree.branch,
                worktree: row.worktree.summary,
                gitSummary: row.source.summary,
                worktreeExists: row.worktree.exists,
                sourceExists: row.source.exists
            )
        }
        let risks = snapshot.risks.map { risk in
            RiskAlert(title: riskTitle(risk), detail: risk)
        }
        let worktreeState = services.isEmpty
            ? "No confirmed services"
            : "\(services.count) services · \(snapshot.gitRows.filter { !$0.worktree.exists }.count) missing"
        let snapshotActivities = (snapshot.activities ?? []).map { activity in
            ActivityEvent(time: activity.time, title: activity.title, detail: activity.detail)
        }
        let activities = snapshotActivities.isEmpty ? [
            ActivityEvent(
                time: snapshot.updated,
                title: snapshot.risks.first ?? "Workspace scanned",
                detail: "Loaded from Nexus Core dashboard snapshot"
            )
        ] : snapshotActivities
        let healthChecks = (snapshot.healthChecks ?? []).map { check in
            WorkspaceHealthCheck(
                id: check.id,
                label: check.label,
                detail: check.detail,
                status: check.status,
                action: check.action
            )
        }
        let sessionActions = (snapshot.sessionActions ?? []).map { action in
            WorkspaceSessionAction(
                id: action.id,
                label: action.label,
                detail: action.detail,
                priority: action.priority,
                status: action.status,
                instructionType: action.instructionType,
                documentKey: action.documentKey
            )
        }
        let sqlFiles = (snapshot.sqlFiles ?? []).map { file in
            WorkspaceSqlFile(
                relativePath: file.relativePath,
                path: file.path,
                kind: file.kind
            )
        }
        let sqlDocuments = (snapshot.sqlDocuments ?? []).map { file in
            WorkspaceSqlDocument(
                relativePath: file.relativePath,
                path: file.path,
                kind: file.kind
            )
        }
        let tasks = (snapshot.tasks ?? []).map { task in
            WorkspaceTask(
                id: task.id,
                title: task.title,
                status: task.status,
                detail: task.detail,
                priority: task.priority,
                source: task.source,
                sourceEventID: task.sourceEventId,
                sourceLine: task.sourceLine
            )
        }
        let lifecycle = WorkspaceLifecycle(
            snapshot: snapshot.lifecycle,
            state: snapshot.state,
            targetBranch: snapshot.targetBranch,
            services: services,
            risks: risks,
            tasks: tasks
        )

        self.init(
            id: snapshot.folder,
            name: snapshot.name,
            folder: snapshot.folder,
            path: snapshot.path,
            branch: snapshot.targetBranch,
            state: WorkspaceState(snapshot.state),
            riskLevel: RiskLevel(riskCount: snapshot.riskCount),
            aiState: snapshot.riskCount == 0 ? "Ready for Codex continuation" : "\(snapshot.riskCount) risks need review",
            worktreeState: worktreeState,
            documentLinks: snapshot.links,
            sqlFiles: sqlFiles,
            sqlDocuments: sqlDocuments,
            services: services,
            activities: activities,
            risks: risks,
            healthChecks: healthChecks,
            sessionActions: sessionActions,
            lifecycle: lifecycle,
            tasks: tasks
        )
    }

    static let previewData: [WorkspaceSummary] = [
        WorkspaceSummary(
            id: "2026-05-25-yibao-pay-log",
            name: "易宝对账补充 pay_log",
            folder: "2026-05-25-yibao-pay-log",
            path: "~/ks_project/workspaces/2026-05-25-yibao-pay-log",
            branch: "feature/yibao-pay-log",
            state: .developing,
            riskLevel: .medium,
            aiState: "Needs delivery update",
            worktreeState: "3 services pending review",
            documentLinks: ["handoff": "~/ks_project/workspaces/2026-05-25-yibao-pay-log/handoff.md"],
            sqlFiles: [
                WorkspaceSqlFile(
                    relativePath: "20260525_pay_log_backfill.sql",
                    path: "~/ks_project/workspaces/2026-05-25-yibao-pay-log/sql/20260525_pay_log_backfill.sql",
                    kind: "formal"
                ),
                WorkspaceSqlFile(
                    relativePath: "20260525_pay_log_backfill_rollback.sql",
                    path: "~/ks_project/workspaces/2026-05-25-yibao-pay-log/sql/20260525_pay_log_backfill_rollback.sql",
                    kind: "rollback"
                )
            ],
            services: [
                ServiceStatus(name: "order", branch: "feature/yibao-pay-log", worktree: "ready", gitSummary: "clean", worktreeExists: true, sourceExists: true),
                ServiceStatus(name: "store-cashier", branch: "feature/yibao-pay-log", worktree: "ready", gitSummary: "dirty", worktreeExists: true, sourceExists: true),
                ServiceStatus(name: "commodity", branch: "master", worktree: "missing", gitSummary: "source clean", worktreeExists: false, sourceExists: true)
            ],
            activities: [
                ActivityEvent(time: "09:42", title: "交付记录待补充", detail: "新增 pay_log 回填逻辑后需要补齐 SQL 与验证说明"),
                ActivityEvent(time: "09:18", title: "Branch alignment checked", detail: "order and store-cashier are aligned")
            ],
            risks: [
                RiskAlert(title: "worktree 未创建", detail: "commodity 尚未建立需求 worktree"),
                RiskAlert(title: "交付记录待补充", detail: "交付记录仍包含占位内容")
            ],
            healthChecks: [
                WorkspaceHealthCheck(id: "worktree-ready", label: "Worktree 就绪 / Worktree ready", detail: "缺少: commodity", status: "fail", action: "worktreeScript"),
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录 / Delivery record", detail: "交付记录仍包含待补充内容", status: "warning", action: "delivery")
            ],
            sessionActions: [
                WorkspaceSessionAction(id: "create-worktrees", label: "创建缺失 worktree / Create worktrees", detail: "缺少 worktree: commodity", priority: "high", status: "recommended", instructionType: "worktree", documentKey: "worktreeScript"),
                WorkspaceSessionAction(id: "start-codex-session", label: "启动 Codex 会话 / Start Codex session", detail: "复制当前工作区上下文，带着上方动作进入 Codex 继续处理。", priority: "low", status: "recommended", instructionType: "continue", documentKey: "handoff")
            ],
            lifecycle: WorkspaceLifecycle(
                stage: "setup",
                label: "环境准备 / Setup",
                detail: "还有 1 个服务缺少 workspace-local worktree。",
                progress: 35,
                nextAction: "创建缺失 worktree 后再进入开发。",
                documentKey: "worktreeScript"
            ),
            tasks: [
                WorkspaceTask(id: "task-pay-log-chain", title: "核对 pay_log 回填链路", status: "进行中", detail: "确认 order 与 store-cashier 的写入路径", priority: "high", source: "workspace", sourceEventID: nil, sourceLine: 5),
                WorkspaceTask(id: "task-delivery-doc", title: "补齐交付记录", status: "待办", detail: "新增 SQL 或逻辑后补齐验证说明", priority: "medium", source: "workspace", sourceEventID: nil, sourceLine: 6),
                WorkspaceTask(id: "task-agent-review", title: "Review permission request: Git push", status: "待确认", detail: "来自 Agent 事件 preview-agent-event", priority: "medium", source: "agent", sourceEventID: "preview-agent-event", sourceLine: 7)
            ]
        ),
        WorkspaceSummary(
            id: "2026-05-25-multi-price",
            name: "多价格开发",
            folder: "2026-05-25-多价格开发",
            path: "~/ks_project/workspaces/2026-05-25-多价格开发",
            branch: "feature/pricing-snapshot",
            state: .analyzing,
            riskLevel: .low,
            aiState: "Ready for Codex continuation",
            worktreeState: "All selected services ready",
            documentLinks: ["handoff": "~/ks_project/workspaces/2026-05-25-多价格开发/handoff.md"],
            services: [
                ServiceStatus(name: "store", branch: "feature/pricing-snapshot", worktree: "ready", gitSummary: "clean", worktreeExists: true, sourceExists: true),
                ServiceStatus(name: "order", branch: "feature/pricing-snapshot", worktree: "ready", gitSummary: "clean", worktreeExists: true, sourceExists: true)
            ],
            activities: [
                ActivityEvent(time: "08:40", title: "Workspace created", detail: "Standard Markdown skeleton generated"),
                ActivityEvent(time: "08:44", title: "AI context archived", detail: "AGENTS and handoff docs are available")
            ],
            risks: [],
            healthChecks: [
                WorkspaceHealthCheck(id: "service-scope", label: "服务范围 / Service scope", detail: "已确认 2 个服务", status: "pass", action: "services")
            ],
            sessionActions: [
                WorkspaceSessionAction(id: "start-codex-session", label: "启动 Codex 会话 / Start Codex session", detail: "就绪检查已通过，可以复制完整上下文并进入开发会话。", priority: "high", status: "recommended", instructionType: "continue", documentKey: "handoff")
            ],
            lifecycle: WorkspaceLifecycle(
                stage: "ready",
                label: "就绪 / Ready",
                detail: "服务、分支和 worktree 已就绪，可以启动 Codex 开发会话。",
                progress: 45,
                nextAction: "复制 handoff 上下文并进入开发。",
                documentKey: "handoff"
            ),
            tasks: [
                WorkspaceTask(id: "task-snapshot-plan", title: "确认价格快照方案", status: "已完成", detail: "方案已归档到工作区文档", priority: "normal", source: "workspace", sourceEventID: nil, sourceLine: 5)
            ]
        )
    ]

    func prepending(activity: ActivityEvent) -> WorkspaceSummary {
        WorkspaceSummary(
            id: id,
            name: name,
            folder: folder,
            path: path,
            branch: branch,
            state: state,
            riskLevel: riskLevel,
            aiState: aiState,
            worktreeState: worktreeState,
            documentLinks: documentLinks,
            sqlFiles: sqlFiles,
            sqlDocuments: sqlDocuments,
            services: services,
            activities: Array(([activity] + activities).prefix(6)),
            risks: risks,
            healthChecks: healthChecks,
            sessionActions: sessionActions,
            lifecycle: lifecycle,
            tasks: tasks
        )
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

private extension WorkspaceState {
    init(_ rawState: String) {
        switch rawState.lowercased() {
        case "developing", "development":
            self = .developing
        case "ready", "delivery", "done":
            self = .ready
        case "blocked", "阻塞":
            self = .blocked
        case "archived", "archive", "归档", "已归档":
            self = .archived
        default:
            self = .analyzing
        }
    }
}

private extension RiskLevel {
    init(riskCount: Int) {
        if riskCount >= 3 {
            self = .high
        } else if riskCount > 0 {
            self = .medium
        } else {
            self = .low
        }
    }
}

private func riskTitle(_ risk: String) -> String {
    guard let title = risk.split(separator: ":", maxSplits: 1).first else {
        return risk
    }
    return String(title)
}
