import Foundation
import NexusBridge

struct NativeDemandTaskTransferResponse: Hashable {
    let path: String
    let transferredItems: [DemandTaskTransferItem]
    let duplicateCount: Int
    let transferred: Bool

    var transferredCount: Int {
        transferredItems.count
    }
}

enum NativeDemandTaskTransferStore {
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
            transferred: true
        )
        appendAuditEvent(plan: plan, response: response, auditRoot: auditRoot, actor: actor)
        return response
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
    ) {
        guard let auditRoot = auditRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
              !auditRoot.isEmpty else {
            return
        }
        _ = try? NativeAuditEventStore.append(
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
