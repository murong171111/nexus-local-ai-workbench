import AppKit
import NexusBridge
import SwiftUI
import UniformTypeIdentifiers

private func copyToPasteboard(_ payload: String) {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(payload, forType: .string)
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
                    if let lastError = appState.lastError {
                        Text(lastError)
                            .font(.caption2)
                            .foregroundStyle(NexusPalette.danger)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(12)
                .background(NexusPalette.panel)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            }

            if !appState.agentEvents.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Agent 事件 / Events")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)

                    ForEach(appState.agentEvents.prefix(3)) { event in
                        Button {
                            appState.selectedAgentEvent = event
                        } label: {
                            AgentEventRow(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if appState.taskCenterTotalCount > 0 {
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

                    TaskCenterFilterBar()

                    if appState.taskCenterItems.isEmpty {
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
                                selectAction: {
                                    appState.selectTaskCenterItem(item)
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

            VStack(alignment: .leading, spacing: 8) {
                Text("筛选 / Filters")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ForEach(WorkspaceFilter.allCases) { filter in
                    Button {
                        appState.selectedFilter = filter
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
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(filter == appState.selectedFilter ? NexusPalette.selected : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }

            Spacer()

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
        .padding(18)
        .background(NexusPalette.sidebar)
    }

    private func copyTaskHandoff(_ item: TaskCenterItem) {
        guard let workspace = appState.workspaces.first(where: { $0.id == item.workspaceID }) else {
            return
        }
        appState.selectTaskCenterItem(item)
        Task {
            let payload = await appState.workspaceTaskHandoffPrompt(for: item.task, in: workspace)
            copyToPasteboard(payload)
            await appState.recordTaskHandoffCopied(task: item.task, in: workspace)
        }
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
            && confirmed
            && !appState.isCreatingWorkspace
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

    private static func todayString() -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: Date())
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
    case blocker
    case blockedDone
    case info

    var symbol: String {
        switch self {
        case .pass:
            return "checkmark.circle"
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

            WorktreeSetupResultGroup(title: "Created", results: response.created, color: NexusPalette.success)
            WorktreeSetupResultGroup(title: "Skipped", results: response.skipped, color: .secondary)
            WorktreeSetupResultGroup(title: "Failed", results: response.failed, color: NexusPalette.danger)

            HStack(spacing: 8) {
                Button {
                    Task {
                        await appState.openWorkspaceInFinder(workspace)
                    }
                } label: {
                    Label("Finder", systemImage: "folder")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task {
                        await appState.openWorkspaceInCodex(workspace)
                    }
                } label: {
                    Label("Codex", systemImage: "point.3.connected.trianglepath.dotted")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    Task {
                        await appState.runLocalAutomationCheck()
                    }
                } label: {
                    Label(appState.isRunningAutomationCheck ? "Checking" : "Check", systemImage: "checklist")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isRunningAutomationCheck)

                Spacer()

                Button("Close") {
                    closeAction()
                }
                .buttonStyle(.borderless)
                .controlSize(.small)
            }
        }
        .padding(12)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var resultSummary: String {
        "\(response.created.count) created · \(response.skipped.count) skipped · \(response.failed.count) failed"
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

            LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                if hasWorkspaces && hasSearchOrFilter {
                    Button {
                        appState.selectedFilter = .all
                        appState.clearSearch()
                    } label: {
                        Label("Show all", systemImage: "square.grid.2x2")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                Button {
                    isCreateWorkspacePresented = true
                } label: {
                    Label("New Workspace", systemImage: "plus")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)

                Button {
                    isSettingsPresented = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)

                Button {
                    Task {
                        await appState.checkNativeEnvironment()
                    }
                } label: {
                    Label(appState.isCheckingNativeEnvironment ? "Checking" : "Environment", systemImage: "checkmark.seal")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isCheckingNativeEnvironment)

                Button {
                    Task {
                        await appState.refreshFromBridge()
                    }
                } label: {
                    Label(appState.isLoading ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.isLoading)
            }
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

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 126), spacing: 8, alignment: .leading)]
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
                Metric(label: "任务 / Tasks", value: "\(workspace.tasks.filter { !$0.isDone }.count) open")
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
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let feedback = appState.codexHandoffFeedback {
                    CodexHandoffFeedbackView(feedback: feedback) {
                        appState.clearCodexHandoffFeedback()
                    }
                }

                AutomationActionCenterView()

                if let workspace = appState.selectedWorkspace {
                    WorkspaceDetailView(workspace: workspace)
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

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                    Button {
                        isCreateWorkspacePresented = true
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        isSettingsPresented = true
                    } label: {
                        Label("Settings", systemImage: "gearshape")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task {
                            await appState.refreshFromBridge()
                        }
                    } label: {
                        Label(appState.isLoading ? "Refreshing" : "Refresh", systemImage: "arrow.clockwise")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isLoading)
                }
            }
        }
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

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 92), spacing: 8, alignment: .leading)]
    }
}

private struct CodexHandoffFeedbackView: View {
    let feedback: CodexHandoffFeedback
    let dismissAction: () -> Void

    var body: some View {
        SectionBlock(title: "交接状态 / Handoff") {
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
                        Text("\(feedback.timestamp) · Prompt is on the clipboard")
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

                Label("如果 Codex 没有自动带入内容，直接粘贴剪贴板里的上下文。", systemImage: "doc.on.clipboard")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
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
                    Text("运行本地检查后，这里会把风险、交付、任务和 worktree 信号转换成可执行动作。")
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

    var body: some View {
        HStack(spacing: 8) {
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
                value: worktreeIssueCount,
                tone: worktreeIssueCount > 0 ? NexusPalette.warning : NexusPalette.success
            )
            AutomationMetric(
                label: "Archive",
                value: check.archivedWorkspaceCount,
                tone: .secondary
            )
        }
    }

    private var worktreeIssueCount: Int {
        check.missingWorktreeCount + check.dirtyServiceCount
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
            "Focus"
        case "update-delivery":
            "Delivery"
        case "review-worktrees":
            "Worktree"
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

            if appState.lastCreatedWorkspace?.folder == workspace.folder {
                WorkspaceCreationNextStepsView(workspace: workspace)
            }

            WorkspaceCommandCenterView(workspace: workspace)
                .environmentObject(appState)

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
                taskCodexAction: { task in
                    copyTaskHandoff(task, in: workspace)
                }
            )
            .environmentObject(appState)

            SectionBlock(title: "服务 Git 状态 / Services") {
                ForEach(workspace.services) { service in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack {
                            Text(service.name)
                                .font(.subheadline.weight(.medium))
                            Spacer()
                            Text(service.gitSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Text("\(service.branch) · \(service.worktree)")
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }

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

            if !workspace.sessionActions.isEmpty {
                SectionBlock(title: "建议动作 / Suggested actions") {
                    ForEach(workspace.sessionActions) { action in
                        SessionActionRow(action: action) {
                            run(action)
                        }
                    }
                }
            }

            WorkspaceDocumentsHubView(workspace: workspace)
                .environmentObject(appState)

            SectionBlock(title: "最近活动 / Activity") {
                ActivityTimelineView(events: workspace.activities)
            }

            Spacer()
        }
    }

    private func run(_ action: WorkspaceSessionAction) {
        if action.instructionType == "worktree" {
            appState.presentWorktreeSetup(for: workspace)
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
            let payload = await appState.workspaceTaskHandoffPrompt(for: task, in: workspace)
            copyToPasteboard(payload)
            await appState.recordTaskHandoffCopied(task: task, in: workspace)
        }
    }

    private var riskReviewChecks: [WorkspaceHealthCheck] {
        workspace.healthChecks.filter { check in
            check.id != "delivery-record" && check.action != "delivery"
        }
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

    var id: String { key }
}

private struct WorkspaceDocumentsHubView: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary

    private let standardEntries: [WorkspaceDocumentEntry] = [
        WorkspaceDocumentEntry(key: "workspace", label: "Workspace", description: "需求范围", systemImage: "doc.text", fallbackRelativePath: "workspace.md"),
        WorkspaceDocumentEntry(key: "status", label: "Status", description: "当前状态", systemImage: "gauge.with.dots.needle.bottom.50percent", fallbackRelativePath: "STATUS.md"),
        WorkspaceDocumentEntry(key: "services", label: "Services", description: "服务范围", systemImage: "square.stack.3d.up", fallbackRelativePath: "services.md"),
        WorkspaceDocumentEntry(key: "branches", label: "Branches", description: "分支记录", systemImage: "arrow.triangle.branch", fallbackRelativePath: "branches.md"),
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

    private var documentEntries: [ResolvedWorkspaceDocumentEntry] {
        standardEntries.map { entry in
            ResolvedWorkspaceDocumentEntry(
                entry: entry,
                path: workspace.documentLinks[entry.key] ?? "\(workspace.path)/\(entry.fallbackRelativePath)"
            )
        }
    }

    var body: some View {
        SectionBlock(title: "文档入口 / Documents") {
            VStack(alignment: .leading, spacing: 12) {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 116), spacing: 8)], alignment: .leading, spacing: 8) {
                    ForEach(documentEntries) { entry in
                        Button {
                            Task {
                                await appState.loadDocument(path: entry.path)
                            }
                        } label: {
                            VStack(alignment: .leading, spacing: 4) {
                                Label(entry.label, systemImage: entry.systemImage)
                                    .font(.caption.weight(.semibold))
                                    .lineLimit(1)
                                Text(entry.description)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(8)
                            .background(NexusPalette.badge)
                            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(appState.isDocumentLoading)
                        .help(entry.path)
                    }
                }

                if appState.isDocumentLoading {
                    HStack(spacing: 8) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Loading document...")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let document = activePreview {
                    NativeDocumentPreview(document: document)
                } else {
                    Label("选择一个文档后在这里预览。", systemImage: "doc.text.magnifyingglass")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
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

private struct NativeDocumentPreview: View {
    let document: DocumentSnapshot
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
            .frame(maxHeight: 260)
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
    let workspace: WorkspaceSummary

    private var openTaskCount: Int {
        workspace.tasks.filter { !$0.isDone }.count
    }

    private var missingWorktreeCount: Int {
        workspace.services.filter { !$0.worktreeExists }.count
    }

    private var blockedTaskCount: Int {
        workspace.tasks.filter { !$0.isDone && $0.isBlocked }.count
    }

    private var serviceValue: String {
        if workspace.services.isEmpty {
            return "pending"
        }
        if missingWorktreeCount > 0 {
            return "\(workspace.services.count) / \(missingWorktreeCount) miss"
        }
        return "\(workspace.services.count) ready"
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
        openTaskCount == 0 ? NexusPalette.success : NexusPalette.accent
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
                statusLabel: "archive",
                systemImage: "archivebox",
                actionLabel: "Open docs",
                actionSystemImage: "doc.text",
                tone: .secondary,
                action: .document("handoff")
            )
        }

        if !Self.hasConfirmedTargetBranch(workspace.branch) {
            return CommandCenterPrimaryStep(
                title: "确认目标分支 / Confirm branch",
                detail: "分支仍是待确认状态。先补齐 branches.md 或 workspace.md，后续 worktree 和交付检查才有可靠基准。",
                statusLabel: "block",
                systemImage: "arrow.triangle.branch",
                actionLabel: "Open branch",
                actionSystemImage: "doc.text",
                tone: NexusPalette.danger,
                action: .document("branches")
            )
        }

        if workspace.services.isEmpty {
            return CommandCenterPrimaryStep(
                title: "确认服务范围 / Confirm services",
                detail: "服务范围为空。先确认涉及服务，Nexus 才能检查 worktree、风险和交付影响面。",
                statusLabel: "block",
                systemImage: "square.stack.3d.up",
                actionLabel: "Open services",
                actionSystemImage: "doc.text",
                tone: NexusPalette.danger,
                action: .document("services")
            )
        }

        if missingWorktreeCount > 0 {
            return CommandCenterPrimaryStep(
                title: "创建缺失 worktree / Setup worktrees",
                detail: "\(missingWorktreeCount) 个服务还没有 workspace-local worktree。先完成隔离工作副本，再进入代码修改。",
                statusLabel: "next",
                systemImage: "arrow.triangle.branch",
                actionLabel: "Setup",
                actionSystemImage: "wrench.and.screwdriver",
                tone: NexusPalette.warning,
                action: .worktree
            )
        }

        if workspace.riskLevel == .high || !workspace.risks.isEmpty {
            return CommandCenterPrimaryStep(
                title: "复核风险 / Review risks",
                detail: "当前存在 \(workspace.risks.count) 个风险信号。建议先复制风险复核上下文交给 Codex，再决定是否继续交付。",
                statusLabel: workspace.riskLevel == .high ? "block" : "review",
                systemImage: "exclamationmark.triangle",
                actionLabel: "Risk prompt",
                actionSystemImage: "point.3.connected.trianglepath.dotted",
                tone: workspace.riskLevel == .high ? NexusPalette.danger : NexusPalette.warning,
                action: .riskPrompt
            )
        }

        if blockedTaskCount > 0 {
            return CommandCenterPrimaryStep(
                title: "处理阻塞任务 / Resolve blocked tasks",
                detail: "\(blockedTaskCount) 个任务仍处于阻塞状态。先打开 tasks.md，确认完成、延期或继续拆解。",
                statusLabel: "block",
                systemImage: "checklist",
                actionLabel: "Open tasks",
                actionSystemImage: "checklist",
                tone: NexusPalette.danger,
                action: .document("tasks")
            )
        }

        if openTaskCount > 0 {
            return CommandCenterPrimaryStep(
                title: "处理开放任务 / Review tasks",
                detail: "\(openTaskCount) 个任务仍未关闭。开发前后都可以从这里确认任务状态和交付影响。",
                statusLabel: "next",
                systemImage: "checklist",
                actionLabel: "Open tasks",
                actionSystemImage: "checklist",
                tone: NexusPalette.accent,
                action: .document("tasks")
            )
        }

        if workspace.lifecycle.stage == "delivery" {
            return CommandCenterPrimaryStep(
                title: "整理交付 / Prepare delivery",
                detail: "任务和 worktree 已基本就绪。现在重点是交付记录、SQL、验证和风险说明。",
                statusLabel: "next",
                systemImage: "shippingbox",
                actionLabel: "Delivery",
                actionSystemImage: "doc.text",
                tone: NexusPalette.warning,
                action: .document("delivery")
            )
        }

        return CommandCenterPrimaryStep(
            title: "继续开发 / Continue with Codex",
            detail: "当前主流程没有明显阻塞。可以把工作区上下文交给 Codex 继续开发或复核。",
            statusLabel: "ready",
            systemImage: "point.3.connected.trianglepath.dotted",
            actionLabel: "Open Codex",
            actionSystemImage: "point.3.connected.trianglepath.dotted",
            tone: NexusPalette.success,
            action: .codex
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

                LazyVGrid(columns: metricColumns, alignment: .leading, spacing: 8) {
                    WorkflowMetric(label: "Branch", value: shortBranch, tone: branchTone)
                    WorkflowMetric(label: "Services", value: serviceValue, tone: worktreeTone)
                    WorkflowMetric(label: "Risk", value: workspace.riskLevel.label, tone: workspace.risks.isEmpty ? NexusPalette.success : NexusPalette.warning)
                    WorkflowMetric(label: "Tasks", value: "\(openTaskCount) open", tone: taskTone)
                }

                LazyVGrid(columns: actionColumns, alignment: .leading, spacing: 8) {
                    Button {
                        Task {
                            await appState.openWorkspaceInCodex(workspace)
                        }
                    } label: {
                        Label("Open Codex", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                    Button {
                        Task {
                            await appState.runLifecycleAction(for: workspace)
                        }
                    } label: {
                        Label(nextActionLabel, systemImage: nextActionSymbol)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task {
                            await appState.runLocalAutomationCheck(actor: "Nexus Command Center")
                        }
                    } label: {
                        Label(appState.isRunningAutomationCheck ? "Checking" : "Run check", systemImage: "checklist.checked")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isRunningAutomationCheck)

                    Button {
                        Task {
                            await appState.openWorkspaceInFinder(workspace)
                        }
                    } label: {
                        Label("Finder", systemImage: "folder")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task {
                            await appState.openWorkspaceInTerminal(workspace)
                        }
                    } label: {
                        Label("Terminal", systemImage: "terminal")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                }

                Text("主路径用于决定下一步；下方工具入口保留 Codex、本地检查、Finder 和 Terminal，方便接力或手工处理。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var actionColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 112), spacing: 8, alignment: .leading)]
    }

    private var metricColumns: [GridItem] {
        [GridItem(.adaptive(minimum: 96), spacing: 8, alignment: .leading)]
    }

    private func runPrimaryStep(_ step: CommandCenterPrimaryStep) {
        switch step.action {
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
        }
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

    private var nextActionLabel: String {
        switch workspace.lifecycle.documentKey {
        case "worktreeScript":
            return "Open next"
        case "delivery":
            return "Open next"
        case "tasks":
            return "Open next"
        case "branches":
            return "Open next"
        case "services":
            return "Open next"
        case "status":
            return "Open next"
        default:
            return "Open next"
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
}

private struct CommandCenterPrimaryStep {
    let title: String
    let detail: String
    let statusLabel: String
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
                    Text(step.statusLabel)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(step.tone)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 2)
                        .background(step.tone.opacity(0.1))
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
            "Setup"
        default:
            "Open"
        }
    }

    private var statusLabel: String {
        switch action.status {
        case "blocked":
            "block"
        case "recommended":
            "next"
        default:
            "later"
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
                    Button {
                        Task {
                            await appState.loadHandoffForSelectedWorkspace()
                        }
                    } label: {
                        Label("打开 handoff / Open handoff", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isDocumentLoading)

                    Button {
                        appState.presentWorktreeSetup(for: workspace)
                    } label: {
                        Label("创建 worktree / Setup worktrees", systemImage: "arrow.triangle.branch")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(!appState.canSetupWorktrees(in: workspace))

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
                        Task {
                            await appState.runLocalAutomationCheck()
                        }
                    } label: {
                        Label(appState.isRunningAutomationCheck ? "检查中 / Checking" : "运行检查 / Run check", systemImage: "checklist")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isRunningAutomationCheck)
                }
            }
        }
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

private struct WorkflowStatusView: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary
    let completeTaskAction: (WorkspaceTask) -> Void
    let deferTaskAction: (WorkspaceTask) -> Void
    let taskCodexAction: (WorkspaceTask) -> Void

    private var openTasks: [WorkspaceTask] {
        workspace.tasks.filter { !$0.isDone }
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
                detail: "\(openTasks.count) 个任务仍未关闭，交付前需要确认是否完成或延期。",
                status: .warning,
                systemImage: "checklist"
            )
        }

        return DeliveryReadinessItem(
            id: "tasks",
            title: "任务状态 / Tasks",
            detail: "当前没有开放任务。",
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

        let status: DeliveryReadinessStatus = sqlCheck.status == "pass" ? .pass : .warning
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
                HStack(spacing: 8) {
                    WorkflowMetric(
                        label: "Open tasks",
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

                HStack(spacing: 8) {
                    Button {
                        Task {
                            await appState.loadDocument(path: tasksPath)
                        }
                    } label: {
                        Label("Tasks", systemImage: "checklist")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task {
                            await appState.loadDocument(path: deliveryPath)
                        }
                    } label: {
                        Label("Delivery", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    Button {
                        Task {
                            await appState.runLocalAutomationCheck()
                        }
                    } label: {
                        Label(appState.isRunningAutomationCheck ? "Checking" : "Check", systemImage: "checklist.checked")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isRunningAutomationCheck)

                    Button {
                        Task {
                            await appState.openWorkspaceInCodex(workspace)
                        }
                    } label: {
                        Label("Codex", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }

                DeliveryReadinessChecklistView(items: readinessItems)

                if openTasks.isEmpty {
                    Label("当前没有开放任务。可以继续查看交付记录或运行本地检查确认状态。", systemImage: "checkmark.circle")
                        .font(.caption)
                        .foregroundStyle(NexusPalette.success)
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(Array(openTasks.prefix(4))) { task in
                            WorkspaceTaskRow(
                                task: task,
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
                            Text("Showing 4 of \(openTasks.count) open tasks. Open tasks.md for the full list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
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

private struct DeliveryReadinessChecklistView: View {
    let items: [DeliveryReadinessItem]

    private var blockerCount: Int {
        items.filter { $0.status == .blocker }.count
    }

    private var warningCount: Int {
        items.filter { $0.status == .warning }.count
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

            VStack(alignment: .leading, spacing: 7) {
                ForEach(items) { item in
                    DeliveryReadinessRow(item: item)
                }
            }
        }
        .padding(10)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct DeliveryReadinessRow: View {
    let item: DeliveryReadinessItem

    var body: some View {
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
                        Label(appState.isRunningAutomationCheck ? "Checking" : "Run check", systemImage: "checklist.checked")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(appState.isRunningAutomationCheck)

                    Button {
                        Task {
                            await appState.loadDocument(path: statusPath)
                        }
                    } label: {
                        Label("Status", systemImage: "doc.text")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if !missingWorktreeServices.isEmpty {
                        Button {
                            appState.presentWorktreeSetup(for: workspace)
                        } label: {
                            Label("Worktree", systemImage: "arrow.triangle.branch")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .disabled(!appState.canSetupWorktrees(in: workspace))
                    }

                    Button {
                        codexAction()
                    } label: {
                        Label("Copy prompt", systemImage: "point.3.connected.trianglepath.dotted")
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
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
                                HealthCheckRow(check: check)
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

    var body: some View {
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

    private var statusLabel: String {
        switch check.status {
        case "pass":
            "pass"
        case "warning":
            "warn"
        default:
            "block"
        }
    }

    private var symbol: String {
        switch check.status {
        case "pass":
            "checkmark.circle"
        case "warning":
            "exclamationmark.circle"
        default:
            "xmark.octagon"
        }
    }

    private var color: Color {
        switch check.status {
        case "pass":
            NexusPalette.success
        case "warning":
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

private struct TaskCenterSidebarRow: View {
    let item: TaskCenterItem
    let selectAction: () -> Void
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
                Button("完成") {
                    completeAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(item.task.isDone)

                Button("延期") {
                    deferAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(item.task.isDone || item.task.status.contains("延期"))

                Button("Codex") {
                    codexAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(NexusPalette.panel)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
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

                        Button("延期") {
                            deferAction()
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                        .disabled(task.status.contains("延期"))
                    }
                }
                Button("Codex") {
                    codexAction()
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
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
                    TextField("Workspaces root", text: $appState.workspaceRoot)
                    TextField("Source repositories root", text: $appState.sourceReposRoot)
                    TextField("Delivery documents root", text: $appState.docsRoot)
                    TextField("Codex URL", text: $appState.codexURL)
                    Stepper(
                        "Profile refresh interval: \(appState.refreshIntervalSeconds) sec",
                        value: $appState.refreshIntervalSeconds,
                        in: 3...3600,
                        step: 1
                    )
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
                    Text("Profiles are compatible with the Tauri preview app and store workspaces, source repositories, delivery documents, Codex URL, and refresh interval.")
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
        .onChange(of: appState.workspaceRoot) { _ in appState.persistLocalPaths() }
        .onChange(of: appState.sourceReposRoot) { _ in appState.persistLocalPaths() }
        .onChange(of: appState.docsRoot) { _ in appState.persistLocalPaths() }
        .onChange(of: appState.codexURL) { _ in appState.persistLocalPaths() }
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

private struct AgentEventRow: View {
    let event: AgentEvent

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

    private var metadataRows: [(String, String)] {
        event.metadata
            .map { ($0.key, $0.value) }
            .sorted { $0.0 < $1.0 }
    }

    private var displayedTaskDraft: AgentEventTaskDraftResponse {
        taskDraft ?? event.fallbackTaskDraft
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

                                if let taskAppendResult {
                                    Text(taskAppendResult.alreadyExists ? "Already exists" : "Added")
                                        .font(.caption)
                                        .foregroundStyle(taskAppendResult.appended ? NexusPalette.success : .secondary)
                                }
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
                        title: "复制 Codex 上下文 / Copy Codex context",
                        detail: "Use this when continuing the event in Codex",
                        systemImage: "doc.on.clipboard",
                        isEnabled: true
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

    private func copyCodexContext() {
        Task {
            let payload = await appState.agentEventHandoffPrompt(for: event)
            copyToPasteboard(payload)
            appState.markAgentEventHandoffCopied(event)
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
