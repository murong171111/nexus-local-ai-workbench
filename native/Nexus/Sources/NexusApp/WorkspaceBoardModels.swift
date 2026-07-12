import Foundation

enum WorkspaceBoardLaneID: String, CaseIterable, Hashable, Identifiable {
    case attention
    case active
    case completed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .attention: WorkspaceBoardCopy.attentionTitle
        case .active: WorkspaceBoardCopy.activeTitle
        case .completed: WorkspaceBoardCopy.completedTitle
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
    static let attentionTitle = "需要你处理"
    static let activeTitle = "进行中"
    static let completedTitle = "最近完成"
    static let showAll = "查看全部"
    static let showAllCompleted = showAll
    static let showRecentCompleted = "收起"

    static func activeWorkspaceCount(_ count: Int) -> String {
        "\(count) 个活跃项目"
    }

    static func attentionWorkspaceCount(_ count: Int) -> String {
        "\(count) 个需要处理"
    }

    static func refreshTime(_ date: Date?) -> String {
        guard let date else { return "尚未自动刷新" }
        return "自动刷新：\(date.formatted(date: .abbreviated, time: .shortened))"
    }

    static func destination(for stage: WorkspaceMainStage) -> String {
        "进入项目 · \(stage.primaryActionLabel)"
    }

    static func cardAccessibilityLabel(workspace: WorkspaceSummary, stage: WorkspaceMainStage) -> String {
        [
            workspace.name,
            "分支 \(workspace.branch)",
            workspace.riskLevel == .low ? nil : workspace.riskLevel.label,
            stage.id.shortLabel,
            stage.reason,
            destination(for: stage)
        ]
        .compactMap { $0 }
        .joined(separator: "，")
    }

    static func completedRowAccessibilityLabel(workspace: WorkspaceSummary, stage: WorkspaceMainStage) -> String {
        [workspace.name, "分支 \(workspace.branch)", stage.id.shortLabel, destination(for: stage)]
            .joined(separator: "，")
    }
}

struct WorkspaceBoardSummary: Equatable {
    let activeCount: Int
    let attentionCount: Int
    let lastRefreshAt: Date?

    init(lanes: [WorkspaceBoardLane], lastRefreshAt: Date?) {
        let attention = lanes.first { $0.id == .attention }?.workspaces.count ?? 0
        let active = lanes.first { $0.id == .active }?.workspaces.count ?? 0
        activeCount = attention + active
        attentionCount = attention
        self.lastRefreshAt = lastRefreshAt
    }
}

struct WorkspaceBoardFeatureProgress: Hashable {
    let completedCount: Int
    let totalCount: Int

    init?(document: FeatureDocument?, revision: FeatureDocumentRevision?) {
        guard let document,
              case .some(.regularUTF8(_, _)) = revision,
              !document.features.isEmpty else { return nil }
        completedCount = document.features.filter { $0.status == .done }.count
        totalCount = document.features.count
    }

    var label: String {
        "已确认功能点 \(completedCount)/\(totalCount)"
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
