import SwiftUI
import UniformTypeIdentifiers

enum FeatureWorkspaceDraftPolicy {
    static func refreshedDraft(
        current: DemandInputDraft,
        snapshot: DemandInputSnapshot?
    ) -> DemandInputDraft {
        snapshot?.draft ?? current
    }
}

struct FeatureWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary
    let demandInputFocused: FocusState<Bool>.Binding

    @State private var draft = DemandInputDraft.empty
    @State private var isLoading = false
    @State private var isImportingMaterials = false
    @State private var pendingMaterials: [URL] = []
    @State private var autosaveTask: Task<Void, Never>?

    private var isSaving: Bool {
        appState.demandInputSavingWorkspaceID == workspace.id
    }

    private var saveStatus: DemandInputSaveStatus {
        appState.demandInputSaveStatus(for: workspace)
    }

    private var hasSaveFailure: Bool {
        if case .failed = saveStatus { return true }
        return false
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("需求输入 / Demand")
                .font(.headline)
            VStack(alignment: .leading, spacing: 12) {
                TextEditor(text: $draft.requirement)
                    .font(.body)
                    .frame(minHeight: 180, maxHeight: 260)
                    .padding(6)
                    .background(Color.primary.opacity(0.03))
                    .overlay {
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(Color.secondary.opacity(0.35))
                    }
                    .focused(demandInputFocused)
                    .accessibilityLabel("需求描述")

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("链接")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button {
                            draft.links.append("")
                        } label: {
                            Image(systemName: "plus")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("添加链接")
                    }

                    ForEach(Array(draft.links.indices), id: \.self) { index in
                        HStack(spacing: 8) {
                            TextField("https://", text: $draft.links[index])
                                .textFieldStyle(.roundedBorder)
                            Button {
                                draft.links.remove(at: index)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                            .help("移除链接")
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("材料")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Button {
                            isImportingMaterials = true
                        } label: {
                            Image(systemName: "paperclip")
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                        .help("选择材料")
                    }

                    if draft.attachments.isEmpty {
                        Text("暂无确认材料")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(draft.attachments, id: \.self) { attachment in
                            HStack(spacing: 8) {
                                Image(systemName: "doc")
                                    .foregroundStyle(.secondary)
                                Text(attachment)
                                    .font(.caption.monospaced())
                                    .lineLimit(1)
                                Spacer()
                            }
                        }
                    }
                }

                HStack(spacing: 8) {
                    Image(systemName: saveStatus == .saving ? "arrow.triangle.2.circlepath" : (hasSaveFailure ? "exclamationmark.triangle" : "checkmark.circle"))
                        .foregroundStyle(hasSaveFailure ? Color.orange : (isSaving ? Color.orange : Color.green))
                    Text(saveStatusText)
                        .font(.caption)
                        .foregroundStyle(hasSaveFailure ? Color.orange : .secondary)
                    Spacer()
                }
                if case .failed(let message) = saveStatus {
                    Text(message)
                        .font(.caption)
                        .foregroundStyle(Color.orange)
                        .textSelection(.enabled)
                }

                Button {
                    autosaveTask?.cancel()
                    Task {
                        let result = await appState.saveDemandInputDraft(draft, in: workspace)
                        guard result.succeeded else { return }
                        await appState.openFeatureIntakeInCodex(for: workspace)
                    }
                } label: {
                    Label("生成上下文并打开 Codex", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isSaving)
            }
            .padding(12)
        }
        .padding(12)
        .background(Color.primary.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .task(id: workspace.id) {
            isLoading = true
            await appState.loadDemandInput(for: workspace)
            draft = FeatureWorkspaceDraftPolicy.refreshedDraft(
                current: draft,
                snapshot: appState.demandInputSnapshot(for: workspace)
            )
            isLoading = false
        }
        .onChange(of: draft) { _ in
            scheduleAutosave()
        }
        .fileImporter(
            isPresented: $isImportingMaterials,
            allowedContentTypes: [UTType.image, UTType.pdf, UTType.plainText, UTType.text],
            allowsMultipleSelection: true
        ) { result in
            switch result {
            case .success(let urls):
                pendingMaterials = urls
            case .failure(let error):
                appState.lastError = error.localizedDescription
            }
        }
        .confirmationDialog(
            "确认复制材料",
            isPresented: Binding(
                get: { !pendingMaterials.isEmpty },
                set: { if !$0 { pendingMaterials = [] } }
            ),
            titleVisibility: Visibility.visible
        ) {
            Button("复制 \(pendingMaterials.count) 个材料") {
                let urls = pendingMaterials
                let liveDraft = draft
                pendingMaterials = []
                autosaveTask?.cancel()
                autosaveTask = nil
                Task {
                    guard await appState.attachDemandMaterials(
                        urls,
                        liveDraft: liveDraft,
                        to: workspace,
                        confirmed: true
                    ) != nil else {
                        return
                    }
                    draft = FeatureWorkspaceDraftPolicy.refreshedDraft(
                        current: liveDraft,
                        snapshot: appState.demandInputSnapshot(for: workspace)
                    )
                }
            }
            Button("取消", role: .cancel) {
                pendingMaterials = []
            }
        }
    }

    private func scheduleAutosave() {
        guard !isLoading else { return }
        autosaveTask?.cancel()
        autosaveTask = Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            _ = await appState.saveDemandInputDraft(draft, in: workspace)
        }
    }

    private var saveStatusText: String {
        if isLoading { return "正在加载" }
        switch saveStatus {
        case .saving:
            return "正在保存"
        case .failed:
            return "保存失败"
        case .idle, .saved:
            return "已自动保存"
        }
    }
}
