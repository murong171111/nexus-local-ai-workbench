import Foundation

enum WorkspaceFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case active = "进行中"
    case risky = "有风险"
    case blocked = "阻塞"

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
        }
    }
}

enum WorkspaceState: String, Hashable {
    case analyzing = "analyzing"
    case developing = "developing"
    case ready = "ready"
    case blocked = "blocked"

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

struct ServiceStatus: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let branch: String
    let worktree: String
    let gitSummary: String
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
    let services: [ServiceStatus]
    let activities: [ActivityEvent]
    let risks: [RiskAlert]

    var serviceSummary: String {
        services.map(\.name).joined(separator: ", ")
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
            services: [
                ServiceStatus(name: "order", branch: "feature/yibao-pay-log", worktree: "ready", gitSummary: "clean"),
                ServiceStatus(name: "store-cashier", branch: "feature/yibao-pay-log", worktree: "ready", gitSummary: "dirty"),
                ServiceStatus(name: "commodity", branch: "master", worktree: "missing", gitSummary: "source clean")
            ],
            activities: [
                ActivityEvent(time: "09:42", title: "交付记录待补充", detail: "新增 pay_log 回填逻辑后需要补齐 SQL 与验证说明"),
                ActivityEvent(time: "09:18", title: "Branch alignment checked", detail: "order and store-cashier are aligned")
            ],
            risks: [
                RiskAlert(title: "worktree 未创建", detail: "commodity 尚未建立需求 worktree"),
                RiskAlert(title: "交付记录待补充", detail: "交付记录仍包含占位内容")
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
            services: [
                ServiceStatus(name: "store", branch: "feature/pricing-snapshot", worktree: "ready", gitSummary: "clean"),
                ServiceStatus(name: "order", branch: "feature/pricing-snapshot", worktree: "ready", gitSummary: "clean")
            ],
            activities: [
                ActivityEvent(time: "08:40", title: "Workspace created", detail: "Standard Markdown skeleton generated"),
                ActivityEvent(time: "08:44", title: "AI context archived", detail: "AGENTS and handoff docs are available")
            ],
            risks: []
        )
    ]
}
