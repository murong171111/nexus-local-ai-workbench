import SwiftUI
import WidgetKit

private let appGroupIdentifier = "group.com.ks.nexus"
private let fallbackSnapshotPath = "Library/Application Support/com.ks.nexus/widget-snapshot.json"

struct NexusSnapshot: Decodable {
    let generatedAt: String
    let workspacesRoot: String
    let activeWorkspace: String?
    let activeWorkspaceFolder: String?
    let workspaceCount: Int
    let riskCount: Int
    let dirtyServiceCount: Int
    let missingWorktreeCount: Int
    let topRisks: [String]
    let mainStage: String?
    let mainStageStatus: String?
    let mainStageBlockerSummary: String?
    let mainStageNextAction: String?
    let mainStageEvidence: String?
    let deepLink: String

    static let empty = NexusSnapshot(
        generatedAt: "",
        workspacesRoot: "",
        activeWorkspace: "No active workspace",
        activeWorkspaceFolder: nil,
        workspaceCount: 0,
        riskCount: 0,
        dirtyServiceCount: 0,
        missingWorktreeCount: 0,
        topRisks: ["Open Nexus to generate widget data."],
        mainStage: nil,
        mainStageStatus: nil,
        mainStageBlockerSummary: nil,
        mainStageNextAction: nil,
        mainStageEvidence: nil,
        deepLink: "nexus://"
    )
}

struct NexusEntry: TimelineEntry {
    let date: Date
    let snapshot: NexusSnapshot
}

struct NexusProvider: TimelineProvider {
    func placeholder(in context: Context) -> NexusEntry {
        NexusEntry(date: Date(), snapshot: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (NexusEntry) -> Void) {
        completion(NexusEntry(date: Date(), snapshot: loadSnapshot()))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<NexusEntry>) -> Void) {
        let entry = NexusEntry(date: Date(), snapshot: loadSnapshot())
        let nextRefresh = Calendar.current.date(byAdding: .minute, value: 15, to: Date()) ?? Date().addingTimeInterval(900)
        completion(Timeline(entries: [entry], policy: .after(nextRefresh)))
    }

    private func loadSnapshot() -> NexusSnapshot {
        let decoder = JSONDecoder()
        let urls = snapshotURLs()

        for url in urls {
            guard let data = try? Data(contentsOf: url), let snapshot = try? decoder.decode(NexusSnapshot.self, from: data) else {
                continue
            }
            return snapshot
        }

        return .empty
    }

    private func snapshotURLs() -> [URL] {
        var urls: [URL] = []

        if let groupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            urls.append(groupURL.appendingPathComponent("widget-snapshot.json"))
        }

        urls.append(FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(fallbackSnapshotPath))
        return urls
    }
}

struct NexusWidgetView: View {
    let entry: NexusEntry

    var body: some View {
        let snapshot = entry.snapshot

        VStack(alignment: .leading, spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Nexus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Local AI Workbench")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                statusPill(snapshot.riskCount > 0 ? "\(snapshot.riskCount) risks" : "clean")
            }

            Text(snapshot.activeWorkspace ?? "No active workspace")
                .font(.system(size: 16, weight: .semibold))
                .lineLimit(2)

            HStack(spacing: 8) {
                metric("WS", snapshot.workspaceCount)
                metric("Risk", snapshot.riskCount)
                metric("Dirty", snapshot.dirtyServiceCount)
                metric("Missing", snapshot.missingWorktreeCount)
            }

            if let risk = snapshot.topRisks.first {
                Text(risk)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            if let mainStage = snapshot.mainStage {
                Text([mainStage, snapshot.mainStageNextAction, snapshot.mainStageEvidence].compactMap(\.self).joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .containerBackground(.background, for: .widget)
        .widgetURL(URL(string: snapshot.deepLink))
    }

    private func metric(_ label: String, _ value: Int) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 8, design: .monospaced))
                .foregroundStyle(.secondary)
            Text("\(value)")
                .font(.system(size: 15, weight: .semibold, design: .monospaced))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.blue.opacity(0.12), in: Capsule())
            .foregroundStyle(.blue)
    }
}

@main
struct NexusWidget: Widget {
    let kind = "NexusWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: NexusProvider()) { entry in
            NexusWidgetView(entry: entry)
        }
        .configurationDisplayName("Nexus")
        .description("Shows the current local workspace, risks, dirty services, and missing worktrees.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
