import Foundation
import NexusBridge

enum NativeSearchIndexStore {
    static func fallbackResults(
        matching query: String,
        in workspaces: [WorkspaceSummary],
        limit: Int = 10
    ) -> [SearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        return workspaces.compactMap { workspace in
            let haystack = [
                workspace.name,
                workspace.folder,
                workspace.branch,
                workspace.aiState,
                workspace.serviceSummary,
                workspace.worktreeState,
                workspace.tasks.map(\.title).joined(separator: " "),
                workspace.tasks.map(\.detail).joined(separator: " "),
                workspace.risks.map(\.detail).joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()

            guard haystack.contains(normalizedQuery) else { return nil }

            let riskSummary = workspace.risks.first?.detail ?? "暂无风险"
            let serviceSummary = workspace.serviceSummary.isEmpty ? "服务待确认" : workspace.serviceSummary
            return SearchResult(
                workspaceFolder: workspace.folder,
                workspaceName: workspace.name,
                documentKey: "workspace",
                documentName: "Workspace metadata",
                documentPath: workspace.path,
                kind: "workspace",
                snippet: "\(workspace.branch) · \(serviceSummary) · \(riskSummary)"
            )
        }
        .prefix(limit)
        .map { $0 }
    }
}
