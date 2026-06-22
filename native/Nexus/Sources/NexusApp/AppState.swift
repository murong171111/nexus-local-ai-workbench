import AppKit
import Combine
import Foundation
import NexusBridge
import UserNotifications

private struct NativeSettingsProfile: Codable {
    let schemaVersion: Int
    let app: String
    let exportedAt: String
    let settings: NativeSettingsProfileSettings
    let notes: [String]
}

private struct NativeSettingsProfileSettings: Codable {
    let workspacesRoot: String
    let sourceReposRoot: String
    let docsRoot: String
    let codexUrl: String
    let ideUrl: String?
    let refreshIntervalSeconds: Int
}

private enum SettingsProfileError: LocalizedError {
    case invalid(String)

    var errorDescription: String? {
        switch self {
        case .invalid(let message):
            return message
        }
    }
}

struct DocumentLoadError: Equatable {
    let path: String
    let message: String
}

struct DocumentFocusHint: Equatable {
    let path: String
    let line: Int?
    let title: String
    let detail: String

    var lineLabel: String {
        line.map { "L\($0)" } ?? "Line unknown"
    }
}

struct NativeEnvironmentPathCheck: Identifiable, Hashable {
    let key: String
    let label: String
    let path: String
    let exists: Bool
    let isDirectory: Bool
    let writable: Bool
    let summary: String

    var id: String { key }

    var status: String {
        if !exists || !isDirectory {
            return "blocker"
        }
        if !writable {
            return "warning"
        }
        return "pass"
    }
}

struct NativeEnvironmentToolCheck: Identifiable, Hashable {
    let key: String
    let label: String
    let available: Bool
    let summary: String

    var id: String { key }
    var status: String { available ? "pass" : "blocker" }
}

struct NativeEnvironmentHealth: Hashable {
    let generatedAt: String
    let ready: Bool
    let pathChecks: [NativeEnvironmentPathCheck]
    let toolChecks: [NativeEnvironmentToolCheck]
    let workspaceCount: Int
    let sourceRepoCount: Int
    let blockers: [String]
    let warnings: [String]
}

enum NativeSetupReadinessStatus: String, Hashable {
    case unchecked
    case ready
    case needsReview

    var environmentStatus: String {
        switch self {
        case .ready:
            "pass"
        case .needsReview:
            "blocker"
        case .unchecked:
            "warning"
        }
    }
}

struct NativeSetupReadiness: Hashable {
    let status: NativeSetupReadinessStatus
    let title: String
    let detail: String
    let primaryActionLabel: String
    let secondaryActionLabel: String

    init(health: NativeEnvironmentHealth?, workspaceCount: Int, profileImported: Bool) {
        guard let health else {
            status = .unchecked
            title = "待检查 / Setup check"
            detail = profileImported
                ? "已导入 Profile，运行环境检查后即可确认是否需要调整路径。"
                : "首次使用前先确认路径和 Git；已有有效配置时不会强制初始化。"
            primaryActionLabel = "环境检查"
            secondaryActionLabel = "Settings"
            return
        }

        if health.ready {
            status = .ready
            title = "环境可用 / Ready"
            detail = workspaceCount > 0
                ? "路径和 Git 已通过检查，不需要初始化；可以直接进入现有工作区。"
                : "路径和 Git 已通过检查，不需要初始化；可以直接新建第一个工作区。"
            primaryActionLabel = workspaceCount > 0 ? "刷新" : "新建"
            secondaryActionLabel = "Settings"
            return
        }

        status = .needsReview
        title = "需要配置 / Needs setup"
        detail = "\(health.blockers.count) blockers · \(health.warnings.count) warnings。先在 Settings 调整路径，再重新运行环境检查。"
        primaryActionLabel = "环境检查"
        secondaryActionLabel = "Settings"
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published var query = ""
    @Published var selectedFilter: WorkspaceFilter = .all
    @Published var selectedWorkspaceID: WorkspaceSummary.ID?
    @Published var workspaces: [WorkspaceSummary]
    @Published var pinnedWorkspaceIDs: Set<WorkspaceSummary.ID>
    @Published var selectedSearchScope: SearchScope
    @Published var selectedTaskCenterFilter: TaskCenterFilter
    @Published var focusedTaskCenterItemID: TaskCenterItem.ID?
    @Published var workspaceRoot: String
    @Published var sourceReposRoot: String
    @Published var docsRoot: String
    @Published var codexURL: String
    @Published var ideURL: String
    @Published var refreshIntervalSeconds: Int
    @Published var isLoading = false
    @Published var isDocumentLoading = false
    @Published var isCreatingWorkspace = false
    @Published var isSettingUpWorktrees = false
    @Published var isCreatingDocument = false
    @Published var isInitializingDemandIntake = false
    @Published var demandIntakeLoadingWorkspaceID: WorkspaceSummary.ID?
    @Published var demandIntakeStatusesByWorkspace: [WorkspaceSummary.ID: DemandIntakeStatus] = [:]
    @Published var isUpdatingTask = false
    @Published var isUpdatingDeliveryRecord = false
    @Published var isUpdatingLifecycle = false
    @Published var lastError: String?
    @Published var bridgeMode: String
    @Published var documentPreview: DocumentSnapshot?
    @Published var documentLoadingPath: String?
    @Published var documentLoadError: DocumentLoadError?
    @Published var documentFocusHint: DocumentFocusHint?
    @Published var widgetSnapshot: WidgetSnapshot?
    @Published var widgetSnapshotStorageStatus = "Not written"
    @Published var widgetSnapshotStoragePaths: [String] = []
    @Published var settingsProfileStatus = "No profile imported or exported"
    @Published var lastSettingsProfilePath: String?
    @Published var agentEvents: [AgentEvent] = []
    @Published var selectedAgentEvent: AgentEvent?
    @Published var pendingTaskStatusUpdate: TaskStatusUpdate?
    @Published var pendingScopeFreezeWrite: ScopeFreezeWritePlan?
    @Published var pendingDemandTaskTransfer: DemandTaskTransferPlan?
    @Published var pendingDeliveryRecordWrite: DeliveryRecordWritePlan?
    @Published var pendingArchiveChecklistWrite: ArchiveChecklistWritePlan?
    @Published var pendingValidationPrWrite: ValidationPrWritePlan?
    @Published var pendingLifecycleStatusUpdate: LifecycleStatusUpdate?
    @Published var lastCreatedWorkspace: CreateWorkspaceResponse?
    @Published var pendingWorktreeSetupWorkspace: WorkspaceSummary?
    @Published var lastWorktreeSetupResponse: SetupWorktreesResponse?
    @Published var codexHandoffFeedback: CodexHandoffFeedback?
    @Published var lastCopiedCodexHandoffPayload: String?
    @Published var localWriteFeedback: LocalWriteFeedback?
    @Published var workspaceLinkFeedback: WorkspaceLinkFeedback?
    @Published var codexSessionLinksByWorkspace: [WorkspaceSummary.ID: [CodexSessionLink]] = [:]
    @Published var searchResults: [SearchResult] = []
    @Published var selectedSearchResultIndex = 0
    @Published var isSearching = false
    @Published var searchIndexSummary: RebuildSearchIndexResponse?
    @Published var searchError: String?
    @Published var sourceRepositories: [SourceRepositorySnapshot] = []
    @Published var isScanningSourceRepositories = false
    @Published var sourceRepositoryScanError: String?
    @Published var nativeEnvironmentHealth: NativeEnvironmentHealth?
    @Published var isCheckingNativeEnvironment = false
    @Published var isRunningAutomationCheck = false
    @Published var lastAutomationCheck: LocalAutomationCheckResponse?
    @Published var lastAutomationCheckActor: String?
    @Published var isAutomationScheduleEnabled: Bool
    @Published var automationIntervalMinutes: Int
    @Published var lastAutomationRunAt: String?
    @Published var areAutomationNotificationsEnabled: Bool
    @Published var automationNotificationStatus: String
    @Published var automationNotificationMinimumStatus: AutomationNotificationMinimumStatus
    @Published var automationNotificationCooldownMinutes: Int
    @Published var automationNotificationSignalKinds: Set<String>
    @Published var lastAutomationNotificationAt: String?

    @Published var agentStatus: AgentStatus
    private let bridge: NexusBridge
    private let defaults: UserDefaults

    private enum DefaultsKey {
        static let pinnedWorkspaceIDs = "nexus.native.pinnedWorkspaceIDs"
        static let selectedWorkspaceFilter = "nexus.native.selectedWorkspaceFilter"
        static let selectedSearchScope = "nexus.native.selectedSearchScope"
        static let selectedTaskCenterFilter = "nexus.native.selectedTaskCenterFilter"
        static let workspaceRoot = "nexus.native.workspaceRoot"
        static let sourceReposRoot = "nexus.native.sourceReposRoot"
        static let docsRoot = "nexus.native.docsRoot"
        static let codexURL = "nexus.native.codexURL"
        static let ideURL = "nexus.native.ideURL"
        static let refreshIntervalSeconds = "nexus.native.refreshIntervalSeconds"
        static let isAutomationScheduleEnabled = "nexus.native.isAutomationScheduleEnabled"
        static let automationIntervalMinutes = "nexus.native.automationIntervalMinutes"
        static let lastAutomationRunAt = "nexus.native.lastAutomationRunAt"
        static let areAutomationNotificationsEnabled = "nexus.native.areAutomationNotificationsEnabled"
        static let automationNotificationMinimumStatus = "nexus.native.automationNotificationMinimumStatus"
        static let automationNotificationCooldownMinutes = "nexus.native.automationNotificationCooldownMinutes"
        static let automationNotificationSignalKinds = "nexus.native.automationNotificationSignalKinds"
        static let lastAutomationNotificationAt = "nexus.native.lastAutomationNotificationAt"
    }

    static let defaultWorkspaceRoot = "~/ks_project/workspaces"
    static let defaultSourceReposRoot = "~/ks_project/source-repos"
    static let defaultDocsRoot = "~/ks_project/docs"
    static let defaultCodexURL = "codex://"
    static let defaultIDEURL = "idea://open?file={path}"
    static let defaultRefreshIntervalSeconds = 10
    static let widgetAppGroupIdentifier = "group.com.ks.nexus"
    static let widgetSnapshotFileName = "widget-snapshot.json"
    static let supportedAutomationIntervals = [5, 15, 30, 60]
    static let defaultAutomationIntervalMinutes = 30
    static let supportedNotificationCooldownMinutes = [15, 30, 60, 180]
    static let defaultNotificationCooldownMinutes = 60

    init(
        workspaces: [WorkspaceSummary],
        agentStatus: AgentStatus,
        bridge: NexusBridge,
        workspaceRoot: String = "~/ks_project/workspaces",
        sourceReposRoot: String = "~/ks_project/source-repos",
        docsRoot: String = "~/ks_project/docs",
        codexURL: String = "codex://",
        ideURL: String = "idea://open?file={path}",
        refreshIntervalSeconds: Int = 10,
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
        self.codexURL = Self.storedPath(
            defaults: defaults,
            key: DefaultsKey.codexURL,
            fallback: codexURL
        )
        self.ideURL = Self.storedPath(
            defaults: defaults,
            key: DefaultsKey.ideURL,
            fallback: ideURL
        )
        self.refreshIntervalSeconds = Self.normalizedRefreshInterval(
            defaults.object(forKey: DefaultsKey.refreshIntervalSeconds) == nil
                ? refreshIntervalSeconds
                : defaults.integer(forKey: DefaultsKey.refreshIntervalSeconds)
        )
        self.bridgeMode = bridge.modeDescription.isEmpty ? bridgeMode : bridge.modeDescription
        self.pinnedWorkspaceIDs = Set(defaults.stringArray(forKey: DefaultsKey.pinnedWorkspaceIDs) ?? [])
        self.selectedFilter = WorkspaceFilter(
            rawValue: defaults.string(forKey: DefaultsKey.selectedWorkspaceFilter) ?? ""
        ) ?? .all
        self.selectedSearchScope = SearchScope(
            rawValue: defaults.string(forKey: DefaultsKey.selectedSearchScope) ?? ""
        ) ?? .all
        self.selectedTaskCenterFilter = TaskCenterFilter(
            rawValue: defaults.string(forKey: DefaultsKey.selectedTaskCenterFilter) ?? ""
        ) ?? .all
        self.isAutomationScheduleEnabled = defaults.object(
            forKey: DefaultsKey.isAutomationScheduleEnabled
        ) == nil ? false : defaults.bool(forKey: DefaultsKey.isAutomationScheduleEnabled)
        self.automationIntervalMinutes = Self.normalizedAutomationInterval(
            defaults.integer(forKey: DefaultsKey.automationIntervalMinutes)
        )
        self.lastAutomationRunAt = defaults.string(forKey: DefaultsKey.lastAutomationRunAt)
        let storedNotificationsEnabled = defaults.bool(
            forKey: DefaultsKey.areAutomationNotificationsEnabled
        )
        self.areAutomationNotificationsEnabled = storedNotificationsEnabled
        self.automationNotificationStatus = storedNotificationsEnabled
            ? "Checking authorization"
            : "Disabled"
        self.automationNotificationMinimumStatus = AutomationNotificationMinimumStatus(
            rawValue: defaults.string(forKey: DefaultsKey.automationNotificationMinimumStatus) ?? ""
        ) ?? .review
        self.automationNotificationCooldownMinutes = Self.normalizedNotificationCooldown(
            defaults.integer(forKey: DefaultsKey.automationNotificationCooldownMinutes)
        )
        let storedSignalKinds = defaults.stringArray(
            forKey: DefaultsKey.automationNotificationSignalKinds
        ) ?? Self.defaultAutomationNotificationSignalKinds
        self.automationNotificationSignalKinds = Set(storedSignalKinds)
        self.lastAutomationNotificationAt = defaults.string(forKey: DefaultsKey.lastAutomationNotificationAt)
        self.selectedWorkspaceID = workspaces.first?.id
    }

    var selectedWorkspace: WorkspaceSummary? {
        workspaces.first { $0.id == selectedWorkspaceID } ?? filteredWorkspaces.first
    }

    var agentInboxSummary: AgentInboxSummary {
        AgentInboxSummary(events: agentEvents)
    }

    var agentWorkflowSummary: AgentWorkflowSummary {
        AgentWorkflowSummary(
            inbox: agentInboxSummary,
            agentTaskCount: activeAgentTaskCenterCount,
            openTaskCount: activeTaskCenterCount
        )
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

    var allTaskCenterItems: [TaskCenterItem] {
        activeSignalWorkspaces
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

    var taskCenterItems: [TaskCenterItem] {
        allTaskCenterItems.filter { selectedTaskCenterFilter.matches($0) }
    }

    var taskCenterTotalCount: Int {
        allTaskCenterItems.count
    }

    var actionableAutomationSignals: [LocalAutomationSignal] {
        guard let lastAutomationCheck else { return [] }
        return lastAutomationCheck.signals.filter { signal in
            signal.action != "none" && signal.kind != "refresh"
        }
    }

    var menuBarSummary: MenuBarStatusSummary {
        let summary = WorkspaceListSummary(workspaces: workspaces)

        return MenuBarStatusSummary(
            workspaceCount: summary.totalWorkspaceCount,
            activeWorkspaceCount: summary.activeWorkspaceCount,
            archivedWorkspaceCount: summary.archivedWorkspaceCount,
            riskyWorkspaceCount: summary.riskyWorkspaceCount,
            blockedWorkspaceCount: summary.blockedWorkspaceCount,
            openTaskCount: summary.openTaskCount,
            highPriorityTaskCount: summary.highPriorityTaskCount,
            agentTaskCount: activeAgentTaskCenterCount,
            missingWorktreeCount: summary.missingWorktreeCount,
            dirtyServiceCount: summary.dirtyServiceCount,
            activeWorkspaceName: selectedWorkspace?.name,
            activeStageLine: selectedWorkspace.map(Self.menuBarStageLine),
            bridgeMode: bridgeMode
        )
    }

    private static func menuBarStageLine(for workspace: WorkspaceSummary) -> String {
        let answer = workspace.mainStage().answer
        return "\(answer.stageLabel) · \(answer.blockerSummary) · 下一步: \(answer.nextActionLabel) · 证据: \(answer.primaryEvidenceLink?.label ?? "未路由")"
    }

    func taskCenterCount(for filter: TaskCenterFilter) -> Int {
        allTaskCenterItems.filter { filter.matches($0) }.count
    }

    private var activeTaskCenterCount: Int {
        allTaskCenterItems.filter { $0.task.isActive }.count
    }

    private var activeAgentTaskCenterCount: Int {
        allTaskCenterItems.filter { $0.task.isActive && TaskCenterFilter.agent.matches($0) }.count
    }

    var hasSearchQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasWorkspaceListScope: Bool {
        selectedFilter != .all || hasSearchQuery
    }

    var automationScheduleToken: String {
        "\(isAutomationScheduleEnabled)-\(automationIntervalMinutes)"
    }

    var setupReadiness: NativeSetupReadiness {
        NativeSetupReadiness(
            health: nativeEnvironmentHealth,
            workspaceCount: workspaces.count,
            profileImported: lastSettingsProfilePath != nil
        )
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

    private func refreshWidgetSnapshot() async {
        let nextWidgetSnapshot = try? await bridge.widgetSnapshot(
            request: WidgetSnapshotRequest(
                workspacesRoot: workspaceRoot,
                sourceReposRoot: sourceReposRoot,
                docsRoot: docsRoot,
                activeFolder: selectedWorkspaceID ?? "",
                generatedAt: ISO8601DateFormatter().string(from: Date())
            )
        )
        let enrichedWidgetSnapshot = nextWidgetSnapshot.map(enrichWidgetSnapshotWithMainStage)
        widgetSnapshot = enrichedWidgetSnapshot
        if let enrichedWidgetSnapshot {
            persistWidgetSnapshot(enrichedWidgetSnapshot)
        } else {
            widgetSnapshotStorageStatus = "Snapshot unavailable"
            widgetSnapshotStoragePaths = []
        }
    }

    private func enrichWidgetSnapshotWithMainStage(_ snapshot: WidgetSnapshot) -> WidgetSnapshot {
        guard let workspace = selectedWorkspace else {
            return snapshot
        }

        let answer = workspace.mainStage().answer
        return WidgetSnapshot(
            generatedAt: snapshot.generatedAt,
            workspacesRoot: snapshot.workspacesRoot,
            activeWorkspace: snapshot.activeWorkspace,
            activeWorkspaceFolder: snapshot.activeWorkspaceFolder,
            workspaceCount: snapshot.workspaceCount,
            riskCount: snapshot.riskCount,
            dirtyServiceCount: snapshot.dirtyServiceCount,
            missingWorktreeCount: snapshot.missingWorktreeCount,
            topRisks: snapshot.topRisks,
            mainStage: answer.stageLabel,
            mainStageStatus: answer.status.displayLabel,
            mainStageBlockerSummary: answer.blockerSummary,
            mainStageNextAction: answer.nextActionLabel,
            mainStageEvidence: answer.primaryEvidenceLink?.label,
            deepLink: snapshot.deepLink
        )
    }

    private func persistWidgetSnapshot(_ snapshot: WidgetSnapshot) {
        do {
            let writtenPaths = try NativeWidgetSnapshotStore.write(
                snapshot: snapshot,
                applicationSupportRoot: applicationSupportRootPath,
                appGroupURL: FileManager.default.containerURL(
                    forSecurityApplicationGroupIdentifier: Self.widgetAppGroupIdentifier
                ),
                fileName: Self.widgetSnapshotFileName
            )
            widgetSnapshotStoragePaths = writtenPaths
            widgetSnapshotStorageStatus = writtenPaths.count > 1
                ? "Application Support + App Group"
                : "Application Support"
        } catch {
            widgetSnapshotStoragePaths = []
            widgetSnapshotStorageStatus = "Write failed: \(error.localizedDescription)"
        }
    }

    var filteredWorkspaces: [WorkspaceSummary] {
        let matchingWorkspaces = workspaces.enumerated().filter { item in
            selectedFilter.matches(item.element, query: query)
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

    func workspaceCount(for filter: WorkspaceFilter) -> Int {
        workspaces.filter { filter.matches($0, query: query) }.count
    }

    func select(_ workspace: WorkspaceSummary) {
        if selectedWorkspaceID != workspace.id {
            documentPreview = nil
            documentFocusHint = nil
        }
        selectedWorkspaceID = workspace.id
        focusedTaskCenterItemID = nil
        Task {
            await refreshWidgetSnapshot()
        }
    }

    func selectTaskCenterItem(_ item: TaskCenterItem) {
        if selectedWorkspaceID != item.workspaceID {
            documentPreview = nil
            documentFocusHint = nil
        }
        selectedWorkspaceID = item.workspaceID
        focusedTaskCenterItemID = item.id
        Task {
            await refreshWidgetSnapshot()
        }
    }

    func focusWorkspace(id: WorkspaceSummary.ID) {
        if selectedWorkspaceID != id {
            documentPreview = nil
            documentFocusHint = nil
        }
        setWorkspaceFilter(.all)
        clearSearch()
        selectedWorkspaceID = id
        focusedTaskCenterItemID = nil
        Task {
            await refreshWidgetSnapshot()
        }
    }

    func handleDeepLink(_ url: URL) async {
        lastError = nil
        guard url.scheme?.lowercased() == "nexus" else {
            lastError = "Unsupported Nexus deep link: \(url.absoluteString)"
            return
        }

        guard let workspaceFolder = Self.workspaceFolder(fromDeepLink: url) else {
            lastError = "Unsupported Nexus deep link. Expected nexus://workspace/<workspace-folder>."
            return
        }

        if let workspace = workspaceForDeepLink(folder: workspaceFolder) {
            await focusWorkspaceFromDeepLink(workspace, url: url)
            return
        }

        await refreshFromBridge()
        if let workspace = workspaceForDeepLink(folder: workspaceFolder) {
            await focusWorkspaceFromDeepLink(workspace, url: url)
            return
        }

        lastError = "Workspace not found for deep link: \(workspaceFolder)"
    }

    private func workspaceForDeepLink(folder: String) -> WorkspaceSummary? {
        workspaces.first { workspace in
            workspace.folder == folder || workspace.id == folder
        }
    }

    private func focusWorkspaceFromDeepLink(_ workspace: WorkspaceSummary, url: URL) async {
        focusWorkspace(id: workspace.id)
        await recordWorkspaceAction(
            action: "workspace.deeplink.opened",
            target: url.absoluteString,
            summary: "Focused workspace from Nexus deep link",
            metadata: [
                "tool": "Nexus URL Scheme",
                "deepLink": url.absoluteString
            ],
            workspaceOverride: workspace
        )
    }

    func workspaceDeepLink(for workspace: WorkspaceSummary) -> String {
        let encodedFolder = workspace.folder.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)
            ?? workspace.folder
        return "nexus://workspace/\(encodedFolder)"
    }

    func copyWorkspaceDeepLink(_ workspace: WorkspaceSummary) async {
        lastError = nil
        let link = workspaceDeepLink(for: workspace)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link, forType: .string)
        markWorkspaceLinkFeedback(
            title: "工作区链接已复制 / Workspace link copied",
            detail: "\(workspace.name) · 可从小组件、脚本或其他工具回到这个工作区。",
            workspace: workspace,
            link: link,
            systemImage: "link"
        )
        await recordWorkspaceAction(
            action: "workspace.deeplink.copied",
            target: link,
            summary: "Copied workspace Nexus deep link",
            metadata: [
                "tool": "Nexus URL Scheme",
                "deepLink": link
            ],
            workspaceOverride: workspace
        )
    }

    func requestTaskStatusUpdate(_ item: TaskCenterItem, status: String) {
        guard let workspace = workspaces.first(where: { $0.id == item.workspaceID }) else {
            return
        }
        requestTaskStatusUpdate(item.task, in: workspace, status: status)
    }

    func requestTaskStatusUpdate(_ task: WorkspaceTask, in workspace: WorkspaceSummary, status: String) {
        pendingTaskStatusUpdate = TaskStatusUpdate(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            taskID: task.id,
            taskTitle: task.title,
            taskSourceLine: task.sourceLine,
            currentStatus: task.status,
            nextStatus: status,
            postWriteChecks: TaskStatusUpdate.postWriteChecks(
                for: task,
                workspace: workspace,
                nextStatus: status
            )
        )
    }

    func requestLifecycleStatusUpdate(_ transition: LifecycleTransition, in workspace: WorkspaceSummary) {
        pendingLifecycleStatusUpdate = LifecycleStatusUpdate(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            currentStage: workspace.lifecycle.stage,
            currentLabel: workspace.lifecycle.label,
            nextState: transition.state,
            nextLabel: transition.label,
            focus: transition.focus,
            nextAction: transition.nextAction,
            postWriteChecks: LifecycleStatusUpdate.postWriteChecks(
                for: transition,
                workspace: workspace
            )
        )
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

    func setWorkspaceFilter(_ filter: WorkspaceFilter) {
        selectedFilter = filter
        defaults.set(filter.rawValue, forKey: DefaultsKey.selectedWorkspaceFilter)
    }

    func resetWorkspaceListScope() {
        setWorkspaceFilter(.all)
        clearSearch()
    }

    func setSearchScope(_ scope: SearchScope) {
        selectedSearchScope = scope
        selectedSearchResultIndex = 0
        defaults.set(scope.rawValue, forKey: DefaultsKey.selectedSearchScope)
    }

    func setTaskCenterFilter(_ filter: TaskCenterFilter) {
        selectedTaskCenterFilter = filter
        if let focusedTaskCenterItemID,
           !taskCenterItems.contains(where: { $0.id == focusedTaskCenterItemID }) {
            self.focusedTaskCenterItemID = nil
        }
        defaults.set(filter.rawValue, forKey: DefaultsKey.selectedTaskCenterFilter)
    }

    func focusAgentTasks() {
        focusAgentTask(sourceEventID: nil)
    }

    func focusAgentTask(sourceEventID: String?) {
        setTaskCenterFilter(.agent)
        let agentItems = allTaskCenterItems.filter { TaskCenterFilter.agent.matches($0) }
        let matchedItem = sourceEventID.flatMap { sourceEventID in
            agentItems.first { $0.task.sourceEventID == sourceEventID }
        }
        if let item = matchedItem ?? agentItems.first {
            selectTaskCenterItem(item)
        }
    }

    func nextTaskCenterItem(after feedback: LocalWriteFeedback) -> TaskCenterItem? {
        nextTaskCenterItem(preferredWorkspaceID: feedback.workspaceID, excludingTaskID: nil)
    }

    func focusNextTask(after feedback: LocalWriteFeedback) {
        guard let item = nextTaskCenterItem(after: feedback) else {
            return
        }
        if !selectedTaskCenterFilter.matches(item) {
            setTaskCenterFilter(.all)
        }
        selectTaskCenterItem(item)
    }

    private func nextTaskCenterItem(
        preferredWorkspaceID: WorkspaceSummary.ID,
        excludingTaskID: WorkspaceTask.ID?
    ) -> TaskCenterItem? {
        let activeItems = allTaskCenterItems.filter { item in
            item.task.isActive && item.task.id != excludingTaskID
        }
        return activeItems.first { $0.workspaceID == preferredWorkspaceID } ?? activeItems.first
    }

    private func focusTransferredDemandTask(_ plan: DemandTaskTransferPlan) {
        let transferredTitles = Set(plan.transferableItems.map(\.normalizedTitle))
        guard let item = allTaskCenterItems.first(where: { item in
            item.workspaceID == plan.workspaceID
                && transferredTitles.contains(DemandTaskTransferItem.normalizeTitle(item.task.title))
        }) else {
            return
        }
        selectTaskCenterItem(item)
    }

    private func readOrCreateExecutionTasksDocument(at path: String) throws -> String {
        let fileURL = URL(fileURLWithPath: path)
        let parentURL = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentURL, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: path) {
            return try String(contentsOfFile: path, encoding: .utf8)
        }
        return "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n"
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
        defaults.set(
            codexURL.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DefaultsKey.codexURL
        )
        defaults.set(
            ideURL.trimmingCharacters(in: .whitespacesAndNewlines),
            forKey: DefaultsKey.ideURL
        )
        refreshIntervalSeconds = Self.normalizedRefreshInterval(refreshIntervalSeconds)
        defaults.set(refreshIntervalSeconds, forKey: DefaultsKey.refreshIntervalSeconds)
    }

    func resetLocalPaths() {
        workspaceRoot = Self.defaultWorkspaceRoot
        sourceReposRoot = Self.defaultSourceReposRoot
        docsRoot = Self.defaultDocsRoot
        codexURL = Self.defaultCodexURL
        ideURL = Self.defaultIDEURL
        refreshIntervalSeconds = Self.defaultRefreshIntervalSeconds
        persistLocalPaths()
    }

    func reloadConfiguredPaths() async {
        persistLocalPaths()
        clearSearch()
        selectedWorkspaceID = nil
        documentPreview = nil
        documentFocusHint = nil
        await checkNativeEnvironment()
        await refreshFromBridge()
    }

    func checkNativeEnvironment() async {
        isCheckingNativeEnvironment = true
        defer {
            isCheckingNativeEnvironment = false
        }

        nativeEnvironmentHealth = Self.buildNativeEnvironmentHealth(
            workspacesRoot: workspaceRoot,
            sourceReposRoot: sourceReposRoot,
            docsRoot: docsRoot
        )
    }

    func refreshSourceRepositories() async {
        guard !isScanningSourceRepositories else { return }
        isScanningSourceRepositories = true
        sourceRepositoryScanError = nil
        defer {
            isScanningSourceRepositories = false
        }

        do {
            sourceRepositories = try NativeSourceRepositoryStore.scan(sourceReposRoot: sourceReposRoot)
        } catch {
            do {
                sourceRepositories = try await bridge.scanSourceRepos(
                    request: ScanSourceReposRequest(sourceReposRoot: sourceReposRoot)
                )
            } catch {
                sourceRepositories = []
                sourceRepositoryScanError = error.localizedDescription
            }
        }
    }

    var settingsProfileDefaultFilename: String {
        let date = ISO8601DateFormatter().string(from: Date()).prefix(10)
        return "nexus-settings-profile-\(date).json"
    }

    func exportSettingsProfile(to url: URL) async {
        persistLocalPaths()
        let profile = NativeSettingsProfile(
            schemaVersion: 1,
            app: "Nexus",
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            settings: NativeSettingsProfileSettings(
                workspacesRoot: workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines),
                sourceReposRoot: sourceReposRoot.trimmingCharacters(in: .whitespacesAndNewlines),
                docsRoot: docsRoot.trimmingCharacters(in: .whitespacesAndNewlines),
                codexUrl: codexURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Self.defaultCodexURL
                    : codexURL.trimmingCharacters(in: .whitespacesAndNewlines),
                ideUrl: ideURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? Self.defaultIDEURL
                    : ideURL.trimmingCharacters(in: .whitespacesAndNewlines),
                refreshIntervalSeconds: Self.normalizedRefreshInterval(refreshIntervalSeconds)
            ),
            notes: [
                "This file stores local Nexus path and tool-link conventions for team sharing.",
                "Review paths after importing because every machine can use different local roots."
            ]
        )

        do {
            let payload = try Self.profileEncoder.encode(profile)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try payload.write(to: url, options: .atomic)
            settingsProfileStatus = "Exported \(url.lastPathComponent)"
            lastSettingsProfilePath = url.path
            await recordSettingsProfileAudit(
                action: "settings_profile.exported",
                target: url.path,
                summary: "Exported a shareable Nexus settings profile"
            )
        } catch {
            settingsProfileStatus = "Export failed: \(error.localizedDescription)"
            lastError = settingsProfileStatus
        }
    }

    func importSettingsProfile(from url: URL) async {
        do {
            let payload = try Data(contentsOf: url)
            let profile = try JSONDecoder().decode(NativeSettingsProfile.self, from: payload)
            let settings = try Self.validatedSettings(from: profile)

            workspaceRoot = settings.workspacesRoot
            sourceReposRoot = settings.sourceReposRoot
            docsRoot = settings.docsRoot
            codexURL = settings.codexUrl
            ideURL = settings.ideUrl ?? Self.defaultIDEURL
            refreshIntervalSeconds = settings.refreshIntervalSeconds
            persistLocalPaths()

            settingsProfileStatus = "Imported \(url.lastPathComponent)"
            lastSettingsProfilePath = url.path
            await recordSettingsProfileAudit(
                action: "settings_profile.imported",
                target: url.path,
                summary: "Imported a shared Nexus settings profile"
            )
            await reloadConfiguredPaths()
        } catch {
            settingsProfileStatus = "Import failed: \(error.localizedDescription)"
            lastError = settingsProfileStatus
        }
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
            let nativeAuditEvents = (try? NativeAuditEventStore.loadRecent(auditRoot: auditRootPath, limit: 40)) ?? []
            let enrichedWorkspaces = Self.workspaces(mappedWorkspaces, applyingNativeAuditEvents: nativeAuditEvents)
            workspaces = enrichedWorkspaces
            codexSessionLinksByWorkspace = Self.loadCodexSessionLinks(for: enrichedWorkspaces)
            if selectedWorkspaceID == nil || !enrichedWorkspaces.contains(where: { $0.id == selectedWorkspaceID }) {
                selectedWorkspaceID = enrichedWorkspaces.first?.id
            }
            await refreshWidgetSnapshot()
            agentEvents = (try? await bridge.readAgentEvents(
                request: ReadAgentEventsRequest(eventsRoot: agentEventsRootPath, limit: 8)
            )) ?? []
            await rebuildSearchIndex(reportErrors: false)
            bridgeMode = bridge.modeDescription
            agentStatus = AgentStatus(
                title: "Ready",
                detail: "\(bridgeMode) · \(enrichedWorkspaces.count) workspaces loaded",
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

    func setAutomationScheduleEnabled(_ enabled: Bool) {
        isAutomationScheduleEnabled = enabled
        defaults.set(enabled, forKey: DefaultsKey.isAutomationScheduleEnabled)
    }

    func setAutomationIntervalMinutes(_ minutes: Int) {
        automationIntervalMinutes = Self.normalizedAutomationInterval(minutes)
        defaults.set(automationIntervalMinutes, forKey: DefaultsKey.automationIntervalMinutes)
    }

    func setAutomationNotificationsEnabled(_ enabled: Bool) async {
        guard enabled else {
            areAutomationNotificationsEnabled = false
            automationNotificationStatus = "Disabled"
            defaults.set(false, forKey: DefaultsKey.areAutomationNotificationsEnabled)
            return
        }

        let authorization = await requestAutomationNotificationAuthorization()
        areAutomationNotificationsEnabled = authorization.granted
        automationNotificationStatus = authorization.status
        defaults.set(authorization.granted, forKey: DefaultsKey.areAutomationNotificationsEnabled)
    }

    func setAutomationNotificationMinimumStatus(_ status: AutomationNotificationMinimumStatus) {
        automationNotificationMinimumStatus = status
        defaults.set(status.rawValue, forKey: DefaultsKey.automationNotificationMinimumStatus)
    }

    func setAutomationNotificationCooldownMinutes(_ minutes: Int) {
        automationNotificationCooldownMinutes = Self.normalizedNotificationCooldown(minutes)
        defaults.set(
            automationNotificationCooldownMinutes,
            forKey: DefaultsKey.automationNotificationCooldownMinutes
        )
    }

    func isAutomationNotificationSignalEnabled(_ kind: AutomationNotificationSignalKind) -> Bool {
        automationNotificationSignalKinds.contains(kind.rawValue)
    }

    func setAutomationNotificationSignal(_ kind: AutomationNotificationSignalKind, enabled: Bool) {
        var updatedKinds = automationNotificationSignalKinds
        if enabled {
            updatedKinds.insert(kind.rawValue)
        } else {
            updatedKinds.remove(kind.rawValue)
        }
        automationNotificationSignalKinds = updatedKinds
        defaults.set(
            AutomationNotificationSignalKind.allCases
                .map(\.rawValue)
                .filter { updatedKinds.contains($0) },
            forKey: DefaultsKey.automationNotificationSignalKinds
        )
    }

    func refreshAutomationNotificationStatus() async {
        let settings = await notificationSettings()
        automationNotificationStatus = Self.notificationStatusLabel(settings.authorizationStatus)
        if settings.authorizationStatus == .denied || settings.authorizationStatus == .notDetermined {
            areAutomationNotificationsEnabled = false
            defaults.set(false, forKey: DefaultsKey.areAutomationNotificationsEnabled)
        }
    }

    func runAutomationScheduleLoop() async {
        guard isAutomationScheduleEnabled else { return }
        while !Task.isCancelled && isAutomationScheduleEnabled {
            let nanoseconds = UInt64(max(1, automationIntervalMinutes)) * 60 * 1_000_000_000
            do {
                try await Task.sleep(nanoseconds: nanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled && isAutomationScheduleEnabled else { return }
            await runLocalAutomationCheck(actor: "Nexus Scheduler")
        }
    }

    @discardableResult
    func runLocalAutomationCheck(actor: String = "Nexus Native") async -> LocalAutomationCheckResponse? {
        guard !isRunningAutomationCheck else { return nil }
        isRunningAutomationCheck = true
        lastError = nil
        defer {
            isRunningAutomationCheck = false
        }

        do {
            let generatedAt = ISO8601DateFormatter().string(from: Date())
            let response = try await bridge.localAutomationCheck(
                request: LocalAutomationCheckRequest(
                    workspacesRoot: workspaceRoot,
                    sourceReposRoot: sourceReposRoot,
                    docsRoot: docsRoot,
                    auditRoot: auditRootPath,
                    actor: actor,
                    generatedAt: generatedAt
                )
            )
            lastAutomationRunAt = generatedAt
            lastAutomationCheckActor = actor
            defaults.set(generatedAt, forKey: DefaultsKey.lastAutomationRunAt)
            lastAutomationCheck = response
            if let auditError = response.auditError {
                lastError = "Automation audit failed: \(auditError)"
            }
            await sendAutomationNotificationIfNeeded(response)
            await refreshFromBridge()
            lastAutomationCheck = response
            return response
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func runAutomationSignalAction(_ signal: LocalAutomationSignal) async {
        switch signal.action {
        case "review-risk":
            setWorkspaceFilter(.risky)
            if let workspace = workspaceForAutomationSignal(signal) {
                selectedWorkspaceID = workspace.id
                let prompt = riskReviewPrompt(for: workspace)
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(prompt, forType: .string)
                lastCopiedCodexHandoffPayload = prompt
                await recordRiskReviewHandoffCopied(for: workspace)
            }
        case "update-delivery":
            setWorkspaceFilter(.risky)
            let workspace = workspaceForAutomationSignal(signal) ?? selectedWorkspace
            if let workspace {
                selectedWorkspaceID = workspace.id
                if workspaceHasSqlDeliveryIssue(workspace) {
                    await openDeliveryUpdateInCodex(workspace)
                } else if workspaceMissingDeliveryRecord(workspace) {
                    await loadDocument(path: deliveryDocumentPath(for: workspace))
                } else {
                    await openDeliveryUpdateInCodex(workspace)
                }
            }
        case "review-worktrees":
            if let workspace = workspaceForAutomationSignal(signal) {
                selectedWorkspaceID = workspace.id
                if !missingWorktreeServices(in: workspace).isEmpty {
                    presentWorktreeSetup(for: workspace)
                }
            }
        case "review-dirty-services":
            if let workspace = workspaceForAutomationSignal(signal) {
                selectedWorkspaceID = workspace.id
                if let service = dirtyServices(in: workspace).first {
                    await openServiceInCodex(service, in: workspace)
                }
            }
        case "review-branches":
            setWorkspaceFilter(.risky)
            if let workspace = workspaceForAutomationSignal(signal) {
                selectedWorkspaceID = workspace.id
                await loadDocument(path: branchesDocumentPath(for: workspace))
            }
        case "review-tasks":
            if highPriorityTaskCount(from: lastAutomationCheck) > 0 {
                setTaskCenterFilter(.high)
            } else {
                setTaskCenterFilter(.all)
            }
            if let item = taskCenterItems.first(where: { $0.task.isActive })
                ?? allTaskCenterItems.first(where: { $0.task.isActive })
                ?? taskCenterItems.first
                ?? allTaskCenterItems.first {
                selectTaskCenterItem(item)
            }
        case "refresh":
            await refreshFromBridge()
        default:
            if let workspace = selectedWorkspace {
                selectedWorkspaceID = workspace.id
            }
        }
    }

    func runLifecycleAction(for workspace: WorkspaceSummary) async {
        selectedWorkspaceID = workspace.id
        let documentKey = workspace.lifecycle.documentKey
        if documentKey == "worktreeScript" && !missingWorktreeServices(in: workspace).isEmpty {
            presentWorktreeSetup(for: workspace)
            return
        }

        let path = workspace.documentLinks[documentKey]
            ?? workspace.documentLinks["handoff"]
            ?? "\(workspace.path)/handoff.md"
        await loadDocument(path: path)
    }

    func lifecycleHandoffPrompt(for workspace: WorkspaceSummary) -> String {
        [
            "请根据 Nexus 工作区生命周期继续推进本地开发流程。",
            "",
            "## 工作区",
            "- 名称: \(workspace.name)",
            "- 目录: \(workspace.path)",
            "- 文件夹: \(workspace.folder)",
            "- 目标分支: \(workspace.branch)",
            "- 涉及服务: \(workspace.serviceSummary.isEmpty ? "待确认" : workspace.serviceSummary)",
            "",
            "## 生命周期",
            "- 阶段: \(workspace.lifecycle.label)",
            "- 进度: \(workspace.lifecycle.progress)%",
            "- 当前说明: \(workspace.lifecycle.detail)",
            "- 下一步: \(workspace.lifecycle.nextAction)",
            "",
            "## 已绑定 Codex 会话",
            codexSessionHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 当前信号",
            "- 风险数: \(workspace.risks.count)",
            "- 活跃任务: \(workspace.tasks.filter(\.isActive).count)",
            "- Worktree: \(workspace.worktreeState)",
            "",
            "## 处理要求",
            "- 先读取工作区 Markdown，尤其是 AGENTS.md、requirements.md、acceptance.md、changes.md、STATUS.md、tasks.md、branches.md 和交付记录。",
            "- 按生命周期下一步处理，不要跳过服务范围、分支、worktree、交付记录这些前置条件。",
            "- 如果涉及代码、SQL、业务逻辑、接口、DTO、配置或验证变化，同步更新 changes.md 和交付记录。",
            "- 处理完成后回到 Nexus 刷新，并重新确认生命周期阶段。"
        ].joined(separator: "\n")
    }

    func workspaceHandoffPrompt(for workspace: WorkspaceSummary) -> String {
        let openTasks = workspace.tasks.filter(\.isActive)
        let deferredTaskCount = workspace.tasks.filter(\.isDeferred).count
        let blockedTaskCount = openTasks.filter(\.isBlocked).count
        let deliveryLines = deliveryHandoffLines(for: workspace)
        let serviceLines = serviceHandoffLines(for: workspace)
        let taskLines = taskHandoffLines(for: workspace)
        let actionLines = sessionActionHandoffLines(for: workspace)
        let localCheckLines = localCheckHandoffLines()
        let mainStageLines = mainStageAnswerHandoffLines(for: workspace)

        return [
            "继续处理这个 Nexus 本地工作区。",
            "",
            "## 工作区",
            "- 名称: \(workspace.name)",
            "- 目录: \(workspace.path)",
            "- 文件夹: \(workspace.folder)",
            "- 目标分支: \(workspace.branch)",
            "- 涉及服务: \(workspace.serviceSummary.isEmpty ? "待确认" : workspace.serviceSummary)",
            "- Worktree: \(workspace.worktreeState)",
            "",
            "## 当前状态",
            "- 生命周期: \(workspace.lifecycle.label)",
            "- 下一步: \(workspace.lifecycle.nextAction)",
            "- 风险数: \(workspace.risks.count)",
            "- 活跃任务: \(openTasks.count)",
            "- 延期任务: \(deferredTaskCount)",
            "- 阻塞任务: \(blockedTaskCount)",
            "- Worktree 缺失: \(workspace.services.filter { !$0.worktreeExists }.count)",
            "",
            "## 主路径回答",
            mainStageLines.joined(separator: "\n"),
            "",
            "## 最近本地检查",
            localCheckLines.joined(separator: "\n"),
            "",
            "## 服务与 worktree",
            serviceLines.joined(separator: "\n"),
            "",
            "## 任务与交付",
            taskLines.joined(separator: "\n"),
            "",
            "### 交付状态",
            deliveryLines.joined(separator: "\n"),
            "",
            "## Nexus 推荐动作",
            actionLines.joined(separator: "\n"),
            "",
            "## 已绑定 Codex 会话",
            codexSessionHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 本地路径",
            "- Workspaces root: \(workspaceRoot)",
            "- Source repos root: \(sourceReposRoot)",
            "- Docs root: \(docsRoot)",
            "- requirements.md: \(workspace.documentLinks["requirements"] ?? "\(workspace.path)/requirements.md")",
            "- acceptance.md: \(workspace.documentLinks["acceptance"] ?? "\(workspace.path)/acceptance.md")",
            "- changes.md: \(workspace.documentLinks["changes"] ?? "\(workspace.path)/changes.md")",
            "- tasks.md: \(workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md")",
            "- 交付记录: \(workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md")",
            "- handoff.md: \(workspace.documentLinks["handoff"] ?? "\(workspace.path)/handoff.md")",
            "",
            "## 处理要求",
            "- 先读取工作区 Markdown，再决定是否修改代码或文档。",
            "- 优先按 Nexus 推荐动作处理；如果有阻塞项，先处理阻塞项再进入代码修改。",
            "- 优先在 workspace-local repos/<service> worktree 中处理，不要切换源仓库分支。",
            "- 如果涉及代码、SQL、业务逻辑、接口、DTO、配置或验证变化，同步更新 changes.md 和交付记录。",
            "- 处理完成后回到 Nexus 刷新工作区状态，并再次运行本地检查。"
        ].joined(separator: "\n")
    }

    private func localCheckHandoffLines() -> [String] {
        guard let check = lastAutomationCheck else {
            return ["- 尚未运行本地检查。建议先在 Nexus 运行本地检查，或接手后自行检查 workspace/git 状态。"]
        }

        return [
            "- 触发方: \(lastAutomationCheckActor ?? "Nexus")",
            "- 状态: \(check.status)",
            "- 时间: \(check.generatedAt)",
            "- 摘要: \(check.summary)",
            "- 风险: \(check.riskCount)",
            "- 交付问题: \(check.deliveryIssueCount)",
            "- 分支问题: \(check.branchMismatchCount)",
            "- 活跃任务: \(check.openTaskCount)（高优先级 \(check.highPriorityTaskCount)）",
            "- worktree 问题: 缺失 \(check.missingWorktreeCount)，未提交 \(check.dirtyServiceCount)",
            check.auditError.map { "- 审计写入失败: \($0)" } ?? "- 审计: \(check.auditEventId == nil ? "未写入" : "已写入")"
        ]
    }

    private func mainStageAnswerHandoffLines(for workspace: WorkspaceSummary) -> [String] {
        let answer = workspace.mainStage().answer
        return [
            "- 当前阶段: \(answer.stageLabel)",
            "- 状态: \(answer.status.displayLabel)",
            "- 阻塞/就绪: \(answer.blockerSummary)",
            "- 下一步: \(answer.nextActionLabel)",
            "- 主证据: \(answer.primaryEvidenceLink?.label ?? "未路由")"
        ]
    }

    private func serviceHandoffLines(for workspace: WorkspaceSummary) -> [String] {
        guard !workspace.services.isEmpty else {
            return ["- 服务范围待确认。先查看 services.md 和 branches.md。"]
        }

        return workspace.services.prefix(8).map { service in
            "- \(service.name): branch=\(service.branch), worktree=\(service.worktree), git=\(service.gitSummary)"
        } + (workspace.services.count > 8 ? ["- 仅列出前 8 个服务，完整范围请查看 services.md。"] : [])
    }

    private func taskHandoffLines(for workspace: WorkspaceSummary) -> [String] {
        let openTasks = workspace.tasks.filter(\.isActive)
        let deferredTasks = workspace.tasks.filter(\.isDeferred)
        guard !openTasks.isEmpty else {
            if !deferredTasks.isEmpty {
                return [
                    "- 当前没有活跃任务。",
                    "- 延期任务: \(deferredTasks.prefix(5).map(\.title).joined(separator: ", "))"
                ]
            }
            return ["- 当前没有活跃任务。交付前仍需复核 tasks.md 是否有遗漏。"]
        }

        let activeLines = openTasks.prefix(5).map { task in
            "- [\(task.priority)] \(task.title) · 状态: \(task.status) · 来源: \(task.source)"
        } + (openTasks.count > 5 ? ["- 仅列出前 5 个活跃任务，完整任务请查看 tasks.md。"] : [])
        let deferredLine = deferredTasks.isEmpty
            ? []
            : ["- 延期任务: \(deferredTasks.prefix(5).map(\.title).joined(separator: ", "))"]
        return activeLines + deferredLine
    }

    private func deliveryHandoffLines(for workspace: WorkspaceSummary) -> [String] {
        let deliveryPath = workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md"
        let deliveryCheck = workspace.healthChecks.first { check in
            check.id == "delivery-record" || check.action == "delivery"
        }
        let sqlCheck = workspace.healthChecks.first { check in
            check.id == "sql-directory" || check.action == "sql"
        }

        return [
            "- 交付记录: \(deliveryPath)",
            "- 交付检查: \(deliveryCheck.map { "\($0.status) · \($0.detail)" } ?? "未生成检查结果")",
            "- SQL 检查: \(sqlCheck.map { "\($0.status) · \($0.detail)" } ?? "未生成检查结果")",
            "- 生命周期建议: \(workspace.lifecycle.nextAction)"
        ]
    }

    func deliveryUpdatePrompt(for workspace: WorkspaceSummary) -> String {
        let openTasks = workspace.tasks.filter(\.isActive)
        let blockedTasks = openTasks.filter(\.isBlocked)
        let riskLines = workspace.risks.isEmpty
            ? ["- 暂无显式风险。"]
            : workspace.risks.map { "- \($0.title): \($0.detail)" }
        let sqlLines = workspace.healthChecks
            .filter { check in check.id == "sql-directory" || check.action == "sql" }
            .map { "- \($0.label) [\($0.status)]: \($0.detail)" }
        let deliveryPath = workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md"

        return [
            "请帮我复核并补充这个 Nexus 工作区的交付记录。",
            "",
            "## 工作区",
            "- 名称: \(workspace.name)",
            "- 目录: \(workspace.path)",
            "- 文件夹: \(workspace.folder)",
            "- 目标分支: \(workspace.branch)",
            "- 涉及服务: \(workspace.serviceSummary.isEmpty ? "待确认" : workspace.serviceSummary)",
            "- Worktree: \(workspace.worktreeState)",
            "",
            "## 交付文档",
            "- 交付记录: \(deliveryPath)",
            "- tasks.md: \(workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md")",
            "- STATUS.md: \(workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md")",
            "- services.md: \(workspace.documentLinks["services"] ?? "\(workspace.path)/services.md")",
            "- branches.md: \(workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md")",
            "- requirements.md: \(workspace.documentLinks["requirements"] ?? "\(workspace.path)/requirements.md")",
            "- acceptance.md: \(workspace.documentLinks["acceptance"] ?? "\(workspace.path)/acceptance.md")",
            "- changes.md: \(workspace.documentLinks["changes"] ?? "\(workspace.path)/changes.md")",
            "",
            "## 最近本地检查",
            localCheckHandoffLines().joined(separator: "\n"),
            "",
            "## 服务与 worktree",
            serviceHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 已绑定 Codex 会话",
            codexSessionHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 任务",
            "- 活跃任务: \(openTasks.count)",
            "- 阻塞任务: \(blockedTasks.count)",
            taskHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 交付与 SQL",
            deliveryHandoffLines(for: workspace).joined(separator: "\n"),
            sqlLines.isEmpty ? "- SQL 检查: 暂无检查结果。请查看 sql/ 目录和交付记录是否需要补 SQL。" : sqlLines.joined(separator: "\n"),
            "",
            "## 风险",
            riskLines.joined(separator: "\n"),
            "",
            "## 处理要求",
            "- 先读取工作区 Markdown、requirements.md、acceptance.md、changes.md 和现有交付记录，不要凭空补内容。",
            "- 如果本轮有代码、SQL、业务逻辑、接口、DTO、配置或验证变化，必须补到 changes.md 和交付记录。",
            "- 如果交付记录任意位置记录实际 SQL 变更，或 SQL 段落出现 `变更类型：DDL/DML`、影响表、新增字段、回填脚本、数据修复等变更元数据，必须在 sql/ 下同步正式 SQL 文件和回滚 SQL 文件。",
            "- 交付记录至少覆盖：涉及服务、分支/worktree 状态、改动范围、SQL/配置、验证记录、风险和后续事项。",
            "- 如果发现交付记录缺少事实，请列出需要我确认的问题，不要编造验证结果。",
            "- 完成后提示我回到 Nexus 刷新并重新运行本地检查。"
        ].joined(separator: "\n")
    }

    func validationPrHandoffPrompt(for workspace: WorkspaceSummary) -> String {
        let openTasks = workspace.tasks.filter(\.isActive)
        let blockedTasks = openTasks.filter(\.isBlocked)
        let deliveryPath = workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md"
        let tasksPath = workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md"
        let handoffPath = workspace.documentLinks["handoff"] ?? "\(workspace.path)/handoff.md"
        let branchPath = workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md"
        let requirementsPath = workspace.documentLinks["requirements"] ?? "\(workspace.path)/requirements.md"
        let acceptancePath = workspace.documentLinks["acceptance"] ?? "\(workspace.path)/acceptance.md"
        let changesPath = workspace.documentLinks["changes"] ?? "\(workspace.path)/changes.md"
        let localCheckLines = localCheckHandoffLines()
        let readinessLines = workspace.healthChecks.isEmpty
            ? ["- 暂无 workspace health check，请先运行 Nexus 本地检查。"]
            : workspace.healthChecks.map { "- \($0.label) [\($0.status)]: \($0.detail)" }

        return [
            "请帮我准备这个 Nexus 工作区的验证与 PR 交接。",
            "",
            "## 工作区",
            "- 名称: \(workspace.name)",
            "- 目录: \(workspace.path)",
            "- 文件夹: \(workspace.folder)",
            "- 目标分支: \(workspace.branch)",
            "- 涉及服务: \(workspace.serviceSummary.isEmpty ? "待确认" : workspace.serviceSummary)",
            "- Worktree: \(workspace.worktreeState)",
            "- 生命周期: \(workspace.lifecycle.label)",
            "",
            "## 最近本地检查",
            localCheckLines.joined(separator: "\n"),
            "",
            "## 交付与就绪检查",
            deliveryHandoffLines(for: workspace).joined(separator: "\n"),
            readinessLines.joined(separator: "\n"),
            "",
            "## 任务状态",
            "- 活跃任务: \(openTasks.count)",
            "- 阻塞任务: \(blockedTasks.count)",
            taskHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 服务与 worktree",
            serviceHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 已绑定 Codex 会话",
            codexSessionHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 文档入口",
            "- 交付记录: \(deliveryPath)",
            "- tasks.md: \(tasksPath)",
            "- branches.md: \(branchPath)",
            "- requirements.md: \(requirementsPath)",
            "- acceptance.md: \(acceptancePath)",
            "- changes.md: \(changesPath)",
            "- handoff.md: \(handoffPath)",
            "",
            "## 处理要求",
            "- 先复核需求规则、验收清单、变更日志、本地工作树、目标分支、任务、交付记录、SQL 产物和最近本地检查。",
            "- 不要编造验证结果；缺少的测试、CI、PR 链接或发布状态请明确列为待确认。",
            "- 输出适合 PR 描述的摘要：背景、改动范围、影响服务、验证记录、SQL/配置、风险与回滚。",
            "- 如果交付记录任意位置记录实际 SQL 变更，或 SQL 段落出现 `变更类型：DDL/DML`、影响表、新增字段、回填脚本、数据修复等变更元数据，确认 sql/ 下已有正式 SQL 和回滚 SQL。",
            "- 最后列出回到 Nexus 后需要执行的动作，例如刷新、运行本地检查、绑定 Codex 会话或归档。"
        ].joined(separator: "\n")
    }

    func openValidationPrHandoffInCodex(_ workspace: WorkspaceSummary) async {
        let prompt = validationPrHandoffPrompt(for: workspace)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        let rawURL = codexURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultCodexURL
            : codexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: rawURL) {
            NSWorkspace.shared.open(url)
            markCodexHandoff(
                title: "验证与 PR 已复制 / PR handoff copied",
                detail: "\(workspace.name) · 本地检查、交付、任务、SQL 和 PR 待确认项已复制到剪贴板。",
                systemImage: "checkmark.seal",
                sectionTitle: "验证交接 / Validation",
                clipboardLabel: "Validation and PR handoff is on the clipboard"
            )
        } else {
            lastError = "Invalid Codex URL: \(rawURL)"
            markCodexHandoff(
                title: "验证与 PR 已复制 / URL needs review",
                detail: "\(workspace.name) · Codex URL 无效，请在 Settings 中修正。",
                systemImage: "exclamationmark.triangle",
                sectionTitle: "验证交接 / Validation",
                clipboardLabel: "Validation and PR handoff is on the clipboard"
            )
        }

        await recordWorkspaceAction(
            action: "codex_validation_pr_handoff.opened",
            target: workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md",
            summary: "Copied validation and PR handoff and opened Codex",
            metadata: [
                "tool": "Codex",
                "codexUrl": rawURL,
                "lifecycle": workspace.lifecycle.stage,
                "openTasks": "\(workspace.tasks.filter(\.isActive).count)",
                "riskCount": "\(workspace.risks.count)",
                "serviceCount": "\(workspace.services.count)",
                "lastLocalCheckStatus": lastAutomationCheck?.status ?? "none"
            ],
            workspaceOverride: workspace
        )
    }

    func openDeliveryUpdateInCodex(_ workspace: WorkspaceSummary) async {
        let prompt = deliveryUpdatePrompt(for: workspace)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        let rawURL = codexURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultCodexURL
            : codexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: rawURL) {
            NSWorkspace.shared.open(url)
            markCodexHandoff(
                title: "交付上下文已复制 / Delivery copied",
                detail: "\(workspace.name) · 交付记录、任务、SQL、风险和服务状态已复制到剪贴板。",
                systemImage: "doc.text"
            )
        } else {
            lastError = "Invalid Codex URL: \(rawURL)"
            markCodexHandoff(
                title: "交付上下文已复制 / URL needs review",
                detail: "\(workspace.name) · Codex URL 无效，请在 Settings 中修正。",
                systemImage: "exclamationmark.triangle"
            )
        }

        await recordWorkspaceAction(
            action: "codex_delivery_handoff.opened",
            target: workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md",
            summary: "Copied delivery update handoff and opened Codex",
            metadata: [
                "tool": "Codex",
                "codexUrl": rawURL,
                "openTasks": "\(workspace.tasks.filter(\.isActive).count)",
                "riskCount": "\(workspace.risks.count)",
                "serviceCount": "\(workspace.services.count)"
            ],
            workspaceOverride: workspace
        )
    }

    private func sessionActionHandoffLines(for workspace: WorkspaceSummary) -> [String] {
        guard !workspace.sessionActions.isEmpty else {
            return ["- Nexus 当前没有返回推荐动作。可从状态概览、Workflow 和 Risk Review 继续判断。"]
        }

        return workspace.sessionActions.prefix(5).map { action in
            "- [\(action.priority)] \(action.label): \(action.detail)"
        }
    }

    private func codexSessionHandoffLines(for workspace: WorkspaceSummary) -> [String] {
        let links = codexSessionLinks(for: workspace)
        guard !links.isEmpty else {
            return ["- 未绑定 Codex 会话。需要继续历史上下文时，可在 Nexus 的 Sessions 区块绑定会话链接。"]
        }

        let visibleLinks = links.prefix(5).map { link in
            let opened = link.lastOpenedAt ?? "never"
            let cleanNotes = link.notes.trimmingCharacters(in: .whitespacesAndNewlines)
            let notes = cleanNotes.isEmpty ? "" : " · notes: \(cleanNotes)"
            return "- \(link.title): \(link.url) · opened: \(opened)\(notes)"
        }
        let overflow = links.count > 5
            ? ["- 仅列出前 5 个 Codex 会话，完整列表请查看 Nexus Sessions 区块。"]
            : []
        return visibleLinks + overflow
    }

    func riskReviewPrompt(for workspace: WorkspaceSummary) -> String {
        let riskLines = workspace.risks.isEmpty
            ? ["- 暂无显式风险。"]
            : workspace.risks.map { "- \($0.title): \($0.detail)" }
        let checkLines = workspace.healthChecks
            .filter { check in
                let status = check.status.lowercased()
                return status != "pass" && status != "ok"
            }
            .map { "- \($0.label) [\($0.status)]: \($0.detail)" }
        let actionLines = workspace.sessionActions.isEmpty
            ? ["- 暂无推荐会话动作。"]
            : workspace.sessionActions.map { "- \($0.label) [\($0.priority)]: \($0.detail)" }

        return [
            "请对这个 Nexus 工作区做一次风险复核，并给出下一步处理顺序。",
            "",
            "## 工作区",
            "- 名称: \(workspace.name)",
            "- 目录: \(workspace.path)",
            "- 文件夹: \(workspace.folder)",
            "- 目标分支: \(workspace.branch)",
            "- 涉及服务: \(workspace.serviceSummary.isEmpty ? "待确认" : workspace.serviceSummary)",
            "- Worktree: \(workspace.worktreeState)",
            "",
            "## 当前风险",
            riskLines.joined(separator: "\n"),
            "",
            "## 未通过检查",
            checkLines.isEmpty ? "- 暂无未通过检查。" : checkLines.joined(separator: "\n"),
            "",
            "## 推荐动作",
            actionLines.joined(separator: "\n"),
            "",
            "## 已绑定 Codex 会话",
            codexSessionHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 处理要求",
            "- 先读取 requirements.md、acceptance.md、changes.md、workspace.md、STATUS.md、services.md、branches.md、tasks.md 和交付记录。",
            "- 判断风险属于需求范围、分支、worktree、服务 git 状态、任务阻塞、SQL/交付记录，还是实现逻辑。",
            "- 给出阻塞项、可并行项和建议处理顺序。",
            "- 如果处理涉及代码、SQL、业务逻辑、接口、DTO、配置或验证变化，同步更新 changes.md 和交付记录。",
            "- 处理完成后回到 Nexus 运行本地检查并刷新状态。"
        ].joined(separator: "\n")
    }

    func openWorkspaceInFinder(_ workspace: WorkspaceSummary) async {
        let url = Self.localFileURL(for: workspace.path)
        NSWorkspace.shared.activateFileViewerSelecting([url])
        await recordWorkspaceAction(
            action: "workspace.finder.opened",
            target: workspace.path,
            summary: "Opened workspace in Finder",
            metadata: ["tool": "Finder"],
            workspaceOverride: workspace
        )
    }

    func openWorkspaceInTerminal(_ workspace: WorkspaceSummary) async {
        let url = Self.localFileURL(for: workspace.path)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true

        if let terminalURL = Self.terminalApplicationURL {
            NSWorkspace.shared.open(
                [url],
                withApplicationAt: terminalURL,
                configuration: configuration
            ) { [weak self] _, error in
                Task { @MainActor in
                    if let error {
                        self?.lastError = "Terminal open failed: \(error.localizedDescription)"
                    }
                }
            }
        } else {
            NSWorkspace.shared.open(url)
        }

        await recordWorkspaceAction(
            action: "workspace.terminal.opened",
            target: workspace.path,
            summary: "Opened workspace in Terminal",
            metadata: ["tool": "Terminal"],
            workspaceOverride: workspace
        )
    }

    func openWorkspaceInIDE(_ workspace: WorkspaceSummary) async {
        lastError = nil
        let rawTemplate = ideURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTemplate.isEmpty else {
            lastError = "IDE URL template is empty. Configure it in Settings, for example \(Self.defaultIDEURL)."
            return
        }

        let rawPath = workspace.path.trimmingCharacters(in: .whitespacesAndNewlines)
        let encodedPath = rawPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawPath
        let rawURL = rawTemplate
            .replacingOccurrences(of: "{path}", with: encodedPath)
            .replacingOccurrences(of: "{rawPath}", with: rawPath)

        guard let url = URL(string: rawURL), NSWorkspace.shared.open(url) else {
            lastError = "IDE open failed. Check the IDE URL template in Settings: \(rawTemplate)"
            return
        }

        await recordWorkspaceAction(
            action: "workspace.ide.opened",
            target: workspace.path,
            summary: "Opened workspace in IDE",
            metadata: [
                "tool": "IDE",
                "ideUrl": rawURL
            ],
            workspaceOverride: workspace
        )
    }

    func openServiceWorktreeInFinder(_ service: ServiceStatus, in workspace: WorkspaceSummary) async {
        await openServicePathInFinder(
            serviceWorktreePath(for: service, in: workspace),
            service: service,
            workspace: workspace,
            action: "service.worktree.finder.opened",
            summary: "Opened service worktree in Finder",
            tool: "Finder",
            readOnly: false
        )
    }

    func openServiceSourceInFinder(_ service: ServiceStatus, in workspace: WorkspaceSummary) async {
        await openServicePathInFinder(
            serviceSourcePath(for: service),
            service: service,
            workspace: workspace,
            action: "service.source.finder.opened",
            summary: "Opened service source repository in Finder",
            tool: "Finder",
            readOnly: true
        )
    }

    func openServiceWorktreeInIDE(_ service: ServiceStatus, in workspace: WorkspaceSummary) async {
        await openServicePathInIDE(
            serviceWorktreePath(for: service, in: workspace),
            service: service,
            workspace: workspace,
            action: "service.worktree.ide.opened",
            summary: "Opened service worktree in IDE"
        )
    }

    func openServiceInCodex(_ service: ServiceStatus, in workspace: WorkspaceSummary) async {
        let prompt = serviceHandoffPrompt(for: service, in: workspace)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        let rawURL = codexURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultCodexURL
            : codexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: rawURL) {
            NSWorkspace.shared.open(url)
            markCodexHandoff(
                title: "服务上下文已复制 / Service copied",
                detail: "\(workspace.name) · \(service.name) 的分支、worktree、source 和文档上下文已复制。",
                systemImage: "square.stack.3d.up",
                sectionTitle: "服务交接 / Service",
                clipboardLabel: "Service handoff is on the clipboard"
            )
        } else {
            lastError = "Invalid Codex URL: \(rawURL)"
            markCodexHandoff(
                title: "服务上下文已复制 / URL needs review",
                detail: "\(workspace.name) · Codex URL 无效，请在 Settings 中修正。",
                systemImage: "exclamationmark.triangle",
                sectionTitle: "服务交接 / Service",
                clipboardLabel: "Service handoff is on the clipboard"
            )
        }

        await recordWorkspaceAction(
            action: "codex_service_handoff.opened",
            target: serviceWorktreePath(for: service, in: workspace),
            summary: "Copied service handoff and opened Codex",
            metadata: [
                "tool": "Codex",
                "codexUrl": rawURL,
                "service": service.name,
                "serviceBranch": service.branch,
                "worktree": service.worktree,
                "source": service.gitSummary,
                "worktreeExists": "\(service.worktreeExists)",
                "sourceExists": "\(service.sourceExists)"
            ],
            workspaceOverride: workspace
        )
    }

    func openWorkspaceInCodex(_ workspace: WorkspaceSummary) async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(workspaceHandoffPrompt(for: workspace), forType: .string)

        let rawURL = codexURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultCodexURL
            : codexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: rawURL) {
            NSWorkspace.shared.open(url)
            markCodexHandoff(
                title: "Codex 已打开 / Workspace copied",
                detail: "\(workspace.name) · 工作区、任务、交付和最近检查上下文已复制。",
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        } else {
            lastError = "Invalid Codex URL: \(rawURL)"
            markCodexHandoff(
                title: "上下文已复制 / URL needs review",
                detail: "\(workspace.name) · Codex URL 无效，请在 Settings 中修正。",
                systemImage: "exclamationmark.triangle"
            )
        }

        await recordWorkspaceAction(
            action: "codex.opened",
            target: workspace.path,
            summary: "Copied workspace handoff and opened Codex",
            metadata: [
                "tool": "Codex",
                "codexUrl": rawURL,
                "riskCount": "\(workspace.risks.count)",
                "openTaskCount": "\(workspace.tasks.filter(\.isActive).count)",
                "lastCheckStatus": lastAutomationCheck?.status ?? "none"
            ],
            workspaceOverride: workspace
        )
    }

    private func openServicePathInFinder(
        _ path: String,
        service: ServiceStatus,
        workspace: WorkspaceSummary,
        action: String,
        summary: String,
        tool: String,
        readOnly: Bool
    ) async {
        lastError = nil
        let url = Self.localFileURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastError = "Service path does not exist: \(url.path)"
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([url])
        await recordWorkspaceAction(
            action: action,
            target: url.path,
            summary: summary,
            metadata: [
                "tool": tool,
                "service": service.name,
                "serviceBranch": service.branch,
                "accessMode": readOnly ? "read-only" : "workspace-local",
                "reviewOnly": readOnly ? "true" : "false"
            ],
            workspaceOverride: workspace
        )
    }

    private func openServicePathInIDE(
        _ path: String,
        service: ServiceStatus,
        workspace: WorkspaceSummary,
        action: String,
        summary: String
    ) async {
        lastError = nil
        let url = Self.localFileURL(for: path)
        guard FileManager.default.fileExists(atPath: url.path) else {
            lastError = "Service worktree path does not exist: \(url.path)"
            return
        }

        let rawTemplate = ideURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawTemplate.isEmpty else {
            lastError = "IDE URL template is empty. Configure it in Settings, for example \(Self.defaultIDEURL)."
            return
        }

        let rawPath = url.path
        let encodedPath = rawPath.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? rawPath
        let rawURL = rawTemplate
            .replacingOccurrences(of: "{path}", with: encodedPath)
            .replacingOccurrences(of: "{rawPath}", with: rawPath)

        guard let ideLaunchURL = URL(string: rawURL), NSWorkspace.shared.open(ideLaunchURL) else {
            lastError = "IDE open failed. Check the IDE URL template in Settings: \(rawTemplate)"
            return
        }

        await recordWorkspaceAction(
            action: action,
            target: rawPath,
            summary: summary,
            metadata: [
                "tool": "IDE",
                "ideUrl": rawURL,
                "service": service.name,
                "serviceBranch": service.branch
            ],
            workspaceOverride: workspace
        )
    }

    private func serviceWorktreePath(for service: ServiceStatus, in workspace: WorkspaceSummary) -> String {
        Self.localFileURL(for: workspace.path)
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent(service.name, isDirectory: true)
            .path
    }

    private func serviceSourcePath(for service: ServiceStatus) -> String {
        Self.localFileURL(for: sourceReposRoot)
            .appendingPathComponent(service.name, isDirectory: true)
            .path
    }

    private func serviceHandoffPrompt(for service: ServiceStatus, in workspace: WorkspaceSummary) -> String {
        [
            "请继续处理 Nexus 工作区中的单个服务上下文。",
            "",
            "## 工作区",
            "- 名称: \(workspace.name)",
            "- 目录: \(workspace.path)",
            "- 目标分支: \(workspace.branch)",
            "",
            "## 服务",
            "- 服务名: \(service.name)",
            "- worktree 路径: \(serviceWorktreePath(for: service, in: workspace))",
            "- source repo 路径: \(serviceSourcePath(for: service))",
            "- worktree 分支: \(service.branch)",
            "- worktree 状态: \(service.worktree)",
            "- source 状态: \(service.gitSummary)",
            "- worktree 是否存在: \(service.worktreeExists ? "是" : "否")",
            "- source repo 是否存在: \(service.sourceExists ? "是" : "否")",
            "",
            "## 相关文档",
            "- services.md: \(workspace.documentLinks["services"] ?? "\(workspace.path)/services.md")",
            "- branches.md: \(workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md")",
            "- requirements.md: \(workspace.documentLinks["requirements"] ?? "\(workspace.path)/requirements.md")",
            "- acceptance.md: \(workspace.documentLinks["acceptance"] ?? "\(workspace.path)/acceptance.md")",
            "- changes.md: \(workspace.documentLinks["changes"] ?? "\(workspace.path)/changes.md")",
            "- tasks.md: \(workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md")",
            "- 交付记录.md: \(workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md")",
            "",
            "## 已绑定 Codex 会话",
            codexSessionHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 处理要求",
            "- 先确认该服务是否应该在当前需求范围内。",
            "- 如果 worktree 缺失，先回到 Nexus 执行确认后的 worktree 创建流程，不要直接在 source repo 切分支。",
            "- 如果存在未提交或分支不一致，先说明风险，再决定是否继续开发、提交或调整文档。",
            "- 涉及代码、SQL、业务逻辑、配置或验证变化时，同步更新 changes.md、交付记录和必要 SQL 产物。"
        ].joined(separator: "\n")
    }

    func codexSessionLinks(for workspace: WorkspaceSummary) -> [CodexSessionLink] {
        codexSessionLinksByWorkspace[workspace.id] ?? []
    }

    func codexSessionLinksPath(for workspace: WorkspaceSummary) -> String {
        Self.codexSessionLinksURL(for: workspace).path
    }

    func codexSessionSuggestions(for workspace: WorkspaceSummary) -> [CodexSessionSuggestion] {
        let existingURLs = Set(codexSessionLinks(for: workspace).map { $0.url })
        var seenURLs: Set<String> = []

        return agentEvents
            .filter { Self.agentEvent($0, matches: workspace) }
            .flatMap { event in
                Self.codexSessionURLCandidates(from: event).compactMap { candidate in
                    guard !existingURLs.contains(candidate.url),
                          !seenURLs.contains(candidate.url) else {
                        return nil
                    }
                    seenURLs.insert(candidate.url)
                    return CodexSessionSuggestion(
                        id: "\(event.id)-\(candidate.url)",
                        title: candidate.title,
                        url: candidate.url,
                        notes: "From \(event.source) event: \(event.title)",
                        source: event.source,
                        eventTitle: event.title,
                        eventTimestamp: event.timestamp
                    )
                }
            }
    }

    @discardableResult
    func bindCodexSessionSuggestion(
        _ suggestion: CodexSessionSuggestion,
        to workspace: WorkspaceSummary
    ) async -> Bool {
        await bindCodexSessionLink(
            to: workspace,
            title: suggestion.title,
            url: suggestion.url,
            notes: suggestion.notes
        )
    }

    @discardableResult
    func bindCodexSessionLink(
        to workspace: WorkspaceSummary,
        title: String,
        url rawURL: String,
        notes: String
    ) async -> Bool {
        lastError = nil
        guard let sessionURL = Self.normalizedCodexSessionURL(rawURL) else {
            lastError = "Codex session URL requires a valid scheme, for example codex:// or https://."
            return false
        }

        let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let cleanNotes = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        var links = codexSessionLinks(for: workspace)
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let displayTitle = cleanTitle.isEmpty ? "Codex session \(links.count + 1)" : cleanTitle
        let isUpdate: Bool

        if let existingIndex = links.firstIndex(where: { $0.url == sessionURL }) {
            links[existingIndex].title = displayTitle
            links[existingIndex].notes = cleanNotes
            isUpdate = true
        } else {
            links.insert(
                CodexSessionLink(
                    id: UUID().uuidString,
                    title: displayTitle,
                    url: sessionURL,
                    notes: cleanNotes,
                    createdAt: timestamp,
                    lastOpenedAt: nil
                ),
                at: 0
            )
            isUpdate = false
        }

        return await persistCodexSessionLinks(
            links,
            for: workspace,
            action: isUpdate ? "codex_session_link.updated" : "codex_session_link.bound",
            summary: isUpdate ? "Updated Codex session link" : "Bound Codex session link",
            feedbackTitle: isUpdate ? "Codex 会话已更新 / Session updated" : "Codex 会话已绑定 / Session bound",
            feedbackDetail: "\(workspace.name) · \(displayTitle)",
            metadata: [
                "sessionTitle": displayTitle,
                "sessionUrl": sessionURL,
                "sessionCount": "\(links.count)"
            ]
        )
    }

    func openCodexSessionLink(_ link: CodexSessionLink, in workspace: WorkspaceSummary) async {
        lastError = nil
        guard let url = URL(string: link.url) else {
            lastError = "Invalid Codex session URL: \(link.url)"
            return
        }

        NSWorkspace.shared.open(url)
        var links = codexSessionLinks(for: workspace)
        if let existingIndex = links.firstIndex(where: { $0.id == link.id }) {
            links[existingIndex].lastOpenedAt = ISO8601DateFormatter().string(from: Date())
            _ = await persistCodexSessionLinks(
                links,
                for: workspace,
                action: "codex_session_link.opened",
                summary: "Opened Codex session link",
                feedbackTitle: nil,
                feedbackDetail: nil,
                metadata: [
                    "sessionTitle": link.title,
                    "sessionUrl": link.url
                ]
            )
        }

        markCodexHandoff(
            title: "Codex 会话已打开 / Session opened",
            detail: "\(workspace.name) · \(link.title)",
            systemImage: "link"
        )
    }

    func copyCodexSessionLink(_ link: CodexSessionLink, in workspace: WorkspaceSummary) async {
        lastError = nil
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(link.url, forType: .string)
        markCodexHandoff(
            title: "Codex 会话链接已复制 / Session copied",
            detail: "\(workspace.name) · \(link.title)",
            systemImage: "doc.on.clipboard"
        )
        await recordWorkspaceAction(
            action: "codex_session_link.copied",
            target: link.url,
            summary: "Copied Codex session link",
            metadata: [
                "sessionTitle": link.title,
                "sessionUrl": link.url
            ],
            workspaceOverride: workspace
        )
    }

    @discardableResult
    func deleteCodexSessionLink(_ link: CodexSessionLink, from workspace: WorkspaceSummary) async -> Bool {
        lastError = nil
        let links = codexSessionLinks(for: workspace).filter { $0.id != link.id }
        return await persistCodexSessionLinks(
            links,
            for: workspace,
            action: "codex_session_link.deleted",
            summary: "Deleted Codex session link",
            feedbackTitle: "Codex 会话已删除 / Session deleted",
            feedbackDetail: "\(workspace.name) · \(link.title)",
            metadata: [
                "sessionTitle": link.title,
                "sessionUrl": link.url,
                "sessionCount": "\(links.count)"
            ]
        )
    }

    func recordLifecycleHandoffCopied(for workspace: WorkspaceSummary) async {
        markCodexHandoff(
            title: "生命周期上下文已复制 / Lifecycle copied",
            detail: "\(workspace.name) · \(workspace.lifecycle.label) · 下一步已放入剪贴板。",
            systemImage: "doc.on.clipboard"
        )
        await recordWorkspaceAction(
            action: "lifecycle_handoff.copied",
            target: workspace.path,
            summary: "Copied lifecycle handoff for \(workspace.lifecycle.label)",
            metadata: [
                "stage": workspace.lifecycle.stage,
                "progress": "\(workspace.lifecycle.progress)",
                "documentKey": workspace.lifecycle.documentKey
            ],
            workspaceOverride: workspace
        )
    }

    func recordRiskReviewHandoffCopied(for workspace: WorkspaceSummary) async {
        markCodexHandoff(
            title: "风险复核上下文已复制 / Risk copied",
            detail: "\(workspace.name) · \(workspace.risks.count) risks · 用于 Codex 继续复核。",
            systemImage: "exclamationmark.triangle"
        )
        await recordWorkspaceAction(
            action: "risk_review_handoff.copied",
            target: workspace.path,
            summary: "Copied risk review handoff",
            metadata: [
                "riskCount": "\(workspace.risks.count)",
                "healthCheckCount": "\(workspace.healthChecks.count)"
            ],
            workspaceOverride: workspace
        )
    }

    func automationSignalHandoffPrompt(for signal: LocalAutomationSignal) -> String {
        let selected = workspaceForAutomationSignal(signal) ?? selectedWorkspace
        let workspaceLines: [String]
        if let selected {
            let deliveryAndSqlChecks = selected.healthChecks
                .filter { check in
                    check.id == "delivery-record"
                        || check.id == "sql-directory"
                        || check.action == "delivery"
                        || check.action == "sql"
                }
                .map { "\($0.label) [\($0.status)]: \($0.detail)" }
                .joined(separator: " | ")
            let branchChecks = selected.healthChecks
                .filter { check in
                    check.id == "target-branch"
                        || check.id == "branch-alignment"
                        || check.action == "branches"
                }
                .map { "\($0.label) [\($0.status)]: \($0.detail)" }
                .joined(separator: " | ")
            let dirtyServiceDetails = dirtyServices(in: selected)
                .map { service in
                    "\(service.name): worktree=\(service.worktree), source=\(service.gitSummary)"
                }
                .joined(separator: " | ")
            let missingWorktreeDetails = selected.services
                .filter { !$0.worktreeExists }
                .map { service in
                    "\(service.name): worktree=\(service.worktree), source=\(service.sourceExists ? "exists" : "missing"), sourceGit=\(service.gitSummary)"
                }
                .joined(separator: " | ")
            let worktreeChecks = selected.healthChecks
                .filter { check in
                    check.id == "worktree-ready"
                        || check.action == "worktreeScript"
                }
                .map { "\($0.label) [\($0.status)]: \($0.detail)" }
                .joined(separator: " | ")
            let worktreeScriptPath = selected.documentLinks["worktreeScript"]
                ?? "\(selected.path)/scripts/worktree-commands.sh"
            let worktreeReadiness = Self.hasConfirmedTargetBranch(selected.branch)
                ? "目标分支已确认；在 Nexus 中显式确认后创建缺失 worktree。"
                : "目标分支未确认；先更新 branches.md 或 workspace.md，暂不要创建 worktree。"
            let nextStepActions = selected.sessionActions.isEmpty
                ? "无"
                : selected.sessionActions.prefix(5).map { action in
                    "[\(action.priority)/\(action.status)] \(action.label): \(action.detail) · 文档: \(action.documentKey)"
                }.joined(separator: " | ")
            let mainStageAnswer = mainStageAnswerHandoffLines(for: selected)
                .map { $0.replacingOccurrences(of: "- ", with: "", options: [.anchored]) }
                .joined(separator: " | ")
            let codexSessionDetails = codexSessionLinks(for: selected).isEmpty
                ? "未绑定"
                : codexSessionLinks(for: selected).prefix(5).map { link in
                    "\(link.title): \(link.url)"
                }.joined(separator: " | ")
            workspaceLines = [
                "- 当前工作区: \(selected.name)",
                "- 工作区目录: \(selected.path)",
                "- 目标分支: \(selected.branch)",
                "- 涉及服务: \(selected.serviceSummary.isEmpty ? "待确认" : selected.serviceSummary)",
                "- 风险数: \(selected.risks.count)",
                "- 活跃任务: \(selected.tasks.filter(\.isActive).count)",
                "- 主路径回答: \(mainStageAnswer)",
                "- 缺失 worktree: \(missingWorktreeDetails.isEmpty ? "无" : missingWorktreeDetails)",
                "- Worktree 脚本: \(worktreeScriptPath)",
                "- Worktree 检查: \(worktreeChecks.isEmpty ? "未生成" : worktreeChecks)",
                "- Worktree 创建限制: \(worktreeReadiness)",
                "- Dirty 服务: \(dirtyServiceDetails.isEmpty ? "无" : dirtyServiceDetails)",
                "- 分支记录: \(branchesDocumentPath(for: selected))",
                "- 分支检查: \(branchChecks.isEmpty ? "未生成" : branchChecks)",
                "- 交付记录: \(deliveryDocumentPath(for: selected))",
                "- SQL 文件: \(selected.sqlFiles.isEmpty ? "未扫描到" : selected.sqlFiles.map(\.relativePath).joined(separator: ", "))",
                "- 交付/SQL 检查: \(deliveryAndSqlChecks.isEmpty ? "未生成" : deliveryAndSqlChecks)",
                "- Nexus 推荐动作: \(nextStepActions)",
                "- Codex 会话: \(codexSessionDetails)"
            ]
        } else {
            workspaceLines = ["- 当前工作区: 未选择"]
        }

        return ([
            "请根据 Nexus 自动化检查结果继续处理本地工作区。",
            "",
            "## 自动化信号",
            "- 类型: \(signal.kind)",
            "- 严重级别: \(signal.severity)",
            "- 标题: \(signal.title)",
            "- 详情: \(signal.detail)",
            "- 数量: \(signal.count)",
            "- 建议动作: \(signal.action)",
            "",
            "## 本地路径",
            "- Workspaces root: \(workspaceRoot)",
            "- Source repos root: \(sourceReposRoot)",
            "- Docs root: \(docsRoot)",
            "",
            "## 当前上下文"
        ] + workspaceLines + [
            "",
            "## 处理要求",
            "- 先读取相关工作区 Markdown，再决定是否修改代码或文档。",
            "- 如果涉及代码、SQL、业务逻辑、接口、DTO、配置或验证变化，同步更新 changes.md 和交付记录。",
            "- 优先在 workspace-local repos/<service> worktree 中处理，不直接切换源仓库分支。",
            "- 处理完成后回到 Nexus 刷新并再次运行自动化检查。"
        ]).joined(separator: "\n")
    }

    func recordAutomationSignalHandoffCopied(_ signal: LocalAutomationSignal) async {
        markCodexHandoff(
            title: "自动化信号已复制 / Signal copied",
            detail: "\(signal.title) · \(signal.count) item(s) · 可交给 Codex 继续处理。",
            systemImage: "bolt.badge.clock"
        )
        await recordNativeAuditEvent(
            AuditEventInput(
                actor: "Nexus Native",
                action: "automation_signal_handoff.copied",
                target: workspaceRoot,
                summary: "Copied handoff for \(signal.title)",
                metadata: [
                    "signalId": signal.id,
                    "kind": signal.kind,
                    "severity": signal.severity,
                    "action": signal.action,
                    "count": "\(signal.count)"
                ]
            )
        )
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

    func openSqlReviewDocument(in workspace: WorkspaceSummary) async {
        selectedWorkspaceID = workspace.id
        let path = workspace.sqlFiles.first?.path
            ?? workspace.documentLinks["delivery"]
            ?? "\(workspace.path)/交付记录.md"
        await loadDocument(path: path)
    }

    func loadDocument(path: String, focusHint: DocumentFocusHint? = nil) async {
        isDocumentLoading = true
        documentLoadingPath = path
        documentLoadError = nil
        documentFocusHint = focusHint
        lastError = nil
        defer {
            isDocumentLoading = false
            if documentLoadingPath == path {
                documentLoadingPath = nil
            }
        }

        do {
            let document: DocumentSnapshot
            do {
                document = try NativeDocumentStore.read(path: path)
            } catch {
                document = try await bridge.readDocument(request: ReadDocumentRequest(path: path))
            }
            documentPreview = document
            await recordWorkspaceAction(
                action: "document.opened",
                target: path,
                summary: "Opened \(document.name)",
                metadata: ["documentPath": path, "documentName": document.name]
            )
        } catch {
            documentPreview = nil
            documentFocusHint = nil
            documentLoadError = DocumentLoadError(path: path, message: error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func clearDocumentPreview() {
        documentPreview = nil
        documentLoadError = nil
        documentFocusHint = nil
        documentLoadingPath = nil
    }

    func createWorkspaceDocument(
        in workspace: WorkspaceSummary,
        documentKey: String,
        relativePath: String,
        documentLabel: String,
        confirmed: Bool
    ) async -> CreateWorkspaceDocumentResponse? {
        isCreatingDocument = true
        lastError = nil
        defer {
            isCreatingDocument = false
        }

        do {
            let response: CreateWorkspaceDocumentResponse
            do {
                response = try NativeDocumentStore.createWorkspaceDocument(
                    workspacePath: workspace.path,
                    documentKey: documentKey,
                    relativePath: relativePath,
                    confirmed: confirmed
                )
                if response.created {
                    await recordWorkspaceAction(
                        action: "document.created",
                        target: response.path,
                        summary: "Created workspace document \(response.relativePath)",
                        metadata: [
                            "workspace": workspace.path,
                            "documentKey": response.documentKey,
                            "relativePath": response.relativePath,
                            "documentPath": response.path
                        ]
                    )
                }
            } catch {
                response = try await bridge.createWorkspaceDocument(
                    request: CreateWorkspaceDocumentRequest(
                        workspacePath: workspace.path,
                        documentKey: documentKey,
                        relativePath: relativePath,
                        confirmed: confirmed,
                        auditRoot: auditRootPath,
                        actor: "Nexus Native"
                    )
                )
            }
            if response.created || response.alreadyExists {
                await refreshFromBridge()
                await loadDocument(path: response.path)
                if lastError == nil {
                    markLocalWriteFeedback(
                        title: response.created
                            ? "文档已创建 / Document created"
                            : "文档已存在 / Document already exists",
                        detail: "\(workspace.name) · \(response.relativePath)。Documents Hub 已重新打开该文档。",
                        workspaceID: workspace.id,
                        workspaceName: workspace.name,
                        documentPath: response.path,
                        documentLabel: "打开 \(documentLabel)",
                        systemImage: response.created ? "doc.badge.plus" : "doc.text"
                    )
                }
            }
            return response
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func demandIntakeStatus(for workspace: WorkspaceSummary) -> DemandIntakeStatus? {
        demandIntakeStatusesByWorkspace[workspace.id]
    }

    func demandIntakeDisplayStatus(for workspace: WorkspaceSummary) -> DemandIntakeStatus {
        demandIntakeStatus(for: workspace) ?? Self.fallbackDemandIntakeStatus(for: workspace)
    }

    func demandIntakeReadiness(for workspace: WorkspaceSummary) -> DemandIntakeReadinessEvidence {
        DemandIntakeReadinessEvidence.resolve(
            status: demandIntakeDisplayStatus(for: workspace),
            workspace: workspace
        )
    }

    func scopeFreezeEvidence(for workspace: WorkspaceSummary) -> ScopeFreezeEvidence {
        ScopeFreezeEvidence.resolve(
            status: demandIntakeDisplayStatus(for: workspace),
            workspace: workspace
        )
    }

    func serviceBranchEvidence(for workspace: WorkspaceSummary) -> ServiceBranchEvidence {
        ServiceBranchEvidence.resolve(workspace: workspace)
    }

    func worktreeSetupEvidence(for workspace: WorkspaceSummary) -> WorktreeSetupEvidence {
        WorktreeSetupEvidence.resolve(workspace: workspace)
    }

    func developmentTaskEvidence(for workspace: WorkspaceSummary) -> DevelopmentTaskEvidence {
        DevelopmentTaskEvidence.resolve(workspace: workspace)
    }

    func deliveryGateEvidence(for workspace: WorkspaceSummary) -> DeliveryGateEvidence {
        DeliveryGateEvidence.resolve(workspace: workspace)
    }

    func mainWorkflowStage(for workspace: WorkspaceSummary) -> WorkspaceMainStage {
        workspace.mainStage(
            demandIntakeStatus: demandIntakeDisplayStatus(for: workspace),
            demandReadiness: demandIntakeReadiness(for: workspace),
            scopeFreeze: scopeFreezeEvidence(for: workspace),
            serviceBranch: serviceBranchEvidence(for: workspace),
            worktreeSetup: worktreeSetupEvidence(for: workspace),
            developmentTasks: developmentTaskEvidence(for: workspace),
            deliveryGate: deliveryGateEvidence(for: workspace),
            archiveGate: archiveGateEvidence(for: workspace),
            demandTaskTransfer: demandTaskTransferPlan(for: workspace)
        )
    }

    func mainWorkflowAcceptanceEvidence(for workspace: WorkspaceSummary) -> MainWorkflowAcceptanceEvidence {
        let worktreeRows = workspaces.flatMap { workspace in
            workspace.services.map { service in
                ServiceWorktreeRowState.resolve(service: service, targetBranch: workspace.branch)
            }
        }
        return MainWorkflowAcceptanceEvidence.resolve(
            stages: workspaces.map { mainWorkflowStage(for: $0) },
            demandReadiness: demandIntakeReadiness(for: workspace),
            developmentTasks: developmentTaskEvidence(for: workspace),
            worktreeRows: worktreeRows,
            deliveryGate: deliveryGateEvidence(for: workspace),
            archiveGate: archiveGateEvidence(for: workspace),
            legacyBoundary: .nativeOnly
        )
    }

    func nativeLocalCoreEvidence() -> NativeLocalCoreEvidence {
        NativeLocalCoreEvidence.resolve(
            bridgeMode: bridgeMode,
            nativeDomains: nativeLocalCoreDomains(),
            partialNativeDomains: nativeLocalCorePartialDomains()
        )
    }

    func nativeLocalCoreDomains() -> Set<NativeLocalCoreDomain> {
        [
            .codexSessions,
            .documentInventory,
            .demandIntake,
            .readiness,
            .settings
        ]
    }

    func nativeLocalCorePartialDomains() -> Set<NativeLocalCoreDomain> {
        [
            .audit,
            .gitWorktreeStatus,
            .searchIndex,
            .widgetSnapshot
        ]
    }

    func nativeDistributionReadinessEvidence(
        repositoryRoot: String = FileManager.default.currentDirectoryPath
    ) -> NativeDistributionReadinessEvidence {
        NativeDistributionReadinessEvidence.resolve(
            repositoryRoot: repositoryRoot,
            m1Ready: workspaces.first.map { mainWorkflowAcceptanceEvidence(for: $0).ready } ?? false,
            m2Ready: nativeLocalCoreEvidence().ready,
            realLifecycleProven: false
        )
    }

    func deliveryRecordWritePlan(for workspace: WorkspaceSummary) -> DeliveryRecordWritePlan {
        DeliveryRecordWritePlan.resolve(
            workspace: workspace,
            gate: deliveryGateEvidence(for: workspace)
        )
    }

    func requestDeliveryRecordWrite(in workspace: WorkspaceSummary) {
        pendingDeliveryRecordWrite = deliveryRecordWritePlan(for: workspace)
        lastError = nil
    }

    func confirmPendingDeliveryRecordWrite(confirmed: Bool) async {
        guard let plan = pendingDeliveryRecordWrite else {
            return
        }
        guard confirmed else {
            lastError = "需要确认后才会写入交付记录。"
            return
        }
        guard plan.canWrite else {
            lastError = plan.summary
            return
        }

        isUpdatingDeliveryRecord = true
        lastError = nil
        defer {
            isUpdatingDeliveryRecord = false
        }

        do {
            try appendMarkdownBlock(plan.appendedMarkdown, toFile: plan.deliveryPath, fallbackHeader: "# 交付记录\n")
            pendingDeliveryRecordWrite = nil
            await recordWorkspaceAction(
                action: "delivery_record.snapshot_appended",
                target: plan.deliveryPath,
                summary: "Appended Delivery Gate snapshot to delivery record",
                metadata: [
                    "deliveryPath": plan.deliveryPath,
                    "status": plan.status.rawValue,
                    "checkCount": "\(plan.items.count)"
                ],
                workspaceOverride: workspaces.first { $0.id == plan.workspaceID }
            )
            await refreshFromBridge()
            focusWorkspace(id: plan.workspaceID)
            markLocalWriteFeedback(
                title: "交付记录已更新 / Delivery record updated",
                detail: "已追加当前 Delivery Gate 快照；SQL、PR/CI、发布或遗留风险结论可继续补在交付记录中。",
                workspaceID: plan.workspaceID,
                workspaceName: plan.workspaceName,
                documentPath: plan.deliveryPath,
                documentLabel: "打开交付记录",
                systemImage: "shippingbox"
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func archiveGateEvidence(
        for workspace: WorkspaceSummary,
        validationPr: ValidationPrEvidence? = nil
    ) -> ArchiveGateEvidence {
        let delivery = deliveryGateEvidence(for: workspace)
        return ArchiveGateEvidence.resolve(
            workspace: workspace,
            deliveryGate: delivery,
            validationPr: validationPr ?? ValidationPrEvidence.resolve(workspace: workspace, deliveryGate: delivery)
        )
    }

    func archiveChecklistWritePlan(for workspace: WorkspaceSummary) -> ArchiveChecklistWritePlan {
        ArchiveChecklistWritePlan.resolve(
            workspace: workspace,
            archiveGate: archiveGateEvidence(for: workspace)
        )
    }

    func requestArchiveChecklistWrite(in workspace: WorkspaceSummary) {
        pendingArchiveChecklistWrite = archiveChecklistWritePlan(for: workspace)
        lastError = nil
    }

    func confirmPendingArchiveChecklistWrite(confirmed: Bool) async {
        guard let plan = pendingArchiveChecklistWrite else {
            return
        }
        guard confirmed else {
            lastError = "需要确认后才会写入归档清单。"
            return
        }
        guard plan.canWrite else {
            lastError = plan.summary
            return
        }

        isUpdatingDeliveryRecord = true
        lastError = nil
        defer {
            isUpdatingDeliveryRecord = false
        }

        do {
            try appendMarkdownBlock(plan.appendedMarkdown, toFile: plan.deliveryPath, fallbackHeader: "# 交付记录\n")
            pendingArchiveChecklistWrite = nil
            await recordWorkspaceAction(
                action: "archive_checklist.snapshot_appended",
                target: plan.deliveryPath,
                summary: "Appended archive checklist to delivery record",
                metadata: [
                    "deliveryPath": plan.deliveryPath,
                    "status": plan.status.rawValue,
                    "itemCount": "\(plan.items.count)"
                ],
                workspaceOverride: workspaces.first { $0.id == plan.workspaceID }
            )
            await refreshFromBridge()
            focusWorkspace(id: plan.workspaceID)
            markLocalWriteFeedback(
                title: "归档清单已写入 / Archive checklist saved",
                detail: "已追加当前归档确认清单；最终生命周期变更仍需通过确认弹窗写回。",
                workspaceID: plan.workspaceID,
                workspaceName: plan.workspaceName,
                documentPath: plan.deliveryPath,
                documentLabel: "打开交付记录",
                systemImage: "archivebox"
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func validationPrWritePlan(for workspace: WorkspaceSummary) -> ValidationPrWritePlan {
        let delivery = deliveryGateEvidence(for: workspace)
        return ValidationPrWritePlan.resolve(
            workspace: workspace,
            evidence: ValidationPrEvidence.resolve(workspace: workspace, deliveryGate: delivery)
        )
    }

    func requestValidationPrWrite(in workspace: WorkspaceSummary) {
        pendingValidationPrWrite = validationPrWritePlan(for: workspace)
        lastError = nil
    }

    func confirmPendingValidationPrWrite(confirmed: Bool) async {
        guard let plan = pendingValidationPrWrite else {
            return
        }
        guard confirmed else {
            lastError = "需要确认后才会写入验证/PR 快照。"
            return
        }
        guard plan.canWrite else {
            lastError = plan.summary
            return
        }

        isUpdatingDeliveryRecord = true
        lastError = nil
        defer {
            isUpdatingDeliveryRecord = false
        }

        do {
            try appendMarkdownBlock(plan.appendedMarkdown, toFile: plan.deliveryPath, fallbackHeader: "# 交付记录\n")
            pendingValidationPrWrite = nil
            await recordWorkspaceAction(
                action: "validation_pr.snapshot_appended",
                target: plan.deliveryPath,
                summary: "Appended validation and PR snapshot to delivery record",
                metadata: [
                    "deliveryPath": plan.deliveryPath,
                    "status": plan.status.rawValue,
                    "checkCount": "\(plan.items.count)"
                ],
                workspaceOverride: workspaces.first { $0.id == plan.workspaceID }
            )
            await refreshFromBridge()
            focusWorkspace(id: plan.workspaceID)
            markLocalWriteFeedback(
                title: "验证/PR 快照已写入 / Validation snapshot saved",
                detail: "已追加当前验证、PR、CI 和发布复核快照；外部 PR/CI 链接仍以人工记录为准。",
                workspaceID: plan.workspaceID,
                workspaceName: plan.workspaceName,
                documentPath: plan.deliveryPath,
                documentLabel: "打开交付记录",
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func demandTaskTransferPlan(for workspace: WorkspaceSummary) -> DemandTaskTransferPlan {
        DemandTaskTransferPlan.resolve(
            workspace: workspace,
            status: demandIntakeDisplayStatus(for: workspace)
        )
    }

    func scopeFreezeWritePlan(for workspace: WorkspaceSummary) -> ScopeFreezeWritePlan {
        ScopeFreezeWritePlan.resolve(
            workspace: workspace,
            evidence: scopeFreezeEvidence(for: workspace)
        )
    }

    func requestScopeFreezeWrite(in workspace: WorkspaceSummary) {
        pendingScopeFreezeWrite = scopeFreezeWritePlan(for: workspace)
        lastError = nil
    }

    func confirmPendingScopeFreezeWrite(confirmed: Bool) async {
        guard let plan = pendingScopeFreezeWrite else {
            return
        }
        guard confirmed else {
            lastError = "需要确认后才会写入 scope.md。"
            return
        }
        guard plan.canWrite else {
            lastError = plan.summary
            return
        }

        isInitializingDemandIntake = true
        lastError = nil
        defer {
            isInitializingDemandIntake = false
        }

        do {
            try appendMarkdownBlock(plan.appendedMarkdown, toFile: plan.scopePath, fallbackHeader: "")
            pendingScopeFreezeWrite = nil
            await recordWorkspaceAction(
                action: "scope.freeze_confirmed",
                target: plan.scopePath,
                summary: "Appended scope freeze confirmation to scope.md",
                metadata: [
                    "scopePath": plan.scopePath,
                    "status": plan.status.rawValue
                ],
                workspaceOverride: workspaces.first { $0.id == plan.workspaceID }
            )
            await refreshFromBridge()
            focusWorkspace(id: plan.workspaceID)
            markLocalWriteFeedback(
                title: "范围已冻结 / Scope frozen",
                detail: "已向 需求/scope.md 追加冻结确认；后续范围变更需要记录原因和影响。",
                workspaceID: plan.workspaceID,
                workspaceName: plan.workspaceName,
                documentPath: plan.scopePath,
                documentLabel: "打开 scope.md",
                systemImage: "scope"
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func requestDemandTaskTransfer(in workspace: WorkspaceSummary) {
        pendingDemandTaskTransfer = demandTaskTransferPlan(for: workspace)
        lastError = nil
    }

    func confirmPendingDemandTaskTransfer(confirmed: Bool) async {
        guard let plan = pendingDemandTaskTransfer else {
            return
        }
        guard confirmed else {
            lastError = "需要确认后才会写入 tasks.md。"
            return
        }
        guard plan.hasTransferableItems else {
            lastError = "没有可转入 root tasks.md 的新需求任务。"
            return
        }

        isUpdatingTask = true
        lastError = nil
        defer {
            isUpdatingTask = false
        }

        do {
            var content = try readOrCreateExecutionTasksDocument(at: plan.executionTasksPath)
            if !content.contains("## Requirement Tasks") {
                if !content.hasSuffix("\n") {
                    content.append("\n")
                }
                content.append("\n## Requirement Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n")
            } else if !content.hasSuffix("\n") {
                content.append("\n")
            }

            for item in plan.transferableItems {
                content.append(item.markdownRow)
                content.append("\n")
            }

            try content.write(toFile: plan.executionTasksPath, atomically: true, encoding: .utf8)
            pendingDemandTaskTransfer = nil
            await recordWorkspaceAction(
                action: "demand_tasks.transferred",
                target: plan.executionTasksPath,
                summary: "Transferred \(plan.transferableItems.count) demand tasks into root tasks.md",
                metadata: [
                    "intakeTasksPath": plan.intakeTasksPath,
                    "executionTasksPath": plan.executionTasksPath,
                    "transferredCount": "\(plan.transferableItems.count)",
                    "duplicateCount": "\(plan.duplicateCount)"
                ],
                workspaceOverride: workspaces.first { $0.id == plan.workspaceID }
            )
            await refreshFromBridge()
            setTaskCenterFilter(.all)
            focusWorkspace(id: plan.workspaceID)
            focusTransferredDemandTask(plan)
            markLocalWriteFeedback(
                title: "需求任务已转入 / Demand tasks transferred",
                detail: "\(plan.transferableItems.count) 个需求点已追加到 root tasks.md，开发任务以 root tasks.md 为准。",
                workspaceID: plan.workspaceID,
                workspaceName: plan.workspaceName,
                documentPath: plan.executionTasksPath,
                documentLabel: "打开 tasks.md",
                systemImage: "checklist"
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func refreshDemandIntakeStatus(for workspace: WorkspaceSummary) async {
        demandIntakeLoadingWorkspaceID = workspace.id
        lastError = nil
        defer {
            if demandIntakeLoadingWorkspaceID == workspace.id {
                demandIntakeLoadingWorkspaceID = nil
            }
        }

        do {
            let status = try NativeDemandIntakeStore.status(workspacePath: workspace.path)
            demandIntakeStatusesByWorkspace[workspace.id] = status
        } catch {
            do {
                let status = try await bridge.readDemandIntakeStatus(
                    request: DemandIntakeStatusRequest(workspacePath: workspace.path)
                )
                demandIntakeStatusesByWorkspace[workspace.id] = status
            } catch {
                lastError = error.localizedDescription
                demandIntakeStatusesByWorkspace[workspace.id] = Self.fallbackDemandIntakeStatus(for: workspace)
            }
        }
    }

    func initializeDemandIntake(
        in workspace: WorkspaceSummary,
        demandName: String,
        lanhuLink: String,
        notes: String,
        confirmed: Bool
    ) async -> InitializeDemandIntakeResponse? {
        isInitializingDemandIntake = true
        lastError = nil
        defer {
            isInitializingDemandIntake = false
        }

        do {
            let response: InitializeDemandIntakeResponse
            do {
                response = try NativeDemandIntakeStore.initialize(
                    workspacePath: workspace.path,
                    demandName: demandName,
                    lanhuLink: lanhuLink,
                    notes: notes,
                    confirmed: confirmed
                )
                await recordWorkspaceAction(
                    action: "demand_intake.initialized",
                    target: response.status.directoryPath,
                    summary: "Initialized demand intake files for \(demandName)",
                    metadata: [
                        "workspacePath": workspace.path,
                        "demandName": demandName,
                        "lanhuLink": lanhuLink,
                        "createdFiles": response.createdFiles.joined(separator: ","),
                        "missingCount": "\(response.status.missingCount)"
                    ]
                )
            } catch {
                response = try await bridge.initializeDemandIntake(
                    request: InitializeDemandIntakeRequest(
                        workspacePath: workspace.path,
                        demandName: demandName,
                        lanhuLink: lanhuLink,
                        notes: notes,
                        confirmed: confirmed,
                        auditRoot: auditRootPath,
                        actor: "Nexus Native"
                    )
                )
            }
            demandIntakeStatusesByWorkspace[workspace.id] = response.status
            await refreshFromBridge()
            markLocalWriteFeedback(
                title: response.createdFiles.isEmpty
                    ? "需求预检已就绪 / Demand intake ready"
                    : "需求预检已初始化 / Demand intake created",
                detail: "\(workspace.name) · \(response.createdFiles.count) files created · \(response.status.missingCount) missing。",
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                documentPath: response.status.files.first?.path ?? response.status.directoryPath,
                documentLabel: "打开需求确认卡",
                systemImage: "text.badge.checkmark"
            )
            return response
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func demandIntakePrompt(
        for workspace: WorkspaceSummary,
        demandName: String,
        lanhuLink: String,
        notes: String
    ) -> String {
        let cleanDemandName = demandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? workspace.name
            : demandName.trimmingCharacters(in: .whitespacesAndNewlines)
        let materialLines = [
            normalizedDemandIntakeLine(label: "蓝湖链接", value: lanhuLink),
            normalizedDemandIntakeLine(label: "补充说明", value: notes)
        ].compactMap { $0 }
        let materials = materialLines.isEmpty ? "待补充" : materialLines.joined(separator: "\n")

        return [
            "使用 $lanhu-demand-intake。",
            "",
            "## 工作区",
            "- 当前工作区: \(workspace.path)",
            "- 需求名称: \(cleanDemandName)",
            "- 需求目录: \(workspace.path)/需求",
            "- 目标分支: \(workspace.branch)",
            "",
            "## 蓝湖材料",
            materials,
            "",
            "## 已绑定 Codex 会话",
            codexSessionHandoffLines(for: workspace).joined(separator: "\n"),
            "",
            "## 处理要求",
            "- 先整理 需求/requirement.md 和 需求/questions.md。",
            "- 在 需求/scope.md 冻结本次开发范围。",
            "- 在 需求/tasks.md 创建未完成需求列表，按 P0/P1/P2 标记优先级。",
            "- 在 P0 问题清零前不要开发代码。",
            "- 不要覆盖已有人工内容；缺口请追加或标注待确认。"
        ].joined(separator: "\n")
    }

    func copyDemandIntakePrompt(
        for workspace: WorkspaceSummary,
        demandName: String,
        lanhuLink: String,
        notes: String,
        openCodex: Bool
    ) async {
        let prompt = demandIntakePrompt(
            for: workspace,
            demandName: demandName,
            lanhuLink: lanhuLink,
            notes: notes
        )
        let cleanDemandName = demandName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? workspace.name
            : demandName.trimmingCharacters(in: .whitespacesAndNewlines)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        let rawURL = codexURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultCodexURL
            : codexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let action = openCodex ? "demand_intake_prompt.opened" : "demand_intake_prompt.copied"
        if openCodex {
            if let url = URL(string: rawURL) {
                NSWorkspace.shared.open(url)
                markCodexHandoff(
                    title: "Codex 已打开 / Intake copied",
                    detail: "\(workspace.name) · 需求预检提示词已复制到剪贴板。",
                    systemImage: "text.badge.checkmark",
                    sectionTitle: "需求预检 / Demand intake",
                    clipboardLabel: "$lanhu-demand-intake prompt is on the clipboard"
                )
            } else {
                lastError = "Invalid Codex URL: \(rawURL)"
                markCodexHandoff(
                    title: "预检提示已复制 / URL needs review",
                    detail: "\(workspace.name) · Codex URL 无效，请在 Settings 中修正。",
                    systemImage: "exclamationmark.triangle",
                    sectionTitle: "需求预检 / Demand intake",
                    clipboardLabel: "$lanhu-demand-intake prompt is on the clipboard"
                )
            }
        } else {
            markCodexHandoff(
                title: "预检提示词已复制 / Intake copied",
                detail: "\(workspace.name) · $lanhu-demand-intake 已放入剪贴板。",
                systemImage: "doc.on.clipboard",
                sectionTitle: "需求预检 / Demand intake",
                clipboardLabel: "$lanhu-demand-intake prompt is on the clipboard"
            )
        }

        await recordWorkspaceAction(
            action: action,
            target: "\(workspace.path)/需求",
            summary: openCodex ? "Copied demand intake prompt and opened Codex" : "Copied demand intake prompt",
            metadata: [
                "tool": "Codex",
                "codexUrl": openCodex ? rawURL : "",
                "demandName": cleanDemandName,
                "hasLanhuLink": "\(!lanhuLink.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)",
                "hasNotes": "\(!notes.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)"
            ],
            workspaceOverride: workspace
        )
    }

    private func normalizedDemandIntakeLine(label: String, value: String) -> String? {
        let cleanValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanValue.isEmpty else {
            return nil
        }
        return "\(label): \(cleanValue)"
    }

    static func fallbackDemandIntakeStatus(for workspace: WorkspaceSummary) -> DemandIntakeStatus {
        let workspacePath = workspace.path.hasSuffix("/")
            ? String(workspace.path.dropLast())
            : workspace.path
        let directoryPath = "\(workspacePath)/需求"
        let files = [
            ("requirement", "需求确认卡", "requirement.md"),
            ("questions", "待确认问题", "questions.md"),
            ("scope", "开发范围", "scope.md"),
            ("tasks", "需求列表", "tasks.md"),
            ("delivery", "需求交付", "delivery.md")
        ].map { item in
            let (key, label, filename) = item
            return DemandIntakeFileStatus(
                key: key,
                label: label,
                filename: filename,
                path: "\(directoryPath)/\(filename)",
                exists: false
            )
        }
        return DemandIntakeStatus(
            directoryPath: directoryPath,
            exists: false,
            ready: false,
            missingCount: files.count,
            files: files
        )
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

    func workspaceTaskHandoffPrompt(for task: WorkspaceTask, in workspace: WorkspaceSummary) async -> String {
        let request = WorkspaceTaskHandoffPromptRequest(
            workspaceName: workspace.name,
            workspaceFolder: workspace.folder,
            workspacePath: workspace.path,
            targetBranch: workspace.branch,
            sourceRoot: sourceReposRoot,
            task: WorkspaceTaskSnapshot(
                id: task.id,
                title: task.title,
                status: task.status,
                detail: task.detail,
                priority: task.priority,
                source: task.source,
                sourceEventId: task.sourceEventID,
                sourceLine: task.sourceLine
            )
        )
        func appendCodexSessions(to prompt: String) -> String {
            [
                prompt,
                "",
                "## 已绑定 Codex 会话",
                codexSessionHandoffLines(for: workspace).joined(separator: "\n")
            ].joined(separator: "\n")
        }
        do {
            let response = try await bridge.workspaceTaskHandoffPrompt(request: request)
            return appendCodexSessions(to: response.prompt)
        } catch {
            return appendCodexSessions(to: request.fallbackPrompt)
        }
    }

    func openTaskSource(_ task: WorkspaceTask, in workspace: WorkspaceSummary) async {
        let path = workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md"
        let payload = taskSourceLocatorPayload(for: task, in: workspace, path: path)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)

        await loadDocument(
            path: path,
            focusHint: DocumentFocusHint(
                path: path,
                line: task.sourceLine,
                title: task.title,
                detail: "tasks.md · \(task.status) · \(task.priorityLabel)"
            )
        )
        markCodexHandoff(
            title: "任务定位已复制 / Task locator copied",
            detail: "\(workspace.name) · \(task.title) · \(task.sourceLineLabel)",
            systemImage: "text.line.first.and.arrowtriangle.forward",
            sectionTitle: "任务定位 / Task locator",
            clipboardLabel: "Task locator is on the clipboard",
            guidance: "Documents Hub 已打开 tasks.md；使用上方行号和剪贴板定位信息复查源任务。"
        )
        await recordWorkspaceAction(
            action: "workspace_task.source_located",
            target: path,
            summary: "Opened tasks.md and copied task source locator",
            metadata: [
                "taskId": task.id,
                "taskTitle": task.title,
                "taskStatus": task.status,
                "taskSource": task.source,
                "sourceLine": task.sourceLine.map(String.init) ?? "unknown"
            ],
            workspaceOverride: workspace
        )
    }

    func openTaskInCodex(_ task: WorkspaceTask, in workspace: WorkspaceSummary) async {
        let prompt = await workspaceTaskHandoffPrompt(for: task, in: workspace)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        let rawURL = codexURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultCodexURL
            : codexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: rawURL) {
            NSWorkspace.shared.open(url)
            markCodexHandoff(
                title: "Codex 已打开 / Task copied",
                detail: "\(workspace.name) · \(task.title) · 任务上下文已复制到剪贴板。",
                systemImage: "checklist"
            )
        } else {
            lastError = "Invalid Codex URL: \(rawURL)"
            markCodexHandoff(
                title: "任务上下文已复制 / URL needs review",
                detail: "\(workspace.name) · \(task.title) · Codex URL 无效，请在 Settings 中修正。",
                systemImage: "exclamationmark.triangle"
            )
        }

        await recordWorkspaceAction(
            action: "codex_task_handoff.opened",
            target: "\(workspace.path)/tasks.md",
            summary: "Copied task handoff and opened Codex for \(task.title)",
            metadata: [
                "tool": "Codex",
                "codexUrl": rawURL,
                "taskId": task.id,
                "taskTitle": task.title,
                "taskStatus": task.status,
                "taskSource": task.source
            ],
            workspaceOverride: workspace
        )
    }

    private func taskSourceLocatorPayload(for task: WorkspaceTask, in workspace: WorkspaceSummary, path: String) -> String {
        [
            "Nexus task source locator",
            "- Workspace: \(workspace.name)",
            "- Folder: \(workspace.folder)",
            "- tasks.md: \(path)",
            "- Line: \(task.sourceLine.map(String.init) ?? "unknown")",
            "- Task ID: \(task.id)",
            "- Title: \(task.title)",
            "- Status: \(task.status)",
            "- Priority: \(task.priority)",
            "- Source: \(task.source)",
            "- Source event: \(task.sourceEventID ?? "none")",
            "- Detail: \(task.detail.isEmpty ? "none" : task.detail)"
        ].joined(separator: "\n")
    }

    func openWorktreeSetupResultInCodex(_ response: SetupWorktreesResponse, in workspace: WorkspaceSummary) async {
        let prompt = worktreeSetupResultHandoffPrompt(response, in: workspace)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        let rawURL = codexURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultCodexURL
            : codexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        if let url = URL(string: rawURL) {
            NSWorkspace.shared.open(url)
            markCodexHandoff(
                title: "Codex 已打开 / Worktree result copied",
                detail: "\(workspace.name) · \(response.created.count) created · \(response.failed.count) failed",
                systemImage: "arrow.triangle.branch"
            )
        } else {
            lastError = "Invalid Codex URL: \(rawURL)"
            markCodexHandoff(
                title: "worktree 结果已复制 / URL needs review",
                detail: "\(workspace.name) · Codex URL 无效，请在 Settings 中修正。",
                systemImage: "exclamationmark.triangle"
            )
        }

        await recordWorkspaceAction(
            action: "codex_worktree_setup.opened",
            target: workspace.path,
            summary: "Copied worktree setup result and opened Codex",
            metadata: [
                "tool": "Codex",
                "codexUrl": rawURL,
                "targetBranch": response.targetBranch,
                "created": "\(response.created.count)",
                "skipped": "\(response.skipped.count)",
                "failed": "\(response.failed.count)"
            ],
            workspaceOverride: workspace
        )
    }

    private func worktreeSetupResultHandoffPrompt(_ response: SetupWorktreesResponse, in workspace: WorkspaceSummary) -> String {
        let failedGuidance = response.failed.isEmpty
            ? "worktree 创建没有失败项。先运行本地检查，确认分支、dirty 状态和风险后再继续开发。"
            : "优先处理 failed 服务，检查源仓库、目标分支、本地路径或 git 输出后，再重新执行 worktree 创建。"

        return [
            "请根据 Nexus worktree 创建结果继续处理当前工作区。",
            "",
            "## 工作区",
            "- 名称: \(workspace.name)",
            "- 文件夹: \(workspace.folder)",
            "- 路径: \(workspace.path)",
            "- 目标分支: \(response.targetBranch)",
            "- Source repos root: \(sourceReposRoot)",
            "",
            "## worktree 创建结果",
            "- Created: \(response.created.count)",
            "- Skipped: \(response.skipped.count)",
            "- Failed: \(response.failed.count)",
            "",
            "### Created",
            worktreeSetupResultLines(response.created),
            "",
            "### Skipped",
            worktreeSetupResultLines(response.skipped),
            "",
            "### Failed",
            worktreeSetupResultLines(response.failed),
            "",
            "## Nexus 恢复建议",
            worktreeSetupRecoveryLines(response),
            "",
            "## 本地命令摘要",
            response.command.isEmpty ? "- Nexus 未返回命令摘要。" : response.command,
            "",
            "## 下一步要求",
            "- \(failedGuidance)",
            "- 不要删除 worktree、reset、clean 或切换源仓库分支，除非用户明确要求。",
            "- 继续前读取 requirements.md、acceptance.md、changes.md、workspace.md、STATUS.md、branches.md、services.md、tasks.md 和交付记录。",
            "- 如果后续修改代码、SQL、配置或业务逻辑，同步更新 changes.md 和交付记录。",
            "- 处理完成后回到 Nexus 刷新，并运行本地检查。"
        ].joined(separator: "\n")
    }

    private func worktreeSetupRecoveryLines(_ response: SetupWorktreesResponse) -> String {
        let actions = WorktreeSetupRecoveryAction.actions(for: response)
        guard !actions.isEmpty else {
            return "- none"
        }
        return actions.map { action in
            ([
                "- \(action.title)",
                action.serviceName.map { "  - service: \($0)" },
                "  - detail: \(action.detail)",
                "  - status: \(action.status.rawValue)"
            ].compactMap { $0 }).joined(separator: "\n")
        }.joined(separator: "\n")
    }

    private func worktreeSetupResultLines(_ results: [WorktreeSetupResult]) -> String {
        guard !results.isEmpty else {
            return "- none"
        }

        return results.map { result in
            [
                "- \(result.service): \(result.status)",
                "  - detail: \(result.detail)",
                "  - source: \(result.sourcePath)",
                "  - worktree: \(result.worktreePath)"
            ].joined(separator: "\n")
        }.joined(separator: "\n")
    }

    func copyAgentEventCodexContext(_ event: AgentEvent) async {
        let prompt = await agentEventHandoffPrompt(for: event)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        let target = event.workspaceFolder ?? event.id
        markCodexHandoff(
            title: "Agent 事件上下文已复制 / Event copied",
            detail: "\(event.title) · \(target)",
            systemImage: "doc.on.clipboard"
        )

        await recordAgentEventCodexAction(
            event,
            action: "codex_agent_event.copied",
            target: target,
            summary: "Copied Agent Event Codex context",
            metadata: [:]
        )
    }

    func copyAgentEventActionResponse(label: String, payload: String, for event: AgentEvent) async {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)

        let target = event.workspaceFolder ?? event.id
        markCodexHandoff(
            title: "Agent 回应已复制 / Response copied",
            detail: "\(event.title) · \(label)",
            systemImage: "text.bubble",
            sectionTitle: "Agent 回应 / Agent response",
            clipboardLabel: "Response template is on the clipboard",
            guidance: "先复核模板内容，再粘贴给当前 Agent 或 Codex；Nexus 不会自动批准或执行命令。"
        )

        await recordAgentEventCodexAction(
            event,
            action: "agent_event_response.copied",
            target: target,
            summary: "Copied Agent Event response template",
            metadata: [
                "responseLabel": label,
                "responseLength": "\(payload.count)"
            ]
        )
    }

    func openAgentEventInCodex(_ event: AgentEvent) async {
        let prompt = await agentEventHandoffPrompt(for: event)
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(prompt, forType: .string)

        let rawURL = codexURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Self.defaultCodexURL
            : codexURL.trimmingCharacters(in: .whitespacesAndNewlines)
        let target = event.workspaceFolder ?? event.id
        if let url = URL(string: rawURL) {
            NSWorkspace.shared.open(url)
            markCodexHandoff(
                title: "Codex 已打开 / Agent event copied",
                detail: "\(event.title) · Agent 事件上下文已复制到剪贴板。",
                systemImage: "point.3.connected.trianglepath.dotted"
            )
        } else {
            lastError = "Invalid Codex URL: \(rawURL)"
            markCodexHandoff(
                title: "Agent 事件已复制 / URL needs review",
                detail: "\(event.title) · Codex URL 无效，请在 Settings 中修正。",
                systemImage: "exclamationmark.triangle"
            )
        }

        await recordAgentEventCodexAction(
            event,
            action: "codex_agent_event.opened",
            target: target,
            summary: "Copied Agent Event context and opened Codex",
            metadata: [
                "tool": "Codex",
                "codexUrl": rawURL
            ]
        )
    }

    func clearCodexHandoffFeedback() {
        codexHandoffFeedback = nil
    }

    func clearLocalWriteFeedback() {
        localWriteFeedback = nil
    }

    func clearWorkspaceLinkFeedback() {
        workspaceLinkFeedback = nil
    }

    func clearLastError() {
        lastError = nil
    }

    private func markCodexHandoff(
        title: String,
        detail: String,
        systemImage: String,
        sectionTitle: String = "剪贴板反馈 / Clipboard",
        clipboardLabel: String = "Context is on the clipboard",
        guidance: String = "需要继续时可粘贴剪贴板内容；如果 Codex 没有自动带入，也可以直接粘贴。"
    ) {
        codexHandoffFeedback = CodexHandoffFeedback(
            title: title,
            detail: detail,
            timestamp: Self.activityTimestamp(),
            systemImage: systemImage,
            sectionTitle: sectionTitle,
            clipboardLabel: clipboardLabel,
            guidance: guidance
        )
    }

    private func markLocalWriteFeedback(
        title: String,
        detail: String,
        workspaceID: WorkspaceSummary.ID,
        workspaceName: String,
        documentPath: String,
        documentLabel: String,
        systemImage: String
    ) {
        localWriteFeedback = LocalWriteFeedback(
            title: title,
            detail: detail,
            timestamp: Self.activityTimestamp(),
            workspaceID: workspaceID,
            workspaceName: workspaceName,
            documentPath: documentPath,
            documentLabel: documentLabel,
            systemImage: systemImage
        )
    }

    private func appendMarkdownBlock(
        _ block: String,
        toFile path: String,
        fallbackHeader: String
    ) throws {
        var content = (try? String(contentsOfFile: path, encoding: .utf8)) ?? fallbackHeader
        if !content.isEmpty, !content.hasSuffix("\n") {
            content.append("\n")
        }
        content.append(block)
        if !content.hasSuffix("\n") {
            content.append("\n")
        }
        try content.write(toFile: path, atomically: true, encoding: .utf8)
    }

    private func markWorkspaceLinkFeedback(
        title: String,
        detail: String,
        workspace: WorkspaceSummary,
        link: String,
        systemImage: String
    ) {
        workspaceLinkFeedback = WorkspaceLinkFeedback(
            title: title,
            detail: detail,
            timestamp: Self.activityTimestamp(),
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            link: link,
            systemImage: systemImage
        )
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
            if response.appended || response.alreadyExists {
                await refreshFromBridge()
                focusAgentTask(sourceEventID: response.sourceEventId)
                markLocalWriteFeedback(
                    title: response.appended
                        ? "Agent 任务已写入 / Agent task saved"
                        : "Agent 任务已存在 / Agent task already exists",
                    detail: "\(response.title)。Task Center 已可按 Agent 筛选继续定位、延期、完成或交接 Codex。",
                    workspaceID: workspace.id,
                    workspaceName: workspace.name,
                    documentPath: response.path,
                    documentLabel: "打开 tasks.md",
                    systemImage: response.appended ? "text.badge.plus" : "doc.text"
                )
            }
            return response
        } catch {
            lastError = error.localizedDescription
            return nil
        }
    }

    func confirmPendingTaskStatusUpdate(confirmed: Bool) async {
        guard let update = pendingTaskStatusUpdate else {
            return
        }
        isUpdatingTask = true
        lastError = nil
        defer {
            isUpdatingTask = false
        }

        do {
            let response = try await bridge.updateWorkspaceTask(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: update.workspacePath,
                    taskId: update.taskID,
                    status: update.nextStatus,
                    confirmed: confirmed,
                    auditRoot: auditRootPath,
                    actor: "Nexus Native"
                )
            )
            if response.updated {
                pendingTaskStatusUpdate = nil
                await refreshFromBridge()
                if let nextTask = nextTaskCenterItem(
                    preferredWorkspaceID: update.workspaceID,
                    excludingTaskID: update.taskID
                ) {
                    if !selectedTaskCenterFilter.matches(nextTask) {
                        setTaskCenterFilter(.all)
                    }
                    selectTaskCenterItem(nextTask)
                }
                if lastError == nil {
                    markLocalWriteFeedback(
                        title: "任务状态已写回 / Task updated",
                        detail: "\(response.task.title): \(response.previousStatus) -> \(response.task.status)。Task Center 已聚焦下一项；没有下一项时可进入交付焦点。",
                        workspaceID: update.workspaceID,
                        workspaceName: update.workspaceName,
                        documentPath: response.path,
                        documentLabel: "打开 tasks.md",
                        systemImage: "checkmark.circle"
                    )
                }
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func confirmPendingLifecycleStatusUpdate(confirmed: Bool) async {
        guard let update = pendingLifecycleStatusUpdate else {
            return
        }
        isUpdatingLifecycle = true
        lastError = nil
        defer {
            isUpdatingLifecycle = false
        }

        do {
            let response = try await bridge.updateWorkspaceLifecycle(
                request: UpdateWorkspaceLifecycleRequest(
                    workspacePath: update.workspacePath,
                    state: update.nextState,
                    focus: update.focus,
                    nextAction: update.nextAction,
                    confirmed: confirmed,
                    auditRoot: auditRootPath,
                    actor: "Nexus Native"
                )
            )
            if response.updated {
                pendingLifecycleStatusUpdate = nil
                await refreshFromBridge()
                if lastError == nil {
                    markLocalWriteFeedback(
                        title: "生命周期已写回 / Lifecycle updated",
                        detail: update.requiresLocalCheckAfterWrite
                            ? "\(update.currentLabel) -> \(update.nextLabel)。恢复后请立即运行本地检查，并复查分支、worktree、任务、风险和交付记录。"
                            : "\(update.currentLabel) -> \(update.nextLabel)。workspace.md 和 STATUS.md 已更新，Workflow 焦点已重新计算。",
                        workspaceID: update.workspaceID,
                        workspaceName: update.workspaceName,
                        documentPath: response.statusDocumentPath,
                        documentLabel: "打开 STATUS.md",
                        systemImage: "arrow.triangle.2.circlepath.circle"
                    )
                }
            }
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
            setWorkspaceFilter(.all)
            selectedWorkspaceID = response.folder
            documentPreview = nil
            documentFocusHint = nil
            await refreshFromBridge()
            selectedWorkspaceID = response.folder
            await loadDocument(
                path: "\(response.path)/handoff.md",
                focusHint: DocumentFocusHint(
                    path: "\(response.path)/handoff.md",
                    line: nil,
                    title: "Workspace created",
                    detail: "新工作区已选中，先从 handoff.md 进入后续服务、分支和 worktree 检查。"
                )
            )
        } catch {
            lastError = error.localizedDescription
        }
    }

    func dismissCreatedWorkspaceFollowUp() {
        lastCreatedWorkspace = nil
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
        let evidence = worktreeSetupEvidence(for: workspace)
        return evidence.mutationPolicy.canRequestConfirmation
    }

    func setupMissingWorktrees(for workspace: WorkspaceSummary, confirmed: Bool) async {
        lastError = nil
        lastWorktreeSetupResponse = nil

        let evidence = worktreeSetupEvidence(for: workspace)
        let mutationPolicy = evidence.mutationPolicy
        let missingServices = evidence.missingServices
        guard !missingServices.isEmpty else {
            lastError = "当前工作区没有缺失的 worktree。"
            return
        }

        guard evidence.branchConfirmed else {
            lastError = "目标分支仍未确认，不能创建 worktree。"
            return
        }
        guard evidence.missingSourceServices.isEmpty else {
            lastError = "存在源仓库不可用的服务：\(evidence.missingSourceServices.joined(separator: ", "))。"
            return
        }
        guard evidence.branchMismatchServices.isEmpty else {
            lastError = "存在分支不一致的 worktree：\(evidence.branchMismatchServices.joined(separator: ", "))。"
            return
        }
        guard mutationPolicy.canRequestConfirmation else {
            lastError = mutationPolicy.summary
            return
        }
        guard mutationPolicy.canRun(afterConfirmation: confirmed) else {
            lastError = "需要在确认 sheet 勾选本地 git 写入确认后，才会执行 worktree 创建。"
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
                    services: mutationPolicy.allowedServices,
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
        NativeSearchIndexStore.fallbackResults(matching: query, in: workspaces)
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

    private var activeSignalWorkspaces: [WorkspaceSummary] {
        workspaces.filter { !$0.isArchived }
    }

    private func workspaceForAutomationSignal(_ signal: LocalAutomationSignal) -> WorkspaceSummary? {
        switch signal.action {
        case "review-risk":
            return firstWorkspaceWithRisk()
        case "update-delivery":
            return firstWorkspaceWithSqlDeliveryIssue()
                ?? firstWorkspaceWithDeliveryIssue()
        case "review-worktrees":
            return firstWorkspaceWithMissingWorktrees()
        case "review-dirty-services":
            return firstWorkspaceWithDirtyServices()
        case "review-branches":
            return firstWorkspaceWithBranchIssue()
        case "review-tasks":
            return firstWorkspaceWithHighPriorityTask()
                ?? firstWorkspaceWithOpenTask()
        default:
            return selectedWorkspace
        }
    }

    private func firstWorkspaceWithRisk() -> WorkspaceSummary? {
        activeSignalWorkspaces.first { workspace in
            workspace.riskLevel == .high || workspace.riskLevel == .medium || !workspace.risks.isEmpty
        }
    }

    private func firstWorkspaceWithSqlDeliveryIssue() -> WorkspaceSummary? {
        activeSignalWorkspaces.first { workspace in
            workspaceHasSqlDeliveryIssue(workspace)
        }
    }

    private func firstWorkspaceWithDeliveryIssue() -> WorkspaceSummary? {
        activeSignalWorkspaces.first { workspace in
            workspaceHasDeliveryRecordIssue(workspace) || workspaceHasSqlDeliveryIssue(workspace)
        }
    }

    private func workspaceHasDeliveryRecordIssue(_ workspace: WorkspaceSummary) -> Bool {
        workspace.risks.contains { risk in
            let normalized = "\(risk.title) \(risk.detail)".lowercased()
            return normalized.contains("交付记录") || normalized.contains("delivery")
        } || workspace.healthChecks.contains { check in
            check.id == "delivery-record" && !Self.healthStatusIsPassing(check.status)
        }
    }

    private func workspaceHasSqlDeliveryIssue(_ workspace: WorkspaceSummary) -> Bool {
        workspace.risks.contains { risk in
            let normalized = "\(risk.title) \(risk.detail)".lowercased()
            return normalized.contains("sql") || normalized.contains("sql 变更")
        } || workspace.healthChecks.contains { check in
            (check.id == "sql-directory" || check.action == "sql")
                && !Self.healthStatusIsPassing(check.status)
        }
    }

    private func workspaceMissingDeliveryRecord(_ workspace: WorkspaceSummary) -> Bool {
        workspace.healthChecks.contains { check in
            check.id == "delivery-record"
                && !Self.healthStatusIsPassing(check.status)
                && check.detail.contains("缺少")
        }
    }

    private func deliveryDocumentPath(for workspace: WorkspaceSummary) -> String {
        workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md"
    }

    private func branchesDocumentPath(for workspace: WorkspaceSummary) -> String {
        workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md"
    }

    private static func healthStatusIsPassing(_ status: String) -> Bool {
        let normalized = status.lowercased()
        return normalized == "pass" || normalized == "ok" || normalized == "ready"
    }

    private func firstWorkspaceWithMissingWorktrees() -> WorkspaceSummary? {
        activeSignalWorkspaces.first { workspace in
            workspace.services.contains { !$0.worktreeExists }
        }
    }

    private func firstWorkspaceWithDirtyServices() -> WorkspaceSummary? {
        activeSignalWorkspaces.first { workspace in
            !dirtyServices(in: workspace).isEmpty
        }
    }

    private func dirtyServices(in workspace: WorkspaceSummary) -> [ServiceStatus] {
        workspace.services.filter(Self.serviceHasDirtyGit)
    }

    private static func serviceHasDirtyGit(_ service: ServiceStatus) -> Bool {
        let normalized = "\(service.gitSummary) \(service.worktree)".lowercased()
        return normalized.contains("dirty")
            || normalized.contains("未提交")
            || normalized.contains("有改动")
            || normalized.contains("不是 git")
            || normalized.contains("not git")
            || normalized.contains("检查失败")
            || normalized.contains("failed")
    }

    private func firstWorkspaceWithBranchIssue() -> WorkspaceSummary? {
        activeSignalWorkspaces.first { workspace in
            workspaceHasBranchIssue(workspace)
        }
    }

    private func workspaceHasBranchIssue(_ workspace: WorkspaceSummary) -> Bool {
        workspace.risks.contains { risk in
            let normalized = "\(risk.title) \(risk.detail)".lowercased()
            return normalized.contains("分支不一致") || normalized.contains("branch mismatch")
        } || workspace.healthChecks.contains { check in
            check.id == "branch-alignment" && !Self.healthStatusIsPassing(check.status)
        }
    }

    private func firstWorkspaceWithHighPriorityTask() -> WorkspaceSummary? {
        activeSignalWorkspaces.first { workspace in
            workspace.tasks.contains { task in
                task.isActive && task.priorityRank == 0
            }
        }
    }

    private func firstWorkspaceWithOpenTask() -> WorkspaceSummary? {
        activeSignalWorkspaces.first { workspace in
            workspace.tasks.contains(where: \.isActive)
        }
    }

    private func highPriorityTaskCount(from response: LocalAutomationCheckResponse?) -> Int {
        response?.highPriorityTaskCount ?? 0
    }

    private func recordSettingsProfileAudit(action: String, target: String, summary: String) async {
        await recordNativeAuditEvent(
            AuditEventInput(
                actor: "Nexus Native",
                action: action,
                target: target,
                summary: summary,
                metadata: [
                    "path": target,
                    "workspacesRoot": workspaceRoot,
                    "sourceReposRoot": sourceReposRoot,
                    "docsRoot": docsRoot,
                    "codexUrl": codexURL,
                    "refreshIntervalSeconds": "\(refreshIntervalSeconds)"
                ]
            )
        )
    }

    @discardableResult
    private func persistCodexSessionLinks(
        _ links: [CodexSessionLink],
        for workspace: WorkspaceSummary,
        action: String,
        summary: String,
        feedbackTitle: String?,
        feedbackDetail: String?,
        metadata: [String: String]
    ) async -> Bool {
        do {
            try Self.writeCodexSessionLinks(links, for: workspace)
            codexSessionLinksByWorkspace[workspace.id] = links

            if let feedbackTitle, let feedbackDetail {
                markLocalWriteFeedback(
                    title: feedbackTitle,
                    detail: feedbackDetail,
                    workspaceID: workspace.id,
                    workspaceName: workspace.name,
                    documentPath: codexSessionLinksPath(for: workspace),
                    documentLabel: "Codex sessions",
                    systemImage: "link.badge.plus"
                )
            }

            await recordWorkspaceAction(
                action: action,
                target: codexSessionLinksPath(for: workspace),
                summary: summary,
                metadata: metadata,
                workspaceOverride: workspace
            )
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func recordWorkspaceAction(
        action: String,
        target: String,
        summary: String,
        metadata: [String: String] = [:],
        workspaceOverride: WorkspaceSummary? = nil
    ) async {
        guard let workspace = workspaceOverride ?? selectedWorkspace else { return }
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

        await recordNativeAuditEvent(
            AuditEventInput(
                actor: "Nexus Native",
                action: action,
                target: target,
                summary: summary,
                metadata: eventMetadata
            )
        )
    }

    private func recordAgentEventCodexAction(
        _ event: AgentEvent,
        action: String,
        target: String,
        summary: String,
        metadata: [String: String]
    ) async {
        var eventMetadata = metadata
        eventMetadata["eventId"] = event.id
        eventMetadata["eventTitle"] = event.title
        eventMetadata["eventKind"] = event.kind
        eventMetadata["eventSeverity"] = event.severity
        eventMetadata["eventSource"] = event.source
        eventMetadata["sessionId"] = event.sessionId
        if let workspaceFolder = event.workspaceFolder {
            eventMetadata["workspaceFolder"] = workspaceFolder
        }

        if let workspace = workspaces.first(where: { Self.agentEvent(event, matches: $0) }) {
            await recordWorkspaceAction(
                action: action,
                target: target,
                summary: summary,
                metadata: eventMetadata,
                workspaceOverride: workspace
            )
            return
        }

        await recordNativeAuditEvent(
            AuditEventInput(
                actor: "Nexus Native",
                action: action,
                target: target,
                summary: summary,
                metadata: eventMetadata
            )
        )
    }

    static func workspaces(
        _ workspaces: [WorkspaceSummary],
        applyingNativeAuditEvents events: [AuditEvent]
    ) -> [WorkspaceSummary] {
        guard !events.isEmpty else { return workspaces }
        return workspaces.map { workspace in
            let workspaceEvents = events.filter { event in
                let folder = event.metadata["workspaceFolder"] ?? event.metadata["folder"]
                return folder == workspace.folder || folder == workspace.id
            }
            return workspaceEvents.reversed().reduce(workspace) { currentWorkspace, event in
                currentWorkspace.prepending(
                    activity: ActivityEvent(
                        time: event.timestamp,
                        title: auditActivityTitle(event.action),
                        detail: "Nexus Native · \(event.summary)"
                    )
                )
            }
        }
    }

    private func recordNativeAuditEvent(_ event: AuditEventInput) async {
        do {
            _ = try NativeAuditEventStore.append(auditRoot: auditRootPath, event: event)
        } catch {
            lastError = "Native audit failed: \(error.localizedDescription)"
        }

        _ = try? await bridge.appendAuditEvent(
            request: AppendAuditEventRequest(
                auditRoot: auditRootPath,
                event: event
            )
        )
    }

    private static func auditActivityTitle(_ action: String) -> String {
        switch action {
        case "document.opened":
            return "文档已打开 / Document opened"
        case "document.created":
            return "文档已创建 / Document created"
        case "codex.opened":
            return "Codex 已打开 / Codex opened"
        case "codex_instruction.copied":
            return "Codex 指令已复制 / Instruction copied"
        case "codex_task_handoff.opened":
            return "任务 Codex 已打开 / Task Codex opened"
        case "codex_task_handoff.copied":
            return "任务上下文已复制 / Task handoff copied"
        case "codex_worktree_setup.opened":
            return "worktree 结果已交接 / Worktree result opened"
        case "codex_validation_pr_handoff.opened":
            return "验证 PR 已交接 / Validation PR handoff"
        case "workspace_task.source_located":
            return "任务来源已定位 / Task source located"
        case "codex_agent_event.copied":
            return "Agent 事件已复制 / Agent event copied"
        case "codex_agent_event.opened":
            return "Agent 事件 Codex 已打开 / Agent event opened"
        case "agent_event_response.copied":
            return "Agent 回应已复制 / Agent response copied"
        case "codex_session_link.bound":
            return "Codex 会话已绑定 / Session bound"
        case "codex_session_link.updated":
            return "Codex 会话已更新 / Session updated"
        case "codex_session_link.opened":
            return "Codex 会话已打开 / Session opened"
        case "codex_session_link.copied":
            return "Codex 会话已复制 / Session copied"
        case "codex_session_link.deleted":
            return "Codex 会话已删除 / Session deleted"
        case "demand_intake_prompt.copied":
            return "需求预检已复制 / Intake copied"
        case "demand_intake_prompt.opened":
            return "需求预检已打开 / Intake opened"
        case "risk_review_handoff.copied":
            return "风险复核已复制 / Risk review copied"
        case "settings_profile.exported":
            return "设置已导出 / Settings exported"
        case "settings_profile.imported":
            return "设置已导入 / Settings imported"
        case "workspace.finder.opened":
            return "Finder 已打开 / Finder opened"
        case "workspace.terminal.opened":
            return "Terminal 已打开 / Terminal opened"
        case "workspace.ide.opened":
            return "IDE 已打开 / IDE opened"
        case "workspace.deeplink.opened":
            return "工作区深链已打开 / Deep link opened"
        case "workspace.deeplink.copied":
            return "工作区链接已复制 / Deep link copied"
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

    private static var profileEncoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static func validatedSettings(
        from profile: NativeSettingsProfile
    ) throws -> NativeSettingsProfileSettings {
        guard profile.app == "Nexus" else {
            throw SettingsProfileError.invalid("配置文件不是 Nexus Profile")
        }
        guard profile.schemaVersion == 1 else {
            throw SettingsProfileError.invalid("暂不支持该配置版本")
        }

        let workspacesRoot = try requiredProfilePath(profile.settings.workspacesRoot, label: "workspacesRoot")
        let sourceReposRoot = try requiredProfilePath(profile.settings.sourceReposRoot, label: "sourceReposRoot")
        let docsRoot = try requiredProfilePath(profile.settings.docsRoot, label: "docsRoot")
        let codexUrl = profile.settings.codexUrl.trimmingCharacters(in: .whitespacesAndNewlines)
        let ideUrl = profile.settings.ideUrl?.trimmingCharacters(in: .whitespacesAndNewlines)

        return NativeSettingsProfileSettings(
            workspacesRoot: workspacesRoot,
            sourceReposRoot: sourceReposRoot,
            docsRoot: docsRoot,
            codexUrl: codexUrl.isEmpty ? defaultCodexURL : codexUrl,
            ideUrl: ideUrl?.isEmpty == false ? ideUrl : defaultIDEURL,
            refreshIntervalSeconds: normalizedRefreshInterval(profile.settings.refreshIntervalSeconds)
        )
    }

    private static func requiredProfilePath(_ value: String, label: String) throws -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw SettingsProfileError.invalid("配置文件缺少 \(label)")
        }
        return trimmed
    }

    private static func workspaceFolder(fromDeepLink url: URL) -> String? {
        guard url.scheme?.lowercased() == "nexus" else { return nil }

        if url.host?.lowercased() == "workspace" {
            let pathFolder = url.path
                .split(separator: "/")
                .first
                .map(String.init)?
                .removingPercentEncoding
            if let pathFolder, !pathFolder.isEmpty {
                return pathFolder
            }
        }

        if let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryFolder = components.queryItems?.first(where: { $0.name == "workspace" || $0.name == "folder" })?.value?
            .trimmingCharacters(in: .whitespacesAndNewlines),
           !queryFolder.isEmpty {
            return queryFolder
        }

        return nil
    }

    private static func buildNativeEnvironmentHealth(
        workspacesRoot: String,
        sourceReposRoot: String,
        docsRoot: String
    ) -> NativeEnvironmentHealth {
        let pathChecks = [
            environmentPathCheck(key: "workspacesRoot", label: "工作区目录", rawPath: workspacesRoot),
            environmentPathCheck(key: "sourceReposRoot", label: "源仓库目录", rawPath: sourceReposRoot),
            environmentPathCheck(key: "docsRoot", label: "交付文档目录", rawPath: docsRoot)
        ]
        let toolChecks = [
            environmentToolCheck(key: "git", label: "Git", command: "git", arguments: ["--version"])
        ]
        let workspaceCount = countChildDirectories(
            at: localFileURL(for: workspacesRoot),
            ignoredName: "dashboard"
        )
        let sourceRepoCount = countGitRepositories(at: localFileURL(for: sourceReposRoot))

        var blockers: [String] = []
        var warnings: [String] = []

        for check in pathChecks {
            if !check.exists {
                blockers.append("\(check.label)不存在: \(check.path)")
            } else if !check.isDirectory {
                blockers.append("\(check.label)不是目录: \(check.path)")
            } else if !check.writable {
                warnings.append("\(check.label)可能不可写: \(check.path)")
            }
        }

        for check in toolChecks where !check.available {
            blockers.append("\(check.label)不可用: \(check.summary)")
        }

        if sourceRepoCount == 0 {
            warnings.append("源仓库目录下暂未识别到 git 服务仓库")
        }

        return NativeEnvironmentHealth(
            generatedAt: ISO8601DateFormatter().string(from: Date()),
            ready: blockers.isEmpty,
            pathChecks: pathChecks,
            toolChecks: toolChecks,
            workspaceCount: workspaceCount,
            sourceRepoCount: sourceRepoCount,
            blockers: blockers,
            warnings: warnings
        )
    }

    private static func environmentPathCheck(
        key: String,
        label: String,
        rawPath: String
    ) -> NativeEnvironmentPathCheck {
        let url = localFileURL(for: rawPath)
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        let writable = exists && isDirectory.boolValue && canWriteMarker(in: url)
        let summary: String
        if !exists {
            summary = "目录不存在"
        } else if !isDirectory.boolValue {
            summary = "路径存在但不是目录"
        } else if writable {
            summary = "目录可用"
        } else {
            summary = "目录存在但写入检查未通过"
        }

        return NativeEnvironmentPathCheck(
            key: key,
            label: label,
            path: rawPath,
            exists: exists,
            isDirectory: isDirectory.boolValue,
            writable: writable,
            summary: summary
        )
    }

    private static func canWriteMarker(in directoryURL: URL) -> Bool {
        let markerURL = directoryURL.appendingPathComponent(".nexus-write-check")
        do {
            try "ok".write(to: markerURL, atomically: true, encoding: .utf8)
            try? FileManager.default.removeItem(at: markerURL)
            return true
        } catch {
            return false
        }
    }

    private static func environmentToolCheck(
        key: String,
        label: String,
        command: String,
        arguments: [String]
    ) -> NativeEnvironmentToolCheck {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [command] + arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            let output = String(
                data: outputPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let error = String(
                data: errorPipe.fileHandleForReading.readDataToEndOfFile(),
                encoding: .utf8
            )?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return NativeEnvironmentToolCheck(
                key: key,
                label: label,
                available: process.terminationStatus == 0,
                summary: output.isEmpty ? error : output
            )
        } catch {
            return NativeEnvironmentToolCheck(
                key: key,
                label: label,
                available: false,
                summary: error.localizedDescription
            )
        }
    }

    private static func countChildDirectories(at rootURL: URL, ignoredName: String?) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return entries.filter { entry in
            guard entry.lastPathComponent != ignoredName else { return false }
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
        }.count
    }

    private static func countGitRepositories(at rootURL: URL) -> Int {
        guard let entries = try? FileManager.default.contentsOfDirectory(
            at: rootURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        ) else {
            return 0
        }

        return entries.filter { entry in
            let values = try? entry.resourceValues(forKeys: [.isDirectoryKey])
            return values?.isDirectory == true
                && FileManager.default.fileExists(
                    atPath: entry.appendingPathComponent(".git").path
                )
        }.count
    }

    private static func loadCodexSessionLinks(
        for workspaces: [WorkspaceSummary]
    ) -> [WorkspaceSummary.ID: [CodexSessionLink]] {
        Dictionary(uniqueKeysWithValues: workspaces.map { workspace in
            (workspace.id, readCodexSessionLinks(for: workspace))
        })
    }

    private static func readCodexSessionLinks(for workspace: WorkspaceSummary) -> [CodexSessionLink] {
        NativeCodexSessionStore.load(workspacePath: workspace.path)
    }

    private static func writeCodexSessionLinks(
        _ links: [CodexSessionLink],
        for workspace: WorkspaceSummary
    ) throws {
        _ = try NativeCodexSessionStore.write(links, workspacePath: workspace.path)
    }

    private static func codexSessionLinksURL(for workspace: WorkspaceSummary) -> URL {
        NativeCodexSessionStore.storeURL(workspacePath: workspace.path)
    }

    private static func normalizedCodexSessionURL(_ rawURL: String) -> String? {
        let trimmed = rawURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let components = URLComponents(string: trimmed),
              let scheme = components.scheme,
              !scheme.isEmpty
        else {
            return nil
        }
        return trimmed
    }

    private static func agentEvent(_ event: AgentEvent, matches workspace: WorkspaceSummary) -> Bool {
        let workspaceCandidates = [
            event.workspaceFolder,
            event.metadata["workspaceFolder"],
            event.metadata["folder"],
            event.metadata["workspace"],
            event.metadata["workspacePath"],
            event.metadata["path"]
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return workspaceCandidates.contains { candidate in
            candidate == workspace.folder
                || candidate == workspace.path
                || (!workspace.path.isEmpty && candidate.contains(workspace.path))
                || (!workspace.folder.isEmpty && candidate.contains("/\(workspace.folder)"))
        }
    }

    private static func codexSessionURLCandidates(from event: AgentEvent) -> [(title: String, url: String)] {
        var candidates = event.metadata
            .sorted { $0.key < $1.key }
            .compactMap { key, value -> (title: String, url: String)? in
                guard isLikelyCodexSessionURLCandidate(key: key, value: value, source: event.source),
                      let url = normalizedCodexSessionURL(value)
                else {
                    return nil
                }
                return (suggestedCodexSessionTitle(for: key, event: event), url)
            }

        if isLikelyCodexSessionURLCandidate(key: "sessionId", value: event.sessionId, source: event.source),
           let url = normalizedCodexSessionURL(event.sessionId) {
            candidates.append((suggestedCodexSessionTitle(for: "sessionId", event: event), url))
        }

        var seenURLs: Set<String> = []
        return candidates.filter { candidate in
            guard !seenURLs.contains(candidate.url) else { return false }
            seenURLs.insert(candidate.url)
            return true
        }
    }

    private static func isLikelyCodexSessionURLCandidate(
        key: String,
        value: String,
        source: String
    ) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              !scheme.isEmpty
        else {
            return false
        }

        let normalizedKey = key.lowercased()
        let normalizedSource = source.lowercased()
        let normalizedHost = components.host?.lowercased() ?? ""
        let isLinkKey = normalizedKey.contains("url")
            || normalizedKey.contains("link")
        let isSessionKey = normalizedKey.contains("codex")
            || normalizedKey.contains("deeplink")
            || normalizedKey.contains("deep_link")
            || normalizedKey.contains("deep")
            || normalizedKey.contains("session")
            || normalizedKey.contains("thread")
            || normalizedKey.contains("conversation")

        return scheme.contains("codex")
            || normalizedKey.contains("codex") && (isLinkKey || isSessionKey)
            || normalizedHost.contains("codex") && (isLinkKey || isSessionKey)
            || normalizedSource.contains("codex") && isSessionKey
    }

    private static func suggestedCodexSessionTitle(for key: String, event: AgentEvent) -> String {
        let cleanKey = key
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
        let trimmedTitle = event.title.trimmingCharacters(in: .whitespacesAndNewlines)
        let eventTitle = trimmedTitle.isEmpty ? event.sessionId : trimmedTitle
        return "\(event.source) · \(cleanKey) · \(eventTitle)"
    }

    private static func localFileURL(for rawPath: String) -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded: String
        if trimmed == "~" {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path
        } else if trimmed.hasPrefix("~/") {
            expanded = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(trimmed.dropFirst(2)))
                .path
        } else {
            expanded = trimmed
        }
        return URL(fileURLWithPath: expanded)
    }

    private static var terminalApplicationURL: URL? {
        let candidates = [
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/Utilities/Terminal.app"
        ]
        return candidates
            .map { URL(fileURLWithPath: $0) }
            .first { FileManager.default.fileExists(atPath: $0.path) }
    }

    private func requestAutomationNotificationAuthorization() async -> (granted: Bool, status: String) {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
                let status: String
                if let error {
                    status = "Failed: \(error.localizedDescription)"
                } else {
                    status = granted ? "Authorized" : "Denied"
                }
                continuation.resume(returning: (granted, status))
            }
        }
    }

    private func notificationSettings() async -> UNNotificationSettings {
        await withCheckedContinuation { continuation in
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                continuation.resume(returning: settings)
            }
        }
    }

    private func sendAutomationNotificationIfNeeded(_ response: LocalAutomationCheckResponse) async {
        guard areAutomationNotificationsEnabled else { return }
        guard automationNotificationMinimumStatus.allows(response.status) else { return }
        guard let notificationSignals = automationNotificationSignals(from: response), !notificationSignals.isEmpty else {
            return
        }
        guard canSendAutomationNotification(now: Date()) else {
            automationNotificationStatus = "Throttled"
            return
        }

        let settings = await notificationSettings()
        automationNotificationStatus = Self.notificationStatusLabel(settings.authorizationStatus)
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            areAutomationNotificationsEnabled = false
            defaults.set(false, forKey: DefaultsKey.areAutomationNotificationsEnabled)
            return
        }

        let content = UNMutableNotificationContent()
        content.title = response.status == "attention"
            ? "Nexus needs attention"
            : "Nexus review needed"
        content.body = notificationSignals
            .prefix(3)
            .map { "\($0.title): \($0.count)" }
            .joined(separator: " · ")
        content.sound = .default
        content.userInfo = [
            "generatedAt": response.generatedAt,
            "status": response.status,
            "riskCount": response.riskCount,
            "openTaskCount": response.openTaskCount
        ]

        let request = UNNotificationRequest(
            identifier: "nexus-automation-\(response.generatedAt)",
            content: content,
            trigger: nil
        )
        do {
            try await UNUserNotificationCenter.current().add(request)
            lastAutomationNotificationAt = response.generatedAt
            defaults.set(response.generatedAt, forKey: DefaultsKey.lastAutomationNotificationAt)
        } catch {
            automationNotificationStatus = "Failed: \(error.localizedDescription)"
        }
    }

    private static func normalizedAutomationInterval(_ value: Int) -> Int {
        guard value > 0 else { return defaultAutomationIntervalMinutes }
        return supportedAutomationIntervals.min { left, right in
            abs(left - value) < abs(right - value)
        } ?? defaultAutomationIntervalMinutes
    }

    private static func normalizedRefreshInterval(_ value: Int) -> Int {
        max(3, value)
    }

    private func automationNotificationSignals(
        from response: LocalAutomationCheckResponse
    ) -> [LocalAutomationSignal]? {
        let enabledKinds = automationNotificationSignalKinds
        guard !enabledKinds.isEmpty else { return nil }
        let signals = response.signals.filter { signal in
            enabledKinds.contains(signal.kind)
        }
        return signals
    }

    private func canSendAutomationNotification(now: Date) -> Bool {
        guard let lastAutomationNotificationAt,
              let lastDate = ISO8601DateFormatter().date(from: lastAutomationNotificationAt) else {
            return true
        }
        let cooldownSeconds = TimeInterval(max(1, automationNotificationCooldownMinutes) * 60)
        return now.timeIntervalSince(lastDate) >= cooldownSeconds
    }

    private static var defaultAutomationNotificationSignalKinds: [String] {
        AutomationNotificationSignalKind.allCases.map(\.rawValue)
    }

    private static func normalizedNotificationCooldown(_ value: Int) -> Int {
        guard value > 0 else { return defaultNotificationCooldownMinutes }
        return supportedNotificationCooldownMinutes.min { left, right in
            abs(left - value) < abs(right - value)
        } ?? defaultNotificationCooldownMinutes
    }

    private static func notificationStatusLabel(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "Not requested"
        case .denied:
            return "Denied"
        case .authorized:
            return "Authorized"
        case .provisional:
            return "Provisional"
        case .ephemeral:
            return "Ephemeral"
        @unknown default:
            return "Unknown"
        }
    }
}

struct CreateWorkspaceDraft: Equatable {
    var name: String
    var folder: String
    var services: [String]
    var targetBranch: String
    var confirmed: Bool
}
