import Combine
import Foundation
import NexusBridge

@MainActor
final class AppState: ObservableObject {
    @Published var query = ""
    @Published var selectedFilter: WorkspaceFilter = .all
    @Published var selectedWorkspaceID: WorkspaceSummary.ID?
    @Published var workspaces: [WorkspaceSummary]
    @Published var workspaceRoot: String
    @Published var sourceReposRoot: String
    @Published var docsRoot: String
    @Published var isLoading = false
    @Published var lastError: String?
    @Published var bridgeMode: String

    @Published var agentStatus: AgentStatus
    private let bridge: NexusBridge

    init(
        workspaces: [WorkspaceSummary],
        agentStatus: AgentStatus,
        bridge: NexusBridge,
        workspaceRoot: String = "~/ks_project/workspaces",
        sourceReposRoot: String = "~/ks_project/source-repos",
        docsRoot: String = "~/ks_project/docs",
        bridgeMode: String = "Preview"
    ) {
        self.workspaces = workspaces
        self.agentStatus = agentStatus
        self.bridge = bridge
        self.workspaceRoot = workspaceRoot
        self.sourceReposRoot = sourceReposRoot
        self.docsRoot = docsRoot
        self.bridgeMode = bridge.modeDescription.isEmpty ? bridgeMode : bridge.modeDescription
        self.selectedWorkspaceID = workspaces.first?.id
    }

    var selectedWorkspace: WorkspaceSummary? {
        workspaces.first { $0.id == selectedWorkspaceID } ?? filteredWorkspaces.first
    }

    var filteredWorkspaces: [WorkspaceSummary] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        return workspaces.filter { workspace in
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .active:
                matchesFilter = workspace.state == .developing || workspace.state == .analyzing
            case .risky:
                matchesFilter = workspace.riskLevel == .high || workspace.riskLevel == .medium
            case .blocked:
                matchesFilter = workspace.state == .blocked
            }

            guard matchesFilter else { return false }
            guard !trimmedQuery.isEmpty else { return true }

            let haystack = [
                workspace.name,
                workspace.folder,
                workspace.branch,
                workspace.aiState,
                workspace.serviceSummary,
                workspace.worktreeState
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(trimmedQuery)
        }
    }

    func select(_ workspace: WorkspaceSummary) {
        selectedWorkspaceID = workspace.id
    }

    func refreshFromBridge() async {
        isLoading = true
        lastError = nil
        defer {
            isLoading = false
        }

        do {
            let dashboard = try await bridge.scanWorkspaces(
                request: ScanWorkspacesRequest(
                    workspacesRoot: workspaceRoot,
                    sourceReposRoot: sourceReposRoot,
                    docsRoot: docsRoot
                )
            )
            let mappedWorkspaces = dashboard.workspaces.map(WorkspaceSummary.init(snapshot:))
            workspaces = mappedWorkspaces
            if selectedWorkspaceID == nil || !mappedWorkspaces.contains(where: { $0.id == selectedWorkspaceID }) {
                selectedWorkspaceID = mappedWorkspaces.first?.id
            }
            bridgeMode = bridge.modeDescription
            agentStatus = AgentStatus(
                title: "Ready",
                detail: "\(bridgeMode) · \(mappedWorkspaces.count) workspaces loaded",
                connectedTools: ["Codex", "Git", "Nexus Core"]
            )
        } catch {
            lastError = error.localizedDescription
            agentStatus = AgentStatus(
                title: "Bridge error",
                detail: error.localizedDescription,
                connectedTools: ["Nexus Core"]
            )
        }
    }

    static func preview() -> AppState {
        AppState(
            workspaces: WorkspaceSummary.previewData,
            agentStatus: AgentStatus(
                title: "Ready",
                detail: "Markdown, Git, and Workspace Core online",
                connectedTools: ["Codex", "Git", "Nexus Core"]
            ),
            bridge: NexusBridgeFactory.makeDefault()
        )
    }
}
