import CryptoKit
import Darwin
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
        fileManager: FileManager = .default,
        beforeDemandDirectoryOpen: (() throws -> Void)? = nil
    ) throws -> DemandInputSnapshot {
        let workspaceURL = try validatedWorkspaceURL(workspacePath, fileManager: fileManager)
        let draftPath = workspaceURL.appendingPathComponent(demandDirectoryName).appendingPathComponent(draftFileName).path
        return try withWorkspaceDirectory(workspaceURL) { workspaceFD in
            guard let demandFD = try openDemandDirectory(
                workspaceFD: workspaceFD,
                path: draftPath,
                create: false,
                beforeOpen: beforeDemandDirectoryOpen
            ) else {
                return DemandInputSnapshot(draft: .empty, revision: .missing, path: draftPath)
            }
            defer { close(demandFD) }
            let document = inspectDraft(demandFD: demandFD, path: draftPath)
            return DemandInputSnapshot(draft: document.draft, revision: document.revision, path: draftPath)
        }
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
        let draftPath = workspaceURL.appendingPathComponent(demandDirectoryName).appendingPathComponent(draftFileName).path
        let revision = try withWorkspaceDirectory(workspaceURL) { workspaceFD in
            guard let demandFD = try openDemandDirectory(workspaceFD: workspaceFD, path: draftPath, create: true) else {
                throw NativeDemandInputStoreError.unsafeDirectory(draftPath)
            }
            defer { close(demandFD) }
            let current = inspectDraft(demandFD: demandFD, path: draftPath)
            try requireExpectedDraftRevision(current.revision, expected: expectedRevision, path: draftPath)

            let temporaryName = ".\(draftFileName).\(UUID().uuidString).tmp"
            defer { _ = unlinkat(demandFD, temporaryName, 0) }
            try writeNewFile(Data(render(draft).utf8), parentFD: demandFD, name: temporaryName)
            try beforeFinalRevisionCheck?()

            let latest = inspectDraft(demandFD: demandFD, path: draftPath)
            try requireExpectedDraftRevision(latest.revision, expected: expectedRevision, path: draftPath)
            try replaceDraft(
                demandFD: demandFD,
                temporaryName: temporaryName,
                draftPath: draftPath,
                expectedRevision: expectedRevision
            )

            let revision = inspectDraft(demandFD: demandFD, path: draftPath).revision
            guard case .regularUTF8 = revision else {
                throw NativeDemandInputStoreError.invalidDraft("staged draft write did not produce a regular UTF-8 file")
            }
            return revision
        }
        let audit = NativeAuditEventStore.appendFeedback(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: actor ?? "Nexus Native",
                action: "demand_input.saved",
                target: draftPath,
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
            path: draftPath,
            revision: revision,
            auditEventID: audit.response?.event.id,
            auditEventPath: audit.response?.path,
            auditError: audit.error
        )
    }

    static func makeAttachmentPlan(
        workspacePath: String,
        sourceURLs: [URL],
        fileManager: FileManager = .default,
        beforeSourceRead: (() throws -> Void)? = nil
    ) throws -> DemandAttachmentPlan {
        let workspaceURL = try validatedWorkspaceURL(workspacePath, fileManager: fileManager)
        let demandURL = workspaceURL.appendingPathComponent(demandDirectoryName, isDirectory: true)
        let draftPath = demandURL.appendingPathComponent(draftFileName).path
        let attachmentsURL = demandURL.appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
        return try withWorkspaceDirectory(workspaceURL) { workspaceFD in
            guard let demandFD = try openDemandDirectory(workspaceFD: workspaceFD, path: demandURL.path, create: true) else {
                throw NativeDemandInputStoreError.unsafeDirectory(demandURL.path)
            }
            defer { close(demandFD) }
            let snapshot = inspectDraft(demandFD: demandFD, path: draftPath)
            if case .invalid(let reason) = snapshot.revision {
                throw NativeDemandInputStoreError.invalidDraft(reason)
            }
            let attachmentsFD = try openAttachmentsDirectory(demandFD: demandFD, path: attachmentsURL.path)
            defer { close(attachmentsFD) }
            var names = Set<String>()
            let items = try sourceURLs.map { sourceURL in
                let normalizedURL = sourceURL.standardizedFileURL
                try beforeSourceRead?()
                let data = try regularFileData(at: normalizedURL)
                let name = try sanitizedAttachmentName(for: normalizedURL)
                guard names.insert(name).inserted else {
                    throw NativeDemandInputStoreError.duplicateAttachmentName(name)
                }
                let destinationURL = attachmentsURL.appendingPathComponent(name, isDirectory: false)
                guard entryKind(at: attachmentsFD, name: name) == .missing else {
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
    }

    static func copyAttachments(
        plan: DemandAttachmentPlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default,
        beforeDestinationWrite: ((DemandAttachmentPlanItem) throws -> Void)? = nil,
        beforeSourceRead: ((DemandAttachmentPlanItem) throws -> Void)? = nil,
        beforeAttachmentPublish: ((DemandAttachmentPlanItem) throws -> Void)? = nil,
        beforeAttachmentResponse: (() -> Void)? = nil
    ) throws -> DemandAttachmentCopyResponse {
        guard confirmed else {
            throw NativeDemandInputStoreError.unconfirmedAttachmentCopy
        }

        let workspaceURL = try validatedWorkspaceURL(plan.workspacePath, fileManager: fileManager)
        let demandURL = workspaceURL.appendingPathComponent(demandDirectoryName, isDirectory: true)
        let draftPath = demandURL.appendingPathComponent(draftFileName).path
        let expectedAttachmentsURL = workspaceURL
            .appendingPathComponent(demandDirectoryName, isDirectory: true)
            .appendingPathComponent(attachmentsDirectoryName, isDirectory: true)
        try validateAttachmentPlanShape(
            plan,
            workspaceURL: workspaceURL,
            attachmentsURL: expectedAttachmentsURL
        )
        let result = try withWorkspaceDirectory(workspaceURL) { workspaceFD -> (copiedPaths: [String], errors: [DemandAttachmentCopyError]) in
            guard let demandFD = try openDemandDirectory(workspaceFD: workspaceFD, path: demandURL.path, create: true) else {
                throw NativeDemandInputStoreError.unsafeDirectory(demandURL.path)
            }
            defer { close(demandFD) }
            let currentDraft = inspectDraft(demandFD: demandFD, path: draftPath)
            try requireExpectedDraftRevision(currentDraft.revision, expected: plan.expectedDraftRevision, path: draftPath)
            let attachmentsFD = try openAttachmentsDirectory(demandFD: demandFD, path: expectedAttachmentsURL.path)
            defer { close(attachmentsFD) }

            var copiedPaths: [String] = []
            var errors: [DemandAttachmentCopyError] = []
            for item in plan.items {
                do {
                    try beforeSourceRead?(item)
                    let data = try verifiedAttachmentData(item)
                    try beforeDestinationWrite?(item)
                    let name = item.destinationURL.lastPathComponent
                    guard entryKind(at: attachmentsFD, name: name) == .missing else {
                        throw NativeDemandInputStoreError.destinationExists(item.destinationURL.path)
                    }
                    try publishVerifiedAttachment(
                        data: data,
                        item: item,
                        attachmentsFD: attachmentsFD,
                        beforePublish: beforeAttachmentPublish
                    )
                    copiedPaths.append(item.destinationURL.path)
                } catch {
                    errors.append(DemandAttachmentCopyError(
                        sourcePath: item.sourceURL.path,
                        message: error.localizedDescription
                    ))
                }
            }
            return (copiedPaths, errors)
        }
        beforeAttachmentResponse?()

        let audit = NativeAuditEventStore.appendFeedback(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: actor ?? "Nexus Native",
                action: "demand_input.attachments_copied",
                target: expectedAttachmentsURL.path,
                summary: "Copied \(result.copiedPaths.count) confirmed demand attachment(s), \(result.errors.count) failed",
                metadata: [
                    "workspace": workspaceURL.path,
                    "copiedPaths": result.copiedPaths.joined(separator: " | "),
                    "errorCount": "\(result.errors.count)",
                    "errors": result.errors.map { $0.message }.joined(separator: " | ")
                ]
            )
        )
        return DemandAttachmentCopyResponse(
            copiedPaths: result.copiedPaths,
            errors: result.errors,
            auditEventID: audit.response?.event.id,
            auditEventPath: audit.response?.path,
            auditError: audit.error
        )
    }

    private static func replaceDraft(
        demandFD: Int32,
        temporaryName: String,
        draftPath: String,
        expectedRevision: DemandInputRevision,
    ) throws {
        switch expectedRevision {
        case .missing:
            guard entryKind(at: demandFD, name: draftFileName) == .missing else {
                let current = inspectDraft(demandFD: demandFD, path: draftPath).revision
                throw NativeDemandInputStoreError.staleDraft(
                    path: draftPath,
                    expected: expectedRevision.label,
                    current: current.label
                )
            }
            guard linkat(demandFD, temporaryName, demandFD, draftFileName, 0) == 0 else {
                let current = inspectDraft(demandFD: demandFD, path: draftPath).revision
                throw NativeDemandInputStoreError.staleDraft(path: draftPath, expected: expectedRevision.label, current: current.label)
            }
            _ = unlinkat(demandFD, temporaryName, 0)
        case .regularUTF8:
            guard entryKind(at: demandFD, name: draftFileName) == .regular else {
                let current = inspectDraft(demandFD: demandFD, path: draftPath).revision
                throw NativeDemandInputStoreError.staleDraft(
                    path: draftPath,
                    expected: expectedRevision.label,
                    current: current.label
                )
            }
            guard renameat(demandFD, temporaryName, demandFD, draftFileName) == 0 else {
                throw NativeDemandInputStoreError.invalidDraft("could not replace demand draft: \(draftPath)")
            }
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
        _ item: DemandAttachmentPlanItem
    ) throws -> Data {
        let data = try regularFileData(at: item.sourceURL)
        guard data.count == item.expectedSizeBytes,
              sha256Hex(data) == item.expectedSHA256 else {
            throw NativeDemandInputStoreError.sourceChanged(item.sourceURL.path)
        }
        return data
    }

    private static func validatedWorkspaceURL(_ workspacePath: String, fileManager: FileManager) throws -> URL {
        let workspaceURL = URL(fileURLWithPath: (workspacePath as NSString).expandingTildeInPath).standardizedFileURL
        return workspaceURL
    }

    private static func withWorkspaceDirectory<T>(_ workspaceURL: URL, body: (Int32) throws -> T) throws -> T {
        let workspaceFD = open(workspaceURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard workspaceFD >= 0 else {
            throw NativeDemandInputStoreError.invalidWorkspace(workspaceURL.path)
        }
        defer { close(workspaceFD) }
        return try body(workspaceFD)
    }

    private static func openDemandDirectory(
        workspaceFD: Int32,
        path: String,
        create: Bool,
        beforeOpen: (() throws -> Void)? = nil
    ) throws -> Int32? {
        try beforeOpen?()
        var demandFD = openat(workspaceFD, demandDirectoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if demandFD < 0 && errno == ENOENT && create {
            guard mkdirat(workspaceFD, demandDirectoryName, mode_t(0o700)) == 0 || errno == EEXIST else {
                throw NativeDemandInputStoreError.unsafeDirectory(path)
            }
            demandFD = openat(workspaceFD, demandDirectoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        if demandFD < 0 {
            if errno == ENOENT { return nil }
            throw NativeDemandInputStoreError.unsafeDirectory(path)
        }
        return demandFD
    }

    private static func openAttachmentsDirectory(demandFD: Int32, path: String) throws -> Int32 {
        var attachmentsFD = openat(demandFD, attachmentsDirectoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        if attachmentsFD < 0 && errno == ENOENT {
            guard mkdirat(demandFD, attachmentsDirectoryName, mode_t(0o700)) == 0 || errno == EEXIST else {
                throw NativeDemandInputStoreError.unsafeDirectory(path)
            }
            attachmentsFD = openat(demandFD, attachmentsDirectoryName, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        }
        guard attachmentsFD >= 0 else {
            throw NativeDemandInputStoreError.unsafeDirectory(path)
        }
        return attachmentsFD
    }

    private static func inspectDraft(demandFD: Int32, path: String) -> DemandDocumentSnapshot {
        switch entryKind(at: demandFD, name: draftFileName) {
        case .missing:
            return DemandDocumentSnapshot(draft: .empty, revision: .missing)
        case .regular:
            do {
                let data = try readRegularFile(parentFD: demandFD, name: draftFileName, path: path)
                guard let content = String(data: data, encoding: .utf8) else {
                    return DemandDocumentSnapshot(
                        draft: .empty,
                        revision: .invalid(reason: "demand draft is not valid UTF-8: \(path)")
                    )
                }
                return DemandDocumentSnapshot(
                    draft: parse(content),
                    revision: .regularUTF8(sha256: sha256Hex(data), byteCount: data.count)
                )
            } catch {
                return DemandDocumentSnapshot(
                    draft: .empty,
                    revision: .invalid(reason: "demand draft is unreadable: \(path): \(error.localizedDescription)")
                )
            }
        default:
            return DemandDocumentSnapshot(
                draft: .empty,
                revision: .invalid(reason: "demand draft is not a regular file: \(path)")
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

    private static func regularFileData(at url: URL) throws -> Data {
        let fileFD = open(url.path, O_RDONLY | O_NOFOLLOW)
        guard fileFD >= 0 else {
            throw NativeDemandInputStoreError.unsafeSource(url.path)
        }
        defer { close(fileFD) }
        var info = stat()
        guard fstat(fileFD, &info) == 0, fileType(info) == .regular else {
            throw NativeDemandInputStoreError.unsafeSource(url.path)
        }
        return try FileHandle(fileDescriptor: fileFD, closeOnDealloc: false).readToEnd() ?? Data()
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

    private static func writeNewFile(_ data: Data, parentFD: Int32, name: String) throws {
        let fileFD = openat(parentFD, name, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fileFD >= 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        defer { close(fileFD) }
        let handle = FileHandle(fileDescriptor: fileFD, closeOnDealloc: false)
        try handle.write(contentsOf: data)
        guard fsync(fileFD) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func publishVerifiedAttachment(
        data: Data,
        item: DemandAttachmentPlanItem,
        attachmentsFD: Int32,
        beforePublish: ((DemandAttachmentPlanItem) throws -> Void)?
    ) throws {
        let temporaryName = ".attachment.\(UUID().uuidString).tmp"
        defer { _ = unlinkat(attachmentsFD, temporaryName, 0) }
        try writeNewFile(data, parentFD: attachmentsFD, name: temporaryName)

        let writtenData = try readRegularFile(
            parentFD: attachmentsFD,
            name: temporaryName,
            path: item.destinationURL.path
        )
        guard writtenData.count == item.expectedSizeBytes,
              sha256Hex(writtenData) == item.expectedSHA256 else {
            throw NativeDemandInputStoreError.destinationVerificationFailed(item.destinationURL.path)
        }
        try beforePublish?(item)

        let destinationName = item.destinationURL.lastPathComponent
        guard entryKind(at: attachmentsFD, name: destinationName) == .missing else {
            throw NativeDemandInputStoreError.destinationExists(item.destinationURL.path)
        }
        guard linkat(attachmentsFD, temporaryName, attachmentsFD, destinationName, 0) == 0 else {
            if errno == EEXIST {
                throw NativeDemandInputStoreError.destinationExists(item.destinationURL.path)
            }
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }

    private static func readRegularFile(parentFD: Int32, name: String, path: String) throws -> Data {
        let fileFD = openat(parentFD, name, O_RDONLY | O_NOFOLLOW)
        guard fileFD >= 0 else {
            throw NativeDemandInputStoreError.unsafeSource(path)
        }
        defer { close(fileFD) }
        var info = stat()
        guard fstat(fileFD, &info) == 0, fileType(info) == .regular else {
            throw NativeDemandInputStoreError.unsafeSource(path)
        }
        return try FileHandle(fileDescriptor: fileFD, closeOnDealloc: false).readToEnd() ?? Data()
    }

    private static func entryKind(at parentFD: Int32, name: String) -> EntryKind {
        var info = stat()
        guard fstatat(parentFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            return errno == ENOENT ? .missing : .other
        }
        return fileType(info)
    }

    private static func fileType(_ info: stat) -> EntryKind {
        switch info.st_mode & S_IFMT {
        case S_IFREG:
            .regular
        case S_IFDIR:
            .directory
        case S_IFLNK:
            .symlink
        default:
            .other
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
