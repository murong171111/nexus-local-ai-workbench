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
            item.task.priorityRank == 0
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
        let openTasks = workspace.tasks.filter { !$0.isDone }
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
            return "\(openTaskCount) open tasks are ready"
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
            "Open tasks: \(openTaskCount)",
            "High-priority tasks: \(highPriorityTaskCount)",
            "Agent tasks: \(agentTaskCount)",
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

    var priorityRank: Int {
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

        let openTasks = tasks.filter { !$0.isDone }.count
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
                detail: "\(openTasks) 个开放任务需要继续处理。",
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
