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

struct NativeDeliveryRecordWriteResponse: Hashable {
    let kind: NativeDeliveryRecordWriteKind
    let path: String
    let status: WorkflowPathStatus
    let itemCount: Int
    let appended: Bool
    let auditEventID: String?
    let auditEventPath: String?
}

enum NativeDeliveryRecordStore {
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
        canWrite: Bool,
        notWritableSummary: String,
        confirmed: Bool,
        auditRoot: String?,
        actor: String?
    ) throws -> NativeDeliveryRecordWriteResponse {
        guard confirmed else {
            throw NativeDeliveryRecordStoreError.unconfirmed
        }
        guard canWrite else {
            throw NativeDeliveryRecordStoreError.notWritable(notWritableSummary)
        }

        try appendMarkdownBlock(appendedMarkdown, toFile: deliveryPath, fallbackHeader: "# 交付记录\n")
        let response = NativeDeliveryRecordWriteResponse(
            kind: kind,
            path: deliveryPath,
            status: status,
            itemCount: itemCount,
            appended: true,
            auditEventID: nil,
            auditEventPath: nil
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
        response: NativeDeliveryRecordWriteResponse,
        workspaceID: String,
        workspaceName: String,
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
}

private enum NativeDeliveryRecordStoreError: LocalizedError {
    case unconfirmed
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "delivery record write requires explicit confirmation"
        case .notWritable(let summary):
            return summary
        }
    }
}
