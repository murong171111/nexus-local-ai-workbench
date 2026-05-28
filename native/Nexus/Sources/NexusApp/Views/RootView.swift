import AppKit
import NexusBridge
import SwiftUI

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

                WorkspaceListView()
            }

            Divider()

            InspectorView()
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

    private var services: [String] {
        servicesText
            .split { character in
                character.isWhitespace || [",", "，", "、", ";", "；"].contains(String(character))
            }
            .map { String($0).trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
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
                TextField("需求名称", text: $name)
                    .onChange(of: name) { value in
                        if folder.isEmpty || folder.hasSuffix("-workspace") {
                            folder = defaultFolder(for: value)
                        }
                    }
                TextField("工作区目录名", text: $folder)
                TextField("涉及服务，逗号或空格分隔", text: $servicesText)
                TextField("目标分支，留空则待确认", text: $targetBranch)
                Toggle("确认创建目录和标准 Markdown 文档", isOn: $confirmed)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Workspaces root")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Text(appState.workspaceRoot)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
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
        .padding(22)
        .frame(width: 560)
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

private struct WorktreeSetupSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var confirmed = false
    let workspace: WorkspaceSummary

    private var missingServices: [String] {
        appState.missingWorktreeServices(in: workspace)
    }

    private var canRun: Bool {
        confirmed && appState.canSetupWorktrees(in: workspace) && !appState.isSettingUpWorktrees
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
                    WorktreeSetupMetaRow(label: "Workspace", value: workspace.path)
                    WorktreeSetupMetaRow(label: "Source repos", value: appState.sourceReposRoot)
                    WorktreeSetupMetaRow(label: "Target branch", value: workspace.branch)
                }

                SectionBlock(title: "缺失服务 / Missing services") {
                    if missingServices.isEmpty {
                        Label("All selected services already have worktrees", systemImage: "checkmark.circle")
                            .foregroundStyle(NexusPalette.success)
                    } else {
                        FlowTags(values: missingServices)
                    }
                }

                Toggle("确认执行本地 git fetch 与 git worktree add", isOn: $confirmed)

                HStack {
                    Button("Close") {
                        dismiss()
                    }
                    .keyboardShortcut(.cancelAction)

                    Spacer()

                    Button(appState.isSettingUpWorktrees ? "Setting up" : "Setup worktrees") {
                        Task {
                            await appState.setupMissingWorktrees(for: workspace, confirmed: confirmed)
                        }
                    }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!canRun)
                }

                if let response = appState.lastWorktreeSetupResponse {
                    WorktreeSetupResultView(response: response)
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
    let response: SetupWorktreesResponse

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(resultSummary, systemImage: response.failed.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(response.failed.isEmpty ? NexusPalette.success : NexusPalette.warning)

            if !response.command.isEmpty {
                Text(response.command)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            WorktreeSetupResultGroup(title: "Created", results: response.created, color: NexusPalette.success)
            WorktreeSetupResultGroup(title: "Skipped", results: response.skipped, color: .secondary)
            WorktreeSetupResultGroup(title: "Failed", results: response.failed, color: NexusPalette.danger)
        }
        .padding(12)
        .background(NexusPalette.badge)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private var resultSummary: String {
        "\(response.created.count) created · \(response.skipped.count) skipped · \(response.failed.count) failed"
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

    var body: some View {
        ScrollView {
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
        .background(NexusPalette.panel)
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(isSelected ? NexusPalette.accent : NexusPalette.border, lineWidth: isSelected ? 1.4 : 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

private struct InspectorView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                AutomationActionCenterView()

                if let workspace = appState.selectedWorkspace {
                    WorkspaceDetailView(workspace: workspace)
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text("选择一个工作区")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(18)
        .background(NexusPalette.inspector)
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

            if !workspace.tasks.isEmpty {
                SectionBlock(title: "本地任务 / Tasks") {
                    ForEach(Array(workspace.tasks.prefix(6))) { task in
                        WorkspaceTaskRow(
                            task: task,
                            completeAction: {
                                appState.requestTaskStatusUpdate(task, in: workspace, status: "已完成")
                            },
                            deferAction: {
                                appState.requestTaskStatusUpdate(task, in: workspace, status: "延期")
                            },
                            codexAction: {
                                copyTaskHandoff(task, in: workspace)
                            }
                        )
                    }
                }
            }

            if !workspace.healthChecks.isEmpty {
                SectionBlock(title: "就绪检查 / Readiness") {
                    ForEach(workspace.healthChecks) { check in
                        HealthCheckRow(check: check)
                    }
                }
            }

            if !workspace.sessionActions.isEmpty {
                SectionBlock(title: "会话动作 / Session actions") {
                    ForEach(workspace.sessionActions) { action in
                        SessionActionRow(action: action) {
                            run(action)
                        }
                    }
                }
            }

            SectionBlock(title: "风险告警 / Risks") {
                if workspace.risks.isEmpty {
                    Label("No active risk", systemImage: "checkmark.circle")
                        .foregroundStyle(NexusPalette.success)
                } else {
                    ForEach(workspace.risks) { risk in
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(risk.title)
                                Text(risk.detail)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "exclamationmark.triangle")
                                .foregroundStyle(NexusPalette.warning)
                        }
                    }
                }
            }

            SectionBlock(title: "最近活动 / Activity") {
                ActivityTimelineView(events: workspace.activities)
            }

            SectionBlock(title: "文档预览 / Documents") {
                Button {
                    Task {
                        await appState.loadHandoffForSelectedWorkspace()
                    }
                } label: {
                    Label(appState.isDocumentLoading ? "Loading handoff" : "Load handoff", systemImage: "doc.text")
                }
                .buttonStyle(.bordered)
                .disabled(appState.isDocumentLoading)

                if let document = appState.documentPreview {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.name)
                            .font(.caption.weight(.semibold))
                        Text(String(document.content.prefix(260)))
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .lineLimit(6)
                    }
                }
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
                }

                Section("Native Shell") {
                    Text("Bridge mode: \(appState.bridgeMode)")
                    Text("Search scope: \(appState.selectedSearchScope.label) / \(appState.selectedSearchScope.subtitle)")
                    Text("Pinned workspaces: \(appState.pinnedWorkspaceIDs.count)")
                    Text("Set NEXUS_CORE_LIBRARY to a local libnexus_ffi.dylib to load real workspace data through Rust Core during development.")
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
        .onDisappear {
            appState.persistLocalPaths()
        }
        .padding(20)
        .frame(width: 620, height: 520)
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
