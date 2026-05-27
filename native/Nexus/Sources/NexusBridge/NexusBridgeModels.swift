import Foundation

public struct ScanWorkspacesRequest: Codable, Equatable, Sendable {
    public let workspacesRoot: String
    public let sourceReposRoot: String
    public let docsRoot: String
    public let auditRoot: String?

    public init(
        workspacesRoot: String,
        sourceReposRoot: String,
        docsRoot: String,
        auditRoot: String? = nil
    ) {
        self.workspacesRoot = workspacesRoot
        self.sourceReposRoot = sourceReposRoot
        self.docsRoot = docsRoot
        self.auditRoot = auditRoot
    }
}

public struct ScanSourceReposRequest: Codable, Equatable, Sendable {
    public let sourceReposRoot: String

    public init(sourceReposRoot: String) {
        self.sourceReposRoot = sourceReposRoot
    }
}

public struct ReadDocumentRequest: Codable, Equatable, Sendable {
    public let path: String

    public init(path: String) {
        self.path = path
    }
}

public struct WidgetSnapshotRequest: Codable, Equatable, Sendable {
    public let workspacesRoot: String
    public let sourceReposRoot: String
    public let docsRoot: String
    public let activeFolder: String
    public let generatedAt: String

    public init(
        workspacesRoot: String,
        sourceReposRoot: String,
        docsRoot: String,
        activeFolder: String,
        generatedAt: String
    ) {
        self.workspacesRoot = workspacesRoot
        self.sourceReposRoot = sourceReposRoot
        self.docsRoot = docsRoot
        self.activeFolder = activeFolder
        self.generatedAt = generatedAt
    }
}

public struct CreateWorkspaceRequest: Codable, Equatable, Sendable {
    public let name: String
    public let folder: String
    public let workspacesRoot: String
    public let sourceReposRoot: String
    public let services: [String]
    public let targetBranch: String
    public let confirmed: Bool
    public let auditRoot: String?
    public let actor: String?

    public init(
        name: String,
        folder: String,
        workspacesRoot: String,
        sourceReposRoot: String,
        services: [String],
        targetBranch: String,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil
    ) {
        self.name = name
        self.folder = folder
        self.workspacesRoot = workspacesRoot
        self.sourceReposRoot = sourceReposRoot
        self.services = services
        self.targetBranch = targetBranch
        self.confirmed = confirmed
        self.auditRoot = auditRoot
        self.actor = actor
    }
}

public struct CreateWorkspaceResponse: Codable, Equatable, Sendable {
    public let path: String
    public let folder: String

    public init(path: String, folder: String) {
        self.path = path
        self.folder = folder
    }
}

public struct SetupWorktreesRequest: Codable, Equatable, Sendable {
    public let workspacePath: String
    public let sourceReposRoot: String
    public let services: [String]
    public let targetBranch: String
    public let confirmed: Bool
    public let auditRoot: String?
    public let actor: String?

    public init(
        workspacePath: String,
        sourceReposRoot: String,
        services: [String],
        targetBranch: String,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil
    ) {
        self.workspacePath = workspacePath
        self.sourceReposRoot = sourceReposRoot
        self.services = services
        self.targetBranch = targetBranch
        self.confirmed = confirmed
        self.auditRoot = auditRoot
        self.actor = actor
    }
}

public struct SetupWorktreesResponse: Codable, Equatable, Sendable {
    public let workspacePath: String
    public let targetBranch: String
    public let command: String
    public let created: [WorktreeSetupResult]
    public let skipped: [WorktreeSetupResult]
    public let failed: [WorktreeSetupResult]

    public init(
        workspacePath: String,
        targetBranch: String,
        command: String,
        created: [WorktreeSetupResult],
        skipped: [WorktreeSetupResult],
        failed: [WorktreeSetupResult]
    ) {
        self.workspacePath = workspacePath
        self.targetBranch = targetBranch
        self.command = command
        self.created = created
        self.skipped = skipped
        self.failed = failed
    }
}

public struct WorktreeSetupResult: Codable, Equatable, Sendable {
    public let service: String
    public let sourcePath: String
    public let worktreePath: String
    public let status: String
    public let detail: String

    public init(
        service: String,
        sourcePath: String,
        worktreePath: String,
        status: String,
        detail: String
    ) {
        self.service = service
        self.sourcePath = sourcePath
        self.worktreePath = worktreePath
        self.status = status
        self.detail = detail
    }
}

public struct AppendAuditEventRequest: Codable, Equatable, Sendable {
    public let auditRoot: String
    public let event: AuditEventInput

    public init(auditRoot: String, event: AuditEventInput) {
        self.auditRoot = auditRoot
        self.event = event
    }
}

public struct AuditEventInput: Codable, Equatable, Sendable {
    public let actor: String
    public let action: String
    public let target: String
    public let summary: String
    public let metadata: [String: String]

    public init(
        actor: String,
        action: String,
        target: String,
        summary: String,
        metadata: [String: String] = [:]
    ) {
        self.actor = actor
        self.action = action
        self.target = target
        self.summary = summary
        self.metadata = metadata
    }
}

public struct AuditEvent: Codable, Equatable, Sendable {
    public let id: String
    public let timestamp: String
    public let actor: String
    public let action: String
    public let target: String
    public let summary: String
    public let metadata: [String: String]

    public init(
        id: String,
        timestamp: String,
        actor: String,
        action: String,
        target: String,
        summary: String,
        metadata: [String: String]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.actor = actor
        self.action = action
        self.target = target
        self.summary = summary
        self.metadata = metadata
    }
}

public struct AppendAuditEventResponse: Codable, Equatable, Sendable {
    public let path: String
    public let event: AuditEvent

    public init(path: String, event: AuditEvent) {
        self.path = path
        self.event = event
    }
}

public struct AppendAgentEventRequest: Codable, Equatable, Sendable {
    public let eventsRoot: String
    public let event: AgentEventInput

    public init(eventsRoot: String, event: AgentEventInput) {
        self.eventsRoot = eventsRoot
        self.event = event
    }
}

public struct ReadAgentEventsRequest: Codable, Equatable, Sendable {
    public let eventsRoot: String
    public let limit: Int?
    public let workspaceFolder: String?

    public init(eventsRoot: String, limit: Int? = nil, workspaceFolder: String? = nil) {
        self.eventsRoot = eventsRoot
        self.limit = limit
        self.workspaceFolder = workspaceFolder
    }
}

public struct AgentEventInput: Codable, Equatable, Sendable {
    public let source: String
    public let sessionId: String
    public let workspaceFolder: String?
    public let kind: String
    public let title: String
    public let summary: String
    public let severity: String
    public let metadata: [String: String]

    public init(
        source: String,
        sessionId: String,
        workspaceFolder: String? = nil,
        kind: String,
        title: String,
        summary: String,
        severity: String,
        metadata: [String: String] = [:]
    ) {
        self.source = source
        self.sessionId = sessionId
        self.workspaceFolder = workspaceFolder
        self.kind = kind
        self.title = title
        self.summary = summary
        self.severity = severity
        self.metadata = metadata
    }
}

public struct AgentEvent: Codable, Equatable, Sendable {
    public let id: String
    public let timestamp: String
    public let source: String
    public let sessionId: String
    public let workspaceFolder: String?
    public let kind: String
    public let title: String
    public let summary: String
    public let severity: String
    public let metadata: [String: String]

    public init(
        id: String,
        timestamp: String,
        source: String,
        sessionId: String,
        workspaceFolder: String? = nil,
        kind: String,
        title: String,
        summary: String,
        severity: String,
        metadata: [String: String] = [:]
    ) {
        self.id = id
        self.timestamp = timestamp
        self.source = source
        self.sessionId = sessionId
        self.workspaceFolder = workspaceFolder
        self.kind = kind
        self.title = title
        self.summary = summary
        self.severity = severity
        self.metadata = metadata
    }
}

public struct AppendAgentEventResponse: Codable, Equatable, Sendable {
    public let path: String
    public let event: AgentEvent

    public init(path: String, event: AgentEvent) {
        self.path = path
        self.event = event
    }
}

public struct RebuildSearchIndexRequest: Codable, Equatable, Sendable {
    public let indexPath: String
    public let workspacesRoot: String
    public let sourceReposRoot: String
    public let docsRoot: String

    public init(indexPath: String, workspacesRoot: String, sourceReposRoot: String, docsRoot: String) {
        self.indexPath = indexPath
        self.workspacesRoot = workspacesRoot
        self.sourceReposRoot = sourceReposRoot
        self.docsRoot = docsRoot
    }
}

public struct RebuildSearchIndexResponse: Codable, Equatable, Sendable {
    public let path: String
    public let workspaceCount: Int
    public let documentCount: Int

    public init(path: String, workspaceCount: Int, documentCount: Int) {
        self.path = path
        self.workspaceCount = workspaceCount
        self.documentCount = documentCount
    }
}

public struct SearchIndexRequest: Codable, Equatable, Sendable {
    public let indexPath: String
    public let query: String
    public let limit: Int?

    public init(indexPath: String, query: String, limit: Int? = nil) {
        self.indexPath = indexPath
        self.query = query
        self.limit = limit
    }
}

public struct SearchResult: Codable, Equatable, Sendable {
    public let workspaceFolder: String
    public let workspaceName: String
    public let documentKey: String
    public let documentName: String
    public let documentPath: String
    public let kind: String
    public let snippet: String

    public init(
        workspaceFolder: String,
        workspaceName: String,
        documentKey: String,
        documentName: String,
        documentPath: String,
        kind: String,
        snippet: String
    ) {
        self.workspaceFolder = workspaceFolder
        self.workspaceName = workspaceName
        self.documentKey = documentKey
        self.documentName = documentName
        self.documentPath = documentPath
        self.kind = kind
        self.snippet = snippet
    }
}

public struct DashboardSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let workspacesRoot: String
    public let sourceReposRoot: String
    public let docsRoot: String
    public let workspaces: [WorkspaceSnapshot]

    public init(
        generatedAt: String,
        workspacesRoot: String,
        sourceReposRoot: String,
        docsRoot: String,
        workspaces: [WorkspaceSnapshot]
    ) {
        self.generatedAt = generatedAt
        self.workspacesRoot = workspacesRoot
        self.sourceReposRoot = sourceReposRoot
        self.docsRoot = docsRoot
        self.workspaces = workspaces
    }
}

public struct WorkspaceSnapshot: Codable, Equatable, Sendable {
    public let name: String
    public let folder: String
    public let path: String
    public let state: String
    public let targetBranch: String
    public let sourceRoot: String
    public let confirmedServices: [String]
    public let candidateServices: [String]
    public let taskCounts: TaskCountsSnapshot
    public let decisionCount: Int
    public let gitRows: [GitRowSnapshot]
    public let risks: [String]
    public let riskCount: Int
    public let updated: String
    public let links: [String: String]
    public let worktreeCommand: String
    public let activities: [WorkspaceActivitySnapshot]?
    public let healthChecks: [WorkspaceHealthCheckSnapshot]?
    public let sessionActions: [WorkspaceSessionActionSnapshot]?

    public init(
        name: String,
        folder: String,
        path: String,
        state: String,
        targetBranch: String,
        sourceRoot: String,
        confirmedServices: [String],
        candidateServices: [String],
        taskCounts: TaskCountsSnapshot,
        decisionCount: Int,
        gitRows: [GitRowSnapshot],
        risks: [String],
        riskCount: Int,
        updated: String,
        links: [String: String],
        worktreeCommand: String,
        activities: [WorkspaceActivitySnapshot]? = nil,
        healthChecks: [WorkspaceHealthCheckSnapshot]? = nil,
        sessionActions: [WorkspaceSessionActionSnapshot]? = nil
    ) {
        self.name = name
        self.folder = folder
        self.path = path
        self.state = state
        self.targetBranch = targetBranch
        self.sourceRoot = sourceRoot
        self.confirmedServices = confirmedServices
        self.candidateServices = candidateServices
        self.taskCounts = taskCounts
        self.decisionCount = decisionCount
        self.gitRows = gitRows
        self.risks = risks
        self.riskCount = riskCount
        self.updated = updated
        self.links = links
        self.worktreeCommand = worktreeCommand
        self.activities = activities
        self.healthChecks = healthChecks
        self.sessionActions = sessionActions
    }
}

public struct WorkspaceHealthCheckSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let detail: String
    public let status: String
    public let action: String

    public init(id: String, label: String, detail: String, status: String, action: String) {
        self.id = id
        self.label = label
        self.detail = detail
        self.status = status
        self.action = action
    }
}

public struct WorkspaceSessionActionSnapshot: Codable, Equatable, Sendable {
    public let id: String
    public let label: String
    public let detail: String
    public let priority: String
    public let status: String
    public let instructionType: String
    public let documentKey: String

    public init(
        id: String,
        label: String,
        detail: String,
        priority: String,
        status: String,
        instructionType: String,
        documentKey: String
    ) {
        self.id = id
        self.label = label
        self.detail = detail
        self.priority = priority
        self.status = status
        self.instructionType = instructionType
        self.documentKey = documentKey
    }
}

public struct WorkspaceActivitySnapshot: Codable, Equatable, Sendable {
    public let time: String
    public let title: String
    public let detail: String

    public init(time: String, title: String, detail: String) {
        self.time = time
        self.title = title
        self.detail = detail
    }
}

public struct TaskCountsSnapshot: Codable, Equatable, Sendable {
    public let done: Int
    public let doing: Int
    public let todo: Int
    public let blocked: Int

    public init(done: Int, doing: Int, todo: Int, blocked: Int) {
        self.done = done
        self.doing = doing
        self.todo = todo
        self.blocked = blocked
    }
}

public struct GitRowSnapshot: Codable, Equatable, Sendable {
    public let service: String
    public let worktreePath: String
    public let sourcePath: String
    public let worktree: GitStatusSnapshot
    public let source: GitStatusSnapshot

    public init(
        service: String,
        worktreePath: String,
        sourcePath: String,
        worktree: GitStatusSnapshot,
        source: GitStatusSnapshot
    ) {
        self.service = service
        self.worktreePath = worktreePath
        self.sourcePath = sourcePath
        self.worktree = worktree
        self.source = source
    }
}

public struct GitStatusSnapshot: Codable, Equatable, Sendable {
    public let exists: Bool
    public let branch: String
    public let dirty: Bool
    public let summary: String

    public init(exists: Bool, branch: String, dirty: Bool, summary: String) {
        self.exists = exists
        self.branch = branch
        self.dirty = dirty
        self.summary = summary
    }
}

public struct SourceRepositorySnapshot: Codable, Equatable, Sendable {
    public let name: String
    public let path: String
    public let isGit: Bool
    public let branch: String
    public let dirty: Bool
    public let summary: String

    public init(name: String, path: String, isGit: Bool, branch: String, dirty: Bool, summary: String) {
        self.name = name
        self.path = path
        self.isGit = isGit
        self.branch = branch
        self.dirty = dirty
        self.summary = summary
    }
}

public struct DocumentSnapshot: Codable, Equatable, Sendable {
    public let path: String
    public let name: String
    public let `extension`: String
    public let isMarkdown: Bool
    public let content: String

    public init(path: String, name: String, extension: String, isMarkdown: Bool, content: String) {
        self.path = path
        self.name = name
        self.extension = `extension`
        self.isMarkdown = isMarkdown
        self.content = content
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let generatedAt: String
    public let workspacesRoot: String
    public let activeWorkspace: String?
    public let activeWorkspaceFolder: String?
    public let workspaceCount: Int
    public let riskCount: Int
    public let dirtyServiceCount: Int
    public let missingWorktreeCount: Int
    public let topRisks: [String]
    public let deepLink: String

    public init(
        generatedAt: String,
        workspacesRoot: String,
        activeWorkspace: String?,
        activeWorkspaceFolder: String?,
        workspaceCount: Int,
        riskCount: Int,
        dirtyServiceCount: Int,
        missingWorktreeCount: Int,
        topRisks: [String],
        deepLink: String
    ) {
        self.generatedAt = generatedAt
        self.workspacesRoot = workspacesRoot
        self.activeWorkspace = activeWorkspace
        self.activeWorkspaceFolder = activeWorkspaceFolder
        self.workspaceCount = workspaceCount
        self.riskCount = riskCount
        self.dirtyServiceCount = dirtyServiceCount
        self.missingWorktreeCount = missingWorktreeCount
        self.topRisks = topRisks
        self.deepLink = deepLink
    }
}

public extension DashboardSnapshot {
    static func preview(
        workspacesRoot: String,
        sourceReposRoot: String,
        docsRoot: String
    ) -> DashboardSnapshot {
        DashboardSnapshot(
            generatedAt: "preview",
            workspacesRoot: workspacesRoot,
            sourceReposRoot: sourceReposRoot,
            docsRoot: docsRoot,
            workspaces: [
                WorkspaceSnapshot(
                    name: "易宝对账补充 pay_log",
                    folder: "2026-05-25-yibao-pay-log",
                    path: "\(workspacesRoot)/2026-05-25-yibao-pay-log",
                    state: "developing",
                    targetBranch: "feature/yibao-pay-log",
                    sourceRoot: sourceReposRoot,
                    confirmedServices: ["order", "store-cashier", "commodity"],
                    candidateServices: [],
                    taskCounts: TaskCountsSnapshot(done: 2, doing: 1, todo: 2, blocked: 0),
                    decisionCount: 1,
                    gitRows: [
                        GitRowSnapshot(
                            service: "order",
                            worktreePath: "\(workspacesRoot)/2026-05-25-yibao-pay-log/repos/order",
                            sourcePath: "\(sourceReposRoot)/order",
                            worktree: GitStatusSnapshot(exists: true, branch: "feature/yibao-pay-log", dirty: false, summary: "clean"),
                            source: GitStatusSnapshot(exists: true, branch: "master", dirty: false, summary: "clean")
                        ),
                        GitRowSnapshot(
                            service: "store-cashier",
                            worktreePath: "\(workspacesRoot)/2026-05-25-yibao-pay-log/repos/store-cashier",
                            sourcePath: "\(sourceReposRoot)/store-cashier",
                            worktree: GitStatusSnapshot(exists: true, branch: "feature/yibao-pay-log", dirty: true, summary: "dirty"),
                            source: GitStatusSnapshot(exists: true, branch: "master", dirty: false, summary: "clean")
                        ),
                        GitRowSnapshot(
                            service: "commodity",
                            worktreePath: "\(workspacesRoot)/2026-05-25-yibao-pay-log/repos/commodity",
                            sourcePath: "\(sourceReposRoot)/commodity",
                            worktree: GitStatusSnapshot(exists: false, branch: "未创建", dirty: false, summary: "未创建"),
                            source: GitStatusSnapshot(exists: true, branch: "master", dirty: false, summary: "clean")
                        )
                    ],
                    risks: ["worktree 未创建: commodity", "交付记录待补充"],
                    riskCount: 2,
                    updated: "preview",
                    links: [:],
                    worktreeCommand: "git worktree add ...",
                    activities: [
                        WorkspaceActivitySnapshot(
                            time: "preview",
                            title: "工作区已创建 / Workspace created",
                            detail: "Nexus Preview · Created preview workspace"
                        )
                    ],
                    healthChecks: [
                        WorkspaceHealthCheckSnapshot(
                            id: "worktree-ready",
                            label: "Worktree 就绪 / Worktree ready",
                            detail: "缺少: commodity",
                            status: "fail",
                            action: "worktreeScript"
                        ),
                        WorkspaceHealthCheckSnapshot(
                            id: "delivery-record",
                            label: "交付记录 / Delivery record",
                            detail: "交付记录仍包含待补充内容",
                            status: "warning",
                            action: "delivery"
                        )
                    ],
                    sessionActions: [
                        WorkspaceSessionActionSnapshot(
                            id: "create-worktrees",
                            label: "创建缺失 worktree / Create worktrees",
                            detail: "缺少 worktree: commodity",
                            priority: "high",
                            status: "recommended",
                            instructionType: "worktree",
                            documentKey: "worktreeScript"
                        ),
                        WorkspaceSessionActionSnapshot(
                            id: "start-codex-session",
                            label: "启动 Codex 会话 / Start Codex session",
                            detail: "复制当前工作区上下文，带着上方动作进入 Codex 继续处理。",
                            priority: "low",
                            status: "recommended",
                            instructionType: "continue",
                            documentKey: "handoff"
                        )
                    ]
                )
            ]
        )
    }
}

public extension WidgetSnapshot {
    static func preview(
        dashboard: DashboardSnapshot,
        activeFolder: String,
        generatedAt: String
    ) -> WidgetSnapshot {
        let activeWorkspace = dashboard.workspaces.first { $0.folder == activeFolder } ?? dashboard.workspaces.first
        let allGitRows = dashboard.workspaces.flatMap(\.gitRows)
        let riskTotal = dashboard.workspaces.reduce(0) { sum, workspace in
            sum + workspace.riskCount
        }
        let topRisks = dashboard.workspaces
            .flatMap { workspace in
                workspace.risks.map { risk in "\(workspace.name): \(risk)" }
            }
            .prefix(3)

        return WidgetSnapshot(
            generatedAt: generatedAt,
            workspacesRoot: dashboard.workspacesRoot,
            activeWorkspace: activeWorkspace?.name,
            activeWorkspaceFolder: activeWorkspace?.folder,
            workspaceCount: dashboard.workspaces.count,
            riskCount: riskTotal,
            dirtyServiceCount: allGitRows.filter(\.worktree.dirty).count,
            missingWorktreeCount: allGitRows.filter { !$0.worktree.exists }.count,
            topRisks: Array(topRisks),
            deepLink: activeWorkspace.map { "nexus://workspace/\($0.folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? $0.folder)" } ?? "nexus://"
        )
    }
}
