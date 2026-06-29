import Foundation
import NexusBridge

struct NativeScopeFreezeWriteResponse: Hashable {
    let path: String
    let status: WorkflowPathStatus
    let appended: Bool
    let auditEventID: String?
    let auditEventPath: String?
}

enum NativeScopeFreezeStore {
    static func write(
        plan: ScopeFreezeWritePlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil
    ) throws -> NativeScopeFreezeWriteResponse {
        guard confirmed else {
            throw NativeScopeFreezeStoreError.unconfirmed
        }
        guard plan.canWrite else {
            throw NativeScopeFreezeStoreError.notWritable(plan.summary)
        }

        try appendMarkdownBlock(plan.appendedMarkdown, toFile: plan.scopePath, fallbackHeader: "")
        let response = NativeScopeFreezeWriteResponse(
            path: plan.scopePath,
            status: plan.status,
            appended: true,
            auditEventID: nil,
            auditEventPath: nil
        )
        let audit = appendAuditEvent(plan: plan, response: response, auditRoot: auditRoot, actor: actor)
        return NativeScopeFreezeWriteResponse(
            path: response.path,
            status: response.status,
            appended: response.appended,
            auditEventID: audit?.event.id,
            auditEventPath: audit?.path
        )
    }

    private static func appendMarkdownBlock(
        _ block: String,
        toFile path: String,
        fallbackHeader: String
    ) throws {
        var content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? fallbackHeader
        if !content.isEmpty, !content.hasSuffix("\n") {
            content.append("\n")
        }
        content.append(block)
        if !content.hasSuffix("\n") {
            content.append("\n")
        }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private static func appendAuditEvent(
        plan: ScopeFreezeWritePlan,
        response: NativeScopeFreezeWriteResponse,
        auditRoot: String?,
        actor: String?
    ) -> AppendAuditEventResponse? {
        guard let auditRoot = auditRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
              !auditRoot.isEmpty else {
            return nil
        }
        return try? NativeAuditEventStore.append(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: actor ?? "Nexus Native",
                action: "scope.freeze_confirmed",
                target: response.path,
                summary: "Appended scope freeze confirmation to scope.md",
                metadata: [
                    "workspaceID": plan.workspaceID,
                    "workspaceName": plan.workspaceName,
                    "scopePath": response.path,
                    "status": response.status.rawValue
                ]
            )
        )
    }
}

private enum NativeScopeFreezeStoreError: LocalizedError {
    case unconfirmed
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "scope freeze write requires explicit confirmation"
        case .notWritable(let summary):
            return summary
        }
    }
}
