import Foundation
import NexusBridge

enum NativeLocalAutomationCheck {
    static func appendingFeatureCompletionSignals(
        to response: LocalAutomationCheckResponse,
        transitions: [FeatureCompletionTransition]
    ) -> LocalAutomationCheckResponse {
        let completed = transitions.filter { $0.action == "feature.auto_completed" }
        let stale = transitions.filter { $0.action == "feature.evidence_stale" }
        guard !completed.isEmpty || !stale.isEmpty else { return response }
        var signals = response.signals.filter { $0.id != "workspace.clean" }
        if !completed.isEmpty {
            signals.append(
                LocalAutomationSignal(
                    id: "feature.auto-completed",
                    kind: "feature",
                    severity: "info",
                    title: "功能点自动完成 / Features completed",
                    detail: completed.map(\.featureID).sorted().joined(separator: ", "),
                    count: completed.count,
                    action: "none"
                )
            )
        }
        if !stale.isEmpty {
            signals.append(
                LocalAutomationSignal(
                    id: "feature.evidence-stale",
                    kind: "feature",
                    severity: "warning",
                    title: "完成证据待复核 / Evidence needs review",
                    detail: stale.map(\.featureID).sorted().joined(separator: ", "),
                    count: stale.count,
                    action: "review-feature-evidence"
                )
            )
        }
        let details = [
            completed.isEmpty ? nil : "completed \(completed.map(\.featureID).sorted().joined(separator: ", "))",
            stale.isEmpty ? nil : "stale \(stale.map(\.featureID).sorted().joined(separator: ", "))"
        ].compactMap { $0 }.joined(separator: "; ")
        return LocalAutomationCheckResponse(
            generatedAt: response.generatedAt,
            status: response.status == "attention"
                ? "attention"
                : (stale.isEmpty ? response.status : "review"),
            summary: "\(response.summary) Feature evidence: \(details).",
            workspaceCount: response.workspaceCount,
            archivedWorkspaceCount: response.archivedWorkspaceCount,
            riskCount: response.riskCount,
            deliveryIssueCount: response.deliveryIssueCount,
            branchMismatchCount: response.branchMismatchCount,
            openTaskCount: response.openTaskCount,
            highPriorityTaskCount: response.highPriorityTaskCount,
            missingWorktreeCount: response.missingWorktreeCount,
            dirtyServiceCount: response.dirtyServiceCount,
            signals: signals,
            auditEventId: response.auditEventId,
            auditError: response.auditError
        )
    }

    static func response(
        workspaces: [WorkspaceSummary],
        generatedAt: String,
        auditEventID: String? = nil,
        auditError: String? = nil
    ) -> LocalAutomationCheckResponse {
        let workspaceCount = workspaces.count
        let activeWorkspaces = workspaces.filter { !$0.isArchived }
        let archivedWorkspaceCount = workspaceCount - activeWorkspaces.count
        let riskCount = activeWorkspaces.reduce(0) { $0 + $1.risks.count }
        let deliveryIssueCount = activeWorkspaces.filter(workspaceHasDeliveryIssue).count
        let branchMismatchCount = activeWorkspaces.filter(workspaceHasBranchIssue).count
        let activeTasks = activeWorkspaces.flatMap(\.tasks).filter(\.isActive)
        let highPriorityTaskCount = activeTasks.filter { $0.priorityRank == 0 }.count
        let missingWorktreeCount = activeWorkspaces
            .flatMap(\.services)
            .filter { !$0.worktreeExists }
            .count
        let dirtyServiceCount = activeWorkspaces
            .flatMap(\.services)
            .filter(serviceHasDirtyGit)
            .count

        var signals = [
            LocalAutomationSignal(
                id: "refresh.completed",
                kind: "refresh",
                severity: "info",
                title: "刷新完成 / Refresh completed",
                detail: "Scanned \(workspaceCount) workspaces (\(archivedWorkspaceCount) archived).",
                count: workspaceCount,
                action: "refresh"
            )
        ]

        if riskCount > 0 {
            signals.append(
                LocalAutomationSignal(
                    id: "risk.scan",
                    kind: "risk",
                    severity: riskCount >= 3 ? "error" : "warning",
                    title: "风险扫描 / Risk scan",
                    detail: "\(riskCount) risk signals need review across active workspaces.",
                    count: riskCount,
                    action: "review-risk"
                )
            )
        }

        if deliveryIssueCount > 0 {
            signals.append(
                LocalAutomationSignal(
                    id: "delivery.check",
                    kind: "delivery",
                    severity: "warning",
                    title: "交付检查 / Delivery check",
                    detail: "\(deliveryIssueCount) workspaces need delivery-record attention.",
                    count: deliveryIssueCount,
                    action: "update-delivery"
                )
            )
        }

        if branchMismatchCount > 0 {
            signals.append(
                LocalAutomationSignal(
                    id: "branch.check",
                    kind: "branch",
                    severity: "warning",
                    title: "目标分支可用性 / Target branch availability",
                    detail: "\(branchMismatchCount) workspaces have missing or unavailable target branches.",
                    count: branchMismatchCount,
                    action: "review-branches"
                )
            )
        }

        if missingWorktreeCount > 0 {
            signals.append(
                LocalAutomationSignal(
                    id: "worktree.check",
                    kind: "worktree",
                    severity: "warning",
                    title: "Worktree 检查 / Worktree check",
                    detail: "\(missingWorktreeCount) workspace-local worktrees are missing.",
                    count: missingWorktreeCount,
                    action: "review-worktrees"
                )
            )
        }

        if dirtyServiceCount > 0 {
            signals.append(
                LocalAutomationSignal(
                    id: "dirty-service.check",
                    kind: "git",
                    severity: "warning",
                    title: "Git 状态检查 / Dirty services",
                    detail: "\(dirtyServiceCount) services have uncommitted git changes.",
                    count: dirtyServiceCount,
                    action: "review-dirty-services"
                )
            )
        }

        if !activeTasks.isEmpty {
            signals.append(
                LocalAutomationSignal(
                    id: "task.check",
                    kind: "task",
                    severity: highPriorityTaskCount > 0 ? "warning" : "info",
                    title: "任务检查 / Task check",
                    detail: "\(activeTasks.count) open tasks, \(highPriorityTaskCount) high priority.",
                    count: activeTasks.count,
                    action: "review-tasks"
                )
            )
        }

        if signals.count == 1 {
            signals.append(
                LocalAutomationSignal(
                    id: "workspace.clean",
                    kind: "workspace",
                    severity: "info",
                    title: "状态清洁 / Clean state",
                    detail: "No active risk, delivery, git, worktree, or task attention signals.",
                    count: activeWorkspaces.count,
                    action: "none"
                )
            )
        }

        let status: String
        if signals.contains(where: { $0.severity == "error" }) {
            status = "attention"
        } else if signals.contains(where: { $0.severity == "warning" }) {
            status = "review"
        } else {
            status = "clean"
        }

        let summary: String
        switch status {
        case "attention":
            summary = "Automation check found \(riskCount) risks and \(highPriorityTaskCount) high-priority tasks."
        case "review":
            summary = "Automation check found \(riskCount) risks, \(deliveryIssueCount) delivery issues, \(branchMismatchCount) target-branch availability issues, \(missingWorktreeCount) missing worktrees, \(dirtyServiceCount) dirty services, and \(activeTasks.count) open tasks."
        default:
            summary = "Automation check passed for \(activeWorkspaces.count) active workspaces."
        }

        return LocalAutomationCheckResponse(
            generatedAt: generatedAt,
            status: status,
            summary: summary,
            workspaceCount: workspaceCount,
            archivedWorkspaceCount: archivedWorkspaceCount,
            riskCount: riskCount,
            deliveryIssueCount: deliveryIssueCount,
            branchMismatchCount: branchMismatchCount,
            openTaskCount: activeTasks.count,
            highPriorityTaskCount: highPriorityTaskCount,
            missingWorktreeCount: missingWorktreeCount,
            dirtyServiceCount: dirtyServiceCount,
            signals: signals,
            auditEventId: auditEventID,
            auditError: auditError
        )
    }

    static func appendingAudit(
        to response: LocalAutomationCheckResponse,
        auditRoot: String,
        actor: String,
        target: String
    ) -> LocalAutomationCheckResponse {
        do {
            let audit = try NativeAuditEventStore.append(
                auditRoot: auditRoot,
                event: AuditEventInput(
                    actor: actor,
                    action: "automation.check.completed",
                    target: target,
                    summary: response.summary,
                    metadata: metadata(for: response)
                )
            )
            return response.withAudit(auditEventID: audit.event.id, auditError: nil)
        } catch {
            return response.withAudit(auditEventID: nil, auditError: error.localizedDescription)
        }
    }

    static func metadata(for response: LocalAutomationCheckResponse) -> [String: String] {
        [
            "generatedAt": response.generatedAt,
            "status": response.status,
            "workspaceCount": "\(response.workspaceCount)",
            "archivedWorkspaceCount": "\(response.archivedWorkspaceCount)",
            "riskCount": "\(response.riskCount)",
            "deliveryIssueCount": "\(response.deliveryIssueCount)",
            "branchMismatchCount": "\(response.branchMismatchCount)",
            "openTaskCount": "\(response.openTaskCount)",
            "highPriorityTaskCount": "\(response.highPriorityTaskCount)",
            "missingWorktreeCount": "\(response.missingWorktreeCount)",
            "dirtyServiceCount": "\(response.dirtyServiceCount)",
            "signals": response.signals.map(\.id).joined(separator: ",")
        ]
    }

    private static func workspaceHasDeliveryIssue(_ workspace: WorkspaceSummary) -> Bool {
        workspace.risks.contains { risk in
            let normalized = "\(risk.title) \(risk.detail)".lowercased()
            return normalized.contains("交付记录")
                || normalized.contains("sql 变更")
                || normalized.contains("delivery")
                || normalized.contains("sql")
        } || workspace.healthChecks.contains { check in
            (check.id == "delivery-record" || check.id == "sql-directory")
                && !healthStatusIsPassing(check.status)
        }
    }

    private static func workspaceHasBranchIssue(_ workspace: WorkspaceSummary) -> Bool {
        workspace.risks.contains { risk in
            let normalized = "\(risk.title) \(risk.detail)".lowercased()
            return normalized.contains("目标分支不可用")
                || normalized.contains("目标分支缺失")
                || normalized.contains("target branch unavailable")
                || normalized.contains("target branch missing")
        } || workspace.healthChecks.contains { check in
            check.id == "target-branch-availability"
                && !healthStatusIsPassing(check.status)
        }
    }

    private static func serviceHasDirtyGit(_ service: ServiceStatus) -> Bool {
        let normalized = "\(service.gitSummary) \(service.worktree)".lowercased()
        return normalized.contains("dirty")
            || normalized.contains("modified")
            || normalized.contains("uncommitted")
            || normalized.contains("未提交")
            || normalized.contains("有改动")
            || normalized.contains("不是 git")
            || normalized.contains("not git")
            || normalized.contains("检查失败")
            || normalized.contains("failed")
    }

    private static func healthStatusIsPassing(_ status: String) -> Bool {
        let normalized = status.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return ["pass", "passed", "ok", "ready", "clean", "success"].contains(normalized)
    }
}

private extension LocalAutomationCheckResponse {
    func withAudit(
        auditEventID: String?,
        auditError: String?
    ) -> LocalAutomationCheckResponse {
        LocalAutomationCheckResponse(
            generatedAt: generatedAt,
            status: status,
            summary: summary,
            workspaceCount: workspaceCount,
            archivedWorkspaceCount: archivedWorkspaceCount,
            riskCount: riskCount,
            deliveryIssueCount: deliveryIssueCount,
            branchMismatchCount: branchMismatchCount,
            openTaskCount: openTaskCount,
            highPriorityTaskCount: highPriorityTaskCount,
            missingWorktreeCount: missingWorktreeCount,
            dirtyServiceCount: dirtyServiceCount,
            signals: signals,
            auditEventId: auditEventID,
            auditError: auditError
        )
    }
}
