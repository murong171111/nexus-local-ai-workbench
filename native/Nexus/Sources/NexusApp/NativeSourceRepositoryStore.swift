import Foundation
import NexusBridge

enum NativeSourceRepositoryStore {
    private static let ignoredDirectoryNames: Set<String> = ["node_modules", "target", "dist"]

    static func scan(sourceReposRoot: String, fileManager: FileManager = .default) throws -> [SourceRepositorySnapshot] {
        let rootURL = URL(fileURLWithPath: (sourceReposRoot as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            return []
        }
        guard isDirectory.boolValue else {
            throw NativeSourceRepositoryStoreError.rootNotDirectory(rootURL.path)
        }

        let entries = try fileManager.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsSubdirectoryDescendants]
        )
        return entries.compactMap { entryURL in
            guard shouldIncludeDirectory(entryURL) else {
                return nil
            }
            let status = gitStatus(at: entryURL, fileManager: fileManager)
            return SourceRepositorySnapshot(
                name: entryURL.lastPathComponent,
                path: entryURL.path,
                isGit: fileManager.fileExists(atPath: entryURL.appendingPathComponent(".git").path),
                branch: status.branch,
                dirty: status.dirty,
                summary: status.summary
            )
        }
        .sorted { $0.name < $1.name }
    }

    private static func shouldIncludeDirectory(_ url: URL) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else {
            return false
        }
        let name = url.lastPathComponent
        return !name.hasPrefix(".") && !ignoredDirectoryNames.contains(name)
    }

    private static func gitStatus(at url: URL, fileManager: FileManager) -> NativeGitStatus {
        guard fileManager.fileExists(atPath: url.path) else {
            return NativeGitStatus(branch: "未创建", dirty: false, summary: "未创建")
        }
        guard fileManager.fileExists(atPath: url.appendingPathComponent(".git").path) else {
            return NativeGitStatus(branch: "非 git worktree", dirty: true, summary: "目录存在但不是 git worktree")
        }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", url.path, "status", "--short", "--branch"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return NativeGitStatus(branch: "检查失败", dirty: true, summary: error.localizedDescription)
        }

        if process.terminationStatus == 0 {
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let lines = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let branch = lines.first.map { normalizedBranchLabel($0) } ?? "未知"
            let dirty = lines.count > 1
            return NativeGitStatus(branch: branch, dirty: dirty, summary: dirty ? "有未提交改动" : "干净")
        }

        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return NativeGitStatus(branch: "检查失败", dirty: true, summary: errorOutput)
    }

    private static func normalizedBranchLabel(_ statusLine: String) -> String {
        let branch = statusLine.replacingOccurrences(of: "## ", with: "")
        let emptyRepositoryPrefix = "No commits yet on "
        if branch.hasPrefix(emptyRepositoryPrefix) {
            return String(branch.dropFirst(emptyRepositoryPrefix.count))
        }
        return branch
    }
}

private struct NativeGitStatus {
    let branch: String
    let dirty: Bool
    let summary: String
}

private enum NativeSourceRepositoryStoreError: LocalizedError {
    case rootNotDirectory(String)

    var errorDescription: String? {
        switch self {
        case .rootNotDirectory(let path):
            return "source repositories root is not a directory: \(path)"
        }
    }
}
