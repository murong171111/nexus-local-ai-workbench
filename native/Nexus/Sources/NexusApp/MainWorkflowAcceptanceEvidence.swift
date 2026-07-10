import Foundation

enum MainWorkflowAcceptanceRequirement: String, CaseIterable, Hashable {
    case stageCoverage
    case stageActionEvidence
    case demandBlocksDevelopment
    case executionTaskSource
    case worktreeStateCoverage
    case deliveryArchiveGate
    case legacyBoundary

    var label: String {
        switch self {
        case .stageCoverage:
            return "阶段覆盖 / Stage coverage"
        case .stageActionEvidence:
            return "动作与证据 / Action and evidence"
        case .demandBlocksDevelopment:
            return "需求阻塞开发 / Demand gate"
        case .executionTaskSource:
            return "执行任务源 / Task source"
        case .worktreeStateCoverage:
            return "Worktree 状态 / Worktree states"
        case .deliveryArchiveGate:
            return "交付归档门禁 / Delivery archive"
        case .legacyBoundary:
            return "Legacy 边界 / Legacy boundary"
        }
    }
}

struct MainWorkflowLegacyBoundary: Hashable {
    let allowsLegacyProductWorkflow: Bool
    let evidence: [String]

    static let nativeOnly = MainWorkflowLegacyBoundary(
        allowsLegacyProductWorkflow: false,
        evidence: ["docs/main-workflow.md#legacy-interaction-rules"]
    )
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
    let stagesMissingCurrentStateAnswer: [WorkspaceMainStageID]
    let stagesMissingPrimaryAction: [WorkspaceMainStageID]
    let stagesMissingEvidence: [WorkspaceMainStageID]
    let coveredWorktreeStates: [ServiceWorktreeRowStateKind]
    let missingWorktreeStates: [ServiceWorktreeRowStateKind]

    var ready: Bool {
        status == .ready
    }

    static func resolve(
        stages: [WorkspaceMainStage],
        demandReadiness: DemandIntakeReadinessEvidence? = nil,
        developmentTasks: DevelopmentTaskEvidence? = nil,
        worktreeRows: [ServiceWorktreeRowState]? = nil,
        deliveryGate: DeliveryGateEvidence? = nil,
        archiveGate: ArchiveGateEvidence? = nil,
        legacyBoundary: MainWorkflowLegacyBoundary? = nil
    ) -> MainWorkflowAcceptanceEvidence {
        resolveWithChecks(
            stages: stages,
            worktreeRows: worktreeRows ?? [],
            demandCheck: demandGateCheck(demandReadiness),
            taskSourceCheck: taskSourceCheck(developmentTasks),
            deliveryArchiveCheck: deliveryArchiveCheck(
                deliveryGate: deliveryGate,
                archiveGate: archiveGate
            ),
            legacyCheck: legacyBoundaryCheck(legacyBoundary)
        )
    }

    static func resolveGlobal(
        stages: [WorkspaceMainStage],
        demandReadinessCandidates: [DemandIntakeReadinessEvidence],
        developmentTaskCandidates: [DevelopmentTaskEvidence],
        worktreeRows: [ServiceWorktreeRowState],
        deliveryGateCandidates: [DeliveryGateEvidence],
        archiveGateCandidates: [ArchiveGateEvidence],
        legacyBoundary: MainWorkflowLegacyBoundary
    ) -> MainWorkflowAcceptanceEvidence {
        let deliveryArchiveCandidates = deliveryGateCandidates.flatMap { deliveryGate in
            archiveGateCandidates.map { archiveGate in
                deliveryArchiveCheck(deliveryGate: deliveryGate, archiveGate: archiveGate)
            }
        }
        return resolveWithChecks(
            stages: stages,
            worktreeRows: worktreeRows,
            demandCheck: strongestCheck(
                demandReadinessCandidates.map(demandGateCheck),
                missing: demandGateCheck(nil)
            ),
            taskSourceCheck: strongestCheck(
                developmentTaskCandidates.map(taskSourceCheck),
                missing: taskSourceCheck(nil)
            ),
            deliveryArchiveCheck: strongestCheck(
                deliveryArchiveCandidates,
                missing: deliveryArchiveCheck(deliveryGate: nil, archiveGate: nil)
            ),
            legacyCheck: legacyBoundaryCheck(legacyBoundary)
        )
    }

    private static func resolveWithChecks(
        stages: [WorkspaceMainStage],
        worktreeRows: [ServiceWorktreeRowState],
        demandCheck: MainWorkflowAcceptanceCheck,
        taskSourceCheck: MainWorkflowAcceptanceCheck,
        deliveryArchiveCheck: MainWorkflowAcceptanceCheck,
        legacyCheck: MainWorkflowAcceptanceCheck
    ) -> MainWorkflowAcceptanceEvidence {
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
        let stagesMissingCurrentStateAnswer = orderedObservedStages(
            stages.filter { !$0.answer.canAnswerCurrentState }
        )
        let coveredWorktreeStates = orderedWorktreeStates(worktreeRows)
        let coveredWorktreeSet = Set(coveredWorktreeStates)
        let missingWorktreeStates = ServiceWorktreeRowStateKind.allCases.filter { !coveredWorktreeSet.contains($0) }

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
            status: stagesMissingPrimaryAction.isEmpty
                && stagesMissingEvidence.isEmpty
                && stagesMissingCurrentStateAnswer.isEmpty ? .ready : .blocked,
            detail: actionEvidenceDetail(
                missingAction: stagesMissingPrimaryAction,
                missingEvidence: stagesMissingEvidence,
                missingCurrentStateAnswer: stagesMissingCurrentStateAnswer
            ),
            evidence: stages.compactMap { $0.answer.primaryEvidenceLink?.label }
        )

        let worktreeCheck = worktreeStateCheck(
            covered: coveredWorktreeStates,
            missing: missingWorktreeStates
        )
        let checks = [
            coverageCheck,
            actionEvidenceCheck,
            demandCheck,
            taskSourceCheck,
            worktreeCheck,
            deliveryArchiveCheck,
            legacyCheck
        ]
        let blockers = checks.filter { $0.status == .blocked }
        let status: WorkflowPathStatus = blockers.isEmpty ? .ready : .blocked
        let reason = blockers.isEmpty
            ? "M1 主链路验收证据已覆盖阶段、动作、需求门禁、任务源、worktree 状态、交付归档门禁和 legacy 边界。"
            : blockers.map(\.detail).joined(separator: " ")

        return MainWorkflowAcceptanceEvidence(
            status: status,
            reason: reason,
            checks: checks,
            observedStages: observedStages,
            missingStages: missingStages,
            stagesMissingCurrentStateAnswer: stagesMissingCurrentStateAnswer,
            stagesMissingPrimaryAction: stagesMissingPrimaryAction,
            stagesMissingEvidence: stagesMissingEvidence,
            coveredWorktreeStates: coveredWorktreeStates,
            missingWorktreeStates: missingWorktreeStates
        )
    }

    private static func strongestCheck(
        _ candidates: [MainWorkflowAcceptanceCheck],
        missing: MainWorkflowAcceptanceCheck
    ) -> MainWorkflowAcceptanceCheck {
        guard !candidates.isEmpty else { return missing }
        let readyCandidates = candidates.filter { $0.status == .ready }
        let eligible = readyCandidates.isEmpty ? candidates : readyCandidates
        return eligible.sorted { lhs, rhs in
            let lhsSignature = (lhs.evidence + [lhs.detail]).joined(separator: "\n")
            let rhsSignature = (rhs.evidence + [rhs.detail]).joined(separator: "\n")
            return lhsSignature < rhsSignature
        }.first ?? missing
    }

    private static func orderedObservedStages(_ stages: [WorkspaceMainStage]) -> [WorkspaceMainStageID] {
        let observed = Set(stages.map(\.id))
        return WorkspaceMainStageID.allCases.filter { observed.contains($0) }
    }

    private static func stageLabels(_ stages: [WorkspaceMainStageID]) -> String {
        stages.map(\.shortLabel).joined(separator: ", ")
    }

    private static func orderedWorktreeStates(_ rows: [ServiceWorktreeRowState]) -> [ServiceWorktreeRowStateKind] {
        let covered = Set(rows.map(\.kind))
        return ServiceWorktreeRowStateKind.allCases.filter { covered.contains($0) }
    }

    private static func worktreeStateLabels(_ states: [ServiceWorktreeRowStateKind]) -> String {
        states.map(\.rawValue).joined(separator: ", ")
    }

    private static func demandGateCheck(
        _ readiness: DemandIntakeReadinessEvidence?
    ) -> MainWorkflowAcceptanceCheck {
        guard let readiness else {
            return missingEvidenceCheck(.demandBlocksDevelopment, detail: "缺少需求预检 evidence，无法证明开发会被 P0 和范围冻结门禁阻塞。")
        }

        let ready = readiness.requirementHasContent
            && readiness.unresolvedP0Count == 0
            && readiness.scopeFrozen
            && readiness.requirementTasksReady
        return MainWorkflowAcceptanceCheck(
            id: .demandBlocksDevelopment,
            label: MainWorkflowAcceptanceRequirement.demandBlocksDevelopment.label,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "需求内容、P0、范围冻结和需求任务都已作为开发前置门禁。"
                : "需求门禁未满足：requirement=\(readiness.requirementHasContent)，P0=\(readiness.unresolvedP0Count)，scopeFrozen=\(readiness.scopeFrozen)，tasks=\(readiness.requirementTasksReady)。",
            evidence: readiness.evidence
        )
    }

    private static func taskSourceCheck(
        _ developmentTasks: DevelopmentTaskEvidence?
    ) -> MainWorkflowAcceptanceCheck {
        guard let developmentTasks else {
            return missingEvidenceCheck(.executionTaskSource, detail: "缺少开发任务 evidence，无法证明 root tasks.md 是唯一执行队列。")
        }

        let executionSources = developmentTasks.sources.filter(\.participatesInExecutionQueue)
        let intakeSources = developmentTasks.sources.filter { !$0.participatesInExecutionQueue }
        let ready = executionSources.count == 1
            && executionSources.first?.role == .executionQueue
            && executionSources.first?.path.hasSuffix("/tasks.md") == true
            && intakeSources.allSatisfy { $0.role == .intakeEvidence }

        return MainWorkflowAcceptanceCheck(
            id: .executionTaskSource,
            label: MainWorkflowAcceptanceRequirement.executionTaskSource.label,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "root tasks.md 是唯一执行队列，需求任务只作为 intake evidence。"
                : "执行任务源不清晰：execution=\(executionSources.map(\.path).joined(separator: ", "))，intake=\(intakeSources.map(\.path).joined(separator: ", "))。",
            evidence: developmentTasks.sources.map(\.path)
        )
    }

    private static func worktreeStateCheck(
        covered: [ServiceWorktreeRowStateKind],
        missing: [ServiceWorktreeRowStateKind]
    ) -> MainWorkflowAcceptanceCheck {
        MainWorkflowAcceptanceCheck(
            id: .worktreeStateCoverage,
            label: MainWorkflowAcceptanceRequirement.worktreeStateCoverage.label,
            status: missing.isEmpty ? .ready : .blocked,
            detail: missing.isEmpty
                ? "Worktree 行状态已覆盖 source repo、worktree、branch、dirty 和 clean 五种状态。"
                : "Worktree 行状态仍缺：\(worktreeStateLabels(missing))。",
            evidence: covered.map(\.rawValue)
        )
    }

    private static func deliveryArchiveCheck(
        deliveryGate: DeliveryGateEvidence?,
        archiveGate: ArchiveGateEvidence?
    ) -> MainWorkflowAcceptanceCheck {
        guard let deliveryGate, let archiveGate else {
            return missingEvidenceCheck(.deliveryArchiveGate, detail: "缺少交付或归档 evidence，无法证明二者共用 SQL、任务、风险和 git 门禁。")
        }

        let deliveryCheckIDs = Set(deliveryGate.checks.map(\.id))
        let requiredDeliveryChecks: Set<String> = ["tasks", "risks", "sql", "dirty-services"]
        let hasRequiredDeliveryChecks = requiredDeliveryChecks.isSubset(of: deliveryCheckIDs)
        let archiveReusesDelivery = archiveGate.checks.contains { $0.id.hasPrefix("delivery-") }
            || archiveGate.confirmationPlan.contains { $0.id.contains("delivery") }
        let ready = hasRequiredDeliveryChecks && archiveReusesDelivery

        return MainWorkflowAcceptanceCheck(
            id: .deliveryArchiveGate,
            label: MainWorkflowAcceptanceRequirement.deliveryArchiveGate.label,
            status: ready ? .ready : .blocked,
            detail: ready
                ? "交付门禁包含任务、风险、SQL 和 git 状态，归档门禁复用交付证据并走确认计划。"
                : "交付/归档门禁未证明复用：deliveryChecks=\(deliveryCheckIDs.sorted().joined(separator: ", "))，archivePlan=\(archiveGate.confirmationPlan.map(\.id).joined(separator: ", "))。",
            evidence: deliveryGate.evidence + archiveGate.evidence
        )
    }

    private static func legacyBoundaryCheck(
        _ boundary: MainWorkflowLegacyBoundary?
    ) -> MainWorkflowAcceptanceCheck {
        guard let boundary else {
            return missingEvidenceCheck(.legacyBoundary, detail: "缺少 legacy 边界 evidence，无法证明新产品流只进入 Native。")
        }

        return MainWorkflowAcceptanceCheck(
            id: .legacyBoundary,
            label: MainWorkflowAcceptanceRequirement.legacyBoundary.label,
            status: boundary.allowsLegacyProductWorkflow ? .blocked : .ready,
            detail: boundary.allowsLegacyProductWorkflow
                ? "Legacy Web/Tauri/Rust/TypeScript 仍允许新增产品工作流。"
                : "Legacy 只能作为证据或迁移参考，新产品工作流进入 Swift Native。",
            evidence: boundary.evidence
        )
    }

    private static func missingEvidenceCheck(
        _ requirement: MainWorkflowAcceptanceRequirement,
        detail: String
    ) -> MainWorkflowAcceptanceCheck {
        MainWorkflowAcceptanceCheck(
            id: requirement,
            label: requirement.label,
            status: .blocked,
            detail: detail,
            evidence: []
        )
    }

    private static func actionEvidenceDetail(
        missingAction: [WorkspaceMainStageID],
        missingEvidence: [WorkspaceMainStageID],
        missingCurrentStateAnswer: [WorkspaceMainStageID]
    ) -> String {
        if missingAction.isEmpty && missingEvidence.isEmpty && missingCurrentStateAnswer.isEmpty {
            return "每个阶段快照都能回答当前阶段、原因、下一步和主证据文件。"
        }

        var parts: [String] = []
        if !missingCurrentStateAnswer.isEmpty {
            parts.append("缺完整阶段回答：\(stageLabels(missingCurrentStateAnswer))")
        }
        if !missingAction.isEmpty {
            parts.append("缺主动作：\(stageLabels(missingAction))")
        }
        if !missingEvidence.isEmpty {
            parts.append("缺可路由证据：\(stageLabels(missingEvidence))")
        }
        return parts.joined(separator: "；") + "。"
    }
}
