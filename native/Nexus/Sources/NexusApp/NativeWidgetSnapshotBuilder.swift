import Foundation
import NexusBridge

enum NativeWidgetSnapshotBuilder {
    static func build(
        generatedAt: String,
        workspacesRoot: String,
        workspaces: [WorkspaceSummary],
        activeWorkspaceID: WorkspaceSummary.ID?
    ) -> WidgetSnapshot {
        let activeWorkspace = workspaces.first { $0.id == activeWorkspaceID }
            ?? workspaces.first { $0.folder == activeWorkspaceID }
            ?? workspaces.first
        let summary = WorkspaceListSummary(workspaces: workspaces)
        let activeStageAnswer = activeWorkspace?.mainStage().answer

        return WidgetSnapshot(
            generatedAt: generatedAt,
            workspacesRoot: workspacesRoot,
            activeWorkspace: activeWorkspace?.name,
            activeWorkspaceFolder: activeWorkspace?.folder,
            workspaceCount: workspaces.count,
            riskCount: workspaces.reduce(0) { $0 + $1.risks.count },
            dirtyServiceCount: summary.dirtyServiceCount,
            missingWorktreeCount: summary.missingWorktreeCount,
            topRisks: topRisks(from: workspaces),
            mainStage: activeStageAnswer?.stageLabel,
            mainStageStatus: activeStageAnswer?.status.displayLabel,
            mainStageBlockerSummary: activeStageAnswer?.blockerSummary,
            mainStageNextAction: activeStageAnswer?.nextActionLabel,
            mainStageEvidence: activeStageAnswer?.primaryEvidenceLink?.label,
            deepLink: activeWorkspace.map { deepLink(for: $0) } ?? "nexus://"
        )
    }

    private static func topRisks(from workspaces: [WorkspaceSummary]) -> [String] {
        Array(
            workspaces.flatMap { workspace in
                workspace.risks.map { "\(workspace.name): \($0.detail)" }
            }
            .prefix(3)
        )
    }

    private static func deepLink(for workspace: WorkspaceSummary) -> String {
        let encodedFolder = workspace.folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? workspace.folder
        return "nexus://workspace/\(encodedFolder)"
    }
}
