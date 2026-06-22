import Foundation
import NexusBridge

enum AgentActionSurfaceKind: String, Hashable {
    case approval
    case answer
    case toolReview

    var statusLabel: String {
        switch self {
        case .approval:
            "需确认 / approval"
        case .answer:
            "待回复 / answer"
        case .toolReview:
            "需复核 / review"
        }
    }

    var systemImage: String {
        switch self {
        case .approval:
            "hand.raised"
        case .answer:
            "text.bubble"
        case .toolReview:
            "terminal"
        }
    }
}

struct AgentActionResponse: Hashable, Identifiable {
    let id: String
    let label: String
    let systemImage: String
    let payload: String
}

struct AgentActionSurface: Hashable {
    let kind: AgentActionSurfaceKind
    let title: String
    let detail: String
    let safetyNote: String
    let primaryResponse: AgentActionResponse
    let secondaryResponse: AgentActionResponse?

    init?(event: AgentEvent) {
        let normalizedKind = event.kind.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let category = event.fallbackTaskDraft.category
        let command = Self.firstMetadataValue(
            in: event,
            matching: ["command", "cmd", "operation", "tool", "toolName"]
        )
        let target = event.workspaceFolder ?? event.metadata["workspaceFolder"] ?? event.metadata["workspace"] ?? "No workspace"

        switch category {
        case "approval":
            kind = .approval
            title = "审批请求 / Approval request"
            detail = command.map { "Agent 请求执行或继续：\($0)" }
                ?? "Agent 请求一个需要人工确认的操作。"
            safetyNote = "Nexus 只复制可审查回应，不会执行 metadata 中的命令，也不会替你授权。"
            primaryResponse = AgentActionResponse(
                id: "approval-approve",
                label: "复制批准回应 / Copy approve",
                systemImage: "checkmark.circle",
                payload: Self.responsePayload(
                    heading: "Nexus approval response",
                    event: event,
                    target: target,
                    decision: "Approved by user",
                    body: [
                        "Scope: only the operation described by this event.",
                        "Safety: do not run additional commands or broaden permissions without another explicit user confirmation.",
                        "Command: \(command ?? "not provided")"
                    ]
                )
            )
            secondaryResponse = AgentActionResponse(
                id: "approval-deny",
                label: "复制拒绝回应 / Copy deny",
                systemImage: "xmark.circle",
                payload: Self.responsePayload(
                    heading: "Nexus approval response",
                    event: event,
                    target: target,
                    decision: "Not approved",
                    body: [
                        "Do not execute the requested operation.",
                        "Explain the safer alternative or ask for a narrower request.",
                        "Command: \(command ?? "not provided")"
                    ]
                )
            )
        case "answer":
            kind = .answer
            title = "Agent 提问 / Question"
            detail = "把答复模板复制给当前 Agent，补充答案后再继续。"
            safetyNote = "模板会带上事件上下文，但答案仍需要你确认后再发送。"
            primaryResponse = AgentActionResponse(
                id: "answer-template",
                label: "复制答复模板 / Copy answer",
                systemImage: "text.bubble",
                payload: Self.responsePayload(
                    heading: "Nexus answer response",
                    event: event,
                    target: target,
                    decision: "Answer from user",
                    body: [
                        "Answer: <fill in the answer before sending>",
                        "Continue only after applying this answer to the current workspace context.",
                        "Question summary: \(event.summary)"
                    ]
                )
            )
            secondaryResponse = AgentActionResponse(
                id: "answer-more-context",
                label: "复制补充上下文请求 / Ask context",
                systemImage: "questionmark.circle",
                payload: Self.responsePayload(
                    heading: "Nexus answer response",
                    event: event,
                    target: target,
                    decision: "Need more context",
                    body: [
                        "Please clarify the missing information before making code, file, git, SQL, or delivery-document changes.",
                        "Keep the current workspace unchanged until the question is resolved."
                    ]
                )
            )
        case "tool-review" where normalizedKind == "tool_use" || normalizedKind == "tool-use" || normalizedKind == "tool":
            kind = .toolReview
            title = "工具调用复核 / Tool review"
            detail = command.map { "待复核工具或命令：\($0)" }
                ?? "Agent 记录了一个需要复核的工具调用。"
            safetyNote = "这里只给出复核结论模板；本地命令仍必须通过明确确认流程执行。"
            primaryResponse = AgentActionResponse(
                id: "tool-review-note",
                label: "复制复核结论 / Copy review",
                systemImage: "doc.on.clipboard",
                payload: Self.responsePayload(
                    heading: "Nexus tool review response",
                    event: event,
                    target: target,
                    decision: "Reviewed in Nexus",
                    body: [
                        "Result: <safe / needs changes / blocked>",
                        "Reason: <write the review reason before sending>",
                        "Tool or command: \(command ?? "not provided")"
                    ]
                )
            )
            secondaryResponse = nil
        default:
            return nil
        }
    }

    private static func firstMetadataValue(in event: AgentEvent, matching keys: [String]) -> String? {
        let normalizedKeys = keys.map { $0.lowercased() }
        return event.metadata
            .sorted { $0.key < $1.key }
            .first { item in
                let normalizedKey = item.key.lowercased()
                return !item.value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    && normalizedKeys.contains(where: { normalizedKey.contains($0) })
            }?
            .value
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func responsePayload(
        heading: String,
        event: AgentEvent,
        target: String,
        decision: String,
        body: [String]
    ) -> String {
        let bodyLines = body.map { "- \($0)" }.joined(separator: "\n")
        return """
        \(heading)

        Decision:
        - \(decision)

        Event:
        - Title: \(event.title)
        - Kind: \(event.kind)
        - Severity: \(event.severity)
        - Source: \(event.source)
        - Session: \(event.sessionId)
        - Workspace: \(target)
        - Event ID: \(event.id)

        Response:
        \(bodyLines)
        """
    }
}

struct AgentInboxSummary {
    let actionRequired: [AgentEvent]
    let recent: [AgentEvent]
    let totalCount: Int

    init(events: [AgentEvent]) {
        totalCount = events.count
        actionRequired = events.filter(Self.requiresAction)
        let actionIDs = Set(actionRequired.map(\.id))
        recent = events.filter { !actionIDs.contains($0.id) }
    }

    var isEmpty: Bool {
        totalCount == 0
    }

    var pendingLabel: String {
        actionRequired.isEmpty ? "0 pending" : "\(actionRequired.count) pending"
    }

    static func requiresAction(_ event: AgentEvent) -> Bool {
        if AgentActionSurface(event: event) != nil {
            return true
        }

        return event.severity.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "error"
    }
}

struct AgentWorkflowSummary: Hashable {
    let pendingEventCount: Int
    let recentEventCount: Int
    let agentTaskCount: Int
    let openTaskCount: Int

    init(inbox: AgentInboxSummary, agentTaskCount: Int, openTaskCount: Int) {
        pendingEventCount = inbox.actionRequired.count
        recentEventCount = inbox.recent.count
        self.agentTaskCount = agentTaskCount
        self.openTaskCount = openTaskCount
    }

    var shouldShow: Bool {
        pendingEventCount > 0 || agentTaskCount > 0
    }

    var title: String {
        if pendingEventCount > 0 && agentTaskCount > 0 {
            return "事件与任务待跟进 / Active flow"
        }
        if pendingEventCount > 0 {
            return "先处理 Agent 事件 / Review inbox"
        }
        return "Agent 任务待跟进 / Agent tasks"
    }

    var detail: String {
        if pendingEventCount > 0 && agentTaskCount > 0 {
            return "先处理审批、问题或工具复核；已写入 tasks.md 的 Agent 任务从任务中心继续。"
        }
        if pendingEventCount > 0 {
            return "打开 Inbox 中的事件，复制回应模板或确认写入任务草稿。"
        }
        return "这些任务来自 Agent 事件，继续从 Task Center 处理、定位或交接 Codex。"
    }

    var metricLabel: String {
        "\(pendingEventCount) inbox / \(agentTaskCount) tasks"
    }
}
