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
}
