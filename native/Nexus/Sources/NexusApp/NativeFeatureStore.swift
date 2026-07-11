import CryptoKit
import Darwin
import Foundation
import NexusBridge

enum NativeFeatureStore {
    private static let fileName = "FEATURES.md"
    private static let idPattern = try! NSRegularExpression(pattern: #"^F-[0-9]{3,}$"#)
    private static let headingPattern = try! NSRegularExpression(pattern: #"^## (F-[^ ]*) (.+)$"#)
    private static let metadataLabels = [
        "Status", "Verification", "Auto complete", "Source", "Services", "Tasks", "Evidence",
        "Completed at", "Completed by", "Completion note", "Evidence stale"
    ]
    private static let lockRegistry = NSLock()
    private static var locksByWorkspace: [String: NSLock] = [:]

    static func inspect(workspacePath: String) -> FeatureDocumentSnapshot {
        do {
            return try load(workspacePath: workspacePath)
        } catch {
            let path = featureURL(workspacePath).path
            return FeatureDocumentSnapshot(
                document: .empty,
                revision: .invalid(reason: error.localizedDescription),
                path: path
            )
        }
    }

    static func load(workspacePath: String) throws -> FeatureDocumentSnapshot {
        let workspaceURL = try validatedWorkspaceURL(workspacePath)
        let url = workspaceURL.appendingPathComponent(fileName)
        let inspected = try inspectFile(url)
        switch inspected {
        case .missing:
            return FeatureDocumentSnapshot(document: .empty, revision: .missing, path: url.path)
        case .regular(let content, let revision):
            return FeatureDocumentSnapshot(document: try parse(content), revision: revision, path: url.path)
        }
    }

    static func makePlan(workspacePath: String, mutation: FeatureMutation) throws -> FeatureWritePlan {
        let snapshot = try load(workspacePath: workspacePath)
        let expectedFeature: WorkspaceFeature?
        switch mutation {
        case .add:
            expectedFeature = nil
        case .update(let expected, _):
            expectedFeature = expected
        case .setStatus(let id, _, _), .cancel(let id, _):
            expectedFeature = snapshot.document.features.first { $0.id == id }
            guard expectedFeature != nil else { throw NativeFeatureStoreError.featureNotFound(id) }
        }
        return FeatureWritePlan(
            workspacePath: workspacePath,
            path: snapshot.path,
            revision: snapshot.revision,
            document: snapshot.document,
            expectedFeature: expectedFeature,
            mutation: mutation
        )
    }

    static func write(
        plan: FeatureWritePlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil
    ) throws -> FeatureWriteResponse {
        guard confirmed else { throw NativeFeatureStoreError.unconfirmed }
        if case .invalid(let reason) = plan.revision {
            throw NativeFeatureStoreError.invalidDocument(reason)
        }

        let mutationActor = actor ?? "Nexus Native"
        let result = try writeLock(for: plan.workspacePath).withLock {
            () -> (FeatureDocument, FeatureDocumentRevision) in
            let current = try load(workspacePath: plan.workspacePath)
            guard current.path == plan.path, current.revision == plan.revision else {
                throw NativeFeatureStoreError.staleRevision(
                    expected: plan.revision.label,
                    current: current.revision.label
                )
            }
            if let expected = plan.expectedFeature,
               current.document.features.first(where: { $0.id == expected.id }) != expected {
                throw NativeFeatureStoreError.staleFeature(expected.id)
            }

            var document = current.document
            try apply(plan.mutation, actor: mutationActor, to: &document)
            try validate(document)
            let data = Data(render(document).utf8)
            try data.write(to: URL(fileURLWithPath: plan.path), options: .atomic)
            let written = try load(workspacePath: plan.workspacePath)
            return (written.document, written.revision)
        }

        let id = mutationID(plan.mutation)
        let writtenFeature = result.0.features.first { $0.id == id }
        let audit = NativeAuditEventStore.appendFeedback(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: mutationActor,
                action: auditAction(plan.mutation),
                target: plan.path,
                summary: auditSummary(plan.mutation),
                metadata: [
                    "workspace": plan.workspacePath,
                    "featureID": id,
                    "policy": writtenFeature?.verification.rawValue ?? "",
                    "evidenceIDs": writtenFeature?.evidenceIDs.joined(separator: ",") ?? "",
                    "previousStatus": plan.expectedFeature?.status.rawValue ?? "missing",
                    "nextStatus": writtenFeature?.status.rawValue ?? "missing",
                    "sourceRevision": plan.revision.label,
                    "revision": result.1.label
                ]
            )
        )
        return FeatureWriteResponse(
            path: plan.path,
            revision: result.1,
            document: result.0,
            auditEventID: audit.response?.event.id,
            auditEventPath: audit.response?.path,
            auditError: audit.error
        )
    }

    static func parse(_ source: String) throws -> FeatureDocument {
        let lines = source.components(separatedBy: "\n")
        var preamble: [String] = []
        var blocks: [(id: String, title: String, lines: [String])] = []
        var current: (id: String, title: String, lines: [String])?

        for line in lines {
            if let heading = featureHeading(line) {
                if let current { blocks.append(current) }
                current = (heading.id, heading.title, [])
            } else if line.hasPrefix("## F-") {
                throw NativeFeatureStoreError.invalidHeading(line)
            } else if current == nil {
                preamble.append(line)
            } else {
                current!.lines.append(line)
            }
        }
        if let current { blocks.append(current) }

        var ids = Set<String>()
        let features = try blocks.map { block -> WorkspaceFeature in
            guard validID(block.id) else { throw NativeFeatureStoreError.invalidID(block.id) }
            guard ids.insert(block.id).inserted else { throw NativeFeatureStoreError.duplicateID(block.id) }
            return try parseFeature(block)
        }
        return FeatureDocument(preamble: preamble, features: features)
    }

    static func render(_ document: FeatureDocument) -> String {
        var lines = document.preamble
        while lines.last == "" { lines.removeLast() }
        for feature in document.features {
            if !lines.isEmpty { lines.append("") }
            lines.append("## \(feature.id) \(feature.title)")
            lines.append("")
            lines.append("- Status: \(feature.status.rawValue)")
            lines.append("- Verification: \(feature.verification.rawValue)")
            lines.append("- Auto complete: \(feature.autoComplete)")
            appendList("Source", feature.sources, to: &lines)
            appendList("Services", feature.services, to: &lines)
            appendList("Tasks", feature.taskIDs, to: &lines)
            appendList("Evidence", feature.evidenceIDs, to: &lines)
            lines.append("- Completed at: \(feature.completedAt ?? "")")
            lines.append("- Completed by: \(feature.completedBy ?? "")")
            if let note = feature.completionNote { lines.append("- Completion note: \(note)") }
            if feature.evidenceStale { lines.append("- Evidence stale: true") }
            if !feature.preservedLines.isEmpty {
                if feature.preservedLines.first != "" { lines.append("") }
                lines.append(contentsOf: feature.preservedLines)
            }
        }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func parseFeature(
        _ block: (id: String, title: String, lines: [String])
    ) throws -> WorkspaceFeature {
        let title = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw NativeFeatureStoreError.missingRequired("title", block.id) }
        var values: [String: String] = [:]
        var preserved: [String] = []
        for line in block.lines {
            guard let metadata = recognizedMetadata(line) else {
                preserved.append(line)
                continue
            }
            guard values[metadata.label] == nil else {
                throw NativeFeatureStoreError.duplicateMetadata(metadata.label, block.id)
            }
            values[metadata.label] = metadata.value
        }
        guard let statusValue = values["Status"], let status = FeatureStatus(rawValue: statusValue) else {
            throw NativeFeatureStoreError.missingRequired("valid Status", block.id)
        }
        guard let verificationValue = values["Verification"],
              let verification = FeatureVerificationPolicy(rawValue: verificationValue) else {
            throw NativeFeatureStoreError.missingRequired("valid Verification", block.id)
        }
        guard let autoValue = values["Auto complete"], let autoComplete = Bool(autoValue) else {
            throw NativeFeatureStoreError.missingRequired("valid Auto complete", block.id)
        }
        if let staleValue = values["Evidence stale"], Bool(staleValue) == nil {
            throw NativeFeatureStoreError.invalidMetadata("Evidence stale", block.id)
        }
        let description = preserved
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkspaceFeature(
            id: block.id,
            title: title,
            status: status,
            verification: verification,
            autoComplete: autoComplete,
            sources: list(values["Source"]),
            services: list(values["Services"]),
            taskIDs: list(values["Tasks"]),
            evidenceIDs: list(values["Evidence"]),
            description: description,
            completedAt: optional(values["Completed at"]),
            completedBy: optional(values["Completed by"]),
            completionNote: optional(values["Completion note"]),
            evidenceStale: values["Evidence stale"].flatMap(Bool.init) ?? false,
            preservedLines: preserved
        )
    }

    private static func apply(
        _ mutation: FeatureMutation,
        actor: String,
        to document: inout FeatureDocument
    ) throws {
        switch mutation {
        case .add(let feature):
            guard validID(feature.id) else { throw NativeFeatureStoreError.invalidID(feature.id) }
            guard !document.features.contains(where: { $0.id == feature.id }) else {
                throw NativeFeatureStoreError.duplicateID(feature.id)
            }
            document.features.append(feature)
        case .update(let expected, let replacement):
            guard expected.id == replacement.id else { throw NativeFeatureStoreError.changedID }
            guard let index = document.features.firstIndex(of: expected) else {
                throw NativeFeatureStoreError.staleFeature(expected.id)
            }
            document.features[index] = replacement
        case .setStatus(let id, let status, let completionNote):
            guard let index = document.features.firstIndex(where: { $0.id == id }) else {
                throw NativeFeatureStoreError.featureNotFound(id)
            }
            document.features[index].status = status
            document.features[index].completionNote = completionNote
            if status == .done {
                document.features[index].completedAt = ISO8601DateFormatter().string(from: Date())
                document.features[index].completedBy = actor
            } else {
                document.features[index].completedAt = nil
                document.features[index].completedBy = nil
            }
        case .cancel(let id, let reason):
            guard let index = document.features.firstIndex(where: { $0.id == id }) else {
                throw NativeFeatureStoreError.featureNotFound(id)
            }
            document.features[index].status = .cancelled
            document.features[index].completionNote = reason
            document.features[index].completedAt = nil
            document.features[index].completedBy = nil
        }
    }

    private static func validate(_ document: FeatureDocument) throws {
        var ids = Set<String>()
        for feature in document.features {
            guard validID(feature.id) else { throw NativeFeatureStoreError.invalidID(feature.id) }
            guard ids.insert(feature.id).inserted else {
                throw NativeFeatureStoreError.duplicateID(feature.id)
            }
            guard !feature.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NativeFeatureStoreError.missingRequired("title", feature.id)
            }
        }
    }

    private static func featureHeading(_ line: String) -> (id: String, title: String)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = headingPattern.firstMatch(in: line, range: range),
              let idRange = Range(match.range(at: 1), in: line),
              let titleRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[idRange]), String(line[titleRange]))
    }

    private static func recognizedMetadata(_ line: String) -> (label: String, value: String)? {
        for label in metadataLabels {
            let prefix = "- \(label):"
            if line.hasPrefix(prefix) {
                return (label, String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private static func validID(_ id: String) -> Bool {
        idPattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil
    }

    private static func list(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func optional(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func appendList(_ label: String, _ values: [String], to lines: inout [String]) {
        let normalized = Array(Set(values.filter { !$0.isEmpty })).sorted()
        if !normalized.isEmpty { lines.append("- \(label): \(normalized.joined(separator: ", "))") }
    }

    private static func inspectFile(_ url: URL) throws -> InspectedFile {
        var info = stat()
        if lstat(url.path, &info) != 0 {
            if errno == ENOENT { return .missing }
            throw NativeFeatureStoreError.unreadable(url.path)
        }
        guard (info.st_mode & S_IFMT) == S_IFREG else {
            throw NativeFeatureStoreError.notRegularFile(url.path)
        }
        let data = try Data(contentsOf: url)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NativeFeatureStoreError.invalidUTF8(url.path)
        }
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return .regular(content, .regularUTF8(sha256: digest, byteCount: data.count))
    }

    private static func validatedWorkspaceURL(_ path: String) throws -> URL {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
        var info = stat()
        guard lstat(url.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFDIR else {
            throw NativeFeatureStoreError.invalidWorkspace(url.path)
        }
        return url
    }

    private static func featureURL(_ workspacePath: String) -> URL {
        URL(fileURLWithPath: (workspacePath as NSString).expandingTildeInPath)
            .standardizedFileURL
            .appendingPathComponent(fileName)
    }

    private static func writeLock(for workspacePath: String) -> NSLock {
        lockRegistry.withLock {
            if let lock = locksByWorkspace[workspacePath] { return lock }
            let lock = NSLock()
            locksByWorkspace[workspacePath] = lock
            return lock
        }
    }

    private static func mutationID(_ mutation: FeatureMutation) -> String {
        switch mutation {
        case .add(let feature): return feature.id
        case .update(let expected, _): return expected.id
        case .setStatus(let id, _, _), .cancel(let id, _): return id
        }
    }

    private static func auditAction(_ mutation: FeatureMutation) -> String {
        switch mutation {
        case .add: return "feature.added"
        case .update: return "feature.updated"
        case .setStatus: return "feature.status_changed"
        case .cancel: return "feature.cancelled"
        }
    }

    private static func auditSummary(_ mutation: FeatureMutation) -> String {
        "Confirmed feature mutation: \(auditAction(mutation))"
    }
}

private enum InspectedFile {
    case missing
    case regular(String, FeatureDocumentRevision)
}

private enum NativeFeatureStoreError: LocalizedError {
    case unconfirmed
    case invalidWorkspace(String)
    case unreadable(String)
    case notRegularFile(String)
    case invalidUTF8(String)
    case invalidDocument(String)
    case invalidHeading(String)
    case invalidID(String)
    case duplicateID(String)
    case duplicateMetadata(String, String)
    case missingRequired(String, String)
    case invalidMetadata(String, String)
    case staleRevision(expected: String, current: String)
    case staleFeature(String)
    case featureNotFound(String)
    case changedID

    var errorDescription: String? {
        switch self {
        case .unconfirmed: return "feature write requires explicit confirmation"
        case .invalidWorkspace(let path): return "workspace is not a regular directory: \(path)"
        case .unreadable(let path): return "feature document is unreadable: \(path)"
        case .notRegularFile(let path): return "feature document is not a regular file: \(path)"
        case .invalidUTF8(let path): return "feature document is not valid UTF-8: \(path)"
        case .invalidDocument(let reason): return reason
        case .invalidHeading(let heading): return "invalid feature heading: \(heading)"
        case .invalidID(let id): return "invalid feature ID: \(id)"
        case .duplicateID(let id): return "duplicate feature ID: \(id)"
        case .duplicateMetadata(let label, let id): return "duplicate \(label) metadata for \(id)"
        case .missingRequired(let field, let id): return "missing \(field) metadata for \(id)"
        case .invalidMetadata(let field, let id): return "invalid \(field) metadata for \(id)"
        case .staleRevision(let expected, let current):
            return "FEATURES.md changed since confirmation; expected \(expected); current \(current)"
        case .staleFeature(let id): return "feature changed since confirmation: \(id)"
        case .featureNotFound(let id): return "feature not found: \(id)"
        case .changedID: return "feature IDs cannot be changed"
        }
    }
}
