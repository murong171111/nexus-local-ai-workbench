import CryptoKit
import Foundation
import NexusBridge

enum NativeScopeDocumentRevision: Hashable {
    case missing
    case regularUTF8(sha256: String, byteCount: Int)
    case invalid(reason: String)

    var label: String {
        switch self {
        case .missing:
            return "missing"
        case .regularUTF8(let sha256, let byteCount):
            return "regular UTF-8 \(byteCount) bytes sha256=\(sha256)"
        case .invalid(let reason):
            return "invalid: \(reason)"
        }
    }
}

struct NativeScopeFreezeWriteResponse: Hashable {
    let path: String
    let status: WorkflowPathStatus
    let appended: Bool
    let auditEventID: String?
    let auditEventPath: String?
}

struct NativeScopeDocumentSnapshot {
    let revision: NativeScopeDocumentRevision
    let content: String?
}

enum NativeScopeFreezeStore {
    static func inspectRevision(
        at path: String,
        fileManager: FileManager = .default
    ) -> NativeScopeDocumentRevision {
        inspectDocument(at: path, fileManager: fileManager).revision
    }

    static func write(
        plan: ScopeFreezeWritePlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default
    ) throws -> NativeScopeFreezeWriteResponse {
        guard confirmed else {
            throw NativeScopeFreezeStoreError.unconfirmed
        }
        guard case .regularUTF8 = plan.expectedRevision else {
            throw NativeScopeFreezeStoreError.invalidExpectedRevision(plan.expectedRevision.label)
        }
        guard plan.canWrite else {
            throw NativeScopeFreezeStoreError.notWritable(plan.summary)
        }

        let url = expandedURL(for: plan.scopePath)
        let current = inspectDocument(at: plan.scopePath, fileManager: fileManager)
        if case .invalid(let reason) = current.revision {
            throw NativeScopeFreezeStoreError.invalidCurrentDocument(reason)
        }
        guard case .regularUTF8 = current.revision else {
            throw NativeScopeFreezeStoreError.staleDocument(
                path: plan.scopePath,
                expected: plan.expectedRevision.label,
                current: current.revision.label
            )
        }
        guard current.revision == plan.expectedRevision else {
            throw NativeScopeFreezeStoreError.staleDocument(
                path: plan.scopePath,
                expected: plan.expectedRevision.label,
                current: current.revision.label
            )
        }

        try appendMarkdownBlock(plan.appendedMarkdown, to: current.content!, at: url)
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
        to currentContent: String,
        at url: URL
    ) throws {
        var content = currentContent
        if !content.isEmpty, !content.hasSuffix("\n") {
            content.append("\n")
        }
        content.append(block)
        if !content.hasSuffix("\n") {
            content.append("\n")
        }
        try content.write(to: url, atomically: true, encoding: .utf8)
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

    static func inspectDocument(
        at path: String,
        fileManager: FileManager
    ) -> NativeScopeDocumentSnapshot {
        let url = expandedURL(for: path)
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
                && error.code == NSFileReadNoSuchFileError {
            return NativeScopeDocumentSnapshot(revision: .missing, content: nil)
        } catch {
            return NativeScopeDocumentSnapshot(
                revision: .invalid(
                    reason: "scope document is unreadable: \(url.path): \(error.localizedDescription)"
                ),
                content: nil
            )
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            return NativeScopeDocumentSnapshot(
                revision: .invalid(reason: "scope document is not a regular file: \(url.path)"),
                content: nil
            )
        }
        do {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) else {
                return NativeScopeDocumentSnapshot(
                    revision: .invalid(reason: "scope document is not valid UTF-8: \(url.path)"),
                    content: nil
                )
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return NativeScopeDocumentSnapshot(
                revision: .regularUTF8(sha256: digest, byteCount: data.count),
                content: content
            )
        } catch {
            return NativeScopeDocumentSnapshot(
                revision: .invalid(
                    reason: "scope document is unreadable: \(url.path): \(error.localizedDescription)"
                ),
                content: nil
            )
        }
    }

    private static func expandedURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}

private enum NativeScopeFreezeStoreError: LocalizedError {
    case unconfirmed
    case notWritable(String)
    case invalidExpectedRevision(String)
    case invalidCurrentDocument(String)
    case staleDocument(path: String, expected: String, current: String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "scope freeze write requires explicit confirmation"
        case .notWritable(let summary):
            return summary
        case .invalidExpectedRevision(let reason):
            return reason
        case .invalidCurrentDocument(let reason):
            return reason
        case .staleDocument(let path, let expected, let current):
            return "scope document changed since confirmation: \(path); expected \(expected); current \(current)"
        }
    }
}
