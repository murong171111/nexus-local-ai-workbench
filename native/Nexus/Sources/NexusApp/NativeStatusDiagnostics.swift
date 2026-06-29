import Foundation
import NexusBridge

enum WorkspaceBoardEmptyStateReason: Hashable {
    case unconfigured
    case configuredNoDirectories
    case filteredNoResults

    var title: String {
        switch self {
        case .unconfigured:
            "本地路径还未确认"
        case .configuredNoDirectories:
            "目录已配置但未扫描到工作区"
        case .filteredNoResults:
            "当前筛选没有结果"
        }
    }

    var helpText: String {
        switch self {
        case .unconfigured:
            "Setup needed"
        case .configuredNoDirectories:
            "No workspace directories"
        case .filteredNoResults:
            "No matching workspaces"
        }
    }

    var detail: String {
        switch self {
        case .unconfigured:
            "先运行环境检查或导入团队配置，确认 Workspaces root、Source repos 和 Git 可用。"
        case .configuredNoDirectories:
            "路径可用，但真实工作区目录数为 0。可以新建工作区，或确认团队目录路径后刷新。"
        case .filteredNoResults:
            "已有工作区记录，但当前 Board 范围没有命中项。切回全部即可查看现有项目。"
        }
    }

    var systemImage: String {
        switch self {
        case .unconfigured:
            "gearshape"
        case .configuredNoDirectories:
            "folder.badge.questionmark"
        case .filteredNoResults:
            "line.3.horizontal.decrease.circle"
        }
    }

    var primaryActionLabel: String {
        switch self {
        case .unconfigured:
            "检查本机设置"
        case .configuredNoDirectories:
            "新建工作区"
        case .filteredNoResults:
            "查看全部工作区"
        }
    }

    var primaryActionSystemImage: String {
        switch self {
        case .unconfigured:
            "gearshape"
        case .configuredNoDirectories:
            "plus"
        case .filteredNoResults:
            "line.3.horizontal.decrease.circle"
        }
    }

    static func resolve(
        summary: WorkspaceListSummary,
        visibleCount: Int,
        readiness: NativeSetupReadiness
    ) -> WorkspaceBoardEmptyStateReason? {
        guard visibleCount == 0 else {
            return nil
        }
        if summary.totalWorkspaceCount > 0 {
            return .filteredNoResults
        }
        switch readiness.status {
        case .ready:
            return .configuredNoDirectories
        case .unchecked, .needsReview:
            return .unconfigured
        }
    }
}

struct NativeStatusDiagnosticItem: Hashable, Identifiable {
    let id: String
    let label: String
    let value: String
    let helpText: String
    let isAttention: Bool
}

struct NativeStatusDiagnostics: Hashable {
    let workspaceDirectoryCount: Int?
    let indexRecordCount: Int
    let widgetUpdatedAt: String?
    let latestAuditAction: String?
    let latestAuditTarget: String?
    let latestAuditTargetExists: Bool?

    var directoryValue: String {
        workspaceDirectoryCount.map(String.init) ?? "未检查"
    }

    var indexValue: String {
        "\(indexRecordCount)"
    }

    var widgetValue: String {
        widgetUpdatedAt?.isEmpty == false ? widgetUpdatedAt! : "未生成"
    }

    var auditValue: String {
        guard let latestAuditAction else {
            return "无记录"
        }
        let existsText = latestAuditTargetExists.map { $0 ? "目标存在" : "目标缺失" } ?? "目标未知"
        return "\(latestAuditAction) · \(existsText)"
    }

    var diagnosticItems: [NativeStatusDiagnosticItem] {
        [
            NativeStatusDiagnosticItem(
                id: "directories",
                label: "真实目录",
                value: directoryValue,
                helpText: "Workspace directories from environment health",
                isAttention: workspaceDirectoryCount == nil || workspaceDirectoryCount == 0
            ),
            NativeStatusDiagnosticItem(
                id: "index",
                label: "索引记录",
                value: indexValue,
                helpText: "Workspace rows found in INDEX.md",
                isAttention: indexRecordCount == 0
            ),
            NativeStatusDiagnosticItem(
                id: "widget",
                label: "Widget 更新",
                value: widgetValue,
                helpText: "Latest native widget snapshot timestamp",
                isAttention: widgetUpdatedAt?.isEmpty ?? true
            ),
            NativeStatusDiagnosticItem(
                id: "audit",
                label: "最近目标",
                value: auditValue,
                helpText: "Latest native audit event target existence",
                isAttention: latestAuditTargetExists == false
            )
        ]
    }

    static func resolve(
        workspaceRoot: String,
        health: NativeEnvironmentHealth?,
        widgetSnapshot: WidgetSnapshot?,
        auditRoot: String,
        fileManager: FileManager = .default
    ) -> NativeStatusDiagnostics {
        let indexPath = expandedURL(for: workspaceRoot)
            .appendingPathComponent("INDEX.md", isDirectory: false)
            .path
        let latestAudit = try? NativeAuditEventStore.loadRecent(
            auditRoot: auditRoot,
            limit: 1,
            fileManager: fileManager
        ).first

        return NativeStatusDiagnostics(
            workspaceDirectoryCount: health?.workspaceCount,
            indexRecordCount: indexRecordCount(at: indexPath, fileManager: fileManager),
            widgetUpdatedAt: widgetSnapshot?.generatedAt,
            latestAuditAction: latestAudit?.action,
            latestAuditTarget: latestAudit?.target,
            latestAuditTargetExists: latestAudit.flatMap { auditTargetExists($0.target, fileManager: fileManager) }
        )
    }

    private static func expandedURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func indexRecordCount(at path: String, fileManager: FileManager) -> Int {
        guard fileManager.fileExists(atPath: path),
              let content = try? String(contentsOfFile: path, encoding: .utf8) else {
            return 0
        }
        return content
            .split(separator: "\n")
            .filter { rawLine in
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard line.hasPrefix("|"), line.hasSuffix("|") else { return false }
                guard !line.contains("---") else { return false }
                return !line.localizedCaseInsensitiveContains("需求")
                    && !line.localizedCaseInsensitiveContains("workspace")
                    && !line.localizedCaseInsensitiveContains("工作区")
            }
            .count
    }

    private static func auditTargetExists(_ target: String, fileManager: FileManager) -> Bool? {
        let trimmed = target.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            return nil
        }
        let path = (trimmed as NSString).expandingTildeInPath
        return fileManager.fileExists(atPath: path)
    }
}
