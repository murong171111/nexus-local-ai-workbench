import CryptoKit
import Foundation
import NexusBridge

enum NativeDemandTaskDocumentRevision: Hashable {
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

struct NativeDemandTaskDocumentSnapshot {
    let revision: NativeDemandTaskDocumentRevision
    let content: String?
}

struct NativeDemandTaskTransferResponse: Hashable {
    let path: String
    let transferredItems: [DemandTaskTransferItem]
    let duplicateCount: Int
    let transferred: Bool
    let auditEventID: String?
    let auditEventPath: String?

    var transferredCount: Int {
        transferredItems.count
    }
}

enum NativeDemandTaskTransferStore {
    static func inspectDocument(
        at path: String,
        fileManager: FileManager = .default
    ) -> NativeDemandTaskDocumentSnapshot {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain
                && error.code == NSFileReadNoSuchFileError {
            return NativeDemandTaskDocumentSnapshot(revision: .missing, content: nil)
        } catch {
            return NativeDemandTaskDocumentSnapshot(
                revision: .invalid(
                    reason: "demand task document is unreadable: \(url.path): \(error.localizedDescription)"
                ),
                content: nil
            )
        }
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            return NativeDemandTaskDocumentSnapshot(
                revision: .invalid(reason: "demand task document is not a regular file: \(url.path)"),
                content: nil
            )
        }
        do {
            let data = try Data(contentsOf: url)
            guard let content = String(data: data, encoding: .utf8) else {
                return NativeDemandTaskDocumentSnapshot(
                    revision: .invalid(reason: "demand task document is not valid UTF-8: \(url.path)"),
                    content: nil
                )
            }
            let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
            return NativeDemandTaskDocumentSnapshot(
                revision: .regularUTF8(sha256: digest, byteCount: data.count),
                content: content
            )
        } catch {
            return NativeDemandTaskDocumentSnapshot(
                revision: .invalid(
                    reason: "demand task document is unreadable: \(url.path): \(error.localizedDescription)"
                ),
                content: nil
            )
        }
    }

    static func transfer(
        plan: DemandTaskTransferPlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default
    ) throws -> NativeDemandTaskTransferResponse {
        guard confirmed else {
            throw NativeDemandTaskTransferStoreError.unconfirmed
        }
        guard plan.hasTransferableItems else {
            throw NativeDemandTaskTransferStoreError.noTransferableItems
        }

        var content = try readOrCreateExecutionTasksDocument(
            at: plan.executionTasksPath,
            fileManager: fileManager
        )
        if !content.contains("## Requirement Tasks") {
            if !content.hasSuffix("\n") {
                content.append("\n")
            }
            content.append("\n## Requirement Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n")
        } else if !content.hasSuffix("\n") {
            content.append("\n")
        }

        for item in plan.transferableItems {
            content.append(item.markdownRow)
            content.append("\n")
        }

        try content.write(toFile: plan.executionTasksPath, atomically: true, encoding: .utf8)
        let response = NativeDemandTaskTransferResponse(
            path: plan.executionTasksPath,
            transferredItems: plan.transferableItems,
            duplicateCount: plan.duplicateCount,
            transferred: true,
            auditEventID: nil,
            auditEventPath: nil
        )
        let audit = appendAuditEvent(plan: plan, response: response, auditRoot: auditRoot, actor: actor)
        return NativeDemandTaskTransferResponse(
            path: response.path,
            transferredItems: response.transferredItems,
            duplicateCount: response.duplicateCount,
            transferred: response.transferred,
            auditEventID: audit?.event.id,
            auditEventPath: audit?.path
        )
    }

    private static func readOrCreateExecutionTasksDocument(
        at path: String,
        fileManager: FileManager
    ) throws -> String {
        let fileURL = URL(fileURLWithPath: path)
        let parentURL = fileURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        if fileManager.fileExists(atPath: path) {
            return try String(contentsOfFile: path, encoding: .utf8)
        }
        return "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n"
    }

    private static func appendAuditEvent(
        plan: DemandTaskTransferPlan,
        response: NativeDemandTaskTransferResponse,
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
                action: "demand_tasks.transferred",
                target: response.path,
                summary: "Transferred \(response.transferredCount) demand tasks into root tasks.md",
                metadata: [
                    "workspace": plan.workspacePath,
                    "intakeTasksPath": plan.intakeTasksPath,
                    "executionTasksPath": response.path,
                    "transferredCount": "\(response.transferredCount)",
                    "duplicateCount": "\(response.duplicateCount)",
                    "taskTitles": response.transferredItems.map(\.title).joined(separator: " | ")
                ]
            )
        )
    }
}

private enum NativeDemandTaskTransferStoreError: LocalizedError {
    case unconfirmed
    case noTransferableItems

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "demand task transfer requires explicit confirmation"
        case .noTransferableItems:
            return "no new demand tasks can be transferred into root tasks.md"
        }
    }
}
