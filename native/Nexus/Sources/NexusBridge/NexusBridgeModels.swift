import Foundation

public struct ScanWorkspacesRequest: Codable, Equatable, Sendable {
    public let workspacesRoot: String
    public let sourceReposRoot: String
    public let docsRoot: String

    public init(workspacesRoot: String, sourceReposRoot: String, docsRoot: String) {
        self.workspacesRoot = workspacesRoot
        self.sourceReposRoot = sourceReposRoot
        self.docsRoot = docsRoot
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

    public init(
        name: String,
        folder: String,
        workspacesRoot: String,
        sourceReposRoot: String,
        services: [String],
        targetBranch: String,
        confirmed: Bool
    ) {
        self.name = name
        self.folder = folder
        self.workspacesRoot = workspacesRoot
        self.sourceReposRoot = sourceReposRoot
        self.services = services
        self.targetBranch = targetBranch
        self.confirmed = confirmed
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
        worktreeCommand: String
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
                    worktreeCommand: "git worktree add ..."
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
