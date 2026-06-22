import Foundation

struct WorkspaceBoardColumn: Hashable, Identifiable {
    let id: WorkspaceMainStageID
    let workspaces: [WorkspaceSummary]

    var title: String { id.label }
    var shortTitle: String { id.shortLabel }
    var systemImage: String { id.systemImage }
    var count: Int { workspaces.count }

    static let visibleStageOrder: [WorkspaceMainStageID] = [
        .created,
        .demandIntake,
        .scopeFreeze,
        .serviceBranchConfirm,
        .worktreeSetup,
        .development,
        .deliveryCheck,
        .archived
    ]

    static func columns(
        for workspaces: [WorkspaceSummary],
        scope: WorkspaceBoardScope = .all
    ) -> [WorkspaceBoardColumn] {
        let visibleWorkspaces = scope.filter(workspaces)
        let grouped = Dictionary(grouping: visibleWorkspaces) { workspace in
            workspace.mainStage().id
        }

        return visibleStageOrder.map { stageID in
            WorkspaceBoardColumn(
                id: stageID,
                workspaces: (grouped[stageID] ?? []).sorted(by: boardSort)
            )
        }
    }

    private static func boardSort(_ lhs: WorkspaceSummary, _ rhs: WorkspaceSummary) -> Bool {
        let lhsStage = lhs.mainStage()
        let rhsStage = rhs.mainStage()
        if lhsStage.status.boardPriority != rhsStage.status.boardPriority {
            return lhsStage.status.boardPriority < rhsStage.status.boardPriority
        }
        if lhs.riskLevel.rank != rhs.riskLevel.rank {
            return lhs.riskLevel.rank < rhs.riskLevel.rank
        }
        if lhs.folder != rhs.folder {
            return lhs.folder > rhs.folder
        }
        return lhs.name < rhs.name
    }
}

enum WorkspaceBoardScope: String, CaseIterable, Hashable, Identifiable {
    case all
    case attention
    case delivery
    case archived

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all:
            "全部"
        case .attention:
            "需处理"
        case .delivery:
            "交付"
        case .archived:
            "归档"
        }
    }

    var englishLabel: String {
        switch self {
        case .all:
            "All"
        case .attention:
            "Attention"
        case .delivery:
            "Delivery"
        case .archived:
            "Archive"
        }
    }

    func filter(_ workspaces: [WorkspaceSummary]) -> [WorkspaceSummary] {
        workspaces.filter(matches)
    }

    func matches(_ workspace: WorkspaceSummary) -> Bool {
        switch self {
        case .all:
            true
        case .attention:
            workspace.needsBoardAttention
        case .delivery:
            workspace.mainStage().id == .deliveryCheck
        case .archived:
            workspace.isArchived
        }
    }
}

extension WorkspaceSummary {
    var needsBoardAttention: Bool {
        if isArchived {
            return false
        }

        let stage = mainStage()
        if stage.status == .blocked || stage.status == .pending || stage.status == .review {
            return true
        }

        if stage.id == .created && stage.status == .next {
            return true
        }

        if state == .blocked || riskLevel != .low {
            return true
        }

        return services.contains { service in
            service.worktreeExists == false
                || service.sourceExists == false
                || !service.gitSummary.localizedCaseInsensitiveContains("clean")
        }
    }
}

extension WorkflowPathStatus {
    var boardPriority: Int {
        switch self {
        case .blocked:
            0
        case .pending:
            1
        case .review:
            2
        case .next:
            3
        case .ready:
            4
        case .archived:
            5
        }
    }
}
