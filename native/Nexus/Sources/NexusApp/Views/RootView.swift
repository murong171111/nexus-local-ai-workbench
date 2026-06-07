import AppKit
import NexusBridge
import SwiftUI
import UniformTypeIdentifiers

private func copyToPasteboard(_ payload: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(payload, forType: .string)
}

private func localCheckSummaryPayload(
    title: String,
    actor: String?,
    check: LocalAutomationCheckResponse,
    workspace: WorkspaceSummary? = nil
) -> String {
    var lines = [
        title,
        "- Actor: \(actor ?? "Nexus")",
        "- Status: \(check.status)",
        "- Summary: \(check.summary)",
        "- Generated at: \(check.generatedAt)",
        "- Workspaces: \(check.workspaceCount) total, \(check.archivedWorkspaceCount) archived",
        "- Risks: \(check.riskCount)",
        "- Delivery issues: \(check.deliveryIssueCount)",
        "- Branch issues: \(check.branchMismatchCount)",
        "- Active tasks: \(check.openTaskCount) (\(check.highPriorityTaskCount) high priority)",
        "- Worktree issues: \(check.missingWorktreeCount) missing, \(check.dirtyServiceCount) dirty"
    ]

    if let workspace {
        lines.append("- Workspace: \(workspace.name)")
        lines.append("- Path: \(workspace.path)")
    }

    return lines.joined(separator: "\n")
}

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCreateWorkspacePresented = false
    @State private var isSettingsPresented = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(
                isCreateWorkspacePresented: $isCreateWorkspacePresented,
                isSettingsPresented: $isSettingsPresented
            )
                .frame(width: 264)

            Divider()

            VStack(spacing: 0) {
                TopCommandBar()
                Divider()

                WorkspaceListView(
                    isCreateWorkspacePresented: $isCreateWorkspacePresented,
                    isSettingsPresented: $isSettingsPresented
                )
            }

            Divider()

            InspectorView(
                isCreateWorkspacePresented: $isCreateWorkspacePresented,
                isSettingsPresented: $isSettingsPresented
            )
                .frame(width: 328)
        }
        .background(NexusPalette.background)
        .task {
            await appState.refreshFromBridge()
        }
        .task {
            await appState.refreshAutomationNotificationStatus()
        }
        .task(id: appState.automationScheduleToken) {
            await appState.runAutomationScheduleLoop()
        }
        .sheet(isPresented: $isCreateWorkspacePresented) {
            CreateWorkspaceSheet()
                .environmentObject(appState)
        }
        .sheet(isPresented: $isSettingsPresented) {
            SettingsView()
                .environmentObject(appState)
        }
        .sheet(item: $appState.pendingWorktreeSetupWorkspace) { workspace in
            WorktreeSetupSheet(workspace: workspace)
                .environmentObject(appState)
        }
        .sheet(item: $appState.pendingTaskStatusUpdate) { update in
            TaskStatusUpdateSheet(update: update)
                .environmentObject(appState)
        }
        .sheet(item: $appState.pendingLifecycleStatusUpdate) { update in
            LifecycleStatusUpdateSheet(update: update)
                .environmentObject(appState)
        }
        .sheet(item: $appState.selectedAgentEvent) { event in
            AgentEventDetailSheet(event: event)
                .environmentObject(appState)
        }
    }
}

private struct TopCommandBar: View {
    @EnvironmentObject private var appState: AppState
    @FocusState private var searchFocused: Bool

    var body: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .topLeading) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(.secondary)
                    TextField("搜索工作区、文档、SQL、任务...", text: $appState.query)
                        .textFieldStyle(.plain)
                        .focused($searchFocused)
                        .onSubmit {
                            appState.openSelectedSearchResult()
                        }
                        .task(id: appState.query) {
                            try? await Task.sleep(nanoseconds: 160_000_000)
                            guard !Task.isCancelled else { return }
                            await appState.searchForCurrentQuery()
                        }
                }
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(NexusPalette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if appState.hasSearchQuery {
                    NativeSearchPopover()
                        .offset(y: 42)
                        .zIndex(20)
                }
            }
            .frame(maxWidth: 560)
            .zIndex(10)
            .onMoveCommand { direction in
                guard searchFocused else { return }
                switch direction {
                case .up:
                    appState.moveSearchSelection(-1)
                case .down:
                    appState.moveSearchSelection(1)
                default:
                    break
                }
            }
            .onExitCommand {
                guard searchFocused else { return }
                appState.clearSearch()
            }

            Button {
                Task {
                    await appState.rebuildSearchIndex()
                }
            } label: {
                Label("Index", systemImage: "externaldrive.badge.magnifyingglass")
            }
            .buttonStyle(.bordered)

            Button {
                Task {
                    await appState.refreshFromBridge()
                }
            } label: {
                Label(appState.isLoading ? "Loading" : "Refresh", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .disabled(appState.isLoading)

            Button {
                Task {
                    await appState.runLocalAutomationCheck()
                }
            } label: {
                Label(
                    appState.isRunningAutomationCheck ? "Checking" : "Checks",
                    systemImage: "checklist.checked"
                )
            }
            .buttonStyle(.bordered)
            .disabled(appState.isRunningAutomationCheck)

            Spacer()

            Label(appState.bridgeMode, systemImage: "point.3.connected.trianglepath.dotted")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text(appState.selectedWorkspace?.folder ?? "No workspace")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(NexusPalette.background)
    }
}

private struct NativeSearchPopover: View {
    @EnvironmentObject private var appState: AppState

    private var groupedResults: [SearchResultGroup] {
        appState.groupedSearchResults
    }

    private var orderedResults: [SearchResult] {
        appState.orderedSearchResults
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "externaldrive.badge.magnifyingglass")
                    .foregroundStyle(NexusPalette.accent)
                Text("本地索引搜索 / Local index")
                    .font(.caption.weight(.semibold))
                SearchStateBadge()
                Spacer()
                if let summary = appState.searchIndexSummary {
                    Text("\(summary.workspaceCount) ws / \(summary.documentCount) docs")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                } else {
                    Text("preview fallback")
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(NexusPalette.panel)

            SearchScopeBar()
                .padding(.horizontal, 10)
                .padding(.bottom, 9)
                .background(NexusPalette.panel)

            Divider()

            if appState.isSearching {
                HStack(spacing: 8) {
                    ProgressView()
                        .controlSize(.small)
                    Text("正在搜索本地索引...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .padding(14)
            } else if orderedResults.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Text("没有命中文档索引")
                        .font(.subheadline.weight(.medium))
                    Text("工作区列表仍会按名称、服务、分支和风险元数据过滤。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(groupedResults) { group in
                            VStack(alignment: .leading, spacing: 5) {
                                Text(group.label)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textCase(.uppercase)

                                ForEach(group.results, id: \.stableID) { result in
                                    let index = orderedResults.firstIndex(of: result) ?? 0
                                    NativeSearchResultRow(
                                        result: result,
                                        isSelected: index == appState.selectedSearchResultIndex
                                    ) {
                                        appState.openSearchResult(result)
                                    }
                                }
                            }
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 360)

                if let selectedResult = appState.selectedSearchResult {
                    Divider()
                    SearchResultPreview(
                        result: selectedResult,
                        workspace: appState.workspace(for: selectedResult)
                    ) {
                        appState.openSearchResult(selectedResult)
                    }
                }
            }

            Divider()

            HStack {
                if let searchError = appState.searchError {
                    Text(searchError)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else {
                    Text("↑↓ 选择")
                    Text("Enter 打开")
                    Text("Esc 清空")
                }
                Spacer()
            }
            .font(.system(size: 10, design: .monospaced))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
        .frame(width: 520)
        .background(NexusPalette.panel)
        .overlay {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .stroke(NexusPalette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        .shadow(color: Color.black.opacity(0.14), radius: 28, x: 0, y: 18)
    }
}

private struct SearchScopeBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 6) {
            ForEach(SearchScope.allCases) { scope in
                Button {
                    appState.setSearchScope(scope)
                } label: {
                    VStack(spacing: 1) {
                        Text(scope.label)
                            .font(.caption.weight(.semibold))
                        Text(scope.subtitle)
                            .font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
                    .background(scope == appState.selectedSearchScope ? NexusPalette.selected : Color.clear)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                scope == appState.selectedSearchScope ? NexusPalette.accent.opacity(0.28) : NexusPalette.border,
                                lineWidth: 1
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

private struct SearchResultPreview: View {
    let result: SearchResult
    let workspace: WorkspaceSummary?
    let openAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("结果上下文 / Result context")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(result.documentName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(result.documentPath)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Button(action: openAction) {
                    Label("Open", systemImage: "arrow.turn.down.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            Text(result.snippet.isEmpty ? "No snippet available." : result.snippet)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(3)

            if let workspace {
                HStack(spacing: 10) {
                    PreviewMetric(label: "Branch", value: workspace.branch)
                    PreviewMetric(label: "Services", value: "\(workspace.services.count)")
                    PreviewMetric(label: "Risk", value: workspace.riskLevel.label)
                }

                if let firstRisk = workspace.risks.first {
                    Label {
                        Text(firstRisk.detail)
                            .font(.caption)
                            .lineLimit(2)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle")
                            .foregroundStyle(NexusPalette.warning)
                    }
                    .padding(8)
                    .background(NexusPalette.warning.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }

                ActivityTimelineView(events: Array(workspace.activities.prefix(3)), compact: true)
            }
        }
        .padding(12)
        .background(NexusPalette.preview)
    }
}

private struct PreviewMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(NexusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct SearchStateBadge: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var label: String {
        if appState.isSearching {
            return "searching"
        }
        if appState.searchError != nil {
            return "fallback"
        }
        if appState.searchIndexSummary != nil {
            return "ready"
        }
        return "preview"
    }

    private var color: Color {
        if appState.searchError != nil {
            return NexusPalette.warning
        }
        if appState.searchIndexSummary != nil {
            return NexusPalette.success
        }
        return NexusPalette.accent
    }
}

private struct NativeSearchResultRow: View {
    let result: SearchResult
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 7) {
                    Text(result.displayKind)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(result.kind == "sql" ? NexusPalette.warning : NexusPalette.accent)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(NexusPalette.badge)
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                    Text(result.workspaceName)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                    Text(result.documentName)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Spacer()
                }

                Text(result.snippet.isEmpty ? result.documentPath : result.snippet)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(10)
            .background(isSelected ? NexusPalette.selected : Color.clear)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(isSelected ? NexusPalette.accent.opacity(0.35) : Color.clear, lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isCreateWorkspacePresented: Bool
    @Binding var isSettingsPresented: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Image(systemName: "point.3.connected.trianglepath.dotted")
                                .foregroundStyle(NexusPalette.accent)
                            Text("Nexus")
                                .font(.title3.weight(.semibold))
                        }
                        Text("Local AI Workbench")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Agent 状态 / Status")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 6) {
                            Label(appState.agentStatus.title, systemImage: "circle.fill")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(appState.lastError == nil ? NexusPalette.success : NexusPalette.danger)
                            Text(appState.agentStatus.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                            if appState.lastError != nil {
                                Text("右侧操作反馈包含恢复动作 / See operation feedback")
                                    .font(.caption2)
                                    .foregroundStyle(NexusPalette.danger)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .padding(12)
                        .background(NexusPalette.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    }

                    AgentInboxSidebarView(
                        summary: appState.agentInboxSummary,
                        openEvent: { event in
                            appState.selectedAgentEvent = event
                        }
                    )

                    if appState.agentWorkflowSummary.shouldShow {
                        AgentWorkflowBridgeView(
                            summary: appState.agentWorkflowSummary,
                            focusAgentTasks: {
                                appState.focusAgentTasks()
                            }
                        )
                    }

                    sidebarTaskCenter
                    sidebarWidgetSnapshot
                    sidebarPinnedWorkspaces
                    sidebarFilters
                }
                .padding(18)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                SetupReadinessSidebarCard(
                    isCreateWorkspacePresented: $isCreateWorkspacePresented,
                    isSettingsPresented: $isSettingsPresented
                )

                Button {
                    isCreateWorkspacePresented = true
                } label: {
                    Label("New Workspace", systemImage: "plus")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderedProminent)

                Button {
                    isSettingsPresented = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal, 18)
            .padding(.top, 12)
            .padding(.bottom, 18)
        }
        .background(NexusPalette.sidebar)
    }

    @ViewBuilder
    private var sidebarTaskCenter: some View {
            if appState.taskCenterTotalCount > 0 || recentTaskWriteback != nil {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("任务中心 / Tasks")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(appState.taskCenterItems.count)/\(appState.taskCenterTotalCount)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(NexusPalette.accent)
                    }

                    if let recentTaskWriteback {
                        TaskCenterWritebackHintView(feedback: recentTaskWriteback)
                            .environmentObject(appState)
                    }

                    if appState.taskCenterTotalCount > 0 {
                        TaskCenterFilterBar()
                    }

                    if appState.taskCenterTotalCount == 0 {
                        Text("当前没有开放任务，最近写回结果会保留在上方，方便复查。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NexusPalette.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else if appState.taskCenterItems.isEmpty {
                        Text("当前筛选暂无任务")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(NexusPalette.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                    } else {
                        ForEach(Array(appState.taskCenterItems.prefix(4))) { item in
                            TaskCenterSidebarRow(
                                item: item,
                                isFocused: item.id == appState.focusedTaskCenterItemID,
                                selectAction: {
                                    appState.selectTaskCenterItem(item)
                                },
                                openDocumentAction: {
                                    openTaskDocument(item)
                                },
                                completeAction: {
                                    appState.requestTaskStatusUpdate(item, status: "已完成")
                                },
                                deferAction: {
                                    appState.requestTaskStatusUpdate(item, status: "延期")
                                },
                                codexAction: {
                                    copyTaskHandoff(item)
                                }
                            )
                        }
                    }
                }
            }
    }

    @ViewBuilder
    private var sidebarWidgetSnapshot: some View {
            if let snapshot = appState.widgetSnapshot {
                VStack(alignment: .leading, spacing: 8) {
                    Text("小组件摘要 / Widget")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 10) {
                        SidebarMetric(label: "WS", value: snapshot.workspaceCount)
                        SidebarMetric(label: "Risk", value: snapshot.riskCount)
                        SidebarMetric(label: "Dirty", value: snapshot.dirtyServiceCount)
                    }
                    Text(snapshot.activeWorkspace ?? "No active workspace")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(appState.widgetSnapshotStorageStatus)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .padding(12)
                .background(NexusPalette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
    }

    @ViewBuilder
    private var sidebarPinnedWorkspaces: some View {
            if !appState.pinnedWorkspaces.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("置顶工作区 / Pinned")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(appState.pinnedWorkspaces) { workspace in
                        Button {
                            appState.select(workspace)
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "pin.fill")
                                    .font(.caption)
                                    .foregroundStyle(NexusPalette.accent)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(workspace.name)
                                        .font(.caption.weight(.semibold))
                                        .lineLimit(1)
                                    Text(workspace.folder)
                                        .font(.system(size: 10, design: .monospaced))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                Spacer()
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 8)
                            .background(workspace.id == appState.selectedWorkspace?.id ? NexusPalette.selected : NexusPalette.panel)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
    }

    private var sidebarFilters: some View {
            VStack(alignment: .leading, spacing: 8) {
                Text("筛选 / Filters")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(WorkspaceFilter.allCases) { filter in
                    Button {
                        appState.setWorkspaceFilter(filter)
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: filter.systemImage)
                                .frame(width: 16)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(filter.rawValue)
                                Text(filter.subtitle)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("\(appState.workspaceCount(for: filter))")
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(filter == appState.selectedFilter ? NexusPalette.accent : .secondary)
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(filter == appState.selectedFilter ? NexusPalette.selected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .disabled(appState.workspaceCount(for: filter) == 0 && filter != appState.selectedFilter)
                }

                if appState.hasWorkspaceListScope {
                    Button {
                        appState.resetWorkspaceListScope()
                    } label: {
                        Label("清空筛选 / Reset", systemImage: "line.3.horizontal.decrease.circle")
                            .font(.caption.weight(.medium))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                    .help("清空搜索和工作区筛选 / Clear search and workspace filter")
                }
            }
    }

    private func copyTaskHandoff(_ item: TaskCenterItem) {
        guard let workspace = appState.workspaces.first(where: { $0.id == item.workspaceID }) else {
            return
        }
        appState.selectTaskCenterItem(item)
        Task {
            await appState.openTaskInCodex(item.task, in: workspace)
        }
    }

    private func openTaskDocument(_ item: TaskCenterItem) {
        guard let workspace = appState.workspaces.first(where: { $0.id == item.workspaceID }) else {
            return
        }
        appState.selectTaskCenterItem(item)
        Task {
            await appState.openTaskSource(item.task, in: workspace)
        }
    }

    private var recentTaskWriteback: LocalWriteFeedback? {
        guard let feedback = appState.localWriteFeedback else {
            return nil
        }
        return feedback.documentPath.hasSuffix("/tasks.md") ? feedback : nil
    }
}

private struct CreateWorkspaceSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var folder = ""
    @State private var servicesText = ""
    @State private var targetBranch = ""
    @State private var confirmed = false
    @State private var selectedServiceNames: Set<String> = []
    @State private var didEditFolder = false
    @State private var serviceQuery = ""

    private var manualServices: [String] {
        servicesText
            .split { character in
                character.isWhitespace || [",", "，", "、", ";", "；"].contains(String(character))
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private var services: [String] {
        Array(selectedServiceNames.union(Set(manualServices)))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var availableSourceRepositories: [SourceRepositorySnapshot] {
        appState.sourceRepositories.filter(\.isGit)
    }

    private var filteredSourceRepositories: [SourceRepositorySnapshot] {
        let query = serviceQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return availableSourceRepositories
        }
        return availableSourceRepositories.filter { repository in
            repository.name.localizedCaseInsensitiveContains(query)
                || repository.branch.localizedCaseInsensitiveContains(query)
                || repository.summary.localizedCaseInsensitiveContains(query)
        }
    }

    private var canCreate: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !folder.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && preflightCanCreate
            && confirmed
            && !appState.isCreatingWorkspace
    }

    private var normalizedFolder: String {
        folder.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var normalizedTargetBranch: String {
        targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var folderNameIsValid: Bool {
        guard !normalizedFolder.isEmpty else {
            return false
        }
        guard normalizedFolder != "." && normalizedFolder != ".." else {
            return false
        }
        return normalizedFolder.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\")) == nil
    }

    private var workspaceRootPath: String {
        NSString(
            string: appState.workspaceRoot.trimmingCharacters(in: .whitespacesAndNewlines)
        ).expandingTildeInPath
    }

    private var workspaceRootStatus: (exists: Bool, isDirectory: Bool) {
        guard !workspaceRootPath.isEmpty else {
            return (false, false)
        }
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: workspaceRootPath, isDirectory: &isDirectory)
        return (exists, isDirectory.boolValue)
    }

    private var workspaceRootCanCreate: Bool {
        guard !workspaceRootPath.isEmpty else {
            return false
        }
        let status = workspaceRootStatus
        return !status.exists || status.isDirectory
    }

    private var destinationPath: String {
        guard !workspaceRootPath.isEmpty else {
            return "\(appState.workspaceRoot)/\(normalizedFolder)"
        }
        return URL(fileURLWithPath: workspaceRootPath)
            .appendingPathComponent(normalizedFolder.isEmpty ? "workspace" : normalizedFolder)
            .path
    }

    private var destinationExists: Bool {
        FileManager.default.fileExists(atPath: destinationPath)
    }

    private var sourceRepositoryNames: Set<String> {
        Set(availableSourceRepositories.map(\.name))
    }

    private var missingSelectedSourceRepositories: [String] {
        services
            .filter { !sourceRepositoryNames.contains($0) }
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private var preflightCanCreate: Bool {
        workspaceRootCanCreate && folderNameIsValid && !destinationExists
    }

    private var preflightItems: [WorkspaceCreationPreflightItem] {
        [
            workspaceRootPreflightItem,
            folderPreflightItem,
            destinationPreflightItem,
            scopePreflightItem,
            environmentPreflightItem
        ]
    }

    private var workspaceRootPreflightItem: WorkspaceCreationPreflightItem {
        let status = workspaceRootStatus
        if workspaceRootPath.isEmpty {
            return WorkspaceCreationPreflightItem(
                id: "root",
                title: "工作区根目录 / Workspaces root",
                detail: "Settings 中的工作区路径为空，无法确定写入位置。",
                status: .blocker
            )
        }
        if status.exists && !status.isDirectory {
            return WorkspaceCreationPreflightItem(
                id: "root",
                title: "工作区根目录 / Workspaces root",
                detail: "\(workspaceRootPath) 不是目录，请先调整 Settings。",
                status: .blocker
            )
        }
        if status.exists {
            return WorkspaceCreationPreflightItem(
                id: "root",
                title: "工作区根目录 / Workspaces root",
                detail: workspaceRootPath,
                status: .pass
            )
        }
        return WorkspaceCreationPreflightItem(
            id: "root",
            title: "工作区根目录 / Workspaces root",
            detail: "\(workspaceRootPath) 不存在，创建时会尝试建立目录。",
            status: .review
        )
    }

    private var folderPreflightItem: WorkspaceCreationPreflightItem {
        if folderNameIsValid {
            return WorkspaceCreationPreflightItem(
                id: "folder",
                title: "目录名 / Folder name",
                detail: normalizedFolder,
                status: .pass
            )
        }
        return WorkspaceCreationPreflightItem(
            id: "folder",
            title: "目录名 / Folder name",
            detail: "目录名不能为空，也不能使用 /、:、\\、. 或 ..。",
            status: .blocker
        )
    }

    private var destinationPreflightItem: WorkspaceCreationPreflightItem {
        if destinationExists {
            return WorkspaceCreationPreflightItem(
                id: "destination",
                title: "写入位置 / Destination",
                detail: "\(destinationPath) 已存在，请换一个目录名。",
                status: .blocker
            )
        }
        return WorkspaceCreationPreflightItem(
            id: "destination",
            title: "写入位置 / Destination",
            detail: destinationPath,
            status: folderNameIsValid ? .pass : .review
        )
    }

    private var scopePreflightItem: WorkspaceCreationPreflightItem {
        if services.isEmpty && normalizedTargetBranch.isEmpty {
            return WorkspaceCreationPreflightItem(
                id: "scope",
                title: "范围 / Scope",
                detail: "服务范围和目标分支都会保持待确认，适合先建档再分析。",
                status: .review
            )
        }
        if services.isEmpty {
            return WorkspaceCreationPreflightItem(
                id: "scope",
                title: "范围 / Scope",
                detail: "目标分支已填写，服务范围仍待确认。",
                status: .review
            )
        }
        if normalizedTargetBranch.isEmpty {
            return WorkspaceCreationPreflightItem(
                id: "scope",
                title: "范围 / Scope",
                detail: "\(services.count) 个服务已选，目标分支仍待确认。",
                status: .review
            )
        }
        if !missingSelectedSourceRepositories.isEmpty {
            return WorkspaceCreationPreflightItem(
                id: "scope",
                title: "范围 / Scope",
                detail: "\(services.count) 个服务已选；\(missingSelectedSourceRepositories.count) 个未在源仓库扫描中出现，后续创建 worktree 前需复核。",
                status: .review
            )
        }
        return WorkspaceCreationPreflightItem(
            id: "scope",
            title: "范围 / Scope",
            detail: "\(services.count) 个服务 · \(normalizedTargetBranch)",
            status: .pass
        )
    }

    private var environmentPreflightItem: WorkspaceCreationPreflightItem {
        guard let health = appState.nativeEnvironmentHealth else {
            return WorkspaceCreationPreflightItem(
                id: "environment",
                title: "环境检查 / Environment",
                detail: "尚未运行环境检查。可以继续创建，也建议先检查 Git、路径和源仓库数量。",
                status: .review
            )
        }
        if health.ready {
            return WorkspaceCreationPreflightItem(
                id: "environment",
                title: "环境检查 / Environment",
                detail: "\(health.workspaceCount) workspaces · \(health.sourceRepoCount) repos",
                status: .pass
            )
        }
        return WorkspaceCreationPreflightItem(
            id: "environment",
            title: "环境检查 / Environment",
            detail: "\(health.blockers.count) blockers · \(health.warnings.count) warnings。创建可继续，但建议先处理 Settings 中的环境提示。",
            status: .review
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("新建工作区 / New Workspace")
                    .font(.title3.weight(.semibold))
                Text("This writes the standard Nexus workspace documents under the configured Workspaces root.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                if appState.workspaces.isEmpty {
                    Section("首次使用 / First run") {
                        CreateWorkspaceFirstRunTemplateCard {
                            applyDemoTemplate()
                        }
                    }
                }

                Section("基本信息 / Basics") {
                    TextField("需求名称", text: $name)
                        .onChange(of: name) { value in
                            if !didEditFolder {
                                folder = defaultFolder(for: value)
                            }
                        }
                    TextField("工作区目录名", text: Binding(
                        get: { folder },
                        set: { value in
                            didEditFolder = true
                            folder = value
                        }
                    ))
                    TextField("目标分支，留空则待确认", text: $targetBranch)
                }

                Section("服务范围 / Service scope") {
                    HStack {
                        Text("\(services.count) selected")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button(appState.isScanningSourceRepositories ? "Scanning" : "Scan repos") {
                            Task {
                                await appState.refreshSourceRepositories()
                            }
                        }
                        .disabled(appState.isScanningSourceRepositories)
                    }

                    if !availableSourceRepositories.isEmpty {
                        TextField("筛选源仓库 / Filter services", text: $serviceQuery)

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(filteredSourceRepositories.prefix(12), id: \.name) { repository in
                                SourceRepositorySelectionRow(
                                    repository: repository,
                                    isSelected: Binding(
                                        get: { selectedServiceNames.contains(repository.name) },
                                        set: { isSelected in
                                            if isSelected {
                                                selectedServiceNames.insert(repository.name)
                                            } else {
                                                selectedServiceNames.remove(repository.name)
                                            }
                                        }
                                    )
                                )
                            }

                            if filteredSourceRepositories.isEmpty {
                                Text("No services match this filter. Clear the filter or type the service manually.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            } else if filteredSourceRepositories.count > 12 {
                                Text("Showing 12 of \(filteredSourceRepositories.count) matching repositories. Refine the filter to narrow the list.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if appState.isScanningSourceRepositories {
                        HStack(spacing: 8) {
                            ProgressView()
                                .controlSize(.small)
                            Text("Scanning configured source repository root...")
                                .foregroundStyle(.secondary)
                        }
                    } else {
                        Text("No source repositories detected yet. You can scan again, type services manually, or leave service scope pending.")
                            .foregroundStyle(.secondary)
                    }

                    if let error = appState.sourceRepositoryScanError {
                        Text(error)
                            .foregroundStyle(NexusPalette.danger)
                    }

                    TextField("手动补充服务，逗号或空格分隔", text: $servicesText)
                }

                Section("创建确认 / Confirmation") {
                    WorkspaceCreationPreflightView(
                        items: preflightItems,
                        canCreate: preflightCanCreate,
                        isCheckingEnvironment: appState.isCheckingNativeEnvironment,
                        runEnvironmentCheckAction: {
                            Task {
                                await appState.checkNativeEnvironment()
                            }
                        }
                    )
                    WorkspaceCreationSummary(
                        workspaceRoot: appState.workspaceRoot,
                        folder: folder,
                        targetBranch: targetBranch,
                        services: services
                    )
                    Toggle("确认创建目录和标准 Markdown 文档", isOn: $confirmed)
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(appState.isCreatingWorkspace ? "Creating" : "Create") {
                    Task {
                        await appState.createWorkspace(
                            draft: CreateWorkspaceDraft(
                                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                                folder: folder.trimmingCharacters(in: .whitespacesAndNewlines),
                                services: services,
                                targetBranch: targetBranch.trimmingCharacters(in: .whitespacesAndNewlines),
                                confirmed: confirmed
                            )
                        )
                        if appState.lastError == nil {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canCreate)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(NexusPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .task {
            await appState.refreshSourceRepositories()
        }
        .padding(22)
        .frame(width: 620, height: 620)
    }

    private func defaultFolder(for value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let slug = trimmed
            .lowercased()
            .components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "-")
        let suffix = slug.isEmpty ? "workspace" : slug
        return "\(Self.todayString())-\(suffix)"
    }

    private func applyDemoTemplate() {
        name = "Nexus 示例工作区"
        folder = "\(Self.todayString())-nexus-demo-workspace"
        targetBranch = "chen/nexus-demo"
        servicesText = ""
        selectedServiceNames = []
        serviceQuery = ""
        confirmed = false
        didEditFolder = true
    }

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
    }
}

private struct CreateWorkspaceFirstRunTemplateCard: View {
    let applyDemoAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("示例模板 / Demo template", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
            Text("用于第一次熟悉 Nexus 工作区结构。点击后只会预填名称、目录和分支，真正写入前仍需要通过预检并勾选确认。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                applyDemoAction()
            } label: {
                Label("套用示例 / Use demo", systemImage: "wand.and.stars")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }
}

private struct SourceRepositorySelectionRow: View {
    let repository: SourceRepositorySnapshot
    @Binding var isSelected: Bool

    var body: some View {
        Toggle(isOn: $isSelected) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(repository.name)
                        .font(.caption.weight(.medium))
                    if repository.dirty {
                        Text("dirty")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(NexusPalette.warning)
                    }
                }
                Text("\(repository.branch) · \(repository.summary)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
    }
}

private struct WorkspaceCreationSummary: View {
    let workspaceRoot: String
    let folder: String
    let targetBranch: String
    let services: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            SummaryLine(label: "Path", value: "\(workspaceRoot)/\(folder.trimmingCharacters(in: .whitespacesAndNewlines))")
            SummaryLine(
                label: "Branch",
                value: targetBranch.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    ? "待确认 / Pending"
                    : targetBranch.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            SummaryLine(
                label: "Services",
                value: services.isEmpty
                    ? "服务范围待确认 / Scope pending"
                    : services.joined(separator: ", ")
            )
            Text("Nexus will create the standard Markdown set and keep worktree creation as a separate confirmed step.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct WorkspaceCreationPreflightItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: WorktreePreflightStatus
}

private struct WorkspaceCreationPreflightView: View {
    let items: [WorkspaceCreationPreflightItem]
    let canCreate: Bool
    let isCheckingEnvironment: Bool
    let runEnvironmentCheckAction: () -> Void

    private var blockerCount: Int {
        items.filter { $0.status == .blocker }.count
    }

    private var reviewCount: Int {
        items.filter { $0.status == .review }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Label(summaryTitle, systemImage: canCreate ? "checkmark.seal" : "xmark.octagon")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(canCreate ? NexusPalette.success : NexusPalette.danger)

                Spacer()

                Button(isCheckingEnvironment ? "Checking" : "Run Check") {
                    runEnvironmentCheckAction()
                }
                .disabled(isCheckingEnvironment)
            }

            Text(summaryDetail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    WorktreePreflightRow(
                        title: item.title,
                        detail: item.detail,
                        status: item.status
                    )
                }
            }
        }
        .padding(12)
        .background((canCreate ? NexusPalette.success : NexusPalette.warning).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var summaryTitle: String {
        canCreate ? "创建预检通过 / Preflight ready" : "需要先处理阻塞项 / Blocked"
    }

    private var summaryDetail: String {
        if blockerCount > 0 {
            return "\(blockerCount) 个阻塞项会导致创建失败。处理后再确认创建。"
        }
        if reviewCount > 0 {
            return "\(reviewCount) 个 review 项不会阻止建档，但会影响后续 worktree 或交付检查。"
        }
        return "路径、目录名和写入位置都可用。创建后会进入工作区详情的下一步引导。"
    }
}

private struct SummaryLine: View {
    let label: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
    }
}

private struct WorktreeSetupSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    let workspace: WorkspaceSummary

    private var currentWorkspace: WorkspaceSummary {
        appState.workspaces.first { $0.id == workspace.id } ?? workspace
    }

    private var missingServices: [String] {
        appState.missingWorktreeServices(in: currentWorkspace)
    }

    private var missingSourceServices: [String] {
        currentWorkspace.services
            .filter { service in
                !service.worktreeExists && !service.sourceExists
            }
            .map(\.name)
    }

    private var preflightIsReady: Bool {
        branchIsReady && !missingServices.isEmpty && missingSourceServices.isEmpty
    }

    private var canRun: Bool {
        confirmed && preflightIsReady && !appState.isSettingUpWorktrees
    }

    private var branchIsReady: Bool {
        let normalized = currentWorkspace.branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return !normalized.isEmpty
            && normalized != "-"
            && !["待确认", "未确认", "pending", "tbd", "todo"].contains { marker in
                normalized.contains(marker)
            }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("创建缺失 worktree / Setup worktrees")
                        .font(.title3.weight(.semibold))
                    Text("Nexus will fetch each source repository and create missing workspace-local repos under this workspace.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 10) {
                    WorktreeSetupMetaRow(label: "Workspace", value: currentWorkspace.path)
                    WorktreeSetupMetaRow(label: "Source repos", value: appState.sourceReposRoot)
                    WorktreeSetupMetaRow(label: "Target branch", value: currentWorkspace.branch)
                }

                WorktreeSetupPreflightView(
                    branchIsReady: branchIsReady,
                    missingServices: missingServices,
                    missingSourceServices: missingSourceServices,
                    targetBranch: currentWorkspace.branch,
                    sourceReposRoot: appState.sourceReposRoot,
                    workspacePath: currentWorkspace.path
                )

                if preflightIsReady {
                    SectionBlock(title: "将要执行 / Local git operations") {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Nexus 会为 \(missingServices.count) 个服务执行 git fetch origin 和 git worktree add。", systemImage: "terminal")
                                .font(.caption)
                            Text("\(currentWorkspace.path)/repos/<service>")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            FlowTags(values: missingServices)
                        }
                    }
                }

                Toggle("确认执行本地 git fetch 与 git worktree add / Confirm local git write", isOn: $confirmed)
                    .disabled(!preflightIsReady)

                HStack {
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Button(appState.isLoading ? "Refreshing" : "Refresh") {
                        Task {
                            await appState.refreshFromBridge()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isLoading || appState.isSettingUpWorktrees)

                    Spacer()

                    Button(appState.isSettingUpWorktrees ? "Setting up" : "Setup worktrees") {
                        Task {
                            await appState.setupMissingWorktrees(for: currentWorkspace, confirmed: confirmed)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRun)
                }

                if !preflightIsReady {
                    Text(preflightGuidance)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let response = appState.lastWorktreeSetupResponse {
                    WorktreeSetupResultView(
                        response: response,
                        workspace: currentWorkspace,
                        closeAction: {
                            dismiss()
                        }
                    )
                    .environmentObject(appState)
                }

                if let error = appState.lastError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(NexusPalette.danger)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(22)
        .frame(width: 620)
    }

    private var preflightGuidance: String {
        if !branchIsReady {
            return "先在 branches.md 或 workspace.md 中确认目标分支，再创建 workspace-local worktree。"
        }
        if missingServices.isEmpty {
            return "当前没有需要创建的 worktree，可以关闭弹窗后继续 Codex 交接或本地检查。"
        }
        if !missingSourceServices.isEmpty {
            return "缺少源仓库：\(missingSourceServices.joined(separator: ", "))。请先同步 source repositories root，或在 Settings 中调整路径后刷新。"
        }
        return "预检通过后，需要显式确认才会执行本地 git 命令。"
    }
}

private struct WorktreeSetupPreflightView: View {
    let branchIsReady: Bool
    let missingServices: [String]
    let missingSourceServices: [String]
    let targetBranch: String
    let sourceReposRoot: String
    let workspacePath: String

    private var hasServicesToCreate: Bool {
        !missingServices.isEmpty
    }

    private var sourceReposReady: Bool {
        missingSourceServices.isEmpty
    }

    var body: some View {
        SectionBlock(title: "预检 / Preflight") {
            VStack(alignment: .leading, spacing: 10) {
                WorktreePreflightRow(
                    title: "目标分支 / Target branch",
                    detail: branchIsReady ? targetBranch : "目标分支仍待确认",
                    status: branchIsReady ? .pass : .blocker
                )

                WorktreePreflightRow(
                    title: "缺失 worktree / Missing worktrees",
                    detail: hasServicesToCreate ? "\(missingServices.count) services: \(missingServices.joined(separator: ", "))" : "没有需要创建的 worktree",
                    status: hasServicesToCreate ? .pass : .blockedDone
                )

                WorktreePreflightRow(
                    title: "源仓库 / Source repositories",
                    detail: sourceReposReady ? sourceReposRoot : "缺少: \(missingSourceServices.joined(separator: ", "))",
                    status: sourceReposReady ? .pass : .blocker
                )

                WorktreePreflightRow(
                    title: "写入位置 / Workspace-local repos",
                    detail: "\(workspacePath)/repos/<service>",
                    status: .info
                )
            }
        }
    }
}

private enum WorktreePreflightStatus {
    case pass
    case review
    case blocker
    case blockedDone
    case info

    var symbol: String {
        switch self {
        case .pass:
            return "checkmark.circle"
        case .review:
            return "exclamationmark.triangle"
        case .blocker:
            return "xmark.octagon"
        case .blockedDone:
            return "checkmark.seal"
        case .info:
            return "info.circle"
        }
    }

    var color: Color {
        switch self {
        case .pass, .blockedDone:
            return NexusPalette.success
        case .review:
            return NexusPalette.warning
        case .blocker:
            return NexusPalette.danger
        case .info:
            return NexusPalette.accent
        }
    }

    var label: String {
        switch self {
        case .pass:
            return "ready"
        case .review:
            return "review"
        case .blocker:
            return "block"
        case .blockedDone:
            return "done"
        case .info:
            return "info"
        }
    }
}

private struct WorktreePreflightRow: View {
    let title: String
    let detail: String
    let status: WorktreePreflightStatus

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.subheadline.weight(.medium))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer()

            Text(status.label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(status.color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(status.color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct TaskStatusUpdateSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    let update: TaskStatusUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("更新任务状态 / Update task")
                    .font(.title3.weight(.semibold))
                Text("Nexus will update the matching row in this workspace's tasks.md after confirmation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SectionBlock(title: "任务 / Task") {
                VStack(alignment: .leading, spacing: 8) {
                    TaskStatusMetaRow(label: "Workspace", value: update.workspaceName)
                    TaskStatusMetaRow(label: "Task", value: update.taskTitle)
                    TaskStatusMetaRow(label: "Status", value: "\(update.currentStatus) -> \(update.nextStatus)")
                    TaskStatusMetaRow(label: "Path", value: "\(update.workspacePath)/tasks.md")
                }
            }

            Toggle("确认写入 tasks.md / Confirm local write", isOn: $confirmed)

            HStack {
                Button("Cancel") {
                    appState.pendingTaskStatusUpdate = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(appState.isUpdatingTask ? "Updating" : "Update") {
                    Task {
                        await appState.confirmPendingTaskStatusUpdate(confirmed: confirmed)
                        if appState.lastError == nil {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!confirmed || appState.isUpdatingTask)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(NexusPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

private struct LifecycleStatusUpdateSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    let update: LifecycleStatusUpdate

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("更新生命周期 / Update lifecycle")
                    .font(.title3.weight(.semibold))
                Text("Nexus will update workspace.md and STATUS.md after confirmation, then append an audit event when the Rust Core bridge is available.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SectionBlock(title: "生命周期 / Lifecycle") {
                VStack(alignment: .leading, spacing: 8) {
                    TaskStatusMetaRow(label: "Workspace", value: update.workspaceName)
                    TaskStatusMetaRow(label: "Stage", value: "\(update.currentLabel) -> \(update.nextLabel)")
                    TaskStatusMetaRow(label: "State", value: "\(update.currentStage) -> \(update.nextState)")
                    TaskStatusMetaRow(label: "Focus", value: update.focus)
                    TaskStatusMetaRow(label: "Next", value: update.nextAction)
                    TaskStatusMetaRow(label: "Files", value: "workspace.md, STATUS.md")
                }
            }

            Toggle("确认写入 workspace.md 和 STATUS.md / Confirm local write", isOn: $confirmed)

            HStack {
                Button("Cancel") {
                    appState.pendingLifecycleStatusUpdate = nil
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(appState.isUpdatingLifecycle ? "Updating" : "Update") {
                    Task {
                        await appState.confirmPendingLifecycleStatusUpdate(confirmed: confirmed)
                        if appState.lastError == nil {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!confirmed || appState.isUpdatingLifecycle)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(NexusPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(width: 600)
    }
}

private struct TaskStatusMetaRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct WorktreeSetupMetaRow: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
    }
}

private struct WorktreeSetupResultView: View {
    @EnvironmentObject private var appState: AppState
    @State private var didRunFollowUpCheck = false
    @State private var followUpCheck: LocalAutomationCheckResponse?
    @State private var followUpCheckError: String?
    let response: SetupWorktreesResponse
    let workspace: WorkspaceSummary
    let closeAction: () -> Void

    private var hasFailure: Bool {
        !response.failed.isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(resultSummary, systemImage: response.failed.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(response.failed.isEmpty ? NexusPalette.success : NexusPalette.warning)

            Text(resultGuidance)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if !response.command.isEmpty {
                Text(response.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            WorktreeSetupResultGroup(title: "已创建 / Created", results: response.created, color: NexusPalette.success)
            WorktreeSetupResultGroup(title: "已跳过 / Skipped", results: response.skipped, color: .secondary)
            WorktreeSetupResultGroup(title: "失败 / Failed", results: response.failed, color: NexusPalette.danger)

            HStack(spacing: 8) {
                Button {
                    Task {
                        await appState.openWorkspaceInFinder(workspace)
                    }
                } label: {
                    Label("打开 Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("打开当前工作区目录 / Open workspace folder")

                Button {
                    Task {
                        await appState.openWorktreeSetupResultInCodex(response, in: workspace)
                    }
                } label: {
                    Label("交接 Codex", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("复制 worktree 创建结果并打开 Codex / Copy setup result and open Codex")

                Button {
                    didRunFollowUpCheck = true
                    followUpCheck = nil
                    followUpCheckError = nil
                    Task { @MainActor in
                        let response = await appState.runLocalAutomationCheck(actor: "Nexus Worktree Setup")
                        followUpCheck = response
                        if response == nil {
                            followUpCheckError = appState.lastError ?? "检查失败，请稍后重试 / Check failed, please retry."
                        }
                    }
                } label: {
                    Label(appState.isRunningAutomationCheck ? "检查中" : "运行检查", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("运行本地检查并在结果卡内显示摘要 / Run local check and show the summary here")
                .disabled(appState.isRunningAutomationCheck)

                Spacer()

                Button("关闭") {
                    closeAction()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }

            if didRunFollowUpCheck {
                if appState.isRunningAutomationCheck {
                    Label("正在运行本地检查 / Running local check", systemImage: "arrow.triangle.2.circlepath")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else if let check = followUpCheck {
                    WorktreeSetupFollowUpCheckView(check: check)
                } else if let followUpCheckError {
                    Label(followUpCheckError, systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(NexusPalette.danger)
                }
            }
        }
        .padding(12)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var resultSummary: String {
        "\(response.created.count) 已创建 · \(response.skipped.count) 已跳过 · \(response.failed.count) 失败"
    }

    private var resultGuidance: String {
        if hasFailure {
            return "部分服务没有创建成功。请先查看失败明细；修复源仓库、分支或本地路径后可以再次执行。"
        }
        if response.created.isEmpty {
            return "没有新增 worktree。可以关闭弹窗，继续 Codex 交接或运行本地检查确认状态。"
        }
        return "worktree 已写入工作区。下一步建议运行本地检查，确认分支和未提交状态后再交接 Codex。"
    }
}

private struct WorktreeSetupFollowUpCheckView: View {
    let check: LocalAutomationCheckResponse

    private var tone: Color {
        switch check.status {
        case "attention":
            NexusPalette.danger
        case "review":
            NexusPalette.warning
        default:
            NexusPalette.success
        }
    }

    private var symbol: String {
        switch check.status {
        case "attention":
            "xmark.octagon"
        case "review":
            "exclamationmark.triangle"
        default:
            "checkmark.circle"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(tone)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 2) {
                    Text("检查结果 / Local check")
                        .font(.caption.weight(.semibold))
                    Text("\(check.summary) · \(check.generatedAt)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                WorktreeSetupCheckMetric(
                    label: "风险",
                    value: check.riskCount,
                    tone: check.riskCount > 0 ? NexusPalette.warning : NexusPalette.success,
                    help: "风险数量 / Risk count"
                )
                WorktreeSetupCheckMetric(
                    label: "任务",
                    value: check.openTaskCount,
                    tone: check.highPriorityTaskCount > 0 ? NexusPalette.warning : NexusPalette.accent,
                    help: "活跃任务数量 / Active task count"
                )
                WorktreeSetupCheckMetric(
                    label: "分支",
                    value: check.branchMismatchCount,
                    tone: check.branchMismatchCount > 0 ? NexusPalette.warning : NexusPalette.success,
                    help: "分支不一致工作区数量 / Branch mismatch workspace count"
                )
                WorktreeSetupCheckMetric(
                    label: "WT",
                    value: check.missingWorktreeCount,
                    tone: check.missingWorktreeCount > 0 ? NexusPalette.warning : NexusPalette.success,
                    help: "缺失 worktree 数量 / Missing worktree count"
                )
                WorktreeSetupCheckMetric(
                    label: "改动",
                    value: check.dirtyServiceCount,
                    tone: check.dirtyServiceCount > 0 ? NexusPalette.warning : NexusPalette.success,
                    help: "未提交服务数量 / Dirty service count"
                )
            }
        }
        .padding(10)
        .background(NexusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WorktreeSetupCheckMetric: View {
    let label: String
    let value: Int
    let tone: Color
    let help: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(help)
    }
}

private struct WorktreeSetupResultGroup: View {
    let title: String
    let results: [WorktreeSetupResult]
    let color: Color

    var body: some View {
        if !results.isEmpty {
            VStack(alignment: .leading, spacing: 5) {
                Text("\(title) \(results.count)")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                ForEach(results, id: \.service) { result in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(result.service)
                            .font(.caption.weight(.semibold))
                        Text(result.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                        Text(result.worktreePath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        }
    }
}

private struct FlowTags: View {
    let values: [String]

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(values, id: \.self) { value in
                Text(value)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 5)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(NexusPalette.badge)
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }
        }
    }
}

private struct FlowTagsButtonRow: View {
    let transitions: [LifecycleTransition]
    let action: (LifecycleTransition) -> Void

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 112), spacing: 8)], alignment: .leading, spacing: 8) {
            ForEach(transitions) { transition in
                Button {
                    action(transition)
                } label: {
                    Label(transition.label, systemImage: transition.systemImage)
                        .font(.caption.weight(.medium))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

private struct WorkspaceListView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isCreateWorkspacePresented: Bool
    @Binding var isSettingsPresented: Bool

    var body: some View {
        ScrollView {
            if appState.filteredWorkspaces.isEmpty {
                WorkspaceListEmptyStateView(
                    isCreateWorkspacePresented: $isCreateWorkspacePresented,
                    isSettingsPresented: $isSettingsPresented
                )
                .padding(18)
            } else {
                LazyVStack(spacing: 12) {
                    ForEach(appState.filteredWorkspaces) { workspace in
                        WorkspaceCard(
                            workspace: workspace,
                            isSelected: workspace.id == appState.selectedWorkspace?.id,
                            isPinned: appState.isPinned(workspace)
                        ) {
                            appState.togglePinned(workspace)
                        }
                        .onTapGesture {
                            appState.select(workspace)
                        }
                    }
                }
                .padding(18)
            }
        }
    }
}

private struct WorkspaceListEmptyStateView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isCreateWorkspacePresented: Bool
    @Binding var isSettingsPresented: Bool

    private var hasWorkspaces: Bool {
        !appState.workspaces.isEmpty
    }

    private var hasSearchOrFilter: Bool {
        appState.selectedFilter != .all
            || !appState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var title: String {
        if appState.isLoading {
            return "正在加载工作区 / Loading workspaces"
        }
        if hasWorkspaces && hasSearchOrFilter {
            return "当前筛选没有结果 / No matching workspaces"
        }
        return "还没有可用工作区 / No workspaces yet"
    }

    private var detail: String {
        if appState.isLoading {
            return "Nexus 正在读取配置路径、工作区 Markdown 和本地索引。"
        }
        if hasWorkspaces && hasSearchOrFilter {
            return "清空搜索或切回全部工作区后，可以继续从现有 workspace 进入详情。"
        }
        return "先确认本地路径，再创建第一个需求工作区；如果团队已经有工作区目录，可以保存路径后刷新。"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 8) {
                Label(title, systemImage: appState.isLoading ? "arrow.triangle.2.circlepath" : "tray")
                    .font(.title3.weight(.semibold))
                Text(detail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            WorkspaceSetupPathSummary()

            if let health = appState.nativeEnvironmentHealth {
                WorkspaceSetupHealthSummary(health: health)
            } else {
                Label("尚未运行环境检查。检查后会显示路径、Git、工作区和源仓库状态。", systemImage: "info.circle")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if !hasWorkspaces {
                WorkspaceFirstRunGuide(
                    health: appState.nativeEnvironmentHealth,
                    profileImported: appState.lastSettingsProfilePath != nil
                )
            }

            WorkspaceSetupActionGrid(
                isCreateWorkspacePresented: $isCreateWorkspacePresented,
                isSettingsPresented: $isSettingsPresented,
                settingsLabel: hasWorkspaces ? "设置" : "团队配置",
                showAllAction: hasWorkspaces && hasSearchOrFilter ? {
                    appState.resetWorkspaceListScope()
                } : nil,
                minimumColumnWidth: 116
            )
        }
        .frame(maxWidth: 720, alignment: .leading)
        .padding(18)
        .background(NexusPalette.panel)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NexusPalette.border, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

}

private struct WorkspaceSetupActionGrid: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isCreateWorkspacePresented: Bool
    @Binding var isSettingsPresented: Bool
    let settingsLabel: String
    let showAllAction: (() -> Void)?
    let minimumColumnWidth: CGFloat

    var body: some View {
        LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
            if let showAllAction {
                Button {
                    showAllAction()
                } label: {
                    Label("显示全部", systemImage: "square.grid.2x2")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("清空搜索和筛选 / Show all workspaces")
            }

            if showAllAction == nil {
                newWorkspaceButton
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("创建需求工作区 / New workspace")
            } else {
                newWorkspaceButton
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("创建需求工作区 / New workspace")
            }

            Button {
                isSettingsPresented = true
            } label: {
                Label(settingsLabel, systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("打开路径和团队配置 / Open Settings")

            Button {
                Task {
                    await appState.checkNativeEnvironment()
                }
            } label: {
                Label(appState.isCheckingNativeEnvironment ? "检查中" : "环境检查", systemImage: "checkmark.seal")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.isCheckingNativeEnvironment)
            .help("检查路径和 Git / Run environment check")

            Button {
                Task {
                    await appState.refreshFromBridge()
                }
            } label: {
                Label(appState.isLoading ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(appState.isLoading)
            .help("重新扫描工作区 / Refresh workspaces")
        }
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: minimumColumnWidth), spacing: 8, alignment: .leading)]
    }

    private var newWorkspaceButton: some View {
        Button {
            isCreateWorkspacePresented = true
        } label: {
            Label("新建工作区", systemImage: "plus")
        }
    }
}

private struct WorkspaceFirstRunGuide: View {
    let health: NativeEnvironmentHealth?
    let profileImported: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            Text("首次使用路径 / First-run path")
                .font(.caption.weight(.semibold))
            FirstRunStepRow(
                title: "1. 导入团队配置 / Import profile",
                detail: profileDetail,
                status: profileStatus
            )
            FirstRunStepRow(
                title: "2. 环境检查 / Check environment",
                detail: environmentDetail,
                status: environmentStatus
            )
            FirstRunStepRow(
                title: "3. 创建工作区 / Create workspace",
                detail: "可以创建真实需求，也可以在新建弹窗里套用示例模板熟悉流程。",
                status: .review
            )
        }
    }

    private var profileStatus: WorktreePreflightStatus {
        profileImported ? .pass : .review
    }

    private var profileDetail: String {
        if profileImported {
            return "已导入团队 Profile；仍可在 Settings 调整本机路径。"
        }
        return "如果同事已经分享 Profile，先在 Settings 导入；否则保留本机路径也可以继续。"
    }

    private var environmentStatus: WorktreePreflightStatus {
        guard let health else {
            return .review
        }
        return health.ready ? .pass : .blocker
    }

    private var environmentDetail: String {
        guard let health else {
            return "运行 Environment 后会确认路径、Git、工作区数量和源仓库数量。"
        }
        if health.ready {
            return "\(health.workspaceCount) workspaces · \(health.sourceRepoCount) repos，环境已可用。"
        }
        return "\(health.blockers.count) blockers · \(health.warnings.count) warnings，优先回到 Settings 调整路径。"
    }
}

private struct FirstRunStepRow: View {
    let title: String
    let detail: String
    let status: WorktreePreflightStatus

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: status.symbol)
                .foregroundStyle(status.color)
                .frame(width: 14)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption.weight(.medium))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WorkspaceSetupPathSummary: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            WorkspaceSetupPathRow(label: "Workspaces", value: appState.workspaceRoot, systemImage: "folder")
            WorkspaceSetupPathRow(label: "Source repos", value: appState.sourceReposRoot, systemImage: "shippingbox")
            WorkspaceSetupPathRow(label: "Docs", value: appState.docsRoot, systemImage: "doc.text")
        }
        .padding(12)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WorkspaceSetupPathRow: View {
    let label: String
    let value: String
    let systemImage: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: systemImage)
                .foregroundStyle(NexusPalette.accent)
                .frame(width: 16)
            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption.weight(.semibold))
                Text(value)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }
}

private struct WorkspaceSetupHealthSummary: View {
    let health: NativeEnvironmentHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Label(health.ready ? "环境可用 / Ready" : "需要配置 / Needs setup", systemImage: health.ready ? "checkmark.circle" : "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(health.ready ? NexusPalette.success : NexusPalette.warning)
                Spacer()
                Text("\(health.workspaceCount) ws / \(health.sourceRepoCount) repos")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            if health.blockers.isEmpty && health.warnings.isEmpty {
                Text("路径和基础工具检查通过，可以创建或刷新工作区。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array((health.blockers + health.warnings).prefix(3).enumerated()), id: \.offset) { _, issue in
                    Text(issue)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }
        }
        .padding(12)
        .background((health.ready ? NexusPalette.success : NexusPalette.warning).opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WorkspaceCard: View {
    let workspace: WorkspaceSummary
    let isSelected: Bool
    let isPinned: Bool
    let togglePinned: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(workspace.name)
                        .font(.headline)
                    Text(workspace.folder)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button(action: togglePinned) {
                    Image(systemName: isPinned ? "pin.fill" : "pin")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(isPinned ? NexusPalette.accent : .secondary)
                        .frame(width: 28, height: 28)
                        .background(isPinned ? NexusPalette.selected : NexusPalette.badge)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .help(isPinned ? "取消置顶 / Unpin workspace" : "置顶工作区 / Pin workspace")
                if workspace.isArchived {
                    ArchivedBadge()
                }
                RiskBadge(level: workspace.riskLevel)
            }

            HStack(spacing: 8) {
                Pill(label: workspace.branch, systemImage: "arrow.triangle.branch")
                Pill(label: workspace.state.label, systemImage: "circle.dashed")
                Pill(label: workspace.aiState, systemImage: "sparkle.magnifyingglass")
            }

            LifecycleCompactView(lifecycle: workspace.lifecycle)

            HStack(spacing: 16) {
                Metric(label: "服务 / Services", value: "\(workspace.services.count)")
                Metric(label: "任务 / Tasks", value: "\(workspace.tasks.filter(\.isActive).count) active")
                Metric(label: "Worktree", value: workspace.worktreeState)
                Metric(label: "最近活动 / Activity", value: workspace.activities.first?.title ?? "No recent activity")
            }
        }
        .padding(16)
        .background(workspace.isArchived ? NexusPalette.preview : NexusPalette.panel)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(cardBorder, lineWidth: isSelected ? 1.4 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var cardBorder: Color {
        if isSelected {
            return workspace.isArchived ? NexusPalette.accent.opacity(0.65) : NexusPalette.accent
        }
        return workspace.isArchived ? NexusPalette.border.opacity(0.65) : NexusPalette.border
    }
}

private struct InspectorView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isCreateWorkspacePresented: Bool
    @Binding var isSettingsPresented: Bool

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if let error = appState.lastError {
                        OperationFeedbackView(
                            error: error,
                            settingsAction: {
                                isSettingsPresented = true
                            },
                            dismissAction: {
                                appState.clearLastError()
                            }
                        )
                        .environmentObject(appState)
                    }

                    if let feedback = appState.codexHandoffFeedback {
                        CodexHandoffFeedbackView(feedback: feedback) {
                            appState.clearCodexHandoffFeedback()
                        }
                    }

                    if let feedback = appState.workspaceLinkFeedback {
                        WorkspaceLinkFeedbackView(feedback: feedback) {
                            appState.clearWorkspaceLinkFeedback()
                        }
                        .environmentObject(appState)
                    }

                    if let feedback = appState.localWriteFeedback {
                        LocalWriteFeedbackView(feedback: feedback) {
                            appState.clearLocalWriteFeedback()
                        }
                        .environmentObject(appState)
                    }

                    AutomationActionCenterView()

                    if let workspace = appState.selectedWorkspace {
                        WorkspaceDetailView(
                            workspace: workspace,
                            scrollToSection: { section in
                                withAnimation(.easeInOut(duration: 0.18)) {
                                    proxy.scrollTo(section, anchor: .top)
                                }
                            }
                        )
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        InspectorEmptyStateView(
                            isCreateWorkspacePresented: $isCreateWorkspacePresented,
                            isSettingsPresented: $isSettingsPresented
                        )
                    }
                }
            }
            .padding(18)
            .background(NexusPalette.inspector)
        }
    }
}

private struct OperationFeedbackView: View {
    @EnvironmentObject private var appState: AppState
    let error: String
    let settingsAction: () -> Void
    let dismissAction: () -> Void

    var body: some View {
        SectionBlock(title: "操作反馈 / Operation") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(NexusPalette.danger)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("需要处理 / Needs review")
                            .font(.subheadline.weight(.semibold))
                        Text("最近一次本地操作没有完成。先复制错误或运行恢复动作，再继续当前工作流。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        dismissAction()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("关闭操作反馈 / Dismiss")
                }

                Text(error)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(NexusPalette.danger)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                    Button {
                        copyToPasteboard(error)
                    } label: {
                        Label("复制错误", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("复制错误信息 / Copy error")

                    Button {
                        Task {
                            await appState.refreshFromBridge()
                        }
                    } label: {
                        Label(appState.isLoading ? "刷新中" : "刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isLoading)
                    .help("重新扫描工作区 / Refresh workspaces")

                    Button {
                        Task {
                            await appState.checkNativeEnvironment()
                        }
                    } label: {
                        Label(appState.isCheckingNativeEnvironment ? "检查中" : "环境检查", systemImage: "checkmark.seal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isCheckingNativeEnvironment)
                    .help("检查路径和 Git / Run environment check")

                    Button {
                        settingsAction()
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("打开路径配置 / Open settings")
                }
            }
        }
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 104), spacing: 8, alignment: .leading)]
    }
}

private struct InspectorEmptyStateView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isCreateWorkspacePresented: Bool
    @Binding var isSettingsPresented: Bool

    var body: some View {
        SectionBlock(title: "工作区详情 / Detail") {
            VStack(alignment: .leading, spacing: 12) {
                Label(title, systemImage: appState.workspaces.isEmpty ? "tray" : "sidebar.leading")
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                WorkspaceSetupActionGrid(
                    isCreateWorkspacePresented: $isCreateWorkspacePresented,
                    isSettingsPresented: $isSettingsPresented,
                    settingsLabel: appState.workspaces.isEmpty ? "团队配置" : "设置",
                    showAllAction: hasHiddenWorkspaces ? {
                        appState.resetWorkspaceListScope()
                    } : nil,
                    minimumColumnWidth: 96
                )
            }
        }
    }

    private var hasHiddenWorkspaces: Bool {
        !appState.workspaces.isEmpty
            && appState.filteredWorkspaces.isEmpty
            && (appState.selectedFilter != .all
                || !appState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
    }

    private var title: String {
        appState.workspaces.isEmpty ? "还没有工作区 / No workspace" : "选择一个工作区 / Select a workspace"
    }

    private var detail: String {
        if appState.workspaces.isEmpty {
            return "创建工作区后，这里会展示 Command Center、Workflow、Risk Review、Documents 和 Activity。"
        }
        return "从中间列表选择工作区，或者清空筛选后进入详情。"
    }
}

private struct CodexHandoffFeedbackView: View {
    let feedback: CodexHandoffFeedback
    let dismissAction: () -> Void

    var body: some View {
        SectionBlock(title: feedback.sectionTitle) {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: feedback.systemImage)
                        .foregroundStyle(NexusPalette.accent)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(feedback.title)
                            .font(.subheadline.weight(.semibold))
                        Text(feedback.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(feedback.timestamp) · \(feedback.clipboardLabel)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        dismissAction()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("关闭交接提示 / Dismiss")
                }

                Label(feedback.guidance, systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private struct WorkspaceLinkFeedbackView: View {
    @EnvironmentObject private var appState: AppState
    let feedback: WorkspaceLinkFeedback
    let dismissAction: () -> Void

    var body: some View {
        SectionBlock(title: "工作区链接 / Link") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: feedback.systemImage)
                        .foregroundStyle(NexusPalette.accent)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(feedback.title)
                            .font(.subheadline.weight(.semibold))
                        Text(feedback.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(feedback.timestamp) · \(feedback.workspaceName)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        dismissAction()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("关闭链接提示 / Dismiss")
                }

                Text(feedback.link)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                    Button {
                        copyToPasteboard(feedback.link)
                    } label: {
                        Label("复制链接", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        appState.focusWorkspace(id: feedback.workspaceID)
                    } label: {
                        Label("聚焦工作区", systemImage: "scope")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 104), spacing: 8, alignment: .leading)]
    }
}

private struct LocalWriteFeedbackView: View {
    @EnvironmentObject private var appState: AppState
    let feedback: LocalWriteFeedback
    let dismissAction: () -> Void

    var body: some View {
        SectionBlock(title: "本地写入 / Writeback") {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: feedback.systemImage)
                        .foregroundStyle(NexusPalette.success)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(feedback.title)
                            .font(.subheadline.weight(.semibold))
                        Text(feedback.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Text("\(feedback.timestamp) · \(feedback.workspaceName) · Workspace state refreshed")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button {
                        dismissAction()
                    } label: {
                        Image(systemName: "xmark")
                            .frame(width: 24, height: 24)
                    }
                    .buttonStyle(.plain)
                    .help("关闭写回提示 / Dismiss")
                }

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                    Button {
                        appState.focusWorkspace(id: feedback.workspaceID)
                    } label: {
                        Label("聚焦工作区", systemImage: "scope")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("清空筛选并选中刚刚写回的工作区 / Focus the updated workspace")

                    Button {
                        appState.focusWorkspace(id: feedback.workspaceID)
                        Task {
                            await appState.loadDocument(path: feedback.documentPath)
                        }
                    } label: {
                        Label(feedback.documentLabel, systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("打开刚刚写回的源文档 / Open the updated source document")

                    if feedback.documentPath.hasSuffix("/tasks.md"),
                       appState.nextTaskCenterItem(after: feedback) != nil {
                        Button {
                            appState.focusNextTask(after: feedback)
                        } label: {
                            Label("继续任务", systemImage: "arrow.down.circle")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("聚焦下一条活跃任务 / Focus the next active task")
                    }

                    Button {
                        appState.focusWorkspace(id: feedback.workspaceID)
                        Task {
                            await appState.runLocalAutomationCheck(actor: "Nexus Writeback")
                        }
                    } label: {
                        Label(appState.isRunningAutomationCheck ? "检查中" : "运行检查", systemImage: "checklist.checked")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isRunningAutomationCheck)
                    .help("写回后重新运行本地检查 / Run local checks after writeback")
                }
            }
        }
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)]
    }
}

private struct AutomationActionCenterView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        SectionBlock(title: "自动化动作 / Automation") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: statusSymbol)
                        .foregroundStyle(statusColor)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(appState.isRunningAutomationCheck ? "Checking" : "Run") {
                        Task {
                            await appState.runLocalAutomationCheck()
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isRunningAutomationCheck)
                }

                if let check = appState.lastAutomationCheck {
                    AutomationCheckMetrics(check: check)

                    if appState.actionableAutomationSignals.isEmpty {
                        Label("当前没有需要处理的自动化动作", systemImage: "checkmark.circle")
                            .font(.caption)
                            .foregroundStyle(NexusPalette.success)
                    } else {
                        ForEach(appState.actionableAutomationSignals.prefix(5)) { signal in
                            AutomationSignalRow(signal: signal)
                        }
                    }
                } else {
                    Text("运行本地检查后，这里会把风险、交付、任务、worktree 和 git 信号转换成可执行动作。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var statusTitle: String {
        guard let check = appState.lastAutomationCheck else {
            return appState.isRunningAutomationCheck ? "检查中 / Checking" : "等待检查 / Ready"
        }
        switch check.status {
        case "attention":
            return "需要立即处理 / Attention"
        case "review":
            return "需要复核 / Review"
        default:
            return "状态清洁 / Clean"
        }
    }

    private var statusDetail: String {
        if appState.isRunningAutomationCheck {
            return "正在扫描 workspace、git、任务、交付记录和 worktree 状态。"
        }
        if let check = appState.lastAutomationCheck {
            return "\(check.summary) · \(check.generatedAt)"
        }
        return "本地自动化检查尚未运行。"
    }

    private var statusSymbol: String {
        guard let check = appState.lastAutomationCheck else {
            return appState.isRunningAutomationCheck ? "arrow.triangle.2.circlepath" : "checklist"
        }
        switch check.status {
        case "attention":
            return "xmark.octagon"
        case "review":
            return "exclamationmark.triangle"
        default:
            return "checkmark.circle"
        }
    }

    private var statusColor: Color {
        guard let check = appState.lastAutomationCheck else {
            return NexusPalette.accent
        }
        switch check.status {
        case "attention":
            return NexusPalette.danger
        case "review":
            return NexusPalette.warning
        default:
            return NexusPalette.success
        }
    }
}

private struct AutomationCheckMetrics: View {
    let check: LocalAutomationCheckResponse
    private let columns = Array(repeating: GridItem(.flexible(), spacing: 8), count: 3)

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            AutomationMetric(
                label: "Risk",
                value: check.riskCount,
                tone: check.riskCount > 0 ? NexusPalette.warning : NexusPalette.success
            )
            AutomationMetric(
                label: "Delivery",
                value: check.deliveryIssueCount,
                tone: check.deliveryIssueCount > 0 ? NexusPalette.warning : NexusPalette.success
            )
            AutomationMetric(
                label: "Tasks",
                value: check.openTaskCount,
                tone: check.highPriorityTaskCount > 0 ? NexusPalette.warning : NexusPalette.accent
            )
            AutomationMetric(
                label: "Branch",
                value: check.branchMismatchCount,
                tone: check.branchMismatchCount > 0 ? NexusPalette.warning : NexusPalette.success
            )
            AutomationMetric(
                label: "WT",
                value: check.missingWorktreeCount,
                tone: check.missingWorktreeCount > 0 ? NexusPalette.warning : NexusPalette.success
            )
            AutomationMetric(
                label: "Dirty",
                value: check.dirtyServiceCount,
                tone: check.dirtyServiceCount > 0 ? NexusPalette.warning : NexusPalette.success
            )
            AutomationMetric(
                label: "Archive",
                value: check.archivedWorkspaceCount,
                tone: .secondary
            )
        }
    }

}

private struct AutomationMetric: View {
    let label: String
    let value: Int
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
                .foregroundStyle(tone)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct LocalCheckReceiptView: View {
    let check: LocalAutomationCheckResponse?
    let actor: String?
    let isRunning: Bool
    let contextLabel: String
    let copyAction: (LocalAutomationCheckResponse) -> Void

    private var statusColor: Color {
        guard let check else {
            return NexusPalette.accent
        }
        switch check.status {
        case "attention":
            return NexusPalette.danger
        case "review":
            return NexusPalette.warning
        default:
            return NexusPalette.success
        }
    }

    private var statusIcon: String {
        if isRunning {
            return "arrow.triangle.2.circlepath"
        }
        guard let check else {
            return "checklist"
        }
        switch check.status {
        case "attention":
            return "xmark.octagon"
        case "review":
            return "exclamationmark.triangle"
        default:
            return "checkmark.circle"
        }
    }

    private var statusTitle: String {
        if isRunning {
            return "正在运行本地检查 / Running local check"
        }
        guard let check else {
            return "等待本地检查 / Awaiting local check"
        }
        switch check.status {
        case "attention":
            return "检查发现阻塞 / Attention"
        case "review":
            return "检查需要复核 / Review needed"
        default:
            return "检查通过 / Clean"
        }
    }

    private var statusDetail: String {
        if isRunning {
            return "Nexus 正在扫描 workspace、任务、风险、交付记录、git 和 worktree 状态。"
        }
        guard let check else {
            return "运行本地检查后，这里会保留最近一次结果，方便继续交给 Codex 或回到文档复核。"
        }
        let actorText = actor ?? "Nexus"
        return "\(check.summary) · \(actorText) · \(check.generatedAt)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: statusIcon)
                    .foregroundStyle(statusColor)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 3) {
                    Text(statusTitle)
                        .font(.caption.weight(.semibold))
                    Text(statusDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Text(contextLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            if isRunning {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(NexusPalette.accent)
            } else if let check {
                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
                    AutomationMetric(
                        label: "Risk",
                        value: check.riskCount,
                        tone: check.riskCount > 0 ? NexusPalette.warning : NexusPalette.success
                    )
                    AutomationMetric(
                        label: "Delivery",
                        value: check.deliveryIssueCount,
                        tone: check.deliveryIssueCount > 0 ? NexusPalette.warning : NexusPalette.success
                    )
                    AutomationMetric(
                        label: "Tasks",
                        value: check.openTaskCount,
                        tone: check.highPriorityTaskCount > 0 ? NexusPalette.warning : NexusPalette.accent
                    )
                    AutomationMetric(
                        label: "WT",
                        value: check.missingWorktreeCount,
                        tone: check.missingWorktreeCount > 0 ? NexusPalette.warning : NexusPalette.success
                    )
                    AutomationMetric(
                        label: "Dirty",
                        value: check.dirtyServiceCount,
                        tone: check.dirtyServiceCount > 0 ? NexusPalette.warning : NexusPalette.success
                    )
                }

                HStack(spacing: 8) {
                    Button {
                        copyAction(check)
                    } label: {
                        Label("复制检查摘要", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if let auditError = check.auditError {
                        Text("审计写入失败: \(auditError)")
                            .font(.caption2)
                            .foregroundStyle(NexusPalette.warning)
                            .lineLimit(2)
                    } else if check.auditEventId != nil {
                        Label("已写入审计 / Audited", systemImage: "checkmark.circle")
                            .font(.caption2)
                            .foregroundStyle(NexusPalette.success)
                    }
                }
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(statusColor.opacity(0.18))
        }
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 72), spacing: 8, alignment: .leading)]
    }
}

private struct AutomationSignalRow: View {
    @EnvironmentObject private var appState: AppState
    let signal: LocalAutomationSignal

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(signal.title)
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text("\(signal.count)")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(color)
                    }
                    Text(signal.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 6) {
                Button(actionLabel) {
                    Task {
                        await appState.runAutomationSignalAction(signal)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)

                Button("Codex") {
                    let prompt = appState.automationSignalHandoffPrompt(for: signal)
                    copyToPasteboard(prompt)
                    Task {
                        await appState.recordAutomationSignalHandoffCopied(signal)
                    }
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(color.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var actionLabel: String {
        switch signal.action {
        case "review-risk":
            "风险交接"
        case "update-delivery":
            "处理交付"
        case "review-worktrees":
            "创建 worktree"
        case "review-dirty-services":
            "服务交接"
        case "review-branches":
            "打开分支"
        case "review-tasks":
            "Tasks"
        case "refresh":
            "Refresh"
        default:
            "Open"
        }
    }

    private var symbol: String {
        switch signal.kind {
        case "risk":
            "exclamationmark.triangle"
        case "delivery":
            "doc.text"
        case "task":
            "checklist"
        case "worktree":
            "terminal"
        case "git":
            "arrow.triangle.branch"
        case "branch":
            "arrow.triangle.branch"
        default:
            "sparkles"
        }
    }

    private var color: Color {
        switch signal.severity {
        case "error":
            NexusPalette.danger
        case "warning":
            NexusPalette.warning
        default:
            NexusPalette.accent
        }
    }
}

private struct WorkspaceDetailView: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary
    let scrollToSection: (WorkspaceDetailSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("工作区详情 / Detail")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(workspace.name)
                    .font(.title3.weight(.semibold))
                Text(workspace.path)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            WorkspaceDetailMapView(workspace: workspace) { section in
                scrollToSection(section)
            }

            WorkspaceActiveDocumentBanner(workspace: workspace) {
                scrollToSection(.documents)
            }
            .environmentObject(appState)

            WorkspaceDetailOverviewView(
                workspace: workspace,
                lastCheck: appState.lastAutomationCheck
            )
            .id(WorkspaceDetailSection.overview)

            if appState.lastCreatedWorkspace?.folder == workspace.folder {
                WorkspaceCreationNextStepsView(workspace: workspace)
            }

            WorkspaceCommandCenterView(
                workspace: workspace,
                demandAction: {
                    scrollToSection(.demand)
                }
            )
                .environmentObject(appState)
                .id(WorkspaceDetailSection.command)

            if !workspace.sessionActions.isEmpty {
                NextStepQueueView(actions: workspace.sessionActions) { action in
                    run(action)
                }
            }

            CodexSessionLinksView(workspace: workspace)
                .environmentObject(appState)

            WorkspaceDemandIntakeView(workspace: workspace)
                .environmentObject(appState)
                .id(WorkspaceDetailSection.demand)

            LifecycleDetailView(
                workspace: workspace,
                openAction: {
                    Task {
                        await appState.runLifecycleAction(for: workspace)
                    }
                },
                codexAction: {
                    copyToPasteboard(appState.lifecycleHandoffPrompt(for: workspace))
                    Task {
                        await appState.recordLifecycleHandoffCopied(for: workspace)
                    }
                },
                transitionAction: { transition in
                    appState.requestLifecycleStatusUpdate(transition, in: workspace)
                }
            )

            WorkflowStatusView(
                workspace: workspace,
                completeTaskAction: { task in
                    appState.requestTaskStatusUpdate(task, in: workspace, status: "已完成")
                },
                deferTaskAction: { task in
                    appState.requestTaskStatusUpdate(task, in: workspace, status: "延期")
                },
                openTaskDocumentAction: { task in
                    Task {
                        await appState.openTaskSource(task, in: workspace)
                    }
                },
                taskCodexAction: { task in
                    copyTaskHandoff(task, in: workspace)
                },
                lifecycleAction: { transition in
                    appState.requestLifecycleStatusUpdate(transition, in: workspace)
                }
            )
            .environmentObject(appState)
            .id(WorkspaceDetailSection.workflow)

            ServiceGitStatusSectionView(workspace: workspace)
                .environmentObject(appState)
            .id(WorkspaceDetailSection.services)

            RiskReviewView(
                workspace: workspace,
                checks: riskReviewChecks,
                codexAction: {
                    copyToPasteboard(appState.riskReviewPrompt(for: workspace))
                    Task {
                        await appState.recordRiskReviewHandoffCopied(for: workspace)
                    }
                }
            )
            .environmentObject(appState)
            .id(WorkspaceDetailSection.risk)

            WorkspaceDocumentsHubView(workspace: workspace)
                .environmentObject(appState)
                .id(WorkspaceDetailSection.documents)

            SectionBlock(title: "最近活动 / Activity") {
                ActivityTimelineView(events: workspace.activities)
            }
            .id(WorkspaceDetailSection.activity)

            Spacer()
        }
    }

    private func run(_ action: WorkspaceSessionAction) {
        if action.instructionType == "worktree" {
            appState.presentWorktreeSetup(for: workspace)
            return
        }

        if action.instructionType == "demand" || action.documentKey == "demandIntake" {
            scrollToSection(.demand)
            return
        }

        if action.documentKey == "sql" {
            Task {
                await appState.openSqlReviewDocument(in: workspace)
            }
            return
        }

        let documentPath = workspace.documentLinks[action.documentKey]
            ?? workspace.documentLinks["handoff"]
            ?? "\(workspace.path)/handoff.md"
        Task {
            await appState.loadDocument(path: documentPath)
        }
    }

    private func copyTaskHandoff(_ task: WorkspaceTask, in workspace: WorkspaceSummary) {
        Task {
            await appState.openTaskInCodex(task, in: workspace)
        }
    }

    private var riskReviewChecks: [WorkspaceHealthCheck] {
        workspace.healthChecks.filter { check in
            check.id != "delivery-record" && check.action != "delivery"
        }
    }
}

private struct NextStepQueueView: View {
    let actions: [WorkspaceSessionAction]
    let runAction: (WorkspaceSessionAction) -> Void

    var body: some View {
        SectionBlock(title: "下一步队列 / Next-step queue") {
            VStack(alignment: .leading, spacing: 10) {
                Text("这里收纳由本地工作区证据生成的后续动作。Command Center 决定当前主路径；队列保留可以并行查看或稍后处理的文档、worktree 和交接入口。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(actions) { action in
                    SessionActionRow(action: action) {
                        runAction(action)
                    }
                }
            }
        }
    }
}

private struct ServiceGitStatusSectionView: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary

    private var missingWorktreeCount: Int {
        workspace.services.filter { !$0.worktreeExists }.count
    }

    private var dirtyServiceCount: Int {
        workspace.services.filter { service in
            let normalized = "\(service.gitSummary) \(service.worktree)".lowercased()
            return normalized.contains("dirty")
                || normalized.contains("modified")
                || normalized.contains("uncommitted")
                || normalized.contains("未提交")
                || normalized.contains("有改动")
                || normalized.contains("不是 git")
                || normalized.contains("not git")
                || normalized.contains("检查失败")
                || normalized.contains("failed")
        }.count
    }

    private var serviceDocPath: String {
        workspace.documentLinks["services"] ?? "\(workspace.path)/services.md"
    }

    var body: some View {
        SectionBlock(title: "服务 Git 状态 / Services") {
            VStack(alignment: .leading, spacing: 11) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(statusTone)
                        .frame(width: 15)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.subheadline.weight(.medium))
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    WorkflowMetric(
                        label: "Services",
                        value: "\(workspace.services.count)",
                        tone: workspace.services.isEmpty ? NexusPalette.warning : NexusPalette.accent
                    )
                    WorkflowMetric(
                        label: "Missing WT",
                        value: "\(missingWorktreeCount)",
                        tone: missingWorktreeCount > 0 ? NexusPalette.warning : NexusPalette.success
                    )
                    WorkflowMetric(
                        label: "Dirty",
                        value: "\(dirtyServiceCount)",
                        tone: dirtyServiceCount > 0 ? NexusPalette.warning : NexusPalette.success
                    )
                }

                if workspace.services.isEmpty {
                    ServiceEmptyStateView {
                        Task {
                            await appState.loadDocument(path: serviceDocPath)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(workspace.services) { service in
                            ServiceGitStatusRow(
                                service: service,
                                workspace: workspace,
                                servicesDocumentPath: serviceDocPath
                            )
                            .environmentObject(appState)
                        }
                    }
                }
            }
        }
    }

    private var statusTitle: String {
        if workspace.services.isEmpty {
            return "服务范围待确认 / Scope pending"
        }
        if missingWorktreeCount > 0 {
            return "需要补齐 worktree / Worktree setup needed"
        }
        if dirtyServiceCount > 0 {
            return "存在未提交服务 / Review local changes"
        }
        return "服务状态可用 / Services ready"
    }

    private var statusDetail: String {
        if workspace.services.isEmpty {
            return "先确认涉及服务，后续 worktree、风险、任务和交付检查才有明确范围。"
        }
        if missingWorktreeCount > 0 {
            return "\(missingWorktreeCount) 个服务缺少 workspace-local worktree，可从对应服务行或 Command Center 进入确认创建流程。"
        }
        if dirtyServiceCount > 0 {
            return "\(dirtyServiceCount) 个服务存在未提交状态。服务行可以直接交接 Codex 或打开对应 worktree。"
        }
        return "当前服务范围、worktree 和 source repo 都有可用入口。"
    }

    private var statusTone: Color {
        if workspace.services.isEmpty {
            return NexusPalette.warning
        }
        if missingWorktreeCount > 0 || dirtyServiceCount > 0 {
            return NexusPalette.warning
        }
        return NexusPalette.success
    }
}

private struct ServiceEmptyStateView: View {
    let openServicesDocument: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "doc.text")
                .foregroundStyle(NexusPalette.warning)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 4) {
                Text("还没有确认服务 / No services yet")
                    .font(.caption.weight(.semibold))
                Text("打开 services.md 补齐涉及服务，也可以回到创建/工作区文档阶段先保持待确认。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                openServicesDocument()
            } label: {
                Label("打开服务", systemImage: "doc.text")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct ServiceGitStatusRow: View {
    @EnvironmentObject private var appState: AppState
    let service: ServiceStatus
    let workspace: WorkspaceSummary
    let servicesDocumentPath: String

    private var isDirty: Bool {
        let normalized = "\(service.gitSummary) \(service.worktree)".lowercased()
        return normalized.contains("dirty")
            || normalized.contains("modified")
            || normalized.contains("uncommitted")
            || normalized.contains("未提交")
            || normalized.contains("有改动")
            || normalized.contains("不是 git")
            || normalized.contains("not git")
            || normalized.contains("检查失败")
            || normalized.contains("failed")
    }

    private var statusTone: Color {
        if !service.sourceExists {
            return NexusPalette.danger
        }
        if !service.worktreeExists || isDirty {
            return NexusPalette.warning
        }
        return NexusPalette.success
    }

    private var statusLabel: String {
        if !service.sourceExists {
            return "source 缺失"
        }
        if !service.worktreeExists {
            return "缺 worktree"
        }
        if isDirty {
            return "需复核"
        }
        return "就绪"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: service.worktreeExists ? "checkmark.circle" : "arrow.triangle.branch")
                    .foregroundStyle(statusTone)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 7) {
                        Text(service.name)
                            .font(.subheadline.weight(.semibold))
                            .lineLimit(1)

                        Text(statusLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(statusTone)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 2)
                            .background(statusTone.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    Text("\(service.branch) · \(service.worktree)")
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)

                    Text("source: \(service.gitSummary)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()
            }

            LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                if service.worktreeExists {
                    Button {
                        Task {
                            await appState.openServiceWorktreeInFinder(service, in: workspace)
                        }
                    } label: {
                        Label("Worktree", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("在 Finder 中打开该服务的 workspace-local worktree")

                    Button {
                        Task {
                            await appState.openServiceWorktreeInIDE(service, in: workspace)
                        }
                    } label: {
                        Label("IDE", systemImage: "curlybraces")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("使用 Settings 中的 IDE URL 模板打开该服务 worktree")
                } else {
                    Button {
                        appState.presentWorktreeSetup(for: workspace)
                    } label: {
                        Label("创建 worktree", systemImage: "wrench.and.screwdriver")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(!appState.canSetupWorktrees(in: workspace))
                    .help("进入确认后的 worktree 创建流程")
                }

                if service.sourceExists {
                    Button {
                        Task {
                            await appState.openServiceSourceInFinder(service, in: workspace)
                        }
                    } label: {
                        Label("源仓库", systemImage: "externaldrive")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("在 Finder 中打开 source repo，只用于查看或确认状态")
                } else {
                    Button {
                        Task {
                            await appState.loadDocument(path: servicesDocumentPath)
                        }
                    } label: {
                        Label("服务文档", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("打开 services.md 复核服务范围")
                }

                Button {
                    Task {
                        await appState.openServiceInCodex(service, in: workspace)
                    }
                } label: {
                    Label("服务交接", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("复制该服务的分支、worktree、source 和文档上下文，并打开 Codex")
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(statusTone.opacity(0.16))
        }
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 106), spacing: 8, alignment: .leading)]
    }
}

private struct WorkspaceActiveDocumentBanner: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary
    let openDocumentsAction: () -> Void

    private enum StateKind {
        case loading
        case error
        case ready
    }

    private var activePath: String? {
        if let path = appState.documentLoadingPath, belongsToWorkspace(path) {
            return path
        }
        if let error = appState.documentLoadError, belongsToWorkspace(error.path) {
            return error.path
        }
        if let document = appState.documentPreview, belongsToWorkspace(document.path) {
            return document.path
        }
        return nil
    }

    private var stateKind: StateKind? {
        guard let activePath else {
            return nil
        }
        if appState.documentLoadingPath == activePath {
            return .loading
        }
        if appState.documentLoadError?.path == activePath {
            return .error
        }
        return .ready
    }

    private var documentName: String {
        guard let activePath else {
            return "Document"
        }
        if let document = appState.documentPreview, document.path == activePath {
            return document.name
        }
        return URL(fileURLWithPath: activePath).lastPathComponent
    }

    private var detail: String {
        guard let activePath else {
            return ""
        }
        if let error = appState.documentLoadError, error.path == activePath {
            return error.message
        }
        if let hint = appState.documentFocusHint, hint.path == activePath {
            return "\(hint.lineLabel) · \(hint.title)"
        }
        return activePath
    }

    private var title: String {
        switch stateKind {
        case .loading:
            return "正在打开文档 / Opening document"
        case .error:
            return "文档需要处理 / Document attention"
        case .ready:
            return "当前文档 / Active document"
        case nil:
            return ""
        }
    }

    private var symbol: String {
        switch stateKind {
        case .loading:
            return "arrow.clockwise"
        case .error:
            return "exclamationmark.triangle"
        case .ready:
            return "doc.richtext"
        case nil:
            return "doc.text"
        }
    }

    private var tone: Color {
        switch stateKind {
        case .loading:
            return NexusPalette.accent
        case .error:
            return NexusPalette.warning
        case .ready:
            return NexusPalette.accent
        case nil:
            return .secondary
        }
    }

    var body: some View {
        if let activePath, let stateKind {
            HStack(alignment: .top, spacing: 9) {
                if stateKind == .loading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 16, height: 16)
                        .padding(.top, 1)
                } else {
                    Image(systemName: symbol)
                        .foregroundStyle(tone)
                        .frame(width: 16)
                }

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(title)
                            .font(.caption.weight(.semibold))
                        Text(documentName)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(tone)
                            .lineLimit(1)
                    }

                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                HStack(spacing: 6) {
                    Button {
                        openDocumentsAction()
                    } label: {
                        Label("查看", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button {
                        copyToPasteboard(activePath)
                    } label: {
                        Label("路径", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)

                    Button {
                        appState.clearDocumentPreview()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .controlSize(.mini)
                    .help("只关闭文档预览，不关闭工作区详情 / Close document preview only")
                }
            }
            .padding(10)
            .background(tone.opacity(0.07))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(tone.opacity(0.18))
            }
        }
    }

    private func belongsToWorkspace(_ path: String) -> Bool {
        path == workspace.path || path.hasPrefix("\(workspace.path)/")
    }
}

private enum WorkspaceDetailSection: String, CaseIterable, Identifiable {
    case overview
    case command
    case demand
    case workflow
    case services
    case risk
    case documents
    case activity

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview:
            "概览 / Overview"
        case .command:
            "工作台 / Command"
        case .demand:
            "需求 / Demand"
        case .workflow:
            "任务交付 / Workflow"
        case .services:
            "服务 / Services"
        case .risk:
            "风险 / Risk"
        case .documents:
            "文档 / Docs"
        case .activity:
            "活动 / Activity"
        }
    }

    var systemImage: String {
        switch self {
        case .overview:
            "rectangle.grid.2x2"
        case .command:
            "point.3.connected.trianglepath.dotted"
        case .demand:
            "text.badge.checkmark"
        case .workflow:
            "checklist"
        case .services:
            "square.stack.3d.up"
        case .risk:
            "exclamationmark.triangle"
        case .documents:
            "doc.text"
        case .activity:
            "clock"
        }
    }
}

private struct WorkspaceDetailMapView: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary
    let action: (WorkspaceDetailSection) -> Void

    private var openTaskCount: Int {
        workspace.tasks.filter(\.isActive).count
    }

    private var blockedTaskCount: Int {
        workspace.tasks.filter { $0.isActive && $0.isBlocked }.count
    }

    private var missingWorktreeCount: Int {
        workspace.services.filter { !$0.worktreeExists }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Label("详情导航 / Detail map", systemImage: "map")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(WorkspaceDetailSection.allCases.count) 区块")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                ForEach(WorkspaceDetailSection.allCases) { section in
                    Button {
                        action(section)
                    } label: {
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: section.systemImage)
                                .font(.caption)
                                .foregroundStyle(tone(for: section))
                                .frame(width: 15)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(section.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(detail(for: section))
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .background(NexusPalette.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(tone(for: section).opacity(0.14))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(section.title)
                }
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 118), spacing: 8, alignment: .leading)]
    }

    private func detail(for section: WorkspaceDetailSection) -> String {
        switch section {
        case .overview:
            workspace.lifecycle.label
        case .command:
            primaryPathDetail
        case .demand:
            demandDetail
        case .workflow:
            blockedTaskCount > 0 ? "\(blockedTaskCount) 阻塞" : "\(openTaskCount) 开放"
        case .services:
            workspace.services.isEmpty ? "待确认" : "\(workspace.services.count) 服务 / 缺 \(missingWorktreeCount)"
        case .risk:
            workspace.risks.isEmpty ? "暂无风险" : "\(workspace.risks.count) 信号"
        case .documents:
            "\(workspace.documentLinks.count) 文档"
        case .activity:
            workspace.activities.isEmpty ? "无活动" : "\(workspace.activities.count) 活动"
        }
    }

    private func tone(for section: WorkspaceDetailSection) -> Color {
        switch section {
        case .overview:
            return workspace.isArchived ? .secondary : NexusPalette.accent
        case .command:
            return commandTone
        case .demand:
            return demandTone
        case .workflow:
            if blockedTaskCount > 0 {
                return NexusPalette.danger
            }
            return openTaskCount > 0 ? NexusPalette.warning : NexusPalette.success
        case .services:
            if workspace.services.isEmpty {
                return NexusPalette.warning
            }
            return missingWorktreeCount > 0 ? NexusPalette.warning : NexusPalette.success
        case .risk:
            return workspace.risks.isEmpty ? NexusPalette.success : NexusPalette.warning
        case .documents:
            return NexusPalette.accent
        case .activity:
            return .secondary
        }
    }

    private var commandTone: Color {
        if workspace.isArchived {
            return .secondary
        }
        if !hasConfirmedTargetBranch(workspace.branch) || workspace.services.isEmpty {
            return NexusPalette.danger
        }
        if missingWorktreeCount > 0 || !workspace.risks.isEmpty || openTaskCount > 0 {
            return NexusPalette.warning
        }
        return NexusPalette.success
    }

    private var demandStatus: DemandIntakeStatus? {
        appState.demandIntakeStatus(for: workspace)
    }

    private var demandDetail: String {
        guard let demandStatus else {
            return "待检查"
        }
        if demandStatus.ready {
            return "已就绪"
        }
        return demandStatus.exists ? "缺 \(demandStatus.missingCount)" : "待初始化"
    }

    private var demandTone: Color {
        guard let demandStatus else {
            return .secondary
        }
        if demandStatus.ready {
            return NexusPalette.success
        }
        return demandStatus.exists ? NexusPalette.warning : NexusPalette.accent
    }

    private var primaryPathDetail: String {
        if workspace.isArchived {
            return "已归档"
        }
        if !hasConfirmedTargetBranch(workspace.branch) {
            return "分支"
        }
        if workspace.services.isEmpty {
            return "服务"
        }
        if missingWorktreeCount > 0 {
            return "worktree"
        }
        if !workspace.risks.isEmpty {
            return "风险"
        }
        if openTaskCount > 0 {
            return "任务"
        }
        return "就绪"
    }

    private func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("未确认")
            && !normalized.contains("pending")
            && !normalized.contains("tbd")
            && !normalized.contains("todo")
            && normalized != "-"
    }
}

private enum DetailOverviewStatus {
    case ready
    case review
    case blocked
    case pending

    init(workflowStatus: WorkflowPathStatus) {
        switch workflowStatus {
        case .ready, .archived:
            self = .ready
        case .review, .next:
            self = .review
        case .blocked:
            self = .blocked
        case .pending:
            self = .pending
        }
    }

    var color: Color {
        switch self {
        case .ready:
            NexusPalette.success
        case .review:
            NexusPalette.warning
        case .blocked:
            NexusPalette.danger
        case .pending:
            .secondary
        }
    }

    var symbol: String {
        switch self {
        case .ready:
            "checkmark.circle"
        case .review:
            "exclamationmark.triangle"
        case .blocked:
            "xmark.octagon"
        case .pending:
            "circle.dotted"
        }
    }
}

private struct DetailOverviewItem: Identifiable {
    let id: String
    let label: String
    let value: String
    let detail: String
    let status: DetailOverviewStatus
    let actionLabel: String
    let action: DetailOverviewAction
}

private enum DetailOverviewAction {
    case document(String)
    case setupWorktrees
    case riskHandoff
    case runLocalCheck
    case delivery(WorkflowDeliveryRoute)
    case openCodexSession(CodexSessionLink)
    case bindCodexSession
}

private struct WorkspaceDetailOverviewView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCodexSessionBindPresented = false
    let workspace: WorkspaceSummary
    let lastCheck: LocalAutomationCheckResponse?

    private var items: [DetailOverviewItem] {
        [
            lifecycleItem,
            branchItem,
            servicesItem,
            riskItem,
            taskItem,
            sqlItem,
            deliveryItem,
            sessionItem,
            checkItem
        ]
    }

    private var workflowSummary: WorkspaceWorkflowSummary {
        WorkspaceWorkflowSummary(workspace: workspace)
    }

    private var codexSessionLinks: [CodexSessionLink] {
        appState.codexSessionLinks(for: workspace)
    }

    private var latestCodexSessionLink: CodexSessionLink? {
        codexSessionLinks.first
    }

    private var openTasks: [WorkspaceTask] {
        workspace.tasks.filter(\.isActive)
    }

    private var blockedTaskCount: Int {
        openTasks.filter(\.isBlocked).count
    }

    private var missingWorktreeCount: Int {
        workspace.services.filter { !$0.worktreeExists }.count
    }

    private var lifecycleItem: DetailOverviewItem {
        let status: DetailOverviewStatus
        switch workspace.lifecycle.stage {
        case "done", "archived":
            status = .ready
        case "blocked":
            status = .blocked
        case "setup", "delivery":
            status = .review
        default:
            status = .pending
        }

        return DetailOverviewItem(
            id: "lifecycle",
            label: "阶段",
            value: workspace.lifecycle.label,
            detail: "\(workspace.lifecycle.progress)%",
            status: status,
            actionLabel: lifecycleActionLabel,
            action: .document(workspace.lifecycle.documentKey)
        )
    }

    private var branchItem: DetailOverviewItem {
        let branchReady = Self.hasConfirmedTargetBranch(workspace.branch)
        return DetailOverviewItem(
            id: "branch",
            label: "分支",
            value: branchReady ? shortBranch : "待确认",
            detail: branchReady ? "目标分支" : "branches.md",
            status: branchReady ? .ready : .blocked,
            actionLabel: "打开分支",
            action: .document("branches")
        )
    }

    private var servicesItem: DetailOverviewItem {
        if workspace.services.isEmpty {
            return DetailOverviewItem(
                id: "services",
                label: "服务",
                value: "待确认",
                detail: "services.md",
                status: .blocked,
                actionLabel: "打开服务",
                action: .document("services")
            )
        }

        if missingWorktreeCount > 0 {
            return DetailOverviewItem(
                id: "services",
                label: "服务",
                value: "\(workspace.services.count) 个",
                detail: "缺 \(missingWorktreeCount) 个 worktree",
                status: .review,
                actionLabel: "创建 worktree",
                action: .setupWorktrees
            )
        }

        return DetailOverviewItem(
            id: "services",
            label: "服务",
            value: "\(workspace.services.count) 个",
            detail: "worktree 就绪",
            status: .ready,
            actionLabel: "打开服务",
            action: .document("services")
        )
    }

    private var riskItem: DetailOverviewItem {
        if workspace.risks.isEmpty {
            return DetailOverviewItem(
                id: "risk",
                label: "风险",
                value: "清晰",
                detail: workspace.riskLevel.label,
                status: .ready,
                actionLabel: "打开状态",
                action: .document("status")
            )
        }

        return DetailOverviewItem(
            id: "risk",
            label: "风险",
            value: "\(workspace.risks.count) 个",
            detail: workspace.riskLevel.label,
            status: workspace.riskLevel == .high ? .blocked : .review,
            actionLabel: "风险交接",
            action: .riskHandoff
        )
    }

    private var taskItem: DetailOverviewItem {
        DetailOverviewItem(
            id: "tasks",
            label: "任务",
            value: workflowSummary.taskValue,
            detail: blockedTaskCount > 0 ? "\(openTasks.count) 活跃" : openTasks.isEmpty ? "无活跃任务" : "tasks.md",
            status: DetailOverviewStatus(workflowStatus: workflowSummary.taskStatus),
            actionLabel: "打开任务",
            action: .document("tasks")
        )
    }

    private var deliveryItem: DetailOverviewItem {
        DetailOverviewItem(
            id: "delivery",
            label: "交付",
            value: workflowSummary.deliveryValue,
            detail: workflowSummary.deliveryDetail,
            status: DetailOverviewStatus(workflowStatus: workflowSummary.deliveryStatus),
            actionLabel: workflowSummary.deliveryRoute.displayLabel,
            action: .delivery(workflowSummary.deliveryRoute)
        )
    }

    private var sqlItem: DetailOverviewItem {
        let summary = WorkspaceSqlSummary(workspace: workspace)
        return DetailOverviewItem(
            id: "sql",
            label: "SQL",
            value: summary.value,
            detail: summary.detail,
            status: DetailOverviewStatus(workflowStatus: summary.status),
            actionLabel: summary.actionLabel,
            action: summary.status == .pending ? .runLocalCheck : .document("sql")
        )
    }

    private var sessionItem: DetailOverviewItem {
        if let latestCodexSessionLink {
            return DetailOverviewItem(
                id: "sessions",
                label: "会话",
                value: "\(codexSessionLinks.count) 个",
                detail: "Codex links",
                status: .ready,
                actionLabel: "打开会话",
                action: .openCodexSession(latestCodexSessionLink)
            )
        }

        return DetailOverviewItem(
            id: "sessions",
            label: "会话",
            value: "未绑定",
            detail: "可绑定",
            status: .pending,
            actionLabel: "绑定会话",
            action: .bindCodexSession
        )
    }

    private var checkItem: DetailOverviewItem {
        guard let lastCheck else {
            return DetailOverviewItem(
                id: "check",
                label: "检查",
                value: "未运行",
                detail: "本地检查",
                status: .pending,
                actionLabel: "运行检查",
                action: .runLocalCheck
            )
        }

        let status: DetailOverviewStatus
        let normalizedStatus = lastCheck.status.lowercased()
        switch normalizedStatus {
        case "attention":
            status = .blocked
        case "review":
            status = .review
        default:
            status = .ready
        }

        return DetailOverviewItem(
            id: "check",
            label: "检查",
            value: Self.checkStatusLabel(normalizedStatus),
            detail: lastCheck.generatedAt,
            status: status,
            actionLabel: "重新检查",
            action: .runLocalCheck
        )
    }

    var body: some View {
        LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
            ForEach(items) { item in
                DetailOverviewTile(item: item) {
                    runOverviewAction(item.action)
                }
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .sheet(isPresented: $isCodexSessionBindPresented) {
            CodexSessionBindSheet(workspace: workspace)
                .environmentObject(appState)
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)]
    }

    private var shortBranch: String {
        let branch = workspace.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        if branch.count <= 16 {
            return branch.isEmpty ? "待确认" : branch
        }
        return "\(branch.prefix(13))..."
    }

    private var lifecycleActionLabel: String {
        switch workspace.lifecycle.documentKey {
        case "worktreeScript":
            "打开脚本"
        case "delivery":
            "打开交付"
        case "tasks":
            "打开任务"
        case "branches":
            "打开分支"
        case "services":
            "打开服务"
        case "status":
            "打开状态"
        default:
            "打开文档"
        }
    }

    private func runOverviewAction(_ action: DetailOverviewAction) {
        switch action {
        case .document(let key):
            Task {
                await appState.loadDocument(path: documentPath(for: key))
            }
        case .setupWorktrees:
            appState.presentWorktreeSetup(for: workspace)
        case .riskHandoff:
            copyToPasteboard(appState.riskReviewPrompt(for: workspace))
            Task {
                await appState.recordRiskReviewHandoffCopied(for: workspace)
            }
        case .runLocalCheck:
            Task {
                await appState.runLocalAutomationCheck(actor: "Nexus Overview")
            }
        case .delivery(let route):
            runDeliveryOverviewAction(route)
        case .openCodexSession(let link):
            Task {
                await appState.openCodexSessionLink(link, in: workspace)
            }
        case .bindCodexSession:
            isCodexSessionBindPresented = true
        }
    }

    private func runDeliveryOverviewAction(_ route: WorkflowDeliveryRoute) {
        switch route {
        case .runLocalCheck:
            Task {
                await appState.runLocalAutomationCheck(actor: "Nexus Overview")
            }
        case .updateDelivery:
            Task {
                await appState.openDeliveryUpdateInCodex(workspace)
            }
        case .validationHandoff:
            Task {
                await appState.openValidationPrHandoffInCodex(workspace)
            }
        case .openDelivery:
            Task {
                await appState.loadDocument(path: documentPath(for: "delivery"))
            }
        }
    }

    private func documentPath(for key: String) -> String {
        if key == "sql" {
            return workspace.sqlFiles.first?.path
                ?? workspace.documentLinks["delivery"]
                ?? "\(workspace.path)/交付记录.md"
        }

        if let path = workspace.documentLinks[key] {
            return path
        }

        switch key {
        case "workspace":
            return "\(workspace.path)/workspace.md"
        case "status":
            return "\(workspace.path)/STATUS.md"
        case "services":
            return "\(workspace.path)/services.md"
        case "branches":
            return "\(workspace.path)/branches.md"
        case "tasks":
            return "\(workspace.path)/tasks.md"
        case "delivery":
            return "\(workspace.path)/交付记录.md"
        case "handoff":
            return "\(workspace.path)/handoff.md"
        case "worktreeScript":
            return "\(workspace.path)/scripts/worktree-commands.sh"
        default:
            return workspace.documentLinks["handoff"] ?? "\(workspace.path)/handoff.md"
        }
    }

    private static func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("未确认")
            && !normalized.contains("pending")
            && !normalized.contains("tbd")
            && !normalized.contains("todo")
            && normalized != "-"
    }

    private static func checkStatusLabel(_ status: String) -> String {
        switch status {
        case "attention":
            return "阻塞"
        case "review":
            return "复核"
        default:
            return "通过"
        }
    }
}

private struct DetailOverviewTile: View {
    let item: DetailOverviewItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 5) {
                    Image(systemName: item.status.symbol)
                        .font(.caption2)
                        .foregroundStyle(item.status.color)
                        .frame(width: 12)

                    Text(item.label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Text(item.value)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(item.status.color)
                    .lineLimit(1)

                Text(item.detail)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(item.actionLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(NexusPalette.accent)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(NexusPalette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        }
        .buttonStyle(.plain)
        .help("\(item.detail) · \(item.actionLabel)")
    }
}

private struct CodexSessionLinksView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isBindSheetPresented = false
    @State private var pendingDelete: CodexSessionLink?
    @State private var bindingSuggestionID: CodexSessionSuggestion.ID?
    let workspace: WorkspaceSummary

    private var links: [CodexSessionLink] {
        appState.codexSessionLinks(for: workspace)
    }

    private var suggestions: [CodexSessionSuggestion] {
        appState.codexSessionSuggestions(for: workspace)
    }

    var body: some View {
        SectionBlock(title: "Codex 会话 / Sessions") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: "link")
                        .foregroundStyle(NexusPalette.accent)
                        .frame(width: 15)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("绑定当前需求相关的 Codex 深度链接")
                            .font(.subheadline.weight(.medium))
                        Text("保存到工作区内的 codex-sessions.json；用于回到指定 Codex 会话，而不是重新拼接上下文。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text("\(links.count)")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(links.isEmpty ? .secondary : NexusPalette.accent)
                }

                HStack(spacing: 8) {
                    Button {
                        isBindSheetPresented = true
                    } label: {
                        Label("绑定会话", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        copyToPasteboard(appState.codexSessionLinksPath(for: workspace))
                    } label: {
                        Label("复制文件路径", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("复制 codex-sessions.json 路径 / Copy local session-link file path")
                }

                if !suggestions.isEmpty {
                    CodexSessionSuggestionsView(
                        suggestions: suggestions,
                        bindingSuggestionID: bindingSuggestionID,
                        bindAction: bindSuggestion,
                        copyAction: { suggestion in
                            copyToPasteboard(suggestion.url)
                        }
                    )
                }

                if links.isEmpty {
                    CodexSessionEmptyState()
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(links) { link in
                            CodexSessionLinkRow(
                                link: link,
                                openAction: {
                                    Task {
                                        await appState.openCodexSessionLink(link, in: workspace)
                                    }
                                },
                                copyAction: {
                                    Task {
                                        await appState.copyCodexSessionLink(link, in: workspace)
                                    }
                                },
                                deleteAction: {
                                    pendingDelete = link
                                }
                            )
                        }
                    }
                }

                Text(appState.codexSessionLinksPath(for: workspace))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .sheet(isPresented: $isBindSheetPresented) {
            CodexSessionBindSheet(workspace: workspace)
                .environmentObject(appState)
        }
        .sheet(item: $pendingDelete) { link in
            CodexSessionDeleteSheet(workspace: workspace, link: link)
                .environmentObject(appState)
        }
    }

    private func bindSuggestion(_ suggestion: CodexSessionSuggestion) {
        bindingSuggestionID = suggestion.id
        Task {
            _ = await appState.bindCodexSessionSuggestion(suggestion, to: workspace)
            bindingSuggestionID = nil
        }
    }
}

private struct CodexSessionSuggestionsView: View {
    let suggestions: [CodexSessionSuggestion]
    let bindingSuggestionID: CodexSessionSuggestion.ID?
    let bindAction: (CodexSessionSuggestion) -> Void
    let copyAction: (CodexSessionSuggestion) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "sparkle.magnifyingglass")
                    .foregroundStyle(NexusPalette.accent)
                Text("建议绑定 / Suggested from Agent events")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(suggestions.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ForEach(Array(suggestions.prefix(3))) { suggestion in
                CodexSessionSuggestionRow(
                    suggestion: suggestion,
                    isBinding: bindingSuggestionID == suggestion.id,
                    bindAction: {
                        bindAction(suggestion)
                    },
                    copyAction: {
                        copyAction(suggestion)
                    }
                )
            }
        }
        .padding(10)
        .background(NexusPalette.selected)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CodexSessionSuggestionRow: View {
    let suggestion: CodexSessionSuggestion
    let isBinding: Bool
    let bindAction: () -> Void
    let copyAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "link.badge.plus")
                    .foregroundStyle(NexusPalette.accent)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 3) {
                    Text(suggestion.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(suggestion.url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text("\(suggestion.source) · \(suggestion.eventTitle) · \(suggestion.eventTimestamp)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                }
            }

            HStack(spacing: 8) {
                Button {
                    bindAction()
                } label: {
                    if isBinding {
                        Label("绑定中", systemImage: "hourglass")
                    } else {
                        Label("绑定", systemImage: "plus")
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(isBinding)

                Button {
                    copyAction()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(9)
        .background(NexusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CodexSessionEmptyState: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "link.badge.plus")
                .foregroundStyle(.secondary)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 3) {
                Text("还没有绑定会话链接")
                    .font(.caption.weight(.semibold))
                Text("打开 Codex 后，把该会话的深度链接粘贴进来；后续可以从这个工作区直接回到对应会话。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CodexSessionLinkRow: View {
    let link: CodexSessionLink
    let openAction: () -> Void
    let copyAction: () -> Void
    let deleteAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "link.circle")
                    .foregroundStyle(NexusPalette.accent)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 3) {
                    Text(link.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(link.url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if !link.notes.isEmpty {
                        Text(link.notes)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }

            HStack(spacing: 8) {
                Button {
                    openAction()
                } label: {
                    Label("打开", systemImage: "arrow.up.forward.app")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    copyAction()
                } label: {
                    Label("复制", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button(role: .destructive) {
                    deleteAction()
                } label: {
                    Label("删除", systemImage: "trash")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            HStack(spacing: 8) {
                CodexSessionMeta(label: "created", value: link.createdAt)
                CodexSessionMeta(label: "opened", value: link.lastOpenedAt ?? "never")
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CodexSessionMeta: View {
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 4) {
            Text(label)
                .font(.system(size: 9, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private struct CodexSessionBindSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var title = ""
    @State private var sessionURL = ""
    @State private var notes = ""
    let workspace: WorkspaceSummary

    private var canSave: Bool {
        !sessionURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("绑定 Codex 会话 / Bind session")
                    .font(.title3.weight(.semibold))
                Text("This writes a local codex-sessions.json record inside the workspace.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("会话信息 / Session") {
                    TextField("标题，例如：开发主会话", text: $title)
                    TextField("Codex deep link or web URL", text: $sessionURL)
                    TextField("备注，可选", text: $notes)
                }

                Section("写入位置 / Local file") {
                    SummaryLine(label: "Workspace", value: workspace.name)
                    SummaryLine(label: "File", value: appState.codexSessionLinksPath(for: workspace))
                }
            }

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    Task {
                        let saved = await appState.bindCodexSessionLink(
                            to: workspace,
                            title: title,
                            url: sessionURL,
                            notes: notes
                        )
                        if saved {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!canSave)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(NexusPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

private struct CodexSessionDeleteSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    let workspace: WorkspaceSummary
    let link: CodexSessionLink

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("删除 Codex 会话 / Delete session")
                    .font(.title3.weight(.semibold))
                Text("This only removes the local binding from Nexus. It does not delete the Codex conversation.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SectionBlock(title: "会话 / Session") {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryLine(label: "Title", value: link.title)
                    SummaryLine(label: "URL", value: link.url)
                    SummaryLine(label: "File", value: appState.codexSessionLinksPath(for: workspace))
                }
            }

            Toggle("确认从 codex-sessions.json 删除这条绑定", isOn: $confirmed)

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Delete", role: .destructive) {
                    Task {
                        let deleted = await appState.deleteCodexSessionLink(link, from: workspace)
                        if deleted {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!confirmed)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(NexusPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

private enum NativeDocumentMode: String, CaseIterable, Identifiable {
    case preview = "预览"
    case source = "源码"

    var id: String { rawValue }
}

private struct WorkspaceDocumentEntry: Identifiable {
    let key: String
    let label: String
    let description: String
    let systemImage: String
    let fallbackRelativePath: String
    let canCreateMissing: Bool

    init(
        key: String,
        label: String,
        description: String,
        systemImage: String,
        fallbackRelativePath: String,
        canCreateMissing: Bool = true
    ) {
        self.key = key
        self.label = label
        self.description = description
        self.systemImage = systemImage
        self.fallbackRelativePath = fallbackRelativePath
        self.canCreateMissing = canCreateMissing
    }

    var id: String { key }
}

private struct WorkspaceDocumentsHubView: View {
    @EnvironmentObject private var appState: AppState
    @State private var recoveryEntry: ResolvedWorkspaceDocumentEntry?
    let workspace: WorkspaceSummary

    private let standardEntries: [WorkspaceDocumentEntry] = [
        WorkspaceDocumentEntry(key: "workspace", label: "Workspace", description: "需求范围", systemImage: "doc.text", fallbackRelativePath: "workspace.md"),
        WorkspaceDocumentEntry(key: "status", label: "Status", description: "当前状态", systemImage: "gauge.with.dots.needle.bottom.50percent", fallbackRelativePath: "STATUS.md"),
        WorkspaceDocumentEntry(key: "services", label: "Services", description: "服务范围", systemImage: "square.stack.3d.up", fallbackRelativePath: "services.md"),
        WorkspaceDocumentEntry(key: "branches", label: "Branches", description: "分支记录", systemImage: "arrow.triangle.branch", fallbackRelativePath: "branches.md"),
        WorkspaceDocumentEntry(key: "requirements", label: "Requirements", description: "需求规则", systemImage: "text.badge.checkmark", fallbackRelativePath: "requirements.md"),
        WorkspaceDocumentEntry(key: "acceptance", label: "Acceptance", description: "验收清单", systemImage: "checkmark.seal", fallbackRelativePath: "acceptance.md"),
        WorkspaceDocumentEntry(key: "changes", label: "Changes", description: "变更日志", systemImage: "clock.arrow.circlepath", fallbackRelativePath: "changes.md"),
        WorkspaceDocumentEntry(key: "tasks", label: "Tasks", description: "任务列表", systemImage: "checklist", fallbackRelativePath: "tasks.md"),
        WorkspaceDocumentEntry(key: "delivery", label: "Delivery", description: "交付记录", systemImage: "shippingbox", fallbackRelativePath: "交付记录.md"),
        WorkspaceDocumentEntry(key: "handoff", label: "Handoff", description: "Codex 上下文", systemImage: "point.3.connected.trianglepath.dotted", fallbackRelativePath: "handoff.md"),
        WorkspaceDocumentEntry(key: "bootstrap", label: "Bootstrap", description: "初始化报告", systemImage: "doc.badge.gearshape", fallbackRelativePath: "bootstrap-report.md"),
        WorkspaceDocumentEntry(key: "worktreeScript", label: "Worktree script", description: "创建脚本", systemImage: "terminal", fallbackRelativePath: "scripts/worktree-commands.sh")
    ]

    private var activePreview: DocumentSnapshot? {
        guard let document = appState.documentPreview else {
            return nil
        }
        let knownPaths = Set(documentEntries.map(\.path))
        if knownPaths.contains(document.path) || document.path.hasPrefix(workspace.path) {
            return document
        }
        return nil
    }

    private var activeDocumentError: DocumentLoadError? {
        guard let error = appState.documentLoadError else {
            return nil
        }
        let knownPaths = Set(documentEntries.map(\.path))
        if knownPaths.contains(error.path) || error.path.hasPrefix(workspace.path) {
            return error
        }
        return nil
    }

    private var activeLoadingPath: String? {
        guard let path = appState.documentLoadingPath else {
            return nil
        }
        let knownPaths = Set(documentEntries.map(\.path))
        if knownPaths.contains(path) || path.hasPrefix(workspace.path) {
            return path
        }
        return nil
    }

    private var activeDocumentPath: String? {
        if let activeLoadingPath {
            return activeLoadingPath
        }
        if let error = activeDocumentError {
            return error.path
        }
        if let document = activePreview {
            return document.path
        }
        return nil
    }

    private var activeFocusHint: DocumentFocusHint? {
        guard let hint = appState.documentFocusHint,
              activeDocumentPath == hint.path else {
            return nil
        }
        return hint
    }

    private var documentEntries: [ResolvedWorkspaceDocumentEntry] {
        standardDocumentEntries + sqlDocumentEntries
    }

    private var standardDocumentEntries: [ResolvedWorkspaceDocumentEntry] {
        standardEntries.map { entry in
            ResolvedWorkspaceDocumentEntry(
                entry: entry,
                path: workspace.documentLinks[entry.key] ?? "\(workspace.path)/\(entry.fallbackRelativePath)"
            )
        }
    }

    private var sqlDocumentEntries: [ResolvedWorkspaceDocumentEntry] {
        let notes = workspace.sqlDocuments.map { file in
            let entry = WorkspaceDocumentEntry(
                key: "sql-doc/\(file.relativePath)",
                label: file.fileName,
                description: file.kindLabel,
                systemImage: "doc.text",
                fallbackRelativePath: "sql/\(file.relativePath)",
                canCreateMissing: false
            )
            return ResolvedWorkspaceDocumentEntry(entry: entry, path: file.path)
        }
        let artifacts = workspace.sqlFiles.map { file in
            let entry = WorkspaceDocumentEntry(
                key: "sql/\(file.relativePath)",
                label: file.fileName,
                description: file.kindLabel,
                systemImage: file.kind == "rollback" ? "arrow.uturn.backward.circle" : "doc.plaintext",
                fallbackRelativePath: "sql/\(file.relativePath)",
                canCreateMissing: false
            )
            return ResolvedWorkspaceDocumentEntry(entry: entry, path: file.path)
        }
        return notes + artifacts
    }

    private func recoverableEntry(for error: DocumentLoadError) -> ResolvedWorkspaceDocumentEntry? {
        guard error.message.localizedCaseInsensitiveContains("does not exist") else {
            return nil
        }
        return documentEntries.first { entry in
            entry.path == error.path
                && entry.entry.canCreateMissing
                && entry.path == "\(workspace.path)/\(entry.entry.fallbackRelativePath)"
        }
    }

    var body: some View {
        SectionBlock(title: "文档入口 / Documents") {
            VStack(alignment: .leading, spacing: 12) {
                WorkspaceDocumentGroupHeader(title: "标准文档 / Standard", count: standardDocumentEntries.count)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(standardDocumentEntries) { entry in
                        documentButton(for: entry)
                    }
                }

                WorkspaceDocumentGroupHeader(title: "SQL 产物 / SQL artifacts", count: sqlDocumentEntries.count)
                if sqlDocumentEntries.isEmpty {
                    WorkspaceSqlDocumentsEmptyState()
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(sqlDocumentEntries) { entry in
                            documentButton(for: entry)
                        }
                    }
                }

                if let loadingPath = activeLoadingPath {
                    NativeDocumentLoadingView(path: loadingPath)
                } else if let error = activeDocumentError {
                    let recovery = recoverableEntry(for: error)
                    NativeDocumentErrorView(
                        error: error,
                        canCreateDocument: recovery != nil,
                        isCreatingDocument: appState.isCreatingDocument,
                        retryAction: {
                            Task {
                                await appState.loadDocument(path: error.path)
                            }
                        },
                        copyPathAction: {
                            copyToPasteboard(error.path)
                        },
                        finderAction: {
                            Task {
                                await appState.openWorkspaceInFinder(workspace)
                            }
                        },
                        createAction: {
                            recoveryEntry = recovery
                        }
                    )
                } else if let document = activePreview {
                    NativeDocumentPreview(
                        document: document,
                        focusHint: activeFocusHint,
                        copyPathAction: {
                            copyToPasteboard(document.path)
                        },
                        closeAction: {
                            appState.clearDocumentPreview()
                        }
                    )
                } else {
                    NativeDocumentEmptyState()
                }
            }
        }
        .sheet(item: $recoveryEntry) { entry in
            CreateMissingDocumentSheet(workspace: workspace, entry: entry)
                .environmentObject(appState)
        }
    }

    private func documentButton(for entry: ResolvedWorkspaceDocumentEntry) -> some View {
        Button {
            Task {
                await appState.loadDocument(path: entry.path)
            }
        } label: {
            WorkspaceDocumentEntryTile(
                entry: entry,
                isActive: entry.path == activeDocumentPath,
                isLoading: entry.path == activeLoadingPath
            )
        }
        .buttonStyle(.plain)
        .disabled(appState.isDocumentLoading)
        .help(entry.path)
    }
}

private struct ResolvedWorkspaceDocumentEntry: Identifiable {
    let entry: WorkspaceDocumentEntry
    let path: String

    var id: String { entry.key }
    var label: String { entry.label }
    var description: String { entry.description }
    var systemImage: String { entry.systemImage }
}

private struct WorkspaceDocumentGroupHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .font(.caption.weight(.semibold))
            Text("\(count)")
                .font(.system(size: 10, design: .monospaced).weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(NexusPalette.badge)
                .clipShape(Capsule())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct WorkspaceDemandIntakeView: View {
    @EnvironmentObject private var appState: AppState
    @State private var demandName = ""
    @State private var lanhuLink = ""
    @State private var notes = ""
    @State private var confirmed = false
    let workspace: WorkspaceSummary

    private var status: DemandIntakeStatus {
        appState.demandIntakeDisplayStatus(for: workspace)
    }

    private var isLoading: Bool {
        appState.demandIntakeLoadingWorkspaceID == workspace.id
    }

    private var actionDisabled: Bool {
        !confirmed || appState.isInitializingDemandIntake
    }

    var body: some View {
        SectionBlock(title: "需求预检 / Demand intake") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: status.ready ? "checkmark.seal" : "text.badge.checkmark")
                        .foregroundStyle(statusColor)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.subheadline.weight(.semibold))
                        Text(status.directoryPath)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Button {
                        Task {
                            await appState.refreshDemandIntakeStatus(for: workspace)
                        }
                    } label: {
                        Label(isLoading ? "检查中" : "刷新", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isLoading)
                }

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
                    WorkflowMetric(label: "目录", value: status.exists ? "exists" : "missing", tone: status.exists ? NexusPalette.success : NexusPalette.warning)
                    WorkflowMetric(label: "文件", value: "\(readyFileCount)/\(status.files.count)", tone: status.ready ? NexusPalette.success : NexusPalette.warning)
                    WorkflowMetric(label: "缺失", value: "\(status.missingCount)", tone: status.missingCount == 0 ? NexusPalette.success : NexusPalette.warning)
                }

                LazyVGrid(columns: fileColumns, alignment: .leading, spacing: 8) {
                    ForEach(status.files) { file in
                        DemandIntakeFileRow(file: file) {
                            Task {
                                await appState.loadDocument(path: file.path)
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    TextField("需求名称", text: $demandName)
                        .textFieldStyle(.roundedBorder)
                    TextField("蓝湖链接", text: $lanhuLink)
                        .textFieldStyle(.roundedBorder)
                    TextField("备注", text: $notes, axis: .vertical)
                        .textFieldStyle(.roundedBorder)
                        .lineLimit(2...4)
                }

                Toggle("确认创建或补齐需求预检文件", isOn: $confirmed)
                    .toggleStyle(.checkbox)

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                    Button {
                        Task {
                            let response = await appState.initializeDemandIntake(
                                in: workspace,
                                demandName: demandName,
                                lanhuLink: lanhuLink,
                                notes: notes,
                                confirmed: confirmed
                            )
                            if response != nil {
                                confirmed = false
                            }
                        }
                    } label: {
                        Label(
                            appState.isInitializingDemandIntake
                                ? "处理中"
                                : (status.exists ? "补齐文件" : "初始化预检"),
                            systemImage: "doc.badge.plus"
                        )
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(actionDisabled)

                    Button {
                        Task {
                            await appState.loadDocument(path: requirementFile?.path ?? "\(status.directoryPath)/requirement.md")
                        }
                    } label: {
                        Label("打开确认卡", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!(requirementFile?.exists ?? false))

                    Button {
                        Task {
                            await appState.copyDemandIntakePrompt(
                                for: workspace,
                                demandName: demandName,
                                lanhuLink: lanhuLink,
                                notes: notes,
                                openCodex: false
                            )
                        }
                    } label: {
                        Label("复制预检", systemImage: "doc.on.clipboard")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task {
                            await appState.copyDemandIntakePrompt(
                                for: workspace,
                                demandName: demandName,
                                lanhuLink: lanhuLink,
                                notes: notes,
                                openCodex: true
                            )
                        }
                    } label: {
                        Label("打开 Codex", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
        .task(id: workspace.id) {
            if demandName.isEmpty {
                demandName = workspace.name
            }
            if appState.demandIntakeStatus(for: workspace) == nil {
                await appState.refreshDemandIntakeStatus(for: workspace)
            }
        }
    }

    private var statusTitle: String {
        if status.ready {
            return "需求预检已就绪"
        }
        if status.exists {
            return "需求预检文件待补齐"
        }
        return "需求预检待初始化"
    }

    private var statusColor: Color {
        if status.ready {
            return NexusPalette.success
        }
        return status.exists ? NexusPalette.warning : NexusPalette.accent
    }

    private var readyFileCount: Int {
        status.files.filter(\.exists).count
    }

    private var requirementFile: DemandIntakeFileStatus? {
        status.files.first { $0.key == "requirement" }
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)]
    }

    private var fileColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 142), spacing: 8, alignment: .leading)]
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 8, alignment: .leading)]
    }
}

private struct DemandIntakeFileRow: View {
    let file: DemandIntakeFileStatus
    let openAction: () -> Void

    var body: some View {
        Button {
            openAction()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: file.exists ? "checkmark.circle.fill" : "circle.dashed")
                    .font(.caption)
                    .foregroundStyle(file.exists ? NexusPalette.success : .secondary)
                    .frame(width: 14)

                VStack(alignment: .leading, spacing: 3) {
                    Text(file.label)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(file.filename)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .background(file.exists ? NexusPalette.selected : NexusPalette.badge)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(file.exists ? NexusPalette.success.opacity(0.24) : Color.clear)
            }
        }
        .buttonStyle(.plain)
        .disabled(!file.exists)
        .help(file.path)
    }
}

private struct WorkspaceSqlDocumentsEmptyState: View {
    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "cylinder.split.1x2")
                .foregroundStyle(.secondary)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 2) {
                Text("sql/ 下暂无可预览的 .sql 文件。")
                    .font(.caption.weight(.semibold))
                Text("如果交付记录声明 SQL 变更，本地检查会要求同时补正式 SQL 和回滚 SQL。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct WorkspaceDocumentEntryTile: View {
    let entry: ResolvedWorkspaceDocumentEntry
    let isActive: Bool
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .controlSize(.small)
                        .frame(width: 14, height: 14)
                } else {
                    Image(systemName: entry.systemImage)
                        .font(.caption)
                        .foregroundStyle(isActive ? NexusPalette.accent : .secondary)
                        .frame(width: 14)
                }

                Text(entry.label)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }

            Text(entry.description)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(isActive ? NexusPalette.selected : NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(isActive ? NexusPalette.accent.opacity(0.34) : Color.clear)
        }
    }
}

private struct NativeDocumentLoadingView: View {
    let path: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            ProgressView()
                .controlSize(.small)
                .padding(.top, 1)

            VStack(alignment: .leading, spacing: 3) {
                Text("正在打开文档 / Opening document")
                    .font(.caption.weight(.semibold))
                Text(URL(fileURLWithPath: path).lastPathComponent)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CreateMissingDocumentSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    let workspace: WorkspaceSummary
    let entry: ResolvedWorkspaceDocumentEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("创建缺失文档 / Create document")
                    .font(.title3.weight(.semibold))
                Text("确认后，Nexus 会创建这个标准工作区文件。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            SectionBlock(title: "文档 / Document") {
                VStack(alignment: .leading, spacing: 8) {
                    SummaryLine(label: "工作区 / Workspace", value: workspace.name)
                    SummaryLine(label: "文档 / Document", value: entry.label)
                    SummaryLine(label: "相对路径 / Relative path", value: entry.entry.fallbackRelativePath)
                    SummaryLine(label: "目标路径 / Target", value: entry.path)
                }
            }

            Text("这只会创建缺失的标准骨架文件，不会覆盖已有文件。创建后请补充真实需求、服务、任务或交付内容。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Toggle("确认创建缺失的标准文档", isOn: $confirmed)
                .toggleStyle(.checkbox)

            HStack {
                Button("取消") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button(appState.isCreatingDocument ? "创建中" : "创建文档") {
                    Task {
                        let response = await appState.createWorkspaceDocument(
                            in: workspace,
                            documentKey: entry.entry.key,
                            relativePath: entry.entry.fallbackRelativePath,
                            documentLabel: entry.label,
                            confirmed: confirmed
                        )
                        if response != nil {
                            dismiss()
                        }
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!confirmed || appState.isCreatingDocument)
            }

            if let error = appState.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(NexusPalette.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(22)
        .frame(width: 560)
    }
}

private struct NativeDocumentErrorView: View {
    let error: DocumentLoadError
    let canCreateDocument: Bool
    let isCreatingDocument: Bool
    let retryAction: () -> Void
    let copyPathAction: () -> Void
    let finderAction: () -> Void
    let createAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "exclamationmark.triangle")
                    .foregroundStyle(NexusPalette.warning)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 3) {
                    Text("文档打开失败 / Document unavailable")
                        .font(.subheadline.weight(.medium))
                    Text(error.message)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(error.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
            }

            HStack(spacing: 8) {
                if canCreateDocument {
                    Button {
                        createAction()
                    } label: {
                        Label(isCreatingDocument ? "创建中" : "创建文档", systemImage: "doc.badge.plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(isCreatingDocument)
                    .help("确认后创建缺失的标准工作区文档 / Create the missing standard workspace document")
                }

                Button {
                    retryAction()
                } label: {
                    Label("重试", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    copyPathAction()
                } label: {
                    Label("复制路径", systemImage: "doc.on.doc")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    finderAction()
                } label: {
                    Label("Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(NexusPalette.warning.opacity(0.24))
        }
    }
}

private struct NativeDocumentEmptyState: View {
    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "doc.text.magnifyingglass")
                .foregroundStyle(.secondary)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 3) {
                Text("选择一个文档后在这里预览。")
                    .font(.caption.weight(.semibold))
                Text("如果标准文档缺失，Nexus 会在这里提供确认创建入口；不可读文件仍可重试、复制路径或打开 Finder。")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct NativeDocumentPreview: View {
    let document: DocumentSnapshot
    let focusHint: DocumentFocusHint?
    let copyPathAction: () -> Void
    let closeAction: () -> Void
    @State private var mode: NativeDocumentMode = .preview

    private var shouldRenderPreview: Bool {
        document.isMarkdown && mode == .preview
    }

    private var markdownText: AttributedString? {
        let options = AttributedString.MarkdownParsingOptions(
            interpretedSyntax: .full,
            failurePolicy: .returnPartiallyParsedIfPossible
        )
        return try? AttributedString(markdown: document.content, options: options)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: document.isMarkdown ? "doc.richtext" : "doc.plaintext")
                    .foregroundStyle(NexusPalette.accent)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 2) {
                    Text(document.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                    Text(document.path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if document.isMarkdown {
                    Picker("Document mode", selection: $mode) {
                        ForEach(NativeDocumentMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .controlSize(.small)
                    .frame(width: 112)
                }

                Button {
                    copyPathAction()
                } label: {
                    Image(systemName: "doc.on.doc")
                }
                .buttonStyle(.borderless)
                .help("复制文档路径 / Copy document path")

                Button {
                    closeAction()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("只关闭文档预览，保留工作区详情 / Close document preview only")
            }

            if let focusHint {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "text.line.first.and.arrowtriangle.forward")
                        .foregroundStyle(NexusPalette.accent)
                        .frame(width: 15)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(focusHint.lineLabel) · \(focusHint.title)")
                            .font(.caption.weight(.semibold))
                            .lineLimit(1)
                        Text(focusHint.detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(NexusPalette.selected)
                .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
            }

            ScrollView {
                if shouldRenderPreview, let markdownText {
                    Text(markdownText)
                        .font(.caption)
                        .lineSpacing(3)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                } else {
                    Text(document.content.isEmpty ? "文档为空。" : document.content)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                }
            }
            .frame(minHeight: 220, maxHeight: 420)
            .padding(10)
            .background(NexusPalette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(NexusPalette.border)
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .onChange(of: document.path) { _ in
            mode = document.isMarkdown ? .preview : .source
        }
        .onAppear {
            mode = document.isMarkdown ? .preview : .source
        }
    }
}

private struct WorkspaceCommandCenterView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCodexSessionBindPresented = false
    let workspace: WorkspaceSummary
    let demandAction: () -> Void

    private var openTaskCount: Int {
        workspace.tasks.filter(\.isActive).count
    }

    private var missingWorktreeCount: Int {
        workspace.services.filter { !$0.worktreeExists }.count
    }

    private var blockedTaskCount: Int {
        workspace.tasks.filter { $0.isActive && $0.isBlocked }.count
    }

    private var workflowSummary: WorkspaceWorkflowSummary {
        WorkspaceWorkflowSummary(workspace: workspace)
    }

    private var codexSessionLinks: [CodexSessionLink] {
        appState.codexSessionLinks(for: workspace)
    }

    private var latestCodexSessionLink: CodexSessionLink? {
        codexSessionLinks.first
    }

    private var codexSessionValue: String {
        codexSessionLinks.isEmpty ? "未绑定" : "\(codexSessionLinks.count) 个"
    }

    private var sqlSummary: WorkspaceSqlSummary {
        WorkspaceSqlSummary(workspace: workspace)
    }

    private var codexSessionTone: Color {
        codexSessionLinks.isEmpty ? .secondary : NexusPalette.success
    }

    private var demandIntakeCheck: WorkspaceHealthCheck? {
        workspace.healthChecks.first { check in
            check.id == "demand-intake" || check.action == "demandIntake"
        }
    }

    private var demandIntakeStatus: DemandIntakeStatus? {
        appState.demandIntakeStatus(for: workspace)
    }

    private var demandIntakeReady: Bool {
        if let demandIntakeStatus {
            return demandIntakeStatus.ready
        }
        if let demandIntakeCheck {
            return demandIntakeCheck.status == "pass"
        }
        return true
    }

    private var demandIntakePathStatus: WorkflowPathStatus {
        if demandIntakeReady {
            return .ready
        }
        if let demandIntakeStatus {
            return demandIntakeStatus.exists ? .review : .blocked
        }
        if let demandIntakeCheck, demandIntakeCheck.status == "fail" {
            return .blocked
        }
        return .review
    }

    private var demandIntakeValue: String {
        if let demandIntakeStatus {
            if demandIntakeStatus.ready {
                return "已就绪"
            }
            return demandIntakeStatus.exists ? "缺 \(demandIntakeStatus.missingCount)" : "待初始化"
        }
        guard let demandIntakeCheck else {
            return "未检查"
        }
        return demandIntakeCheck.status == "pass" ? "已就绪" : "待处理"
    }

    private var demandIntakeTone: Color {
        if demandIntakeReady {
            return NexusPalette.success
        }
        if let demandIntakeStatus, demandIntakeStatus.exists {
            return NexusPalette.warning
        }
        if let demandIntakeCheck, demandIntakeCheck.status == "warning" {
            return NexusPalette.warning
        }
        return NexusPalette.danger
    }

    private var serviceValue: String {
        if workspace.services.isEmpty {
            return "待确认"
        }
        if missingWorktreeCount > 0 {
            return "\(workspace.services.count) 个 / 缺 \(missingWorktreeCount)"
        }
        return "\(workspace.services.count) 个就绪"
    }

    private var branchTone: Color {
        Self.hasConfirmedTargetBranch(workspace.branch) ? NexusPalette.accent : NexusPalette.warning
    }

    private var worktreeTone: Color {
        if workspace.services.isEmpty {
            return NexusPalette.warning
        }
        return missingWorktreeCount == 0 ? NexusPalette.success : NexusPalette.warning
    }

    private var taskTone: Color {
        workflowSummary.taskStatus.color
    }

    private var deliveryTone: Color {
        workflowSummary.deliveryStatus.color
    }

    private var deliveryPrimaryAction: CommandCenterPrimaryAction {
        switch workflowSummary.deliveryRoute {
        case .runLocalCheck:
            .localCheck
        case .updateDelivery:
            .deliveryHandoff
        case .validationHandoff:
            .validationHandoff
        case .openDelivery:
            .document("delivery")
        }
    }

    private var lifecycleTone: Color {
        switch workspace.lifecycle.stage {
        case "blocked":
            return NexusPalette.danger
        case "setup", "delivery":
            return NexusPalette.warning
        case "done", "archived":
            return NexusPalette.success
        default:
            return NexusPalette.accent
        }
    }

    private var primaryStep: CommandCenterPrimaryStep {
        if workspace.isArchived {
            return CommandCenterPrimaryStep(
                title: "已归档 / Archived",
                detail: "这个工作区已退出活跃流。需要恢复时先查看 handoff 和交付记录，再决定是否重新进入开发。",
                status: .archived,
                systemImage: "archivebox",
                actionLabel: "查看文档",
                actionSystemImage: "doc.text",
                tone: .secondary,
                action: .document("handoff")
            )
        }

        if !demandIntakeReady {
            return CommandCenterPrimaryStep(
                title: "完成需求预检 / Demand intake",
                detail: demandIntakeCheck?.detail ?? "开发前先补齐 workspace-local 需求预检文件，把蓝湖和补充说明整理成 requirement、questions、scope、tasks 和 delivery。",
                status: demandIntakePathStatus,
                systemImage: "text.badge.checkmark",
                actionLabel: "打开预检",
                actionSystemImage: "text.badge.checkmark",
                tone: demandIntakeTone,
                action: .demandIntake
            )
        }

        if !Self.hasConfirmedTargetBranch(workspace.branch) {
            return CommandCenterPrimaryStep(
                title: "确认目标分支 / Confirm branch",
                detail: "分支仍是待确认状态。先补齐 branches.md 或 workspace.md，后续 worktree 和交付检查才有可靠基准。",
                status: .blocked,
                systemImage: "arrow.triangle.branch",
                actionLabel: "打开分支",
                actionSystemImage: "doc.text",
                tone: NexusPalette.danger,
                action: .document("branches")
            )
        }

        if workspace.services.isEmpty {
            return CommandCenterPrimaryStep(
                title: "确认服务范围 / Confirm services",
                detail: "服务范围为空。先确认涉及服务，Nexus 才能检查 worktree、风险和交付影响面。",
                status: .blocked,
                systemImage: "square.stack.3d.up",
                actionLabel: "打开服务",
                actionSystemImage: "doc.text",
                tone: NexusPalette.danger,
                action: .document("services")
            )
        }

        if missingWorktreeCount > 0 {
            return CommandCenterPrimaryStep(
                title: "创建缺失 worktree / Setup worktrees",
                detail: "\(missingWorktreeCount) 个服务还没有 workspace-local worktree。先完成隔离工作副本，再进入代码修改。",
                status: .next,
                systemImage: "arrow.triangle.branch",
                actionLabel: "创建 worktree",
                actionSystemImage: "wrench.and.screwdriver",
                tone: NexusPalette.warning,
                action: .worktree
            )
        }

        if workspace.riskLevel == .high || !workspace.risks.isEmpty {
            return CommandCenterPrimaryStep(
                title: "复核风险 / Review risks",
                detail: "当前存在 \(workspace.risks.count) 个风险信号。建议先复制风险复核上下文交给 Codex，再决定是否继续交付。",
                status: workspace.riskLevel == .high ? .blocked : .review,
                systemImage: "exclamationmark.triangle",
                actionLabel: "风险交接",
                actionSystemImage: "point.3.connected.trianglepath.dotted",
                tone: workspace.riskLevel == .high ? NexusPalette.danger : NexusPalette.warning,
                action: .riskPrompt
            )
        }

        if blockedTaskCount > 0 {
            return CommandCenterPrimaryStep(
                title: "处理阻塞任务 / Resolve blocked tasks",
                detail: "\(blockedTaskCount) 个任务仍处于阻塞状态。先打开 tasks.md，确认完成、延期或继续拆解。",
                status: .blocked,
                systemImage: "checklist",
                actionLabel: "打开任务",
                actionSystemImage: "checklist",
                tone: NexusPalette.danger,
                action: .document("tasks")
            )
        }

        if openTaskCount > 0 {
            return CommandCenterPrimaryStep(
                title: "处理活跃任务 / Review tasks",
                detail: "\(openTaskCount) 个任务仍未关闭。开发前后都可以从这里确认任务状态和交付影响。",
                status: .next,
                systemImage: "checklist",
                actionLabel: "打开任务",
                actionSystemImage: "checklist",
                tone: NexusPalette.accent,
                action: .document("tasks")
            )
        }

        if workspace.lifecycle.stage == "delivery" {
            return CommandCenterPrimaryStep(
                title: "整理交付 / Prepare delivery",
                detail: "任务和 worktree 已基本就绪。现在把交付记录、SQL、验证和风险说明交给 Codex 做最后整理。",
                status: .next,
                systemImage: "shippingbox",
                actionLabel: "交付交接",
                actionSystemImage: "point.3.connected.trianglepath.dotted",
                tone: NexusPalette.warning,
                action: .deliveryHandoff
            )
        }

        return CommandCenterPrimaryStep(
            title: latestCodexSessionLink == nil ? "继续开发 / Continue with Codex" : "回到 Codex 会话 / Resume Codex session",
            detail: latestCodexSessionLink == nil
                ? "当前主流程没有明显阻塞。可以把工作区上下文交给 Codex 继续开发或复核。"
                : "当前主流程没有明显阻塞，且已有 \(codexSessionLinks.count) 个绑定会话。优先回到最近会话，避免重新解释上下文。",
            status: .ready,
            systemImage: latestCodexSessionLink == nil ? "point.3.connected.trianglepath.dotted" : "link",
            actionLabel: latestCodexSessionLink == nil ? "交接 Codex" : "打开会话",
            actionSystemImage: latestCodexSessionLink == nil ? "point.3.connected.trianglepath.dotted" : "arrow.up.forward.app",
            tone: NexusPalette.success,
            action: latestCodexSessionLink.map(CommandCenterPrimaryAction.codexSession) ?? .codex
        )
    }

    private var sessionPathItems: [CommandCenterPathItem] {
        [
            scopePathItem,
            demandPathItem,
            worktreePathItem,
            riskPathItem,
            taskPathItem,
            sqlPathItem,
            deliveryPathItem,
            codexSessionPathItem,
            handoffPathItem
        ]
    }

    private var demandPathItem: CommandCenterPathItem {
        CommandCenterPathItem(
            title: "预检 / Intake",
            detail: demandIntakeValue,
            status: demandIntakePathStatus,
            systemImage: "text.badge.checkmark",
            actionLabel: demandIntakeReady ? "查看预检" : "打开预检",
            action: .demandIntake
        )
    }

    private var scopePathItem: CommandCenterPathItem {
        if !Self.hasConfirmedTargetBranch(workspace.branch) {
            return CommandCenterPathItem(
                title: "范围 / Scope",
                detail: "分支待确认",
                status: .blocked,
                systemImage: "arrow.triangle.branch",
                actionLabel: "打开分支",
                action: .document("branches")
            )
        }

        if workspace.services.isEmpty {
            return CommandCenterPathItem(
                title: "范围 / Scope",
                detail: "服务待确认",
                status: .blocked,
                systemImage: "square.stack.3d.up",
                actionLabel: "打开服务",
                action: .document("services")
            )
        }

        return CommandCenterPathItem(
            title: "范围 / Scope",
            detail: "\(workspace.services.count) 个服务",
            status: .ready,
            systemImage: "scope",
            actionLabel: "打开服务",
            action: .document("services")
        )
    }

    private var worktreePathItem: CommandCenterPathItem {
        if workspace.services.isEmpty {
            return CommandCenterPathItem(
                title: "Worktree",
                detail: "等待服务范围",
                status: .pending,
                systemImage: "arrow.triangle.branch",
                actionLabel: "打开服务",
                action: .document("services")
            )
        }

        if missingWorktreeCount > 0 {
            return CommandCenterPathItem(
                title: "Worktree",
                detail: "缺 \(missingWorktreeCount) 个",
                status: .review,
                systemImage: "arrow.triangle.branch",
                actionLabel: "创建 worktree",
                action: .worktree
            )
        }

        return CommandCenterPathItem(
            title: "Worktree",
            detail: "已就绪",
            status: .ready,
            systemImage: "arrow.triangle.branch",
            actionLabel: "打开脚本",
            action: .document("worktreeScript")
        )
    }

    private var riskPathItem: CommandCenterPathItem {
        if workspace.riskLevel == .high {
            return CommandCenterPathItem(
                title: "风险 / Risk",
                detail: "\(workspace.risks.count) 个高风险",
                status: .blocked,
                systemImage: "exclamationmark.triangle",
                actionLabel: "风险交接",
                action: .riskPrompt
            )
        }

        if !workspace.risks.isEmpty {
            return CommandCenterPathItem(
                title: "风险 / Risk",
                detail: "\(workspace.risks.count) 个待复核",
                status: .review,
                systemImage: "exclamationmark.triangle",
                actionLabel: "风险交接",
                action: .riskPrompt
            )
        }

        return CommandCenterPathItem(
            title: "风险 / Risk",
            detail: "暂无风险",
            status: .ready,
            systemImage: "checkmark.shield",
            actionLabel: "打开状态",
            action: .document("status")
        )
    }

    private var taskPathItem: CommandCenterPathItem {
        CommandCenterPathItem(
            title: "任务 / Tasks",
            detail: workflowSummary.taskValue,
            status: workflowSummary.taskStatus,
            systemImage: workflowSummary.taskStatus == .ready ? "checklist.checked" : "checklist",
            actionLabel: "打开任务",
            action: .document("tasks")
        )
    }

    private var deliveryPathItem: CommandCenterPathItem {
        CommandCenterPathItem(
            title: "交付 / Delivery",
            detail: workflowSummary.deliveryValue,
            status: workflowSummary.deliveryStatus,
            systemImage: deliverySymbol,
            actionLabel: workflowSummary.deliveryRoute.displayLabel,
            action: deliveryPrimaryAction
        )
    }

    private var sqlPathItem: CommandCenterPathItem {
        let action: CommandCenterPrimaryAction = sqlSummary.status == .pending
            ? .localCheck
            : .document("sql")
        return CommandCenterPathItem(
            title: "SQL",
            detail: sqlSummary.value,
            status: sqlSummary.status,
            systemImage: "cylinder.split.1x2",
            actionLabel: sqlSummary.actionLabel,
            action: action
        )
    }

    private var handoffPathItem: CommandCenterPathItem {
        CommandCenterPathItem(
            title: "交接 / Handoff",
            detail: workspace.isArchived ? "查阅上下文" : "复制接力包",
            status: workspace.isArchived ? .pending : .ready,
            systemImage: "point.3.connected.trianglepath.dotted",
            actionLabel: workspace.isArchived ? "查看交接" : "交接 Codex",
            action: workspace.isArchived ? .document("handoff") : .codex
        )
    }

    private var codexSessionPathItem: CommandCenterPathItem {
        if let latestCodexSessionLink {
            return CommandCenterPathItem(
                title: "会话 / Sessions",
                detail: "\(codexSessionLinks.count) 个已绑定",
                status: .ready,
                systemImage: "link",
                actionLabel: "打开会话",
                action: .codexSession(latestCodexSessionLink)
            )
        }

        return CommandCenterPathItem(
            title: "会话 / Sessions",
            detail: "未绑定",
            status: .pending,
            systemImage: "link.badge.plus",
            actionLabel: "绑定会话",
            action: .bindCodexSession
        )
    }

    var body: some View {
        SectionBlock(title: "工作台 / Command Center") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: lifecycleSymbol)
                        .foregroundStyle(lifecycleTone)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(workspace.lifecycle.label)
                            .font(.subheadline.weight(.semibold))
                        Text(workspace.lifecycle.nextAction)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Text("\(workspace.lifecycle.progress)%")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(lifecycleTone)
                }

                ProgressView(value: workspace.lifecycle.normalizedProgress)
                    .progressViewStyle(.linear)
                    .tint(lifecycleTone)

                CommandCenterPrimaryStepView(step: primaryStep) {
                    runPrimaryStep(primaryStep)
                }

                CommandCenterSessionPathView(items: sessionPathItems) { action in
                    runPrimaryAction(action)
                }

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
                    WorkflowMetric(label: "分支", value: shortBranch, tone: branchTone)
                    WorkflowMetric(label: "服务", value: serviceValue, tone: worktreeTone)
                    WorkflowMetric(label: "风险", value: workspace.riskLevel.label, tone: workspace.risks.isEmpty ? NexusPalette.success : NexusPalette.warning)
                    WorkflowMetric(label: "预检", value: demandIntakeValue, tone: demandIntakeTone)
                    WorkflowMetric(label: "任务", value: workflowSummary.taskValue, tone: taskTone)
                    WorkflowMetric(label: "SQL", value: sqlSummary.value, tone: sqlStatusTone)
                    WorkflowMetric(label: "交付", value: workflowSummary.deliveryValue, tone: deliveryTone)
                    WorkflowMetric(label: "会话", value: codexSessionValue, tone: codexSessionTone)
                }

                CommandCenterQuickActionsView(
                    sessionLabel: latestCodexSessionLink == nil ? "绑定会话" : "最近会话",
                    sessionSystemImage: latestCodexSessionLink == nil ? "link.badge.plus" : "arrow.up.forward.app",
                    nextActionLabel: nextActionLabel,
                    nextActionSystemImage: nextActionSymbol,
                    isChecking: appState.isRunningAutomationCheck,
                    codexAction: {
                        Task {
                            await appState.openWorkspaceInCodex(workspace)
                        }
                    },
                    sessionAction: {
                        if let latestCodexSessionLink {
                            Task {
                                await appState.openCodexSessionLink(latestCodexSessionLink, in: workspace)
                            }
                        } else {
                            isCodexSessionBindPresented = true
                        }
                    },
                    lifecycleAction: {
                        Task {
                            await appState.runLifecycleAction(for: workspace)
                        }
                    },
                    checkAction: {
                        Task {
                            await appState.runLocalAutomationCheck(actor: "Nexus Command Center")
                        }
                    },
                    finderAction: {
                        Task {
                            await appState.openWorkspaceInFinder(workspace)
                        }
                    },
                    copyLinkAction: {
                        Task {
                            await appState.copyWorkspaceDeepLink(workspace)
                        }
                    },
                    ideAction: {
                        Task {
                            await appState.openWorkspaceInIDE(workspace)
                        }
                    },
                    terminalAction: {
                        Task {
                            await appState.openWorkspaceInTerminal(workspace)
                        }
                    }
                )

                if appState.isRunningAutomationCheck || appState.lastAutomationCheck != nil {
                    LocalCheckReceiptView(
                        check: appState.lastAutomationCheck,
                        actor: appState.lastAutomationCheckActor,
                        isRunning: appState.isRunningAutomationCheck,
                        contextLabel: "工作台 / Command Center",
                        copyAction: copyLocalCheckSummary
                    )
                }

                Text("主路径用于决定下一步；工作流路径用于定位范围、worktree、风险、任务、交付和会话状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .sheet(isPresented: $isCodexSessionBindPresented) {
            CodexSessionBindSheet(workspace: workspace)
                .environmentObject(appState)
        }
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)]
    }

    private func runPrimaryStep(_ step: CommandCenterPrimaryStep) {
        runPrimaryAction(step.action)
    }

    private func runPrimaryAction(_ action: CommandCenterPrimaryAction) {
        switch action {
        case .codex:
            Task {
                await appState.openWorkspaceInCodex(workspace)
            }
        case .document(let key):
            let path = workspace.documentLinks[key]
                ?? workspace.documentLinks["handoff"]
                ?? "\(workspace.path)/handoff.md"
            Task {
                await appState.loadDocument(path: path)
            }
        case .riskPrompt:
            copyToPasteboard(appState.riskReviewPrompt(for: workspace))
            Task {
                await appState.recordRiskReviewHandoffCopied(for: workspace)
            }
        case .worktree:
            appState.presentWorktreeSetup(for: workspace)
        case .demandIntake:
            demandAction()
        case .localCheck:
            Task {
                await appState.runLocalAutomationCheck(actor: "Nexus Command Center")
            }
        case .deliveryHandoff:
            Task {
                await appState.openDeliveryUpdateInCodex(workspace)
            }
        case .validationHandoff:
            Task {
                await appState.openValidationPrHandoffInCodex(workspace)
            }
        case .codexSession(let link):
            Task {
                await appState.openCodexSessionLink(link, in: workspace)
            }
        case .bindCodexSession:
            isCodexSessionBindPresented = true
        }
    }

    private func copyLocalCheckSummary(_ check: LocalAutomationCheckResponse) {
        copyToPasteboard(
            localCheckSummaryPayload(
                title: "Nexus local check",
                actor: appState.lastAutomationCheckActor,
                check: check
            )
        )
    }

    private var shortBranch: String {
        let branch = workspace.branch.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !branch.isEmpty else { return "pending" }
        if branch.count <= 18 {
            return branch
        }
        return "\(branch.prefix(15))..."
    }

    private var lifecycleSymbol: String {
        switch workspace.lifecycle.stage {
        case "scoping":
            return "magnifyingglass"
        case "setup":
            return "wrench.and.screwdriver"
        case "developing":
            return "hammer"
        case "delivery":
            return "doc.text"
        case "done":
            return "checkmark.seal"
        case "archived":
            return "archivebox"
        case "blocked":
            return "pause.circle"
        default:
            return "point.3.connected.trianglepath.dotted"
        }
    }

    private var deliverySymbol: String {
        switch workflowSummary.deliveryStatus {
        case .ready:
            return "checkmark.seal"
        case .review, .next:
            return "shippingbox"
        case .blocked:
            return "xmark.octagon"
        case .archived:
            return "archivebox"
        case .pending:
            return "doc.text"
        }
    }

    private var sqlStatusTone: Color {
        switch sqlSummary.status {
        case .ready:
            return NexusPalette.success
        case .blocked:
            return NexusPalette.danger
        case .review:
            return NexusPalette.warning
        case .pending:
            return .secondary
        case .next:
            return NexusPalette.accent
        case .archived:
            return .secondary
        }
    }

    private var nextActionLabel: String {
        switch workspace.lifecycle.documentKey {
        case "worktreeScript":
            return "打开 Worktree"
        case "delivery":
            return "打开交付"
        case "tasks":
            return "打开任务"
        case "branches":
            return "打开分支"
        case "services":
            return "打开服务"
        case "status":
            return "打开状态"
        default:
            return "打开下一步"
        }
    }

    private var nextActionSymbol: String {
        switch workspace.lifecycle.documentKey {
        case "worktreeScript":
            return "arrow.triangle.branch"
        case "delivery":
            return "doc.text"
        case "tasks":
            return "checklist"
        case "branches":
            return "arrow.triangle.branch"
        case "services":
            return "square.stack.3d.up"
        default:
            return "arrow.right.circle"
        }
    }

    private static func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("pending")
            && !normalized.contains("todo")
            && normalized != "-"
    }
}

private enum CommandCenterPrimaryAction {
    case codex
    case document(String)
    case riskPrompt
    case worktree
    case demandIntake
    case localCheck
    case deliveryHandoff
    case validationHandoff
    case codexSession(CodexSessionLink)
    case bindCodexSession
}

private struct CommandCenterPrimaryStep {
    let title: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let actionLabel: String
    let actionSystemImage: String
    let tone: Color
    let action: CommandCenterPrimaryAction
}

private struct CommandCenterPrimaryStepView: View {
    let step: CommandCenterPrimaryStep
    let action: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: step.systemImage)
                .foregroundStyle(step.tone)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 7) {
                    Text("主路径 / Primary path")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(step.status.displayLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(step.status.color)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(step.status.color.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                Text(step.title)
                    .font(.subheadline.weight(.semibold))

                Text(step.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button {
                action()
            } label: {
                Label(step.actionLabel, systemImage: step.actionSystemImage)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private extension WorkflowPathStatus {
    var color: Color {
        switch self {
        case .ready:
            NexusPalette.success
        case .review:
            NexusPalette.warning
        case .blocked:
            NexusPalette.danger
        case .pending:
            .secondary
        case .next:
            NexusPalette.accent
        case .archived:
            .secondary
        }
    }
}

private struct CommandCenterPathItem: Identifiable {
    let title: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let actionLabel: String
    let action: CommandCenterPrimaryAction

    var id: String { title }

    init(
        title: String,
        detail: String,
        status: WorkflowPathStatus,
        systemImage: String,
        actionLabel: String = "",
        action: CommandCenterPrimaryAction
    ) {
        self.title = title
        self.detail = detail
        self.status = status
        self.systemImage = systemImage
        self.actionLabel = actionLabel
        self.action = action
    }
}

private struct CommandCenterSessionPathView: View {
    let items: [CommandCenterPathItem]
    let action: (CommandCenterPrimaryAction) -> Void

    private var readyCount: Int {
        items.filter { $0.status == .ready }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 7) {
                Image(systemName: "point.3.connected.trianglepath.dotted")
                    .foregroundStyle(NexusPalette.accent)
                Text("工作流路径 / Workflow path")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("\(readyCount)/\(items.count) ready")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 118), spacing: 8)], alignment: .leading, spacing: 8) {
                ForEach(items) { item in
                    Button {
                        action(item.action)
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack(spacing: 6) {
                                Image(systemName: item.systemImage)
                                    .font(.caption)
                                    .foregroundStyle(item.status.color)
                                    .frame(width: 14)

                                Text(item.title)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                            }

                            Text(item.detail)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)

                            if !item.actionLabel.isEmpty {
                                Text(item.actionLabel)
                                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                    .foregroundStyle(NexusPalette.accent)
                                    .lineLimit(1)
                            }

                            Text(item.status.displayLabel)
                                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                                .foregroundStyle(item.status.color)
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(9)
                        .background(NexusPalette.panel)
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(item.status.color.opacity(0.16))
                        }
                    }
                    .buttonStyle(.plain)
                    .help(item.actionLabel.isEmpty ? item.detail : "\(item.detail) · \(item.actionLabel)")
                }
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct CommandCenterQuickActionsView: View {
    let sessionLabel: String
    let sessionSystemImage: String
    let nextActionLabel: String
    let nextActionSystemImage: String
    let isChecking: Bool
    let codexAction: () -> Void
    let sessionAction: () -> Void
    let lifecycleAction: () -> Void
    let checkAction: () -> Void
    let finderAction: () -> Void
    let copyLinkAction: () -> Void
    let ideAction: () -> Void
    let terminalAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("快捷动作 / Quick actions")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            CommandCenterActionGroup(title: "交接 / Handoff") {
                Button {
                    codexAction()
                } label: {
                    Label("交接 Codex", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    sessionAction()
                } label: {
                    Label(sessionLabel, systemImage: sessionSystemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            CommandCenterActionGroup(title: "下一步 / Next") {
                Button {
                    lifecycleAction()
                } label: {
                    Label(nextActionLabel, systemImage: nextActionSystemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    checkAction()
                } label: {
                    Label(isChecking ? "检查中" : "本地检查", systemImage: "checklist.checked")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isChecking)
            }

            CommandCenterActionGroup(title: "本地打开 / Local") {
                Button {
                    finderAction()
                } label: {
                    Label("Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    copyLinkAction()
                } label: {
                    Label("复制链接", systemImage: "link")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    ideAction()
                } label: {
                    Label("IDE", systemImage: "curlybraces")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    terminalAction()
                } label: {
                    Label("Terminal", systemImage: "terminal")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
    }
}

private struct CommandCenterActionGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                content
            }
        }
    }

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 8, alignment: .leading)]
    }
}

private struct LifecycleCompactView: View {
    let lifecycle: WorkspaceLifecycle

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 8) {
                Label(lifecycle.label, systemImage: symbol)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(color)
                Spacer()
                Text("\(lifecycle.progress)%")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            ProgressView(value: lifecycle.normalizedProgress)
                .progressViewStyle(.linear)
                .tint(color)

            Text(lifecycle.nextAction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var symbol: String {
        switch lifecycle.stage {
        case "scoping":
            "magnifyingglass"
        case "setup":
            "wrench.and.screwdriver"
        case "developing":
            "hammer"
        case "delivery":
            "doc.text"
        case "done":
            "checkmark.seal"
        case "archived":
            "archivebox"
        case "blocked":
            "pause.circle"
        default:
            "point.3.connected.trianglepath.dotted"
        }
    }

    private var color: Color {
        switch lifecycle.stage {
        case "blocked":
            NexusPalette.danger
        case "delivery", "setup":
            NexusPalette.warning
        case "done", "archived":
            NexusPalette.success
        default:
            NexusPalette.accent
        }
    }
}

private struct LifecycleDetailView: View {
    let workspace: WorkspaceSummary
    let openAction: () -> Void
    let codexAction: () -> Void
    let transitionAction: (LifecycleTransition) -> Void

    var body: some View {
        SectionBlock(title: "生命周期 / Lifecycle") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: symbol)
                        .foregroundStyle(color)
                        .frame(width: 16)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(workspace.lifecycle.label)
                            .font(.subheadline.weight(.semibold))
                        Text(workspace.lifecycle.detail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Text("\(workspace.lifecycle.progress)%")
                        .font(.system(.caption, design: .monospaced).weight(.semibold))
                        .foregroundStyle(color)
                }

                ProgressView(value: workspace.lifecycle.normalizedProgress)
                    .progressViewStyle(.linear)
                    .tint(color)

                VStack(alignment: .leading, spacing: 4) {
                    Text("下一步 / Next")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(workspace.lifecycle.nextAction)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack(spacing: 8) {
                    Button(actionLabel) {
                        openAction()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button("Codex") {
                        codexAction()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                if !workspace.lifecycleTransitions.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("状态写回 / Status writeback")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)

                        FlowTagsButtonRow(transitions: workspace.lifecycleTransitions) { transition in
                            transitionAction(transition)
                        }
                    }
                }
            }
        }
    }

    private var actionLabel: String {
        switch workspace.lifecycle.documentKey {
        case "worktreeScript":
            "Worktree"
        case "delivery":
            "Delivery"
        case "tasks":
            "Tasks"
        case "branches":
            "Branch"
        case "services":
            "Services"
        default:
            "Open"
        }
    }

    private var symbol: String {
        switch workspace.lifecycle.stage {
        case "scoping":
            "magnifyingglass"
        case "setup":
            "wrench.and.screwdriver"
        case "developing":
            "hammer"
        case "delivery":
            "doc.text"
        case "done":
            "checkmark.seal"
        case "archived":
            "archivebox"
        case "blocked":
            "pause.circle"
        default:
            "point.3.connected.trianglepath.dotted"
        }
    }

    private var color: Color {
        switch workspace.lifecycle.stage {
        case "blocked":
            NexusPalette.danger
        case "delivery", "setup":
            NexusPalette.warning
        case "done", "archived":
            NexusPalette.success
        default:
            NexusPalette.accent
        }
    }
}

private struct SessionActionRow: View {
    let action: WorkspaceSessionAction
    let onRun: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: symbol)
                .foregroundStyle(color)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(action.label)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(priorityLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Text(action.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Text(statusLabel)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            Button(actionButtonLabel) {
                onRun()
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
    }

    private var actionButtonLabel: String {
        switch action.instructionType {
        case "worktree":
            "创建"
        case "continue":
            "交接"
        default:
            "打开"
        }
    }

    private var statusLabel: String {
        switch action.status {
        case "blocked":
            "阻塞"
        case "recommended":
            "下一步"
        default:
            "稍后"
        }
    }

    private var priorityLabel: String {
        switch action.priority {
        case "high":
            "P0"
        case "medium":
            "P1"
        default:
            "P2"
        }
    }

    private var symbol: String {
        switch action.instructionType {
        case "worktree":
            "terminal"
        case "git":
            "arrow.triangle.branch"
        case "task":
            "checklist"
        case "delivery":
            "doc.text"
        default:
            "sparkles"
        }
    }

    private var color: Color {
        switch action.status {
        case "blocked":
            NexusPalette.danger
        case "recommended":
            NexusPalette.accent
        default:
            Color.gray
        }
    }
}

private struct WorkspaceCreationNextStepsView: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary

    private var missingWorktrees: [String] {
        appState.missingWorktreeServices(in: workspace)
    }

    private var creationReceipt: CreateWorkspaceResponse? {
        guard appState.lastCreatedWorkspace?.folder == workspace.folder else {
            return nil
        }
        return appState.lastCreatedWorkspace
    }

    private var worktreeHint: String {
        if workspace.services.isEmpty {
            return "先补齐服务范围，之后才能生成准确的 worktree。"
        }
        if !branchLooksConfirmed {
            return "目标分支仍待确认，确认分支后再创建 worktree。"
        }
        if missingWorktrees.isEmpty {
            return "当前服务已具备 workspace-local worktree。"
        }
        return "缺失 worktree: \(missingWorktrees.joined(separator: ", "))"
    }

    private var branchLooksConfirmed: Bool {
        let normalizedBranch = workspace.branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedBranch.isEmpty else { return false }
        return !["待确认", "未确认", "pending", "tbd", "todo"].contains { normalizedBranch.contains($0) }
    }

    private var followUpSteps: [WorkspaceCreationFollowUpStep] {
        [
            serviceScopeStep,
            targetBranchStep,
            worktreeStep,
            handoffStep,
            localCheckStep
        ]
    }

    private var serviceScopeStep: WorkspaceCreationFollowUpStep {
        if workspace.services.isEmpty {
            return WorkspaceCreationFollowUpStep(
                id: "services",
                title: "确认服务范围 / Services",
                detail: "服务范围仍待确认，先补齐 services.md，后续 worktree 和风险检查才有可靠目标。",
                status: "review",
                tone: NexusPalette.warning,
                systemImage: "square.stack.3d.up",
                actionLabel: "打开 services.md",
                actionSystemImage: "doc.text",
                action: .openServices
            )
        }
        return WorkspaceCreationFollowUpStep(
            id: "services",
            title: "确认服务范围 / Services",
            detail: "\(workspace.services.count) 个服务已记录，可继续确认分支和 worktree。",
            status: "ready",
            tone: NexusPalette.success,
            systemImage: "square.stack.3d.up",
            actionLabel: "复核 services.md",
            actionSystemImage: "doc.text",
            action: .openServices
        )
    }

    private var targetBranchStep: WorkspaceCreationFollowUpStep {
        if branchLooksConfirmed {
            return WorkspaceCreationFollowUpStep(
                id: "branch",
                title: "确认目标分支 / Branch",
                detail: workspace.branch,
                status: "ready",
                tone: NexusPalette.success,
                systemImage: "arrow.triangle.branch",
                actionLabel: "复核 branches.md",
                actionSystemImage: "doc.text",
                action: .openBranches
            )
        }
        return WorkspaceCreationFollowUpStep(
            id: "branch",
            title: "确认目标分支 / Branch",
            detail: "目标分支仍待确认，创建 worktree 前先更新 branches.md 或 workspace.md。",
            status: "blocked",
            tone: NexusPalette.danger,
            systemImage: "arrow.triangle.branch",
            actionLabel: "打开 branches.md",
            actionSystemImage: "doc.text",
            action: .openBranches
        )
    }

    private var worktreeStep: WorkspaceCreationFollowUpStep {
        if workspace.services.isEmpty {
            return WorkspaceCreationFollowUpStep(
                id: "worktree",
                title: "准备 worktree / Worktrees",
                detail: "服务范围未确认，暂不创建 workspace-local worktree。",
                status: "pending",
                tone: NexusPalette.warning,
                systemImage: "terminal",
                actionLabel: "先补服务",
                actionSystemImage: "square.stack.3d.up",
                action: .openServices
            )
        }
        if !branchLooksConfirmed {
            return WorkspaceCreationFollowUpStep(
                id: "worktree",
                title: "准备 worktree / Worktrees",
                detail: "目标分支未确认，暂不执行 worktree 创建。",
                status: "blocked",
                tone: NexusPalette.danger,
                systemImage: "terminal",
                actionLabel: "先定分支",
                actionSystemImage: "arrow.triangle.branch",
                action: .openBranches
            )
        }
        if missingWorktrees.isEmpty {
            return WorkspaceCreationFollowUpStep(
                id: "worktree",
                title: "准备 worktree / Worktrees",
                detail: "当前服务已具备 workspace-local worktree。",
                status: "ready",
                tone: NexusPalette.success,
                systemImage: "terminal",
                actionLabel: nil,
                actionSystemImage: nil,
                action: nil
            )
        }
        return WorkspaceCreationFollowUpStep(
            id: "worktree",
            title: "准备 worktree / Worktrees",
            detail: "缺失 \(missingWorktrees.count) 个 worktree: \(missingWorktrees.joined(separator: ", "))",
            status: "next",
            tone: NexusPalette.accent,
            systemImage: "terminal",
            actionLabel: "创建 worktree",
            actionSystemImage: "arrow.triangle.branch",
            action: .setupWorktrees
        )
    }

    private var handoffStep: WorkspaceCreationFollowUpStep {
        WorkspaceCreationFollowUpStep(
            id: "handoff",
            title: "打开交接文档 / Handoff",
            detail: "先看 handoff.md，再决定是否进入 Codex 接力。",
            status: "next",
            tone: NexusPalette.accent,
            systemImage: "point.3.connected.trianglepath.dotted",
            actionLabel: "打开 handoff",
            actionSystemImage: "doc.text",
            action: .openHandoff
        )
    }

    private var localCheckStep: WorkspaceCreationFollowUpStep {
        WorkspaceCreationFollowUpStep(
            id: "local-check",
            title: "运行本地检查 / Local check",
            detail: "建档后跑一次检查，把分支、worktree、任务、交付和 SQL 风险收敛到 Action Center。",
            status: "next",
            tone: NexusPalette.accent,
            systemImage: "checklist",
            actionLabel: appState.isRunningAutomationCheck ? "检查中" : "运行检查",
            actionSystemImage: "checklist",
            action: .runLocalCheck
        )
    }

    var body: some View {
        SectionBlock(title: "创建后下一步 / Next steps") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "checkmark.circle")
                        .foregroundStyle(NexusPalette.success)
                        .frame(width: 16)

                    VStack(alignment: .leading, spacing: 3) {
                        Text("Workspace created")
                            .font(.subheadline.weight(.semibold))
                        Text("Nexus 已选中新工作区。先看 handoff，再按服务和分支状态决定是否创建 worktree。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button {
                        appState.dismissCreatedWorkspaceFollowUp()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .help("Dismiss")
                }

                VStack(alignment: .leading, spacing: 6) {
                    SummaryLine(label: "Path", value: workspace.path)
                    SummaryLine(label: "Branch", value: workspace.branch)
                    SummaryLine(
                        label: "Services",
                        value: workspace.services.isEmpty
                            ? "服务范围待确认 / Scope pending"
                            : workspace.services.map(\.name).joined(separator: ", ")
                    )
                }

                Text(worktreeHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let creationReceipt {
                    InitializationReceiptView(receipt: creationReceipt)
                }

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(followUpSteps) { step in
                        WorkspaceCreationFollowUpRow(
                            step: step,
                            isDisabled: actionIsDisabled(step.action),
                            performAction: performAction
                        )
                    }
                }

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await appState.openWorkspaceInCodex(workspace)
                        }
                    } label: {
                        Label("交接 Codex / Open Codex", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        appState.dismissCreatedWorkspaceFollowUp()
                    } label: {
                        Label("稍后处理 / Later", systemImage: "clock")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }
            }
        }
    }

    private func documentPath(for key: String, fallback: String) -> String {
        workspace.documentLinks[key] ?? "\(workspace.path)/\(fallback)"
    }

    private func actionIsDisabled(_ action: WorkspaceCreationFollowUpAction?) -> Bool {
        switch action {
        case .openServices, .openBranches, .openHandoff:
            return appState.isDocumentLoading
        case .setupWorktrees:
            return !appState.canSetupWorktrees(in: workspace)
        case .runLocalCheck:
            return appState.isRunningAutomationCheck
        case nil:
            return true
        }
    }

    private func performAction(_ action: WorkspaceCreationFollowUpAction) {
        switch action {
        case .openServices:
            Task {
                await appState.loadDocument(path: documentPath(for: "services", fallback: "services.md"))
            }
        case .openBranches:
            Task {
                await appState.loadDocument(path: documentPath(for: "branches", fallback: "branches.md"))
            }
        case .openHandoff:
            Task {
                await appState.loadHandoffForSelectedWorkspace()
            }
        case .setupWorktrees:
            appState.presentWorktreeSetup(for: workspace)
        case .runLocalCheck:
            Task {
                await appState.runLocalAutomationCheck()
            }
        }
    }
}

private enum WorkspaceCreationFollowUpAction {
    case openServices
    case openBranches
    case setupWorktrees
    case openHandoff
    case runLocalCheck
}

private struct WorkspaceCreationFollowUpStep: Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: String
    let tone: Color
    let systemImage: String
    let actionLabel: String?
    let actionSystemImage: String?
    let action: WorkspaceCreationFollowUpAction?
}

private struct WorkspaceCreationFollowUpRow: View {
    let step: WorkspaceCreationFollowUpStep
    let isDisabled: Bool
    let performAction: (WorkspaceCreationFollowUpAction) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: step.systemImage)
                .foregroundStyle(step.tone)
                .frame(width: 16)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(step.title)
                        .font(.caption.weight(.semibold))
                    Text(step.status)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(step.tone)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(step.tone.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                }

                Text(step.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if let action = step.action,
               let actionLabel = step.actionLabel,
               let actionSystemImage = step.actionSystemImage {
                Button {
                    performAction(action)
                } label: {
                    Label(actionLabel, systemImage: actionSystemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(isDisabled)
            }
        }
        .padding(9)
        .background(step.tone.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InitializationReceiptView: View {
    let receipt: CreateWorkspaceResponse

    private var checks: [WorkspaceInitializationCheck] {
        receipt.initializationChecks ?? []
    }

    private var files: [WorkspaceInitializationFile] {
        receipt.generatedFiles ?? []
    }

    private var failedCheckCount: Int {
        checks.filter { $0.status == "fail" || $0.status == "blocker" }.count
    }

    private var warningCheckCount: Int {
        checks.filter { $0.status == "warning" || $0.status == "review" }.count
    }

    private var missingFileCount: Int {
        files.filter { !$0.exists }.count
    }

    private var headline: String {
        if failedCheckCount > 0 || missingFileCount > 0 {
            return "初始化有缺失项，先处理后再交接 Codex。"
        }
        if warningCheckCount > 0 {
            return "初始化已完成，但仍有待确认项。"
        }
        return "初始化文件和 STATUS 初始状态已确认。"
    }

    private var headlineColor: Color {
        if failedCheckCount > 0 || missingFileCount > 0 {
            return NexusPalette.danger
        }
        if warningCheckCount > 0 {
            return NexusPalette.warning
        }
        return NexusPalette.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: failedCheckCount > 0 || missingFileCount > 0 ? "xmark.octagon" : warningCheckCount > 0 ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(headlineColor)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 2) {
                    Text("初始化回执 / Initialization receipt")
                        .font(.subheadline.weight(.medium))
                    Text(headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text("\(files.filter(\.exists).count)/\(files.count)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(headlineColor)
            }

            if checks.isEmpty && files.isEmpty {
                Text("当前 bridge 未返回初始化回执。刷新工作区后仍可通过 Documents 和 Workflow 继续检查。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                    ForEach(checks) { check in
                        InitializationCheckRow(check: check)
                    }
                }

                DisclosureGroup("生成文件 / Generated files") {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(files) { file in
                            InitializationFileRow(file: file)
                        }
                    }
                    .padding(.top, 6)
                }
                .font(.caption)
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InitializationCheckRow: View {
    let check: WorkspaceInitializationCheck

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .foregroundStyle(color)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 2) {
                Text(check.label)
                    .font(.caption.weight(.semibold))
                Text(check.detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(color)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(color.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var normalizedStatus: String {
        check.status.lowercased()
    }

    private var label: String {
        switch normalizedStatus {
        case "pass", "ok", "ready":
            return "pass"
        case "warning", "review":
            return "review"
        default:
            return "fail"
        }
    }

    private var icon: String {
        switch label {
        case "pass":
            return "checkmark.circle"
        case "review":
            return "exclamationmark.triangle"
        default:
            return "xmark.octagon"
        }
    }

    private var color: Color {
        switch label {
        case "pass":
            return NexusPalette.success
        case "review":
            return NexusPalette.warning
        default:
            return NexusPalette.danger
        }
    }
}

private struct InitializationFileRow: View {
    let file: WorkspaceInitializationFile

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: file.exists ? "checkmark.circle" : "xmark.octagon")
                .foregroundStyle(file.exists ? NexusPalette.success : NexusPalette.danger)
                .frame(width: 15)
            Text(file.label)
                .font(.caption)
            Spacer()
            Text(file.relativePath)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
    }
}

private enum DeliveryFocusAction {
    case openTasks
    case openDelivery
    case openBranches
    case openServices
    case setupWorktrees
    case reviewRisks
    case runCheck
    case openCodex
    case deliveryHandoff
    case sqlHandoff
    case validationPrHandoff
    case enterDelivery
    case markDone
}

private struct DeliveryFocusStep {
    let title: String
    let detail: String
    let statusLabel: String
    let tone: Color
    let systemImage: String
    let actionLabel: String
    let actionSystemImage: String
    let action: DeliveryFocusAction
}

private struct DeliveryFocusCardView: View {
    let step: DeliveryFocusStep
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: step.systemImage)
                    .foregroundStyle(step.tone)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text(step.title)
                            .font(.subheadline.weight(.semibold))
                            .fixedSize(horizontal: false, vertical: true)
                        Text(step.statusLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(step.tone)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(step.tone.opacity(0.1))
                            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }

                    Text(step.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack {
                Button {
                    action()
                } label: {
                    Label(step.actionLabel, systemImage: step.actionSystemImage)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("执行当前交付焦点建议 / Run the current delivery focus action")

                Spacer()
            }
        }
        .padding(10)
        .background(step.tone.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(step.tone.opacity(0.18))
        }
    }
}

private struct WorkflowActionTrayView: View {
    let isRunningCheck: Bool
    let openTasksAction: () -> Void
    let openDeliveryAction: () -> Void
    let runCheckAction: () -> Void
    let workspaceHandoffAction: () -> Void
    let deliveryHandoffAction: () -> Void
    let validationPrHandoffAction: () -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 8, alignment: .leading)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "slider.horizontal.3")
                    .foregroundStyle(NexusPalette.accent)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 2) {
                    Text("工作流动作 / Actions")
                        .font(.subheadline.weight(.medium))
                    Text("按事实来源、检查和 Agent 交接分组处理，避免交付动作散落。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 9) {
                actionLane(title: "文档 / Docs", detail: "回到 Markdown 来源") {
                    Button {
                        openTasksAction()
                    } label: {
                        Label("任务", systemImage: "checklist")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("打开 tasks.md / Open tasks document")

                    Button {
                        openDeliveryAction()
                    } label: {
                        Label("交付", systemImage: "doc.text")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("打开交付记录 / Open delivery record")
                }

                actionLane(title: "检查 / Check", detail: "刷新风险、任务和 worktree 信号") {
                    Button {
                        runCheckAction()
                    } label: {
                        Label(isRunningCheck ? "检查中" : "本地检查", systemImage: "checklist.checked")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isRunningCheck)
                    .help("运行本地自动化检查 / Run local checks")
                }

                actionLane(title: "Agent 交接 / Handoff", detail: "把不同阶段的上下文交给 Codex") {
                    Button {
                        workspaceHandoffAction()
                    } label: {
                        Label("工作区", systemImage: "point.3.connected.trianglepath.dotted")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("复制工作区上下文并打开 Codex / Copy workspace context and open Codex")

                    Button {
                        deliveryHandoffAction()
                    } label: {
                        Label("补交付", systemImage: "doc.badge.arrow.up")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .help("复制交付补充上下文并打开 Codex / Copy delivery update context and open Codex")

                    Button {
                        validationPrHandoffAction()
                    } label: {
                        Label("PR 交接", systemImage: "checkmark.seal")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .help("复制验证与 PR 交接上下文并打开 Codex / Copy validation and PR handoff context and open Codex")
                }
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func actionLane<Content: View>(
        title: String,
        detail: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            LazyVGrid(columns: columns, alignment: .leading, spacing: 8) {
                content()
            }
        }
    }
}

private struct WorkflowStatusView: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary
    let completeTaskAction: (WorkspaceTask) -> Void
    let deferTaskAction: (WorkspaceTask) -> Void
    let openTaskDocumentAction: (WorkspaceTask) -> Void
    let taskCodexAction: (WorkspaceTask) -> Void
    let lifecycleAction: (LifecycleTransition) -> Void

    private var openTasks: [WorkspaceTask] {
        workspace.tasks.filter(\.isActive)
    }

    private var blockedTasks: [WorkspaceTask] {
        openTasks.filter(\.isBlocked)
    }

    private var deliveryCheck: WorkspaceHealthCheck? {
        workspace.healthChecks.first { check in
            check.id == "delivery-record" || check.action == "delivery"
        }
    }

    private var deliveryRisk: RiskAlert? {
        workspace.risks.first { risk in
            let normalized = "\(risk.title) \(risk.detail)".lowercased()
            return normalized.contains("交付") || normalized.contains("delivery")
        }
    }

    private var deliveryStatusText: String {
        if let deliveryCheck {
            return deliveryCheck.detail
        }
        if let deliveryRisk {
            return deliveryRisk.detail
        }
        return "交付记录暂无明显占位内容。"
    }

    private var deliveryStatusLabel: String {
        guard let deliveryCheck else {
            return deliveryRisk == nil ? "ready" : "review"
        }
        switch deliveryCheck.status {
        case "pass":
            return "ready"
        case "warning":
            return "review"
        default:
            return "blocked"
        }
    }

    private var deliveryColor: Color {
        switch deliveryStatusLabel {
        case "ready":
            return NexusPalette.success
        case "review":
            return NexusPalette.warning
        default:
            return NexusPalette.danger
        }
    }

    private var tasksPath: String {
        workspace.documentLinks["tasks"] ?? "\(workspace.path)/tasks.md"
    }

    private var deliveryPath: String {
        workspace.documentLinks["delivery"] ?? "\(workspace.path)/交付记录.md"
    }

    private var missingWorktreeServices: [ServiceStatus] {
        workspace.services.filter { !$0.worktreeExists }
    }

    private var dirtyServices: [ServiceStatus] {
        workspace.services.filter { service in
            let normalized = "\(service.gitSummary) \(service.worktree)".lowercased()
            return normalized.contains("dirty")
                || normalized.contains("modified")
                || normalized.contains("uncommitted")
                || normalized.contains("未提交")
                || normalized.contains("有改动")
                || normalized.contains("不是 git")
                || normalized.contains("not git")
                || normalized.contains("检查失败")
                || normalized.contains("failed")
        }
    }

    private var readinessItems: [DeliveryReadinessItem] {
        [
            branchReadiness,
            serviceReadiness,
            taskReadiness,
            riskReadiness,
            deliveryRecordReadiness,
            sqlReadiness,
            dirtyServiceReadiness
        ]
    }

    private var deliveryFocusStep: DeliveryFocusStep {
        if workspace.isArchived {
            return DeliveryFocusStep(
                title: "工作区已归档 / Archived",
                detail: "这个需求已退出活跃交付流。需要重新处理前，先复查交付记录和 handoff。",
                statusLabel: "archive",
                tone: .secondary,
                systemImage: "archivebox",
                actionLabel: "打开交付",
                actionSystemImage: "doc.text",
                action: .openDelivery
            )
        }

        if workspace.lifecycle.stage == "done" {
            return DeliveryFocusStep(
                title: "确认 PR 与 CI / Confirm PR and CI",
                detail: "生命周期已标记完成。下一步复核本地验证、PR、CI、发布和遗留风险，再决定是否归档。",
                statusLabel: "done",
                tone: NexusPalette.success,
                systemImage: "checkmark.seal",
                actionLabel: "PR 交接",
                actionSystemImage: "point.3.connected.trianglepath.dotted",
                action: .validationPrHandoff
            )
        }

        if !Self.hasConfirmedTargetBranch(workspace.branch) {
            return DeliveryFocusStep(
                title: "先确认目标分支 / Confirm branch first",
                detail: "分支仍待确认，交付检查无法判断代码是否在正确的开发线上。",
                statusLabel: "block",
                tone: NexusPalette.danger,
                systemImage: "arrow.triangle.branch",
                actionLabel: "打开分支",
                actionSystemImage: "doc.text",
                action: .openBranches
            )
        }

        if workspace.services.isEmpty {
            return DeliveryFocusStep(
                title: "先确认服务范围 / Confirm services first",
                detail: "服务范围为空，任务、worktree 和交付影响面都还没有可靠边界。",
                statusLabel: "block",
                tone: NexusPalette.danger,
                systemImage: "square.stack.3d.up",
                actionLabel: "打开服务",
                actionSystemImage: "doc.text",
                action: .openServices
            )
        }

        if !missingWorktreeServices.isEmpty {
            let names = missingWorktreeServices.map(\.name).joined(separator: ", ")
            return DeliveryFocusStep(
                title: "先补齐 worktree / Setup worktrees first",
                detail: "缺失 \(missingWorktreeServices.count) 个 workspace-local worktree: \(names)",
                statusLabel: "block",
                tone: NexusPalette.warning,
                systemImage: "arrow.triangle.branch",
                actionLabel: "创建 worktree",
                actionSystemImage: "wrench.and.screwdriver",
                action: .setupWorktrees
            )
        }

        if !blockedTasks.isEmpty {
            return DeliveryFocusStep(
                title: "先处理阻塞任务 / Resolve blockers",
                detail: "\(blockedTasks.count) 个任务处于阻塞状态，交付前需要完成、延期或拆分处理。",
                statusLabel: "block",
                tone: NexusPalette.danger,
                systemImage: "checklist",
                actionLabel: "打开任务",
                actionSystemImage: "checklist",
                action: .openTasks
            )
        }

        if workspace.riskLevel == .high || !workspace.risks.isEmpty {
            return DeliveryFocusStep(
                title: "先复核风险 / Review risks",
                detail: "当前有 \(workspace.risks.count) 个风险信号。建议把风险上下文交给 Codex 复核，再进入交付确认。",
                statusLabel: workspace.riskLevel == .high ? "block" : "review",
                tone: workspace.riskLevel == .high ? NexusPalette.danger : NexusPalette.warning,
                systemImage: "exclamationmark.triangle",
                actionLabel: "风险交接",
                actionSystemImage: "point.3.connected.trianglepath.dotted",
                action: .reviewRisks
            )
        }

        if !openTasks.isEmpty {
            return DeliveryFocusStep(
                title: "确认活跃任务 / Review active tasks",
                detail: "\(openTasks.count) 个任务仍在活跃队列。交付前需要判断它们是已完成、延期，还是还要继续开发。",
                statusLabel: "review",
                tone: NexusPalette.accent,
                systemImage: "checklist",
                actionLabel: "打开任务",
                actionSystemImage: "checklist",
                action: .openTasks
            )
        }

        if deliveryStatusLabel != "ready" {
            return DeliveryFocusStep(
                title: "补齐交付记录 / Update delivery record",
                detail: deliveryStatusText,
                statusLabel: deliveryStatusLabel,
                tone: deliveryColor,
                systemImage: "doc.text",
                actionLabel: "交付交接",
                actionSystemImage: "point.3.connected.trianglepath.dotted",
                action: .deliveryHandoff
            )
        }

        if let sqlItem = readinessItems.first(where: { $0.id == "sql" }), sqlItem.status != .pass {
            return DeliveryFocusStep(
                title: "复核 SQL 记录 / Review SQL notes",
                detail: sqlItem.detail,
                statusLabel: "review",
                tone: NexusPalette.warning,
                systemImage: "cylinder.split.1x2",
                actionLabel: "SQL 交接",
                actionSystemImage: "point.3.connected.trianglepath.dotted",
                action: .sqlHandoff
            )
        }

        if !dirtyServices.isEmpty {
            let names = dirtyServices.map(\.name).joined(separator: ", ")
            return DeliveryFocusStep(
                title: "复核未提交改动 / Review local changes",
                detail: "还有 \(dirtyServices.count) 个服务存在未提交状态: \(names)",
                statusLabel: "review",
                tone: NexusPalette.warning,
                systemImage: "arrow.triangle.branch",
                actionLabel: "交接 Codex",
                actionSystemImage: "point.3.connected.trianglepath.dotted",
                action: .openCodex
            )
        }

        if workspace.lifecycle.stage == "delivery" {
            return DeliveryFocusStep(
                title: "可以完成交付 / Ready to finish",
                detail: "关键检查项已通过。可以进入完成确认，或先再运行一次本地检查。",
                statusLabel: "ready",
                tone: NexusPalette.success,
                systemImage: "checkmark.seal",
                actionLabel: "标记完成",
                actionSystemImage: "checkmark.seal",
                action: .markDone
            )
        }

        return DeliveryFocusStep(
            title: "进入交付整理 / Enter delivery",
            detail: "任务、风险、worktree 和交付记录暂无明显阻塞。下一步把生命周期切到交付整理。",
            statusLabel: "ready",
            tone: NexusPalette.success,
            systemImage: "shippingbox",
            actionLabel: "进入交付",
            actionSystemImage: "shippingbox",
            action: .enterDelivery
        )
    }

    private var nonPassingReadinessItems: [DeliveryReadinessItem] {
        readinessItems.filter { $0.status != .pass }
    }

    private var hasDeliveryBlockers: Bool {
        nonPassingReadinessItems.contains { $0.status == .blocker }
    }

    private var hasDeliveryWarnings: Bool {
        nonPassingReadinessItems.contains { $0.status == .warning }
    }

    private var lifecycleRecommendation: DeliveryLifecycleRecommendation? {
        switch workspace.lifecycle.stage {
        case "delivery":
            if nonPassingReadinessItems.isEmpty {
                return DeliveryLifecycleRecommendation(
                    title: "交付检查已就绪 / Ready to finish",
                    detail: "任务、风险、服务、分支、交付记录和 SQL 检查暂无明显阻塞，可以进入完成确认。",
                    transition: .done,
                    tone: NexusPalette.success,
                    systemImage: "checkmark.seal"
                )
            }

            return DeliveryLifecycleRecommendation(
                title: "交付仍需处理 / Delivery needs review",
                detail: "还有 \(nonPassingReadinessItems.count) 个检查项需要处理，先打开交付记录或运行本地检查后再标记完成。",
                transition: nil,
                tone: hasDeliveryBlockers ? NexusPalette.danger : NexusPalette.warning,
                systemImage: hasDeliveryBlockers ? "xmark.octagon" : "exclamationmark.triangle"
            )
        case "done", "archived":
            return nil
        default:
            return DeliveryLifecycleRecommendation(
                title: "准备交付状态 / Prepare delivery",
                detail: hasDeliveryWarnings || hasDeliveryBlockers
                    ? "当前已有交付相关检查项，建议先把生命周期写回为交付整理，再逐项处理 checklist。"
                    : "交付检查较干净，可以先进入交付整理，最终完成前再做一次本地检查。",
                transition: .delivery,
                tone: hasDeliveryBlockers ? NexusPalette.danger : NexusPalette.warning,
                systemImage: "doc.text"
            )
        }
    }

    private var branchReadiness: DeliveryReadinessItem {
        if Self.hasConfirmedTargetBranch(workspace.branch) {
            return DeliveryReadinessItem(
                id: "branch",
                title: "目标分支 / Branch",
                detail: workspace.branch,
                status: .pass,
                systemImage: "arrow.triangle.branch"
            )
        }

        return DeliveryReadinessItem(
            id: "branch",
            title: "目标分支 / Branch",
            detail: "目标分支仍待确认，交付前需要写入 branches.md 或 workspace.md。",
            status: .blocker,
            systemImage: "arrow.triangle.branch"
        )
    }

    private var serviceReadiness: DeliveryReadinessItem {
        if workspace.services.isEmpty {
            return DeliveryReadinessItem(
                id: "services",
                title: "服务与 worktree / Services",
                detail: "服务范围待确认，无法判断交付涉及的代码范围。",
                status: .blocker,
                systemImage: "square.stack.3d.up"
            )
        }

        if missingWorktreeServices.isEmpty {
            return DeliveryReadinessItem(
                id: "services",
                title: "服务与 worktree / Services",
                detail: "\(workspace.services.count) 个服务均有 workspace-local worktree。",
                status: .pass,
                systemImage: "square.stack.3d.up"
            )
        }

        let names = missingWorktreeServices.map(\.name).joined(separator: ", ")
        return DeliveryReadinessItem(
            id: "services",
            title: "服务与 worktree / Services",
            detail: "缺失 \(missingWorktreeServices.count) 个 worktree: \(names)",
            status: .blocker,
            systemImage: "square.stack.3d.up"
        )
    }

    private var taskReadiness: DeliveryReadinessItem {
        if !blockedTasks.isEmpty {
            return DeliveryReadinessItem(
                id: "tasks",
                title: "任务状态 / Tasks",
                detail: "\(blockedTasks.count) 个任务仍处于阻塞状态。",
                status: .blocker,
                systemImage: "checklist"
            )
        }

        if !openTasks.isEmpty {
            return DeliveryReadinessItem(
                id: "tasks",
                title: "任务状态 / Tasks",
                detail: "\(openTasks.count) 个任务仍在活跃队列，交付前需要确认是否完成或延期。",
                status: .warning,
                systemImage: "checklist"
            )
        }

        return DeliveryReadinessItem(
            id: "tasks",
            title: "任务状态 / Tasks",
            detail: "当前没有活跃任务。",
            status: .pass,
            systemImage: "checklist"
        )
    }

    private var riskReadiness: DeliveryReadinessItem {
        if workspace.risks.isEmpty {
            return DeliveryReadinessItem(
                id: "risks",
                title: "风险复核 / Risks",
                detail: "当前没有活动风险。",
                status: .pass,
                systemImage: "checkmark.shield"
            )
        }

        return DeliveryReadinessItem(
            id: "risks",
            title: "风险复核 / Risks",
            detail: "\(workspace.risks.count) 个风险信号需要复核。",
            status: workspace.riskLevel == .high ? .blocker : .warning,
            systemImage: "exclamationmark.triangle"
        )
    }

    private var deliveryRecordReadiness: DeliveryReadinessItem {
        DeliveryReadinessItem(
            id: "delivery-record",
            title: "交付记录 / Delivery",
            detail: deliveryStatusText,
            status: deliveryStatusLabel == "ready" ? .pass : deliveryStatusLabel == "review" ? .warning : .blocker,
            systemImage: "doc.text"
        )
    }

    private var sqlReadiness: DeliveryReadinessItem {
        guard let sqlCheck = workspace.healthChecks.first(where: { check in
            check.id == "sql-directory" || check.action == "sql"
        }) else {
            return DeliveryReadinessItem(
                id: "sql",
                title: "SQL 记录 / SQL",
                detail: "暂未生成 SQL 目录检查，运行本地检查后可刷新。",
                status: .warning,
                systemImage: "cylinder.split.1x2"
            )
        }

        let status: DeliveryReadinessStatus
        switch sqlCheck.status.lowercased() {
        case "pass", "ok":
            status = .pass
        case "fail", "blocked", "blocker":
            status = .blocker
        default:
            status = .warning
        }
        return DeliveryReadinessItem(
            id: "sql",
            title: "SQL 记录 / SQL",
            detail: sqlCheck.detail,
            status: status,
            systemImage: "cylinder.split.1x2"
        )
    }

    private var dirtyServiceReadiness: DeliveryReadinessItem {
        if dirtyServices.isEmpty {
            return DeliveryReadinessItem(
                id: "dirty-services",
                title: "服务 Git 状态 / Git",
                detail: "当前没有检测到未提交服务。",
                status: .pass,
                systemImage: "arrow.triangle.branch"
            )
        }

        let names = dirtyServices.map(\.name).joined(separator: ", ")
        return DeliveryReadinessItem(
            id: "dirty-services",
            title: "服务 Git 状态 / Git",
            detail: "\(dirtyServices.count) 个服务存在未提交状态: \(names)",
            status: .warning,
            systemImage: "arrow.triangle.branch"
        )
    }

    var body: some View {
        SectionBlock(title: "任务与交付 / Workflow") {
            VStack(alignment: .leading, spacing: 12) {
                DeliveryFocusCardView(step: deliveryFocusStep) {
                    runDeliveryFocusAction(deliveryFocusStep.action)
                }

                HStack(spacing: 8) {
                    WorkflowMetric(
                        label: "Active tasks",
                        value: "\(openTasks.count)",
                        tone: openTasks.isEmpty ? NexusPalette.success : NexusPalette.accent
                    )
                    WorkflowMetric(
                        label: "Blocked",
                        value: "\(blockedTasks.count)",
                        tone: blockedTasks.isEmpty ? NexusPalette.success : NexusPalette.danger
                    )
                    WorkflowMetric(
                        label: "Delivery",
                        value: deliveryStatusLabel,
                        tone: deliveryColor
                    )
                }

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: deliveryStatusLabel == "ready" ? "doc.text.magnifyingglass" : "exclamationmark.triangle")
                        .foregroundStyle(deliveryColor)
                        .frame(width: 15)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("交付记录 / Delivery record")
                            .font(.subheadline.weight(.medium))
                        Text(deliveryStatusText)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                WorkflowActionTrayView(
                    isRunningCheck: appState.isRunningAutomationCheck,
                    openTasksAction: {
                        Task {
                            await appState.loadDocument(path: tasksPath)
                        }
                    },
                    openDeliveryAction: {
                        Task {
                            await appState.loadDocument(path: deliveryPath)
                        }
                    },
                    runCheckAction: {
                        Task {
                            await appState.runLocalAutomationCheck(actor: "Nexus Workflow")
                        }
                    },
                    workspaceHandoffAction: {
                        Task {
                            await appState.openWorkspaceInCodex(workspace)
                        }
                    },
                    deliveryHandoffAction: {
                        Task {
                            await appState.openDeliveryUpdateInCodex(workspace)
                        }
                    },
                    validationPrHandoffAction: {
                        Task {
                            await appState.openValidationPrHandoffInCodex(workspace)
                        }
                    }
                )

                if appState.isRunningAutomationCheck || appState.lastAutomationCheck != nil {
                    LocalCheckReceiptView(
                        check: appState.lastAutomationCheck,
                        actor: appState.lastAutomationCheckActor,
                        isRunning: appState.isRunningAutomationCheck,
                        contextLabel: "任务与交付 / Workflow",
                        copyAction: copyLocalCheckSummary
                    )
                }

                DeliveryReadinessChecklistView(
                    items: readinessItems,
                    actionLabel: readinessActionLabel(for:),
                    action: runReadinessAction(for:)
                )

                ValidationPrHandoffView(
                    localCheckStatus: appState.lastAutomationCheck?.status,
                    lifecycleStage: workspace.lifecycle.label,
                    hasOpenTasks: !openTasks.isEmpty,
                    hasRisks: !workspace.risks.isEmpty
                )

                if let lifecycleRecommendation {
                    DeliveryLifecycleRecommendationView(recommendation: lifecycleRecommendation) { transition in
                        lifecycleAction(transition)
                    }
                }

                if openTasks.isEmpty {
                    Label("当前没有活跃任务。可以继续查看交付记录或运行本地检查确认状态。", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(NexusPalette.success)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(openTasks.prefix(4))) { task in
                            WorkspaceTaskRow(
                                task: task,
                                openDocumentAction: {
                                    openTaskDocumentAction(task)
                                },
                                completeAction: {
                                    completeTaskAction(task)
                                },
                                deferAction: {
                                    deferTaskAction(task)
                                },
                                codexAction: {
                                    taskCodexAction(task)
                                }
                            )
                        }

                        if openTasks.count > 4 {
                            Text("Showing 4 of \(openTasks.count) active tasks. Open tasks.md for the full list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
    }

    private func runDeliveryFocusAction(_ action: DeliveryFocusAction) {
        switch action {
        case .openTasks:
            Task {
                await appState.loadDocument(path: tasksPath)
            }
        case .openDelivery:
            Task {
                await appState.loadDocument(path: deliveryPath)
            }
        case .openBranches:
            Task {
                await appState.loadDocument(path: documentPath(for: "branches", fallback: "branches.md"))
            }
        case .openServices:
            Task {
                await appState.loadDocument(path: documentPath(for: "services", fallback: "services.md"))
            }
        case .setupWorktrees:
            appState.presentWorktreeSetup(for: workspace)
        case .reviewRisks:
            copyToPasteboard(appState.riskReviewPrompt(for: workspace))
            Task {
                await appState.recordRiskReviewHandoffCopied(for: workspace)
            }
        case .runCheck:
            Task {
                await appState.runLocalAutomationCheck(actor: "Nexus Workflow")
            }
        case .openCodex:
            Task {
                await appState.openWorkspaceInCodex(workspace)
            }
        case .deliveryHandoff:
            Task {
                await appState.openDeliveryUpdateInCodex(workspace)
            }
        case .sqlHandoff:
            Task {
                await appState.openDeliveryUpdateInCodex(workspace)
            }
        case .validationPrHandoff:
            Task {
                await appState.openValidationPrHandoffInCodex(workspace)
            }
        case .enterDelivery:
            lifecycleAction(.delivery)
        case .markDone:
            lifecycleAction(.done)
        }
    }

    private func readinessActionLabel(for item: DeliveryReadinessItem) -> String {
        switch item.id {
        case "branch":
            return "打开分支"
        case "services":
            return missingWorktreeServices.isEmpty ? "打开服务" : "创建 worktree"
        case "tasks":
            return "打开任务"
        case "risks":
            return workspace.risks.isEmpty ? "打开状态" : "风险交接"
        case "delivery-record":
            return item.status == .pass ? "打开交付" : "交付交接"
        case "sql":
            return item.status == .pass ? "复查 SQL" : "SQL 交接"
        case "dirty-services":
            return dirtyServices.isEmpty ? "查看服务" : "服务交接"
        default:
            return "处理"
        }
    }

    private func runReadinessAction(for item: DeliveryReadinessItem) {
        switch item.id {
        case "branch":
            Task {
                await appState.loadDocument(path: documentPath(for: "branches", fallback: "branches.md"))
            }
        case "services":
            if missingWorktreeServices.isEmpty {
                Task {
                    await appState.loadDocument(path: documentPath(for: "services", fallback: "services.md"))
                }
            } else {
                appState.presentWorktreeSetup(for: workspace)
            }
        case "tasks":
            Task {
                await appState.loadDocument(path: tasksPath)
            }
        case "risks":
            if workspace.risks.isEmpty {
                Task {
                    await appState.loadDocument(path: documentPath(for: "status", fallback: "STATUS.md"))
                }
            } else {
                copyToPasteboard(appState.riskReviewPrompt(for: workspace))
                Task {
                    await appState.recordRiskReviewHandoffCopied(for: workspace)
                }
            }
        case "delivery-record":
            if item.status == .pass {
                Task {
                    await appState.loadDocument(path: deliveryPath)
                }
            } else {
                Task {
                    await appState.openDeliveryUpdateInCodex(workspace)
                }
            }
        case "sql":
            if item.status == .pass {
                Task {
                    await appState.openSqlReviewDocument(in: workspace)
                }
            } else {
                Task {
                    await appState.openDeliveryUpdateInCodex(workspace)
                }
            }
        case "dirty-services":
            if let service = dirtyServices.first {
                Task {
                    await appState.openServiceInCodex(service, in: workspace)
                }
            } else {
                Task {
                    await appState.loadDocument(path: documentPath(for: "services", fallback: "services.md"))
                }
            }
        default:
            Task {
                await appState.runLocalAutomationCheck(actor: "Nexus Workflow")
            }
        }
    }

    private func documentPath(for key: String, fallback: String) -> String {
        workspace.documentLinks[key] ?? "\(workspace.path)/\(fallback)"
    }

    private func copyLocalCheckSummary(_ check: LocalAutomationCheckResponse) {
        copyToPasteboard(
            localCheckSummaryPayload(
                title: "Nexus workflow local check",
                actor: appState.lastAutomationCheckActor,
                check: check,
                workspace: workspace
            )
        )
    }

    private static func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("未确认")
            && !normalized.contains("pending")
            && !normalized.contains("tbd")
            && !normalized.contains("todo")
            && normalized != "-"
    }
}

private enum DeliveryReadinessStatus {
    case pass
    case warning
    case blocker

    var label: String {
        switch self {
        case .pass:
            "pass"
        case .warning:
            "review"
        case .blocker:
            "block"
        }
    }

    var color: Color {
        switch self {
        case .pass:
            NexusPalette.success
        case .warning:
            NexusPalette.warning
        case .blocker:
            NexusPalette.danger
        }
    }

    var symbol: String {
        switch self {
        case .pass:
            "checkmark.circle"
        case .warning:
            "exclamationmark.triangle"
        case .blocker:
            "xmark.octagon"
        }
    }
}

private struct DeliveryReadinessItem: Identifiable {
    let id: String
    let title: String
    let detail: String
    let status: DeliveryReadinessStatus
    let systemImage: String
}

private struct DeliveryLifecycleRecommendation {
    let title: String
    let detail: String
    let transition: LifecycleTransition?
    let tone: Color
    let systemImage: String
}

private struct DeliveryLifecycleRecommendationView: View {
    let recommendation: DeliveryLifecycleRecommendation
    let action: (LifecycleTransition) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: recommendation.systemImage)
                .foregroundStyle(recommendation.tone)
                .frame(width: 15)

            VStack(alignment: .leading, spacing: 3) {
                Text(recommendation.title)
                    .font(.subheadline.weight(.medium))
                Text(recommendation.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            if let transition = recommendation.transition {
                Button {
                    action(transition)
                } label: {
                    Label(transition.label, systemImage: transition.systemImage)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("打开确认弹窗，写回 workspace.md 和 STATUS.md")
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DeliveryReadinessChecklistView: View {
    let items: [DeliveryReadinessItem]
    let actionLabel: (DeliveryReadinessItem) -> String
    let action: (DeliveryReadinessItem) -> Void

    private var blockerCount: Int {
        items.filter { $0.status == .blocker }.count
    }

    private var warningCount: Int {
        items.filter { $0.status == .warning }.count
    }

    private var attentionItems: [DeliveryReadinessItem] {
        items.filter { $0.status != .pass }
    }

    private var passedItems: [DeliveryReadinessItem] {
        items.filter { $0.status == .pass }
    }

    private var headline: String {
        if blockerCount > 0 {
            return "交付前还有 \(blockerCount) 个阻塞项。"
        }
        if warningCount > 0 {
            return "交付前还有 \(warningCount) 个复核项。"
        }
        return "交付前检查未发现明显阻塞。"
    }

    private var headlineColor: Color {
        if blockerCount > 0 {
            return NexusPalette.danger
        }
        if warningCount > 0 {
            return NexusPalette.warning
        }
        return NexusPalette.success
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                Image(systemName: blockerCount > 0 ? "xmark.octagon" : warningCount > 0 ? "exclamationmark.triangle" : "checkmark.circle")
                    .foregroundStyle(headlineColor)
                    .frame(width: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text("交付前检查 / Delivery readiness")
                        .font(.subheadline.weight(.medium))
                    Text(headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 10) {
                if !attentionItems.isEmpty {
                    DeliveryReadinessGroupView(
                        title: "需要处理 / Attention",
                        detail: "\(blockerCount) 阻塞 / \(warningCount) 复核",
                        tone: blockerCount > 0 ? NexusPalette.danger : NexusPalette.warning,
                        items: attentionItems,
                        actionLabel: actionLabel,
                        action: action
                    )
                }

                if !passedItems.isEmpty {
                    DeliveryReadinessGroupView(
                        title: attentionItems.isEmpty ? "全部通过 / Passed" : "已通过 / Passed",
                        detail: "\(passedItems.count) 项已通过",
                        tone: NexusPalette.success,
                        items: passedItems,
                        actionLabel: actionLabel,
                        action: action
                    )
                }

                if items.isEmpty {
                    Label("暂未生成交付前检查。运行本地检查后，Nexus 会汇总分支、服务、任务、风险、SQL 和 Git 状态。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DeliveryReadinessGroupView: View {
    let title: String
    let detail: String
    let tone: Color
    let items: [DeliveryReadinessItem]
    let actionLabel: (DeliveryReadinessItem) -> String
    let action: (DeliveryReadinessItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                Text(title)
                    .font(.caption.weight(.semibold))
                Text(detail)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(tone)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(tone.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }

            ForEach(items) { item in
                DeliveryReadinessRow(
                    item: item,
                    actionLabel: actionLabel(item)
                ) {
                    action(item)
                }
            }
        }
    }
}

private struct ValidationPrHandoffView: View {
    let localCheckStatus: String?
    let lifecycleStage: String
    let hasOpenTasks: Bool
    let hasRisks: Bool

    private var statusTone: Color {
        guard let status = localCheckStatus?.lowercased() else {
            return NexusPalette.warning
        }
        if status.contains("attention") || status.contains("fail") {
            return NexusPalette.danger
        }
        if status.contains("review") || hasOpenTasks || hasRisks {
            return NexusPalette.warning
        }
        return NexusPalette.success
    }

    private var checkValue: String {
        guard let localCheckStatus, !localCheckStatus.isEmpty else {
            return "none"
        }
        return localCheckStatus
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: "checkmark.seal")
                    .foregroundStyle(statusTone)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 3) {
                    Text("验证与 PR / Validation & PR")
                        .font(.subheadline.weight(.medium))
                    Text("交付记录整理后，把本地检查、任务、SQL、服务状态和 PR 待确认项作为一份上下文交给 Codex。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                WorkflowMetric(label: "Local check", value: checkValue, tone: statusTone)
                WorkflowMetric(label: "Lifecycle", value: lifecycleStage, tone: NexusPalette.accent)
                WorkflowMetric(label: "PR/CI", value: "handoff", tone: NexusPalette.warning)
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DeliveryReadinessRow: View {
    let item: DeliveryReadinessItem
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        Button {
            action()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: item.systemImage)
                    .font(.caption)
                    .foregroundStyle(item.status.color)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 2) {
                    Text(item.title)
                        .font(.caption.weight(.semibold))
                    Text(item.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(actionLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NexusPalette.accent)
                }

                Spacer()

                Text(item.status.label)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(item.status.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(item.status.color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(item.title) · \(actionLabel)")
    }
}

private struct RiskReviewView: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary
    let checks: [WorkspaceHealthCheck]
    let codexAction: () -> Void

    private var blockerChecks: [WorkspaceHealthCheck] {
        checks.filter { Self.statusKind($0.status) == "blocker" }
    }

    private var warningChecks: [WorkspaceHealthCheck] {
        checks.filter { Self.statusKind($0.status) == "warning" }
    }

    private var visibleChecks: [WorkspaceHealthCheck] {
        let attentionChecks = checks.filter { Self.statusKind($0.status) != "pass" }
        let source = attentionChecks.isEmpty ? checks : attentionChecks
        return Array(source.prefix(4))
    }

    private var missingWorktreeServices: [String] {
        workspace.services
            .filter { !$0.worktreeExists }
            .map(\.name)
    }

    private var hasSignals: Bool {
        !workspace.risks.isEmpty || !blockerChecks.isEmpty || !warningChecks.isEmpty
    }

    private var statusTitle: String {
        if !blockerChecks.isEmpty {
            return "存在阻塞项 / Blocked"
        }
        if hasSignals {
            return "需要复核 / Review needed"
        }
        return "风险清晰 / Clear"
    }

    private var statusDetail: String {
        if !blockerChecks.isEmpty {
            return "\(blockerChecks.count) 个检查未通过，建议先处理阻塞项，再进入开发或交付。"
        }
        if hasSignals {
            return "发现 \(workspace.risks.count) 个风险和 \(warningChecks.count) 个警告，建议复制风险复核 Prompt 交给 Codex 继续分析。"
        }
        return "当前没有活动风险，非交付类就绪检查也没有发现阻塞。"
    }

    private var statusColor: Color {
        if !blockerChecks.isEmpty {
            return NexusPalette.danger
        }
        if hasSignals {
            return NexusPalette.warning
        }
        return NexusPalette.success
    }

    private var statusIcon: String {
        if !blockerChecks.isEmpty {
            return "xmark.octagon"
        }
        if hasSignals {
            return "exclamationmark.triangle"
        }
        return "checkmark.circle"
    }

    private var statusPath: String {
        workspace.documentLinks["status"] ?? "\(workspace.path)/STATUS.md"
    }

    var body: some View {
        SectionBlock(title: "风险复核 / Risk review") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    WorkflowMetric(
                        label: "Risks",
                        value: "\(workspace.risks.count)",
                        tone: workspace.risks.isEmpty ? NexusPalette.success : NexusPalette.warning
                    )
                    WorkflowMetric(
                        label: "Blockers",
                        value: "\(blockerChecks.count)",
                        tone: blockerChecks.isEmpty ? NexusPalette.success : NexusPalette.danger
                    )
                    WorkflowMetric(
                        label: "Warnings",
                        value: "\(warningChecks.count)",
                        tone: warningChecks.isEmpty ? NexusPalette.success : NexusPalette.warning
                    )
                }

                HStack(alignment: .top, spacing: 9) {
                    Image(systemName: statusIcon)
                        .foregroundStyle(statusColor)
                        .frame(width: 15)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(statusTitle)
                            .font(.subheadline.weight(.medium))
                        Text(statusDetail)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                    Button {
                        Task {
                            await appState.runLocalAutomationCheck(actor: "Nexus Risk Review")
                        }
                    } label: {
                        Label(appState.isRunningAutomationCheck ? "检查中" : "本地检查", systemImage: "checklist.checked")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isRunningAutomationCheck)

                    Button {
                        Task {
                            await appState.loadDocument(path: statusPath)
                        }
                    } label: {
                        Label("状态", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !missingWorktreeServices.isEmpty {
                        Button {
                            appState.presentWorktreeSetup(for: workspace)
                        } label: {
                            Label("创建 worktree", systemImage: "arrow.triangle.branch")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!appState.canSetupWorktrees(in: workspace))
                    }

                    Button {
                        codexAction()
                    } label: {
                        Label("风险交接", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                if appState.isRunningAutomationCheck || appState.lastAutomationCheck != nil {
                    LocalCheckReceiptView(
                        check: appState.lastAutomationCheck,
                        actor: appState.lastAutomationCheckActor,
                        isRunning: appState.isRunningAutomationCheck,
                        contextLabel: "风险复核 / Risk review",
                        copyAction: copyLocalCheckSummary
                    )
                }

                if hasSignals {
                    VStack(alignment: .leading, spacing: 10) {
                        if !workspace.risks.isEmpty {
                            ForEach(Array(workspace.risks.prefix(3))) { risk in
                                RiskReviewSignalRow(risk: risk)
                            }

                            if workspace.risks.count > 3 {
                                Text("Showing 3 of \(workspace.risks.count) risk signals. Run check or copy Codex risk prompt for the full review.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if !visibleChecks.isEmpty {
                            Divider()
                            ForEach(visibleChecks) { check in
                                HealthCheckRow(
                                    check: check,
                                    actionLabel: riskCheckActionLabel(for: check)
                                ) {
                                    runRiskCheckAction(for: check)
                                }
                            }
                        }
                    }
                } else if checks.isEmpty {
                    Label("暂未生成就绪检查。运行本地检查后，Nexus 会在这里汇总服务、分支、worktree 和任务风险。", systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("当前风险复核通过。可以继续查看任务、交付记录，或运行本地检查刷新状态。", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(NexusPalette.success)
                }
            }
        }
    }

    private func copyLocalCheckSummary(_ check: LocalAutomationCheckResponse) {
        copyToPasteboard(
            localCheckSummaryPayload(
                title: "Nexus risk review local check",
                actor: appState.lastAutomationCheckActor,
                check: check,
                workspace: workspace
            )
        )
    }

    private func riskCheckActionLabel(for check: WorkspaceHealthCheck) -> String {
        switch check.action {
        case "services":
            "打开服务"
        case "branches":
            "打开分支"
        case "worktreeScript":
            "创建 worktree"
        case "status":
            "打开状态"
        case "tasks":
            "打开任务"
        case "sql":
            "复查 SQL"
        default:
            "重新检查"
        }
    }

    private func runRiskCheckAction(for check: WorkspaceHealthCheck) {
        switch check.action {
        case "services":
            openDocument(key: "services", fallback: "services.md")
        case "branches":
            openDocument(key: "branches", fallback: "branches.md")
        case "worktreeScript":
            appState.presentWorktreeSetup(for: workspace)
        case "status":
            openDocument(key: "status", fallback: "STATUS.md")
        case "tasks":
            openDocument(key: "tasks", fallback: "tasks.md")
        case "sql":
            Task {
                await appState.openSqlReviewDocument(in: workspace)
            }
        default:
            Task {
                await appState.runLocalAutomationCheck(actor: "Nexus Risk Review")
            }
        }
    }

    private func openDocument(key: String, fallback: String) {
        let path = workspace.documentLinks[key] ?? "\(workspace.path)/\(fallback)"
        Task {
            await appState.loadDocument(path: path)
        }
    }

    private static func statusKind(_ status: String) -> String {
        switch status.lowercased() {
        case "pass", "ok", "ready":
            return "pass"
        case "warning", "warn", "review":
            return "warning"
        default:
            return "blocker"
        }
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 8, alignment: .leading)]
    }
}

private struct RiskReviewSignalRow: View {
    let risk: RiskAlert

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(NexusPalette.warning)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 2) {
                Text(risk.title)
                    .font(.subheadline.weight(.medium))
                Text(risk.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct WorkflowMetric: View {
    let label: String
    let value: String
    let tone: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(tone)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8)
        .background(tone.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct HealthCheckRow: View {
    let check: WorkspaceHealthCheck
    let actionLabel: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 9) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 15)
                VStack(alignment: .leading, spacing: 2) {
                    Text(check.label)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(check.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text(actionLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(NexusPalette.accent)
                        .lineLimit(1)
                }
                Spacer()
                Text(statusLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(color.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            }
        }
        .buttonStyle(.plain)
        .help("\(check.detail) · \(actionLabel)")
    }

    private var statusLabel: String {
        switch check.status.lowercased() {
        case "pass", "ok", "ready":
            "通过"
        case "warning", "warn", "review":
            "复核"
        default:
            "阻塞"
        }
    }

    private var symbol: String {
        switch check.status.lowercased() {
        case "pass", "ok", "ready":
            "checkmark.circle"
        case "warning", "warn", "review":
            "exclamationmark.circle"
        default:
            "xmark.octagon"
        }
    }

    private var color: Color {
        switch check.status.lowercased() {
        case "pass", "ok", "ready":
            NexusPalette.success
        case "warning", "warn", "review":
            NexusPalette.warning
        default:
            NexusPalette.danger
        }
    }
}

private struct TaskCenterFilterBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 5) {
            ForEach(TaskCenterFilter.allCases) { filter in
                Button {
                    appState.setTaskCenterFilter(filter)
                } label: {
                    VStack(spacing: 1) {
                        Text(filter.label)
                            .font(.system(size: 10, weight: .semibold))
                            .lineLimit(1)
                        Text("\(filter.subtitle) \(appState.taskCenterCount(for: filter))")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 5)
                    .background(filter == appState.selectedTaskCenterFilter ? NexusPalette.selected : NexusPalette.panel)
                    .overlay {
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .stroke(
                                filter == appState.selectedTaskCenterFilter ? NexusPalette.accent.opacity(0.34) : NexusPalette.border,
                                lineWidth: 1
                            )
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(appState.taskCenterCount(for: filter) == 0 && filter != appState.selectedTaskCenterFilter)
            }
        }
    }
}

private struct TaskCenterWritebackHintView: View {
    @EnvironmentObject private var appState: AppState
    let feedback: LocalWriteFeedback

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: "checkmark.circle")
                    .foregroundStyle(NexusPalette.success)
                    .frame(width: 15)

                VStack(alignment: .leading, spacing: 2) {
                    Text("最近写回 / Recent writeback")
                        .font(.caption.weight(.semibold))
                    Text(feedback.detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                    Text("\(feedback.timestamp) · \(feedback.workspaceName)")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            HStack(spacing: 6) {
                Button {
                    appState.focusWorkspace(id: feedback.workspaceID)
                } label: {
                    Label("聚焦", systemImage: "scope")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .help("聚焦刚刚写回的工作区 / Focus the updated workspace")

                if appState.nextTaskCenterItem(after: feedback) != nil {
                    Button {
                        appState.focusNextTask(after: feedback)
                    } label: {
                        Label("下一项", systemImage: "arrow.down.circle")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.mini)
                    .help("聚焦下一条活跃任务 / Focus the next active task")
                }

                Button {
                    appState.focusWorkspace(id: feedback.workspaceID)
                    Task {
                        await appState.loadDocument(path: feedback.documentPath)
                    }
                } label: {
                    Label("tasks.md", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("打开刚刚写回的 tasks.md / Open the updated tasks.md")
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct TaskCenterSidebarRow: View {
    let item: TaskCenterItem
    let isFocused: Bool
    let selectAction: () -> Void
    let openDocumentAction: () -> Void
    let completeAction: () -> Void
    let deferAction: () -> Void
    let codexAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Button(action: selectAction) {
                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 6) {
                        Image(systemName: item.task.source == "agent" ? "sparkles" : "checklist")
                            .font(.caption)
                            .foregroundStyle(color)
                        Text(item.task.priorityLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(color)
                        Text(item.task.status)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(item.task.sourceLineLabel)
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                    Text(item.task.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    Text(item.workspaceName)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Button("定位") {
                    openDocumentAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("打开 tasks.md 并复制任务行定位 / Open tasks.md and copy task source locator")

                Button("完成") {
                    completeAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(item.task.isDone)
                .help("确认后写入 tasks.md 为已完成")

                Button("延期") {
                    deferAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(item.task.isDone || item.task.isDeferred)
                .help("确认后写入 tasks.md 为延期")

                Button("Codex") {
                    codexAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .help("复制任务上下文并打开 Codex / Copy task context and open Codex")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isFocused ? NexusPalette.selected : NexusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isFocused ? NexusPalette.accent.opacity(0.28) : Color.clear)
        }
    }

    private var color: Color {
        if item.task.isBlocked {
            return NexusPalette.danger
        }
        switch item.task.priority.lowercased() {
        case "high":
            return NexusPalette.warning
        case "medium":
            return NexusPalette.accent
        default:
            return Color.gray
        }
    }
}

private struct WorkspaceTaskRow: View {
    let task: WorkspaceTask
    let openDocumentAction: () -> Void
    let completeAction: () -> Void
    let deferAction: () -> Void
    let codexAction: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: task.source == "agent" ? "sparkles" : statusSymbol)
                .foregroundStyle(color)
                .frame(width: 15)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(task.title)
                        .font(.subheadline.weight(.medium))
                        .lineLimit(1)
                    Text(task.source == "agent" ? "Agent" : "Workspace")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    Text(task.sourceLineLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                if !task.detail.isEmpty {
                    Text(task.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                if let sourceEventID = task.sourceEventID {
                    Text(sourceEventID)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text(task.priorityLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                Text(statusLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                if !task.isDone {
                    HStack(spacing: 5) {
                        Button("完成") {
                            completeAction()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .help("确认后写入 tasks.md 为已完成")

                        Button("延期") {
                            deferAction()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(task.isDeferred)
                        .help("确认后写入 tasks.md 为延期")
                    }
                }
                HStack(spacing: 5) {
                    Button("定位") {
                        openDocumentAction()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("打开 tasks.md 并复制任务行定位 / Open tasks.md and copy task source locator")

                    Button("Codex") {
                        codexAction()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    .help("复制任务上下文并打开 Codex / Copy task context and open Codex")
                }
            }
        }
    }

    private var statusLabel: String {
        if task.isDone {
            return "done"
        }
        if task.isBlocked {
            return "block"
        }
        let normalized = task.status.lowercased()
        if normalized.contains("进行中") || normalized.contains("doing") {
            return "doing"
        }
        return "todo"
    }

    private var statusSymbol: String {
        if task.isDone {
            return "checkmark.circle"
        }
        if task.isBlocked {
            return "pause.circle"
        }
        return "circle.dashed"
    }

    private var color: Color {
        if task.isBlocked {
            return NexusPalette.danger
        }
        switch task.priority.lowercased() {
        case "high":
            return NexusPalette.warning
        case "medium":
            return NexusPalette.accent
        default:
            return Color.gray
        }
    }
}

private struct ActivityTimelineView: View {
    let events: [ActivityEvent]
    var compact = false

    var body: some View {
        if events.isEmpty {
            Text("No recent activity")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            VStack(alignment: .leading, spacing: compact ? 6 : 10) {
                ForEach(Array(events.enumerated()), id: \.element.id) { index, event in
                    HStack(alignment: .top, spacing: 9) {
                        VStack(spacing: 3) {
                            Circle()
                                .fill(index == 0 ? NexusPalette.accent : NexusPalette.border)
                                .frame(width: compact ? 6 : 8, height: compact ? 6 : 8)
                            if index < events.count - 1 {
                                Rectangle()
                                    .fill(NexusPalette.border)
                                    .frame(width: 1, height: compact ? 22 : 30)
                            }
                        }
                        .padding(.top, 4)

                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(event.time)
                                    .font(.system(size: compact ? 10 : 11, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                Text(event.title)
                                    .font(compact ? .caption.weight(.medium) : .subheadline.weight(.medium))
                                    .lineLimit(1)
                            }
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(compact ? 2 : 3)
                        }
                    }
                }
            }
        }
    }
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 4) {
                Text("设置 / Settings")
                    .font(.title3.weight(.semibold))
                Text("Configure the local roots Nexus uses to scan workspaces, source repositories, and delivery documents.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Form {
                Section("Local Paths") {
                    PathSettingRow(
                        title: "Workspaces root",
                        detail: "需求工作区目录 / Requirement workspaces",
                        path: $appState.workspaceRoot,
                        check: pathCheck("workspacesRoot"),
                        chooseAction: {
                            chooseDirectory(title: "Choose Workspaces Root") { url in
                                appState.workspaceRoot = url.path
                                appState.nativeEnvironmentHealth = nil
                            }
                        },
                        revealAction: {
                            revealPath(appState.workspaceRoot)
                        }
                    )

                    PathSettingRow(
                        title: "Source repositories root",
                        detail: "源仓库目录 / Source repositories",
                        path: $appState.sourceReposRoot,
                        check: pathCheck("sourceReposRoot"),
                        chooseAction: {
                            chooseDirectory(title: "Choose Source Repositories Root") { url in
                                appState.sourceReposRoot = url.path
                                appState.nativeEnvironmentHealth = nil
                            }
                        },
                        revealAction: {
                            revealPath(appState.sourceReposRoot)
                        }
                    )

                    PathSettingRow(
                        title: "Delivery documents root",
                        detail: "交付文档目录 / Delivery documents",
                        path: $appState.docsRoot,
                        check: pathCheck("docsRoot"),
                        chooseAction: {
                            chooseDirectory(title: "Choose Delivery Documents Root") { url in
                                appState.docsRoot = url.path
                                appState.nativeEnvironmentHealth = nil
                            }
                        },
                        revealAction: {
                            revealPath(appState.docsRoot)
                        }
                    )

                    Stepper(
                        "Profile refresh interval: \(appState.refreshIntervalSeconds) sec",
                        value: $appState.refreshIntervalSeconds,
                        in: 3...3600,
                        step: 1
                    )
                }

                Section("Tool Links") {
                    TextField("Codex URL", text: $appState.codexURL)
                    TextField("IDE URL template", text: $appState.ideURL)
                    Text("Use `{path}` for a URL-encoded workspace path. Default: \(AppState.defaultIDEURL)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Team Profile") {
                    Text(appState.settingsProfileStatus)
                    if let path = appState.lastSettingsProfilePath {
                        Text(path)
                            .font(.system(.caption, design: .monospaced))
                            .textSelection(.enabled)
                    }
                    HStack {
                        Button("Import Profile") {
                            importProfile()
                        }
                        Button("Export Profile") {
                            exportProfile()
                        }
                    }
                    Text("Profiles are compatible with the Tauri preview app and store workspaces, source repositories, delivery documents, Codex URL, IDE URL template, and refresh interval.")
                        .foregroundStyle(.secondary)
                }

                Section("Environment Check") {
                    HStack {
                        if let health = appState.nativeEnvironmentHealth {
                            EnvironmentStatusPill(status: health.ready ? "pass" : "blocker")
                            Text(health.ready ? "Ready" : "Needs review")
                        } else {
                            EnvironmentStatusPill(status: "warning")
                            Text("Not checked")
                        }

                        Spacer()

                        Button(appState.isCheckingNativeEnvironment ? "Checking" : "Run Check") {
                            Task {
                                await appState.checkNativeEnvironment()
                            }
                        }
                        .disabled(appState.isCheckingNativeEnvironment)
                    }

                    if let health = appState.nativeEnvironmentHealth {
                        EnvironmentHealthSummary(health: health)
                    } else {
                        Text("Run this after importing a team profile or changing paths.")
                            .foregroundStyle(.secondary)
                    }
                }

                Section("Native Shell") {
                    Text("Bridge mode: \(appState.bridgeMode)")
                    Text("Search scope: \(appState.selectedSearchScope.label) / \(appState.selectedSearchScope.subtitle)")
                    Text("Pinned workspaces: \(appState.pinnedWorkspaceIDs.count)")
                    Text("Set NEXUS_CORE_LIBRARY to a local libnexus_ffi.dylib to load real workspace data through Rust Core during development.")
                        .foregroundStyle(.secondary)
                }

                Section("Widget Snapshot") {
                    Text("Storage: \(appState.widgetSnapshotStorageStatus)")
                    if appState.widgetSnapshotStoragePaths.isEmpty {
                        Text("Refresh Nexus to generate the local widget snapshot.")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(appState.widgetSnapshotStoragePaths, id: \.self) { path in
                            Text(path)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                        }
                    }
                    Text("The native app writes Application Support data now and automatically mirrors to group.com.ks.nexus when a signed App Group entitlement is available.")
                        .foregroundStyle(.secondary)
                }

                Section("Automation") {
                    Toggle(
                        "Enable scheduled local checks",
                        isOn: Binding(
                            get: { appState.isAutomationScheduleEnabled },
                            set: { appState.setAutomationScheduleEnabled($0) }
                        )
                    )

                    Picker(
                        "Check interval",
                        selection: Binding(
                            get: { appState.automationIntervalMinutes },
                            set: { appState.setAutomationIntervalMinutes($0) }
                        )
                    ) {
                        ForEach(AppState.supportedAutomationIntervals, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .disabled(!appState.isAutomationScheduleEnabled)

                    Text("Last run: \(appState.lastAutomationRunAt ?? "None")")
                    Text("Scheduled checks scan local workspace and git state, then write a fail-open audit event when the Rust Core bridge is available.")
                        .foregroundStyle(.secondary)

                    Toggle(
                        "Notify when checks need review",
                        isOn: Binding(
                            get: { appState.areAutomationNotificationsEnabled },
                            set: { enabled in
                                Task {
                                    await appState.setAutomationNotificationsEnabled(enabled)
                                }
                            }
                        )
                    )

                    Text("Notification status: \(appState.automationNotificationStatus)")
                    Text("Notifications are local macOS alerts and only fire when an automation result is not clean.")
                        .foregroundStyle(.secondary)

                    Picker(
                        "Minimum status",
                        selection: Binding(
                            get: { appState.automationNotificationMinimumStatus },
                            set: { appState.setAutomationNotificationMinimumStatus($0) }
                        )
                    ) {
                        ForEach(AutomationNotificationMinimumStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }
                    .disabled(!appState.areAutomationNotificationsEnabled)

                    Picker(
                        "Notification cooldown",
                        selection: Binding(
                            get: { appState.automationNotificationCooldownMinutes },
                            set: { appState.setAutomationNotificationCooldownMinutes($0) }
                        )
                    ) {
                        ForEach(AppState.supportedNotificationCooldownMinutes, id: \.self) { minutes in
                            Text("\(minutes) min").tag(minutes)
                        }
                    }
                    .disabled(!appState.areAutomationNotificationsEnabled)

                    Text("Notify for")
                        .font(.caption.weight(.semibold))
                    ForEach(AutomationNotificationSignalKind.allCases) { kind in
                        Toggle(
                            kind.label,
                            isOn: Binding(
                                get: { appState.isAutomationNotificationSignalEnabled(kind) },
                                set: { appState.setAutomationNotificationSignal(kind, enabled: $0) }
                            )
                        )
                        .disabled(!appState.areAutomationNotificationsEnabled)
                    }

                    Text("Last notification: \(appState.lastAutomationNotificationAt ?? "None")")
                }
            }

            HStack {
                Button("Reset defaults") {
                    appState.resetLocalPaths()
                }

                Spacer()

                Button("Close") {
                    appState.persistLocalPaths()
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button(appState.isLoading ? "Reloading" : "Save and reload") {
                    Task {
                        await appState.reloadConfiguredPaths()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(appState.isLoading)
            }
        }
        .onChange(of: appState.workspaceRoot) { _ in
            appState.nativeEnvironmentHealth = nil
            appState.persistLocalPaths()
        }
        .onChange(of: appState.sourceReposRoot) { _ in
            appState.nativeEnvironmentHealth = nil
            appState.persistLocalPaths()
        }
        .onChange(of: appState.docsRoot) { _ in
            appState.nativeEnvironmentHealth = nil
            appState.persistLocalPaths()
        }
        .onChange(of: appState.codexURL) { _ in appState.persistLocalPaths() }
        .onChange(of: appState.ideURL) { _ in appState.persistLocalPaths() }
        .onChange(of: appState.refreshIntervalSeconds) { _ in appState.persistLocalPaths() }
        .onDisappear {
            appState.persistLocalPaths()
        }
        .task {
            if appState.nativeEnvironmentHealth == nil {
                await appState.checkNativeEnvironment()
            }
        }
        .padding(20)
        .frame(width: 660, height: 620)
    }

    private func importProfile() {
        let panel = NSOpenPanel()
        panel.title = "Import Nexus Settings Profile"
        panel.allowedContentTypes = [.json]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await appState.importSettingsProfile(from: url)
        }
    }

    private func exportProfile() {
        let panel = NSSavePanel()
        panel.title = "Export Nexus Settings Profile"
        panel.allowedContentTypes = [.json]
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = appState.settingsProfileDefaultFilename

        guard panel.runModal() == .OK, let url = panel.url else { return }
        Task {
            await appState.exportSettingsProfile(to: url)
        }
    }

    private func pathCheck(_ key: String) -> NativeEnvironmentPathCheck? {
        appState.nativeEnvironmentHealth?.pathChecks.first { $0.key == key }
    }

    private func chooseDirectory(title: String, onPick: (URL) -> Void) {
        let panel = NSOpenPanel()
        panel.title = title
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true

        guard panel.runModal() == .OK, let url = panel.url else { return }
        onPick(url)
    }

    private func revealPath(_ rawPath: String) {
        let expandedPath = NSString(string: rawPath.trimmingCharacters(in: .whitespacesAndNewlines)).expandingTildeInPath
        guard !expandedPath.isEmpty else { return }
        let url = URL(fileURLWithPath: expandedPath)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        }
    }
}

private struct PathSettingRow: View {
    let title: String
    let detail: String
    @Binding var path: String
    let check: NativeEnvironmentPathCheck?
    let chooseAction: () -> Void
    let revealAction: () -> Void

    private var status: String {
        check?.status ?? "warning"
    }

    private var statusLabel: String {
        guard let check else { return "未检查" }
        switch check.status {
        case "pass":
            return "可用"
        case "blocker":
            return "需处理"
        default:
            return "复核"
        }
    }

    private var canReveal: Bool {
        check?.exists == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Text(detail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                EnvironmentStatusPill(status: status)
                Text(statusLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 8) {
                TextField(title, text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.caption, design: .monospaced))

                Button("选择") {
                    chooseAction()
                }
                .help("选择本地目录 / Choose local directory")

                Button("打开") {
                    revealAction()
                }
                .disabled(!canReveal)
                .help(canReveal ? "在 Finder 中打开 / Reveal in Finder" : "先运行 Environment Check 确认路径存在")
            }

            Text(check?.summary ?? "Run Environment Check after choosing a path.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 4)
    }
}

private struct EnvironmentHealthSummary: View {
    let health: NativeEnvironmentHealth

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 14) {
                EnvironmentMetric(label: "Workspaces", value: "\(health.workspaceCount)")
                EnvironmentMetric(label: "Repos", value: "\(health.sourceRepoCount)")
                EnvironmentMetric(label: "Warnings", value: "\(health.warnings.count)")
            }

            VStack(alignment: .leading, spacing: 6) {
                ForEach(health.pathChecks) { check in
                    EnvironmentPathCheckRow(check: check)
                }
                ForEach(health.toolChecks) { check in
                    EnvironmentToolCheckRow(check: check)
                }
            }

            if !health.blockers.isEmpty || !health.warnings.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(health.blockers, id: \.self) { blocker in
                        Label(blocker, systemImage: "xmark.octagon")
                            .font(.caption)
                            .foregroundStyle(NexusPalette.danger)
                    }
                    ForEach(health.warnings, id: \.self) { warning in
                        Label(warning, systemImage: "exclamationmark.triangle")
                            .font(.caption)
                            .foregroundStyle(NexusPalette.warning)
                    }
                }
            }

            Text("Checked at \(health.generatedAt)")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
    }
}

private struct EnvironmentMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
        }
    }
}

private struct EnvironmentPathCheckRow: View {
    let check: NativeEnvironmentPathCheck

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            EnvironmentStatusPill(status: check.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.label)
                    .font(.caption.weight(.medium))
                Text("\(check.path) · \(check.summary)")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct EnvironmentToolCheckRow: View {
    let check: NativeEnvironmentToolCheck

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            EnvironmentStatusPill(status: check.status)
            VStack(alignment: .leading, spacing: 2) {
                Text(check.label)
                    .font(.caption.weight(.medium))
                Text(check.summary.isEmpty ? "Unavailable" : check.summary)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
            }
        }
    }
}

private struct EnvironmentStatusPill: View {
    let status: String

    var body: some View {
        Text(label)
            .font(.system(size: 10, weight: .semibold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.09))
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var label: String {
        switch status {
        case "pass":
            "pass"
        case "blocker":
            "block"
        default:
            "warn"
        }
    }

    private var color: Color {
        switch status {
        case "pass":
            NexusPalette.success
        case "blocker":
            NexusPalette.danger
        default:
            NexusPalette.warning
        }
    }
}

private struct SectionBlock<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                content
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(NexusPalette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
    }
}

private struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        Label(level.label, systemImage: level.symbol)
            .font(.caption.weight(.medium))
            .foregroundStyle(level == .high ? NexusPalette.danger : level == .medium ? NexusPalette.warning : NexusPalette.success)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(NexusPalette.badge)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct ArchivedBadge: View {
    var body: some View {
        Label("已归档 / Archived", systemImage: "archivebox")
            .font(.caption.weight(.medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(NexusPalette.badge.opacity(0.72))
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct Pill: View {
    let label: String
    let systemImage: String

    var body: some View {
        Label(label, systemImage: systemImage)
            .font(.caption)
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(NexusPalette.badge)
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct Metric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.medium))
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentInboxSidebarView: View {
    let summary: AgentInboxSummary
    let openEvent: (AgentEvent) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Agent Inbox / 事件")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text(summary.pendingLabel)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(summary.actionRequired.isEmpty ? .secondary : NexusPalette.warning)
            }

            if summary.isEmpty {
                AgentInboxEmptyView()
            } else {
                if !summary.actionRequired.isEmpty {
                    AgentInboxGroupHeader(
                        title: "需要处理 / Attention",
                        detail: "\(summary.actionRequired.count) item(s)"
                    )

                    ForEach(summary.actionRequired.prefix(3)) { event in
                        AgentInboxButton(
                            event: event,
                            badge: AgentInboxSidebarView.badge(for: event),
                            openEvent: openEvent
                        )
                    }
                }

                if !summary.recent.isEmpty {
                    AgentInboxGroupHeader(
                        title: summary.actionRequired.isEmpty ? "最近事件 / Recent" : "其他最近 / Recent",
                        detail: "\(summary.recent.count) item(s)"
                    )

                    ForEach(summary.recent.prefix(summary.actionRequired.isEmpty ? 3 : 2)) { event in
                        AgentInboxButton(
                            event: event,
                            badge: nil,
                            openEvent: openEvent
                        )
                    }
                }
            }
        }
    }

    private static func badge(for event: AgentEvent) -> String {
        if let actionSurface = AgentActionSurface(event: event) {
            return actionSurface.kind.statusLabel
        }
        return "错误 / error"
    }
}

private struct AgentInboxButton: View {
    let event: AgentEvent
    let badge: String?
    let openEvent: (AgentEvent) -> Void

    var body: some View {
        Button {
            openEvent(event)
        } label: {
            AgentEventRow(event: event, badge: badge)
        }
        .buttonStyle(.plain)
    }
}

private struct AgentInboxGroupHeader: View {
    let title: String
    let detail: String

    var body: some View {
        HStack {
            Text(title)
                .font(.system(size: 10, weight: .semibold, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
            Text(detail)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
    }
}

private struct AgentInboxEmptyView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Label("暂无待处理事件 / Clear", systemImage: "checkmark.circle")
                .font(.caption.weight(.semibold))
                .foregroundStyle(NexusPalette.success)
            Text("Hook helper 写入的权限、问题和工具复核事件会优先出现在这里。")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AgentWorkflowBridgeView: View {
    let summary: AgentWorkflowSummary
    let focusAgentTasks: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.caption)
                    .foregroundStyle(NexusPalette.accent)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Agent Workflow / 流转")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(summary.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                Text(summary.metricLabel)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(summary.pendingEventCount > 0 ? NexusPalette.warning : NexusPalette.accent)
            }

            Text(summary.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if summary.agentTaskCount > 0 {
                Button {
                    focusAgentTasks()
                } label: {
                    Label("查看 Agent 任务 / Agent tasks", systemImage: "line.3.horizontal.decrease.circle")
                        .font(.caption.weight(.medium))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .help("切换任务中心到 Agent 筛选，并聚焦第一条 Agent 任务。")
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AgentEventRow: View {
    let event: AgentEvent
    var badge: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: symbol)
                    .font(.caption)
                    .foregroundStyle(color)
                Text(event.source)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
                Text(event.kind)
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(color)
                if let badge {
                    Spacer(minLength: 4)
                    Text(badge)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(color)
                        .lineLimit(1)
                }
            }
            Text(event.title)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
            Text(event.summary)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(2)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var symbol: String {
        switch event.kind {
        case "permission":
            "hand.raised"
        case "question":
            "questionmark.circle"
        case "tool_use":
            "terminal"
        default:
            "point.3.connected.trianglepath.dotted"
        }
    }

    private var color: Color {
        switch event.severity {
        case "warning":
            NexusPalette.warning
        case "error":
            NexusPalette.danger
        default:
            NexusPalette.accent
        }
    }
}

private struct AgentEventDetailSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var appState: AppState
    let event: AgentEvent
    @State private var taskDraft: AgentEventTaskDraftResponse?
    @State private var isTaskDraftLoading = false
    @State private var isTaskWriteConfirmed = false
    @State private var isAppendingTaskDraft = false
    @State private var taskAppendResult: AppendAgentTaskDraftResponse?
    @State private var isOpeningCodex = false
    @State private var isCopyingCodexContext = false
    @State private var copiedActionResponseID: AgentActionResponse.ID?

    private var metadataRows: [(String, String)] {
        event.metadata
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    private var displayedTaskDraft: AgentEventTaskDraftResponse {
        taskDraft ?? event.fallbackTaskDraft
    }

    private var actionSurface: AgentActionSurface? {
        AgentActionSurface(event: event)
    }

    private var workspaceMatch: WorkspaceSummary? {
        let candidates = [
            event.workspaceFolder,
            event.metadata["workspaceFolder"],
            event.metadata["folder"],
            event.metadata["workspace"],
            event.metadata["workspacePath"],
            event.metadata["path"]
        ]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        return appState.workspaces.first { workspace in
            candidates.contains(workspace.folder) || candidates.contains(workspace.path)
        }
    }

    private var localTargets: [AgentEventTarget] {
        AgentEventTarget.localTargets(from: event.metadata)
    }

    private var webTargets: [AgentEventTarget] {
        AgentEventTarget.webTargets(from: event.metadata)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: symbol)
                        .font(.title3)
                        .foregroundStyle(color)
                        .frame(width: 28, height: 28)

                    VStack(alignment: .leading, spacing: 5) {
                        Text(event.title)
                            .font(.title3.weight(.semibold))
                        HStack(spacing: 8) {
                            Pill(label: event.source, systemImage: "point.3.connected.trianglepath.dotted")
                            Pill(label: event.kind, systemImage: "tag")
                            Pill(label: event.severity, systemImage: "circle.dashed")
                        }
                    }

                    Spacer()

                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                    }
                    .buttonStyle(.borderless)
                    .keyboardShortcut(.cancelAction)
                }

                SectionBlock(title: "摘要 / Summary") {
                    Text(event.summary)
                        .font(.body)
                        .fixedSize(horizontal: false, vertical: true)
                }

                SectionBlock(title: "上下文 / Context") {
                    AgentEventField(label: "Time", value: event.timestamp)
                    AgentEventField(label: "Session", value: event.sessionId)
                    AgentEventField(label: "Workspace", value: event.workspaceFolder ?? "No workspace")
                    AgentEventField(label: "Event ID", value: event.id)
                }

                if let actionSurface {
                    SectionBlock(title: "Agent 动作面 / Action surface") {
                        AgentActionSurfaceView(
                            surface: actionSurface,
                            copiedResponseID: copiedActionResponseID
                        ) { response in
                            copyActionResponse(response)
                        }
                    }
                }

                SectionBlock(title: "任务草稿 / Task draft") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Pill(label: displayedTaskDraft.category, systemImage: "tray.full")
                            Pill(label: displayedTaskDraft.priority, systemImage: "flag")
                            Pill(label: displayedTaskDraft.status, systemImage: "doc.badge.clock")
                            if isTaskDraftLoading {
                                ProgressView()
                                    .controlSize(.small)
                            }
                        }

                        Text(displayedTaskDraft.title)
                            .font(.subheadline.weight(.semibold))
                            .textSelection(.enabled)

                        Text(displayedTaskDraft.summary)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)

                        if !displayedTaskDraft.relatedTargets.isEmpty {
                            ForEach(displayedTaskDraft.relatedTargets.prefix(5)) { target in
                                AgentEventField(label: "\(target.kind) · \(target.label)", value: target.value)
                            }
                        }

                        HStack {
                            Button("Copy title") {
                                copyToPasteboard(displayedTaskDraft.title)
                            }
                            Button("Copy prompt") {
                                copyToPasteboard(displayedTaskDraft.prompt)
                            }
                        }

                        if let workspace = workspaceMatch {
                            Divider()
                            Toggle("确认写入 tasks.md / Confirm write", isOn: $isTaskWriteConfirmed)
                                .toggleStyle(.checkbox)
                            HStack {
                                Button(isAppendingTaskDraft ? "Writing" : "Add to tasks.md") {
                                    appendTaskDraft(to: workspace)
                                }
                                .disabled(!isTaskWriteConfirmed || isAppendingTaskDraft)
                            }

                            if let taskAppendResult {
                                AgentTaskDraftResultView(
                                    result: taskAppendResult,
                                    focusAgentTask: {
                                        appState.focusAgentTask(sourceEventID: taskAppendResult.sourceEventId)
                                        dismiss()
                                    },
                                    openTasksDocument: {
                                        appState.focusWorkspace(id: workspace.id)
                                        Task {
                                            await appState.loadDocument(path: taskAppendResult.path)
                                        }
                                        dismiss()
                                    }
                                )
                            }
                        } else {
                            Text("Select a matching workspace before writing this draft.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                SectionBlock(title: "下一步 / Actions") {
                    if let workspace = workspaceMatch {
                        AgentEventActionRow(
                            title: "选中工作区 / Select workspace",
                            detail: workspace.folder,
                            systemImage: "scope",
                            isEnabled: true
                        ) {
                            appState.selectedWorkspaceID = workspace.id
                        }

                        AgentEventActionRow(
                            title: "打开工作区目录 / Open workspace folder",
                            detail: workspace.path,
                            systemImage: "folder",
                            isEnabled: FileManager.default.fileExists(atPath: workspace.path)
                        ) {
                            openLocalPath(workspace.path)
                        }
                    } else {
                        Text("No matching workspace in current dashboard")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    ForEach(localTargets) { target in
                        AgentEventActionRow(
                            title: "打开本地路径 / Open local path",
                            detail: "\(target.key): \(target.value)",
                            systemImage: target.exists ? "doc.viewfinder" : "doc.badge.clock",
                            isEnabled: target.exists
                        ) {
                            openLocalPath(target.value)
                        }
                    }

                    ForEach(webTargets) { target in
                        AgentEventActionRow(
                            title: "打开链接 / Open link",
                            detail: "\(target.key): \(target.value)",
                            systemImage: "arrow.up.right.square",
                            isEnabled: true
                        ) {
                            openURL(target.value)
                        }
                    }

                    AgentEventActionRow(
                        title: isOpeningCodex ? "正在打开 Codex / Opening Codex" : "打开 Codex 继续 / Open in Codex",
                        detail: "复制事件上下文并打开 Settings 中配置的 Codex URL。",
                        systemImage: "point.3.connected.trianglepath.dotted",
                        isEnabled: !isOpeningCodex
                    ) {
                        openInCodex()
                    }

                    AgentEventActionRow(
                        title: isCopyingCodexContext ? "正在复制 / Copying" : "复制 Codex 上下文 / Copy Codex context",
                        detail: "只复制事件接力包，不打开外部应用。",
                        systemImage: "doc.on.clipboard",
                        isEnabled: !isCopyingCodexContext
                    ) {
                        copyCodexContext()
                    }
                }

                SectionBlock(title: "Metadata") {
                    if metadataRows.isEmpty {
                        Text("No metadata")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(metadataRows, id: \.0) { key, value in
                            AgentEventField(label: key, value: value)
                        }
                    }
                }

                HStack {
                    Button("Copy JSON") {
                        copyEventJSON()
                    }
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
        .padding(22)
        .frame(width: 680, height: 640)
        .task(id: event.id) {
            await loadTaskDraft()
        }
    }

    private var symbol: String {
        switch event.kind {
        case "permission":
            "hand.raised"
        case "question":
            "questionmark.circle"
        case "tool_use":
            "terminal"
        default:
            "point.3.connected.trianglepath.dotted"
        }
    }

    private var color: Color {
        switch event.severity {
        case "warning":
            NexusPalette.warning
        case "error":
            NexusPalette.danger
        default:
            NexusPalette.accent
        }
    }

    private func copyEventJSON() {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(event),
              let payload = String(data: data, encoding: .utf8) else {
            return
        }
        copyToPasteboard(payload)
    }

    private func openInCodex() {
        isOpeningCodex = true
        Task {
            await appState.openAgentEventInCodex(event)
            isOpeningCodex = false
        }
    }

    private func copyCodexContext() {
        isCopyingCodexContext = true
        Task {
            await appState.copyAgentEventCodexContext(event)
            isCopyingCodexContext = false
        }
    }

    private func copyActionResponse(_ response: AgentActionResponse) {
        copiedActionResponseID = response.id
        Task {
            await appState.copyAgentEventActionResponse(
                label: response.label,
                payload: response.payload,
                for: event
            )
        }
    }

    private func loadTaskDraft() async {
        isTaskDraftLoading = true
        taskDraft = await appState.agentEventTaskDraft(for: event)
        isTaskDraftLoading = false
    }

    private func appendTaskDraft(to workspace: WorkspaceSummary) {
        let draft = displayedTaskDraft
        isAppendingTaskDraft = true
        Task {
            taskAppendResult = await appState.appendAgentTaskDraft(
                draft,
                to: workspace,
                confirmed: isTaskWriteConfirmed
            )
            isAppendingTaskDraft = false
        }
    }

    private func copyToPasteboard(_ payload: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(payload, forType: .string)
    }

    private func openLocalPath(_ rawPath: String) {
        guard let url = AgentEventTarget.localURL(from: rawPath) else { return }
        NSWorkspace.shared.open(url)
    }

    private func openURL(_ rawURL: String) {
        guard let url = URL(string: rawURL.trimmingCharacters(in: .whitespacesAndNewlines)) else { return }
        NSWorkspace.shared.open(url)
    }
}

private struct AgentActionSurfaceView: View {
    let surface: AgentActionSurface
    let copiedResponseID: AgentActionResponse.ID?
    let onCopy: (AgentActionResponse) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: surface.kind.systemImage)
                    .font(.body)
                    .foregroundStyle(NexusPalette.accent)
                    .frame(width: 20)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        Text(surface.title)
                            .font(.subheadline.weight(.semibold))
                        Pill(label: surface.kind.statusLabel, systemImage: "clock.badge.exclamationmark")
                    }
                    Text(surface.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(surface.safetyNote)
                        .font(.caption)
                        .foregroundStyle(NexusPalette.warning)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                AgentResponseCopyButton(
                    response: surface.primaryResponse,
                    isCopied: copiedResponseID == surface.primaryResponse.id,
                    onCopy: onCopy
                )

                if let secondaryResponse = surface.secondaryResponse {
                    AgentResponseCopyButton(
                        response: secondaryResponse,
                        isCopied: copiedResponseID == secondaryResponse.id,
                        onCopy: onCopy
                    )
                }

                Spacer()
            }
        }
    }
}

private struct AgentTaskDraftResultView: View {
    let result: AppendAgentTaskDraftResponse
    let focusAgentTask: () -> Void
    let openTasksDocument: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: result.appended ? "checkmark.circle" : "doc.text")
                    .foregroundStyle(result.appended ? NexusPalette.success : .secondary)
                    .frame(width: 16)

                VStack(alignment: .leading, spacing: 3) {
                    Text(result.appended ? "任务已写入 / Task added" : "任务已存在 / Already exists")
                        .font(.caption.weight(.semibold))
                    Text(result.title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                    Text("下一步可从任务中心的 Agent 筛选继续处理，或打开 tasks.md 复查源文档。")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            HStack(spacing: 8) {
                Button {
                    focusAgentTask()
                } label: {
                    Label("查看 Agent 任务", systemImage: "line.3.horizontal.decrease.circle")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    openTasksDocument()
                } label: {
                    Label("打开 tasks.md", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusPalette.selected)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct AgentResponseCopyButton: View {
    let response: AgentActionResponse
    let isCopied: Bool
    let onCopy: (AgentActionResponse) -> Void

    var body: some View {
        Button {
            onCopy(response)
        } label: {
            Label(isCopied ? "已复制 / Copied" : response.label, systemImage: isCopied ? "checkmark" : response.systemImage)
                .lineLimit(1)
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
    }
}

private struct AgentEventField: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct AgentEventActionRow: View {
    let title: String
    let detail: String
    let systemImage: String
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isEnabled ? NexusPalette.accent : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.caption.weight(.semibold))
                    Text(detail)
                        .font(.system(.caption2, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.55)
    }
}

private struct AgentEventTarget: Identifiable {
    let key: String
    let value: String
    let exists: Bool

    var id: String {
        "\(key):\(value)"
    }

    static func localTargets(from metadata: [String: String]) -> [AgentEventTarget] {
        uniqueTargets(from: metadata) { key, value in
            guard isLocalPathKey(key) || localURL(from: value) != nil else { return nil }
            guard let url = localURL(from: value) else { return nil }
            return AgentEventTarget(
                key: key,
                value: value,
                exists: FileManager.default.fileExists(atPath: url.path)
            )
        }
    }

    static func webTargets(from metadata: [String: String]) -> [AgentEventTarget] {
        uniqueTargets(from: metadata) { key, value in
            guard isWebURL(value) else { return nil }
            return AgentEventTarget(key: key, value: value, exists: true)
        }
    }

    static func localURL(from rawValue: String) -> URL? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if trimmed.hasPrefix("file://") {
            return URL(string: trimmed)
        }

        guard trimmed.hasPrefix("/") || trimmed.hasPrefix("~/") else {
            return nil
        }

        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
    }

    private static func uniqueTargets(
        from metadata: [String: String],
        mapper: (String, String) -> AgentEventTarget?
    ) -> [AgentEventTarget] {
        var seenValues: Set<String> = []
        return metadata
            .sorted { $0.key < $1.key }
            .compactMap { key, value in
                guard let target = mapper(key, value) else { return nil }
                let normalizedValue = target.value.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !seenValues.contains(normalizedValue) else { return nil }
                seenValues.insert(normalizedValue)
                return target
            }
    }

    private static func isLocalPathKey(_ key: String) -> Bool {
        let normalizedKey = key.lowercased()
        return normalizedKey.contains("path")
            || normalizedKey.contains("file")
            || normalizedKey.contains("folder")
            || normalizedKey.contains("directory")
    }

    private static func isWebURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased() else {
            return false
        }
        return scheme == "http" || scheme == "https"
    }
}

private struct SetupReadinessSidebarCard: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isCreateWorkspacePresented: Bool
    @Binding var isSettingsPresented: Bool

    private var readiness: NativeSetupReadiness {
        appState.setupReadiness
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Image(systemName: symbol)
                    .foregroundStyle(color)
                    .frame(width: 16)
                VStack(alignment: .leading, spacing: 2) {
                    Text("本机设置 / Setup")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                    Text(readiness.title)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }
                Spacer()
                EnvironmentStatusPill(status: readiness.status.environmentStatus)
            }

            Text(readiness.detail)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .lineLimit(3)

            HStack(spacing: 8) {
                Button {
                    runPrimaryAction()
                } label: {
                    Label(readiness.primaryActionLabel, systemImage: primarySymbol)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
                .disabled(appState.isCheckingNativeEnvironment || appState.isLoading)

                Button {
                    isSettingsPresented = true
                } label: {
                    Label(readiness.secondaryActionLabel, systemImage: "gearshape")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func runPrimaryAction() {
        switch readiness.status {
        case .ready where appState.workspaces.isEmpty:
            isCreateWorkspacePresented = true
        case .ready:
            Task {
                await appState.refreshFromBridge()
            }
        default:
            Task {
                await appState.checkNativeEnvironment()
            }
        }
    }

    private var symbol: String {
        switch readiness.status {
        case .ready:
            "checkmark.seal"
        case .needsReview:
            "exclamationmark.triangle"
        case .unchecked:
            "questionmark.circle"
        }
    }

    private var primarySymbol: String {
        switch readiness.status {
        case .ready where appState.workspaces.isEmpty:
            "plus"
        case .ready:
            "arrow.clockwise"
        default:
            "checkmark.seal"
        }
    }

    private var color: Color {
        switch readiness.status {
        case .ready:
            NexusPalette.success
        case .needsReview:
            NexusPalette.danger
        case .unchecked:
            NexusPalette.warning
        }
    }
}

private struct SidebarMetric: View {
    let label: String
    let value: Int

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(.caption, design: .monospaced).weight(.semibold))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private enum NexusPalette {
    static let background = Color(nsColor: NSColor.windowBackgroundColor)
    static let sidebar = Color(nsColor: NSColor.controlBackgroundColor)
    static let inspector = Color(nsColor: NSColor.textBackgroundColor)
    static let panel = Color(nsColor: NSColor.textBackgroundColor)
    static let selected = Color.blue.opacity(0.08)
    static let preview = Color(nsColor: NSColor.controlBackgroundColor).opacity(0.72)
    static let badge = Color(nsColor: NSColor.controlBackgroundColor)
    static let border = Color.black.opacity(0.08)
    static let accent = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
}
