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
        let branchesContent = read(root.appendingPathComponent("branches.md", isDirectory: false))
        let tasks = taskSnapshots(from: read(root.appendingPathComponent("tasks.md", isDirectory: false)))
        let services = serviceNames(from: read(root.appendingPathComponent("services.md", isDirectory: false)))
        let targetBranch = firstValue(in: workspaceContent, labels: ["目标分支", "建议目标分支", "分支", "target branch"])
            ?? firstValue(in: branchesContent, labels: ["目标分支", "建议目标分支", "target branch"])
            ?? "待确认"
        let gitRows = gitRows(
            for: services.confirmed,
            workspaceRoot: root,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        )
        let risks = riskLines(from: statusContent) + gitRisks(
            targetBranch: targetBranch,
            services: services.confirmed,
            gitRows: gitRows
        )
        let updated = workspaceUpdated(at: root)

        return WorkspaceSnapshot(
            name: workspaceName(folder: root.lastPathComponent, workspaceContent: workspaceContent),
            folder: root.lastPathComponent,
            path: root.path,
            state: firstValue(in: workspaceContent, labels: ["当前状态", "状态", "state"])
                ?? firstValue(in: statusContent, labels: ["当前状态", "状态", "state"])
                ?? "developing",
            targetBranch: targetBranch,
            sourceRoot: sourceRoot,
            confirmedServices: services.confirmed,
            candidateServices: services.candidates,
            taskCounts: taskCounts(from: tasks),
            decisionCount: decisionCount(at: root),
            gitRows: gitRows,
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
        let confirmedSectionRows = tableRows(in: section(named: "已确认相关", from: content))
        let fallbackSectionRows = tableRows(in: section(named: "初步服务范围", from: content))
        let candidateSectionRows = tableRows(in: section(named: "待验证范围", from: content))
        let confirmedRows = confirmedSectionRows.isEmpty ? fallbackSectionRows : confirmedSectionRows
        let confirmed = serviceNames(fromRows: confirmedRows)
        let candidates = serviceNames(fromRows: candidateSectionRows)
            .filter { !confirmed.contains($0) }
        if !confirmed.isEmpty || !candidates.isEmpty {
            return (confirmed, candidates)
        }
        return serviceNamesFromAnyTable(in: content)
    }

    private static func serviceNamesFromAnyTable(in content: String) -> (confirmed: [String], candidates: [String]) {
        var confirmed: [String] = []
        var candidates: [String] = []
        for columns in tableRows(in: content) {
            guard let name = columns.first,
                  !name.isEmpty,
                  !name.localizedCaseInsensitiveContains("服务") else {
                continue
            }
            let normalizedName = strippedMarkdownCode(name)
            guard !normalizedName.isEmpty else { continue }
            let scope = columns.dropFirst().joined(separator: " ").lowercased()
            if scope.contains("candidate") || scope.contains("候选") || scope.contains("待验证") {
                candidates.append(normalizedName)
            } else {
                confirmed.append(normalizedName)
            }
        }
        return (Array(Set(confirmed)).sorted(), Array(Set(candidates)).sorted())
    }

    private static func serviceNames(fromRows rows: [[String]]) -> [String] {
        Array(Set(rows.compactMap { row in
            guard let name = row.first else { return nil }
            let normalizedName = strippedMarkdownCode(name)
            return normalizedName.isEmpty ? nil : normalizedName
        })).sorted()
    }

    private static func tableRows(in content: String) -> [[String]] {
        content.split(separator: "\n", omittingEmptySubsequences: false).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("|"), line.hasSuffix("|") else { return nil }
            let columns = line.split(separator: "|", omittingEmptySubsequences: false)
                .dropFirst()
                .dropLast()
                .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            guard !columns.isEmpty,
                  !columns.allSatisfy({ $0.isEmpty || $0.allSatisfy({ $0 == "-" || $0 == ":" || $0 == " " }) }),
                  !columns.first!.localizedCaseInsensitiveContains("服务") else {
                return nil
            }
            return columns
        }
    }

    private static func section(named title: String, from content: String) -> String {
        var collecting = false
        var lines: [String] = []
        for rawLine in content.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("#") {
                if collecting {
                    break
                }
                collecting = line.contains(title)
                continue
            }
            if collecting {
                lines.append(String(rawLine))
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func strippedMarkdownCode(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "`"))
    }

    private static func gitRows(
        for services: [String],
        workspaceRoot: URL,
        sourceRoot: String,
        fileManager: FileManager
    ) -> [GitRowSnapshot] {
        services.map { service in
            let worktreeURL = workspaceRoot
                .appendingPathComponent("repos", isDirectory: true)
                .appendingPathComponent(service, isDirectory: true)
            let sourceURL = URL(fileURLWithPath: sourceRoot)
                .appendingPathComponent(service, isDirectory: true)
            return GitRowSnapshot(
                service: service,
                worktreePath: worktreeURL.path,
                sourcePath: sourceURL.path,
                worktree: gitStatus(at: worktreeURL, fileManager: fileManager),
                source: gitStatus(at: sourceURL, fileManager: fileManager)
            )
        }
    }

    private static func gitStatus(at url: URL, fileManager: FileManager) -> GitStatusSnapshot {
        guard fileManager.fileExists(atPath: url.path) else {
            return GitStatusSnapshot(exists: false, branch: "未创建", dirty: false, summary: "未创建")
        }
        guard fileManager.fileExists(atPath: url.appendingPathComponent(".git").path) else {
            return GitStatusSnapshot(exists: true, branch: "非 git worktree", dirty: true, summary: "目录存在但不是 git worktree")
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
            return GitStatusSnapshot(exists: true, branch: "检查失败", dirty: true, summary: error.localizedDescription)
        }

        if process.terminationStatus == 0 {
            let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let lines = output
                .split(separator: "\n")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            let branch = lines.first.map { normalizedGitBranch($0) } ?? "未知"
            let dirty = lines.count > 1
            return GitStatusSnapshot(exists: true, branch: branch, dirty: dirty, summary: dirty ? "有未提交改动" : "干净")
        }

        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return GitStatusSnapshot(exists: true, branch: "检查失败", dirty: true, summary: errorOutput)
    }

    private static func normalizedGitBranch(_ statusLine: String) -> String {
        let branch = statusLine.replacingOccurrences(of: "## ", with: "")
        let emptyRepositoryPrefix = "No commits yet on "
        if branch.hasPrefix(emptyRepositoryPrefix) {
            return String(branch.dropFirst(emptyRepositoryPrefix.count))
        }
        return branch
    }

    private static func gitRisks(targetBranch: String, services: [String], gitRows: [GitRowSnapshot]) -> [String] {
        var risks: [String] = []
        if targetBranch.contains("待确认") {
            risks.append("目标分支未确认")
        }
        if services.isEmpty {
            risks.append("服务范围未确认")
        }
        let missingWorktrees = gitRows.filter { !$0.worktree.exists }.map(\.service)
        if !missingWorktrees.isEmpty {
            risks.append("worktree 未创建: \(missingWorktrees.joined(separator: ", "))")
        }
        let missingSources = gitRows.filter { !$0.source.exists }.map(\.service)
        if !missingSources.isEmpty {
            risks.append("源仓库缺失: \(missingSources.joined(separator: ", "))")
        }
        let dirtyServices = gitRows
            .filter { $0.worktree.dirty || $0.source.dirty }
            .map(\.service)
        if !dirtyServices.isEmpty {
            risks.append("存在未提交改动: \(dirtyServices.joined(separator: ", "))")
        }
        let branchMismatches = gitRows
            .filter { row in
                row.worktree.exists
                    && !targetBranch.contains("待确认")
                    && normalizedBranchForComparison(row.worktree.branch) != normalizedBranchForComparison(targetBranch)
            }
            .map { "\($0.service)(\($0.worktree.branch))" }
        if !branchMismatches.isEmpty {
            risks.append("worktree 分支不一致: \(branchMismatches.joined(separator: ", "))")
        }
        return risks
    }

    private static func normalizedBranchForComparison(_ value: String) -> String {
        value.split(separator: "...", maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "origin/", with: "")
            .lowercased()
            ?? ""
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
