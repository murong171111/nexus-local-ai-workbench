import SwiftUI

struct FeatureEditView: View {
    @Environment(\.dismiss) private var dismiss
    let featureID: String
    let original: WorkspaceFeature?
    let onSubmit: (WorkspaceFeature) -> Void

    @State private var title: String
    @State private var verification: FeatureVerificationPolicy
    @State private var autoComplete: Bool
    @State private var sources: String
    @State private var services: String
    @State private var taskIDs: String
    @State private var evidenceIDs: String
    @State private var description: String

    init(
        featureID: String,
        feature: WorkspaceFeature? = nil,
        onSubmit: @escaping (WorkspaceFeature) -> Void
    ) {
        self.featureID = featureID
        original = feature
        self.onSubmit = onSubmit
        _title = State(initialValue: feature?.title ?? "")
        _verification = State(initialValue: feature?.verification ?? .code)
        _autoComplete = State(initialValue: feature?.autoComplete ?? true)
        _sources = State(initialValue: feature?.sources.joined(separator: ", ") ?? "")
        _services = State(initialValue: feature?.services.joined(separator: ", ") ?? "")
        _taskIDs = State(initialValue: feature?.taskIDs.joined(separator: ", ") ?? "")
        _evidenceIDs = State(initialValue: feature?.evidenceIDs.joined(separator: ", ") ?? "")
        _description = State(initialValue: feature?.description ?? "")
    }

    var body: some View {
        Form {
            TextField("标题", text: $title)
            Picker("验证策略", selection: $verification) {
                ForEach(FeatureVerificationPolicy.allCases, id: \.self) { policy in
                    Text(policy.rawValue).tag(policy)
                }
            }
            Toggle("允许自动完成", isOn: $autoComplete)
            TextField("来源，逗号分隔", text: $sources)
            TextField("服务，逗号分隔", text: $services)
            TextField("任务 ID，逗号分隔", text: $taskIDs)
            TextField("证据 ID，逗号分隔", text: $evidenceIDs)
            TextEditor(text: $description)
                .frame(minHeight: 110)
                .accessibilityLabel("功能点说明")

            HStack {
                Spacer()
                Button("取消", role: .cancel) { dismiss() }
                Button(original == nil ? "检查新增" : "检查修改") {
                    onSubmit(feature)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(16)
        .frame(minWidth: 520, minHeight: 480)
    }

    private var feature: WorkspaceFeature {
        FeatureEditState.makeFeature(
            id: featureID,
            original: original,
            title: title,
            verification: verification,
            autoComplete: autoComplete,
            sources: list(sources),
            services: list(services),
            taskIDs: list(taskIDs),
            evidenceIDs: list(evidenceIDs),
            description: description
        )
    }

    private func list(_ value: String) -> [String] {
        value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}

enum FeatureEditState {
    static func makeFeature(
        id: String? = nil,
        original: WorkspaceFeature?,
        title: String,
        verification: FeatureVerificationPolicy,
        autoComplete: Bool,
        sources: [String],
        services: [String],
        taskIDs: [String],
        evidenceIDs: [String],
        description: String
    ) -> WorkspaceFeature {
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let preservedLines = original?.description == trimmedDescription
            ? (original?.preservedLines ?? [])
            : (trimmedDescription.isEmpty ? [] : ["", trimmedDescription])
        return WorkspaceFeature(
            id: id ?? original?.id ?? "",
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            status: original?.status ?? .todo,
            verification: verification,
            autoComplete: autoComplete,
            sources: sources,
            services: services,
            taskIDs: taskIDs,
            evidenceIDs: evidenceIDs,
            description: trimmedDescription,
            completedAt: original?.completedAt,
            completedBy: original?.completedBy,
            completionNote: original?.completionNote,
            evidenceStale: original?.evidenceStale ?? false,
            preservedLines: preservedLines
        )
    }
}
