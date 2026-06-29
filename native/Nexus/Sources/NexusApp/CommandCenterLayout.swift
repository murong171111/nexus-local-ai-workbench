import Foundation

enum CommandCenterSecondaryActionGroupKind: String, CaseIterable, Identifiable, Hashable {
    case handoff
    case next
    case local

    var id: String { rawValue }

    var title: String {
        switch self {
        case .handoff:
            "交接 / Handoff"
        case .next:
            "下一步 / Next"
        case .local:
            "本地打开 / Local"
        }
    }
}

struct CommandCenterSecondaryActionLayout: Hashable {
    let groups: [CommandCenterSecondaryActionGroupKind]

    init(groups: [CommandCenterSecondaryActionGroupKind] = CommandCenterSecondaryActionGroupKind.allCases) {
        self.groups = groups
    }

    var title: String {
        "快捷动作 / Quick actions"
    }

    var isSecondarySurface: Bool {
        true
    }

    var usesProminentButtons: Bool {
        false
    }
}

enum CommandCenterPathActionPlacement: String, Hashable {
    case menu

    var label: String {
        switch self {
        case .menu:
            "菜单 / Menu"
        }
    }
}

enum CommandCenterLayoutSection: String, CaseIterable, Hashable {
    case primaryStageAction
    case workflowPathEvidence
    case statusMetrics
    case secondaryActions
    case localCheckReceipt
}

struct CommandCenterLayoutPolicy: Hashable {
    let sections: [CommandCenterLayoutSection]
    let secondaryActions: CommandCenterSecondaryActionLayout
    let pathActionPlacement: CommandCenterPathActionPlacement
    let prominentPrimaryActionLimit: Int

    init(
        sections: [CommandCenterLayoutSection] = CommandCenterLayoutSection.allCases,
        secondaryActions: CommandCenterSecondaryActionLayout = CommandCenterSecondaryActionLayout(),
        pathActionPlacement: CommandCenterPathActionPlacement = .menu,
        prominentPrimaryActionLimit: Int = 1
    ) {
        self.sections = sections
        self.secondaryActions = secondaryActions
        self.pathActionPlacement = pathActionPlacement
        self.prominentPrimaryActionLimit = prominentPrimaryActionLimit
    }

    var keepsSecondaryActionsAfterEvidence: Bool {
        guard let evidenceIndex = sections.firstIndex(of: .workflowPathEvidence),
              let secondaryIndex = sections.firstIndex(of: .secondaryActions) else {
            return false
        }
        return evidenceIndex < secondaryIndex && secondaryActions.isSecondarySurface
    }

    var exposesSingleProminentPrimaryAction: Bool {
        prominentPrimaryActionLimit == 1
            && pathActionPlacement == .menu
            && !secondaryActions.usesProminentButtons
    }

    var auditSummary: CommandCenterLayoutAuditSummary {
        CommandCenterLayoutAuditSummary(
            prominentPrimaryActionCount: prominentPrimaryActionLimit,
            workflowPathPlacement: pathActionPlacement,
            secondaryActionGroupCount: secondaryActions.groups.count,
            keepsSecondaryActionsAfterEvidence: keepsSecondaryActionsAfterEvidence,
            exposesSingleProminentPrimaryAction: exposesSingleProminentPrimaryAction
        )
    }
}

struct CommandCenterLayoutAuditSummary: Hashable {
    let prominentPrimaryActionCount: Int
    let workflowPathPlacement: CommandCenterPathActionPlacement
    let secondaryActionGroupCount: Int
    let keepsSecondaryActionsAfterEvidence: Bool
    let exposesSingleProminentPrimaryAction: Bool

    var status: WorkflowPathStatus {
        exposesSingleProminentPrimaryAction && keepsSecondaryActionsAfterEvidence ? .ready : .blocked
    }

    var title: String {
        "主动作优先 / Primary action first"
    }

    var detail: String {
        if status == .ready {
            return "Command Center 只暴露 \(prominentPrimaryActionCount) 个 prominent 主动作；工作流路径动作进入\(workflowPathPlacement.label)，\(secondaryActionGroupCount) 组快捷动作位于证据之后。"
        }
        return "Command Center 主动作层级未收敛；需要保留 1 个 prominent 主动作，并把路径与快捷动作降级。"
    }

    var evidence: [String] {
        [
            "prominentPrimaryActionCount=\(prominentPrimaryActionCount)",
            "workflowPathPlacement=\(workflowPathPlacement.rawValue)",
            "secondaryActionGroups=\(secondaryActionGroupCount)",
            "secondaryAfterEvidence=\(keepsSecondaryActionsAfterEvidence)"
        ]
    }
}
