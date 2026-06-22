import Foundation

struct WorkspaceListStageBadge: Identifiable, Hashable {
    let id: String
    let label: String
    let systemImage: String
    let status: WorkflowPathStatus
}

extension WorkspaceMainStage {
    var listBadges: [WorkspaceListStageBadge] {
        [
            WorkspaceListStageBadge(
                id: "stage",
                label: id.shortLabel,
                systemImage: id.systemImage,
                status: status
            ),
            WorkspaceListStageBadge(
                id: "status",
                label: status.displayLabel,
                systemImage: status.listBadgeSystemImage,
                status: status
            ),
            WorkspaceListStageBadge(
                id: "action",
                label: primaryActionLabel,
                systemImage: primaryActionSystemImage,
                status: nextStageAllowed ? .ready : status
            )
        ]
    }
}

private extension WorkflowPathStatus {
    var listBadgeSystemImage: String {
        switch self {
        case .ready:
            "checkmark.circle"
        case .review:
            "eye"
        case .blocked:
            "pause.circle"
        case .pending:
            "clock"
        case .next:
            "arrow.forward.circle"
        case .archived:
            "archivebox"
        }
    }
}
