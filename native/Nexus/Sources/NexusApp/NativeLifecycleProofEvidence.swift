import Foundation
import NexusBridge

struct NativeLifecycleProofEvidence: Hashable {
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let status: WorkflowPathStatus
    let detail: String
    let orderedActions: [String]
    let missingActions: [String]

    var ready: Bool {
        status == .ready
    }

    static let requiredAuditActions = [
        "workspace.created",
        "demand_intake.initialized",
        "scope.freeze_confirmed",
        "demand_tasks.transferred",
        "worktree_setup.executed",
        "workspace_task.updated",
        "delivery_record.snapshot_appended",
        "archive_checklist.snapshot_appended",
        "workspace_lifecycle.updated"
    ]

    static func isRequiredAuditEvent(_ event: AuditEvent) -> Bool {
        if event.action == "workspace_lifecycle.updated" {
            return isArchivedLifecycleEvent(event)
        }
        return requiredAuditActions.contains(event.action)
    }

    static func resolve(
        workspace: WorkspaceSummary,
        auditEvents: [AuditEvent]
    ) -> NativeLifecycleProofEvidence {
        let finalBlockers = finalStateBlockers(for: workspace)
        let relevantEvents = chronologicalRelevantEvents(for: workspace, auditEvents: auditEvents)
        let sequence = orderedSequence(in: relevantEvents)
        let hasArchivedLifecycle = hasArchivedLifecycleEvent(relevantEvents)
        var missing = requiredAuditActions.filter { action in
            if action == "workspace_lifecycle.updated" {
                return !hasArchivedLifecycle
            }
            return !sequence.contains(action)
        }
        if !hasArchivedLifecycle {
            missing.removeAll { $0 == "workspace_lifecycle.updated" }
            missing.append("workspace_lifecycle.updated:archived")
        }
        let ordered = containsRequiredOrder(sequence) && hasArchivedLifecycle
        let ready = finalBlockers.isEmpty && missing.isEmpty && ordered
        let detail: String
        if ready {
            detail = "Native lifecycle proof covers create -> demand intake -> worktree -> delivery -> archive with confirmed writes and audit."
        } else {
            let blockers = finalBlockers + missing.map { "missing audit \($0)" } + (ordered ? [] : ["audit order is incomplete"])
            detail = "Native lifecycle proof blockers: \(blockers.joined(separator: "; "))"
        }
        return NativeLifecycleProofEvidence(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            status: ready ? .ready : .blocked,
            detail: detail,
            orderedActions: sequence,
            missingActions: missing
        )
    }

    private static func finalStateBlockers(for workspace: WorkspaceSummary) -> [String] {
        let lifecycleStage = workspace.lifecycle.stage.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let archived = workspace.state == .archived || lifecycleStage == "archived"
        let hasDeliveryEvidence = workspace.documentLinks["delivery-cn"]?.isEmpty == false
            || workspace.documentLinks["delivery"]?.isEmpty == false
        let servicesReady = !workspace.services.isEmpty && workspace.services.allSatisfy { service in
            service.sourceExists && service.worktreeExists
        }
        let noActiveTasks = workspace.tasks.allSatisfy { !$0.isActive }

        var blockers: [String] = []
        if !archived {
            blockers.append("workspace is not archived")
        }
        if !hasDeliveryEvidence {
            blockers.append("delivery evidence is missing")
        }
        if !servicesReady {
            blockers.append("services are not backed by source repos and worktrees")
        }
        if !noActiveTasks {
            blockers.append("active tasks remain")
        }
        if !workspace.risks.isEmpty {
            blockers.append("open risks remain")
        }
        return blockers
    }

    private static func chronologicalRelevantEvents(
        for workspace: WorkspaceSummary,
        auditEvents: [AuditEvent]
    ) -> [AuditEvent] {
        auditEvents
            .reversed()
            .filter { eventMatches($0, workspace: workspace) }
    }

    private static func eventMatches(_ event: AuditEvent, workspace: WorkspaceSummary) -> Bool {
        let values = [event.target, event.summary] + Array(event.metadata.values)
        return values.contains { value in
            value == workspace.id
                || value == workspace.path
                || value.contains(workspace.path)
                || value.contains(workspace.folder)
        }
    }

    private static func orderedSequence(in events: [AuditEvent]) -> [String] {
        events.reduce(into: []) { sequence, event in
            let action = event.action
            if action == "workspace_lifecycle.updated" && !isArchivedLifecycleEvent(event) {
                return
            }
            guard requiredAuditActions.contains(action) else { return }
            if sequence.last != action {
                sequence.append(action)
            }
        }
    }

    private static func containsRequiredOrder(_ sequence: [String]) -> Bool {
        var cursor = sequence.startIndex
        for action in requiredAuditActions {
            guard let match = sequence[cursor...].firstIndex(of: action) else {
                return false
            }
            cursor = sequence.index(after: match)
        }
        return true
    }

    private static func hasArchivedLifecycleEvent(_ events: [AuditEvent]) -> Bool {
        events.contains(where: isArchivedLifecycleEvent)
    }

    private static func isArchivedLifecycleEvent(_ event: AuditEvent) -> Bool {
        event.action == "workspace_lifecycle.updated"
            && event.metadata["state"]?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "archived"
    }
}
