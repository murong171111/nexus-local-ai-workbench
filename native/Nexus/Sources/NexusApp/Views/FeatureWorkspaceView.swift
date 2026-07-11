import SwiftUI
import UniformTypeIdentifiers

enum FeatureWorkspaceDraftPolicy {
    static func shouldScheduleAutosave(isLoading: Bool, isAttaching _: Bool) -> Bool {
        !isLoading
    }

    static func refreshedDraft(
        current: DemandInputDraft,
        snapshot: DemandInputSnapshot?
    ) -> DemandInputDraft {
        snapshot?.draft ?? current
    }

    static func mergingCopiedAttachments(
        _ paths: [String],
        into current: DemandInputDraft
    ) -> DemandInputDraft {
        var merged = current
        for path in paths where !merged.attachments.contains(path) {
            merged.attachments.append(path)
        }
        return merged
    }
}

@MainActor
final class FeatureWorkspaceAutosavePolicy {
    private let delayNanoseconds: UInt64
    private var expectedProgrammaticDraft: DemandInputDraft?
    private var task: Task<Void, Never>?

    init(delayNanoseconds: UInt64 = 600_000_000) {
        self.delayNanoseconds = delayNanoseconds
    }

    func prepareProgrammaticUpdate(_ draft: DemandInputDraft) {
        cancel()
        expectedProgrammaticDraft = draft
    }

    func draftChanged(
        _ draft: DemandInputDraft,
        workspaceID: WorkspaceSummary.ID,
        save: @escaping @MainActor (WorkspaceSummary.ID, DemandInputDraft) async -> Void
    ) {
        if let expectedProgrammaticDraft {
            self.expectedProgrammaticDraft = nil
            if draft == expectedProgrammaticDraft { return }
        }

        cancel()
        let capturedDraft = draft
        let capturedWorkspaceID = workspaceID
        let capturedDelay = delayNanoseconds
        task = Task {
            try? await Task.sleep(nanoseconds: capturedDelay)
            guard !Task.isCancelled else { return }
            await save(capturedWorkspaceID, capturedDraft)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

struct FeatureWorkspaceView: View {
    @EnvironmentObject private var appState: AppState
    let workspace: WorkspaceSummary
    let demandInputFocused: FocusState<Bool>.Binding

    @State private var draft = DemandInputDraft.empty
    @State private var isLoading = false
    @State private var isImportingMaterials = false
    @State private var isAttaching = false
    @State private var pendingMaterials: [URL] = []
    @State private var autosavePolicy = FeatureWorkspaceAutosavePolicy()

    private var isSaving: Bool {
        appState.isDemandInputSaveActive(for: workspace)
            || appState.isDemandAttachmentOperationActive(for: workspace)
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
                    Image(systemName: isSaving ? "arrow.triangle.2.circlepath" : (hasSaveFailure ? "exclamationmark.triangle" : "checkmark.circle"))
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
                    autosavePolicy.cancel()
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
            autosavePolicy.cancel()
            let loadingWorkspace = workspace
            isLoading = true
            await appState.loadDemandInput(for: loadingWorkspace)
            guard !Task.isCancelled, workspace.id == loadingWorkspace.id else { return }
            let loadedDraft = FeatureWorkspaceDraftPolicy.refreshedDraft(
                current: draft,
                snapshot: appState.demandInputSnapshot(for: loadingWorkspace)
            )
            autosavePolicy.prepareProgrammaticUpdate(loadedDraft)
            draft = loadedDraft
            isLoading = false
        }
        .onChange(of: draft) { _ in
            scheduleAutosave()
        }
        .onChange(of: workspace.id) { _ in
            autosavePolicy.cancel()
        }
        .onDisappear {
            autosavePolicy.cancel()
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
                autosavePolicy.cancel()
                isAttaching = true
                Task {
                    defer { isAttaching = false }
                    guard let response = await appState.attachDemandMaterials(
                        urls,
                        liveDraft: liveDraft,
                        currentDraft: { draft },
                        to: workspace,
                        confirmed: true
                    ) else {
                        return
                    }
                    let mergedDraft = FeatureWorkspaceDraftPolicy.mergingCopiedAttachments(
                        response.copiedRelativePaths,
                        into: draft
                    )
                    draft = mergedDraft
                }
            }
            Button("取消", role: .cancel) {
                pendingMaterials = []
            }
        }
    }

    private func scheduleAutosave() {
        guard FeatureWorkspaceDraftPolicy.shouldScheduleAutosave(
            isLoading: isLoading,
            isAttaching: isAttaching
        ) else { return }
        let capturedWorkspace = workspace
        autosavePolicy.draftChanged(draft, workspaceID: capturedWorkspace.id) { _, capturedDraft in
            _ = await appState.saveDemandInputDraft(capturedDraft, in: capturedWorkspace)
        }
    }

    private var saveStatusText: String {
        if isLoading { return "正在加载" }
        if isSaving { return "正在保存" }
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
