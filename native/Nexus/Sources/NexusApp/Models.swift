import Foundation
import NexusBridge

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
    let worktreeExists: Bool
    let sourceExists: Bool
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
    let services: [ServiceStatus]
    let activities: [ActivityEvent]
    let risks: [RiskAlert]
    let healthChecks: [WorkspaceHealthCheck]
    let sessionActions: [WorkspaceSessionAction]

    var serviceSummary: String {
        services.map(\.name).joined(separator: ", ")
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
        services: [ServiceStatus],
        activities: [ActivityEvent],
        risks: [RiskAlert],
        healthChecks: [WorkspaceHealthCheck] = [],
        sessionActions: [WorkspaceSessionAction] = []
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
        self.services = services
        self.activities = activities
        self.risks = risks
        self.healthChecks = healthChecks
        self.sessionActions = sessionActions
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
            services: services,
            activities: activities,
            risks: risks,
            healthChecks: healthChecks,
            sessionActions: sessionActions
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
            services: services,
            activities: Array(([activity] + activities).prefix(6)),
            risks: risks,
            healthChecks: healthChecks,
            sessionActions: sessionActions
        )
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
