import AppKit
import NexusBridge
import SwiftUI

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

                    ForEach(appState.agentEvents.prefix(3), id: \.id) { event in
                        AgentEventRow(event: event)
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

            HStack(spacing: 16) {
                Metric(label: "服务 / Services", value: "\(workspace.services.count)")
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
        VStack(alignment: .leading, spacing: 18) {
            if let workspace = appState.selectedWorkspace {
                WorkspaceDetailView(workspace: workspace)
            } else {
                Text("选择一个工作区")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(18)
        .background(NexusPalette.inspector)
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
        .frame(width: 620, height: 420)
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
