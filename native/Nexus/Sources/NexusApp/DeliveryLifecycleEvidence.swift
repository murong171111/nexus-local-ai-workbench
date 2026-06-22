import Foundation

struct DeliveryGateCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
    let action: WorkspaceMainStageAction
}

enum DeliveryResolutionPlanAction: Hashable {
    case resolveBlocker
    case runCheck
    case review
    case passed

    var displayLabel: String {
        switch self {
        case .resolveBlocker:
            "resolve"
        case .runCheck:
            "check"
        case .review:
            "review"
        case .passed:
            "passed"
        }
    }

    var status: WorkflowPathStatus {
        switch self {
        case .resolveBlocker:
            .blocked
        case .runCheck:
            .pending
        case .review:
            .review
        case .passed:
            .ready
        }
    }

    var systemImage: String {
        switch self {
        case .resolveBlocker:
            "xmark.octagon"
        case .runCheck:
            "checklist"
        case .review:
            "exclamationmark.triangle"
        case .passed:
            "checkmark.circle"
        }
    }

    var sortRank: Int {
        switch self {
        case .resolveBlocker:
            0
        case .runCheck:
            1
        case .review:
            2
        case .passed:
            3
        }
    }
}

struct DeliveryResolutionPlanItem: Hashable, Identifiable {
    let id: String
    let checkID: String
    let title: String
    let action: DeliveryResolutionPlanAction
    let detail: String
    let evidencePath: String?
    let gateAction: WorkspaceMainStageAction
    let handoffHint: String
}

struct DeliveryGateEvidence: Hashable {
    let status: WorkflowPathStatus
    let title: String
    let reason: String
    let value: String
    let evidence: [String]
    let checks: [DeliveryGateCheck]
    let resolutionPlan: [DeliveryResolutionPlanItem]
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
                resolutionPlan: [],
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
            resolutionPlan: buildResolutionPlan(checks: checks),
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

    private static func buildResolutionPlan(checks: [DeliveryGateCheck]) -> [DeliveryResolutionPlanItem] {
        checks.map { check in
            let action = resolutionAction(for: check.status)
            return DeliveryResolutionPlanItem(
                id: "\(action.displayLabel)-\(check.id)",
                checkID: check.id,
                title: check.label,
                action: action,
                detail: check.detail,
                evidencePath: check.path,
                gateAction: check.action,
                handoffHint: resolutionHint(for: check, action: action)
            )
        }
        .sorted { left, right in
            if left.action.sortRank != right.action.sortRank {
                return left.action.sortRank < right.action.sortRank
            }
            return deliveryPlanSortRank(for: left.checkID) < deliveryPlanSortRank(for: right.checkID)
        }
    }

    private static func resolutionAction(for status: WorkflowPathStatus) -> DeliveryResolutionPlanAction {
        switch status {
        case .blocked:
            .resolveBlocker
        case .pending:
            .runCheck
        case .review, .next:
            .review
        case .ready, .archived:
            .passed
        }
    }

    private static func deliveryPlanSortRank(for checkID: String) -> Int {
        switch checkID {
        case "branch":
            0
        case "services":
            1
        case "tasks":
            2
        case "risks":
            3
        case "delivery-record":
            4
        case "sql":
            5
        case "dirty-services":
            6
        default:
            99
        }
    }

    private static func resolutionHint(
        for check: DeliveryGateCheck,
        action: DeliveryResolutionPlanAction
    ) -> String {
        switch check.id {
        case "branch":
            return action == .passed
                ? "目标分支证据已可用，交付记录引用该分支即可。"
                : "在 branches.md 或 workspace.md 确认目标分支后重新运行本地检查。"
        case "services":
            return action == .passed
                ? "服务和 worktree 证据已可用，交付记录引用涉及服务即可。"
                : "补齐 services.md 和 workspace-local worktree 后重新运行本地检查。"
        case "tasks":
            return action == .passed
                ? "root tasks.md 已清理，无需写回；交付记录可引用已完成任务。"
                : "在 root tasks.md 将任务写回为已完成、延期或拆分后再交付。"
        case "risks":
            return action == .passed
                ? "风险复核通过，交付记录可写明当前无活动风险。"
                : "把风险结论写回 STATUS.md 或交付记录，必要时复制风险交接给 Codex。"
        case "delivery-record":
            if action == .runCheck {
                return "运行本地检查，生成交付记录状态后再判断是否需要补写。"
            }
            return action == .passed
                ? "交付记录可用，后续只需追加本地验证、PR、CI 或发布结果。"
                : "补齐代码变更、新逻辑、配置、SQL 影响和验证记录后更新交付记录。"
        case "sql":
            if action == .runCheck {
                return "运行本地检查确认交付记录是否声明 SQL 变更。"
            }
            return action == .passed
                ? "SQL 产物通过，可在交付/PR 交接中引用正式和回滚文件。"
                : "在 sql/ 补齐正式 SQL 和回滚 SQL，或在交付记录明确无 SQL 变更。"
        case "dirty-services":
            return action == .passed
                ? "服务 Git 状态清洁，无需额外处理。"
                : "提交、暂存或记录服务改动结论，避免本地改动漏进交付。"
        default:
            return action == .passed
                ? "该检查已通过，保留当前证据。"
                : "按检查详情处理后重新运行本地检查。"
        }
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

struct DeliveryRecordWritePlanItem: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let evidencePath: String?
}

struct DeliveryRecordWritePlan: Identifiable, Hashable {
    let id: String
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let deliveryPath: String
    let status: WorkflowPathStatus
    let summary: String
    let items: [DeliveryRecordWritePlanItem]
    let appendedMarkdown: String

    var canWrite: Bool {
        status != .archived && !appendedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func resolve(workspace: WorkspaceSummary, gate: DeliveryGateEvidence) -> DeliveryRecordWritePlan {
        let deliveryPath = workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md"
        let id = "\(workspace.id)-delivery-record"

        guard gate.status != .archived else {
            return DeliveryRecordWritePlan(
                id: id,
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                deliveryPath: deliveryPath,
                status: .archived,
                summary: "已归档工作区默认只读；恢复开发后再追加交付记录。",
                items: [],
                appendedMarkdown: ""
            )
        }

        let items = gate.checks.map { check in
            DeliveryRecordWritePlanItem(
                id: check.id,
                label: check.label,
                detail: check.detail,
                status: check.status,
                evidencePath: check.path
            )
        }
        return DeliveryRecordWritePlan(
            id: id,
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            deliveryPath: deliveryPath,
            status: gate.status == .ready ? .next : gate.status,
            summary: "确认后只会向交付记录追加当前 Delivery Gate 快照，不覆盖人工记录。",
            items: items,
            appendedMarkdown: deliverySnapshotMarkdown(workspace: workspace, gate: gate, items: items)
        )
    }

    private static func deliverySnapshotMarkdown(
        workspace: WorkspaceSummary,
        gate: DeliveryGateEvidence,
        items: [DeliveryRecordWritePlanItem]
    ) -> String {
        var lines = [
            "",
            "## Nexus Delivery Gate Snapshot",
            "",
            "- 工作区：\(workspace.name)",
            "- 生命周期：\(workspace.lifecycle.stage)",
            "- 目标分支：\(workspace.branch)",
            "- 门禁状态：\(gate.status.displayLabel)",
            "- 下一步：\(gate.primaryActionLabel)",
            "- 说明：\(gate.reason)",
            "",
            "| 检查项 | 状态 | 证据 | 说明 |",
            "| --- | --- | --- | --- |"
        ]

        for item in items {
            lines.append("| \(escapeMarkdownCell(item.label)) | \(item.status.displayLabel) | \(escapeMarkdownCell(item.evidencePath ?? "-")) | \(escapeMarkdownCell(item.detail)) |")
        }

        lines.append(contentsOf: [
            "",
            "- 写入来源：Nexus Native confirmed write。",
            "- 后续要求：如有 SQL、PR/CI、发布或遗留风险结论，继续追加在本交付记录中。"
        ])
        return lines.joined(separator: "\n")
    }

    private static func escapeMarkdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
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

enum ArchiveConfirmationPlanAction: Hashable {
    case finishDelivery
    case reviewDelivery
    case reviewValidation
    case enterDelivery
    case markDone
    case archive
    case archived
    case restore

    var displayLabel: String {
        switch self {
        case .finishDelivery:
            "finish"
        case .reviewDelivery:
            "delivery"
        case .reviewValidation:
            "review"
        case .enterDelivery:
            "delivery"
        case .markDone:
            "done"
        case .archive:
            "archive"
        case .archived:
            "archived"
        case .restore:
            "restore"
        }
    }

    var systemImage: String {
        switch self {
        case .finishDelivery:
            "shippingbox"
        case .reviewDelivery:
            "doc.text.magnifyingglass"
        case .reviewValidation:
            "point.3.connected.trianglepath.dotted"
        case .enterDelivery:
            LifecycleTransition.delivery.systemImage
        case .markDone:
            LifecycleTransition.done.systemImage
        case .archive, .archived:
            LifecycleTransition.archived.systemImage
        case .restore:
            LifecycleTransition.restoreDevelopment.systemImage
        }
    }
}

struct ArchiveConfirmationPlanItem: Hashable, Identifiable {
    let id: String
    let title: String
    let action: ArchiveConfirmationPlanAction
    let status: WorkflowPathStatus
    let detail: String
    let evidencePath: String?
    let gateAction: WorkspaceMainStageAction
    let confirmationHint: String
}

struct ArchiveGateEvidence: Hashable {
    let status: WorkflowPathStatus
    let title: String
    let reason: String
    let value: String
    let evidence: [String]
    let checks: [ArchiveGateCheck]
    let confirmationPlan: [ArchiveConfirmationPlanItem]
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
        deliveryGate: DeliveryGateEvidence? = nil,
        validationPr: ValidationPrEvidence? = nil
    ) -> ArchiveGateEvidence {
        if workspace.isArchived {
            return ArchiveGateEvidence(
                status: .archived,
                title: "已归档 / Archived",
                reason: "这个工作区已退出活跃开发流，默认作为只读历史查看。恢复开发必须显式确认并写回生命周期。",
                value: "已归档",
                evidence: archiveEvidence(workspace: workspace),
                checks: [],
                confirmationPlan: archivedConfirmationPlan(workspace: workspace),
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
                confirmationPlan: deliveryIssueConfirmationPlan(checks: checks),
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
                confirmationPlan: buildConfirmationPlan(
                    workspace: workspace,
                    delivery: delivery,
                    validationPr: validationPr
                ),
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
                confirmationPlan: buildConfirmationPlan(
                    workspace: workspace,
                    delivery: delivery,
                    validationPr: validationPr
                ),
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
            confirmationPlan: buildConfirmationPlan(
                workspace: workspace,
                delivery: delivery,
                validationPr: validationPr
            ),
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

    private static func archivedConfirmationPlan(workspace: WorkspaceSummary) -> [ArchiveConfirmationPlanItem] {
        [
            ArchiveConfirmationPlanItem(
                id: "archived-handoff",
                title: "查看归档交接 / Archived handoff",
                action: .archived,
                status: .archived,
                detail: "工作区已归档，默认作为只读历史查看。需要继续开发时先从 handoff 恢复上下文。",
                evidencePath: workspace.documentLinks["handoff"] ?? "\(workspace.path)/handoff.md",
                gateAction: .document("handoff"),
                confirmationHint: "归档工作区不再计入活跃统计；恢复开发前先确认分支和 worktree。"
            ),
            ArchiveConfirmationPlanItem(
                id: "restore-development",
                title: "恢复开发 / Restore development",
                action: .restore,
                status: .next,
                detail: "需要继续处理这个需求时，通过确认弹窗把生命周期写回 developing，然后重新运行本地检查。",
                evidencePath: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md",
                gateAction: .lifecycle(.restoreDevelopment),
                confirmationHint: "恢复只更新 workspace.md、STATUS.md 和审计事件，不会自动切分支、移动目录或修改任务。"
            )
        ]
    }

    private static func deliveryIssueConfirmationPlan(checks: [ArchiveGateCheck]) -> [ArchiveConfirmationPlanItem] {
        checks
            .filter { $0.status != .ready && $0.status != .archived }
            .map { check in
                ArchiveConfirmationPlanItem(
                    id: "finish-delivery-\(check.id)",
                    title: check.label,
                    action: .finishDelivery,
                    status: check.status,
                    detail: check.detail,
                    evidencePath: check.path,
                    gateAction: check.action,
                    confirmationHint: deliveryIssueConfirmationHint(for: check)
                )
            }
            .sorted { left, right in
                if archivePlanStatusRank(left.status) != archivePlanStatusRank(right.status) {
                    return archivePlanStatusRank(left.status) < archivePlanStatusRank(right.status)
                }
                return left.id < right.id
            }
    }

    private static func buildConfirmationPlan(
        workspace: WorkspaceSummary,
        delivery: DeliveryGateEvidence,
        validationPr: ValidationPrEvidence?
    ) -> [ArchiveConfirmationPlanItem] {
        var plan = [
            ArchiveConfirmationPlanItem(
                id: "review-delivery-record",
                title: "复核交付记录 / Review delivery",
                action: .reviewDelivery,
                status: .ready,
                detail: "交付门禁已通过。归档前最后确认代码、逻辑、配置、SQL、验证和风险结论都已写入交付记录。",
                evidencePath: workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md",
                gateAction: .document("delivery"),
                confirmationHint: "交付记录是归档后恢复上下文的第一入口。"
            )
        ]

        let lifecycleStage = workspace.lifecycle.stage.lowercased()
        if lifecycleStage == "done" {
            let validation = validationPr ?? ValidationPrEvidence.resolve(workspace: workspace, deliveryGate: delivery)
            plan.append(
                ArchiveConfirmationPlanItem(
                    id: "review-validation-pr",
                    title: "复核验证与 PR / Validation and PR",
                    action: .reviewValidation,
                    status: validation.status == .archived ? .ready : validation.status,
                    detail: validation.reason,
                    evidencePath: workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md",
                    gateAction: validation.primaryAction,
                    confirmationHint: validation.status == .ready
                        ? "已发现 PR、CI、验证或发布证据；归档前确认结论可追溯。"
                        : "PR/CI 尚未直接集成时，把验证、发布和遗留风险结论补到交付记录或交接。"
                )
            )
            plan.append(
                ArchiveConfirmationPlanItem(
                    id: "archive-workspace",
                    title: "最终归档 / Final archive",
                    action: .archive,
                    status: .ready,
                    detail: "生命周期已完成，可以通过确认弹窗写回 archived 状态。",
                    evidencePath: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md",
                    gateAction: .lifecycle(.archived),
                    confirmationHint: "归档只更新 workspace.md、STATUS.md 和审计事件，不移动目录或删除 worktree。"
                )
            )
        } else if lifecycleStage == "delivery" {
            plan.append(
                ArchiveConfirmationPlanItem(
                    id: "mark-workspace-done",
                    title: "标记完成 / Mark done",
                    action: .markDone,
                    status: .next,
                    detail: "当前处于交付整理阶段。先确认交付材料，再通过确认弹窗标记完成。",
                    evidencePath: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md",
                    gateAction: .lifecycle(.done),
                    confirmationHint: "完成状态用于留出 PR、CI、发布和遗留风险复核窗口。"
                )
            )
        } else {
            plan.append(
                ArchiveConfirmationPlanItem(
                    id: "enter-delivery",
                    title: "进入交付整理 / Enter delivery",
                    action: .enterDelivery,
                    status: .next,
                    detail: "交付门禁已通过，但生命周期尚未进入交付整理。先写回 delivery，再继续完成和归档确认。",
                    evidencePath: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md",
                    gateAction: .lifecycle(.delivery),
                    confirmationHint: "这一步防止从开发阶段直接跳到归档。"
                )
            )
        }

        return plan
    }

    private static func archivePlanStatusRank(_ status: WorkflowPathStatus) -> Int {
        switch status {
        case .blocked:
            0
        case .pending:
            1
        case .review:
            2
        case .next:
            3
        case .ready:
            4
        case .archived:
            5
        }
    }

    private static func deliveryIssueConfirmationHint(for check: ArchiveGateCheck) -> String {
        switch check.status {
        case .blocked:
            "该项会阻止归档；处理后重新运行本地检查。"
        case .pending:
            "先运行本地检查生成证据，再继续交付和归档确认。"
        case .review, .next:
            "归档前需要明确处理结论，必要时交给 Codex 补齐文档。"
        case .ready:
            "该项已通过。"
        case .archived:
            "该项已归档。"
        }
    }
}

struct ArchiveChecklistWritePlan: Identifiable, Hashable {
    let id: String
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let deliveryPath: String
    let status: WorkflowPathStatus
    let summary: String
    let items: [ArchiveConfirmationPlanItem]
    let appendedMarkdown: String

    var canWrite: Bool {
        status != .archived && !items.isEmpty && !appendedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func resolve(workspace: WorkspaceSummary, archiveGate: ArchiveGateEvidence) -> ArchiveChecklistWritePlan {
        let deliveryPath = workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md"
        let id = "\(workspace.id)-archive-checklist"

        guard archiveGate.status != .archived else {
            return ArchiveChecklistWritePlan(
                id: id,
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                deliveryPath: deliveryPath,
                status: .archived,
                summary: "已归档工作区默认只读；恢复开发后再追加归档清单。",
                items: archiveGate.confirmationPlan,
                appendedMarkdown: ""
            )
        }

        guard !archiveGate.confirmationPlan.isEmpty else {
            return ArchiveChecklistWritePlan(
                id: id,
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                deliveryPath: deliveryPath,
                status: archiveGate.status,
                summary: "当前没有可写入的归档确认项。",
                items: [],
                appendedMarkdown: ""
            )
        }

        return ArchiveChecklistWritePlan(
            id: id,
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            deliveryPath: deliveryPath,
            status: archiveGate.status == .ready ? .next : archiveGate.status,
            summary: "确认后只会向交付记录追加当前归档确认清单，不会写回生命周期状态。",
            items: archiveGate.confirmationPlan,
            appendedMarkdown: archiveChecklistMarkdown(workspace: workspace, archiveGate: archiveGate)
        )
    }

    private static func archiveChecklistMarkdown(
        workspace: WorkspaceSummary,
        archiveGate: ArchiveGateEvidence
    ) -> String {
        var lines = [
            "",
            "## Nexus Archive Checklist",
            "",
            "- 工作区：\(workspace.name)",
            "- 生命周期：\(workspace.lifecycle.stage)",
            "- 归档状态：\(archiveGate.status.displayLabel)",
            "- 下一步：\(archiveGate.primaryActionLabel)",
            "- 说明：\(archiveGate.reason)",
            "",
            "| 确认项 | 状态 | 证据 | 操作 | 说明 |",
            "| --- | --- | --- | --- | --- |"
        ]

        for item in archiveGate.confirmationPlan {
            lines.append("| \(escapeMarkdownCell(item.title)) | \(item.status.displayLabel) | \(escapeMarkdownCell(item.evidencePath ?? "-")) | \(escapeMarkdownCell(item.action.displayLabel)) | \(escapeMarkdownCell(item.confirmationHint)) |")
        }

        lines.append(contentsOf: [
            "",
            "- 写入来源：Nexus Native confirmed write。",
            "- 生命周期写回：本清单只记录归档前证据；最终进入 delivery、done、archived 或 restore 仍需通过生命周期确认弹窗。"
        ])
        return lines.joined(separator: "\n")
    }

    private static func escapeMarkdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}

struct ValidationPrCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
    let action: WorkspaceMainStageAction
}

struct ValidationPrEvidence: Hashable {
    let status: WorkflowPathStatus
    let title: String
    let reason: String
    let value: String
    let checks: [ValidationPrCheck]
    let primaryActionLabel: String
    let primaryActionSystemImage: String
    let primaryAction: WorkspaceMainStageAction
    let reviewCount: Int

    var ready: Bool {
        status == .ready || status == .archived
    }

    static func resolve(
        workspace: WorkspaceSummary,
        deliveryGate: DeliveryGateEvidence? = nil
    ) -> ValidationPrEvidence {
        if workspace.isArchived {
            return ValidationPrEvidence(
                status: .archived,
                title: "已归档 / Archived",
                reason: "这个工作区已退出活跃交付流。验证、PR 和归档上下文以交付记录与 handoff 为准。",
                value: "已归档",
                checks: [],
                primaryActionLabel: "查看交接",
                primaryActionSystemImage: "doc.text",
                primaryAction: .document("handoff"),
                reviewCount: 0
            )
        }

        let delivery = deliveryGate ?? DeliveryGateEvidence.resolve(workspace: workspace)
        if delivery.status != .ready {
            return ValidationPrEvidence(
                status: delivery.status,
                title: "先完成交付检查 / Finish delivery first",
                reason: delivery.reason,
                value: delivery.value,
                checks: [
                    ValidationPrCheck(
                        id: "delivery-gate",
                        label: "交付门禁 / Delivery",
                        detail: delivery.reason,
                        status: delivery.status,
                        systemImage: delivery.primaryActionSystemImage,
                        path: workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md",
                        action: delivery.primaryAction
                    )
                ],
                primaryActionLabel: delivery.primaryActionLabel,
                primaryActionSystemImage: delivery.primaryActionSystemImage,
                primaryAction: delivery.primaryAction,
                reviewCount: delivery.warningCount + delivery.blockerCount
            )
        }

        let checks = validationChecks(workspace: workspace, deliveryGate: delivery)
        let blockers = checks.filter { $0.status == .blocked }
        let reviews = checks.filter { $0.status == .review || $0.status == .pending || $0.status == .next }
        let lifecycleStage = workspace.lifecycle.stage.lowercased()
        let hasPrEvidence = hasPrCiEvidence(workspace: workspace)

        let status: WorkflowPathStatus
        let title: String
        let value: String
        let primaryAction: WorkspaceMainStageAction
        let reason: String

        if !blockers.isEmpty {
            status = .blocked
            title = "验证前仍有阻塞 / Validation blocked"
            value = "阻 \(blockers.count)"
            primaryAction = blockers.first?.action ?? .validationHandoff
            reason = blockers.first?.detail ?? "验证前仍有阻塞项。"
        } else if lifecycleStage == "delivery" {
            status = .next
            title = "准备标记完成 / Mark done"
            value = "待完成"
            primaryAction = .lifecycle(.done)
            reason = "交付检查已通过。先确认验证与 PR 交接上下文，再把生命周期标记为完成。"
        } else if lifecycleStage == "done", hasPrEvidence, reviews.isEmpty {
            status = .ready
            title = "验证证据可用 / Validation ready"
            value = "可归档"
            primaryAction = .document("delivery")
            reason = "生命周期已完成，且已发现 PR/CI、验证或发布相关证据。可以复查交付记录后归档。"
        } else if lifecycleStage == "done" {
            status = .review
            title = "补充 PR/CI 结论 / PR and CI review"
            value = "待复核"
            primaryAction = .validationHandoff
            reason = "生命周期已完成，但 PR、CI、发布或遗留风险结论仍建议补到交付记录或交接上下文中。"
        } else {
            status = .next
            title = "准备交付完成 / Prepare completion"
            value = "待完成"
            primaryAction = .lifecycle(.delivery)
            reason = "交付检查已通过，但生命周期尚未进入完成阶段。先进入交付整理，再准备验证与 PR 交接。"
        }

        return ValidationPrEvidence(
            status: status,
            title: title,
            reason: reason,
            value: value,
            checks: checks,
            primaryActionLabel: actionLabel(for: primaryAction, status: status),
            primaryActionSystemImage: actionSystemImage(for: primaryAction, status: status),
            primaryAction: primaryAction,
            reviewCount: blockers.count + reviews.count
        )
    }

    private static func validationChecks(
        workspace: WorkspaceSummary,
        deliveryGate: DeliveryGateEvidence
    ) -> [ValidationPrCheck] {
        [
            localCheck(workspace: workspace),
            deliveryCheck(workspace: workspace, deliveryGate: deliveryGate),
            taskRiskCheck(workspace: workspace),
            prCiCheck(workspace: workspace),
            lifecycleCheck(workspace: workspace)
        ]
    }

    private static func localCheck(workspace: WorkspaceSummary) -> ValidationPrCheck {
        let hasChecks = !workspace.healthChecks.isEmpty
        let hasBlocker = workspace.healthChecks.contains { check in
            let normalized = check.status.lowercased()
            return normalized.contains("fail") || normalized.contains("block")
        }
        let hasWarning = workspace.healthChecks.contains { check in
            let normalized = check.status.lowercased()
            return normalized.contains("warning") || normalized.contains("review")
        }

        let status: WorkflowPathStatus
        let detail: String
        if !hasChecks {
            status = .pending
            detail = "尚未看到本地检查结果。验证/PR 交接前建议运行一次 Nexus 本地检查。"
        } else if hasBlocker {
            status = .blocked
            detail = "本地检查仍包含阻塞项，先处理失败检查再准备 PR。"
        } else if hasWarning {
            status = .review
            detail = "本地检查包含复核项，PR 交接中需要说明处理结论。"
        } else {
            status = .ready
            detail = "本地检查没有发现阻塞或复核项。"
        }

        return ValidationPrCheck(
            id: "local-check",
            label: "本地检查 / Local",
            detail: detail,
            status: status,
            systemImage: "checklist",
            path: nil,
            action: .localCheck
        )
    }

    private static func deliveryCheck(
        workspace: WorkspaceSummary,
        deliveryGate: DeliveryGateEvidence
    ) -> ValidationPrCheck {
        ValidationPrCheck(
            id: "delivery-record",
            label: "交付记录 / Delivery",
            detail: deliveryGate.ready
                ? "交付门禁已通过。PR 摘要应引用交付记录中的改动、SQL、配置、验证和风险说明。"
                : deliveryGate.reason,
            status: deliveryGate.ready ? .ready : deliveryGate.status,
            systemImage: "doc.text",
            path: workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md",
            action: deliveryGate.ready ? .document("delivery") : deliveryGate.primaryAction
        )
    }

    private static func taskRiskCheck(workspace: WorkspaceSummary) -> ValidationPrCheck {
        let activeTasks = workspace.tasks.filter(\.isActive)
        let blockedTasks = activeTasks.filter(\.isBlocked)
        if !blockedTasks.isEmpty {
            return ValidationPrCheck(
                id: "task-risk",
                label: "任务与风险 / Tasks",
                detail: "\(blockedTasks.count) 个任务仍阻塞。验证/PR 交接前需要完成、延期或拆分。",
                status: .blocked,
                systemImage: "checklist",
                path: workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md",
                action: .document("tasks")
            )
        }
        if !activeTasks.isEmpty || !workspace.risks.isEmpty {
            return ValidationPrCheck(
                id: "task-risk",
                label: "任务与风险 / Tasks",
                detail: "\(activeTasks.count) 个活跃任务，\(workspace.risks.count) 个风险信号。PR 交接中需要写明结论。",
                status: .review,
                systemImage: "exclamationmark.triangle",
                path: workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md",
                action: .validationHandoff
            )
        }
        return ValidationPrCheck(
            id: "task-risk",
            label: "任务与风险 / Tasks",
            detail: "任务已清理，暂无活动风险。",
            status: .ready,
            systemImage: "checkmark.shield",
            path: workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md",
            action: .document("tasks")
        )
    }

    private static func prCiCheck(workspace: WorkspaceSummary) -> ValidationPrCheck {
        let hasEvidence = hasPrCiEvidence(workspace: workspace)
        return ValidationPrCheck(
            id: "pr-ci",
            label: "PR / CI / 发布",
            detail: hasEvidence
                ? "已在活动、交付记录检查或生命周期上下文中发现 PR、CI、验证或发布证据。"
                : "尚未发现 PR、CI、发布或最终验证结论。没有 GitHub 集成前，把这些结论写入交付记录或 PR 交接。",
            status: hasEvidence ? .ready : .review,
            systemImage: hasEvidence ? "checkmark.seal" : "point.3.connected.trianglepath.dotted",
            path: workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md",
            action: hasEvidence ? .document("delivery") : .validationHandoff
        )
    }

    private static func lifecycleCheck(workspace: WorkspaceSummary) -> ValidationPrCheck {
        switch workspace.lifecycle.stage.lowercased() {
        case "done":
            return ValidationPrCheck(
                id: "lifecycle",
                label: "生命周期 / Lifecycle",
                detail: "生命周期已标记完成，可以进入 PR/CI 复核或归档确认。",
                status: .ready,
                systemImage: "checkmark.seal",
                path: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md",
                action: .lifecycle(.archived)
            )
        case "delivery":
            return ValidationPrCheck(
                id: "lifecycle",
                label: "生命周期 / Lifecycle",
                detail: "当前仍处于交付整理阶段。验证结论确认后再标记完成。",
                status: .next,
                systemImage: "arrow.right.circle",
                path: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md",
                action: .lifecycle(.done)
            )
        default:
            return ValidationPrCheck(
                id: "lifecycle",
                label: "生命周期 / Lifecycle",
                detail: "生命周期尚未进入交付完成链路，先完成交付整理。",
                status: .next,
                systemImage: "shippingbox",
                path: workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md",
                action: .lifecycle(.delivery)
            )
        }
    }

    private static func hasPrCiEvidence(workspace: WorkspaceSummary) -> Bool {
        let activityText = workspace.activities
            .map { "\($0.title) \($0.detail)" }
            .joined(separator: "\n")
        let checkText = workspace.healthChecks
            .map { "\($0.label) \($0.detail)" }
            .joined(separator: "\n")
        let text = "\(activityText)\n\(checkText)\n\(workspace.lifecycle.detail)"
        let lowercased = text.lowercased()
        let caseSensitiveMarkers = ["PR", "CI", "GitHub"]
        let lowerMarkers = ["pull request", "merged", "ci passed", "合并", "已合并", "构建通过", "验证通过", "发布", "上线"]
        return caseSensitiveMarkers.contains { text.contains($0) }
            || lowerMarkers.contains { lowercased.contains($0) }
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
}

struct ValidationPrWritePlanItem: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let evidencePath: String?
}

struct ValidationPrWritePlan: Identifiable, Hashable {
    let id: String
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let deliveryPath: String
    let status: WorkflowPathStatus
    let summary: String
    let items: [ValidationPrWritePlanItem]
    let appendedMarkdown: String

    var canWrite: Bool {
        status != .archived && !appendedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func resolve(workspace: WorkspaceSummary, evidence: ValidationPrEvidence) -> ValidationPrWritePlan {
        let deliveryPath = workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md"
        let id = "\(workspace.id)-validation-pr"

        guard evidence.status != .archived else {
            return ValidationPrWritePlan(
                id: id,
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                deliveryPath: deliveryPath,
                status: .archived,
                summary: "已归档工作区默认只读；恢复开发后再追加验证/PR 结论。",
                items: [],
                appendedMarkdown: ""
            )
        }

        let items = evidence.checks.map { check in
            ValidationPrWritePlanItem(
                id: check.id,
                label: check.label,
                detail: check.detail,
                status: check.status,
                evidencePath: check.path
            )
        }
        return ValidationPrWritePlan(
            id: id,
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            deliveryPath: deliveryPath,
            status: evidence.status == .ready ? .next : evidence.status,
            summary: "确认后只会向交付记录追加当前验证/PR 复核快照，不会调用 GitHub 或写回生命周期。",
            items: items,
            appendedMarkdown: validationPrMarkdown(workspace: workspace, evidence: evidence, items: items)
        )
    }

    private static func validationPrMarkdown(
        workspace: WorkspaceSummary,
        evidence: ValidationPrEvidence,
        items: [ValidationPrWritePlanItem]
    ) -> String {
        var lines = [
            "",
            "## Nexus Validation / PR Snapshot",
            "",
            "- 工作区：\(workspace.name)",
            "- 生命周期：\(workspace.lifecycle.stage)",
            "- 验证状态：\(evidence.status.displayLabel)",
            "- 下一步：\(evidence.primaryActionLabel)",
            "- 说明：\(evidence.reason)",
            "",
            "| 检查项 | 状态 | 证据 | 说明 |",
            "| --- | --- | --- | --- |"
        ]

        for item in items {
            lines.append("| \(escapeMarkdownCell(item.label)) | \(item.status.displayLabel) | \(escapeMarkdownCell(item.evidencePath ?? "-")) | \(escapeMarkdownCell(item.detail)) |")
        }

        lines.append(contentsOf: [
            "",
            "- 写入来源：Nexus Native confirmed write。",
            "- 集成边界：本记录不直接调用 GitHub；PR、CI、发布或遗留风险结论仍以交付记录和人工链接为准。"
        ])
        return lines.joined(separator: "\n")
    }

    private static func escapeMarkdownCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "|", with: "\\|")
            .replacingOccurrences(of: "\n", with: " ")
    }
}
