import Foundation
import NexusBridge

enum WorkspaceDetailSection: String, CaseIterable, Identifiable, Hashable {
    case overview
    case command
    case demand
    case workflow
    case services
    case risk
    case documents
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "概览 / Overview"
        case .command:
            "工作台 / Command"
        case .demand:
            "需求 / Demand"
        case .workflow:
            "任务交付 / Workflow"
        case .services:
            "服务 / Services"
        case .risk:
            "风险 / Risk"
        case .documents:
            "文档 / Docs"
        case .activity:
            "活动 / Activity"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "rectangle.grid.2x2"
        case .command:
            "point.3.connected.trianglepath.dotted"
        case .demand:
            "text.badge.checkmark"
        case .workflow:
            "checklist"
        case .services:
            "square.stack.3d.up"
        case .risk:
            "exclamationmark.triangle"
        case .documents:
            "doc.text"
        case .activity:
            "clock"
        }
    }
}

enum WorkspaceDetailNavigationTone: Hashable {
    case accent
    case success
    case warning
    case danger
    case secondary
}

enum WorkspaceDetailNavigationAction: Hashable {
    case navigate(WorkspaceDetailSection)
}

struct WorkspaceDetailNavigationItem: Identifiable, Hashable {
    let section: WorkspaceDetailSection
    let title: String
    let systemImage: String
    let detail: String
    let tone: WorkspaceDetailNavigationTone
    let action: WorkspaceDetailNavigationAction

    var id: WorkspaceDetailSection { section }

    var isNavigationOnly: Bool {
        switch action {
        case .navigate(let destination):
            destination == section
        }
    }
}

struct WorkspaceDetailNavigationMap: Hashable {
    let items: [WorkspaceDetailNavigationItem]

    init(
        workspace: WorkspaceSummary,
        mainStage: WorkspaceMainStage,
        demandStatus: DemandIntakeStatus
    ) {
        let openTaskCount = workspace.tasks.filter(\.isActive).count
        let blockedTaskCount = workspace.tasks.filter { $0.isActive && $0.isBlocked }.count
        let missingWorktreeCount = workspace.services.filter { !$0.worktreeExists }.count

        items = WorkspaceDetailSection.allCases.map { section in
            WorkspaceDetailNavigationItem(
                section: section,
                title: section.title,
                systemImage: section.systemImage,
                detail: Self.detail(
                    for: section,
                    workspace: workspace,
                    mainStage: mainStage,
                    demandStatus: demandStatus,
                    openTaskCount: openTaskCount,
                    blockedTaskCount: blockedTaskCount,
                    missingWorktreeCount: missingWorktreeCount
                ),
                tone: Self.tone(
                    for: section,
                    workspace: workspace,
                    mainStage: mainStage,
                    demandStatus: demandStatus,
                    openTaskCount: openTaskCount,
                    blockedTaskCount: blockedTaskCount,
                    missingWorktreeCount: missingWorktreeCount
                ),
                action: .navigate(section)
            )
        }
    }

    private static func detail(
        for section: WorkspaceDetailSection,
        workspace: WorkspaceSummary,
        mainStage: WorkspaceMainStage,
        demandStatus: DemandIntakeStatus,
        openTaskCount: Int,
        blockedTaskCount: Int,
        missingWorktreeCount: Int
    ) -> String {
        switch section {
        case .overview:
            workspace.lifecycle.label
        case .command:
            mainStage.id.shortLabel
        case .demand:
            demandDetail(demandStatus)
        case .workflow:
            blockedTaskCount > 0 ? "\(blockedTaskCount) 阻塞" : "\(openTaskCount) 开放"
        case .services:
            workspace.services.isEmpty ? "待确认" : "\(workspace.services.count) 服务 / 缺 \(missingWorktreeCount)"
        case .risk:
            workspace.risks.isEmpty ? "暂无风险" : "\(workspace.risks.count) 信号"
        case .documents:
            "\(workspace.documentLinks.count) 文档"
        case .activity:
            workspace.activities.isEmpty ? "无活动" : "\(workspace.activities.count) 活动"
        }
    }

    private static func tone(
        for section: WorkspaceDetailSection,
        workspace: WorkspaceSummary,
        mainStage: WorkspaceMainStage,
        demandStatus: DemandIntakeStatus,
        openTaskCount: Int,
        blockedTaskCount: Int,
        missingWorktreeCount: Int
    ) -> WorkspaceDetailNavigationTone {
        switch section {
        case .overview:
            return workspace.isArchived ? .secondary : .accent
        case .command:
            return mainStage.status.navigationTone
        case .demand:
            return demandTone(demandStatus)
        case .workflow:
            if blockedTaskCount > 0 {
                return .danger
            }
            return openTaskCount > 0 ? .warning : .success
        case .services:
            if workspace.services.isEmpty {
                return .warning
            }
            return missingWorktreeCount > 0 ? .warning : .success
        case .risk:
            return workspace.risks.isEmpty ? .success : .warning
        case .documents:
            return .accent
        case .activity:
            return .secondary
        }
    }

    private static func demandDetail(_ demandStatus: DemandIntakeStatus) -> String {
        if demandStatus.ready {
            return "已就绪"
        }
        return demandStatus.exists ? "缺 \(demandStatus.missingCount)" : "待初始化"
    }

    private static func demandTone(_ demandStatus: DemandIntakeStatus) -> WorkspaceDetailNavigationTone {
        if demandStatus.ready {
            return .success
        }
        return demandStatus.exists ? .warning : .accent
    }
}

private extension WorkflowPathStatus {
    var navigationTone: WorkspaceDetailNavigationTone {
        switch self {
        case .ready:
            .success
        case .review:
            .warning
        case .blocked:
            .danger
        case .pending:
            .secondary
        case .next:
            .accent
        case .archived:
            .secondary
        }
    }
}
