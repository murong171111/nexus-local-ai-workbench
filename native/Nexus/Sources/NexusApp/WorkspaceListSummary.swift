import Foundation

struct WorkspaceListSummary: Hashable {
    let totalWorkspaceCount: Int
    let activeWorkspaceCount: Int
    let archivedWorkspaceCount: Int
    let riskyWorkspaceCount: Int
    let blockedWorkspaceCount: Int
    let openTaskCount: Int
    let highPriorityTaskCount: Int
    let missingWorktreeCount: Int
    let dirtyServiceCount: Int
    let deliveryWorkspaceCount: Int

    var archivedExclusionLabel: String {
        "归档 \(archivedWorkspaceCount) · 活跃统计已排除"
    }

    init(workspaces: [WorkspaceSummary]) {
        let activeWorkspaces = workspaces.filter { !$0.isArchived }
        let activeTasks = activeWorkspaces.flatMap(\.tasks).filter(\.isActive)
        let activeServices = activeWorkspaces.flatMap(\.services)

        totalWorkspaceCount = workspaces.count
        activeWorkspaceCount = activeWorkspaces.count
        archivedWorkspaceCount = workspaces.count - activeWorkspaces.count
        riskyWorkspaceCount = activeWorkspaces.filter { workspace in
            workspace.riskLevel == .high || workspace.riskLevel == .medium || !workspace.risks.isEmpty
        }.count
        blockedWorkspaceCount = activeWorkspaces.filter { workspace in
            workspace.state == .blocked || workspace.mainStage().status == .blocked
        }.count
        openTaskCount = activeTasks.count
        highPriorityTaskCount = activeTasks.filter { $0.priorityRank == 0 }.count
        missingWorktreeCount = activeServices.filter { !$0.worktreeExists }.count
        dirtyServiceCount = activeServices.filter(Self.serviceHasDirtyGit).count
        deliveryWorkspaceCount = activeWorkspaces.filter { workspace in
            workspace.mainStage().id == .deliveryCheck
        }.count
    }

    private static func serviceHasDirtyGit(_ service: ServiceStatus) -> Bool {
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
