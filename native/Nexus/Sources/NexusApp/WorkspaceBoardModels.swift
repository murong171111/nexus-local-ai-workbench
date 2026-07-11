import Foundation

enum WorkspaceBoardLaneID: String, CaseIterable, Hashable, Identifiable {
    case attention
    case active
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: "待处理"
        case .active: "进行中"
        case .completed: "已完成"
        }
    }

    var systemImage: String {
        switch self {
        case .attention: "exclamationmark.circle"
        case .active: "arrow.right.circle"
        case .completed: "checkmark.circle"
        }
    }

    static func resolve(isArchived: Bool, stage: WorkspaceMainStage) -> Self {
        if isArchived { return .completed }
        if stage.status == .blocked || stage.status == .pending || stage.status == .review {
            return .attention
        }
        if stage.id == .created && stage.status == .next { return .attention }
        return .active
    }
}

struct WorkspaceBoardLane: Hashable, Identifiable {
    let id: WorkspaceBoardLaneID
    let workspaces: [WorkspaceSummary]
    let totalCount: Int

    var title: String { id.title }
    var systemImage: String { id.systemImage }
    var hasHiddenWorkspaces: Bool { workspaces.count < totalCount }

    static func lanes(
        for workspaces: [WorkspaceSummary],
        showsAllCompleted: Bool = false
    ) -> [WorkspaceBoardLane] {
        let grouped = Dictionary(grouping: workspaces) { workspace in
            WorkspaceBoardLaneID.resolve(
                isArchived: workspace.isArchived,
                stage: workspace.mainStage()
            )
        }

        return WorkspaceBoardLaneID.allCases.map { id in
            let sorted = (grouped[id] ?? []).sorted { lhs, rhs in
                if id == .attention {
                    let lhsPriority = lhs.mainStage().status.boardPriority
                    let rhsPriority = rhs.mainStage().status.boardPriority
                    if lhsPriority != rhsPriority { return lhsPriority < rhsPriority }
                    if lhs.riskLevel.rank != rhs.riskLevel.rank {
                        return lhs.riskLevel.rank < rhs.riskLevel.rank
                    }
                }
                if lhs.folder != rhs.folder { return lhs.folder > rhs.folder }
                return lhs.name < rhs.name
            }
            let visible = id == .completed && !showsAllCompleted
                ? Array(sorted.prefix(5))
                : sorted
            return WorkspaceBoardLane(id: id, workspaces: visible, totalCount: sorted.count)
        }
    }
}

struct WorkspaceBoardCopy: Hashable {
    static let title = "工作区"
    static let titleHelp = "Board"
    static let showAllCompleted = "查看全部"
    static let showRecentCompleted = "收起"

    static func activeWorkspaceCount(_ count: Int) -> String {
        "\(count) 个活跃项目"
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
