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
    @Published var isSettingUpWorktrees = false
    @Published var lastError: String?
    @Published var bridgeMode: String
    @Published var documentPreview: DocumentSnapshot?
    @Published var widgetSnapshot: WidgetSnapshot?
    @Published var agentEvents: [AgentEvent] = []
    @Published var selectedAgentEvent: AgentEvent?
    @Published var lastCreatedWorkspace: CreateWorkspaceResponse?
    @Published var pendingWorktreeSetupWorkspace: WorkspaceSummary?
    @Published var lastWorktreeSetupResponse: SetupWorktreesResponse?
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
        static let workspaceRoot = "nexus.native.workspaceRoot"
        static let sourceReposRoot = "nexus.native.sourceReposRoot"
        static let docsRoot = "nexus.native.docsRoot"
    }

    static let defaultWorkspaceRoot = "~/ks_project/workspaces"
    static let defaultSourceReposRoot = "~/ks_project/source-repos"
    static let defaultDocsRoot = "~/ks_project/docs"

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
        self.workspaceRoot = Self.storedPath(
            defaults: defaults,
            key: DefaultsKey.workspaceRoot,
            fallback: workspaceRoot
        )
        self.sourceReposRoot = Self.storedPath(
            defaults: defaults,
            key: DefaultsKey.sourceReposRoot,
            fallback: sourceReposRoot
        )
        self.docsRoot = Self.storedPath(
            defaults: defaults,
            key: DefaultsKey.docsRoot,
            fallback: docsRoot
        )
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

    var taskCenterItems: [TaskCenterItem] {
        workspaces
            .flatMap { workspace in
                workspace.tasks.map { task in
                    TaskCenterItem(
                        workspaceID: workspace.id,
                        workspaceName: workspace.name,
                        workspaceFolder: workspace.folder,
                        task: task
                    )
                }
            }
            .filter { !$0.task.isDone }
            .sorted { lhs, rhs in
                if lhs.task.priorityRank != rhs.task.priorityRank {
                    return lhs.task.priorityRank < rhs.task.priorityRank
                }
                if lhs.workspaceName != rhs.workspaceName {
                    return lhs.workspaceName < rhs.workspaceName
                }
                return lhs.task.title < rhs.task.title
            }
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

    private var agentEventsRootPath: String {
        "\(applicationSupportRootPath)/agent-events"
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
                workspace.worktreeState,
                workspace.tasks.map(\.title).joined(separator: " "),
                workspace.tasks.map(\.detail).joined(separator: " ")
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

    func selectTaskCenterItem(_ item: TaskCenterItem) {
        selectedWorkspaceID = item.workspaceID
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

    func persistLocalPaths() {
        defaults.set(
            workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DefaultsKey.workspaceRoot
        )
        defaults.set(
            sourceReposRoot.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DefaultsKey.sourceReposRoot
        )
        defaults.set(
            docsRoot.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DefaultsKey.docsRoot
        )
    }

    func resetLocalPaths() {
        workspaceRoot = Self.defaultWorkspaceRoot
        sourceReposRoot = Self.defaultSourceReposRoot
        docsRoot = Self.defaultDocsRoot
        persistLocalPaths()
    }

    func reloadConfiguredPaths() async {
        persistLocalPaths()
        clearSearch()
        selectedWorkspaceID = nil
        documentPreview = nil
        await refreshFromBridge()
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
                    docsRoot: docsRoot,
                    auditRoot: auditRootPath
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
            agentEvents = (try? await bridge.readAgentEvents(
                request: ReadAgentEventsRequest(eventsRoot: agentEventsRootPath, limit: 8)
            )) ?? []
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
            let document = try await bridge.readDocument(request: ReadDocumentRequest(path: path))
            documentPreview = document
            await recordWorkspaceAction(
                action: "document.opened",
                target: path,
                summary: "Opened \(document.name)",
                metadata: ["documentPath": path, "documentName": document.name]
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func agentEventHandoffPrompt(for event: AgentEvent) async -> String {
        do {
            let response = try await bridge.agentEventHandoffPrompt(
                request: AgentEventHandoffPromptRequest(event: event)
            )
            return response.prompt
        } catch {
            return event.fallbackHandoffPrompt
        }
    }

    func agentEventTaskDraft(for event: AgentEvent) async -> AgentEventTaskDraftResponse {
        do {
            return try await bridge.agentEventTaskDraft(
                request: AgentEventTaskDraftRequest(event: event)
            )
        } catch {
            return event.fallbackTaskDraft
        }
    }

    func appendAgentTaskDraft(
        _ draft: AgentEventTaskDraftResponse,
        to workspace: WorkspaceSummary,
        confirmed: Bool
    ) async -> AppendAgentTaskDraftResponse? {
        lastError = nil
        do {
            let response = try await bridge.appendAgentTaskDraft(
                request: AppendAgentTaskDraftRequest(
                    workspacePath: workspace.path,
                    draft: draft,
                    confirmed: confirmed,
                    auditRoot: auditRootPath,
                    actor: "Nexus Native"
                )
            )
            if response.appended {
                await refreshFromBridge()
            }
            return response
        } catch {
            lastError = error.localizedDescription
            return nil
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

    func presentWorktreeSetup(for workspace: WorkspaceSummary) {
        lastError = nil
        lastWorktreeSetupResponse = nil
        pendingWorktreeSetupWorkspace = workspace
    }

    func missingWorktreeServices(in workspace: WorkspaceSummary) -> [String] {
        workspace.services
            .filter { !$0.worktreeExists }
            .map(\.name)
    }

    func canSetupWorktrees(in workspace: WorkspaceSummary) -> Bool {
        !missingWorktreeServices(in: workspace).isEmpty && Self.hasConfirmedTargetBranch(workspace.branch)
    }

    func setupMissingWorktrees(for workspace: WorkspaceSummary, confirmed: Bool) async {
        lastError = nil
        lastWorktreeSetupResponse = nil

        let missingServices = missingWorktreeServices(in: workspace)
        guard !missingServices.isEmpty else {
            lastError = "当前工作区没有缺失的 worktree。"
            return
        }

        guard Self.hasConfirmedTargetBranch(workspace.branch) else {
            lastError = "目标分支仍未确认，不能创建 worktree。"
            return
        }

        isSettingUpWorktrees = true
        defer {
            isSettingUpWorktrees = false
        }

        do {
            let response = try await bridge.setupWorktrees(
                request: SetupWorktreesRequest(
                    workspacePath: workspace.path,
                    sourceReposRoot: sourceReposRoot,
                    services: missingServices,
                    targetBranch: workspace.branch,
                    confirmed: confirmed,
                    auditRoot: auditRootPath,
                    actor: "Nexus Native"
                )
            )
            lastWorktreeSetupResponse = response
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

    private func recordWorkspaceAction(
        action: String,
        target: String,
        summary: String,
        metadata: [String: String] = [:]
    ) async {
        guard let workspace = selectedWorkspace else { return }
        let activity = ActivityEvent(
            time: Self.activityTimestamp(),
            title: Self.auditActivityTitle(action),
            detail: "Nexus Native · \(summary)"
        )
        if let index = workspaces.firstIndex(where: { $0.id == workspace.id }) {
            workspaces[index] = workspaces[index].prepending(activity: activity)
        }

        var eventMetadata = metadata
        eventMetadata["folder"] = workspace.folder
        eventMetadata["workspaceFolder"] = workspace.folder
        eventMetadata["name"] = workspace.name
        eventMetadata["path"] = workspace.path

        _ = try? await bridge.appendAuditEvent(
            request: AppendAuditEventRequest(
                auditRoot: auditRootPath,
                event: AuditEventInput(
                    actor: "Nexus Native",
                    action: action,
                    target: target,
                    summary: summary,
                    metadata: eventMetadata
                )
            )
        )
    }

    private static func auditActivityTitle(_ action: String) -> String {
        switch action {
        case "document.opened":
            return "文档已打开 / Document opened"
        case "codex.opened":
            return "Codex 已打开 / Codex opened"
        case "codex_instruction.copied":
            return "Codex 指令已复制 / Instruction copied"
        default:
            return action.replacingOccurrences(of: "_", with: " ")
                .replacingOccurrences(of: ".", with: " ")
        }
    }

    private static func activityTimestamp() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd HH:mm"
        return formatter.string(from: Date())
    }

    private static func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalizedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedBranch.isEmpty else { return false }
        let pendingMarkers = ["待确认", "未确认", "pending", "tbd", "todo"]
        return !pendingMarkers.contains { normalizedBranch.contains($0) }
    }

    private static func storedPath(defaults: UserDefaults, key: String, fallback: String) -> String {
        let value = defaults.string(forKey: key)?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let value, !value.isEmpty else { return fallback }
        return value
    }
}

struct CreateWorkspaceDraft: Equatable {
    var name: String
    var folder: String
    var services: [String]
    var targetBranch: String
    var confirmed: Bool
}
