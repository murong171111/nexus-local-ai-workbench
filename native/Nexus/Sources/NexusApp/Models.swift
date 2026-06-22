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

    var rank: Int {
        switch self {
        case .high:
            0
        case .medium:
            1
        case .low:
            2
        }
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
            return [.restoreDevelopment]
        default:
            return [.developing, .delivery, .blocked]
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
