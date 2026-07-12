import Foundation

enum NexusPrimarySurface: String, CaseIterable, Identifiable {
    case global
    case project

    var id: Self { self }

    var label: String {
        self == .global ? "全局" : "当前项目"
    }

    func isAvailable(hasSelection: Bool) -> Bool {
        self == .global || hasSelection
    }
}

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

    init(stage: WorkspaceMainStage) {
        self.init(stage: stage.id)
    }
}

enum WorkspaceConsoleUtilityPanel: String, CaseIterable, Identifiable {
    case features
    case filesAndSQL
    case evidenceAndChecks
    case changesAndHandoffs

    var id: Self { self }

    var label: String {
        switch self {
        case .features: "功能点"
        case .filesAndSQL: "文件与 SQL"
        case .evidenceAndChecks: "证据与检查"
        case .changesAndHandoffs: "变更与交接记录"
        }
    }

    var systemImage: String {
        switch self {
        case .features: "list.bullet.rectangle"
        case .filesAndSQL: "folder"
        case .evidenceAndChecks: "checkmark.seal"
        case .changesAndHandoffs: "clock.arrow.circlepath"
        }
    }
}

struct WorkspaceConsolePresentation {
    static let defaultUtilityPanel: WorkspaceConsoleUtilityPanel? = nil

    let stage: WorkspaceConsoleStageGroup
    let reason: String
    let primaryActions: [WorkspaceMainStageAction]

    static func make(for workspace: WorkspaceSummary) -> Self {
        make(stage: workspace.mainStage())
    }

    static func make(stage: WorkspaceMainStage) -> Self {
        Self(
            stage: WorkspaceConsoleStageGroup(stage: stage),
            reason: stage.reason,
            primaryActions: [stage.primaryAction]
        )
    }
}

struct WorkspaceConsoleLayoutPolicy: Hashable {
    let stageGroups = WorkspaceConsoleStageGroup.allCases
    let prominentPrimaryActionCount = 1
    let filesAreCollapsed = true
    let hasPermanentCurrentSignals = false

    var auditSummary: WorkspaceConsoleLayoutAuditSummary {
        WorkspaceConsoleLayoutAuditSummary(
            stageGroups: stageGroups,
            prominentPrimaryActionCount: prominentPrimaryActionCount,
            filesAreCollapsed: filesAreCollapsed,
            hasPermanentCurrentSignals: hasPermanentCurrentSignals
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
    let hasPermanentCurrentSignals: Bool
}
