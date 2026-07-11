import SwiftUI

struct FeatureProposalReviewView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let workspace: WorkspaceSummary

    var body: some View {
        NavigationStack {
            Group {
                if let error = review?.error {
                    VStack(spacing: 10) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.title)
                            .foregroundStyle(.orange)
                        Text("无法解析功能提案")
                            .font(.headline)
                        Text(error)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                    }
                    .padding(24)
                } else if let diff = review?.diff {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 18) {
                            proposalSection("新增", kind: .add, items: diff.items)
                            proposalSection("变更", kind: .change, items: diff.items)
                            proposalSection("取消", kind: .cancel, items: diff.items)
                        }
                        .padding(16)
                    }
                } else {
                    ProgressView()
                }
            }
            .navigationTitle("功能提案 / \(workspace.name)")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("关闭") { dismiss() }
                        .disabled(appState.featureProposalMergeWorkspaceID != nil)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button {
                        appState.requestFeatureProposalMerge(in: workspace)
                    } label: {
                        Label("确认选中项", systemImage: "checkmark")
                    }
                    .disabled(!canRequestMerge)
                }
            }
        }
        .frame(minWidth: 620, minHeight: 520)
        .interactiveDismissDisabled(appState.featureProposalMergeWorkspaceID != nil)
        .confirmationDialog(
            "确认合并到 \(workspace.name) 的 FEATURES.md",
            isPresented: Binding(
                get: { appState.pendingFeatureProposalMerge(for: workspace) != nil },
                set: { if !$0 { appState.cancelPendingFeatureProposalMerge() } }
            ),
            titleVisibility: .visible
        ) {
            Button("确认合并") {
                guard let operation = appState.takePendingFeatureProposalMerge() else { return }
                Task {
                    await appState.writeConfirmedFeatureProposal(operation)
                    if appState.featureProposalReview(for: workspace) == nil { dismiss() }
                }
            }
            Button("取消", role: .cancel) {
                appState.cancelPendingFeatureProposalMerge()
            }
        }
    }

    @ViewBuilder
    private func proposalSection(
        _ title: String,
        kind: FeatureProposalKind,
        items: [FeatureProposalItem]
    ) -> some View {
        let grouped = items.filter { $0.kind == kind }
        if !grouped.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("\(title) · \(grouped.count)")
                    .font(.headline)
                ForEach(grouped) { item in
                    FeatureProposalItemEditor(
                        item: item,
                        selected: selectedBinding(item),
                        replacement: replacementBinding(item)
                    )
                }
            }
        }
    }

    private var review: FeatureProposalReview? {
        appState.featureProposalReview(for: workspace)
    }

    private var canRequestMerge: Bool {
        review?.canConfirm == true
            && !(appState.featureProposalSelectedItemIDsByWorkspace[workspace.id] ?? []).isEmpty
            && appState.featureProposalMergeWorkspaceID == nil
    }

    private func selectedBinding(_ item: FeatureProposalItem) -> Binding<Bool> {
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

    private func replacementBinding(_ item: FeatureProposalItem) -> Binding<WorkspaceFeature?> {
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
}

private struct FeatureProposalItemEditor: View {
    let item: FeatureProposalItem
    @Binding var selected: Bool
    @Binding var replacement: WorkspaceFeature?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Toggle("", isOn: $selected)
                    .labelsHidden()
                    .toggleStyle(.checkbox)
                Text(item.assignedFeatureID ?? item.id)
                    .font(.caption.monospaced().weight(.semibold))
                Text(item.kind.rawValue)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            if item.kind == .cancel {
                Text(item.confirmed?.title ?? item.id)
                Text("省略表示取消提案；未选中时保留原状态。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if replacement != nil {
                TextField("标题", text: replacementField(\.title, fallback: ""))
                    .textFieldStyle(.roundedBorder)
                HStack {
                    Picker("验证", selection: replacementField(\.verification, fallback: .manual)) {
                        ForEach(FeatureVerificationPolicy.allCases, id: \.self) { policy in
                            Text(policy.rawValue).tag(policy)
                        }
                    }
                    .pickerStyle(.menu)
                    Toggle("自动完成", isOn: replacementField(\.autoComplete, fallback: false))
                }
                TextEditor(text: descriptionBinding)
                    .frame(minHeight: 72)
                    .overlay {
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(Color.secondary.opacity(0.3))
                    }
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.035))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .opacity(selected ? 1 : 0.6)
    }

    private func replacementField<Value>(
        _ keyPath: WritableKeyPath<WorkspaceFeature, Value>,
        fallback: Value
    ) -> Binding<Value> {
        Binding(
            get: { replacement?[keyPath: keyPath] ?? fallback },
            set: { value in
                guard var updated = replacement else { return }
                updated[keyPath: keyPath] = value
                replacement = updated
            }
        )
    }

    private var descriptionBinding: Binding<String> {
        Binding(
            get: { replacement?.description ?? "" },
            set: { value in
                guard var updated = replacement else { return }
                updated.description = value
                updated.preservedLines = value.isEmpty ? [] : [value]
                replacement = updated
            }
        )
    }
}
