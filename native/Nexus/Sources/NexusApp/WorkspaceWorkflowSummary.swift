import Foundation

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
