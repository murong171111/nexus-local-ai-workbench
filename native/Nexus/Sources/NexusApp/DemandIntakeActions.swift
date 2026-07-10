import Foundation
import NexusBridge

enum DemandIntakeM1ActionKind: String, CaseIterable, Hashable {
    case initializeOrRepair
    case openRequirement
    case copyHandoffPrompt
}

struct DemandIntakeM1Action: Identifiable, Hashable {
    let kind: DemandIntakeM1ActionKind
    let label: String
    let systemImage: String
    let isPrimary: Bool
    let isEnabled: Bool

    var id: DemandIntakeM1ActionKind { kind }
}

struct DemandIntakeM1ActionPolicy: Hashable {
    let actions: [DemandIntakeM1Action]

    init(
        status: DemandIntakeStatus,
        confirmed: Bool,
        isInitializing: Bool,
        requirementFileExists: Bool,
        initializationPlan: NativeDemandIntakeInitializationPlan?
    ) {
        let initializationIsPrimary = !status.ready
        let initializeEnabled = confirmed
            && !isInitializing
            && initializationPlan?.canInitialize == true
        actions = [
            DemandIntakeM1Action(
                kind: .initializeOrRepair,
                label: isInitializing ? "处理中" : (status.exists ? "补齐文件" : "初始化预检"),
                systemImage: "doc.badge.plus",
                isPrimary: initializationIsPrimary,
                isEnabled: initializeEnabled
            ),
            DemandIntakeM1Action(
                kind: .openRequirement,
                label: "打开确认卡",
                systemImage: "doc.text",
                isPrimary: !initializationIsPrimary,
                isEnabled: requirementFileExists
            ),
            DemandIntakeM1Action(
                kind: .copyHandoffPrompt,
                label: "复制预检交接",
                systemImage: "doc.on.clipboard",
                isPrimary: false,
                isEnabled: true
            )
        ]
    }

    var keepsAIInvocationOutOfM1: Bool {
        Set(actions.map(\.kind)).isSubset(of: Set(DemandIntakeM1ActionKind.allCases))
    }
}
