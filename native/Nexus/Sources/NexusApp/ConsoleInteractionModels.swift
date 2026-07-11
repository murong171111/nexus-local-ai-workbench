import Foundation

enum WorkspaceConsoleTarget: String, Hashable {
    case demandInput
    case features
    case evidence

    static func resolve(action: WorkspaceMainStageAction) -> WorkspaceConsoleTarget? {
        switch action {
        case .demandIntake, .transferDemandTasks:
            .demandInput
        case .task:
            .features
        case .document, .path:
            .evidence
        default:
            nil
        }
    }
}

enum WorkspaceConsoleStageGroup: String, CaseIterable, Hashable {
    case created
    case demandAndFeatures
    case development
    case delivery
    case archive

    init(stage: WorkspaceMainStageID) {
        switch stage {
        case .created:
            self = .created
        case .demandIntake, .scopeFreeze, .serviceBranchConfirm:
            self = .demandAndFeatures
        case .worktreeSetup, .development:
            self = .development
        case .deliveryCheck:
            self = .delivery
        case .archived:
            self = .archive
        }
    }
}

struct WorkspaceConsoleLayoutPolicy: Hashable {
    let stageGroups = WorkspaceConsoleStageGroup.allCases
    let prominentPrimaryActionCount = 1
    let filesAreCollapsed = true
    let currentSignalsAreSecondary = true

    var auditSummary: WorkspaceConsoleLayoutAuditSummary {
        WorkspaceConsoleLayoutAuditSummary(
            stageGroups: stageGroups,
            prominentPrimaryActionCount: prominentPrimaryActionCount,
            filesAreCollapsed: filesAreCollapsed,
            currentSignalsAreSecondary: currentSignalsAreSecondary
        )
    }

    func focusesFeatureFlow(
        usesFeatureCenteredWorkflow: Bool,
        stageID: WorkspaceMainStageID
    ) -> Bool {
        usesFeatureCenteredWorkflow && (stageID == .created || stageID == .demandIntake)
    }
}

struct WorkspaceConsoleLayoutAuditSummary: Hashable {
    let stageGroups: [WorkspaceConsoleStageGroup]
    let prominentPrimaryActionCount: Int
    let filesAreCollapsed: Bool
    let currentSignalsAreSecondary: Bool
}
