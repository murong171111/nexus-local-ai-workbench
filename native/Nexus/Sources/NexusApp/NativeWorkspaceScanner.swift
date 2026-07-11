import Foundation
import NexusBridge

enum NativeWorkspaceScanner {
    private static let documentSpecs: [(key: String, name: String)] = [
        ("agents", "AGENTS.md"),
        ("workspace", "workspace.md"),
        ("features", "FEATURES.md"),
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
    private static let ignoredWorkspaceDirectoryNames: Set<String> = [
        "dashboard", "node_modules", "target", "dist", "build", ".build"
    ]
    private static let workspaceIdentityFileNames = ["workspace.md", "STATUS.md"]

    static func workspaceDirectoryCount(
        workspacesRoot: String,
        fileManager: FileManager = .default
    ) -> Int {
        let root = URL(fileURLWithPath: (workspacesRoot as NSString).expandingTildeInPath)
        return (try? workspaceDirectories(at: root, fileManager: fileManager).count) ?? 0
    }

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

        let workspaces = try workspaceDirectories(at: root, fileManager: fileManager)
            .map { workspaceSnapshot(at: $0, sourceRoot: sourceRoot, fileManager: fileManager) }

        return DashboardSnapshot(
            generatedAt: ISO8601DateFormatter().string(from: now),
            workspacesRoot: root.path,
            sourceReposRoot: sourceRoot,
            docsRoot: docsRoot,
            workspaces: workspaces
        )
    }

    private static func workspaceDirectories(
        at root: URL,
        fileManager: FileManager
    ) throws -> [URL] {
        try fileManager.contentsOfDirectory(
            at: root,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        .filter { isWorkspaceDirectory($0, fileManager: fileManager) }
        .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
    }

    private static func isWorkspaceDirectory(_ url: URL, fileManager: FileManager) -> Bool {
        guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
              !ignoredWorkspaceDirectoryNames.contains(url.lastPathComponent) else {
            return false
        }

        return workspaceIdentityFileNames.contains { filename in
            var isDirectory: ObjCBool = false
            let path = url.appendingPathComponent(filename, isDirectory: false).path
            return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
        }
    }

    private static func workspaceSnapshot(at root: URL, sourceRoot: String, fileManager: FileManager) -> WorkspaceSnapshot {
        let workspaceContent = read(root.appendingPathComponent("workspace.md", isDirectory: false))
        let statusContent = read(root.appendingPathComponent("STATUS.md", isDirectory: false))
        let branchesContent = read(root.appendingPathComponent("branches.md", isDirectory: false))
        let tasks = NativeWorkspaceTaskParser.snapshots(
            from: read(root.appendingPathComponent("tasks.md", isDirectory: false)),
            folder: root.lastPathComponent
        )
        let services = serviceNames(from: read(root.appendingPathComponent("services.md", isDirectory: false)))
        let lifecycle = lifecycleResolution(
            workspaceContent: workspaceContent,
            statusContent: statusContent
        )
        let targetBranch = firstValue(in: workspaceContent, labels: ["目标分支", "建议目标分支", "分支", "target branch"])
            ?? firstValue(in: branchesContent, labels: ["目标分支", "建议目标分支", "target branch"])
            ?? "待确认"
        let gitRows = gitRows(
            for: services.confirmed,
            targetBranch: targetBranch,
            workspaceRoot: root,
            sourceRoot: sourceRoot,
            fileManager: fileManager
        )
        let lifecycleRisks = lifecycle.risk.map { [$0] } ?? []
        let risks = riskLines(from: statusContent) + lifecycleRisks + gitRisks(
            targetBranch: targetBranch,
            services: services.confirmed,
            gitRows: gitRows
        )
        let updated = workspaceUpdated(at: root)

        return WorkspaceSnapshot(
            name: workspaceName(folder: root.lastPathComponent, workspaceContent: workspaceContent),
            folder: root.lastPathComponent,
            path: root.path,
            state: lifecycle.state,
            targetBranch: targetBranch,
            sourceRoot: sourceRoot,
            confirmedServices: services.confirmed,
            candidateServices: services.candidates,
            taskCounts: taskCounts(from: tasks),
            decisionCount: decisionCount(at: root),
            gitRows: gitRows,
            risks: risks,
            riskCount: risks.count,
            lifecycle: lifecycle.snapshot,
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

    private struct LifecycleResolution {
        let state: String
        let snapshot: WorkspaceLifecycleSnapshot
        let risk: String?
    }

    private static func lifecycleResolution(
        workspaceContent: String,
        statusContent: String
    ) -> LifecycleResolution {
        let workspaceRaw = firstValue(in: workspaceContent, labels: ["当前状态", "状态", "state"])
        let statusRaw = firstValue(in: statusContent, labels: ["当前状态", "状态", "state"])
        let focus = firstValue(in: statusContent, labels: ["当前焦点", "focus"])
        let requestedNextAction = firstValue(in: statusContent, labels: ["下一步", "next action"])
        let workspaceState = workspaceRaw.flatMap(normalizedLifecycleState)
        let statusState = statusRaw.flatMap(normalizedLifecycleState)

        let evidence = [
            workspaceRaw.map { "workspace.md=\($0)" },
            statusRaw.map { "STATUS.md=\($0)" }
        ].compactMap { $0 }.joined(separator: ", ")

        let state: String
        let detail: String
        let risk: String?

        if (workspaceRaw != nil && workspaceState == nil) || (statusRaw != nil && statusState == nil) {
            state = "unknown"
            detail = "生命周期状态无法识别: \(evidence)"
            risk = detail
        } else if let workspaceState, let statusState, workspaceState != statusState {
            state = "blocked"
            detail = "生命周期状态冲突: \(evidence)"
            risk = detail
        } else if let resolved = workspaceState ?? statusState {
            state = resolved
            detail = focus ?? "已从本地 Markdown 读取生命周期状态: \(resolved)。"
            risk = nil
        } else {
            state = "unknown"
            detail = "workspace.md 和 STATUS.md 尚未记录生命周期状态。"
            risk = nil
        }

        let presentation = lifecyclePresentation(for: state)
        return LifecycleResolution(
            state: state,
            snapshot: WorkspaceLifecycleSnapshot(
                stage: state,
                label: presentation.label,
                detail: detail,
                progress: presentation.progress,
                nextAction: requestedNextAction ?? presentation.nextAction,
                documentKey: "status"
            ),
            risk: risk
        )
    }

    private static func normalizedLifecycleState(_ value: String) -> String? {
        switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "analyzing", "analysis", "scoping", "scope", "范围确认", "分析中":
            return "scoping"
        case "setup", "environment", "环境准备", "准备中":
            return "setup"
        case "developing", "development", "dev", "开发中":
            return "developing"
        case "delivery", "delivering", "交付", "交付整理":
            return "delivery"
        case "done", "ready", "completed", "complete", "完成", "已完成":
            return "done"
        case "blocked", "block", "阻塞":
            return "blocked"
        case "archived", "archive", "归档", "已归档":
            return "archived"
        default:
            return nil
        }
    }

    private static func lifecyclePresentation(
        for state: String
    ) -> (label: String, progress: Int, nextAction: String) {
        switch state {
        case "scoping":
            return ("范围确认 / Scoping", 15, "补齐服务范围和目标分支。")
        case "setup":
            return ("环境准备 / Setup", 35, "创建缺失 worktree 后再进入开发。")
        case "developing":
            return ("开发中 / Developing", 60, "继续编码、验证，并保持交付记录同步。")
        case "delivery":
            return ("交付整理 / Delivery", 80, "补齐交付记录、SQL、验证和风险说明。")
        case "done":
            return ("待归档 / Done", 95, "确认 PR/发布状态后归档工作区。")
        case "blocked":
            return ("阻塞 / Blocked", 25, "先处理阻塞项。")
        case "archived":
            return ("已归档 / Archived", 100, "需要再次开发时从 handoff 恢复上下文。")
        default:
            return ("状态待确认 / Unknown", 0, "在 workspace.md 或 STATUS.md 记录当前状态。")
        }
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
        targetBranch: String,
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
            let sourceStatus = gitStatus(at: sourceURL, fileManager: fileManager)
            return GitRowSnapshot(
                service: service,
                worktreePath: worktreeURL.path,
                sourcePath: sourceURL.path,
                worktree: gitStatus(at: worktreeURL, fileManager: fileManager),
                source: sourceStatusWithTargetBranchAvailability(
                    sourceStatus,
                    sourceURL: sourceURL,
                    targetBranch: targetBranch,
                    fileManager: fileManager
                )
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

    private static func sourceStatusWithTargetBranchAvailability(
        _ status: GitStatusSnapshot,
        sourceURL: URL,
        targetBranch: String,
        fileManager: FileManager
    ) -> GitStatusSnapshot {
        guard targetBranchConfirmed(targetBranch),
              status.exists,
              fileManager.fileExists(atPath: sourceURL.appendingPathComponent(".git").path) else {
            return status
        }

        let normalizedTarget = normalizedBranchForComparison(targetBranch)
        if normalizedBranchForComparison(status.branch) == normalizedTarget {
            return appendingGitSummary(status, "target branch available: \(normalizedTarget)")
        }

        switch targetBranchAvailability(in: sourceURL, targetBranch: normalizedTarget) {
        case .available:
            return appendingGitSummary(status, "target branch available: \(normalizedTarget)")
        case .missing:
            return appendingGitSummary(status, "target branch missing: \(normalizedTarget)")
        case .failed(let detail):
            return appendingGitSummary(status, "target branch unavailable: \(normalizedTarget); check failed: \(detail)")
        }
    }

    private enum TargetBranchAvailability {
        case available
        case missing
        case failed(String)
    }

    private static func targetBranchAvailability(
        in sourceURL: URL,
        targetBranch: String
    ) -> TargetBranchAvailability {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", sourceURL.path, "show-ref"]
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return .failed(error.localizedDescription)
        }

        let output = String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        let refs = output
            .split(separator: "\n")
            .compactMap { line -> String? in
                line.split(separator: " ").last.map(String.init)
            }
        if refs.contains(where: { branchRef($0, matches: targetBranch) }) {
            return .available
        }

        let errorOutput = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if process.terminationStatus == 0
            || (output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && errorOutput.isEmpty) {
            return .missing
        }

        return .failed(errorOutput.isEmpty ? "git show-ref exited \(process.terminationStatus)" : errorOutput)
    }

    private static func branchRef(_ ref: String, matches targetBranch: String) -> Bool {
        if ref == "refs/heads/\(targetBranch)" {
            return true
        }
        let remotePrefix = "refs/remotes/"
        guard ref.hasPrefix(remotePrefix) else { return false }
        let remoteAndBranch = String(ref.dropFirst(remotePrefix.count))
        guard let slash = remoteAndBranch.firstIndex(of: "/") else { return false }
        let branch = String(remoteAndBranch[remoteAndBranch.index(after: slash)...])
        return branch == targetBranch
    }

    private static func appendingGitSummary(
        _ status: GitStatusSnapshot,
        _ detail: String
    ) -> GitStatusSnapshot {
        let summary = status.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        return GitStatusSnapshot(
            exists: status.exists,
            branch: status.branch,
            dirty: status.dirty,
            summary: summary.isEmpty ? detail : "\(summary); \(detail)"
        )
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
        let targetBranchIssues = gitRows
            .filter { row in
                row.source.exists
                    && targetBranchConfirmed(targetBranch)
                    && sourceReportsMissingTargetBranch(row.source.summary, targetBranch: targetBranch)
            }
            .map { "\($0.service)(\(normalizedBranchForComparison(targetBranch)))" }
        if !targetBranchIssues.isEmpty {
            risks.append("目标分支不可用: \(targetBranchIssues.joined(separator: ", "))")
        }
        return risks
    }

    private static func sourceReportsMissingTargetBranch(
        _ summary: String,
        targetBranch: String
    ) -> Bool {
        let normalized = summary.lowercased()
        let target = normalizedBranchForComparison(targetBranch)
        guard normalized.contains("target branch missing")
                || normalized.contains("target branch unavailable")
                || normalized.contains("目标分支缺失")
                || normalized.contains("目标分支不可用") else {
            return false
        }
        return target.isEmpty || normalized.contains(target)
    }

    private static func normalizedBranchForComparison(_ value: String) -> String {
        value.split(separator: "...", maxSplits: 1).first.map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "origin/", with: "")
            .lowercased()
            ?? ""
    }

    private static func targetBranchConfirmed(_ branch: String) -> Bool {
        let normalized = normalizedBranchForComparison(branch)
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("未确认")
            && !normalized.contains("pending")
            && !normalized.contains("tbd")
            && !normalized.contains("todo")
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
}
