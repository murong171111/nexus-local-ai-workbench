import Foundation
import NexusBridge

extension WorkspaceSummary {
    func mainStage(
        demandIntakeStatus: DemandIntakeStatus? = nil,
        demandReadiness: DemandIntakeReadinessEvidence? = nil,
        scopeFreeze: ScopeFreezeEvidence? = nil,
        serviceBranch: ServiceBranchEvidence? = nil,
        worktreeSetup: WorktreeSetupEvidence? = nil,
        developmentTasks: DevelopmentTaskEvidence? = nil,
        deliveryGate: DeliveryGateEvidence? = nil,
        archiveGate: ArchiveGateEvidence? = nil,
        demandTaskTransfer: DemandTaskTransferPlan? = nil
    ) -> WorkspaceMainStage {
        if isArchived {
            return WorkspaceMainStage(
                id: .archived,
                status: .archived,
                title: "已归档 / Archived",
                reason: "这个工作区已退出活跃开发流，默认只读查看。需要继续处理时，从归档确认计划中显式恢复开发。",
                primaryActionLabel: "查看交接",
                primaryActionSystemImage: "doc.text",
                primaryAction: .document("handoff"),
                evidence: compactEvidence("handoff.md", documentLinks["delivery"] ?? "交付记录.md", "恢复开发需要确认写回"),
                nextStageAllowed: false
            )
        }

        let resolvedDemandIntake = resolveDemandIntakeStatus(explicitStatus: demandIntakeStatus)
        let resolvedDemandIntakeStatus = resolvedDemandIntake.status
        let resolvedDemandReadiness = demandReadiness
            ?? resolvedDemandIntakeStatus.map {
                DemandIntakeReadinessEvidence.resolve(status: $0, workspace: self)
            }
        let resolvedScopeFreeze = scopeFreeze
            ?? resolvedDemandIntakeStatus.map {
                ScopeFreezeEvidence.resolve(status: $0, workspace: self)
            }
        let resolvedDemandTaskTransfer = demandTaskTransfer
            ?? resolvedDemandIntakeStatus.map {
                DemandTaskTransferPlan.resolve(workspace: self, status: $0)
            }

        if shouldShowCreatedStage(
            demandIntakeStatus: resolvedDemandIntakeStatus,
            demandReadiness: resolvedDemandReadiness
        ) {
            return WorkspaceMainStage(
                id: .created,
                status: .next,
                title: "工作区已建档 / Workspace created",
                reason: "工作区文件已经存在，但尚未读取到需求预检证据。下一步先进入需求预检，而不是直接创建 worktree 或开始开发。",
                primaryActionLabel: "开始预检",
                primaryActionSystemImage: "text.badge.checkmark",
                primaryAction: .demandIntake,
                evidence: compactEvidence(
                    documentLinks["workspace"] ?? "workspace.md",
                    documentLinks["status"] ?? "STATUS.md",
                    "需求/"
                ),
                nextStageAllowed: false
            )
        }

        let demandGate = Self.demandGate(
            for: self,
            resolution: resolvedDemandIntake,
            status: resolvedDemandIntakeStatus,
            readiness: resolvedDemandReadiness
        )
        if demandGate.status != .ready {
            return WorkspaceMainStage(
                id: .demandIntake,
                status: demandGate.status,
                title: "完成需求预检 / Demand intake",
                reason: demandGate.reason,
                primaryActionLabel: "打开预检",
                primaryActionSystemImage: "text.badge.checkmark",
                primaryAction: .demandIntake,
                evidence: demandGate.evidence,
                nextStageAllowed: false
            )
        }

        let scopeGate = resolvedScopeFreeze
        if let scopeGate, scopeGate.status != .ready {
            return WorkspaceMainStage(
                id: .scopeFreeze,
                status: scopeGate.status,
                title: "冻结开发范围 / Scope freeze",
                reason: scopeGate.reason,
                primaryActionLabel: "打开范围",
                primaryActionSystemImage: "scope",
                primaryAction: .path(scopeGate.scopePath),
                evidence: scopeGate.evidence,
                nextStageAllowed: false
            )
        }

        let serviceBranchGate = serviceBranch ?? ServiceBranchEvidence.resolve(workspace: self)
        if serviceBranchGate.status != .ready {
            return WorkspaceMainStage(
                id: .serviceBranchConfirm,
                status: serviceBranchGate.status,
                title: serviceBranchGate.title,
                reason: serviceBranchGate.reason,
                primaryActionLabel: serviceBranchGate.primaryActionLabel,
                primaryActionSystemImage: serviceBranchGate.primaryActionSystemImage,
                primaryAction: serviceBranchGate.primaryAction,
                evidence: serviceBranchGate.evidence,
                nextStageAllowed: false
            )
        }

        let worktreeGate = worktreeSetup ?? WorktreeSetupEvidence.resolve(workspace: self)
        if worktreeGate.status != .ready {
            return WorkspaceMainStage(
                id: .worktreeSetup,
                status: worktreeGate.status,
                title: worktreeGate.title,
                reason: worktreeGate.reason,
                primaryActionLabel: worktreeGate.primaryActionLabel,
                primaryActionSystemImage: worktreeGate.primaryActionSystemImage,
                primaryAction: worktreeGate.primaryAction,
                evidence: worktreeGate.evidence,
                nextStageAllowed: false
            )
        }

        if let resolvedDemandTaskTransfer, resolvedDemandTaskTransfer.hasTransferableItems {
            return WorkspaceMainStage(
                id: .development,
                status: .next,
                title: "转入执行任务 / Transfer tasks",
                reason: resolvedDemandTaskTransfer.summary,
                primaryActionLabel: "转入 tasks.md",
                primaryActionSystemImage: "arrow.down.doc",
                primaryAction: .transferDemandTasks,
                evidence: compactEvidence("需求/tasks.md", "tasks.md"),
                nextStageAllowed: false
            )
        }

        let taskGate = developmentTasks ?? DevelopmentTaskEvidence.resolve(workspace: self)
        if taskGate.status != .ready {
            return WorkspaceMainStage(
                id: .development,
                status: taskGate.status,
                title: taskGate.title,
                reason: taskGate.reason,
                primaryActionLabel: taskGate.primaryActionLabel,
                primaryActionSystemImage: taskGate.primaryActionSystemImage,
                primaryAction: taskGate.primaryAction,
                evidence: taskGate.evidence,
                nextStageAllowed: false
            )
        }

        let delivery = deliveryGate ?? DeliveryGateEvidence.resolve(workspace: self)
        if delivery.status == .ready {
            let archive = archiveGate ?? ArchiveGateEvidence.resolve(workspace: self, deliveryGate: delivery)
            return WorkspaceMainStage(
                id: .archived,
                status: archive.status,
                title: archive.title,
                reason: archive.reason,
                primaryActionLabel: archive.primaryActionLabel,
                primaryActionSystemImage: archive.primaryActionSystemImage,
                primaryAction: archive.primaryAction,
                evidence: archive.evidence,
                nextStageAllowed: archive.ready
            )
        }

        return WorkspaceMainStage(
            id: .deliveryCheck,
            status: delivery.status,
            title: delivery.title,
            reason: delivery.reason,
            primaryActionLabel: delivery.primaryActionLabel,
            primaryActionSystemImage: delivery.primaryActionSystemImage,
            primaryAction: delivery.primaryAction,
            evidence: delivery.evidence,
            nextStageAllowed: delivery.ready
        )
    }

    private func shouldShowCreatedStage(
        demandIntakeStatus: DemandIntakeStatus?,
        demandReadiness: DemandIntakeReadinessEvidence?
    ) -> Bool {
        if healthChecks.contains(where: { $0.id == "demand-intake" || $0.action == "demandIntake" }) {
            return false
        }

        let normalizedLifecycle = lifecycle.stage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard normalizedLifecycle == "created" || normalizedLifecycle == "scoping" else {
            return false
        }

        if let demandIntakeStatus {
            return !demandIntakeStatus.exists
        }

        return demandReadiness == nil
    }

    private func compactEvidence(_ values: String?...) -> [String] {
        values.compactMap { value in
            let cleaned = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return cleaned.isEmpty ? nil : cleaned
        }
    }

    private func resolveDemandIntakeStatus(
        explicitStatus: DemandIntakeStatus?
    ) -> DemandIntakeStatusResolution {
        if let explicitStatus {
            return .explicit(explicitStatus)
        }

        do {
            return .loaded(try NativeDemandIntakeStore.status(workspacePath: path))
        } catch {
            return .failed
        }
    }

    private static func demandGate(
        for workspace: WorkspaceSummary,
        resolution: DemandIntakeStatusResolution,
        status: DemandIntakeStatus?,
        readiness: DemandIntakeReadinessEvidence?
    ) -> (status: WorkflowPathStatus, reason: String, evidence: [String]) {
        if let readiness {
            return (readiness.status, readiness.reason, readiness.evidence)
        }

        if let status {
            let evidence = status.files.map { "需求/\($0.filename)" }
            if status.ready {
                return (.ready, "需求预检文件已就绪，可以继续冻结范围。", evidence)
            }
            if status.exists {
                return (
                    .review,
                    "需求目录已存在，但仍缺 \(status.missingCount) 个固定文件。先补齐 requirement、questions、scope、tasks 和 delivery。",
                    evidence
                )
            }
            return (
                .blocked,
                "当前工作区还没有 需求/ 目录。先初始化需求预检，再把蓝湖材料和补充说明沉淀到 Markdown。",
                ["需求/"]
            )
        }

        if let check = workspace.healthChecks.first(where: { $0.id == "demand-intake" || $0.action == "demandIntake" }) {
            if case .failed = resolution {
                switch check.status.lowercased() {
                case "fail", "blocked", "blocker":
                    return (.blocked, check.detail, ["需求/"])
                default:
                    return (
                        .pending,
                        "无法读取工作区里的需求预检文件，不能只凭健康检查判定已就绪。先修复工作区路径或刷新 需求/ 目录后再继续。",
                        ["需求/"]
                    )
                }
            }

            switch check.status.lowercased() {
            case "pass", "ok", "ready":
                return (.ready, check.detail, ["需求/requirement.md", "需求/questions.md", "需求/scope.md"])
            case "fail", "blocked", "blocker":
                return (.blocked, check.detail, ["需求/"])
            default:
                return (.review, check.detail, ["需求/"])
            }
        }

        return (
            .pending,
            "尚未读取需求预检状态。刷新工作区后确认 需求/ 目录和固定文件是否齐全。",
            ["需求/"]
        )
    }
}

private enum DemandIntakeStatusResolution {
    case explicit(DemandIntakeStatus)
    case loaded(DemandIntakeStatus)
    case failed

    var status: DemandIntakeStatus? {
        switch self {
        case .explicit(let status), .loaded(let status):
            return status
        case .failed:
            return nil
        }
    }
}
