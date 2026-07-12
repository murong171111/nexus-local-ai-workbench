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

enum FeatureWorkspaceSessionChangePolicy {
    static func canWrite(hasDraft: Bool, confirmed: Bool, isBusy: Bool) -> Bool {
        hasDraft && confirmed && !isBusy
    }
}

enum FeatureWorkspacePresentation {
    enum Phase: Equatable {
        case editing
        case waiting
        case proposalReady
        case proposalInvalid
        case confirmed
    }

    static func phase(
        hasConfirmedFeatures: Bool,
        didHandoff: Bool,
        review: FeatureProposalReview?
    ) -> Phase {
        if didHandoff { return .waiting }
        if review?.diff != nil { return .proposalReady }
        if let error = review?.error,
           !error.contains("feature proposal draft is missing") {
            return .proposalInvalid
        }
        if hasConfirmedFeatures { return .confirmed }
        return didHandoff ? .waiting : .editing
    }
}

enum FeatureWorkspaceEvidencePresentation {
    static func lines(
        evidence: FeatureEvidence,
        evaluation: FeatureCompletionEvaluation?
    ) -> [String] {
        var lines = evaluation?.reasons.map { "判定: \($0)" } ?? []
        append("任务", evidence.linkedTaskIDs, to: &lines)
        append("未完成任务", evidence.incompleteTaskIDs, to: &lines)
        append("变更", evidence.relatedChangeIDs, to: &lines)
        append("测试", evidence.requiredTestIDs, to: &lines)
        append("失败或缺失测试", evidence.failedOrMissingTestIDs, to: &lines)
        append("正式 SQL", evidence.formalSQLPaths, to: &lines)
        append("回滚 SQL", evidence.rollbackSQLPaths, to: &lines)
        append("文档", evidence.documentationPaths, to: &lines)
        append("阻塞", evidence.blockers, to: &lines)
        append("读取错误", evidence.readErrors, to: &lines)
        if let date = evidence.latestRelatedChangeAt {
            lines.append("最近相关变更: \(ISO8601DateFormatter().string(from: date))")
        }
        if let date = evidence.latestTestAt {
            lines.append("最近测试: \(ISO8601DateFormatter().string(from: date))")
        }
        return lines
    }

    private static func append(_ label: String, _ values: [String], to lines: inout [String]) {
        if !values.isEmpty { lines.append("\(label): \(values.joined(separator: ", "))") }
    }
}

enum FeatureFactsPresentation {
    static func linkedTaskLabel(_ count: Int) -> String {
        "关联任务 \(count)"
    }
}

struct FeatureFactsRow: View {
    let feature: WorkspaceFeature
    let workspace: WorkspaceSummary
    var compact = false

    private var linkedTaskCount: Int {
        workspace.tasks.filter {
            NativeWorkspaceTaskParser.featureAttribution(in: $0.detail).id == feature.id
        }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(feature.id)
                    .font(.caption.monospaced().weight(.semibold))
                Text(feature.title)
                    .lineLimit(compact ? 1 : 2)
                Spacer()
                Text(feature.status.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text("\(feature.verification.rawValue) · \(FeatureFactsPresentation.linkedTaskLabel(linkedTaskCount))")
                .font(.caption)
                .foregroundStyle(.secondary)
            if feature.evidenceStale {
                Label("证据待复核", systemImage: "exclamationmark.triangle")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }
}

struct FeatureFactsList: View {
    let features: [WorkspaceFeature]
    let workspace: WorkspaceSummary
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(features) { feature in
                FeatureFactsRow(feature: feature, workspace: workspace, compact: compact)
                if feature.id != features.last?.id { Divider() }
            }
        }
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
    @Environment(\.scenePhase) private var scenePhase
    let workspace: WorkspaceSummary
    let demandInputFocused: FocusState<Bool>.Binding

    @State private var draft = DemandInputDraft.empty
    @State private var isLoading = false
    @State private var isImportingMaterials = false
    @State private var isAttaching = false
    @State private var pendingMaterials: [URL] = []
    @State private var autosavePolicy = FeatureWorkspaceAutosavePolicy()
    @State private var isAddingFeature = false
    @State private var editingFeature: WorkspaceFeature?
    @State private var isReviewingLegacyMigration = false
    @State private var sessionCodexSummary = ""
    @State private var isSessionChangeConfirmed = false
    @State private var expandedEvidenceFeatureIDs = Set<String>()
    @State private var pendingCompletionReversal: WorkspaceFeature?
    @State private var completionReversalReason = ""
    @State private var isDemandExpanded = false
    @State private var isAwaitingCodex = false
    @State private var refreshTask: Task<Void, Never>?
    @State private var handoffTask: Task<Void, Never>?

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
            HStack {
                Text("需求与功能点 / Demand & Features")
                    .font(.headline)
                Spacer()
                Text(presentationLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            VStack(alignment: .leading, spacing: 12) {
                if showsDemandEditor {
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
                        startCodexHandoff()
                    } label: {
                        Label("交给 Codex 梳理功能点", systemImage: "sparkles")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isLoading || isSaving)
                    if canOfferLegacyMigration {
                        legacyMigrationButton
                    }
                } else {
                    demandSummary
                }

                if presentationPhase == .waiting {
                    waitingForCodex
                }
                if showsFeatureList {
                    Divider()
                    featureList
                }
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
            await refreshWorkspaceState(for: loadingWorkspace)
        }
        .onChange(of: draft) { _ in
            scheduleAutosave()
        }
        .onChange(of: workspace.id) { _ in
            autosavePolicy.cancel()
            refreshTask?.cancel()
            handoffTask?.cancel()
            isDemandExpanded = false
            isAwaitingCodex = false
        }
        .onChange(of: scenePhase) { phase in
            guard phase == .active else { return }
            refreshWorkspaceAfterCodex()
        }
        .onDisappear {
            autosavePolicy.cancel()
            refreshTask?.cancel()
            handoffTask?.cancel()
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
        .alert(
            "填写撤销完成原因",
            isPresented: Binding(
                get: { pendingCompletionReversal != nil },
                set: { if !$0 { pendingCompletionReversal = nil } }
            )
        ) {
            TextField("原因", text: $completionReversalReason)
            Button("继续") {
                guard let feature = pendingCompletionReversal else { return }
                let reason = completionReversalReason.trimmingCharacters(in: .whitespacesAndNewlines)
                pendingCompletionReversal = nil
                appState.requestFeatureWrite(
                    .revertCompletion(id: feature.id, reason: reason),
                    in: workspace
                )
            }
            .disabled(completionReversalReason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("取消", role: .cancel) { pendingCompletionReversal = nil }
        } message: {
            Text("撤销后功能点进入 verifying，并清除原完成时间与完成人。")
        }
        .sheet(isPresented: $isAddingFeature) {
            FeatureEditView(featureID: presentationPhase == .proposalReady ? nextDraftID : nextFeatureID) { feature in
                if presentationPhase == .proposalReady {
                    appState.addFeatureProposalItem(feature, in: workspace)
                } else {
                    appState.requestFeatureWrite(.add(feature), in: workspace)
                }
            }
        }
        .sheet(item: $editingFeature) { feature in
            FeatureEditView(featureID: feature.id, feature: feature) { replacement in
                appState.requestFeatureWrite(
                    .update(expected: feature, replacement: replacement),
                    in: workspace
                )
            }
        }
        .sheet(isPresented: $isReviewingLegacyMigration) {
            if let proposal = appState.legacyFeatureMigrationProposalsByWorkspace[workspace.id] {
                LegacyFeatureMigrationReviewSheet(workspace: workspace, proposal: proposal)
                    .environmentObject(appState)
            }
        }
        .confirmationDialog(
            "确认功能点并写入 \(workspace.name) 的 FEATURES.md",
            isPresented: Binding(
                get: { appState.pendingFeatureProposalMerge(for: workspace) != nil },
                set: { if !$0 { appState.cancelPendingFeatureProposalMerge() } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认写入并进入开发") {
                guard let operation = appState.takePendingFeatureProposalMerge() else { return }
                Task { await appState.writeConfirmedFeatureProposal(operation) }
            }
            Button("取消", role: .cancel) {
                appState.cancelPendingFeatureProposalMerge()
            }
        }
        .confirmationDialog(
            featureConfirmationTitle,
            isPresented: Binding(
                get: { appState.pendingFeatureWrite(for: workspace) != nil },
                set: { if !$0 { appState.cancelPendingFeatureWrite() } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认写入 FEATURES.md") {
                guard let operation = appState.takePendingFeatureWrite() else { return }
                Task { await appState.writeConfirmedFeature(operation) }
            }
            Button("取消", role: .cancel) {
                appState.cancelPendingFeatureWrite()
            }
        }
        .confirmationDialog(
            "确认写入 \(workspace.name) changes.md",
            isPresented: Binding(
                get: { appState.pendingSessionChangeWrite(for: workspace) != nil },
                set: { if !$0 { appState.cancelPendingSessionChangeWrite() } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认写入 changes.md") {
                guard let operation = appState.takePendingSessionChangeWrite() else { return }
                Task {
                    await appState.writeConfirmedSessionChange(operation)
                    if appState.sessionChangeDraftsByWorkspace[workspace.id] == nil {
                        isSessionChangeConfirmed = false
                    }
                }
            }
            Button("取消", role: .cancel) {
                appState.cancelPendingSessionChangeWrite()
            }
        }
    }

    private var presentationPhase: FeatureWorkspacePresentation.Phase {
        FeatureWorkspacePresentation.phase(
            hasConfirmedFeatures: !features.isEmpty,
            didHandoff: isAwaitingCodex,
            review: featureProposalReview
        )
    }

    private var presentationLabel: String {
        switch presentationPhase {
        case .editing: return "填写需求"
        case .waiting: return "等待 Codex"
        case .proposalReady: return "待审阅"
        case .proposalInvalid: return "提案需修正"
        case .confirmed: return "功能点已确认"
        }
    }

    private var showsDemandEditor: Bool {
        presentationPhase == .editing || isDemandExpanded
    }

    private var showsFeatureList: Bool {
        switch presentationPhase {
        case .proposalReady, .proposalInvalid, .confirmed: return true
        case .editing, .waiting: return false
        }
    }

    private var demandSummary: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "text.quote")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("原始需求")
                    .font(.caption.weight(.semibold))
                Text(draft.requirement.trimmingCharacters(in: .whitespacesAndNewlines))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Spacer()
            Button {
                isDemandExpanded = true
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("修改原始需求")
        }
        .padding(.vertical, 4)
    }

    private var waitingForCodex: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("等待 Codex 梳理功能点", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
            Text("在 Codex 中完成需求梳理后返回 Nexus，应用会自动检查 FEATURES.draft.md。")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                refreshWorkspaceAfterCodex()
            } label: {
                Label("检查生成结果", systemImage: "arrow.clockwise")
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(appState.featureProposalLoadingWorkspaceID == workspace.id)
        }
        .padding(.vertical, 8)
    }

    private func startCodexHandoff() {
        autosavePolicy.cancel()
        handoffTask?.cancel()
        let target = workspace
        let capturedDraft = draft
        handoffTask = Task {
            let result = await appState.saveDemandInputDraft(capturedDraft, in: target)
            guard result.succeeded else { return }
            let didOpen = await appState.openFeatureIntakeInCodex(for: target)
            guard !Task.isCancelled, appState.selectedWorkspaceID == target.id else { return }
            if didOpen {
                isDemandExpanded = false
                isAwaitingCodex = true
            }
        }
    }

    private func refreshWorkspaceAfterCodex() {
        refreshTask?.cancel()
        let target = workspace
        refreshTask = Task { await refreshWorkspaceState(for: target) }
    }

    private func refreshWorkspaceState(for target: WorkspaceSummary) async {
        await appState.refreshFeatures(for: target)
        await appState.refreshFeatureProposal(for: target)
        guard !Task.isCancelled, appState.selectedWorkspaceID == target.id else { return }
        isAwaitingCodex = false
    }

    private var legacyMigrationButton: some View {
        Button {
            Task {
                await appState.loadLegacyFeatureMigrationProposal(for: workspace)
                if appState.legacyFeatureMigrationProposalsByWorkspace[workspace.id] != nil {
                    isReviewingLegacyMigration = true
                }
            }
        } label: {
            Label("从现有文档生成建议", systemImage: "doc.text.magnifyingglass")
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .disabled(appState.legacyFeatureMigrationLoadingWorkspaceID == workspace.id)
    }

    private var featureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            switch presentationPhase {
            case .proposalReady:
                inlineProposalReview
            case .proposalInvalid:
                invalidProposalReview
            case .confirmed:
                confirmedFeatureList
            case .editing, .waiting:
                EmptyView()
            }
        }
    }

    private var inlineProposalReview: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("审阅功能点")
                        .font(.headline)
                    if let counts = featureProposalCounts {
                        Text("新增 \(counts.add) · 修改 \(counts.change) · 取消 \(counts.cancel)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Button {
                    refreshWorkspaceAfterCodex()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help("刷新功能提案")
                Button {
                    isAddingFeature = true
                } label: {
                    Label("新增功能点", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            }

            if actionableProposalItems.isEmpty {
                Text("提案没有需要写入的变化。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(actionableProposalItems) { item in
                    VStack(alignment: .trailing, spacing: 4) {
                        FeatureProposalItemEditor(
                            item: item,
                            selected: proposalSelectedBinding(item),
                            replacement: proposalReplacementBinding(item)
                        )
                        if isAdditionalProposalItem(item.id) {
                            Button(role: .destructive) {
                                appState.removeFeatureProposalItem(itemID: item.id, in: workspace)
                            } label: {
                                Label("移除", systemImage: "trash")
                            }
                            .buttonStyle(.borderless)
                            .controlSize(.small)
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Button {
                    appState.requestFeatureProposalMerge(in: workspace)
                } label: {
                    Label("确认功能点", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canRequestProposalMerge)
            }
        }
    }

    private var invalidProposalReview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("功能提案格式错误", systemImage: "exclamationmark.triangle")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(featureProposalReview?.error ?? "Nexus 无法读取 FEATURES.draft.md。")
                .font(.caption)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button {
                    startCodexHandoff()
                } label: {
                    Label("重新让 Codex 梳理", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(isSaving)
            }
        }
    }

    private var confirmedFeatureList: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("已确认功能点")
                    .font(.headline)
                Spacer()
                Button {
                    isAddingFeature = true
                } label: {
                    Label("新增", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(appState.featureWriteWorkspaceID != nil)
            }
            ForEach(features) { feature in
                featureRow(feature)
                if feature.id != features.last?.id { Divider() }
            }
            ForEach(taskFeatureWarnings, id: \.self) { warning in
                Label(warning, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private var sessionChangeReview: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("本次变化 / Session Changes")
                    .font(.headline)
                Spacer()
                if sessionChangeDraft == nil {
                    Button {
                        isSessionChangeConfirmed = false
                        Task {
                            _ = await appState.generateSessionChangeDraft(
                                in: workspace,
                                codexSummary: sessionCodexSummary.isEmpty ? nil : sessionCodexSummary
                            )
                        }
                    } label: {
                        Label("生成本次变化摘要", systemImage: "doc.text.magnifyingglass")
                    }
                    .buttonStyle(.bordered)
                    .disabled(isSessionChangeBusy)
                }
            }

            TextField("可选 Codex 摘要", text: $sessionCodexSummary)
                .textFieldStyle(.roundedBorder)
                .disabled(isSessionChangeBusy || sessionChangeDraft != nil)

            if isSessionChangeBusy {
                ProgressView()
                    .controlSize(.small)
            }

            if let draft = sessionChangeDraft {
                Label(
                    draft.notice,
                    systemImage: draft.canClaimPriorDiff ? "info.circle" : "exclamationmark.triangle"
                )
                .font(.caption)
                .foregroundStyle(draft.canClaimPriorDiff ? Color.secondary : Color.orange)

                ScrollView {
                    Text(draft.markdown)
                        .font(.caption.monospaced())
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 180)

                Toggle("我已审阅并确认写入 changes.md", isOn: $isSessionChangeConfirmed)
                    .toggleStyle(.checkbox)

                HStack {
                    Spacer()
                    Button {
                        Task { await appState.prepareSessionChangeWrite(draft, in: workspace) }
                    } label: {
                        Label("写入 changes.md", systemImage: "square.and.arrow.down")
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!FeatureWorkspaceSessionChangePolicy.canWrite(
                        hasDraft: true,
                        confirmed: isSessionChangeConfirmed,
                        isBusy: isSessionChangeBusy
                    ))
                }
            }
        }
    }

    private func featureRow(_ feature: WorkspaceFeature) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            FeatureFactsRow(feature: feature, workspace: workspace)
            HStack(spacing: 8) {
                Spacer()
                Button {
                    editingFeature = feature
                } label: {
                    Image(systemName: "pencil")
                }
                .help("编辑功能点")
                featureStateButton(feature)
                if feature.status != .cancelled {
                    Button(role: .destructive) {
                        appState.requestFeatureWrite(
                            .cancel(id: feature.id, reason: "Cancelled in Nexus"),
                            in: workspace
                        )
                    } label: {
                        Image(systemName: "xmark.circle")
                    }
                    .help("取消功能点")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            if !feature.evidenceStale, let evaluation = featureEvaluation(feature.id) {
                Text(evaluationLabel(evaluation.decision))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if let evidence = featureEvidence(feature.id) {
                DisclosureGroup(
                    "证据详情",
                    isExpanded: evidenceExpansionBinding(feature.id)
                ) {
                    ForEach(
                        FeatureWorkspaceEvidencePresentation.lines(
                            evidence: evidence,
                            evaluation: featureEvaluation(feature.id)
                        ),
                        id: \.self
                    ) { line in
                        Text(line)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                }
                .font(.caption)
            }
        }
    }

    @ViewBuilder
    private func featureStateButton(_ feature: WorkspaceFeature) -> some View {
        if feature.status == .done {
            Button {
                completionReversalReason = ""
                pendingCompletionReversal = feature
            } label: {
                Label("撤销完成", systemImage: "arrow.uturn.backward")
            }
        } else if feature.status != .cancelled {
            Button {
                appState.requestFeatureWrite(
                    .setStatus(id: feature.id, status: .done, completionNote: "Manual completion"),
                    in: workspace
                )
            } label: {
                Label("手动完成", systemImage: "checkmark")
            }
        }
    }

    private var features: [WorkspaceFeature] {
        appState.featuresByWorkspace[workspace.id]?.features ?? []
    }

    private func featureEvidence(_ featureID: String) -> FeatureEvidence? {
        appState.featureEvidenceByWorkspace[workspace.id]?[featureID]
    }

    private func featureEvaluation(_ featureID: String) -> FeatureCompletionEvaluation? {
        appState.featureCompletionEvaluationsByWorkspace[workspace.id]?[featureID]
    }

    private func evidenceExpansionBinding(_ featureID: String) -> Binding<Bool> {
        Binding(
            get: { expandedEvidenceFeatureIDs.contains(featureID) },
            set: { expanded in
                if expanded { expandedEvidenceFeatureIDs.insert(featureID) }
                else { expandedEvidenceFeatureIDs.remove(featureID) }
            }
        )
    }

    private func evaluationLabel(_ decision: FeatureCompletionDecision) -> String {
        switch decision {
        case .autoComplete: "证据满足，已自动完成"
        case .markEvidenceStale: "证据待复核"
        case .requiresManualCompletion: "需要手动完成"
        case .startProgress: "已发现进展证据"
        case .keepVerifying: "继续验证"
        case .noChange: "暂无可归属的新证据"
        }
    }

    private var sessionChangeDraft: SessionChangeDraft? {
        appState.sessionChangeDraftsByWorkspace[workspace.id]
    }

    private var isSessionChangeBusy: Bool {
        appState.sessionChangeLoadingWorkspaceID == workspace.id
            || appState.sessionChangeWriteWorkspaceID == workspace.id
    }

    private var featureProposalReview: FeatureProposalReview? {
        appState.featureProposalReview(for: workspace)
    }

    private var proposalItems: [FeatureProposalItem] {
        appState.featureProposalItems(for: workspace)
    }

    private var actionableProposalItems: [FeatureProposalItem] {
        proposalItems.filter { $0.kind != .unchanged }
    }

    private var featureProposalCounts: (add: Int, change: Int, cancel: Int)? {
        guard featureProposalReview?.diff != nil else { return nil }
        return (
            proposalItems.filter { $0.kind == .add }.count,
            proposalItems.filter { $0.kind == .change }.count,
            proposalItems.filter { $0.kind == .cancel }.count
        )
    }

    private var canRequestProposalMerge: Bool {
        guard featureProposalReview?.canConfirm == true else { return false }
        let selected = appState.featureProposalSelectedItemIDsByWorkspace[workspace.id] ?? []
        return !selected.isEmpty && appState.featureProposalMergeWorkspaceID == nil
    }

    private func proposalSelectedBinding(_ item: FeatureProposalItem) -> Binding<Bool> {
        Binding(
            get: {
                (appState.featureProposalSelectedItemIDsByWorkspace[workspace.id] ?? [])
                    .contains(item.id)
            },
            set: { selected in
                appState.updateFeatureProposalItem(
                    itemID: item.id,
                    selected: selected,
                    replacement: appState.featureProposalReplacementsByWorkspace[workspace.id]?[item.id],
                    in: workspace
                )
            }
        )
    }

    private func proposalReplacementBinding(_ item: FeatureProposalItem) -> Binding<WorkspaceFeature?> {
        Binding(
            get: {
                appState.featureProposalReplacementsByWorkspace[workspace.id]?[item.id]
                    ?? item.proposed
            },
            set: { replacement in
                appState.updateFeatureProposalItem(
                    itemID: item.id,
                    selected: (appState.featureProposalSelectedItemIDsByWorkspace[workspace.id] ?? [])
                        .contains(item.id),
                    replacement: replacement,
                    in: workspace
                )
            }
        )
    }

    private func isAdditionalProposalItem(_ itemID: String) -> Bool {
        appState.featureProposalAdditionalFeaturesByWorkspace[workspace.id]?
            .contains(where: { $0.id == itemID }) == true
    }

    private var nextDraftID: String {
        let next = proposalItems
            .compactMap { item -> Int? in
                guard item.id.hasPrefix("DRAFT-") else { return nil }
                return Int(item.id.dropFirst("DRAFT-".count))
            }
            .max()
            .map { $0 + 1 } ?? 1
        return String(format: "DRAFT-%03d", next)
    }

    private var nextFeatureID: String {
        let next = (features.compactMap { Int($0.id.dropFirst(2)) }.max() ?? 0) + 1
        return String(format: "F-%03d", next)
    }

    private var canOfferLegacyMigration: Bool {
        !workspace.usesFeatureCenteredWorkflow
            && appState.featureRevisionsByWorkspace[workspace.id] == .missing
    }

    private var taskFeatureWarnings: [String] {
        workspace.tasks.compactMap { task in
            NativeWorkspaceTaskParser.featureAttribution(in: task.detail).warning.map {
                "\(task.title): \($0)"
            }
        }
    }

    private var featureConfirmationTitle: String {
        guard let mutation = appState.pendingFeatureWrite(for: workspace)?.mutation else {
            return "确认 \(workspace.name) 功能点变更"
        }
        switch mutation {
        case .add(let feature): return "确认在 \(workspace.name) 新增 \(feature.id)"
        case .update(let expected, _): return "确认在 \(workspace.name) 修改 \(expected.id)"
        case .setStatus(let id, let status, _):
            return "确认在 \(workspace.name) 将 \(id) 设为 \(status.rawValue)"
        case .revertCompletion(let id, _):
            return "确认在 \(workspace.name) 撤销 \(id) 完成状态"
        case .cancel(let id, _): return "确认在 \(workspace.name) 取消 \(id)"
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

private struct LegacyFeatureMigrationReviewSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let workspace: WorkspaceSummary
    let proposal: LegacyFeatureMigrationProposal

    @State private var selectedItemIDs: Set<String>
    @State private var isConfirmed = false

    init(workspace: WorkspaceSummary, proposal: LegacyFeatureMigrationProposal) {
        self.workspace = workspace
        self.proposal = proposal
        let items = FeatureProposalDiff.resolve(
            confirmed: .empty,
            draft: FeatureDocument(preamble: ["# Features", ""], features: proposal.features)
        ).actionableItems
        _selectedItemIDs = State(initialValue: Set(items.map(\.id)))
    }

    private var items: [FeatureProposalItem] {
        FeatureProposalDiff.resolve(
            confirmed: .empty,
            draft: FeatureDocument(preamble: ["# Features", ""], features: proposal.features)
        ).actionableItems
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("从现有文档生成建议")
                    .font(.title3.weight(.semibold))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.borderless)
                .help("关闭")
            }

            Text(proposal.sourcePaths.joined(separator: " · "))
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(2)

            List(items) { item in
                Toggle(
                    isOn: Binding(
                        get: { selectedItemIDs.contains(item.id) },
                        set: { selected in
                            if selected { selectedItemIDs.insert(item.id) }
                            else { selectedItemIDs.remove(item.id) }
                        }
                    )
                ) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.proposed?.title ?? item.id)
                        Text(item.proposed?.sources.joined(separator: ", ") ?? "")
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .toggleStyle(.checkbox)
            }
            .frame(minHeight: 260)

            Toggle("确认创建 FEATURES.md；现有文档保持不变", isOn: $isConfirmed)
                .toggleStyle(.checkbox)

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button {
                    Task {
                        if await appState.applyLegacyFeatureMigration(
                            for: workspace,
                            selectedItemIDs: selectedItemIDs,
                            confirmed: isConfirmed
                        ) {
                            dismiss()
                        }
                    }
                } label: {
                    Label("创建功能点", systemImage: "checkmark")
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    !isConfirmed
                        || selectedItemIDs.isEmpty
                        || appState.legacyFeatureMigrationLoadingWorkspaceID == workspace.id
                )
            }
        }
        .padding(16)
        .frame(minWidth: 620, minHeight: 460)
    }
}
