import Foundation

enum FeatureWorkspacePresentation {
    enum Phase: CaseIterable, Equatable {
        case editing
        case waiting
        case proposalReady
        case proposalInvalid
        case confirmed

        var label: String {
            switch self {
            case .editing: "填写需求"
            case .waiting: "已交接"
            case .proposalReady: "审阅功能点"
            case .proposalInvalid: "提案需修正"
            case .confirmed: "开始开发"
            }
        }

        var demandIsExpanded: Bool { self == .editing }
        var proposalIsVisible: Bool { self == .proposalReady || self == .proposalInvalid }
        var showsConfirmedFeatures: Bool { self == .confirmed }
        var prominentActionCount: Int { 1 }
    }

    struct Recovery: Equatable {
        let factsChanged: Bool
        let message: String
    }

    static func phase(
        hasConfirmedFeatures: Bool,
        didHandoff: Bool,
        review: FeatureProposalReview?
    ) -> Phase {
        if didHandoff { return .waiting }
        if review?.diff != nil { return .proposalReady }
        if let error = review?.error,
           !error.contains("feature proposal draft is missing") {
            return .proposalInvalid
        }
        if hasConfirmedFeatures { return .confirmed }
        return .editing
    }

    static func recovery(for phase: Phase) -> Recovery {
        switch phase {
        case .waiting:
            Recovery(
                factsChanged: false,
                message: "需求、链接和材料已保留；FEATURES.md 未更改。"
            )
        case .proposalInvalid:
            Recovery(
                factsChanged: false,
                message: "需求和提案草稿已保留；FEATURES.md 未更改。"
            )
        case .editing, .proposalReady, .confirmed:
            Recovery(factsChanged: false, message: "FEATURES.md 未更改。")
        }
    }

    static func keepsWaitingAfterRefresh(
        wasWaiting: Bool,
        review: FeatureProposalReview?
    ) -> Bool {
        guard wasWaiting, let review else { return wasWaiting }
        guard review.diff == nil else { return false }
        return review.error?.contains("feature proposal draft is missing") == true
    }
}

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

enum WorkspaceConsoleSurface: Hashable {
    case featureDemand
    case development
    case delivery
    case archive

    init(_ stageGroup: WorkspaceConsoleStageGroup) {
        switch stageGroup {
        case .created, .demandAndFeatures:
            self = .featureDemand
        case .development:
            self = .development
        case .delivery:
            self = .delivery
        case .archive:
            self = .archive
        }
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
    let surface: WorkspaceConsoleSurface
    let reason: String
    let primaryActions: [WorkspaceMainStageAction]

    static func make(for workspace: WorkspaceSummary) -> Self {
        make(stage: workspace.mainStage())
    }

    static func make(stage: WorkspaceMainStage) -> Self {
        let stageGroup = WorkspaceConsoleStageGroup(stage: stage)
        return Self(
            stage: stageGroup,
            surface: WorkspaceConsoleSurface(stageGroup),
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
