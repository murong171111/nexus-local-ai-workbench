import Foundation
import NexusBridge

enum NativeSearchIndexStore {
    private static let documentSpecs: [(key: String, kind: String, name: String)] = [
        ("agents", "guide", "AGENTS.md"),
        ("workspace", "workspace", "workspace.md"),
        ("status", "status", "STATUS.md"),
        ("services", "services", "services.md"),
        ("branches", "branches", "branches.md"),
        ("requirements", "requirements", "requirements.md"),
        ("acceptance", "acceptance", "acceptance.md"),
        ("changes", "changes", "changes.md"),
        ("plan", "plan", "plan.md"),
        ("tasks", "tasks", "tasks.md"),
        ("decisions", "decisions", "decisions.md"),
        ("handoff", "handoff", "handoff.md"),
        ("delivery", "delivery", "delivery.md"),
        ("delivery-cn", "delivery", "交付记录.md"),
        ("bootstrap", "bootstrap", "bootstrap-report.md")
    ]

    private static let indexableExtensions: Set<String> = ["md", "markdown", "mdown", "mkdn", "sql", "txt"]

    static func rebuildSummary(indexPath: String, workspaces: [WorkspaceSummary]) -> RebuildSearchIndexResponse {
        RebuildSearchIndexResponse(
            path: (indexPath as NSString).expandingTildeInPath,
            workspaceCount: workspaces.count,
            documentCount: workspaces.reduce(0) { total, workspace in
                total + documents(in: workspace).count
            }
        )
    }

    static func searchResults(
        matching query: String,
        in workspaces: [WorkspaceSummary],
        limit: Int = 30
    ) -> [SearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        let documentResults = workspaces.flatMap { workspace in
            documents(in: workspace).compactMap { document -> SearchResult? in
                let haystack = [
                    document.key,
                    document.name,
                    document.kind,
                    document.path,
                    document.content
                ]
                .joined(separator: " ")
                .lowercased()
                guard haystack.contains(normalizedQuery) else { return nil }
                return SearchResult(
                    workspaceFolder: workspace.folder,
                    workspaceName: workspace.name,
                    documentKey: document.key,
                    documentName: document.name,
                    documentPath: document.path,
                    kind: document.kind,
                    snippet: snippet(for: normalizedQuery, in: document.content)
                )
            }
        }

        return Array(documentResults.prefix(limit))
    }

    static func fallbackResults(
        matching query: String,
        in workspaces: [WorkspaceSummary],
        limit: Int = 10
    ) -> [SearchResult] {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        return workspaces.compactMap { workspace in
            let haystack = [
                workspace.name,
                workspace.folder,
                workspace.branch,
                workspace.aiState,
                workspace.serviceSummary,
                workspace.worktreeState,
                workspace.tasks.map(\.title).joined(separator: " "),
                workspace.tasks.map(\.detail).joined(separator: " "),
                workspace.risks.map(\.detail).joined(separator: " ")
            ]
            .joined(separator: " ")
            .lowercased()

            guard haystack.contains(normalizedQuery) else { return nil }

            let riskSummary = workspace.risks.first?.detail ?? "暂无风险"
            let serviceSummary = workspace.serviceSummary.isEmpty ? "服务待确认" : workspace.serviceSummary
            return SearchResult(
                workspaceFolder: workspace.folder,
                workspaceName: workspace.name,
                documentKey: "workspace",
                documentName: "Workspace metadata",
                documentPath: workspace.path,
                kind: "workspace",
                snippet: "\(workspace.branch) · \(serviceSummary) · \(riskSummary)"
            )
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func documents(in workspace: WorkspaceSummary) -> [NativeSearchDocument] {
        let root = URL(fileURLWithPath: workspace.path)
        var documents = documentSpecs.compactMap { spec -> NativeSearchDocument? in
            let url = root.appendingPathComponent(spec.name, isDirectory: false)
            return readableDocument(key: spec.key, name: spec.name, kind: spec.kind, url: url)
        }
        let sqlURL = root.appendingPathComponent("sql", isDirectory: true)
        if let sqlEntries = try? FileManager.default.contentsOfDirectory(
            at: sqlURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        ) {
            documents.append(contentsOf: sqlEntries.compactMap { url in
                guard indexableExtensions.contains(url.pathExtension.lowercased()) else { return nil }
                return readableDocument(
                    key: "sql/\(url.lastPathComponent)",
                    name: url.lastPathComponent,
                    kind: "sql",
                    url: url
                )
            })
        }
        return documents
    }

    private static func readableDocument(key: String, name: String, kind: String, url: URL) -> NativeSearchDocument? {
        guard FileManager.default.fileExists(atPath: url.path),
              let content = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return NativeSearchDocument(key: key, name: name, path: url.path, kind: kind, content: content)
    }

    private static func snippet(for query: String, in content: String) -> String {
        let lines = content
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
        let matchingLine = lines.first { $0.lowercased().contains(query) }
        let rawSnippet = matchingLine?.isEmpty == false ? matchingLine! : content.trimmingCharacters(in: .whitespacesAndNewlines)
        guard rawSnippet.count > 160 else {
            return rawSnippet
        }
        return String(rawSnippet.prefix(157)) + "..."
    }
}

private struct NativeSearchDocument {
    let key: String
    let name: String
    let path: String
    let kind: String
    let content: String
}
