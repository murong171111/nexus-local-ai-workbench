import Foundation

enum NativeOnboardingStepID: String, CaseIterable, Hashable {
    case teamProfile
    case environmentCheck
    case workspaceCreation
    case mainPath
}

struct NativeOnboardingStep: Hashable, Identifiable {
    let id: NativeOnboardingStepID
    let title: String
    let detail: String
    let actionLabel: String
    let systemImage: String
    let status: WorkflowPathStatus
    let isCurrent: Bool
}

struct NativeOnboardingPath: Hashable {
    let steps: [NativeOnboardingStep]

    var currentStep: NativeOnboardingStep? {
        steps.first { $0.isCurrent }
    }

    var currentActionLabel: String {
        currentStep?.actionLabel ?? "继续主路径"
    }

    static func resolve(
        readiness: NativeSetupReadiness,
        workspaceCount: Int,
        profileImported: Bool
    ) -> NativeOnboardingPath {
        let currentID = currentStepID(
            readiness: readiness,
            workspaceCount: workspaceCount,
            profileImported: profileImported
        )
        let environmentStatus = environmentStepStatus(readiness: readiness)
        let workspaceStatus: WorkflowPathStatus = workspaceCount > 0
            ? .ready
            : readiness.status == .ready ? .next : .pending
        let mainPathStatus: WorkflowPathStatus = readiness.status == .ready && workspaceCount > 0
            ? .ready
            : .pending

        return NativeOnboardingPath(steps: [
            NativeOnboardingStep(
                id: .teamProfile,
                title: "1. 团队配置",
                detail: profileImported
                    ? "已导入团队 Profile；仍可在 Settings 调整本机路径。"
                    : "如果团队已有共享配置，先导入；也可以保留本机路径继续检查。",
                actionLabel: "打开团队配置",
                systemImage: "person.2",
                status: profileImported ? .ready : .review,
                isCurrent: currentID == .teamProfile
            ),
            NativeOnboardingStep(
                id: .environmentCheck,
                title: "2. 环境检查",
                detail: readiness.detail,
                actionLabel: "运行环境检查",
                systemImage: "checkmark.seal",
                status: environmentStatus,
                isCurrent: currentID == .environmentCheck
            ),
            NativeOnboardingStep(
                id: .workspaceCreation,
                title: "3. 创建工作区",
                detail: workspaceCount > 0
                    ? "已扫描到工作区；下一步进入当前项目的主路径。"
                    : "创建真实需求工作区，或用示例模板熟悉标准文档和审计写入。",
                actionLabel: "新建工作区",
                systemImage: "plus",
                status: workspaceStatus,
                isCurrent: currentID == .workspaceCreation
            ),
            NativeOnboardingStep(
                id: .mainPath,
                title: "4. 继续主路径",
                detail: readiness.status == .ready && workspaceCount > 0
                    ? "选择一个工作区后，只保留当前阶段、阻塞摘要、下一步和主证据。"
                    : "工作区可见后，Nexus 会把 Command Center 聚焦到当前最该做的一步。",
                actionLabel: "继续主路径",
                systemImage: "arrow.forward.circle",
                status: mainPathStatus,
                isCurrent: currentID == .mainPath
            )
        ])
    }

    private static func currentStepID(
        readiness: NativeSetupReadiness,
        workspaceCount: Int,
        profileImported: Bool
    ) -> NativeOnboardingStepID {
        if readiness.status == .ready {
            return workspaceCount > 0 ? .mainPath : .workspaceCreation
        }
        if readiness.status == .needsReview || profileImported {
            return .environmentCheck
        }
        return .teamProfile
    }

    private static func environmentStepStatus(readiness: NativeSetupReadiness) -> WorkflowPathStatus {
        switch readiness.status {
        case .ready:
            return .ready
        case .needsReview:
            return .blocked
        case .unchecked:
            return .review
        }
    }
}
