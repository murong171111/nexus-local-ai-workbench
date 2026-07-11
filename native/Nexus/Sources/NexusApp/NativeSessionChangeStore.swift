import CryptoKit
import Darwin
import Foundation
import NexusBridge

struct SessionChangeBaseline: Codable, Hashable, Sendable {
    let sessionID: String
    let workspacePath: String
    let startedAt: String
    let repositoryHeads: [String: String]
    let featureRevision: String?
    let taskRevision: String?
}

struct SessionChangeBaselineResult: Hashable, Sendable {
    let baseline: SessionChangeBaseline
    let canClaimPriorDiff: Bool
    let notice: String
}

struct SessionChangeDraftInput: Hashable, Sendable {
    let workspacePath: String
    let baseline: SessionChangeBaseline
    let currentRepositoryHeads: [String: String]
    let repositoryDiffs: [String: String]
    let featureRevision: String?
    let taskRevision: String?
    let latestTest: String?
    let sqlAndDeliveryRevisions: [String: String]
    let codexSummary: String?
    let featureAndTaskFacts: [String]
    let canClaimPriorDiff: Bool
    let baselineNotice: String

    init(
        workspacePath: String,
        baseline: SessionChangeBaseline,
        currentRepositoryHeads: [String: String],
        repositoryDiffs: [String: String],
        featureRevision: String?,
        taskRevision: String?,
        latestTest: String?,
        sqlAndDeliveryRevisions: [String: String],
        codexSummary: String?,
        featureAndTaskFacts: [String] = [],
        canClaimPriorDiff: Bool = true,
        baselineNotice: String = ""
    ) {
        self.workspacePath = workspacePath
        self.baseline = baseline
        self.currentRepositoryHeads = currentRepositoryHeads
        self.repositoryDiffs = repositoryDiffs
        self.featureRevision = featureRevision
        self.taskRevision = taskRevision
        self.latestTest = latestTest
        self.sqlAndDeliveryRevisions = sqlAndDeliveryRevisions
        self.codexSummary = codexSummary
        self.featureAndTaskFacts = featureAndTaskFacts
        self.canClaimPriorDiff = canClaimPriorDiff
        self.baselineNotice = baselineNotice
    }
}

struct SessionChangeDraft: Hashable, Sendable {
    let workspacePath: String
    let path: String
    let markdown: String
    let baseline: SessionChangeBaseline
    let changesRevision: NativeStrictFileRevision
    let draftRevision: NativeStrictFileRevision
    let canClaimPriorDiff: Bool
    let notice: String
}

struct SessionChangeWritePlan: Hashable, Sendable {
    let workspacePath: String
    let changesPath: String
    let draftPath: String
    let markdown: String
    let changesRevision: NativeStrictFileRevision
    let draftRevision: NativeStrictFileRevision
    let sessionID: String
}

struct SessionChangeWriteResponse: Hashable, Sendable {
    let path: String
    let revision: NativeStrictFileRevision
    let archivedDraftPath: String?
    let archiveError: String?
    let auditEventPath: String?
    let auditError: String?
}

struct NativeHandoffWritePlan: Hashable, Sendable {
    let workspacePath: String
    let path: String
    let pack: NativeContextPack
    let sourceRevisions: [String: NativeStrictFileRevision]
    let handoffRevision: NativeStrictFileRevision
}

struct NativeHandoffWriteResponse: Hashable, Sendable {
    let path: String
    let revision: NativeStrictFileRevision
    let pack: NativeContextPack
    let markdown: String
}

struct SessionRepositorySnapshot: Hashable, Sendable {
    let heads: [String: String]
    let diffs: [String: String]
}

struct NativeContextSourceSnapshot {
    let featureDocument: FeatureDocument
    let tasks: [WorkspaceTaskSnapshot]
    let confirmedChanges: [String]
    let sourceRevisions: [String: NativeStrictFileRevision]
}

enum NativeStrictFileRevision: Hashable, Sendable {
    case missing
    case regularUTF8(sha256: String, byteCount: Int)

    var token: String {
        switch self {
        case .missing: "missing"
        case .regularUTF8(let sha256, _): sha256
        }
    }
}

enum NativeSessionChangeStoreError: LocalizedError {
    case invalidWorkspace(String)
    case unsafeFile(String)
    case invalidUTF8(String)
    case stale(String)
    case unconfirmed
    case overflow
    case publicationConflict(String)

    var errorDescription: String? {
        switch self {
        case .invalidWorkspace(let path): "invalid workspace: \(path)"
        case .unsafeFile(let path): "not a regular no-follow file: \(path)"
        case .invalidUTF8(let path): "invalid UTF-8: \(path)"
        case .stale(let path): "source revision changed: \(path)"
        case .unconfirmed: "session changes are not confirmed"
        case .overflow: "required context exceeds the UTF-8 byte budget"
        case .publicationConflict(let path): "safe publication conflict: \(path)"
        }
    }
}

enum NativeSessionChangeStore {
    static let baselineFileName = "session-change-baseline.json"
    static let draftFileName = "changes.draft.md"
    static let changesFileName = "changes.md"
    static let handoffFileName = "handoff.md"
    private static let lock = NSLock()

    static func repositorySnapshot(pathsByService: [String: String]) -> SessionRepositorySnapshot {
        var heads: [String: String] = [:]
        var diffs: [String: String] = [:]
        for service in pathsByService.keys.sorted() {
            guard let path = pathsByService[service] else { continue }
            heads[service] = git(["rev-parse", "HEAD"], at: path) ?? "unavailable"
            diffs[service] = git(["status", "--short"], at: path) ?? "unavailable"
        }
        return SessionRepositorySnapshot(heads: heads, diffs: diffs)
    }

    static func sourceRevision(workspacePath: String, name: String) throws -> String {
        try withWorkspace(workspacePath) { fd, root in
            try readSnapshot(fd: fd, root: root, name: name, allowMissing: true).revision.token
        }
    }

    static func contextSourceSnapshot(
        workspacePath: String,
        workspaceFolder: String,
        changeLimit: Int = 3
    ) throws -> NativeContextSourceSnapshot {
        let feature = try NativeFeatureStore.load(workspacePath: workspacePath)
        let featureRevision = try strictRevision(feature.revision, path: feature.path)
        return try withWorkspace(workspacePath) { fd, root in
            let tasks = try readSnapshot(fd: fd, root: root, name: "tasks.md", allowMissing: true)
            let changes = try readSnapshot(fd: fd, root: root, name: changesFileName, allowMissing: true)
            return NativeContextSourceSnapshot(
                featureDocument: feature.document,
                tasks: NativeWorkspaceTaskParser.snapshots(
                    from: String(decoding: tasks.data, as: UTF8.self),
                    folder: workspaceFolder
                ),
                confirmedChanges: changeEntries(from: changes.data, limit: changeLimit),
                sourceRevisions: [
                    "FEATURES.md": featureRevision,
                    "tasks.md": tasks.revision,
                    changesFileName: changes.revision
                ]
            )
        }
    }

    static func fileRevision(path: String, workspacePath: String) throws -> String {
        let root = URL(fileURLWithPath: canonicalPath(workspacePath))
        let url = URL(fileURLWithPath: canonicalPath(path))
        guard url.path == root.path || url.path.hasPrefix(root.path + "/") else {
            throw NativeSessionChangeStoreError.invalidWorkspace(path)
        }
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0, errno == ENOENT { return "missing" }
        guard fd >= 0 else { throw NativeSessionChangeStoreError.unsafeFile(path) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw NativeSessionChangeStoreError.unsafeFile(path)
        }
        let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
        return revision(data).token
    }

    static func confirmedChangeEntries(workspacePath: String, limit: Int = 3) throws -> [String] {
        guard limit > 0 else { return [] }
        return try withWorkspace(workspacePath) { fd, root in
            let snapshot = try readSnapshot(fd: fd, root: root, name: changesFileName, allowMissing: true)
            guard snapshot.revision != .missing else { return [] }
            return changeEntries(from: snapshot.data, limit: limit)
        }
    }

    static func loadOrCreateBaseline(
        workspacePath: String,
        current: SessionChangeBaseline
    ) throws -> SessionChangeBaselineResult {
        if let saved = try loadBaseline(workspacePath: workspacePath) {
            return SessionChangeBaselineResult(
                baseline: saved,
                canClaimPriorDiff: true,
                notice: "已加载会话基线，可以声明该基线之后的差异。"
            )
        }
        guard current.workspacePath == canonicalPath(workspacePath) else {
            throw NativeSessionChangeStoreError.invalidWorkspace(workspacePath)
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        var data = try encoder.encode(current)
        data.append(0x0A)
        try lockedWorkspace(workspacePath) { fd, root in
            try replace(fd: fd, root: root, name: baselineFileName, expected: .missing, data: data)
        }
        return SessionChangeBaselineResult(
            baseline: current,
            canClaimPriorDiff: false,
            notice: "此前没有会话基线；已建立当前基线，不能声称此前差异。"
        )
    }

    static func loadBaseline(workspacePath: String) throws -> SessionChangeBaseline? {
        try withWorkspace(workspacePath) { fd, root in
            let snapshot = try readSnapshot(fd: fd, root: root, name: baselineFileName, allowMissing: true)
            guard snapshot.revision != .missing else { return nil }
            return try JSONDecoder().decode(SessionChangeBaseline.self, from: snapshot.data)
        }
    }

    static func writeDraft(
        input: SessionChangeDraftInput,
        expectedSourceRevisions: [String: NativeStrictFileRevision]? = nil
    ) throws -> SessionChangeDraft {
        let markdown = renderDraft(input)
        return try lockedWorkspace(input.workspacePath) { fd, root in
            if let expectedSourceRevisions {
                try requireSourceRevisions(expectedSourceRevisions, fd: fd, root: root)
            }
            let changes = try readSnapshot(fd: fd, root: root, name: changesFileName)
            let currentDraft = try readSnapshot(fd: fd, root: root, name: draftFileName, allowMissing: true)
            let data = Data(markdown.utf8)
            try replace(fd: fd, root: root, name: draftFileName, expected: currentDraft.revision, data: data)
            let written = try readSnapshot(fd: fd, root: root, name: draftFileName)
            return SessionChangeDraft(
                workspacePath: root.path,
                path: root.appendingPathComponent(draftFileName).path,
                markdown: markdown,
                baseline: input.baseline,
                changesRevision: changes.revision,
                draftRevision: written.revision,
                canClaimPriorDiff: input.canClaimPriorDiff,
                notice: input.baselineNotice
            )
        }
    }

    static func makeWritePlan(draft: SessionChangeDraft) throws -> SessionChangeWritePlan {
        try withWorkspace(draft.workspacePath) { fd, root in
            guard draft.path == root.appendingPathComponent(draftFileName).path else {
                throw NativeSessionChangeStoreError.invalidWorkspace(draft.path)
            }
            let changes = try readSnapshot(fd: fd, root: root, name: changesFileName)
            let currentDraft = try readSnapshot(fd: fd, root: root, name: draftFileName)
            guard changes.revision == draft.changesRevision else {
                throw NativeSessionChangeStoreError.stale(root.appendingPathComponent(changesFileName).path)
            }
            guard currentDraft.revision == draft.draftRevision,
                  currentDraft.data == Data(draft.markdown.utf8) else {
                throw NativeSessionChangeStoreError.stale(draft.path)
            }
            return SessionChangeWritePlan(
                workspacePath: root.path,
                changesPath: root.appendingPathComponent(changesFileName).path,
                draftPath: draft.path,
                markdown: draft.markdown,
                changesRevision: changes.revision,
                draftRevision: currentDraft.revision,
                sessionID: draft.baseline.sessionID
            )
        }
    }

    static func refreshDraftSnapshot(_ draft: SessionChangeDraft) throws -> SessionChangeDraft {
        try withWorkspace(draft.workspacePath) { fd, root in
            let changes = try readSnapshot(fd: fd, root: root, name: changesFileName)
            let currentDraft = try readSnapshot(fd: fd, root: root, name: draftFileName)
            return SessionChangeDraft(
                workspacePath: root.path,
                path: draft.path,
                markdown: String(decoding: currentDraft.data, as: UTF8.self),
                baseline: draft.baseline,
                changesRevision: changes.revision,
                draftRevision: currentDraft.revision,
                canClaimPriorDiff: draft.canClaimPriorDiff,
                notice: draft.notice
            )
        }
    }

    static func append(
        plan: SessionChangeWritePlan,
        confirmed: Bool,
        timestamp: String = ISO8601DateFormatter().string(from: Date()),
        auditRoot: String? = nil,
        actor: String = "Nexus Native",
        beforeFinalRevisionCheck: (() throws -> Void)? = nil,
        beforeDraftArchive: (() throws -> Void)? = nil
    ) throws -> SessionChangeWriteResponse {
        guard confirmed else { throw NativeSessionChangeStoreError.unconfirmed }
        let result: (NativeStrictFileRevision, String) = try lockedWorkspace(plan.workspacePath) { fd, root in
            try validatePlan(plan, fd: fd, root: root)
            try beforeFinalRevisionCheck?()
            try validatePlan(plan, fd: fd, root: root)
            let current = try readSnapshot(fd: fd, root: root, name: changesFileName)
            var markdown = String(decoding: current.data, as: UTF8.self)
            if !markdown.hasSuffix("\n") { markdown += "\n" }
            markdown += "\n## \(timestamp)\n\n"
            markdown += "Session change confirmed from `\(plan.sessionID)`.\n\n"
            markdown += plan.markdown
                .split(separator: "\n", omittingEmptySubsequences: false)
                .dropFirst()
                .joined(separator: "\n")
            if !markdown.hasSuffix("\n") { markdown += "\n" }
            try replace(
                fd: fd,
                root: root,
                name: changesFileName,
                expected: plan.changesRevision,
                data: Data(markdown.utf8)
            )
            let written = try readSnapshot(fd: fd, root: root, name: changesFileName)
            return (written.revision, root.path)
        }

        let archive = archiveDraft(plan: plan, timestamp: timestamp, beforeArchive: beforeDraftArchive)
        let audit = NativeAuditEventStore.appendFeedback(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: actor,
                action: "session.changes_confirmed",
                target: plan.changesPath,
                summary: "Confirmed session changes",
                metadata: [
                    "workspace": plan.workspacePath,
                    "sessionID": plan.sessionID,
                    "changesSourceRevision": plan.changesRevision.token,
                    "draftSourceRevision": plan.draftRevision.token,
                    "revision": result.0.token
                ]
            )
        )
        return SessionChangeWriteResponse(
            path: URL(fileURLWithPath: result.1).appendingPathComponent(changesFileName).path,
            revision: result.0,
            archivedDraftPath: archive.path,
            archiveError: archive.error,
            auditEventPath: audit.response?.path,
            auditError: audit.error
        )
    }

    static func makeHandoffPlan(
        workspacePath: String,
        input: NativeContextPackInput,
        expectedSourceRevisions: [String: NativeStrictFileRevision],
        maximumUTF8Bytes: Int = 6_144
    ) throws -> NativeHandoffWritePlan {
        try withWorkspace(workspacePath) { fd, root in
            try requireSourceRevisions(expectedSourceRevisions, fd: fd, root: root)
            guard input.sourceRevisions == expectedSourceRevisions.mapValues(\.token) else {
                throw NativeSessionChangeStoreError.stale(root.path)
            }
            var currentInput = input
            currentInput.workspacePath = root.path
            let pack = NativeContextPackBuilder.build(
                input: currentInput,
                maximumUTF8Bytes: max(0, maximumUTF8Bytes - 512)
            )
            guard pack.status == .ready else { throw NativeSessionChangeStoreError.overflow }
            let handoff = try readSnapshot(fd: fd, root: root, name: handoffFileName, allowMissing: true)
            return NativeHandoffWritePlan(
                workspacePath: root.path,
                path: root.appendingPathComponent(handoffFileName).path,
                pack: pack,
                sourceRevisions: expectedSourceRevisions,
                handoffRevision: handoff.revision
            )
        }
    }

    static func writeHandoff(plan: NativeHandoffWritePlan) throws -> NativeHandoffWriteResponse {
        try lockedWorkspace(plan.workspacePath) { fd, root in
            guard plan.path == root.appendingPathComponent(handoffFileName).path else {
                throw NativeSessionChangeStoreError.invalidWorkspace(plan.path)
            }
            for (name, expected) in plan.sourceRevisions {
                guard try readSnapshot(fd: fd, root: root, name: name, allowMissing: true).revision == expected else {
                    throw NativeSessionChangeStoreError.stale(root.appendingPathComponent(name).path)
                }
            }
            let sourceLine = ["FEATURES.md", "tasks.md", changesFileName]
                .map { "\($0)=\(plan.sourceRevisions[$0]?.token ?? "missing")" }
                .joined(separator: ";")
            let selectedFeature = plan.pack.markdown
                .split(separator: "\n")
                .first { $0.hasPrefix("- F-") }?
                .split(separator: " ").dropFirst().first.map(String.init) ?? "workspace"
            let metadata = """
            <!-- generated-by: Nexus Native -->
            <!-- selected-feature: \(selectedFeature) -->
            <!-- source-revisions: \(sourceLine) -->

            """
            let data = Data((metadata + plan.pack.markdown).utf8)
            guard data.count <= 6_144 else { throw NativeSessionChangeStoreError.overflow }
            try replace(fd: fd, root: root, name: handoffFileName, expected: plan.handoffRevision, data: data)
            let written = try readSnapshot(fd: fd, root: root, name: handoffFileName)
            return NativeHandoffWriteResponse(
                path: plan.path,
                revision: written.revision,
                pack: plan.pack,
                markdown: String(decoding: data, as: UTF8.self)
            )
        }
    }

    private static func renderDraft(_ input: SessionChangeDraftInput) -> String {
        var lines = [
            "# Session Change Draft",
            "",
            "Draft only; changes.md remains authoritative.",
        ]
        if !input.baselineNotice.isEmpty { lines += ["", "> \(input.baselineNotice)"] }
        lines += ["", "### Repository delta"]
        for service in Set(input.baseline.repositoryHeads.keys).union(input.currentRepositoryHeads.keys).sorted() {
            lines.append("- \(service): head \(input.baseline.repositoryHeads[service] ?? "missing") -> \(input.currentRepositoryHeads[service] ?? "missing")")
            if let diff = input.repositoryDiffs[service], !diff.isEmpty { lines.append("  - \(firstLine(diff))") }
        }
        lines += [
            "",
            "### Feature and task facts",
            "- FEATURES.md: \(input.baseline.featureRevision ?? "missing") -> \(input.featureRevision ?? "missing")",
            "- tasks.md: \(input.baseline.taskRevision ?? "missing") -> \(input.taskRevision ?? "missing")"
        ]
        lines += input.featureAndTaskFacts.map { "- \(firstLine($0))" }
        if let test = input.latestTest { lines += ["", "### Latest test", "- \(firstLine(test))"] }
        if !input.sqlAndDeliveryRevisions.isEmpty {
            lines += ["", "### SQL and delivery revisions"]
            lines += input.sqlAndDeliveryRevisions.keys.sorted().map {
                "- \($0): \(input.sqlAndDeliveryRevisions[$0]!)"
            }
        }
        if let summary = input.codexSummary, !summary.isEmpty {
            lines += ["", "### Optional Codex summary", firstLine(summary)]
        }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func firstLine(_ value: String) -> String {
        value.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
    }

    private static func changeEntries(from data: Data, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        let lines = String(decoding: data, as: UTF8.self)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        var sections: [[String]] = []
        for line in lines {
            if line.hasPrefix("## ") { sections.append([line]) }
            else if !sections.isEmpty { sections[sections.count - 1].append(line) }
        }
        return sections.suffix(limit).reversed().map {
            var lines = $0
            while lines.last?.isEmpty == true { lines.removeLast() }
            return lines.joined(separator: "\n")
        }
    }

    private static func requireSourceRevisions(
        _ expected: [String: NativeStrictFileRevision],
        fd: Int32,
        root: URL
    ) throws {
        guard Set(expected.keys) == Set(["FEATURES.md", "tasks.md", changesFileName]) else {
            throw NativeSessionChangeStoreError.stale(root.path)
        }
        for (name, revision) in expected {
            guard try readSnapshot(fd: fd, root: root, name: name, allowMissing: true).revision == revision else {
                throw NativeSessionChangeStoreError.stale(root.appendingPathComponent(name).path)
            }
        }
    }

    private static func strictRevision(
        _ revision: FeatureDocumentRevision,
        path: String
    ) throws -> NativeStrictFileRevision {
        switch revision {
        case .missing:
            return .missing
        case .regularUTF8(let sha256, let byteCount):
            return .regularUTF8(sha256: sha256, byteCount: byteCount)
        case .invalid:
            throw NativeSessionChangeStoreError.invalidUTF8(path)
        }
    }

    private static func git(_ arguments: [String], at path: String) -> String? {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", path] + arguments
        process.standardOutput = output
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            guard process.terminationStatus == 0 else { return nil }
            return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        } catch {
            return nil
        }
    }

    private static func validatePlan(_ plan: SessionChangeWritePlan, fd: Int32, root: URL) throws {
        guard plan.workspacePath == root.path,
              plan.changesPath == root.appendingPathComponent(changesFileName).path,
              plan.draftPath == root.appendingPathComponent(draftFileName).path else {
            throw NativeSessionChangeStoreError.invalidWorkspace(plan.workspacePath)
        }
        let changes = try readSnapshot(fd: fd, root: root, name: changesFileName)
        let draft = try readSnapshot(fd: fd, root: root, name: draftFileName)
        guard changes.revision == plan.changesRevision else { throw NativeSessionChangeStoreError.stale(plan.changesPath) }
        guard draft.revision == plan.draftRevision, draft.data == Data(plan.markdown.utf8) else {
            throw NativeSessionChangeStoreError.stale(plan.draftPath)
        }
    }

    private static func archiveDraft(
        plan: SessionChangeWritePlan,
        timestamp: String,
        beforeArchive: (() throws -> Void)?
    ) -> (path: String?, error: String?) {
        let safeTimestamp = timestamp.map { $0.isLetter || $0.isNumber ? $0 : "-" }
        let name = "changes.draft.confirmed-\(String(safeTimestamp)).md"
        do {
            return try lockedWorkspace(plan.workspacePath) { fd, root in
                try beforeArchive?()
                let draft = try readSnapshot(fd: fd, root: root, name: draftFileName)
                guard draft.revision == plan.draftRevision else { throw NativeSessionChangeStoreError.stale(plan.draftPath) }
                guard renameatx_np(fd, draftFileName, fd, name, UInt32(RENAME_EXCL)) == 0 else {
                    throw NativeSessionChangeStoreError.publicationConflict(root.appendingPathComponent(name).path)
                }
                return (root.appendingPathComponent(name).path, nil)
            }
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private struct Snapshot {
        let data: Data
        let revision: NativeStrictFileRevision
    }

    private static func readSnapshot(
        fd: Int32,
        root: URL,
        name: String,
        allowMissing: Bool = false
    ) throws -> Snapshot {
        let fileFD = openat(fd, name, O_RDONLY | O_NOFOLLOW)
        if fileFD < 0, errno == ENOENT, allowMissing {
            return Snapshot(data: Data(), revision: .missing)
        }
        guard fileFD >= 0 else { throw NativeSessionChangeStoreError.unsafeFile(root.appendingPathComponent(name).path) }
        defer { close(fileFD) }
        var info = stat()
        guard fstat(fileFD, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw NativeSessionChangeStoreError.unsafeFile(root.appendingPathComponent(name).path)
        }
        guard lseek(fileFD, 0, SEEK_SET) >= 0 else { throw POSIXError(.EIO) }
        let data = try FileHandle(fileDescriptor: fileFD, closeOnDealloc: false).readToEnd() ?? Data()
        guard String(data: data, encoding: .utf8) != nil else {
            throw NativeSessionChangeStoreError.invalidUTF8(root.appendingPathComponent(name).path)
        }
        return Snapshot(data: data, revision: revision(data))
    }

    private static func replace(
        fd: Int32,
        root: URL,
        name: String,
        expected: NativeStrictFileRevision,
        data: Data
    ) throws {
        guard try readSnapshot(fd: fd, root: root, name: name, allowMissing: true).revision == expected else {
            throw NativeSessionChangeStoreError.stale(root.appendingPathComponent(name).path)
        }
        let temporary = ".\(name).nexus-\(UUID().uuidString)"
        let temporaryFD = openat(fd, temporary, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard temporaryFD >= 0 else { throw NativeSessionChangeStoreError.publicationConflict(temporary) }
        do {
            try FileHandle(fileDescriptor: temporaryFD, closeOnDealloc: false).write(contentsOf: data)
            guard fsync(temporaryFD) == 0 else { throw POSIXError(.EIO) }
            close(temporaryFD)
            switch expected {
            case .missing:
                guard renameatx_np(fd, temporary, fd, name, UInt32(RENAME_EXCL)) == 0 else {
                    throw NativeSessionChangeStoreError.publicationConflict(root.appendingPathComponent(name).path)
                }
            case .regularUTF8:
                guard renameatx_np(fd, temporary, fd, name, UInt32(RENAME_SWAP)) == 0 else {
                    throw NativeSessionChangeStoreError.publicationConflict(root.appendingPathComponent(name).path)
                }
                guard unlinkat(fd, temporary, 0) == 0 else {
                    throw NativeSessionChangeStoreError.publicationConflict(root.appendingPathComponent(temporary).path)
                }
            }
            guard try readSnapshot(fd: fd, root: root, name: name).data == data else {
                throw NativeSessionChangeStoreError.publicationConflict(root.appendingPathComponent(name).path)
            }
        } catch {
            close(temporaryFD)
            _ = unlinkat(fd, temporary, 0)
            throw error
        }
    }

    private static func revision(_ data: Data) -> NativeStrictFileRevision {
        .regularUTF8(
            sha256: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
            byteCount: data.count
        )
    }

    private static func canonicalPath(_ path: String) -> String {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL.path
    }

    private static func withWorkspace<T>(_ path: String, body: (Int32, URL) throws -> T) throws -> T {
        let root = URL(fileURLWithPath: canonicalPath(path))
        guard path == root.path else { throw NativeSessionChangeStoreError.invalidWorkspace(path) }
        let fd = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard fd >= 0 else { throw NativeSessionChangeStoreError.invalidWorkspace(path) }
        defer { close(fd) }
        return try body(fd, root)
    }

    private static func lockedWorkspace<T>(_ path: String, body: (Int32, URL) throws -> T) throws -> T {
        lock.lock()
        defer { lock.unlock() }
        return try withWorkspace(path, body: body)
    }
}
