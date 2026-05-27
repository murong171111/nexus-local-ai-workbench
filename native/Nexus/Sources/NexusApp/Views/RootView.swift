import AppKit
import SwiftUI

struct RootView: View {
    @EnvironmentObject private var appState: AppState
    @State private var isCreateWorkspacePresented = false

    var body: some View {
        HStack(spacing: 0) {
            SidebarView(isCreateWorkspacePresented: $isCreateWorkspacePresented)
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
    }
}

private struct TopCommandBar: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("搜索工作区、服务、分支、风险...", text: $appState.query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(NexusPalette.panel)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

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

private struct SidebarView: View {
    @EnvironmentObject private var appState: AppState
    @Binding var isCreateWorkspacePresented: Bool

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

private struct WorkspaceListView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 12) {
                ForEach(appState.filteredWorkspaces) { workspace in
                    WorkspaceCard(
                        workspace: workspace,
                        isSelected: workspace.id == appState.selectedWorkspace?.id
                    )
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
                ForEach(workspace.activities) { event in
                    HStack(alignment: .top, spacing: 8) {
                        Text(event.time)
                            .font(.system(.caption, design: .monospaced))
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(event.title)
                            Text(event.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
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
}

struct SettingsView: View {
    @EnvironmentObject private var appState: AppState

    var body: some View {
        Form {
            Section("Local Paths") {
                TextField("Workspaces root", text: $appState.workspaceRoot)
                TextField("Source repositories root", text: $appState.sourceReposRoot)
                TextField("Delivery documents root", text: $appState.docsRoot)
            }

            Section("Native Shell") {
                Text("Bridge mode: \(appState.bridgeMode)")
                Text("Set NEXUS_CORE_LIBRARY to a local libnexus_ffi.dylib to load real workspace data through Rust Core during development.")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(20)
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
    static let badge = Color(nsColor: NSColor.controlBackgroundColor)
    static let border = Color.black.opacity(0.08)
    static let accent = Color.blue
    static let success = Color.green
    static let warning = Color.orange
    static let danger = Color.red
}
