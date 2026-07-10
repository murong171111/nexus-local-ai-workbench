import CryptoKit
import Foundation
import NexusBridge

enum NativeDeliveryRecordWriteKind: String, Hashable {
    case deliverySnapshot
    case archiveChecklist
    case validationPrSnapshot

    var auditAction: String {
        switch self {
        case .deliverySnapshot:
            return "delivery_record.snapshot_appended"
        case .archiveChecklist:
            return "archive_checklist.snapshot_appended"
        case .validationPrSnapshot:
            return "validation_pr.snapshot_appended"
        }
    }

    var auditSummary: String {
        switch self {
        case .deliverySnapshot:
            return "Appended Delivery Gate snapshot to delivery record"
        case .archiveChecklist:
            return "Appended archive checklist to delivery record"
        case .validationPrSnapshot:
            return "Appended validation and PR snapshot to delivery record"
        }
    }
}

enum NativeDeliveryRecordDocumentRevision: Hashable {
    case missing
    case regularUTF8(sha256: String, byteCount: Int)
    case invalid(reason: String)

    var blockerSummary: String? {
        guard case .invalid(let reason) = self else { return nil }
        return reason
    }

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

struct NativeDeliveryRecordWriteResponse: Hashable {
    let kind: NativeDeliveryRecordWriteKind
    let path: String
    let status: WorkflowPathStatus
    let itemCount: Int
    let appended: Bool
    let auditEventID: String?
    let auditEventPath: String?
    let auditError: String?
}

enum NativeDeliveryRecordStore {
    static func inspectRevision(
        at path: String,
        fileManager: FileManager = .default
    ) -> NativeDeliveryRecordDocumentRevision {
        inspectDocument(at: path, fileManager: fileManager).revision
    }

    static func appendDeliverySnapshot(
        plan: DeliveryRecordWritePlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil
    ) throws -> NativeDeliveryRecordWriteResponse {
        try append(
            kind: .deliverySnapshot,
            deliveryPath: plan.deliveryPath,
            workspaceID: plan.workspaceID,
            workspaceName: plan.workspaceName,
            status: plan.status,
            itemCount: plan.items.count,
            appendedMarkdown: plan.appendedMarkdown,
            expectedRevision: plan.expectedRevision,
            canWrite: plan.canWrite,
            notWritableSummary: plan.summary,
            confirmed: confirmed,
            auditRoot: auditRoot,
            actor: actor
        )
    }

    static func appendArchiveChecklist(
        plan: ArchiveChecklistWritePlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil
    ) throws -> NativeDeliveryRecordWriteResponse {
        try append(
            kind: .archiveChecklist,
            deliveryPath: plan.deliveryPath,
            workspaceID: plan.workspaceID,
            workspaceName: plan.workspaceName,
            status: plan.status,
            itemCount: plan.items.count,
            appendedMarkdown: plan.appendedMarkdown,
            expectedRevision: plan.expectedRevision,
            canWrite: plan.canWrite,
            notWritableSummary: plan.summary,
            confirmed: confirmed,
            auditRoot: auditRoot,
            actor: actor
        )
    }

    static func appendValidationPrSnapshot(
        plan: ValidationPrWritePlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil
    ) throws -> NativeDeliveryRecordWriteResponse {
        try append(
            kind: .validationPrSnapshot,
            deliveryPath: plan.deliveryPath,
            workspaceID: plan.workspaceID,
            workspaceName: plan.workspaceName,
            status: plan.status,
            itemCount: plan.items.count,
            appendedMarkdown: plan.appendedMarkdown,
            expectedRevision: plan.expectedRevision,
            canWrite: plan.canWrite,
            notWritableSummary: plan.summary,
            confirmed: confirmed,
            auditRoot: auditRoot,
            actor: actor
        )
    }

    private static func append(
        kind: NativeDeliveryRecordWriteKind,
        deliveryPath: String,
        workspaceID: String,
        workspaceName: String,
        status: WorkflowPathStatus,
        itemCount: Int,
        appendedMarkdown: String,
        expectedRevision: NativeDeliveryRecordDocumentRevision,
        canWrite: Bool,
        notWritableSummary: String,
        confirmed: Bool,
        auditRoot: String?,
        actor: String?
    ) throws -> NativeDeliveryRecordWriteResponse {
        guard confirmed else {
            throw NativeDeliveryRecordStoreError.unconfirmed
        }
        if case .invalid(let reason) = expectedRevision {
            throw NativeDeliveryRecordStoreError.invalidExpectedRevision(reason)
        }
        guard canWrite else {
            throw NativeDeliveryRecordStoreError.notWritable(notWritableSummary)
        }

        try appendMarkdownBlock(
            appendedMarkdown,
            toFile: deliveryPath,
            expectedRevision: expectedRevision,
            fileManager: .default
        )
        let response = NativeDeliveryRecordWriteResponse(
            kind: kind,
            path: deliveryPath,
            status: status,
            itemCount: itemCount,
            appended: true,
            auditEventID: nil,
            auditEventPath: nil,
            auditError: nil
        )
        let audit = appendAuditEvent(
            response: response,
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            auditRoot: auditRoot,
            actor: actor
        )
        return NativeDeliveryRecordWriteResponse(
            kind: response.kind,
            path: response.path,
            status: response.status,
            itemCount: response.itemCount,
            appended: response.appended,
            auditEventID: audit.response?.event.id,
            auditEventPath: audit.response?.path,
            auditError: audit.error
        )
    }

    private static func appendMarkdownBlock(
        _ block: String,
        toFile path: String,
        expectedRevision: NativeDeliveryRecordDocumentRevision,
        fileManager: FileManager
    ) throws {
        let url = expandedURL(for: path)
        let current = inspectDocument(at: path, fileManager: fileManager)
        if case .invalid(let reason) = current.revision {
            throw NativeDeliveryRecordStoreError.invalidCurrentDocument(reason)
        }
        guard current.revision == expectedRevision else {
            throw NativeDeliveryRecordStoreError.staleDocument(
                path: path,
                expected: expectedRevision.label,
                current: current.revision.label
            )
        }

        var content = current.content ?? "# 交付记录\n"
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
        response: NativeDeliveryRecordWriteResponse,
        workspaceID: String,
        workspaceName: String,
        auditRoot: String?,
        actor: String?
    ) -> NativeAuditAppendFeedback {
        NativeAuditEventStore.appendFeedback(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: actor ?? "Nexus Native",
                action: response.kind.auditAction,
                target: response.path,
                summary: response.kind.auditSummary,
                metadata: [
                    "workspaceID": workspaceID,
                    "workspaceName": workspaceName,
                    "deliveryPath": response.path,
                    "status": response.status.rawValue,
                    "itemCount": "\(response.itemCount)",
                    "kind": response.kind.rawValue
                ]
            )
        )
    }

    private struct DeliveryRecordDocumentSnapshot {
        let revision: NativeDeliveryRecordDocumentRevision
        let content: String?
    }

    private static func expandedURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func inspectDocument(
        at path: String,
        fileManager: FileManager
    ) -> DeliveryRecordDocumentSnapshot {
        let url = expandedURL(for: path)
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
                && error.code == NSFileReadNoSuchFileError {
            return DeliveryRecordDocumentSnapshot(revision: .missing, content: nil)
        } catch {
            return DeliveryRecordDocumentSnapshot(
                revision: .invalid(
                    reason: "delivery record is unreadable: \(url.path): \(error.localizedDescription)"
                ),
                content: nil
            )
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            return DeliveryRecordDocumentSnapshot(
                revision: .invalid(reason: "delivery record is not a regular file: \(url.path)"),
                content: nil
            )
        }
        do {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) else {
                return DeliveryRecordDocumentSnapshot(
                    revision: .invalid(reason: "delivery record is not valid UTF-8: \(url.path)"),
                    content: nil
                )
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return DeliveryRecordDocumentSnapshot(
                revision: .regularUTF8(sha256: digest, byteCount: data.count),
                content: content
            )
        } catch {
            return DeliveryRecordDocumentSnapshot(
                revision: .invalid(
                    reason: "delivery record is unreadable: \(url.path): \(error.localizedDescription)"
                ),
                content: nil
            )
        }
    }
}

private enum NativeDeliveryRecordStoreError: LocalizedError {
    case unconfirmed
    case notWritable(String)
    case invalidExpectedRevision(String)
    case invalidCurrentDocument(String)
    case staleDocument(path: String, expected: String, current: String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "delivery record write requires explicit confirmation"
        case .notWritable(let summary):
            return summary
        case .invalidExpectedRevision(let reason):
            return reason
        case .invalidCurrentDocument(let reason):
            return reason
        case .staleDocument(let path, let expected, let current):
            return "delivery record changed since confirmation: \(path): expected \(expected), found \(current)"
        }
    }
}
