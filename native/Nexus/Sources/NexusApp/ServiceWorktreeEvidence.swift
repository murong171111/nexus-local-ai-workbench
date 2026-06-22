import Foundation
import NexusBridge

struct ServiceBranchCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
}

struct ServiceBranchEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let evidence: [String]
    let checks: [ServiceBranchCheck]
    let servicesPath: String
    let branchesPath: String
    let branchConfirmed: Bool
    let servicesConfirmed: Bool
    let branchPolicyRecorded: Bool
    let missingSourceServices: [String]
    let targetBranchMissingServices: [String]

    var ready: Bool {
        status == .ready
    }

    var title: String {
        if !branchConfirmed {
            return "确认目标分支 / Confirm branch"
        }
        if !servicesConfirmed {
            return "确认服务范围 / Confirm services"
        }
        if !missingSourceServices.isEmpty {
            return "修正源仓库 / Source repos"
        }
        if !targetBranchMissingServices.isEmpty {
            return "修正目标分支 / Target branch"
        }
        if !branchPolicyRecorded {
            return "记录分支策略 / Branch policy"
        }
        return "服务分支已确认 / Service & branch ready"
    }

    var primaryActionLabel: String {
        if !branchConfirmed || !branchPolicyRecorded || !targetBranchMissingServices.isEmpty {
            return "打开分支"
        }
        return "打开服务"
    }

    var primaryActionSystemImage: String {
        if !branchConfirmed || !branchPolicyRecorded || !targetBranchMissingServices.isEmpty {
            return "arrow.triangle.branch"
        }
        return "square.stack.3d.up"
    }

    var primaryAction: WorkspaceMainStageAction {
        if !branchConfirmed || !branchPolicyRecorded || !targetBranchMissingServices.isEmpty {
            return .document("branches")
        }
        return .document("services")
    }

    static func resolve(workspace: WorkspaceSummary) -> ServiceBranchEvidence {
        let servicesPath = workspace.documentLinks["services"] ?? "\(workspace.path)/services.md"
        let branchesPath = workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md"
        let servicesText = readText(at: servicesPath)
        let branchesText = readText(at: branchesPath)
        let branchesDocumentExists = FileManager.default.fileExists(atPath: branchesPath)

        let branchConfirmed = hasConfirmedTargetBranch(workspace.branch)
        let servicesConfirmed = !workspace.services.isEmpty || serviceScopeExplicitlyEmpty(servicesText)
        let missingSourceServices = workspace.services
            .filter { !$0.sourceExists }
            .map(\.name)
        let targetBranchMissingServices = branchConfirmed
            ? workspace.services
                .filter { $0.sourceExists && targetBranchUnavailable($0, target: workspace.branch) }
                .map(\.name)
            : []
        let branchPolicyRecorded = branchConfirmed
            && (!branchesDocumentExists || hasBranchPolicy(in: branchesText, branch: workspace.branch))

        let checks = [
            ServiceBranchCheck(
                id: "target-branch",
                label: "目标分支 / Branch",
                detail: branchConfirmed ? "目标分支已确认：\(workspace.branch)。" : "目标分支仍是占位或为空，请补齐 branches.md 或 workspace.md。",
                status: branchConfirmed ? .ready : .blocked,
                systemImage: "arrow.triangle.branch",
                path: branchesPath
            ),
            ServiceBranchCheck(
                id: "service-scope",
                label: "服务范围 / Services",
                detail: servicesConfirmed
                    ? serviceScopeDetail(workspace: workspace)
                    : "服务范围为空且未写明本需求无代码服务；先确认涉及服务或明确无需服务 worktree。",
                status: servicesConfirmed ? .ready : .blocked,
                systemImage: "square.stack.3d.up",
                path: servicesPath
            ),
            ServiceBranchCheck(
                id: "source-repos",
                label: "源仓库 / Sources",
                detail: missingSourceServices.isEmpty
                    ? "已确认服务都有可用 source repo 记录。"
                    : "这些服务的 source repo 不可用：\(missingSourceServices.joined(separator: ", "))。",
                status: missingSourceServices.isEmpty ? .ready : .blocked,
                systemImage: missingSourceServices.isEmpty ? "externaldrive" : "externaldrive.badge.xmark",
                path: servicesPath
            ),
            ServiceBranchCheck(
                id: "target-branch-availability",
                label: "分支可用 / Availability",
                detail: targetBranchMissingServices.isEmpty
                    ? targetBranchAvailableDetail(branchConfirmed: branchConfirmed, targetBranch: workspace.branch)
                    : "这些服务缺少目标分支或远端引用不可用：\(targetBranchMissingServices.joined(separator: ", "))。",
                status: targetBranchMissingServices.isEmpty ? .ready : .blocked,
                systemImage: targetBranchMissingServices.isEmpty ? "checkmark.seal" : "exclamationmark.triangle",
                path: branchesPath
            ),
            ServiceBranchCheck(
                id: "branch-policy",
                label: "分支策略 / Policy",
                detail: branchPolicyRecorded
                    ? "分支策略已记录或已从工作区扫描结果继承。"
                    : "branches.md 尚未记录目标分支、基线或分支创建/沿用策略。",
                status: branchPolicyRecorded ? .ready : .review,
                systemImage: "point.3.connected.trianglepath.dotted",
                path: branchesPath
            )
        ]

        let blockers = checks.filter { $0.status == .blocked }
        let reviews = checks.filter { $0.status == .review }
        let resolvedStatus: WorkflowPathStatus
        let reason: String
        if !blockers.isEmpty {
            resolvedStatus = .blocked
            reason = blockers.map(\.detail).joined(separator: " ")
        } else if !reviews.isEmpty {
            resolvedStatus = .review
            reason = reviews.map(\.detail).joined(separator: " ")
        } else {
            resolvedStatus = .ready
            reason = "服务范围、目标分支、source repo 和分支策略已具备，可以进入 worktree 准备。"
        }

        return ServiceBranchEvidence(
            status: resolvedStatus,
            reason: reason,
            evidence: ["services.md", "branches.md", "source-repos/"],
            checks: checks,
            servicesPath: servicesPath,
            branchesPath: branchesPath,
            branchConfirmed: branchConfirmed,
            servicesConfirmed: servicesConfirmed,
            branchPolicyRecorded: branchPolicyRecorded,
            missingSourceServices: missingSourceServices,
            targetBranchMissingServices: targetBranchMissingServices
        )
    }

    private static func readText(at path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private static func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("未确认")
            && !normalized.contains("pending")
            && !normalized.contains("tbd")
            && !normalized.contains("todo")
    }

    private static func hasBranchPolicy(in text: String, branch: String) -> Bool {
        let normalizedBranch = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let meaningfulLines = text.components(separatedBy: .newlines).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { line in
            !line.isEmpty && !line.hasPrefix("#") && !line.hasPrefix("| ---") && !placeholderOnly(line)
        }

        return meaningfulLines.contains { line in
            let lowercased = line.lowercased()
            if !normalizedBranch.isEmpty && lowercased.contains(normalizedBranch) {
                return true
            }
            let markers = ["目标分支", "分支策略", "基线", "统一分支", "新建分支", "沿用分支", "branch", "baseline"]
            return markers.contains { lowercased.contains($0.lowercased()) }
        }
    }

    private static func serviceScopeExplicitlyEmpty(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let markers = ["无需服务", "无代码服务", "不涉及服务", "仅文档", "no service", "docs only", "documentation only"]
        return markers.contains { normalized.contains($0) }
    }

    private static func serviceScopeDetail(workspace: WorkspaceSummary) -> String {
        if workspace.services.isEmpty {
            return "services.md 已声明本需求无需代码服务。"
        }
        return "已确认 \(workspace.services.count) 个服务：\(workspace.services.map(\.name).joined(separator: ", "))。"
    }

    private static func targetBranchAvailableDetail(branchConfirmed: Bool, targetBranch: String) -> String {
        if branchConfirmed {
            return "已确认服务未报告目标分支缺失：\(targetBranch)。"
        }
        return "目标分支未确认，分支可用性会在确认后检查。"
    }

    private static func targetBranchUnavailable(_ service: ServiceStatus, target: String) -> Bool {
        let fields = [service.branch, service.gitSummary]
            .map {
                $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            }
            .filter { !$0.isEmpty }
        guard !fields.isEmpty else { return false }
        let missingMarkers = [
            "remote missing",
            "branch missing",
            "target missing",
            "missing branch",
            "not found",
            "no such ref",
            "unknown revision",
            "远端不存在",
            "远端缺失",
            "分支不存在",
            "目标分支不存在",
            "未找到分支"
        ]
        guard let matchingField = fields.first(where: { field in
            missingMarkers.contains(where: { field.contains($0) })
        }) else {
            return false
        }

        let normalizedTarget = target
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "origin/", with: "")
        guard !normalizedTarget.isEmpty else { return true }
        return matchingField.contains(normalizedTarget)
            || matchingField.contains("branch")
            || matchingField.contains("分支")
    }

    private static func placeholderOnly(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        let placeholders = [
            "待整理",
            "待确认",
            "待补充",
            "暂无",
            "todo",
            "tbd",
            "placeholder"
        ]
        return placeholders.contains { lowercased.contains($0) }
    }
}

struct WorktreeSetupCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
}

enum WorktreeSetupPlanAction: String, Hashable {
    case create
    case skip
    case blocked

    var displayLabel: String {
        switch self {
        case .create:
            return "创建 / Create"
        case .skip:
            return "跳过 / Skip"
        case .blocked:
            return "阻塞 / Blocked"
        }
    }

    var status: WorkflowPathStatus {
        switch self {
        case .create:
            return .next
        case .skip:
            return .ready
        case .blocked:
            return .blocked
        }
    }

    var systemImage: String {
        switch self {
        case .create:
            return "plus.rectangle.on.folder"
        case .skip:
            return "checkmark.circle"
        case .blocked:
            return "exclamationmark.triangle"
        }
    }
}

struct WorktreeSetupPlanItem: Hashable, Identifiable {
    let id: String
    let serviceName: String
    let action: WorktreeSetupPlanAction
    let targetBranch: String
    let targetPath: String
    let sourceAvailable: Bool
    let currentBranch: String
    let reason: String
}

enum WorktreeSetupRecoveryDocument: String, Hashable {
    case services
    case branches
    case worktreeScript
}

struct WorktreeSetupRecoveryAction: Hashable, Identifiable {
    let id: String
    let serviceName: String?
    let title: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let document: WorktreeSetupRecoveryDocument?

    static func actions(for response: SetupWorktreesResponse) -> [WorktreeSetupRecoveryAction] {
        if response.failed.isEmpty {
            return [
                WorktreeSetupRecoveryAction(
                    id: "run-local-check",
                    serviceName: nil,
                    title: "运行本地检查 / Run local check",
                    detail: response.created.isEmpty
                        ? "没有新增 worktree。运行检查确认分支、任务和风险状态后继续。"
                        : "已创建 worktree。运行检查确认分支一致、缺失 worktree 和未提交服务状态。",
                    status: .next,
                    systemImage: "checklist",
                    document: nil
                )
            ]
        }

        return response.failed.map { result in
            let detail = result.detail.lowercased()
            if detail.contains("service name") || detail.contains("path segment") {
                return WorktreeSetupRecoveryAction(
                    id: "\(result.service)-service-name",
                    serviceName: result.service,
                    title: "修正服务名 / Service name",
                    detail: "服务名必须是安全的单级目录名。先修正 services.md 中的服务范围，再重新执行 worktree 创建。",
                    status: .blocked,
                    systemImage: "textformat.abc",
                    document: .services
                )
            }
            if detail.contains("source repository does not exist") {
                return WorktreeSetupRecoveryAction(
                    id: "\(result.service)-source-missing",
                    serviceName: result.service,
                    title: "补齐源仓库 / Source repo",
                    detail: "Nexus 没找到 \(result.sourcePath)。请同步源仓库或在 Settings 调整 source repositories root 后刷新。",
                    status: .blocked,
                    systemImage: "externaldrive.badge.xmark",
                    document: .services
                )
            }
            if detail.contains("not a git worktree") {
                return WorktreeSetupRecoveryAction(
                    id: "\(result.service)-source-git",
                    serviceName: result.service,
                    title: "修正源仓库 Git 状态 / Source Git",
                    detail: "\(result.sourcePath) 不是可用 Git worktree。请检查源仓库是否完整克隆，再重试。",
                    status: .blocked,
                    systemImage: "externaldrive.badge.xmark",
                    document: .services
                )
            }
            if detail.contains("git fetch failed") {
                return WorktreeSetupRecoveryAction(
                    id: "\(result.service)-fetch",
                    serviceName: result.service,
                    title: "检查远端访问 / Fetch",
                    detail: "git fetch origin 失败。请检查网络、权限、remote 配置或目标分支是否存在，再重新执行。",
                    status: .blocked,
                    systemImage: "arrow.triangle.branch",
                    document: .branches
                )
            }
            if detail.contains("already used by worktree") {
                return WorktreeSetupRecoveryAction(
                    id: "\(result.service)-branch-used",
                    serviceName: result.service,
                    title: "处理分支占用 / Branch in use",
                    detail: "目标分支已被其他 worktree 占用。先确认占用路径，决定复用、移除旧 worktree，或创建独立分支。",
                    status: .blocked,
                    systemImage: "arrow.triangle.branch",
                    document: .branches
                )
            }
            if detail.contains("git worktree add failed") {
                return WorktreeSetupRecoveryAction(
                    id: "\(result.service)-worktree-add",
                    serviceName: result.service,
                    title: "复核分支和路径 / Worktree add",
                    detail: "git worktree add 失败。请检查目标分支、\(result.worktreePath) 写入路径和 Git 输出，再重试。",
                    status: .blocked,
                    systemImage: "wrench.and.screwdriver",
                    document: .worktreeScript
                )
            }
            return WorktreeSetupRecoveryAction(
                id: "\(result.service)-review",
                serviceName: result.service,
                title: "复核失败明细 / Review failure",
                detail: result.detail.isEmpty
                    ? "Nexus 未返回详细失败原因。请查看 worktree 创建脚本和源仓库状态。"
                    : result.detail,
                status: .review,
                systemImage: "exclamationmark.triangle",
                document: .worktreeScript
            )
        }
    }
}

struct WorktreeSetupEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let evidence: [String]
    let checks: [WorktreeSetupCheck]
    let setupScriptPath: String
    let setupPlan: [WorktreeSetupPlanItem]
    let missingServices: [String]
    let branchMismatchServices: [String]
    let missingSourceServices: [String]
    let branchConfirmed: Bool
    let setupScriptExists: Bool

    var ready: Bool {
        status == .ready
    }

    var hasMissingWorktrees: Bool {
        !missingServices.isEmpty
    }

    var title: String {
        if !branchConfirmed {
            return "确认目标分支 / Confirm branch"
        }
        if !missingSourceServices.isEmpty {
            return "修正源仓库 / Source repos"
        }
        if !branchMismatchServices.isEmpty {
            return "修正 worktree 分支 / Branch mismatch"
        }
        if !missingServices.isEmpty {
            return "准备隔离 worktree / Setup worktrees"
        }
        return "Worktree 已就绪 / Worktrees ready"
    }

    var primaryActionLabel: String {
        if !branchConfirmed {
            return "打开分支"
        }
        if !missingSourceServices.isEmpty {
            return "打开服务"
        }
        if !branchMismatchServices.isEmpty {
            return "打开服务"
        }
        if !missingServices.isEmpty {
            return "创建 worktree"
        }
        return setupScriptExists ? "打开脚本" : "打开服务"
    }

    var primaryActionSystemImage: String {
        if !branchConfirmed || !branchMismatchServices.isEmpty {
            return "arrow.triangle.branch"
        }
        if !missingSourceServices.isEmpty {
            return "square.stack.3d.up"
        }
        if !missingServices.isEmpty {
            return "wrench.and.screwdriver"
        }
        return setupScriptExists ? "terminal" : "checkmark.seal"
    }

    var primaryAction: WorkspaceMainStageAction {
        if !branchConfirmed || !branchMismatchServices.isEmpty {
            return .document("branches")
        }
        if !missingSourceServices.isEmpty {
            return .document("services")
        }
        if !missingServices.isEmpty {
            return .worktree
        }
        return setupScriptExists ? .document("worktreeScript") : .document("services")
    }

    static func resolve(workspace: WorkspaceSummary) -> WorktreeSetupEvidence {
        let setupScriptPath = workspace.documentLinks["worktreeScript"]
            ?? "\(workspace.path)/scripts/worktree-commands.sh"
        let setupScriptExists = FileManager.default.fileExists(atPath: setupScriptPath)
        let branchConfirmed = hasConfirmedTargetBranch(workspace.branch)
        let setupPlan = buildSetupPlan(workspace: workspace, branchConfirmed: branchConfirmed)
        let missingServices = workspace.services
            .filter { !$0.worktreeExists }
            .map(\.name)
        let missingSourceServices = workspace.services
            .filter { !$0.sourceExists }
            .map(\.name)
        let branchMismatchServices: [String] = branchConfirmed
            ? workspace.services.compactMap { service in
                guard service.worktreeExists, !branchMatches(service.branch, target: workspace.branch) else {
                    return nil
                }
                return "\(service.name)(\(service.branch))"
            }
            : []

        let checks = [
            WorktreeSetupCheck(
                id: "target-branch",
                label: "目标分支 / Branch",
                detail: branchConfirmed ? "目标分支已确认：\(workspace.branch)。" : "目标分支仍未确认，不能创建 workspace-local worktree。",
                status: branchConfirmed ? .ready : .blocked,
                systemImage: "arrow.triangle.branch",
                path: workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md"
            ),
            WorktreeSetupCheck(
                id: "source-repos",
                label: "源仓库 / Sources",
                detail: missingSourceServices.isEmpty
                    ? "已确认服务都有可用 source repo。"
                    : "这些服务的 source repo 不可用：\(missingSourceServices.joined(separator: ", "))。",
                status: missingSourceServices.isEmpty ? .ready : .blocked,
                systemImage: missingSourceServices.isEmpty ? "externaldrive" : "externaldrive.badge.xmark",
                path: workspace.documentLinks["services"] ?? "\(workspace.path)/services.md"
            ),
            WorktreeSetupCheck(
                id: "workspace-worktrees",
                label: "工作区 worktree / Worktrees",
                detail: missingServices.isEmpty
                    ? worktreeReadyDetail(workspace: workspace)
                    : "缺失 \(missingServices.count) 个 workspace-local worktree：\(missingServices.joined(separator: ", "))。",
                status: missingServices.isEmpty ? .ready : .next,
                systemImage: missingServices.isEmpty ? "checkmark.circle" : "wrench.and.screwdriver",
                path: setupScriptPath
            ),
            WorktreeSetupCheck(
                id: "branch-alignment",
                label: "分支一致 / Alignment",
                detail: branchMismatchServices.isEmpty
                    ? "已存在的 worktree 与目标分支一致，或尚待创建。"
                    : "这些 worktree 不在目标分支：\(branchMismatchServices.joined(separator: ", "))。",
                status: branchMismatchServices.isEmpty ? .ready : .blocked,
                systemImage: branchMismatchServices.isEmpty ? "checkmark.circle" : "arrow.triangle.branch",
                path: workspace.documentLinks["branches"] ?? "\(workspace.path)/branches.md"
            ),
            WorktreeSetupCheck(
                id: "setup-plan",
                label: "创建计划 / Plan",
                detail: setupPlanDetail(setupPlan, workspace: workspace),
                status: setupPlanStatus(setupPlan, workspace: workspace),
                systemImage: setupPlanSystemImage(setupPlan, workspace: workspace),
                path: setupScriptPath
            ),
            WorktreeSetupCheck(
                id: "setup-script",
                label: "创建脚本 / Commands",
                detail: setupScriptExists
                    ? "scripts/worktree-commands.sh 可用于复核预期命令；确认 sheet 也会列出执行计划。"
                    : "暂未找到 scripts/worktree-commands.sh；确认 sheet 仍会展示将执行的 worktree 计划。",
                status: setupScriptExists || missingServices.isEmpty ? .ready : .review,
                systemImage: setupScriptExists ? "terminal" : "doc.badge.ellipsis",
                path: setupScriptPath
            )
        ]

        let blockers = checks.filter { $0.status == .blocked }
        let reviews = checks.filter { $0.status == .review }
        let resolvedStatus: WorkflowPathStatus
        let reason: String
        if !blockers.isEmpty {
            resolvedStatus = .blocked
            reason = blockers.map(\.detail).joined(separator: " ")
        } else if !missingServices.isEmpty {
            resolvedStatus = .next
            reason = "\(missingServices.count) 个服务还没有 workspace-local worktree：\(missingServices.joined(separator: ", "))。先在确认 sheet 复核命令，再执行创建。"
        } else if !reviews.isEmpty {
            resolvedStatus = .review
            reason = reviews.map(\.detail).joined(separator: " ")
        } else {
            resolvedStatus = .ready
            reason = "确认服务均已有 workspace-local worktree，且已存在 worktree 的分支与目标分支一致。"
        }

        return WorktreeSetupEvidence(
            status: resolvedStatus,
            reason: reason,
            evidence: ["repos/<service>", "source-repos/", "scripts/worktree-commands.sh"],
            checks: checks,
            setupScriptPath: setupScriptPath,
            setupPlan: setupPlan,
            missingServices: missingServices,
            branchMismatchServices: branchMismatchServices,
            missingSourceServices: missingSourceServices,
            branchConfirmed: branchConfirmed,
            setupScriptExists: setupScriptExists
        )
    }

    private static func hasConfirmedTargetBranch(_ branch: String) -> Bool {
        let normalized = branch.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalized.isEmpty else { return false }
        return !normalized.contains("待确认")
            && !normalized.contains("未确认")
            && !normalized.contains("pending")
            && !normalized.contains("tbd")
            && !normalized.contains("todo")
    }

    private static func branchMatches(_ branch: String, target: String) -> Bool {
        let normalizedBranch = normalizeBranch(branch)
        let normalizedTarget = normalizeBranch(target)
        guard !normalizedBranch.isEmpty, !normalizedTarget.isEmpty else {
            return true
        }
        guard !normalizedBranch.contains("missing"),
              !normalizedBranch.contains("待确认"),
              !normalizedBranch.contains("pending") else {
            return true
        }
        return normalizedBranch == normalizedTarget
            || normalizedBranch.hasSuffix("/\(normalizedTarget)")
    }

    private static func buildSetupPlan(
        workspace: WorkspaceSummary,
        branchConfirmed: Bool
    ) -> [WorktreeSetupPlanItem] {
        workspace.services.map { service in
            let targetPath = Self.localWorktreePath(for: service, in: workspace)
            let targetBranch = workspace.branch.trimmingCharacters(in: .whitespacesAndNewlines)

            if !branchConfirmed {
                return WorktreeSetupPlanItem(
                    id: service.name,
                    serviceName: service.name,
                    action: .blocked,
                    targetBranch: targetBranch,
                    targetPath: targetPath,
                    sourceAvailable: service.sourceExists,
                    currentBranch: service.branch,
                    reason: "目标分支未确认，不能生成可执行 worktree 创建计划。"
                )
            }

            if !service.sourceExists {
                return WorktreeSetupPlanItem(
                    id: service.name,
                    serviceName: service.name,
                    action: .blocked,
                    targetBranch: targetBranch,
                    targetPath: targetPath,
                    sourceAvailable: false,
                    currentBranch: service.branch,
                    reason: "source repo 不可用，不能从源仓库创建 workspace-local worktree。"
                )
            }

            if service.worktreeExists && !branchMatches(service.branch, target: workspace.branch) {
                return WorktreeSetupPlanItem(
                    id: service.name,
                    serviceName: service.name,
                    action: .blocked,
                    targetBranch: targetBranch,
                    targetPath: targetPath,
                    sourceAvailable: true,
                    currentBranch: service.branch,
                    reason: "已存在 worktree，但当前分支是 \(service.branch)，需要先修正到目标分支。"
                )
            }

            if service.worktreeExists {
                return WorktreeSetupPlanItem(
                    id: service.name,
                    serviceName: service.name,
                    action: .skip,
                    targetBranch: targetBranch,
                    targetPath: targetPath,
                    sourceAvailable: true,
                    currentBranch: service.branch,
                    reason: "workspace-local worktree 已存在，本次创建会跳过。"
                )
            }

            return WorktreeSetupPlanItem(
                id: service.name,
                serviceName: service.name,
                action: .create,
                targetBranch: targetBranch,
                targetPath: targetPath,
                sourceAvailable: true,
                currentBranch: service.branch,
                reason: "将创建到 repos/\(service.name)，并使用目标分支 \(targetBranch)。"
            )
        }
    }

    private static func setupPlanDetail(
        _ plan: [WorktreeSetupPlanItem],
        workspace: WorkspaceSummary
    ) -> String {
        guard !plan.isEmpty else {
            return workspace.services.isEmpty
                ? "当前工作区没有需要创建的服务 worktree。"
                : "暂无可审计的 worktree 创建计划。"
        }
        let createCount = plan.filter { $0.action == .create }.count
        let skipCount = plan.filter { $0.action == .skip }.count
        let blockedCount = plan.filter { $0.action == .blocked }.count
        return "创建 \(createCount)，跳过 \(skipCount)，阻塞 \(blockedCount)。每个服务都带目标路径、分支和原因。"
    }

    private static func setupPlanStatus(
        _ plan: [WorktreeSetupPlanItem],
        workspace: WorkspaceSummary
    ) -> WorkflowPathStatus {
        guard !plan.isEmpty else {
            return workspace.services.isEmpty ? .ready : .review
        }
        if plan.contains(where: { $0.action == .blocked }) {
            return .blocked
        }
        if plan.contains(where: { $0.action == .create }) {
            return .next
        }
        return .ready
    }

    private static func setupPlanSystemImage(
        _ plan: [WorktreeSetupPlanItem],
        workspace: WorkspaceSummary
    ) -> String {
        switch setupPlanStatus(plan, workspace: workspace) {
        case .blocked:
            return "exclamationmark.triangle"
        case .pending:
            return "clock"
        case .next:
            return "list.bullet.clipboard"
        case .review:
            return "doc.badge.ellipsis"
        case .ready:
            return "checkmark.circle"
        case .archived:
            return "archivebox"
        }
    }

    private static func localWorktreePath(for service: ServiceStatus, in workspace: WorkspaceSummary) -> String {
        URL(fileURLWithPath: workspace.path, isDirectory: true)
            .appendingPathComponent("repos", isDirectory: true)
            .appendingPathComponent(service.name, isDirectory: true)
            .path
    }

    private static func normalizeBranch(_ branch: String) -> String {
        branch
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
            .replacingOccurrences(of: "origin/", with: "")
    }

    private static func worktreeReadyDetail(workspace: WorkspaceSummary) -> String {
        if workspace.services.isEmpty {
            return "当前工作区没有需要创建的服务 worktree。"
        }
        return "\(workspace.services.count) 个服务均已有 workspace-local worktree。"
    }
}
