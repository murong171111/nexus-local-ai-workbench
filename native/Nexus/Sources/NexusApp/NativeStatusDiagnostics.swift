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

struct NativeStatusDiagnosticSummary: Hashable {
    let title: String
    let detail: String
    let actionLabel: String
    let systemImage: String
    let status: WorkflowPathStatus
}

struct WorkspaceStatusDiagnosticCard: Hashable {
    let title: String
    let helpText: String
    let summary: NativeStatusDiagnosticSummary
    let items: [NativeStatusDiagnosticItem]

    init(diagnostics: NativeStatusDiagnostics) {
        title = "状态诊断"
        helpText = "Status diagnostics"
        summary = diagnostics.summary
        items = diagnostics.diagnosticItems
    }

    var status: WorkflowPathStatus {
        summary.status
    }

    var primaryActionLabel: String {
        summary.actionLabel
    }

    var attentionCount: Int {
        items.filter(\.isAttention).count
    }

    var visibleItems: [NativeStatusDiagnosticItem] {
        let attentionItems = items.filter(\.isAttention)
        if !attentionItems.isEmpty {
            return Array(attentionItems.prefix(2))
        }
        return Array(items.prefix(2))
    }

    var collapsedItems: [NativeStatusDiagnosticItem] {
        let visibleIDs = Set(visibleItems.map(\.id))
        return items.filter { !visibleIDs.contains($0.id) }
    }

    var detailsCollapsedByDefault: Bool {
        !collapsedItems.isEmpty
    }

    var detailLabel: String {
        "诊断明细 / Diagnostics (\(collapsedItems.count))"
    }

    var isReady: Bool {
        status == .ready && attentionCount == 0
    }
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

    var summary: NativeStatusDiagnosticSummary {
        guard let workspaceDirectoryCount else {
            return NativeStatusDiagnosticSummary(
                title: "状态还未检查",
                detail: "先运行环境检查，确认真实工作区目录、索引和审计记录是否可读。",
                actionLabel: "运行环境检查",
                systemImage: "questionmark.circle",
                status: .pending
            )
        }

        if workspaceDirectoryCount == 0 && indexRecordCount > 0 {
            return NativeStatusDiagnosticSummary(
                title: "索引有记录但真实目录为 0",
                detail: "INDEX.md 仍有 \(indexRecordCount) 条记录，但扫描不到实际目录；优先检查路径配置或目录是否被移动。",
                actionLabel: "检查路径设置",
                systemImage: "folder.badge.questionmark",
                status: .blocked
            )
        }

        if workspaceDirectoryCount == 0 {
            return NativeStatusDiagnosticSummary(
                title: "还没有真实工作区目录",
                detail: "路径已可读，但目录数为 0；下一步应创建工作区或刷新团队目录。",
                actionLabel: "新建工作区",
                systemImage: "folder.badge.plus",
                status: .next
            )
        }

        if indexRecordCount == 0 {
            return NativeStatusDiagnosticSummary(
                title: "目录存在但索引为空",
                detail: "扫描到 \(workspaceDirectoryCount) 个真实目录，但 INDEX.md 没有工作区记录；刷新索引后再判断列表状态。",
                actionLabel: "重新扫描",
                systemImage: "arrow.clockwise",
                status: .review
            )
        }

        if latestAuditTargetExists == false {
            return NativeStatusDiagnosticSummary(
                title: "最近审计目标缺失",
                detail: "最近一次 audit 指向的目标已经不存在；需要刷新扫描或确认该工作区是否已移动。",
                actionLabel: "重新扫描",
                systemImage: "exclamationmark.triangle",
                status: .review
            )
        }

        if widgetUpdatedAt?.isEmpty ?? true {
            return NativeStatusDiagnosticSummary(
                title: "Widget 快照待更新",
                detail: "真实目录和索引已可读，但还没有 Native Widget 快照时间。",
                actionLabel: "刷新 Widget",
                systemImage: "rectangle.3.group",
                status: .review
            )
        }

        return NativeStatusDiagnosticSummary(
            title: "本地状态已对齐",
            detail: "真实目录 \(workspaceDirectoryCount) 个，索引记录 \(indexRecordCount) 条，最近审计目标可验证。",
            actionLabel: "继续主路径",
            systemImage: "checkmark.seal",
            status: .ready
        )
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

    var workspaceDetailCard: WorkspaceStatusDiagnosticCard {
        WorkspaceStatusDiagnosticCard(diagnostics: self)
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
