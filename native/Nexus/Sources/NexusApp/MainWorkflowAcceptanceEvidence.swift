import Foundation

enum MainWorkflowAcceptanceRequirement: String, CaseIterable, Hashable {
    case stageCoverage
    case stageActionEvidence

    var label: String {
        switch self {
        case .stageCoverage:
            return "阶段覆盖 / Stage coverage"
        case .stageActionEvidence:
            return "动作与证据 / Action and evidence"
        }
    }
}

struct MainWorkflowAcceptanceCheck: Hashable, Identifiable {
    let id: MainWorkflowAcceptanceRequirement
    let label: String
    let status: WorkflowPathStatus
    let detail: String
    let evidence: [String]
}

struct MainWorkflowAcceptanceEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let checks: [MainWorkflowAcceptanceCheck]
    let observedStages: [WorkspaceMainStageID]
    let missingStages: [WorkspaceMainStageID]
    let stagesMissingPrimaryAction: [WorkspaceMainStageID]
    let stagesMissingEvidence: [WorkspaceMainStageID]

    var ready: Bool {
        status == .ready
    }

    static func resolve(stages: [WorkspaceMainStage]) -> MainWorkflowAcceptanceEvidence {
        let observedStages = orderedObservedStages(stages)
        let observedSet = Set(observedStages)
        let missingStages = WorkspaceMainStageID.allCases.filter { !observedSet.contains($0) }
        let stagesMissingPrimaryAction = orderedObservedStages(
            stages.filter { stage in
                stage.answer.nextActionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || stage.primaryActionSystemImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        )
        let stagesMissingEvidence = orderedObservedStages(
            stages.filter { $0.answer.routedEvidenceLinks.isEmpty }
        )

        let coverageCheck = MainWorkflowAcceptanceCheck(
            id: .stageCoverage,
            label: MainWorkflowAcceptanceRequirement.stageCoverage.label,
            status: missingStages.isEmpty ? .ready : .blocked,
            detail: missingStages.isEmpty
                ? "Native 主链路已经观测到 \(observedStages.count) 个阶段。"
                : "Native 主链路还缺阶段：\(stageLabels(missingStages))。",
            evidence: observedStages.map(\.rawValue)
        )

        let actionEvidenceCheck = MainWorkflowAcceptanceCheck(
            id: .stageActionEvidence,
            label: MainWorkflowAcceptanceRequirement.stageActionEvidence.label,
            status: stagesMissingPrimaryAction.isEmpty && stagesMissingEvidence.isEmpty ? .ready : .blocked,
            detail: actionEvidenceDetail(
                missingAction: stagesMissingPrimaryAction,
                missingEvidence: stagesMissingEvidence
            ),
            evidence: stages.flatMap(\.evidence)
        )

        let checks = [coverageCheck, actionEvidenceCheck]
        let blockers = checks.filter { $0.status == .blocked }
        let status: WorkflowPathStatus = blockers.isEmpty ? .ready : .blocked
        let reason = blockers.isEmpty
            ? "M1 主链路阶段快照已覆盖全部阶段，且每个阶段都有主动作和证据。"
            : blockers.map(\.detail).joined(separator: " ")

        return MainWorkflowAcceptanceEvidence(
            status: status,
            reason: reason,
            checks: checks,
            observedStages: observedStages,
            missingStages: missingStages,
            stagesMissingPrimaryAction: stagesMissingPrimaryAction,
            stagesMissingEvidence: stagesMissingEvidence
        )
    }

    static func resolve(workspaces: [WorkspaceSummary]) -> MainWorkflowAcceptanceEvidence {
        resolve(stages: workspaces.map { $0.mainStage() })
    }

    private static func orderedObservedStages(_ stages: [WorkspaceMainStage]) -> [WorkspaceMainStageID] {
        let observed = Set(stages.map(\.id))
        return WorkspaceMainStageID.allCases.filter { observed.contains($0) }
    }

    private static func stageLabels(_ stages: [WorkspaceMainStageID]) -> String {
        stages.map(\.shortLabel).joined(separator: ", ")
    }

    private static func actionEvidenceDetail(
        missingAction: [WorkspaceMainStageID],
        missingEvidence: [WorkspaceMainStageID]
    ) -> String {
        if missingAction.isEmpty && missingEvidence.isEmpty {
            return "每个阶段快照都有主动作、图标和至少一个可路由证据来源。"
        }

        var parts: [String] = []
        if !missingAction.isEmpty {
            parts.append("缺主动作：\(stageLabels(missingAction))")
        }
        if !missingEvidence.isEmpty {
            parts.append("缺可路由证据：\(stageLabels(missingEvidence))")
        }
        return parts.joined(separator: "；") + "。"
    }
}
