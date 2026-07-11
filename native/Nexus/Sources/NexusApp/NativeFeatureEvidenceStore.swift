import CryptoKit
import Darwin
import Foundation
import NexusBridge

enum FeatureEvidenceReceiptKind: String, Codable, Hashable, Sendable {
    case test
    case change
    case sql
    case documentation
}

enum FeatureEvidenceReceiptStatus: String, Codable, Hashable, Sendable {
    case passed
    case failed
}

struct FeatureEvidenceReceipt: Codable, Hashable, Sendable {
    let id: String
    let kind: FeatureEvidenceReceiptKind
    let featureIDs: [String]
    let status: FeatureEvidenceReceiptStatus
    let recordedAt: String
    let path: String?
}

struct FeatureEvidenceReceiptDocument: Codable, Hashable, Sendable {
    let version: Int
    let receipts: [FeatureEvidenceReceipt]
}

enum NativeFeatureEvidenceStore {
    static let receiptFileName = "feature-evidence.json"
    typealias GitRunner = (_ repositoryPath: String, _ arguments: [String]) throws -> String

    static func collect(
        feature: WorkspaceFeature,
        workspace: WorkspaceSummary,
        now: Date = Date(),
        git: GitRunner = runGit
    ) -> FeatureEvidence {
        var readErrors: [String] = []
        var sourceRevisions: [String: String] = [:]

        let taskSnapshots: [WorkspaceTaskSnapshot]
        do {
            let snapshot = try readWorkspaceFile(relativePath: "tasks.md", workspacePath: workspace.path)
            sourceRevisions["file:tasks.md"] = snapshot?.revision ?? "missing"
            taskSnapshots = NativeWorkspaceTaskParser.snapshots(
                from: snapshot?.content ?? "",
                folder: workspace.folder
            )
        } catch {
            taskSnapshots = []
            readErrors.append("tasks.md: \(error.localizedDescription)")
        }
        let linkedTasks = taskSnapshots.filter { task in
            feature.taskIDs.contains(task.id)
                || NativeWorkspaceTaskParser.featureAttribution(in: task.detail).id == feature.id
        }
        let linkedTaskIDs = linkedTasks.map(\.id).sorted()
        let missingDeclaredTasks = Set(feature.taskIDs).subtracting(linkedTaskIDs)
        let incompleteTaskIDs = Set(linkedTasks.filter(taskIsActive).map(\.id))
            .union(missingDeclaredTasks)
            .sorted()

        let receiptDocument: FeatureEvidenceReceiptDocument?
        do {
            let snapshot = try readWorkspaceFile(
                relativePath: receiptFileName,
                workspacePath: workspace.path
            )
            sourceRevisions["file:\(receiptFileName)"] = snapshot?.revision ?? "missing"
            if let snapshot {
                let document = try JSONDecoder().decode(
                    FeatureEvidenceReceiptDocument.self,
                    from: snapshot.data
                )
                guard document.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
                receiptDocument = document
            } else {
                receiptDocument = nil
            }
        } catch {
            receiptDocument = nil
            readErrors.append("\(receiptFileName): \(error.localizedDescription)")
        }
        let receipts = (receiptDocument?.receipts ?? []).filter { receipt in
            receipt.featureIDs.contains(feature.id) || feature.evidenceIDs.contains(receipt.id)
        }
        for receipt in receipts where ISO8601DateFormatter().date(from: receipt.recordedAt) == nil {
            readErrors.append("receipt \(receipt.id): recordedAt is not valid ISO-8601")
        }

        var relatedChangeIDs: [String] = []
        var relatedChangeDates: [Date] = []
        let selectedServices = workspace.services.filter { feature.services.contains($0.name) }
        for missing in Set(feature.services).subtracting(selectedServices.map(\.name)).sorted() {
            readErrors.append("service \(missing): repository evidence is unavailable")
        }
        for service in selectedServices {
            do {
                let logArguments = ["log", "-100", "--format=%H%x09%cI%x09%s"]
                let output = try git(service.worktree, logArguments)
                sourceRevisions["git-log:\(service.worktree)"] = sha256(output)
                for line in output.split(whereSeparator: \.isNewline) {
                    let fields = line.split(separator: "\t", maxSplits: 2).map(String.init)
                    guard fields.count == 3, explicitlyMatches(fields[2], feature: feature) else { continue }
                    relatedChangeIDs.append(fields[0])
                    if let date = ISO8601DateFormatter().date(from: fields[1]) {
                        relatedChangeDates.append(date)
                    }
                }
                let statusArguments = ["status", "--porcelain"]
                let status = try git(service.worktree, statusArguments)
                sourceRevisions["git-status:\(service.worktree)"] = sha256(status)
                if status.split(whereSeparator: \.isNewline).contains(where: {
                    explicitlyMatches(String($0), feature: feature)
                }) {
                    relatedChangeIDs.append("working-tree:\(service.name)")
                    relatedChangeDates.append(now)
                }
            } catch {
                readErrors.append("service \(service.name): git evidence failed: \(error.localizedDescription)")
            }
        }

        let changeReceipts = receipts.filter { $0.kind == .change && $0.status == .passed }
        relatedChangeIDs += changeReceipts.map(\.id)
        relatedChangeDates += changeReceipts.compactMap {
            ISO8601DateFormatter().date(from: $0.recordedAt)
        }

        let testReceipts = receipts.filter { $0.kind == .test }
        let requiredTestIDs: [String]
        if feature.verification == .code {
            let nonTestReceiptIDs = Set(receipts.filter { $0.kind != .test }.map(\.id))
            requiredTestIDs = feature.evidenceIDs.filter { !nonTestReceiptIDs.contains($0) }
                + testReceipts.map(\.id)
        } else {
            requiredTestIDs = testReceipts.map(\.id)
        }
        let passedTests = Set(testReceipts.filter { $0.status == .passed }.map(\.id))
        let failedOrMissingTestIDs = Set(requiredTestIDs).subtracting(passedTests)
            .union(testReceipts.filter { $0.status == .failed }.map(\.id))
            .sorted()
        let latestTestAt = testReceipts
            .filter { $0.status == .passed }
            .compactMap { ISO8601DateFormatter().date(from: $0.recordedAt) }
            .max()

        let declaredText = (feature.sources + linkedTasks.map(\.detail)).joined(separator: "\n")
        var formalSQLPaths: [String] = []
        var rollbackSQLPaths: [String] = []
        var documentationPaths: [String] = []
        let sqlCandidates = workspace.sqlFiles.filter {
            declaredText.contains($0.relativePath)
                || declaredText.contains($0.path)
                || (feature.verification == .sql
                    && token(URL(fileURLWithPath: $0.relativePath).lastPathComponent, contains: feature.id))
        }.map { ($0.relativePath, $0.kind == "rollback") }
        for (path, isRollback) in sqlCandidates {
            recordArtifact(
                path: path,
                kind: isRollback ? .rollbackSQL : .formalSQL,
                workspacePath: workspace.path,
                relatedChangeIDs: &relatedChangeIDs,
                relatedChangeDates: &relatedChangeDates,
                formalSQLPaths: &formalSQLPaths,
                rollbackSQLPaths: &rollbackSQLPaths,
                documentationPaths: &documentationPaths,
                sourceRevisions: &sourceRevisions,
                readErrors: &readErrors
            )
        }
        let documentCandidates = workspace.sqlDocuments.filter {
            declaredText.contains($0.relativePath)
                || declaredText.contains($0.path)
                || (feature.verification == .documentation
                    && token(URL(fileURLWithPath: $0.relativePath).lastPathComponent, contains: feature.id))
        }.map(\.relativePath)
        for path in documentCandidates {
            recordArtifact(
                path: path,
                kind: .documentation,
                workspacePath: workspace.path,
                relatedChangeIDs: &relatedChangeIDs,
                relatedChangeDates: &relatedChangeDates,
                formalSQLPaths: &formalSQLPaths,
                rollbackSQLPaths: &rollbackSQLPaths,
                documentationPaths: &documentationPaths,
                sourceRevisions: &sourceRevisions,
                readErrors: &readErrors
            )
        }
        for source in feature.sources where !source.contains("://") {
            let lowercased = source.lowercased()
            if feature.verification == .sql, lowercased.hasSuffix(".sql") {
                recordArtifact(
                    path: source,
                    kind: lowercased.contains("rollback") ? .rollbackSQL : .formalSQL,
                    workspacePath: workspace.path,
                    relatedChangeIDs: &relatedChangeIDs,
                    relatedChangeDates: &relatedChangeDates,
                    formalSQLPaths: &formalSQLPaths,
                    rollbackSQLPaths: &rollbackSQLPaths,
                    documentationPaths: &documentationPaths,
                    sourceRevisions: &sourceRevisions,
                    readErrors: &readErrors
                )
            }
            if feature.verification == .documentation,
               [".md", ".markdown", ".txt", ".pdf"].contains(where: lowercased.hasSuffix) {
                recordArtifact(
                    path: source,
                    kind: .documentation,
                    workspacePath: workspace.path,
                    relatedChangeIDs: &relatedChangeIDs,
                    relatedChangeDates: &relatedChangeDates,
                    formalSQLPaths: &formalSQLPaths,
                    rollbackSQLPaths: &rollbackSQLPaths,
                    documentationPaths: &documentationPaths,
                    sourceRevisions: &sourceRevisions,
                    readErrors: &readErrors
                )
            }
        }
        for receipt in receipts where receipt.status == .passed {
            guard let path = receipt.path else { continue }
            let kind: ArtifactKind?
            switch receipt.kind {
            case .sql: kind = path.lowercased().contains("rollback") ? .rollbackSQL : .formalSQL
            case .documentation: kind = .documentation
            case .test, .change: kind = nil
            }
            if let kind {
                recordArtifact(
                    path: path,
                    kind: kind,
                    workspacePath: workspace.path,
                    errorPrefix: "receipt \(receipt.id): ",
                    relatedChangeIDs: &relatedChangeIDs,
                    relatedChangeDates: &relatedChangeDates,
                    formalSQLPaths: &formalSQLPaths,
                    rollbackSQLPaths: &rollbackSQLPaths,
                    documentationPaths: &documentationPaths,
                    sourceRevisions: &sourceRevisions,
                    readErrors: &readErrors
                )
            }
        }

        var blockers = linkedTasks.filter(taskIsBlocked).map { "\($0.id): \($0.title)" }
        for path in ["STATUS.md", "交付记录.md"] {
            do {
                let snapshot = try readWorkspaceFile(relativePath: path, workspacePath: workspace.path)
                sourceRevisions["file:\(path)"] = snapshot?.revision ?? "missing"
                blockers += riskLines(from: snapshot?.content ?? "", feature: feature)
            } catch {
                readErrors.append("\(path): \(error.localizedDescription)")
            }
        }

        return FeatureEvidence(
            featureID: feature.id,
            workspacePath: workspace.path,
            linkedTaskIDs: linkedTaskIDs,
            incompleteTaskIDs: incompleteTaskIDs,
            relatedChangeIDs: Array(Set(relatedChangeIDs)).sorted(),
            latestRelatedChangeAt: relatedChangeDates.max(),
            requiredTestIDs: Array(Set(requiredTestIDs)).sorted(),
            failedOrMissingTestIDs: failedOrMissingTestIDs,
            latestTestAt: latestTestAt,
            formalSQLPaths: Array(Set(formalSQLPaths)).sorted(),
            rollbackSQLPaths: Array(Set(rollbackSQLPaths)).sorted(),
            documentationPaths: Array(Set(documentationPaths)).sorted(),
            blockers: Array(Set(blockers)).sorted(),
            readErrors: Array(Set(readErrors)).sorted(),
            sourceRevisions: sourceRevisions
        )
    }

    static func validateSourceRevisions(
        _ evidence: FeatureEvidence,
        git: GitRunner = runGit
    ) throws {
        for (key, expected) in evidence.sourceRevisions {
            let current: String
            if key.hasPrefix("file:") {
                let relativePath = String(key.dropFirst("file:".count))
                current = try readWorkspaceFile(
                    relativePath: relativePath,
                    workspacePath: evidence.workspacePath,
                    requiresUTF8: false
                )?.revision ?? "missing"
            } else if key.hasPrefix("git-log:") {
                let path = String(key.dropFirst("git-log:".count))
                current = sha256(try git(path, ["log", "-100", "--format=%H%x09%cI%x09%s"]))
            } else if key.hasPrefix("git-status:") {
                let path = String(key.dropFirst("git-status:".count))
                current = sha256(try git(path, ["status", "--porcelain"]))
            } else {
                throw NativeFeatureEvidenceError.stale(key)
            }
            guard current == expected else { throw NativeFeatureEvidenceError.stale(key) }
        }
    }

    private enum ArtifactKind {
        case formalSQL
        case rollbackSQL
        case documentation
    }

    private struct WorkspaceFileSnapshot {
        let data: Data
        let content: String?
        let revision: String
        let modifiedAt: Date
    }

    private static func recordArtifact(
        path: String,
        kind: ArtifactKind,
        workspacePath: String,
        errorPrefix: String = "",
        relatedChangeIDs: inout [String],
        relatedChangeDates: inout [Date],
        formalSQLPaths: inout [String],
        rollbackSQLPaths: inout [String],
        documentationPaths: inout [String],
        sourceRevisions: inout [String: String],
        readErrors: inout [String]
    ) {
        guard let relativePath = workspaceRelativePath(path, workspacePath: workspacePath) else {
            readErrors.append("\(errorPrefix)evidence path is outside workspace: \(path)")
            return
        }
        do {
            guard let snapshot = try readWorkspaceFile(
                relativePath: relativePath,
                workspacePath: workspacePath,
                requiresUTF8: false
            ) else {
                readErrors.append("\(errorPrefix)evidence path is unavailable: \(path)")
                return
            }
            sourceRevisions["file:\(relativePath)"] = snapshot.revision
            relatedChangeIDs.append("file:\(relativePath)")
            relatedChangeDates.append(snapshot.modifiedAt)
            switch kind {
            case .formalSQL: formalSQLPaths.append(relativePath)
            case .rollbackSQL: rollbackSQLPaths.append(relativePath)
            case .documentation: documentationPaths.append(relativePath)
            }
        } catch {
            readErrors.append("\(errorPrefix)evidence path is unsafe: \(path)")
        }
    }

    private static func readWorkspaceFile(
        relativePath: String,
        workspacePath: String,
        requiresUTF8: Bool = true
    ) throws -> WorkspaceFileSnapshot? {
        guard let safePath = workspaceRelativePath(relativePath, workspacePath: workspacePath) else {
            throw NativeFeatureEvidenceError.outsideWorkspace(relativePath)
        }
        let rootFD = open(workspacePath, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard rootFD >= 0 else { throw NativeFeatureEvidenceError.unreadable(workspacePath) }
        defer { close(rootFD) }
        let components = safePath.split(separator: "/").map(String.init)
        guard let fileName = components.last else { return nil }
        var parentFD = dup(rootFD)
        guard parentFD >= 0 else { throw NativeFeatureEvidenceError.unreadable(safePath) }
        defer { close(parentFD) }
        for directory in components.dropLast() {
            let nextFD = openat(parentFD, directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if nextFD < 0, errno == ENOENT { return nil }
            guard nextFD >= 0 else { throw NativeFeatureEvidenceError.unreadable(safePath) }
            close(parentFD)
            parentFD = nextFD
        }
        let fileFD = openat(parentFD, fileName, O_RDONLY | O_NOFOLLOW)
        if fileFD < 0, errno == ENOENT { return nil }
        guard fileFD >= 0 else { throw NativeFeatureEvidenceError.unreadable(safePath) }
        defer { close(fileFD) }
        var info = stat()
        guard fstat(fileFD, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw NativeFeatureEvidenceError.unreadable(safePath)
        }
        let data = try FileHandle(fileDescriptor: fileFD, closeOnDealloc: false).readToEnd() ?? Data()
        let content = String(data: data, encoding: .utf8)
        if requiresUTF8, content == nil {
            throw NativeFeatureEvidenceError.invalidUTF8(safePath)
        }
        return WorkspaceFileSnapshot(
            data: data,
            content: content,
            revision: sha256(data),
            modifiedAt: Date(
                timeIntervalSince1970: TimeInterval(info.st_mtimespec.tv_sec)
                    + TimeInterval(info.st_mtimespec.tv_nsec) / 1_000_000_000
            )
        )
    }

    private static func workspaceRelativePath(_ path: String, workspacePath: String) -> String? {
        let root = URL(fileURLWithPath: workspacePath).standardizedFileURL
        let url = path.hasPrefix("/")
            ? URL(fileURLWithPath: path).standardizedFileURL
            : root.appendingPathComponent(path).standardizedFileURL
        guard url.path.hasPrefix(root.path + "/") else { return nil }
        return String(url.path.dropFirst(root.path.count + 1))
    }

    private static func explicitlyMatches(_ text: String, feature: WorkspaceFeature) -> Bool {
        token(text, contains: feature.id)
            || token(text, contains: "feature=\(feature.id)")
            || feature.evidenceIDs.contains { token(text, contains: $0) }
            || feature.sources.contains { source in !source.isEmpty && text.contains(source) }
    }

    private static func token(_ text: String, contains token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: token)
        return text.range(
            of: "(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])",
            options: .regularExpression
        ) != nil
    }

    private static func taskIsActive(_ task: WorkspaceTaskSnapshot) -> Bool {
        let status = task.status.lowercased()
        let statusAndDetail = "\(task.status) \(task.detail)".lowercased()
        let isDone = ["done", "closed", "resolved", "完成", "已完成"]
            .contains { status.contains($0) }
        let isDeferred = ["deferred", "延期"].contains { statusAndDetail.contains($0) }
        return !isDone && !isDeferred
    }

    private static func taskIsBlocked(_ task: WorkspaceTaskSnapshot) -> Bool {
        let normalized = "\(task.status) \(task.detail)".lowercased()
        return normalized.contains("blocked") || normalized.contains("阻塞")
    }

    private static func riskLines(from content: String, feature: WorkspaceFeature) -> [String] {
        content.split(whereSeparator: \.isNewline).compactMap { line in
            let value = String(line).trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = value.lowercased()
            guard explicitlyMatches(value, feature: feature),
                  lowercased.contains("risk") || lowercased.contains("block")
                    || value.contains("风险") || value.contains("阻塞") else { return nil }
            return value
        }
    }

    private static func sha256(_ value: String) -> String { sha256(Data(value.utf8)) }

    private static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func runGit(repositoryPath: String, arguments: [String]) throws -> String {
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", repositoryPath] + arguments
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            throw NSError(
                domain: "NativeFeatureEvidenceStore.Git",
                code: Int(process.terminationStatus),
                userInfo: [NSLocalizedDescriptionKey: message.trimmingCharacters(in: .whitespacesAndNewlines)]
            )
        }
        return String(decoding: output.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }
}

private enum NativeFeatureEvidenceError: LocalizedError {
    case outsideWorkspace(String)
    case unreadable(String)
    case invalidUTF8(String)
    case stale(String)

    var errorDescription: String? {
        switch self {
        case .outsideWorkspace(let path): "evidence path is outside workspace: \(path)"
        case .unreadable(let path): "evidence source is unsafe or unreadable: \(path)"
        case .invalidUTF8(let path): "evidence source is not valid UTF-8: \(path)"
        case .stale(let source): "feature evidence changed before write: \(source)"
        }
    }
}
