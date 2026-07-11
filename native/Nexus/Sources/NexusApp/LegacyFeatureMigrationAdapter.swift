import Darwin
import CryptoKit
import Foundation

struct LegacyFeatureMigrationProposal: Hashable, Sendable {
    let workspacePath: String
    let sourcePaths: [String]
    let sourceRevisions: [String: String]
    let features: [WorkspaceFeature]
}

struct LegacyFeatureMigrationWritePlan: Hashable, Sendable {
    let workspacePath: String
    let path: String
    let revision: FeatureDocumentRevision
    let sourceProposal: LegacyFeatureMigrationProposal
    let document: FeatureDocument
}

struct ConfirmedLegacyFeatureMigration: Hashable, Sendable {
    let plan: LegacyFeatureMigrationWritePlan
    let token: Int
}

enum LegacyFeatureMigrationAdapter {
    private static let candidates = [
        "需求/requirement.md",
        "需求/scope.md",
        "需求/tasks.md",
        "requirements.md",
        "acceptance.md",
        "tasks.md"
    ]

    static func propose(workspacePath: String) throws -> LegacyFeatureMigrationProposal {
        let root = URL(fileURLWithPath: workspacePath).standardizedFileURL
        guard root.path == workspacePath else { throw LegacyFeatureMigrationError.invalidWorkspace(workspacePath) }
        let rootFD = open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard rootFD >= 0 else { throw LegacyFeatureMigrationError.invalidWorkspace(workspacePath) }
        defer { close(rootFD) }

        var orderedTitles: [String] = []
        var sourcesByTitle: [String: Set<String>] = [:]
        var sourcePaths: [String] = []
        var sourceRevisions: [String: String] = [:]
        for path in candidates {
            guard let source = try read(relativePath: path, rootFD: rootFD) else { continue }
            sourcePaths.append(path)
            sourceRevisions[path] = source.revision
            for title in extractedTitles(from: source.content) {
                if sourcesByTitle[title] == nil { orderedTitles.append(title) }
                sourcesByTitle[title, default: []].insert(path)
            }
        }
        let features = orderedTitles.prefix(50).enumerated().map { index, title in
            let sources = Array(sourcesByTitle[title] ?? []).sorted()
            let description = "Migrated from: \(sources.joined(separator: ", "))"
            return WorkspaceFeature(
                id: String(format: "DRAFT-%03d", index + 1),
                title: title,
                status: .draft,
                verification: .manual,
                autoComplete: false,
                sources: sources,
                services: [],
                taskIDs: [],
                evidenceIDs: [],
                description: description,
                completedAt: nil,
                completedBy: nil,
                completionNote: nil,
                evidenceStale: false,
                preservedLines: ["", description]
            )
        }
        return LegacyFeatureMigrationProposal(
            workspacePath: workspacePath,
            sourcePaths: sourcePaths,
            sourceRevisions: sourceRevisions,
            features: features
        )
    }

    private struct SourceSnapshot {
        let content: String
        let revision: String
    }

    private static func read(relativePath: String, rootFD: Int32) throws -> SourceSnapshot? {
        let components = relativePath.split(separator: "/").map(String.init)
        guard let fileName = components.last else { return nil }
        var parentFD = dup(rootFD)
        guard parentFD >= 0 else { throw LegacyFeatureMigrationError.unreadable(relativePath) }
        defer { close(parentFD) }
        for directory in components.dropLast() {
            let nextFD = openat(parentFD, directory, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
            if nextFD < 0, errno == ENOENT { return nil }
            guard nextFD >= 0 else { throw LegacyFeatureMigrationError.unreadable(relativePath) }
            close(parentFD)
            parentFD = nextFD
        }
        let fileFD = openat(parentFD, fileName, O_RDONLY | O_NOFOLLOW)
        if fileFD < 0, errno == ENOENT { return nil }
        guard fileFD >= 0 else { throw LegacyFeatureMigrationError.unreadable(relativePath) }
        defer { close(fileFD) }
        var info = stat()
        guard fstat(fileFD, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw LegacyFeatureMigrationError.unreadable(relativePath)
        }
        let data = try FileHandle(fileDescriptor: fileFD, closeOnDealloc: false).readToEnd() ?? Data()
        guard let source = String(data: data, encoding: .utf8) else {
            throw LegacyFeatureMigrationError.invalidUTF8(relativePath)
        }
        return SourceSnapshot(
            content: source,
            revision: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    private static func extractedTitles(from source: String) -> [String] {
        source.split(whereSeparator: \.isNewline).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let value: String
            if line.hasPrefix("|") {
                let columns = line.split(separator: "|", omittingEmptySubsequences: true)
                    .map { $0.trimmingCharacters(in: .whitespaces) }
                guard let first = columns.first else { return nil }
                value = first
            } else if line.hasPrefix("- ") || line.hasPrefix("* ") {
                value = String(line.dropFirst(2))
                    .replacingOccurrences(of: #"^\[[ xX]\]\s*"#, with: "", options: .regularExpression)
            } else {
                return nil
            }
            let title = value
                .replacingOccurrences(of: "`", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            guard title.count >= 3,
                  !title.allSatisfy({ $0 == "-" || $0 == ":" }),
                  !["需求点", "任务", "状态", "待补充", "待确认"].contains(title),
                  !title.contains("template-version") else { return nil }
            return title
        }
    }
}

private enum LegacyFeatureMigrationError: LocalizedError {
    case invalidWorkspace(String)
    case unreadable(String)
    case invalidUTF8(String)

    var errorDescription: String? {
        switch self {
        case .invalidWorkspace(let path): "invalid legacy workspace: \(path)"
        case .unreadable(let path): "legacy source is not a readable regular file: \(path)"
        case .invalidUTF8(let path): "legacy source is not valid UTF-8: \(path)"
        }
    }
}
