import Foundation

struct WorkspaceMainStageEvidenceLink: Identifiable, Hashable {
    let id: String
    let label: String
    let systemImage: String
    let action: WorkspaceMainStageAction?
}

struct WorkspaceStageAnswer: Hashable {
    let stageID: WorkspaceMainStageID
    let stageLabel: String
    let status: WorkflowPathStatus
    let reason: String
    let nextActionLabel: String
    let nextAction: WorkspaceMainStageAction
    let evidenceLinks: [WorkspaceMainStageEvidenceLink]

    var routedEvidenceLinks: [WorkspaceMainStageEvidenceLink] {
        evidenceLinks.filter { $0.action != nil }
    }

    var canAnswerCurrentState: Bool {
        !stageLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !nextActionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !routedEvidenceLinks.isEmpty
    }
}

extension WorkspaceMainStage {
    var evidenceLinks: [WorkspaceMainStageEvidenceLink] {
        evidence.enumerated().map { index, evidence in
            WorkspaceMainStageEvidenceLink.resolve(evidence, index: index)
        }
    }

    var answer: WorkspaceStageAnswer {
        WorkspaceStageAnswer(
            stageID: id,
            stageLabel: title,
            status: status,
            reason: reason,
            nextActionLabel: primaryActionLabel,
            nextAction: primaryAction,
            evidenceLinks: evidenceLinks
        )
    }
}

private extension WorkspaceMainStageEvidenceLink {
    static func resolve(_ evidence: String, index: Int) -> WorkspaceMainStageEvidenceLink {
        let trimmed = evidence.trimmingCharacters(in: .whitespacesAndNewlines)
        let lowercased = trimmed.lowercased()
        let action: WorkspaceMainStageAction?
        let systemImage: String

        if trimmed.hasPrefix("/") {
            action = .path(trimmed)
            systemImage = "doc.text"
        } else if lowercased.contains("需求/scope.md") {
            action = .document("scope")
            systemImage = "scope"
        } else if lowercased.contains("需求/tasks.md") {
            action = .document("demandTasks")
            systemImage = "checklist"
        } else if lowercased.contains("需求/questions.md") {
            action = .document("questions")
            systemImage = "questionmark.circle"
        } else if lowercased.contains("需求/requirement.md") {
            action = .document("requirement")
            systemImage = "text.quote"
        } else if lowercased == "需求/" || lowercased.contains("需求/") {
            action = .demandIntake
            systemImage = "text.badge.checkmark"
        } else if lowercased.contains("workspace.md") {
            action = .document("workspace")
            systemImage = "folder"
        } else if lowercased.contains("status.md") {
            action = .document("status")
            systemImage = "gauge.with.dots.needle.67percent"
        } else if lowercased.contains("services.md") {
            action = .document("services")
            systemImage = "square.stack.3d.up"
        } else if lowercased.contains("branches.md") {
            action = .document("branches")
            systemImage = "arrow.triangle.branch"
        } else if lowercased.contains("tasks.md") {
            action = .document("tasks")
            systemImage = "checklist"
        } else if trimmed.contains("交付记录.md") {
            action = .document("delivery")
            systemImage = "doc.text.magnifyingglass"
        } else if lowercased.contains("handoff.md") {
            action = .document("handoff")
            systemImage = "point.3.connected.trianglepath.dotted"
        } else if lowercased.contains("sql/") || lowercased.contains(".sql") {
            action = .document("sql")
            systemImage = "cylinder.split.1x2"
        } else if lowercased.contains("scripts/worktree-commands.sh") {
            action = .document("worktreeScript")
            systemImage = "terminal"
        } else if lowercased.contains("repos/") || lowercased.contains("source-repos/") {
            action = .worktree
            systemImage = "terminal"
        } else if trimmed.contains("恢复开发") {
            action = .lifecycle(.restoreDevelopment)
            systemImage = "arrow.uturn.backward.circle"
        } else {
            action = nil
            systemImage = "doc.text"
        }

        return WorkspaceMainStageEvidenceLink(
            id: "\(index):\(trimmed)",
            label: trimmed,
            systemImage: systemImage,
            action: action
        )
    }
}
