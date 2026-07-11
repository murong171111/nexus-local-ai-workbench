import Darwin
import Foundation

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
        let linkedTasks = workspace.tasks.filter { task in
            feature.taskIDs.contains(task.id)
                || NativeWorkspaceTaskParser.featureAttribution(in: task.detail).id == feature.id
        }
        let linkedTaskIDs = linkedTasks.map(\.id).sorted()
        let missingDeclaredTasks = Set(feature.taskIDs).subtracting(linkedTaskIDs)
        let incompleteTaskIDs = Set(linkedTasks.filter(\.isActive).map(\.id))
            .union(missingDeclaredTasks)
            .sorted()

        let receiptURL = URL(fileURLWithPath: workspace.path).appendingPathComponent(receiptFileName)
        let receiptDocument: FeatureEvidenceReceiptDocument?
        do {
            receiptDocument = try loadReceipts(at: receiptURL)
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
                let output = try git(service.worktree, ["log", "-100", "--format=%H%x09%cI%x09%s"])
                for line in output.split(whereSeparator: \.isNewline) {
                    let fields = line.split(separator: "\t", maxSplits: 2).map(String.init)
                    guard fields.count == 3, explicitlyMatches(fields[2], feature: feature) else { continue }
                    relatedChangeIDs.append(fields[0])
                    if let date = ISO8601DateFormatter().date(from: fields[1]) { relatedChangeDates.append(date) }
                }
                let status = try git(service.worktree, ["status", "--porcelain"])
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
        relatedChangeDates += changeReceipts.compactMap { ISO8601DateFormatter().date(from: $0.recordedAt) }

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
        var formalSQLPaths = workspace.sqlFiles.filter {
            $0.kind != "rollback" && explicitlyDeclares($0, in: declaredText, featureID: feature.id)
        }.map(\.relativePath)
        var rollbackSQLPaths = workspace.sqlFiles.filter {
            $0.kind == "rollback" && explicitlyDeclares($0, in: declaredText, featureID: feature.id)
        }.map(\.relativePath)
        var documentationPaths = workspace.sqlDocuments.filter {
            explicitlyDeclares($0.relativePath, absolutePath: $0.path, in: declaredText, featureID: feature.id)
        }.map(\.relativePath)
        for source in feature.sources where !source.contains("://") {
            let lowercased = source.lowercased()
            if feature.verification == .sql, lowercased.hasSuffix(".sql"),
               !workspace.sqlFiles.contains(where: { $0.relativePath == source || $0.path == source }) {
                readErrors.append("declared SQL path is unavailable: \(source)")
            }
            if feature.verification == .documentation,
               [".md", ".markdown", ".txt", ".pdf"].contains(where: lowercased.hasSuffix),
               !workspace.sqlDocuments.contains(where: { $0.relativePath == source || $0.path == source }),
               !isRegularFile(resolvedPath(source, workspacePath: workspace.path)) {
                readErrors.append("declared documentation path is unavailable: \(source)")
            }
        }

        for receipt in receipts where receipt.status == .passed {
            guard let path = receipt.path else { continue }
            switch receipt.kind {
            case .sql where path.lowercased().contains("rollback"):
                if isRegularFile(resolvedPath(path, workspacePath: workspace.path)) {
                    rollbackSQLPaths.append(path)
                } else {
                    readErrors.append("receipt \(receipt.id): SQL path is unavailable: \(path)")
                }
            case .sql:
                if isRegularFile(resolvedPath(path, workspacePath: workspace.path)) {
                    formalSQLPaths.append(path)
                } else {
                    readErrors.append("receipt \(receipt.id): SQL path is unavailable: \(path)")
                }
            case .documentation:
                if isRegularFile(resolvedPath(path, workspacePath: workspace.path)) {
                    documentationPaths.append(path)
                } else {
                    readErrors.append("receipt \(receipt.id): documentation path is unavailable: \(path)")
                }
            case .test, .change:
                break
            }
        }

        let blockers = (linkedTasks.filter(\.isBlocked).map { "\($0.id): \($0.title)" }
            + workspace.risks.compactMap { risk in
                let text = "\(risk.title) \(risk.detail)"
                return explicitlyMatches(text, feature: feature) ? text : nil
            }).sorted()

        return FeatureEvidence(
            featureID: feature.id,
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
            blockers: blockers,
            readErrors: readErrors.sorted()
        )
    }

    private static func loadReceipts(at url: URL) throws -> FeatureEvidenceReceiptDocument? {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW)
        if fd < 0, errno == ENOENT { return nil }
        guard fd >= 0 else { throw CocoaError(.fileReadNoPermission) }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        let data = try FileHandle(fileDescriptor: fd, closeOnDealloc: false).readToEnd() ?? Data()
        let document = try JSONDecoder().decode(FeatureEvidenceReceiptDocument.self, from: data)
        guard document.version == 1 else { throw CocoaError(.fileReadCorruptFile) }
        return document
    }

    private static func explicitlyMatches(_ text: String, feature: WorkspaceFeature) -> Bool {
        token(text, contains: feature.id)
            || token(text, contains: "feature=\(feature.id)")
            || feature.evidenceIDs.contains { token(text, contains: $0) }
            || feature.sources.contains { source in
                !source.isEmpty && (text.contains(source) || text.contains(URL(fileURLWithPath: source).lastPathComponent))
            }
    }

    private static func token(_ text: String, contains token: String) -> Bool {
        guard !token.isEmpty else { return false }
        let escaped = NSRegularExpression.escapedPattern(for: token)
        return text.range(of: "(?<![A-Za-z0-9_])\(escaped)(?![A-Za-z0-9_])", options: .regularExpression) != nil
    }

    private static func explicitlyDeclares(
        _ file: WorkspaceSqlFile,
        in text: String,
        featureID: String
    ) -> Bool {
        explicitlyDeclares(file.relativePath, absolutePath: file.path, in: text, featureID: featureID)
    }

    private static func resolvedPath(_ path: String, workspacePath: String) -> String {
        path.hasPrefix("/") ? path : URL(fileURLWithPath: workspacePath).appendingPathComponent(path).path
    }

    private static func isRegularFile(_ path: String) -> Bool {
        let fd = open(path, O_RDONLY | O_NOFOLLOW)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        var info = stat()
        return fstat(fd, &info) == 0 && (info.st_mode & S_IFMT) == S_IFREG
    }

    private static func explicitlyDeclares(
        _ relativePath: String,
        absolutePath: String,
        in text: String,
        featureID: String
    ) -> Bool {
        text.contains(relativePath)
            || text.contains(absolutePath)
            || token(URL(fileURLWithPath: relativePath).lastPathComponent, contains: featureID)
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
