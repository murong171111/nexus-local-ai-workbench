import Foundation

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
