import Combine
import Foundation
import NexusBridge

@MainActor
final class AppState: ObservableObject {
    @Published var query = ""
    @Published var selectedFilter: WorkspaceFilter = .all
    @Published var selectedWorkspaceID: WorkspaceSummary.ID?
    @Published var workspaces: [WorkspaceSummary]
    @Published var pinnedWorkspaceIDs: Set<WorkspaceSummary.ID>
    @Published var selectedSearchScope: SearchScope
    @Published var workspaceRoot: String
    @Published var sourceReposRoot: String
    @Published var docsRoot: String
    @Published var isLoading = false
    @Published var isDocumentLoading = false
    @Published var isCreatingWorkspace = false
    @Published var lastError: String?
    @Published var bridgeMode: String
    @Published var documentPreview: DocumentSnapshot?
    @Published var widgetSnapshot: WidgetSnapshot?
    @Published var lastCreatedWorkspace: CreateWorkspaceResponse?
    @Published var searchResults: [SearchResult] = []
    @Published var selectedSearchResultIndex = 0
    @Published var isSearching = false
    @Published var searchIndexSummary: RebuildSearchIndexResponse?
    @Published var searchError: String?

    @Published var agentStatus: AgentStatus
    private let bridge: NexusBridge
    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let pinnedWorkspaceIDs = "nexus.native.pinnedWorkspaceIDs"
        static let selectedSearchScope = "nexus.native.selectedSearchScope"
    }

    init(
        workspaces: [WorkspaceSummary],
        agentStatus: AgentStatus,
        bridge: NexusBridge,
        workspaceRoot: String = "~/ks_project/workspaces",
        sourceReposRoot: String = "~/ks_project/source-repos",
        docsRoot: String = "~/ks_project/docs",
        bridgeMode: String = "Preview",
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        self.workspaces = workspaces
        self.agentStatus = agentStatus
        self.bridge = bridge
        self.workspaceRoot = workspaceRoot
        self.sourceReposRoot = sourceReposRoot
        self.docsRoot = docsRoot
        self.bridgeMode = bridge.modeDescription.isEmpty ? bridgeMode : bridge.modeDescription
        self.pinnedWorkspaceIDs = Set(defaults.stringArray(forKey: DefaultsKey.pinnedWorkspaceIDs) ?? [])
        self.selectedSearchScope = SearchScope(
            rawValue: defaults.string(forKey: DefaultsKey.selectedSearchScope) ?? ""
        ) ?? .all
        self.selectedWorkspaceID = workspaces.first?.id
    }

    var selectedWorkspace: WorkspaceSummary? {
        workspaces.first { $0.id == selectedWorkspaceID } ?? filteredWorkspaces.first
    }

    var pinnedWorkspaces: [WorkspaceSummary] {
        workspaces.filter { pinnedWorkspaceIDs.contains($0.id) }
    }

    var scopedSearchResults: [SearchResult] {
        searchResults.filter { selectedSearchScope.matches($0) }
    }

    var groupedSearchResults: [SearchResultGroup] {
        groupSearchResults(scopedSearchResults)
    }

    var orderedSearchResults: [SearchResult] {
        groupedSearchResults.flatMap(\.results)
    }

    var selectedSearchResult: SearchResult? {
        let results = orderedSearchResults
        guard !results.isEmpty else { return nil }
        return results[min(selectedSearchResultIndex, results.count - 1)]
    }

    var hasSearchQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var applicationSupportRootPath: String {
        guard let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first else {
            return "~/Library/Application Support/com.ks.nexus"
        }
        return applicationSupport
            .appendingPathComponent("com.ks.nexus")
            .path
    }

    private var auditRootPath: String {
        "\(applicationSupportRootPath)/audit"
    }

    private var searchIndexPath: String {
        "\(applicationSupportRootPath)/nexus-index.sqlite3"
    }

    var filteredWorkspaces: [WorkspaceSummary] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        let matchingWorkspaces = workspaces.enumerated().filter { item in
            let workspace = item.element
            let matchesFilter: Bool
            switch selectedFilter {
            case .all:
                matchesFilter = true
            case .active:
                matchesFilter = workspace.state == .developing || workspace.state == .analyzing
            case .risky:
                matchesFilter = workspace.riskLevel == .high || workspace.riskLevel == .medium
            case .blocked:
                matchesFilter = workspace.state == .blocked
            }

            guard matchesFilter else { return false }
            guard !trimmedQuery.isEmpty else { return true }

            let haystack = [
                workspace.name,
                workspace.folder,
                workspace.branch,
                workspace.aiState,
                workspace.serviceSummary,
                workspace.worktreeState
            ]
            .joined(separator: " ")
            .lowercased()

            return haystack.contains(trimmedQuery)
        }
        .sorted { lhs, rhs in
            let lhsPinned = pinnedWorkspaceIDs.contains(lhs.element.id)
            let rhsPinned = pinnedWorkspaceIDs.contains(rhs.element.id)
            if lhsPinned != rhsPinned {
                return lhsPinned
            }
            return lhs.offset < rhs.offset
        }
        .map(\.element)

        return matchingWorkspaces
    }

    func select(_ workspace: WorkspaceSummary) {
        selectedWorkspaceID = workspace.id
    }

    func isPinned(_ workspace: WorkspaceSummary) -> Bool {
        pinnedWorkspaceIDs.contains(workspace.id)
    }

    func togglePinned(_ workspace: WorkspaceSummary) {
        var updatedPinnedIDs = pinnedWorkspaceIDs
        if updatedPinnedIDs.contains(workspace.id) {
            updatedPinnedIDs.remove(workspace.id)
        } else {
            updatedPinnedIDs.insert(workspace.id)
        }
        pinnedWorkspaceIDs = updatedPinnedIDs
        persistPinnedWorkspaces()
    }

    func setSearchScope(_ scope: SearchScope) {
        selectedSearchScope = scope
        selectedSearchResultIndex = 0
        defaults.set(scope.rawValue, forKey: DefaultsKey.selectedSearchScope)
    }

    func workspace(for result: SearchResult) -> WorkspaceSummary? {
        workspaces.first { $0.folder == result.workspaceFolder }
    }

    func refreshFromBridge() async {
        isLoading = true
        lastError = nil
        defer {
            isLoading = false
        }

        do {
            let dashboard = try await bridge.scanWorkspaces(
                request: ScanWorkspacesRequest(
                    workspacesRoot: workspaceRoot,
                    sourceReposRoot: sourceReposRoot,
                    docsRoot: docsRoot
                )
            )
            let mappedWorkspaces = dashboard.workspaces.map(WorkspaceSummary.init(snapshot:))
            workspaces = mappedWorkspaces
            if selectedWorkspaceID == nil || !mappedWorkspaces.contains(where: { $0.id == selectedWorkspaceID }) {
                selectedWorkspaceID = mappedWorkspaces.first?.id
            }
            widgetSnapshot = try? await bridge.widgetSnapshot(
                request: WidgetSnapshotRequest(
                    workspacesRoot: workspaceRoot,
                    sourceReposRoot: sourceReposRoot,
                    docsRoot: docsRoot,
                    activeFolder: selectedWorkspaceID ?? "",
                    generatedAt: ISO8601DateFormatter().string(from: Date())
                )
            )
            await rebuildSearchIndex(reportErrors: false)
            bridgeMode = bridge.modeDescription
            agentStatus = AgentStatus(
                title: "Ready",
                detail: "\(bridgeMode) · \(mappedWorkspaces.count) workspaces loaded",
                connectedTools: ["Codex", "Git", "Nexus Core"]
            )
        } catch {
            lastError = error.localizedDescription
            agentStatus = AgentStatus(
                title: "Bridge error",
                detail: error.localizedDescription,
                connectedTools: ["Nexus Core"]
            )
        }
    }

    func rebuildSearchIndex(reportErrors: Bool = true) async {
        do {
            searchIndexSummary = try await bridge.rebuildSearchIndex(
                request: RebuildSearchIndexRequest(
                    indexPath: searchIndexPath,
                    workspacesRoot: workspaceRoot,
                    sourceReposRoot: sourceReposRoot,
                    docsRoot: docsRoot
                )
            )
            searchError = nil
            if hasSearchQuery {
                await searchForCurrentQuery()
            }
        } catch {
            searchIndexSummary = nil
            searchError = error.localizedDescription
            if reportErrors {
                lastError = error.localizedDescription
            }
        }
    }

    func searchForCurrentQuery() async {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            searchResults = []
            selectedSearchResultIndex = 0
            searchError = nil
            return
        }

        isSearching = true
        defer {
            isSearching = false
        }

        do {
            let indexedResults = try await bridge.searchIndex(
                request: SearchIndexRequest(indexPath: searchIndexPath, query: trimmedQuery, limit: 30)
            )
            searchResults = indexedResults.isEmpty ? fallbackSearchResults(matching: trimmedQuery) : indexedResults
            selectedSearchResultIndex = 0
            searchError = nil
        } catch {
            searchResults = fallbackSearchResults(matching: trimmedQuery)
            selectedSearchResultIndex = 0
            searchError = error.localizedDescription
        }
    }

    func moveSearchSelection(_ direction: Int) {
        let results = orderedSearchResults
        guard !results.isEmpty else { return }
        selectedSearchResultIndex = (selectedSearchResultIndex + direction + results.count) % results.count
    }

    func clearSearch() {
        query = ""
        searchResults = []
        selectedSearchResultIndex = 0
        searchError = nil
    }

    func openSelectedSearchResult() {
        let results = orderedSearchResults
        guard !results.isEmpty else { return }
        let index = min(selectedSearchResultIndex, results.count - 1)
        openSearchResult(results[index])
    }

    func openSearchResult(_ result: SearchResult) {
        selectedWorkspaceID = result.workspaceFolder
        let shouldOpenDocument = result.kind != "workspace"
        clearSearch()

        guard shouldOpenDocument else { return }
        Task {
            await loadDocument(path: result.documentPath)
        }
    }

    func loadHandoffForSelectedWorkspace() async {
        guard let workspace = selectedWorkspace else {
            return
        }

        let path = workspace.documentLinks["handoff"] ?? "\(workspace.path)/handoff.md"
        await loadDocument(path: path)
    }

    func loadDocument(path: String) async {
        isDocumentLoading = true
        lastError = nil
        defer {
            isDocumentLoading = false
        }

        do {
            documentPreview = try await bridge.readDocument(request: ReadDocumentRequest(path: path))
        } catch {
            lastError = error.localizedDescription
        }
    }

    func createWorkspace(draft: CreateWorkspaceDraft) async {
        isCreatingWorkspace = true
        lastError = nil
        defer {
            isCreatingWorkspace = false
        }

        do {
            let response = try await bridge.createWorkspace(
                request: CreateWorkspaceRequest(
                    name: draft.name,
                    folder: draft.folder,
                    workspacesRoot: workspaceRoot,
                    sourceReposRoot: sourceReposRoot,
                    services: draft.services,
                    targetBranch: draft.targetBranch,
                    confirmed: draft.confirmed,
                    auditRoot: auditRootPath,
                    actor: "Nexus Native"
                )
            )
            lastCreatedWorkspace = response
            selectedWorkspaceID = response.folder
            await refreshFromBridge()
        } catch {
            lastError = error.localizedDescription
        }
    }

    static func preview() -> AppState {
        AppState(
            workspaces: WorkspaceSummary.previewData,
            agentStatus: AgentStatus(
                title: "Ready",
                detail: "Markdown, Git, and Workspace Core online",
                connectedTools: ["Codex", "Git", "Nexus Core"]
            ),
            bridge: NexusBridgeFactory.makeDefault()
        )
    }

    private func fallbackSearchResults(matching query: String) -> [SearchResult] {
        let normalizedQuery = query.lowercased()
        guard !normalizedQuery.isEmpty else { return [] }

        return workspaces.compactMap { workspace in
            let haystack = [
                workspace.name,
                workspace.folder,
                workspace.branch,
                workspace.aiState,
                workspace.serviceSummary,
                workspace.worktreeState,
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
        .prefix(10)
        .map { $0 }
    }

    private func persistPinnedWorkspaces() {
        let orderedPinnedIDs = workspaces
            .map(\.id)
            .filter { pinnedWorkspaceIDs.contains($0) }
        let orphanedPinnedIDs = pinnedWorkspaceIDs
            .filter { pinnedID in !orderedPinnedIDs.contains(pinnedID) }
            .sorted()

        defaults.set(orderedPinnedIDs + orphanedPinnedIDs, forKey: DefaultsKey.pinnedWorkspaceIDs)
    }
}

struct CreateWorkspaceDraft: Equatable {
    var name: String
    var folder: String
    var services: [String]
    var targetBranch: String
    var confirmed: Bool
}
