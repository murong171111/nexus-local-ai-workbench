import CryptoKit
import Foundation
import NexusBridge

enum NativeDemandInputStore {
    static let demandDirectoryName = "需求"
    static let draftFileName = "intake-draft.md"
    static let attachmentsDirectoryName = "attachments"

    // ponytail: one Nexus-local lock is sufficient for the current in-process editor; split by workspace only if concurrent editing becomes a measured need.
    private static let writeLock = NSLock()

    static func load(
        workspacePath: String,
        fileManager: FileManager = .default
    ) throws -> DemandInputSnapshot {
        let workspaceURL = try validatedWorkspaceURL(workspacePath, fileManager: fileManager)
        let demandURL = try existingDemandDirectory(in: workspaceURL, fileManager: fileManager)
        let draftURL = demandURL.appendingPathComponent(draftFileName, isDirectory: false)
        let document = inspectDraft(at: draftURL, fileManager: fileManager)
        return DemandInputSnapshot(draft: document.draft, revision: document.revision, path: draftURL.path)
    }

    static func save(
        draft: DemandInputDraft,
        workspacePath: String,
        expectedRevision: DemandInputRevision,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default,
        beforeFinalRevisionCheck: (() throws -> Void)? = nil
    ) throws -> DemandInputSaveResponse {
        if case .invalid(let reason) = expectedRevision {
            throw NativeDemandInputStoreError.invalidExpectedRevision(reason)
        }

        writeLock.lock()
        defer { writeLock.unlock() }
        let workspaceURL = try validatedWorkspaceURL(workspacePath, fileManager: fileManager)
        let demandURL = try ensureDemandDirectory(in: workspaceURL, fileManager: fileManager)
        let draftURL = demandURL.appendingPathComponent(draftFileName, isDirectory: false)
        let current = inspectDraft(at: draftURL, fileManager: fileManager)
        try requireExpectedDraftRevision(current.revision, expected: expectedRevision, path: draftURL.path)

        let temporaryURL = demandURL.appendingPathComponent(".\(draftFileName).\(UUID().uuidString).tmp")
        defer { try? fileManager.removeItem(at: temporaryURL) }
        try Data(render(draft).utf8).write(to: temporaryURL, options: [.withoutOverwriting])
        try beforeFinalRevisionCheck?()

        let latest = inspectDraft(at: draftURL, fileManager: fileManager)
        try requireExpectedDraftRevision(latest.revision, expected: expectedRevision, path: draftURL.path)
        try replaceDraft(
            temporaryURL: temporaryURL,
            draftURL: draftURL,
            expectedRevision: expectedRevision,
            fileManager: fileManager
        )

        let revision = inspectDraft(at: draftURL, fileManager: fileManager).revision
        guard case .regularUTF8 = revision else {
            throw NativeDemandInputStoreError.invalidDraft("staged draft write did not produce a regular UTF-8 file")
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

    static func makeAttachmentPlan(
        workspacePath: String,
        sourceURLs: [URL],
        fileManager: FileManager = .default
    ) throws -> DemandAttachmentPlan {
        let workspaceURL = try validatedWorkspaceURL(workspacePath, fileManager: fileManager)
        let snapshot = try load(workspacePath: workspaceURL.path, fileManager: fileManager)
        if case .invalid(let reason) = snapshot.revision {
            throw NativeDemandInputStoreError.invalidDraft(reason)
        }
        let attachmentsURL = try ensureAttachmentsDirectory(in: workspaceURL, fileManager: fileManager)
        var names = Set<String>()
        let items = try sourceURLs.map { sourceURL in
            let normalizedURL = sourceURL.standardizedFileURL
            let data = try regularFileData(at: normalizedURL, fileManager: fileManager)
            let name = try sanitizedAttachmentName(for: normalizedURL)
            guard names.insert(name).inserted else {
                throw NativeDemandInputStoreError.duplicateAttachmentName(name)
            }
            let destinationURL = attachmentsURL.appendingPathComponent(name, isDirectory: false)
            guard entryKind(at: destinationURL, fileManager: fileManager) == .missing else {
                throw NativeDemandInputStoreError.destinationExists(destinationURL.path)
            }
            return DemandAttachmentPlanItem(
                sourceURL: normalizedURL,
                destinationURL: destinationURL,
                expectedSizeBytes: data.count,
                expectedSHA256: sha256Hex(data)
            )
        }
        return DemandAttachmentPlan(
            workspacePath: workspaceURL.path,
            expectedDraftRevision: snapshot.revision,
            items: items
        )
    }

    static func copyAttachments(
        plan: DemandAttachmentPlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default,
        beforeDestinationWrite: ((DemandAttachmentPlanItem) throws -> Void)? = nil
    ) throws -> DemandAttachmentCopyResponse {
        guard confirmed else {
            throw NativeDemandInputStoreError.unconfirmedAttachmentCopy
        }

        let workspaceURL = try validatedWorkspaceURL(plan.workspacePath, fileManager: fileManager)
        let currentDraft = try load(workspacePath: workspaceURL.path, fileManager: fileManager)
        try requireExpectedDraftRevision(
            currentDraft.revision,
            expected: plan.expectedDraftRevision,
            path: currentDraft.path
        )
        let expectedAttachmentsURL = workspaceURL
            .appendingPathComponent(demandDirectoryName, isDirectory: true)
            .appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
        try validateAttachmentPlanShape(
            plan,
            workspaceURL: workspaceURL,
            attachmentsURL: expectedAttachmentsURL
        )
        let attachmentsURL = try ensureAttachmentsDirectory(in: workspaceURL, fileManager: fileManager)

        var copiedPaths: [String] = []
        var errors: [DemandAttachmentCopyError] = []
        for item in plan.items {
            do {
                let data = try verifiedAttachmentData(item, fileManager: fileManager)
                try beforeDestinationWrite?(item)
                guard entryKind(at: item.destinationURL, fileManager: fileManager) == .missing else {
                    throw NativeDemandInputStoreError.destinationExists(item.destinationURL.path)
                }
                try data.write(to: item.destinationURL, options: [.withoutOverwriting])
                let writtenData = try regularFileData(at: item.destinationURL, fileManager: fileManager)
                guard writtenData.count == item.expectedSizeBytes,
                      sha256Hex(writtenData) == item.expectedSHA256 else {
                    throw NativeDemandInputStoreError.destinationVerificationFailed(item.destinationURL.path)
                }
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
                summary: "Copied \(copiedPaths.count) confirmed demand attachment(s), \(errors.count) failed",
                metadata: [
                    "workspace": workspaceURL.path,
                    "copiedPaths": copiedPaths.joined(separator: " | "),
                    "errorCount": "\(errors.count)",
                    "errors": errors.map(\.message).joined(separator: " | ")
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

    private static func replaceDraft(
        temporaryURL: URL,
        draftURL: URL,
        expectedRevision: DemandInputRevision,
        fileManager: FileManager
    ) throws {
        switch expectedRevision {
        case .missing:
            guard entryKind(at: draftURL, fileManager: fileManager) == .missing else {
                let current = inspectDraft(at: draftURL, fileManager: fileManager).revision
                throw NativeDemandInputStoreError.staleDraft(
                    path: draftURL.path,
                    expected: expectedRevision.label,
                    current: current.label
                )
            }
            try fileManager.moveItem(at: temporaryURL, to: draftURL)
        case .regularUTF8:
            guard entryKind(at: draftURL, fileManager: fileManager) == .regular else {
                let current = inspectDraft(at: draftURL, fileManager: fileManager).revision
                throw NativeDemandInputStoreError.staleDraft(
                    path: draftURL.path,
                    expected: expectedRevision.label,
                    current: current.label
                )
            }
            _ = try fileManager.replaceItemAt(
                draftURL,
                withItemAt: temporaryURL,
                backupItemName: nil,
                options: [.usingNewMetadataOnly]
            )
        case .invalid(let reason):
            throw NativeDemandInputStoreError.invalidExpectedRevision(reason)
        }
    }

    private static func requireExpectedDraftRevision(
        _ current: DemandInputRevision,
        expected: DemandInputRevision,
        path: String
    ) throws {
        if case .invalid(let reason) = current {
            throw NativeDemandInputStoreError.invalidDraft(reason)
        }
        guard current == expected else {
            throw NativeDemandInputStoreError.staleDraft(
                path: path,
                expected: expected.label,
                current: current.label
            )
        }
    }

    private static func validateAttachmentPlanShape(
        _ plan: DemandAttachmentPlan,
        workspaceURL: URL,
        attachmentsURL: URL
    ) throws {
        guard plan.workspacePath == workspaceURL.path else {
            throw NativeDemandInputStoreError.malformedAttachmentPlan(plan.workspacePath)
        }
        var destinations = Set<String>()
        for item in plan.items {
            let normalizedSource = item.sourceURL.standardizedFileURL
            let expectedName = sanitizedAttachmentNameUnchecked(normalizedSource.lastPathComponent)
            guard item.sourceURL == normalizedSource,
                  item.expectedSizeBytes >= 0,
                  item.expectedSHA256.count == 64,
                  item.expectedSHA256.allSatisfy({ $0.isHexDigit }),
                  !expectedName.isEmpty,
                  item.destinationURL.deletingLastPathComponent().path == attachmentsURL.path,
                  item.destinationURL.lastPathComponent == expectedName,
                  destinations.insert(item.destinationURL.path).inserted else {
                throw NativeDemandInputStoreError.malformedAttachmentPlan(item.destinationURL.path)
            }
        }
    }

    private static func verifiedAttachmentData(
        _ item: DemandAttachmentPlanItem,
        fileManager: FileManager
    ) throws -> Data {
        let data = try regularFileData(at: item.sourceURL, fileManager: fileManager)
        guard data.count == item.expectedSizeBytes,
              sha256Hex(data) == item.expectedSHA256 else {
            throw NativeDemandInputStoreError.sourceChanged(item.sourceURL.path)
        }
        return data
    }

    private static func existingDemandDirectory(in workspaceURL: URL, fileManager: FileManager) throws -> URL {
        let demandURL = workspaceURL.appendingPathComponent(demandDirectoryName, isDirectory: true)
        switch entryKind(at: demandURL, fileManager: fileManager) {
        case .missing, .directory:
            return demandURL
        default:
            throw NativeDemandInputStoreError.unsafeDirectory(demandURL.path)
        }
    }

    private static func ensureDemandDirectory(in workspaceURL: URL, fileManager: FileManager) throws -> URL {
        let demandURL = try existingDemandDirectory(in: workspaceURL, fileManager: fileManager)
        if entryKind(at: demandURL, fileManager: fileManager) == .missing {
            try fileManager.createDirectory(at: demandURL, withIntermediateDirectories: false)
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
        let lines = content.components(separatedBy: "\n")
        guard let requirementIndex = lines.firstIndex(of: "## Requirement") else {
            return .empty
        }
        guard let attachmentsIndex = lines.indices.reversed().first(where: { index in
            lines[index] == "## Attachments" && attachmentTailIsValid(Array(lines[(index + 1)...]))
        }), let linksIndex = lines.indices.reversed().first(where: { index in
            index > requirementIndex && index < attachmentsIndex
                && lines[index] == "## Links"
                && linkBlockIsValid(Array(lines[(index + 1)..<attachmentsIndex]))
        }) else {
            return DemandInputDraft(
                requirement: lines[(requirementIndex + 1)...].joined(separator: "\n").trimmingCharacters(in: .newlines),
                links: [],
                attachments: []
            )
        }
        let requirement = lines[(requirementIndex + 1)..<linksIndex]
            .joined(separator: "\n")
            .trimmingCharacters(in: .newlines)
        let links = lines[(linksIndex + 1)..<attachmentsIndex].compactMap(linkValue)
        let attachments = lines[(attachmentsIndex + 1)...].compactMap(attachmentValue)
        return DemandInputDraft(requirement: requirement, links: links, attachments: attachments)
    }

    private static func linkBlockIsValid(_ lines: [String]) -> Bool {
        lines.allSatisfy { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty || value.hasPrefix("- ")
        }
    }

    private static func attachmentTailIsValid(_ lines: [String]) -> Bool {
        lines.allSatisfy { line in
            let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return value.isEmpty || attachmentValue(line) != nil
        }
    }

    private static func linkValue(_ line: String) -> String? {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.hasPrefix("- ") ? String(value.dropFirst(2)) : nil
    }

    private static func attachmentValue(_ line: String) -> String? {
        let value = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value.hasPrefix("- `"), value.hasSuffix("`") else { return nil }
        return String(value.dropFirst(3).dropLast())
    }

    private static func regularFileData(at url: URL, fileManager: FileManager) throws -> Data {
        guard entryKind(at: url, fileManager: fileManager) == .regular else {
            throw NativeDemandInputStoreError.unsafeSource(url.path)
        }
        let data = try Data(contentsOf: url)
        guard entryKind(at: url, fileManager: fileManager) == .regular else {
            throw NativeDemandInputStoreError.unsafeSource(url.path)
        }
        return data
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
    case destinationVerificationFailed(String)
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
        case .destinationVerificationFailed(let path):
            "demand attachment destination failed verification: \(path)"
        case .duplicateAttachmentName(let name):
            "duplicate sanitized demand attachment name: \(name)"
        case .malformedAttachmentPlan(let path):
            "malformed demand attachment plan: \(path)"
        }
    }
}
