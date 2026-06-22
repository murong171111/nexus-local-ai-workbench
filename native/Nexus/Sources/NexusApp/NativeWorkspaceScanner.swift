import Foundation
import NexusBridge

enum NativeWorkspaceScanner {
    private static let documentSpecs: [(key: String, name: String)] = [
        ("agents", "AGENTS.md"),
        ("workspace", "workspace.md"),
        ("status", "STATUS.md"),
        ("services", "services.md"),
        ("branches", "branches.md"),
        ("requirements", "requirements.md"),
        ("acceptance", "acceptance.md"),
        ("changes", "changes.md"),
        ("plan", "plan.md"),
        ("tasks", "tasks.md"),
        ("decisions", "decisions.md"),
        ("handoff", "handoff.md"),
        ("delivery", "delivery.md"),
        ("delivery-cn", "交付记录.md"),
        ("bootstrap", "bootstrap-report.md")
    ]

    static func scan(
        workspacesRoot: String,
        sourceReposRoot: String,
        docsRoot: String,
        fileManager: FileManager = .default,
        now: Date = Date()
    ) throws -> DashboardSnapshot {
        let root = URL(fileURLWithPath: (workspacesRoot as NSString).expandingTildeInPath)
        let sourceRoot = (sourceReposRoot as NSString).expandingTildeInPath
        let docsRoot = (docsRoot as NSString).expandingTildeInPath
        guard fileManager.fileExists(atPath: root.path) else {
            return DashboardSnapshot(
                generatedAt: ISO8601DateFormatter().string(from: now),
                workspacesRoot: root.path,
                sourceReposRoot: sourceRoot,
                docsRoot: docsRoot,
                workspaces: []
            )
        }

        let entries = try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        let workspaces = entries
            .filter { isWorkspaceDirectory($0, fileManager: fileManager) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .map { workspaceSnapshot(at: $0, sourceRoot: sourceRoot, fileManager: fileManager) }

        return DashboardSnapshot(
            generatedAt: ISO8601DateFormatter().string(from: now),
            workspacesRoot: root.path,
            sourceReposRoot: sourceRoot,
            docsRoot: docsRoot,
            workspaces: workspaces
        )
    }

    private static func isWorkspaceDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true else { return false }
        let ignored = ["node_modules", "target", "dist", "build", ".build"]
        return !ignored.contains(url.lastPathComponent)
    }

    private static func workspaceSnapshot(at root: URL, sourceRoot: String, fileManager: FileManager) -> WorkspaceSnapshot {
        let workspaceContent = read(root.appendingPathComponent("workspace.md", isDirectory: false))
        let statusContent = read(root.appendingPathComponent("STATUS.md", isDirectory: false))
        let tasks = taskSnapshots(from: read(root.appendingPathComponent("tasks.md", isDirectory: false)))
        let risks = riskLines(from: statusContent)
        let services = serviceNames(from: read(root.appendingPathComponent("services.md", isDirectory: false)))
        let updated = workspaceUpdated(at: root)

        return WorkspaceSnapshot(
            name: workspaceName(folder: root.lastPathComponent, workspaceContent: workspaceContent),
            folder: root.lastPathComponent,
            path: root.path,
            state: firstValue(in: statusContent, labels: ["当前状态", "状态", "state"]) ?? "developing",
            targetBranch: firstValue(in: workspaceContent, labels: ["目标分支", "分支", "target branch"]) ?? "待确认",
            sourceRoot: sourceRoot,
            confirmedServices: services.confirmed,
            candidateServices: services.candidates,
            taskCounts: taskCounts(from: tasks),
            decisionCount: decisionCount(at: root),
            gitRows: [],
            risks: risks,
            riskCount: risks.count,
            lifecycle: nil,
            updated: updated,
            links: documentLinks(at: root, fileManager: fileManager),
            sqlFiles: sqlFiles(at: root, fileManager: fileManager),
            sqlDocuments: sqlDocuments(at: root, fileManager: fileManager),
            worktreeCommand: "",
            tasks: tasks,
            activities: [
                WorkspaceActivitySnapshot(
                    time: updated,
                    title: "Native workspace inventory",
                    detail: "Loaded from Swift local scanner"
                )
            ],
            healthChecks: nil,
            sessionActions: nil
        )
    }

    private static func workspaceName(folder: String, workspaceContent: String) -> String {
        firstValue(in: workspaceContent, labels: ["需求名称", "名称", "name"])
            ?? heading(in: workspaceContent)
            ?? folder
    }

    private static func firstValue(in content: String, labels: [String]) -> String? {
        for line in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            for label in labels {
                let prefixes = ["- \(label):", "- \(label)：", "\(label):", "\(label)："]
                if let prefix = prefixes.first(where: { trimmed.localizedCaseInsensitiveContains($0) && trimmed.hasPrefix($0) }) {
                    let value = trimmed.dropFirst(prefix.count).trimmingCharacters(in: .whitespacesAndNewlines)
                    if !value.isEmpty { return value }
                }
            }
        }
        return nil
    }

    private static func heading(in content: String) -> String? {
        content.split(separator: "\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { $0.hasPrefix("# ") }
            .map { String($0.dropFirst(2)).trimmingCharacters(in: .whitespacesAndNewlines) }
    }

    private static func taskSnapshots(from content: String) -> [WorkspaceTaskSnapshot] {
        let rows = content.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
        return rows.compactMap { lineNumber, rawLine in
            let line = String(rawLine).trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("|"), line.hasSuffix("|") else { return nil }
            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst()
                .dropLast()
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard columns.count >= 2,
                  !columns[0].isEmpty,
                  !columns[0].contains("---"),
                  !columns[0].localizedCaseInsensitiveContains("任务") else {
                return nil
            }
            let title = stripCheckbox(columns[0])
            return WorkspaceTaskSnapshot(
                id: "task-\(lineNumber + 1)-\(slug(title))",
                title: title,
                status: columns[1],
                detail: columns.count > 2 ? columns[2] : "",
                priority: columns.count > 3 ? columns[3] : "normal",
                source: "workspace",
                sourceLine: lineNumber + 1
            )
        }
    }

    private static func stripCheckbox(_ value: String) -> String {
        value.replacingOccurrences(of: "[ ]", with: "")
            .replacingOccurrences(of: "[x]", with: "", options: .caseInsensitive)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func taskCounts(from tasks: [WorkspaceTaskSnapshot]) -> TaskCountsSnapshot {
        func count(_ keywords: [String]) -> Int {
            tasks.filter { task in
                let status = task.status.lowercased()
                return keywords.contains { status.contains($0) }
            }.count
        }
        return TaskCountsSnapshot(
            done: count(["done", "完成", "已完成"]),
            doing: count(["doing", "进行", "开发中"]),
            todo: count(["todo", "待办", "待处理", "待确认"]),
            blocked: count(["blocked", "阻塞", "卡住"]),
            deferred: count(["deferred", "延期", "暂缓"])
        )
    }

    private static func riskLines(from content: String) -> [String] {
        content.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("-") || line.hasPrefix("*") else { return nil }
            let body = line.dropFirst().trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = body.lowercased()
            guard lowercased.contains("risk")
                || lowercased.contains("block")
                || body.contains("风险")
                || body.contains("阻塞")
                || body.contains("卡住") else {
                return nil
            }
            guard !body.contains("无") && !lowercased.contains("none") else { return nil }
            return body
        }
    }

    private static func serviceNames(from content: String) -> (confirmed: [String], candidates: [String]) {
        var confirmed: [String] = []
        var candidates: [String] = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("|"), line.hasSuffix("|") else { continue }
            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst()
                .dropLast()
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard let name = columns.first,
                  !name.isEmpty,
                  !name.contains("---"),
                  !name.localizedCaseInsensitiveContains("服务") else {
                continue
            }
            let scope = columns.dropFirst().joined(separator: " ").lowercased()
            if scope.contains("candidate") || scope.contains("候选") {
                candidates.append(name)
            } else {
                confirmed.append(name)
            }
        }
        return (Array(Set(confirmed)).sorted(), Array(Set(candidates)).sorted())
    }

    private static func documentLinks(at root: URL, fileManager: FileManager) -> [String: String] {
        Dictionary(uniqueKeysWithValues: documentSpecs.compactMap { spec in
            let url = root.appendingPathComponent(spec.name, isDirectory: false)
            guard fileManager.fileExists(atPath: url.path) else { return nil }
            return (spec.key, url.path)
        })
    }

    private static func sqlFiles(at root: URL, fileManager: FileManager) -> [WorkspaceSqlFileSnapshot] {
        sqlEntries(at: root, fileManager: fileManager)
            .filter { ["sql"].contains($0.pathExtension.lowercased()) }
            .map { url in
                WorkspaceSqlFileSnapshot(
                    relativePath: "sql/\(url.lastPathComponent)",
                    path: url.path,
                    kind: url.lastPathComponent.lowercased().contains("rollback") ? "rollback" : "formal"
                )
            }
    }

    private static func sqlDocuments(at root: URL, fileManager: FileManager) -> [WorkspaceSqlDocumentSnapshot] {
        sqlEntries(at: root, fileManager: fileManager)
            .filter { ["md", "markdown", "txt"].contains($0.pathExtension.lowercased()) }
            .map { url in
                WorkspaceSqlDocumentSnapshot(
                    relativePath: "sql/\(url.lastPathComponent)",
                    path: url.path,
                    kind: url.pathExtension.lowercased()
                )
            }
    }

    private static func sqlEntries(at root: URL, fileManager: FileManager) -> [URL] {
        let sqlURL = root.appendingPathComponent("sql", isDirectory: true)
        let entries = (try? fileManager.contentsOfDirectory(
            at: sqlURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        )) ?? []
        return entries.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func decisionCount(at root: URL) -> Int {
        let content = read(root.appendingPathComponent("decisions.md", isDirectory: false))
        return content.split(separator: "\n").filter { line in
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.hasPrefix("-") || trimmed.hasPrefix("*") || trimmed.hasPrefix("|")
        }.count
    }

    private static func workspaceUpdated(at root: URL) -> String {
        let date = (try? root.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? Date()
        return ISO8601DateFormatter().string(from: date)
    }

    private static func read(_ url: URL) -> String {
        (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private static func slug(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics
        let scalars = value.unicodeScalars.map { scalar -> Character in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let collapsed = String(scalars).split(separator: "-").joined(separator: "-")
        return collapsed.isEmpty ? "item" : collapsed.lowercased()
    }
}
