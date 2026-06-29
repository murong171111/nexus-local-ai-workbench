import Foundation
import CryptoKit
import NexusBridge

struct NativeLifecycleProofBundle: Codable, Hashable {
    let schemaVersion: Int
    let generatedAt: String
    let workspace: NativeLifecycleProofWorkspaceSnapshot
    let proof: NativeLifecycleProofSnapshot
    let evidenceFiles: [NativeLifecycleProofFileSnapshot]
    let auditChain: [NativeLifecycleProofAuditSnapshot]
    let missingEvidenceFiles: [String]
    let unverifiedEvidenceFiles: [String]?

    var ready: Bool {
        proof.ready && missingEvidenceFiles.isEmpty && (unverifiedEvidenceFiles ?? []).isEmpty
    }

    static func resolve(
        workspace: WorkspaceSummary,
        auditEvents: [AuditEvent],
        generatedAt: Date = Date(),
        fileManager: FileManager = .default
    ) -> NativeLifecycleProofBundle {
        let proof = NativeLifecycleProofEvidence.resolve(workspace: workspace, auditEvents: auditEvents)
        let files = requiredEvidenceFiles(for: workspace).map { relativePath in
            let path = URL(fileURLWithPath: workspace.path).appendingPathComponent(relativePath).path
            let fileURL = URL(fileURLWithPath: path)
            let exists = fileManager.fileExists(atPath: path)
            let data = exists ? try? Data(contentsOf: fileURL) : nil
            let size = fileSize(path: path, fileManager: fileManager)
            return NativeLifecycleProofFileSnapshot(
                relativePath: relativePath,
                path: path,
                exists: exists,
                sizeBytes: size,
                sha256: data.map(sha256Hex)
            )
        }
        let missingFiles = files
            .filter { !$0.exists }
            .map(\.relativePath)
        let unverifiedFiles = files
            .filter { $0.exists && ($0.sizeBytes == nil || $0.sha256 == nil) }
            .map(\.relativePath)
        let chain = chronologicalRelevantEvents(for: workspace, auditEvents: auditEvents)
            .filter(NativeLifecycleProofEvidence.isRequiredAuditEvent)
            .map(NativeLifecycleProofAuditSnapshot.init(event:))

        return NativeLifecycleProofBundle(
            schemaVersion: 1,
            generatedAt: ISO8601DateFormatter().string(from: generatedAt),
            workspace: NativeLifecycleProofWorkspaceSnapshot(workspace: workspace),
            proof: NativeLifecycleProofSnapshot(
                evidence: proof,
                missingEvidenceFiles: missingFiles,
                unverifiedEvidenceFiles: unverifiedFiles
            ),
            evidenceFiles: files,
            auditChain: chain,
            missingEvidenceFiles: missingFiles,
            unverifiedEvidenceFiles: unverifiedFiles
        )
    }

    static func jsonData(for bundle: NativeLifecycleProofBundle) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(bundle)
    }

    private static func requiredEvidenceFiles(for workspace: WorkspaceSummary) -> [String] {
        var files = [
            "workspace.md",
            "STATUS.md",
            "services.md",
            "branches.md",
            "需求/requirement.md",
            "需求/questions.md",
            "需求/scope.md",
            "需求/tasks.md",
            "需求/delivery.md",
            "tasks.md",
            "交付记录.md"
        ]
        files.append(contentsOf: workspace.sqlFiles.map(\.relativePath))
        return Array(Set(files)).sorted()
    }

    private static func chronologicalRelevantEvents(
        for workspace: WorkspaceSummary,
        auditEvents: [AuditEvent]
    ) -> [AuditEvent] {
        auditEvents
            .reversed()
            .filter { eventMatches($0, workspace: workspace) }
    }

    private static func eventMatches(_ event: AuditEvent, workspace: WorkspaceSummary) -> Bool {
        let values = [event.target, event.summary] + Array(event.metadata.values)
        return values.contains { value in
            value == workspace.id
                || value == workspace.path
                || value.contains(workspace.path)
                || value.contains(workspace.folder)
        }
    }

    private static func fileSize(path: String, fileManager: FileManager) -> Int? {
        guard let size = try? fileManager.attributesOfItem(atPath: path)[.size] as? NSNumber else {
            return nil
        }
        return size.intValue
    }

    static func sha256Hex(data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

struct NativeLifecycleProofWorkspaceSnapshot: Codable, Hashable {
    let id: String
    let name: String
    let folder: String
    let path: String
    let state: String
    let lifecycleStage: String
    let targetBranch: String
    let serviceCount: Int
    let activeTaskCount: Int
    let riskCount: Int

    init(workspace: WorkspaceSummary) {
        id = workspace.id
        name = workspace.name
        folder = workspace.folder
        path = workspace.path
        state = workspace.state.rawValue
        lifecycleStage = workspace.lifecycle.stage
        targetBranch = workspace.branch
        serviceCount = workspace.services.count
        activeTaskCount = workspace.tasks.filter(\.isActive).count
        riskCount = workspace.risks.count
    }
}

struct NativeLifecycleProofSnapshot: Codable, Hashable {
    let ready: Bool
    let status: String
    let detail: String
    let orderedActions: [String]
    let requiredAuditActions: [String]
    let missingActions: [String]
    let missingEvidenceFiles: [String]
    let unverifiedEvidenceFiles: [String]?

    init(
        evidence: NativeLifecycleProofEvidence,
        missingEvidenceFiles: [String],
        unverifiedEvidenceFiles: [String]
    ) {
        ready = evidence.ready && missingEvidenceFiles.isEmpty && unverifiedEvidenceFiles.isEmpty
        status = ready ? WorkflowPathStatus.ready.rawValue : WorkflowPathStatus.blocked.rawValue
        let fileBlockers = [
            missingEvidenceFiles.isEmpty ? nil : "Missing evidence files: \(missingEvidenceFiles.joined(separator: ", ")).",
            unverifiedEvidenceFiles.isEmpty ? nil : "Unverified evidence files: \(unverifiedEvidenceFiles.joined(separator: ", "))."
        ].compactMap { $0 }
        detail = fileBlockers.isEmpty ? evidence.detail : "\(evidence.detail) \(fileBlockers.joined(separator: " "))"
        orderedActions = evidence.orderedActions
        requiredAuditActions = NativeLifecycleProofEvidence.requiredAuditActions
        missingActions = evidence.missingActions
        self.missingEvidenceFiles = missingEvidenceFiles
        self.unverifiedEvidenceFiles = unverifiedEvidenceFiles
    }
}

struct NativeLifecycleProofFileSnapshot: Codable, Hashable {
    let relativePath: String
    let path: String
    let exists: Bool
    let sizeBytes: Int?
    let sha256: String?
}

struct NativeLifecycleProofAuditSnapshot: Codable, Hashable {
    let id: String
    let timestamp: String
    let actor: String
    let action: String
    let target: String
    let summary: String
    let metadata: [String: String]

    init(event: AuditEvent) {
        id = event.id
        timestamp = event.timestamp
        actor = event.actor
        action = event.action
        target = event.target
        summary = event.summary
        metadata = event.metadata
    }
}

struct NativeLifecycleProofBundleWriteResponse: Hashable {
    let path: String
    let ready: Bool
    let auditEventID: String?
    let auditEventPath: String?
}

struct NativeLifecycleProofBundleExportPlan: Identifiable {
    let workspace: WorkspaceSummary
    let bundle: NativeLifecycleProofBundle
    let auditEvents: [AuditEvent]
    let path: String

    var id: WorkspaceSummary.ID { workspace.id }

    var canWrite: Bool {
        bundle.ready
    }

    var status: WorkflowPathStatus {
        bundle.ready ? .ready : .blocked
    }

    var summary: String {
        if bundle.ready {
            return "Ready to export native-lifecycle-proof.json with \(bundle.auditChain.count) audit events and \(bundle.evidenceFiles.count) hashed evidence files."
        }
        return bundle.proof.detail
    }
}

enum NativeLifecycleProofBundleStore {
    static let fileName = "native-lifecycle-proof.json"

    static func bundlePath(for workspace: WorkspaceSummary) -> String {
        URL(fileURLWithPath: workspace.path)
            .appendingPathComponent(fileName)
            .path
    }

    static func load(workspace: WorkspaceSummary) throws -> NativeLifecycleProofBundle {
        let data = try Data(contentsOf: URL(fileURLWithPath: bundlePath(for: workspace)))
        return try JSONDecoder().decode(NativeLifecycleProofBundle.self, from: data)
    }

    static func write(
        workspace: WorkspaceSummary,
        auditEvents: [AuditEvent],
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> NativeLifecycleProofBundleWriteResponse {
        guard confirmed else {
            throw NativeLifecycleProofBundleStoreError.unconfirmed
        }

        let bundle = NativeLifecycleProofBundle.resolve(
            workspace: workspace,
            auditEvents: auditEvents,
            generatedAt: now,
            fileManager: fileManager
        )
        guard bundle.ready else {
            throw NativeLifecycleProofBundleStoreError.notReady(bundle.proof.detail)
        }

        let outputURL = URL(fileURLWithPath: bundlePath(for: workspace))
        let payload = try NativeLifecycleProofBundle.jsonData(for: bundle)
        let bundleSHA256 = NativeLifecycleProofBundle.sha256Hex(data: payload)
        try payload.write(to: outputURL, options: .atomic)

        let audit = appendAuditEvent(
            workspace: workspace,
            outputPath: outputURL.path,
            bundle: bundle,
            bundleSHA256: bundleSHA256,
            auditRoot: auditRoot,
            actor: actor
        )
        return NativeLifecycleProofBundleWriteResponse(
            path: outputURL.path,
            ready: bundle.ready,
            auditEventID: audit?.event.id,
            auditEventPath: audit?.path
        )
    }

    private static func appendAuditEvent(
        workspace: WorkspaceSummary,
        outputPath: String,
        bundle: NativeLifecycleProofBundle,
        bundleSHA256: String,
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
                action: "native_lifecycle_proof.exported",
                target: outputPath,
                summary: "Exported Native lifecycle proof bundle",
                metadata: [
                    "workspaceID": workspace.id,
                    "workspaceName": workspace.name,
                    "workspace": workspace.path,
                    "bundlePath": outputPath,
                    "ready": "\(bundle.ready)",
                    "auditActionCount": "\(bundle.auditChain.count)",
                    "evidenceFileCount": "\(bundle.evidenceFiles.count)",
                    "unverifiedEvidenceFileCount": "\((bundle.unverifiedEvidenceFiles ?? []).count)",
                    "bundleSHA256": bundleSHA256
                ]
            )
        )
    }
}

private enum NativeLifecycleProofBundleStoreError: LocalizedError {
    case unconfirmed
    case notReady(String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "native lifecycle proof export requires explicit confirmation"
        case .notReady(let detail):
            return "native lifecycle proof is not ready: \(detail)"
        }
    }
}
