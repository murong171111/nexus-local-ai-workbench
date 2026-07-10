import Foundation
import NexusBridge

enum NativeWorkspaceLifecycleStore {
    private struct LifecycleDocumentSnapshot {
        let url: URL
        let content: String?

        func contentOrFallback(_ fallback: String) -> String {
            content ?? fallback
        }
    }

    static func update(
        request: UpdateWorkspaceLifecycleRequest,
        expectedState: String,
        fileManager: FileManager = .default,
        writeFile: (String, URL) throws -> Void = { content, url in
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
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
        let workspaceSnapshot = try documentSnapshot(at: workspaceDocumentURL, fileManager: fileManager)
        let statusSnapshot = try documentSnapshot(at: statusDocumentURL, fileManager: fileManager)
        let workspaceContent = workspaceSnapshot.contentOrFallback("# Workspace\n\n")
        let statusContent = statusSnapshot.contentOrFallback("# STATUS\n\n")
        let currentState = try currentLifecycleState(
            workspaceContent: workspaceSnapshot.content,
            statusContent: statusSnapshot.content
        )
        let normalizedExpected = try normalizedExpectedState(expectedState)
        guard currentState == normalizedExpected else {
            throw NativeWorkspaceLifecycleStoreError.staleConfirmation(
                expected: normalizedExpected,
                current: currentState
            )
        }
        let previousState = currentState

        let focus = sanitizedCell(request.focus).flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultFocus(for: state)
        let nextAction = sanitizedCell(request.nextAction).flatMap { $0.isEmpty ? nil : $0 }
            ?? defaultNextAction(for: state)
        let updatedAt = isoTimestamp()

        let nextStatusContent = updateStatusDocument(
            statusContent,
            state: state,
            focus: focus,
            nextAction: nextAction,
            updatedAt: updatedAt
        )
        let nextWorkspaceContent = upsertBulletValue(
            in: workspaceContent,
            label: "当前状态",
            aliases: ["状态"],
            value: state
        )
        do {
            try writeFile(nextWorkspaceContent, workspaceDocumentURL)
            try writeFile(nextStatusContent, statusDocumentURL)
        } catch {
            let writeFailure = error.localizedDescription
            let restoreFailures = restoreSnapshots(
                snapshots: [statusSnapshot, workspaceSnapshot],
                fileManager: fileManager,
                writeFile: writeFile
            )
            if !restoreFailures.isEmpty {
                throw NativeWorkspaceLifecycleStoreError.rollbackFailed(
                    writeFailure: writeFailure,
                    rollbackFailures: restoreFailures
                )
            }
            throw NativeWorkspaceLifecycleStoreError.writeFailed(writeFailure)
        }

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
            auditEventID: audit.response?.event.id,
            auditEventPath: audit.response?.path,
            auditError: audit.error
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

    private static func documentSnapshot(
        at url: URL,
        fileManager: FileManager
    ) throws -> LifecycleDocumentSnapshot {
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return LifecycleDocumentSnapshot(url: url, content: nil)
        } catch {
            throw NativeWorkspaceLifecycleStoreError.documentUnreadable(
                url.path,
                error.localizedDescription
            )
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw NativeWorkspaceLifecycleStoreError.documentNotFile(url.path)
        }
        do {
            return LifecycleDocumentSnapshot(
                url: url,
                content: try String(contentsOf: url, encoding: .utf8)
            )
        } catch {
            throw NativeWorkspaceLifecycleStoreError.documentUnreadable(
                url.path,
                error.localizedDescription
            )
        }
    }

    private static func restore(
        _ snapshot: LifecycleDocumentSnapshot,
        fileManager: FileManager,
        writeFile: (String, URL) throws -> Void
    ) throws {
        if let content = snapshot.content {
            try writeFile(content, snapshot.url)
        } else if fileManager.fileExists(atPath: snapshot.url.path) {
            try fileManager.removeItem(at: snapshot.url)
        }
    }

    private static func restoreSnapshots(
        snapshots: [LifecycleDocumentSnapshot],
        fileManager: FileManager,
        writeFile: (String, URL) throws -> Void
    ) -> [String] {
        snapshots.compactMap { snapshot in
            do {
                try restore(snapshot, fileManager: fileManager, writeFile: writeFile)
                return nil
            } catch {
                return "\(snapshot.url.lastPathComponent): \(error.localizedDescription)"
            }
        }
    }

    private static func acceptedBulletValues(in text: String?, labels: [String]) -> [String] {
        guard let text else { return [] }
        return text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for label in labels {
                for prefix in ["- \(label):", "- \(label)："] where trimmed.hasPrefix(prefix) {
                    let value = trimmed
                        .dropFirst(prefix.count)
                        .replacingOccurrences(of: "`", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    return value.isEmpty ? nil : value
                }
            }
            return nil
        }
    }

    private static func normalizedDocumentState(
        in text: String?,
        source: String
    ) throws -> String? {
        let values = acceptedBulletValues(in: text, labels: ["当前状态", "状态"])
        guard !values.isEmpty else { return nil }

        let normalizedStates = try values.map { try normalizedCurrentState($0, source: source) }
        var distinctStates: [String] = []
        for state in normalizedStates where !distinctStates.contains(state) {
            distinctStates.append(state)
        }
        if distinctStates.count > 1 {
            throw NativeWorkspaceLifecycleStoreError.conflictingStatesWithinDocument(
                source,
                distinctStates
            )
        }
        return distinctStates.first
    }

    private static func normalizedCurrentState(_ raw: String, source: String) throws -> String {
        do {
            return try normalizedLifecycleState(raw)
        } catch {
            throw NativeWorkspaceLifecycleStoreError.unsupportedCurrentState(source, raw)
        }
    }

    private static func currentLifecycleState(
        workspaceContent: String?,
        statusContent: String?
    ) throws -> String {
        let workspaceState = try normalizedDocumentState(
            in: workspaceContent,
            source: "workspace.md"
        )
        let statusState = try normalizedDocumentState(
            in: statusContent,
            source: "STATUS.md"
        )

        if let workspaceState, let statusState, workspaceState != statusState {
            throw NativeWorkspaceLifecycleStoreError.conflictingCurrentStates(
                workspaceState,
                statusState
            )
        }
        return workspaceState ?? statusState ?? "unknown"
    }

    private static func normalizedExpectedState(_ value: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.lowercased() == "unknown" {
            return "unknown"
        }
        do {
            return try normalizedLifecycleState(trimmed)
        } catch {
            throw NativeWorkspaceLifecycleStoreError.unsupportedExpectedState(trimmed)
        }
    }

    private static func upsertBulletValue(
        in text: String,
        label: String,
        aliases: [String] = [],
        value: String
    ) -> String {
        var replaced = false
        var lines = text.components(separatedBy: "\n")
        let hadTrailingNewline = text.hasSuffix("\n")
        let acceptedLabels = [label] + aliases
        if hadTrailingNewline {
            lines.removeLast()
        }

        lines = lines.compactMap { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if acceptedLabels.contains(where: {
                trimmed.hasPrefix("- \($0):") || trimmed.hasPrefix("- \($0)：")
            }) {
                guard !replaced else { return nil }
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
        let withState = upsertBulletValue(
            in: text,
            label: "状态",
            aliases: ["当前状态"],
            value: state
        )
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
    ) -> NativeAuditAppendFeedback {
        NativeAuditEventStore.appendFeedback(
            auditRoot: request.auditRoot,
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
    case documentNotFile(String)
    case documentUnreadable(String, String)
    case unsupportedCurrentState(String, String)
    case unsupportedExpectedState(String)
    case conflictingStatesWithinDocument(String, [String])
    case conflictingCurrentStates(String, String)
    case staleConfirmation(expected: String, current: String)
    case writeFailed(String)
    case rollbackFailed(writeFailure: String, rollbackFailures: [String])

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
        case .documentNotFile(let path):
            return "lifecycle document is not a file: \(path)"
        case .documentUnreadable(let path, let reason):
            return "lifecycle document is unreadable: \(path): \(reason)"
        case .unsupportedCurrentState(let source, let state):
            return "unsupported current lifecycle state: \(source)=\(state)"
        case .unsupportedExpectedState(let state):
            return "unsupported expected lifecycle state: \(state)"
        case .conflictingStatesWithinDocument(let source, let states):
            return "workspace lifecycle file contains conflicting states: \(source)=\(states.joined(separator: ", "))"
        case .conflictingCurrentStates(let workspaceState, let statusState):
            return "workspace lifecycle files conflict: workspace.md=\(workspaceState), STATUS.md=\(statusState)"
        case .staleConfirmation(let expected, let current):
            return "workspace lifecycle changed since confirmation: expected \(expected), found \(current)"
        case .writeFailed(let reason):
            return "workspace lifecycle write failed and original documents were restored: \(reason)"
        case .rollbackFailed(let writeFailure, let rollbackFailures):
            return "workspace lifecycle write failed and rollback is incomplete: \(writeFailure); \(rollbackFailures.joined(separator: "; "))"
        }
    }
}
