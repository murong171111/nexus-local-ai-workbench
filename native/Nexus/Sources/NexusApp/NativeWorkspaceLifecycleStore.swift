import Foundation
import NexusBridge

enum NativeWorkspaceLifecycleStore {
    static func update(
        request: UpdateWorkspaceLifecycleRequest,
        fileManager: FileManager = .default
    ) throws -> UpdateWorkspaceLifecycleResponse {
        guard request.confirmed else {
            throw NativeWorkspaceLifecycleStoreError.unconfirmed
        }

        let state = try normalizedLifecycleState(request.state)
        let workspaceURL = expandedURL(for: request.workspacePath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: workspaceURL.path, isDirectory: &isDirectory) else {
            throw NativeWorkspaceLifecycleStoreError.workspaceMissing(workspaceURL.path)
        }
        guard isDirectory.boolValue else {
            throw NativeWorkspaceLifecycleStoreError.workspaceNotDirectory(workspaceURL.path)
        }

        let workspaceDocumentURL = workspaceURL.appendingPathComponent("workspace.md", isDirectory: false)
        let statusDocumentURL = workspaceURL.appendingPathComponent("STATUS.md", isDirectory: false)
        let workspaceContent = (try? String(contentsOf: workspaceDocumentURL, encoding: .utf8)) ?? "# Workspace\n\n"
        let previousState = extractBulletValue(in: workspaceContent, label: "当前状态") ?? "unknown"

        let focus = sanitizedCell(request.focus).flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultFocus(for: state)
        let nextAction = sanitizedCell(request.nextAction).flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultNextAction(for: state)
        let updatedAt = isoTimestamp()

        let nextWorkspaceContent = upsertBulletValue(in: workspaceContent, label: "当前状态", value: state)
        try nextWorkspaceContent.write(to: workspaceDocumentURL, atomically: true, encoding: .utf8)

        let statusContent = (try? String(contentsOf: statusDocumentURL, encoding: .utf8)) ?? "# STATUS\n\n"
        let nextStatusContent = updateStatusDocument(
            statusContent,
            state: state,
            focus: focus,
            nextAction: nextAction,
            updatedAt: updatedAt
        )
        try nextStatusContent.write(to: statusDocumentURL, atomically: true, encoding: .utf8)

        let response = UpdateWorkspaceLifecycleResponse(
            workspacePath: workspaceURL.path,
            workspaceDocumentPath: workspaceDocumentURL.path,
            statusDocumentPath: statusDocumentURL.path,
            previousState: previousState,
            state: state,
            focus: focus,
            nextAction: nextAction,
            updated: true
        )
        let audit = appendAuditEvent(request: request, response: response)
        return UpdateWorkspaceLifecycleResponse(
            workspacePath: response.workspacePath,
            workspaceDocumentPath: response.workspaceDocumentPath,
            statusDocumentPath: response.statusDocumentPath,
            previousState: response.previousState,
            state: response.state,
            focus: response.focus,
            nextAction: response.nextAction,
            updated: response.updated,
            auditEventID: audit?.event.id,
            auditEventPath: audit?.path
        )
    }

    private static func expandedURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func sanitizedCell(_ value: String?) -> String? {
        value?
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func extractBulletValue(in text: String, label: String) -> String? {
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for prefix in ["- \(label):", "- \(label)："] where trimmed.hasPrefix(prefix) {
                return trimmed
                    .dropFirst(prefix.count)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .replacingOccurrences(of: "`", with: "")
            }
        }
        return nil
    }

    private static func upsertBulletValue(in text: String, label: String, value: String) -> String {
        var replaced = false
        var lines = text.components(separatedBy: "\n")
        let hadTrailingNewline = text.hasSuffix("\n")
        if hadTrailingNewline {
            lines.removeLast()
        }

        lines = lines.map { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if ["- \(label):", "- \(label)："].contains(where: { trimmed.hasPrefix($0) }) {
                replaced = true
                return "- \(label): \(value)"
            }
            return line
        }

        if !replaced {
            if !lines.isEmpty, lines.last?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false {
                lines.append("")
            }
            lines.append("- \(label): \(value)")
        }

        var content = lines.joined(separator: "\n")
        if hadTrailingNewline || !content.hasSuffix("\n") {
            content.append("\n")
        }
        return content
    }

    private static func updateStatusDocument(
        _ text: String,
        state: String,
        focus: String,
        nextAction: String,
        updatedAt: String
    ) -> String {
        let withState = upsertBulletValue(in: text, label: "状态", value: state)
        let withFocus = upsertBulletValue(in: withState, label: "当前焦点", value: focus)
        let withNextAction = upsertBulletValue(in: withFocus, label: "下一步", value: nextAction)
        return upsertBulletValue(in: withNextAction, label: "更新时间", value: updatedAt)
    }

    private static func normalizedLifecycleState(_ value: String) throws -> String {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "scoping", "scope", "analyzing", "analysis", "范围确认", "分析中":
            return "scoping"
        case "setup", "environment", "环境准备", "准备中":
            return "setup"
        case "developing", "development", "dev", "开发中":
            return "developing"
        case "delivery", "delivering", "交付", "交付整理":
            return "delivery"
        case "done", "ready", "completed", "complete", "完成", "已完成":
            return "done"
        case "blocked", "block", "阻塞":
            return "blocked"
        case "archived", "archive", "归档", "已归档":
            return "archived"
        default:
            throw NativeWorkspaceLifecycleStoreError.unsupportedState(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
    }

    private static func defaultFocus(for state: String) -> String {
        switch state {
        case "scoping":
            return "确认需求范围、服务范围和目标分支"
        case "setup":
            return "创建 workspace-local worktree 并完成就绪检查"
        case "developing":
            return "编码、验证，并持续同步交付记录"
        case "delivery":
            return "补齐交付记录、SQL、验证和风险说明"
        case "done":
            return "确认 PR、CI、发布和遗留风险"
        case "blocked":
            return "解除阻塞项"
        case "archived":
            return "保留历史上下文"
        default:
            return "继续处理工作区"
        }
    }

    private static func defaultNextAction(for state: String) -> String {
        switch state {
        case "scoping":
            return "补齐 workspace.md、services.md 和 branches.md"
        case "setup":
            return "确认后创建缺失 worktree"
        case "developing":
            return "继续开发并运行必要验证"
        case "delivery":
            return "更新交付记录并完成验证"
        case "done":
            return "确认可以归档或进入观察"
        case "blocked":
            return "先处理阻塞原因，再恢复生命周期"
        case "archived":
            return "需要再次开发时从 handoff 恢复上下文"
        default:
            return "刷新 Nexus 并确认下一步"
        }
    }

    private static func isoTimestamp() -> String {
        ISO8601DateFormatter().string(from: Date())
    }

    private static func appendAuditEvent(
        request: UpdateWorkspaceLifecycleRequest,
        response: UpdateWorkspaceLifecycleResponse
    ) -> AppendAuditEventResponse? {
        guard let auditRoot = request.auditRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
              !auditRoot.isEmpty else {
            return nil
        }
        return try? NativeAuditEventStore.append(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: request.actor ?? "Nexus Native",
                action: "workspace_lifecycle.updated",
                target: response.statusDocumentPath,
                summary: "Updated lifecycle from \(response.previousState) to \(response.state)",
                metadata: [
                    "workspace": response.workspacePath,
                    "workspaceDocument": response.workspaceDocumentPath,
                    "statusDocument": response.statusDocumentPath,
                    "previousState": response.previousState,
                    "state": response.state,
                    "focus": response.focus,
                    "nextAction": response.nextAction
                ]
            )
        )
    }
}

private enum NativeWorkspaceLifecycleStoreError: LocalizedError {
    case unconfirmed
    case workspaceMissing(String)
    case workspaceNotDirectory(String)
    case unsupportedState(String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "workspace lifecycle update requires explicit confirmation"
        case .workspaceMissing(let path):
            return "workspace does not exist: \(path)"
        case .workspaceNotDirectory(let path):
            return "workspace is not a directory: \(path)"
        case .unsupportedState(let state):
            return "unsupported lifecycle state: \(state)"
        }
    }
}
