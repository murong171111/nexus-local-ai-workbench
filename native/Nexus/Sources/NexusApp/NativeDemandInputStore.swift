import CryptoKit
import Foundation
import NexusBridge

enum NativeDemandInputStore {
    static let demandDirectoryName = "需求"
    static let draftFileName = "intake-draft.md"
    static let attachmentsDirectoryName = "attachments"

    static func load(
        workspacePath: String,
        fileManager: FileManager = .default
    ) throws -> DemandInputSnapshot {
        let workspaceURL = try validatedWorkspaceURL(workspacePath, fileManager: fileManager)
        let draftURL = workspaceURL
            .appendingPathComponent(demandDirectoryName, isDirectory: true)
            .appendingPathComponent(draftFileName, isDirectory: false)
        let document = inspectDraft(at: draftURL, fileManager: fileManager)
        return DemandInputSnapshot(draft: document.draft, revision: document.revision, path: draftURL.path)
    }

    static func save(
        draft: DemandInputDraft,
        workspacePath: String,
        expectedRevision: DemandInputRevision,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default
    ) throws -> DemandInputSaveResponse {
        guard case .invalid(let reason) = expectedRevision else {
            return try saveValidDraft(
                draft: draft,
                workspacePath: workspacePath,
                expectedRevision: expectedRevision,
                auditRoot: auditRoot,
                actor: actor,
                fileManager: fileManager
            )
        }
        throw NativeDemandInputStoreError.invalidExpectedRevision(reason)
    }

    static func makeAttachmentPlan(
        workspacePath: String,
        sourceURLs: [URL],
        fileManager: FileManager = .default
    ) throws -> DemandAttachmentPlan {
        let workspaceURL = try validatedWorkspaceURL(workspacePath, fileManager: fileManager)
        let snapshot = try load(workspacePath: workspaceURL.path, fileManager: fileManager)
        guard case .invalid(let reason) = snapshot.revision else {
            return try makeAttachmentPlan(
                workspaceURL: workspaceURL,
                expectedDraftRevision: snapshot.revision,
                sourceURLs: sourceURLs,
                fileManager: fileManager
            )
        }
        throw NativeDemandInputStoreError.invalidDraft(reason)
    }

    static func copyAttachments(
        plan: DemandAttachmentPlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default
    ) throws -> DemandAttachmentCopyResponse {
        guard confirmed else {
            throw NativeDemandInputStoreError.unconfirmedAttachmentCopy
        }

        let workspaceURL = try validatedWorkspaceURL(plan.workspacePath, fileManager: fileManager)
        let currentDraft = try load(workspacePath: workspaceURL.path, fileManager: fileManager)
        guard currentDraft.revision == plan.expectedDraftRevision else {
            throw NativeDemandInputStoreError.staleDraft(
                path: currentDraft.path,
                expected: plan.expectedDraftRevision.label,
                current: currentDraft.revision.label
            )
        }

        for item in plan.items {
            try validateAttachmentItem(item, workspaceURL: workspaceURL, fileManager: fileManager)
        }
        let attachmentsURL = try ensureAttachmentsDirectory(in: workspaceURL, fileManager: fileManager)

        var copiedPaths: [String] = []
        var errors: [DemandAttachmentCopyError] = []
        for item in plan.items {
            try validateAttachmentItem(item, workspaceURL: workspaceURL, fileManager: fileManager)
            guard item.destinationURL.deletingLastPathComponent().path == attachmentsURL.path else {
                throw NativeDemandInputStoreError.malformedAttachmentPlan(item.destinationURL.path)
            }
            do {
                try fileManager.copyItem(at: item.sourceURL, to: item.destinationURL)
                copiedPaths.append(item.destinationURL.path)
            } catch {
                errors.append(DemandAttachmentCopyError(
                    sourcePath: item.sourceURL.path,
                    message: error.localizedDescription
                ))
            }
        }

        let audit = NativeAuditEventStore.appendFeedback(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: actor ?? "Nexus Native",
                action: "demand_input.attachments_copied",
                target: attachmentsURL.path,
                summary: "Copied \(copiedPaths.count) confirmed demand attachment(s)",
                metadata: [
                    "workspace": workspaceURL.path,
                    "copiedPaths": copiedPaths.joined(separator: " | "),
                    "errorCount": "\(errors.count)"
                ]
            )
        )
        return DemandAttachmentCopyResponse(
            copiedPaths: copiedPaths,
            errors: errors,
            auditEventID: audit.response?.event.id,
            auditEventPath: audit.response?.path,
            auditError: audit.error
        )
    }

    private static func saveValidDraft(
        draft: DemandInputDraft,
        workspacePath: String,
        expectedRevision: DemandInputRevision,
        auditRoot: String?,
        actor: String?,
        fileManager: FileManager
    ) throws -> DemandInputSaveResponse {
        let workspaceURL = try validatedWorkspaceURL(workspacePath, fileManager: fileManager)
        let demandURL = try ensureDemandDirectory(in: workspaceURL, fileManager: fileManager)
        let draftURL = demandURL.appendingPathComponent(draftFileName, isDirectory: false)
        let current = inspectDraft(at: draftURL, fileManager: fileManager)
        if case .invalid(let reason) = current.revision {
            throw NativeDemandInputStoreError.invalidDraft(reason)
        }
        guard current.revision == expectedRevision else {
            throw NativeDemandInputStoreError.staleDraft(
                path: draftURL.path,
                expected: expectedRevision.label,
                current: current.revision.label
            )
        }

        let content = render(draft)
        try content.write(to: draftURL, atomically: true, encoding: .utf8)
        let revision = inspectDraft(at: draftURL, fileManager: fileManager).revision
        guard case .regularUTF8 = revision else {
            throw NativeDemandInputStoreError.invalidDraft("atomic draft write did not produce a regular UTF-8 file")
        }
        let audit = NativeAuditEventStore.appendFeedback(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: actor ?? "Nexus Native",
                action: "demand_input.saved",
                target: draftURL.path,
                summary: "Saved free-form demand draft",
                metadata: [
                    "workspace": workspaceURL.path,
                    "links": "\(draft.links.count)",
                    "attachments": "\(draft.attachments.count)",
                    "revision": revision.label
                ]
            )
        )
        return DemandInputSaveResponse(
            path: draftURL.path,
            revision: revision,
            auditEventID: audit.response?.event.id,
            auditEventPath: audit.response?.path,
            auditError: audit.error
        )
    }

    private static func makeAttachmentPlan(
        workspaceURL: URL,
        expectedDraftRevision: DemandInputRevision,
        sourceURLs: [URL],
        fileManager: FileManager
    ) throws -> DemandAttachmentPlan {
        let attachmentsURL = try ensureAttachmentsDirectory(in: workspaceURL, fileManager: fileManager)
        var names = Set<String>()
        let items = try sourceURLs.map { sourceURL in
            let sourceURL = sourceURL.standardizedFileURL
            let source = try regularFileEvidence(at: sourceURL, fileManager: fileManager)
            let name = try sanitizedAttachmentName(for: sourceURL)
            guard names.insert(name).inserted else {
                throw NativeDemandInputStoreError.duplicateAttachmentName(name)
            }
            let destinationURL = attachmentsURL.appendingPathComponent(name, isDirectory: false)
            guard entryKind(at: destinationURL, fileManager: fileManager) == .missing else {
                throw NativeDemandInputStoreError.destinationExists(destinationURL.path)
            }
            return DemandAttachmentPlanItem(
                sourceURL: sourceURL,
                destinationURL: destinationURL,
                expectedSizeBytes: source.data.count,
                expectedSHA256: sha256Hex(source.data)
            )
        }
        return DemandAttachmentPlan(
            workspacePath: workspaceURL.path,
            expectedDraftRevision: expectedDraftRevision,
            items: items
        )
    }

    private static func validateAttachmentItem(
        _ item: DemandAttachmentPlanItem,
        workspaceURL: URL,
        fileManager: FileManager
    ) throws {
        let attachmentsURL = workspaceURL
            .appendingPathComponent(demandDirectoryName, isDirectory: true)
            .appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
        guard item.destinationURL.deletingLastPathComponent().path == attachmentsURL.path,
              item.destinationURL.lastPathComponent == sanitizedAttachmentNameUnchecked(item.sourceURL.lastPathComponent) else {
            throw NativeDemandInputStoreError.malformedAttachmentPlan(item.destinationURL.path)
        }
        let source = try regularFileEvidence(at: item.sourceURL, fileManager: fileManager)
        guard source.data.count == item.expectedSizeBytes,
              sha256Hex(source.data) == item.expectedSHA256 else {
            throw NativeDemandInputStoreError.sourceChanged(item.sourceURL.path)
        }
        guard entryKind(at: item.destinationURL, fileManager: fileManager) == .missing else {
            throw NativeDemandInputStoreError.destinationExists(item.destinationURL.path)
        }
    }

    private static func ensureDemandDirectory(in workspaceURL: URL, fileManager: FileManager) throws -> URL {
        let demandURL = workspaceURL.appendingPathComponent(demandDirectoryName, isDirectory: true)
        switch entryKind(at: demandURL, fileManager: fileManager) {
        case .missing:
            try fileManager.createDirectory(at: demandURL, withIntermediateDirectories: false)
        case .directory:
            break
        default:
            throw NativeDemandInputStoreError.unsafeDirectory(demandURL.path)
        }
        guard entryKind(at: demandURL, fileManager: fileManager) == .directory else {
            throw NativeDemandInputStoreError.unsafeDirectory(demandURL.path)
        }
        return demandURL
    }

    private static func ensureAttachmentsDirectory(in workspaceURL: URL, fileManager: FileManager) throws -> URL {
        let demandURL = try ensureDemandDirectory(in: workspaceURL, fileManager: fileManager)
        let attachmentsURL = demandURL.appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
        switch entryKind(at: attachmentsURL, fileManager: fileManager) {
        case .missing:
            try fileManager.createDirectory(at: attachmentsURL, withIntermediateDirectories: false)
        case .directory:
            break
        default:
            throw NativeDemandInputStoreError.unsafeDirectory(attachmentsURL.path)
        }
        guard entryKind(at: attachmentsURL, fileManager: fileManager) == .directory else {
            throw NativeDemandInputStoreError.unsafeDirectory(attachmentsURL.path)
        }
        return attachmentsURL
    }

    private static func validatedWorkspaceURL(_ workspacePath: String, fileManager: FileManager) throws -> URL {
        let workspaceURL = URL(fileURLWithPath: (workspacePath as NSString).expandingTildeInPath).standardizedFileURL
        guard entryKind(at: workspaceURL, fileManager: fileManager) == .directory else {
            throw NativeDemandInputStoreError.invalidWorkspace(workspaceURL.path)
        }
        return workspaceURL
    }

    private static func inspectDraft(at url: URL, fileManager: FileManager) -> DemandDocumentSnapshot {
        switch entryKind(at: url, fileManager: fileManager) {
        case .missing:
            return DemandDocumentSnapshot(draft: .empty, revision: .missing)
        case .regular:
            do {
                let data = try Data(contentsOf: url)
                guard let content = String(data: data, encoding: .utf8) else {
                    return DemandDocumentSnapshot(
                        draft: .empty,
                        revision: .invalid(reason: "demand draft is not valid UTF-8: \(url.path)")
                    )
                }
                return DemandDocumentSnapshot(
                    draft: parse(content),
                    revision: .regularUTF8(sha256: sha256Hex(data), byteCount: data.count)
                )
            } catch {
                return DemandDocumentSnapshot(
                    draft: .empty,
                    revision: .invalid(reason: "demand draft is unreadable: \(url.path): \(error.localizedDescription)")
                )
            }
        default:
            return DemandDocumentSnapshot(
                draft: .empty,
                revision: .invalid(reason: "demand draft is not a regular file: \(url.path)")
            )
        }
    }

    private static func render(_ draft: DemandInputDraft) -> String {
        let requirement = draft.requirement.trimmingCharacters(in: .newlines)
        let links = draft.links
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "- \($0)" }
            .joined(separator: "\n")
        let attachments = draft.attachments
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { "- `\($0)`" }
            .joined(separator: "\n")
        return [
            "# Demand Intake Draft",
            "",
            "## Requirement",
            "",
            requirement,
            "",
            "## Links",
            "",
            links,
            "",
            "## Attachments",
            "",
            attachments,
            ""
        ].joined(separator: "\n")
    }

    private static func parse(_ content: String) -> DemandInputDraft {
        let requirement = section("## Requirement", in: content)
        let links = section("## Links", in: content)
            .split(separator: "\n")
            .compactMap { line in
                let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
                return value.hasPrefix("- ") ? String(value.dropFirst(2)) : nil
            }
        let attachments: [String] = section("## Attachments", in: content)
            .split(separator: "\n")
            .compactMap { line in
                let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
                guard value.hasPrefix("- `"), value.hasSuffix("`") else { return nil }
                return String(value.dropFirst(3).dropLast())
            }
        return DemandInputDraft(
            requirement: requirement.trimmingCharacters(in: .newlines),
            links: links,
            attachments: attachments
        )
    }

    private static func section(_ heading: String, in content: String) -> String {
        guard let start = content.range(of: "\(heading)\n") else { return "" }
        let afterHeading = content[start.upperBound...]
        let body = afterHeading.hasPrefix("\n") ? afterHeading.dropFirst() : afterHeading[...]
        if let next = body.range(of: "\n## ") {
            return String(body[..<next.lowerBound])
        }
        return String(body)
    }

    private static func regularFileEvidence(at url: URL, fileManager: FileManager) throws -> (data: Data, url: URL) {
        guard entryKind(at: url, fileManager: fileManager) == .regular else {
            throw NativeDemandInputStoreError.unsafeSource(url.path)
        }
        return (try Data(contentsOf: url), url)
    }

    private static func sanitizedAttachmentName(for url: URL) throws -> String {
        let name = sanitizedAttachmentNameUnchecked(url.lastPathComponent)
        guard !name.isEmpty, name != ".", name != ".." else {
            throw NativeDemandInputStoreError.unsafeSource(url.path)
        }
        return name
    }

    private static func sanitizedAttachmentNameUnchecked(_ name: String) -> String {
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_.")
        let sanitized = String(name.unicodeScalars.map { allowed.contains($0) ? Character(String($0)) : "-" })
        return sanitized.trimmingCharacters(in: CharacterSet(charactersIn: ".-"))
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func entryKind(at url: URL, fileManager: FileManager) -> EntryKind {
        if (try? fileManager.destinationOfSymbolicLink(atPath: url.path)) != nil {
            return .symlink
        }
        do {
            let attributes = try fileManager.attributesOfItem(atPath: url.path)
            switch attributes[.type] as? FileAttributeType {
            case .typeRegular:
                return .regular
            case .typeDirectory:
                return .directory
            default:
                return .other
            }
        } catch let error as NSError where error.domain == NSCocoaErrorDomain
            && (error.code == NSFileNoSuchFileError || error.code == NSFileReadNoSuchFileError) {
            return .missing
        } catch {
            return .other
        }
    }

    private struct DemandDocumentSnapshot {
        let draft: DemandInputDraft
        let revision: DemandInputRevision
    }

    private enum EntryKind {
        case missing
        case regular
        case directory
        case symlink
        case other
    }
}

private enum NativeDemandInputStoreError: LocalizedError {
    case invalidWorkspace(String)
    case invalidExpectedRevision(String)
    case invalidDraft(String)
    case staleDraft(path: String, expected: String, current: String)
    case unconfirmedAttachmentCopy
    case unsafeDirectory(String)
    case unsafeSource(String)
    case sourceChanged(String)
    case destinationExists(String)
    case duplicateAttachmentName(String)
    case malformedAttachmentPlan(String)

    var errorDescription: String? {
        switch self {
        case .invalidWorkspace(let path):
            "workspace is not a real directory: \(path)"
        case .invalidExpectedRevision(let reason):
            "demand draft has an invalid expected revision: \(reason)"
        case .invalidDraft(let reason):
            reason
        case .staleDraft(let path, let expected, let current):
            "demand draft changed since confirmation: \(path): expected \(expected), found \(current)"
        case .unconfirmedAttachmentCopy:
            "demand attachment copy requires explicit confirmation"
        case .unsafeDirectory(let path):
            "demand directory is not a real directory: \(path)"
        case .unsafeSource(let path):
            "demand attachment source is not a regular file: \(path)"
        case .sourceChanged(let path):
            "demand attachment source changed since confirmation: \(path)"
        case .destinationExists(let path):
            "demand attachment destination appeared after confirmation: \(path)"
        case .duplicateAttachmentName(let name):
            "duplicate sanitized demand attachment name: \(name)"
        case .malformedAttachmentPlan(let path):
            "malformed demand attachment plan: \(path)"
        }
    }
}
