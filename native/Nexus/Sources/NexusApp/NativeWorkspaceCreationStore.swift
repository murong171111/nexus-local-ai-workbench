import Foundation
import NexusBridge

enum NativeWorkspaceCreationStore {
    static func create(
        request: CreateWorkspaceRequest,
        fileManager: FileManager = .default
    ) throws -> CreateWorkspaceResponse {
        guard request.confirmed else {
            throw NativeWorkspaceCreationStoreError.unconfirmed
        }

        let rootURL = expandedURL(for: request.workspacesRoot)
        let folder = try safeFolderName(request.folder)
        let workspaceURL = rootURL.appendingPathComponent(folder, isDirectory: true)
        if fileManager.fileExists(atPath: workspaceURL.path) {
            throw NativeWorkspaceCreationStoreError.workspaceAlreadyExists(workspaceURL.path)
        }

        try fileManager.createDirectory(at: workspaceURL.appendingPathComponent("logs"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceURL.appendingPathComponent("sql"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceURL.appendingPathComponent("repos"), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: workspaceURL.appendingPathComponent("scripts"), withIntermediateDirectories: true)

        let services = normalizedServices(request.services)
        let targetBranch = normalizedTargetBranch(request.targetBranch)
        let createdDate = creationDate(from: folder)
        try writeStandardFiles(
            workspaceURL: workspaceURL,
            name: request.name,
            folder: folder,
            sourceReposRoot: request.sourceReposRoot,
            services: services,
            targetBranch: targetBranch,
            createdDate: createdDate
        )
        try updateIndex(
            rootURL: rootURL,
            name: request.name,
            folder: folder,
            targetBranch: targetBranch,
            services: services
        )

        let generatedFiles = initializationFileReceipt(workspaceURL: workspaceURL, fileManager: fileManager)
        let initializationChecks = initializationChecks(
            workspaceURL: workspaceURL,
            generatedFiles: generatedFiles,
            services: services,
            targetBranch: targetBranch,
            fileManager: fileManager
        )
        let response = CreateWorkspaceResponse(
            path: workspaceURL.path,
            folder: folder,
            generatedFiles: generatedFiles,
            initializationChecks: initializationChecks
        )
        let audit = appendAuditEvent(
            request: request,
            response: response,
            services: services,
            targetBranch: targetBranch
        )
        return CreateWorkspaceResponse(
            path: response.path,
            folder: response.folder,
            generatedFiles: response.generatedFiles,
            initializationChecks: response.initializationChecks,
            auditEventID: audit.response?.event.id,
            auditEventPath: audit.response?.path,
            auditError: audit.error
        )
    }

    private static func expandedURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }

    private static func safeFolderName(_ folder: String) throws -> String {
        let trimmed = folder.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NativeWorkspaceCreationStoreError.emptyFolder
        }
        guard trimmed != "." && trimmed != ".." else {
            throw NativeWorkspaceCreationStoreError.unsafeFolder(trimmed)
        }
        guard !(trimmed as NSString).isAbsolutePath,
              trimmed.rangeOfCharacter(from: CharacterSet(charactersIn: "/:\\")) == nil,
              !trimmed.split(separator: "/", omittingEmptySubsequences: false).contains("..") else {
            throw NativeWorkspaceCreationStoreError.unsafeFolder(trimmed)
        }
        return trimmed
    }

    private static func normalizedServices(_ services: [String]) -> [String] {
        Array(Set(services.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }))
            .sorted { $0.localizedStandardCompare($1) == .orderedAscending }
    }

    private static func normalizedTargetBranch(_ branch: String) -> String {
        let trimmed = branch.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "待确认" : trimmed
    }

    private static func creationDate(from folder: String) -> String {
        folder.split(separator: "-").prefix(3).joined(separator: "-")
    }

    private static func writeStandardFiles(
        workspaceURL: URL,
        name: String,
        folder: String,
        sourceReposRoot: String,
        services: [String],
        targetBranch: String,
        createdDate: String
    ) throws {
        let files: [(String, String)] = [
            ("AGENTS.md", agentsMarkdown(name: name, workspacePath: workspaceURL.path, sourceReposRoot: sourceReposRoot)),
            ("workspace.md", workspaceMarkdown(name: name, createdDate: createdDate, targetBranch: targetBranch, sourceReposRoot: sourceReposRoot)),
            ("STATUS.md", statusMarkdown(createdDate: createdDate, services: services, targetBranch: targetBranch, sourceReposRoot: sourceReposRoot)),
            ("services.md", servicesMarkdown(services: services, sourceReposRoot: sourceReposRoot)),
            ("branches.md", branchesMarkdown(services: services, targetBranch: targetBranch, sourceReposRoot: sourceReposRoot)),
            ("requirements.md", requirementsMarkdown(name: name, targetBranch: targetBranch, services: services)),
            ("acceptance.md", acceptanceMarkdown(name: name)),
            ("changes.md", changesMarkdown(name: name)),
            ("plan.md", planMarkdown()),
            ("tasks.md", tasksMarkdown()),
            ("decisions.md", decisionsMarkdown()),
            ("handoff.md", handoffMarkdown()),
            ("delivery.md", deliveryMarkdown()),
            ("交付记录.md", deliveryRecordMarkdown(name: name, folder: folder, targetBranch: targetBranch, services: services)),
            ("bootstrap-report.md", bootstrapReportMarkdown(name: name, folder: folder, workspacePath: workspaceURL.path, services: services, targetBranch: targetBranch, sourceReposRoot: sourceReposRoot, createdDate: createdDate)),
            ("scripts/worktree-commands.sh", worktreeCommandsMarkdown(workspaceURL: workspaceURL, services: services, targetBranch: targetBranch, sourceReposRoot: sourceReposRoot))
        ]
        for (relativePath, content) in files {
            let url = workspaceURL.appendingPathComponent(relativePath, isDirectory: false)
            try content.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private static func updateIndex(
        rootURL: URL,
        name: String,
        folder: String,
        targetBranch: String,
        services: [String]
    ) throws {
        let indexURL = rootURL.appendingPathComponent("INDEX.md", isDirectory: false)
        var content = (try? String(contentsOf: indexURL, encoding: .utf8))
            ?? "# Workspace Index\n\n| 工作区 | 状态 | 目标分支 | 服务 | 路径 |\n| --- | --- | --- | --- | --- |\n"
        content += "| \(name) | analyzing | \(targetBranch) | \(services.isEmpty ? "待确认" : services.joined(separator: ", ")) | `\(folder)` |\n"
        try content.write(to: indexURL, atomically: true, encoding: .utf8)
    }

    private static func initializationFileReceipt(
        workspaceURL: URL,
        fileManager: FileManager
    ) -> [WorkspaceInitializationFile] {
        initializationFileSpecs.map { spec in
            let url = workspaceURL.appendingPathComponent(spec.relativePath)
            let exists = spec.kind == "directory"
                ? fileManager.directoryExists(atPath: url.path)
                : fileManager.fileExists(atPath: url.path)
            return WorkspaceInitializationFile(
                label: spec.label,
                relativePath: spec.relativePath,
                kind: spec.kind,
                exists: exists
            )
        }
    }

    private static func initializationChecks(
        workspaceURL: URL,
        generatedFiles: [WorkspaceInitializationFile],
        services: [String],
        targetBranch: String,
        fileManager: FileManager
    ) -> [WorkspaceInitializationCheck] {
        let missingFiles = generatedFiles.filter { !$0.exists }.map(\.relativePath)
        let statusURL = workspaceURL.appendingPathComponent("STATUS.md")
        let statusContent = (try? String(contentsOf: statusURL, encoding: .utf8)) ?? ""
        let statusIsAnalyzing = statusContent.contains("状态: analyzing")
        let reposReady = fileManager.directoryExists(atPath: workspaceURL.appendingPathComponent("repos").path)
        let scriptReady = fileManager.fileExists(atPath: workspaceURL.appendingPathComponent("scripts/worktree-commands.sh").path)

        return [
            WorkspaceInitializationCheck(
                id: "standard-files",
                label: "标准文件 / Standard files",
                detail: missingFiles.isEmpty ? "已生成 \(generatedFiles.count) 个标准文件和目录。" : "缺失: \(missingFiles.joined(separator: ", "))",
                status: missingFiles.isEmpty ? "pass" : "fail"
            ),
            WorkspaceInitializationCheck(
                id: "status-initial-state",
                label: "初始状态 / Initial status",
                detail: statusIsAnalyzing ? "STATUS.md 已设置为 analyzing。" : "STATUS.md 未识别到 analyzing 初始状态。",
                status: statusIsAnalyzing ? "pass" : "fail"
            ),
            WorkspaceInitializationCheck(
                id: "service-scope",
                label: "服务范围 / Service scope",
                detail: services.isEmpty ? "服务范围待确认，后续 worktree 创建会被阻止。" : "已记录 \(services.count) 个服务。",
                status: services.isEmpty ? "warning" : "pass"
            ),
            WorkspaceInitializationCheck(
                id: "target-branch",
                label: "目标分支 / Target branch",
                detail: targetBranch == "待确认" ? "目标分支待确认，后续 worktree 创建会被阻止。" : "目标分支已记录为 \(targetBranch)。",
                status: targetBranch == "待确认" ? "warning" : "pass"
            ),
            WorkspaceInitializationCheck(
                id: "worktree-readiness",
                label: "Worktree 准备 / Worktree readiness",
                detail: reposReady && scriptReady ? "repos/ 目录和 scripts/worktree-commands.sh 已就绪。" : "repos/ 目录或 worktree 脚本缺失。",
                status: reposReady && scriptReady ? "pass" : "fail"
            )
        ]
    }

    private static func appendAuditEvent(
        request: CreateWorkspaceRequest,
        response: CreateWorkspaceResponse,
        services: [String],
        targetBranch: String
    ) -> NativeAuditAppendFeedback {
        NativeAuditEventStore.appendFeedback(
            auditRoot: request.auditRoot,
            event: AuditEventInput(
                actor: request.actor ?? "Nexus Native",
                action: "workspace.created",
                target: response.path,
                summary: "Created workspace \(request.name)",
                metadata: [
                    "name": request.name,
                    "folder": response.folder,
                    "services": services.joined(separator: ","),
                    "targetBranch": targetBranch,
                    "workspacesRoot": request.workspacesRoot,
                    "sourceReposRoot": request.sourceReposRoot
                ]
            )
        )
    }
}

private extension FileManager {
    func directoryExists(atPath path: String) -> Bool {
        var isDirectory: ObjCBool = false
        return fileExists(atPath: path, isDirectory: &isDirectory) && isDirectory.boolValue
    }
}

private struct WorkspaceInitializationFileSpec {
    let label: String
    let relativePath: String
    let kind: String
}

private let initializationFileSpecs: [WorkspaceInitializationFileSpec] = [
    WorkspaceInitializationFileSpec(label: "Agent guide", relativePath: "AGENTS.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Workspace", relativePath: "workspace.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Status", relativePath: "STATUS.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Services", relativePath: "services.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Branches", relativePath: "branches.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Requirements", relativePath: "requirements.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Acceptance", relativePath: "acceptance.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Changes", relativePath: "changes.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Plan", relativePath: "plan.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Tasks", relativePath: "tasks.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Decisions", relativePath: "decisions.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Handoff", relativePath: "handoff.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Delivery notes", relativePath: "delivery.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "交付记录", relativePath: "交付记录.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Bootstrap report", relativePath: "bootstrap-report.md", kind: "file"),
    WorkspaceInitializationFileSpec(label: "Logs directory", relativePath: "logs", kind: "directory"),
    WorkspaceInitializationFileSpec(label: "SQL directory", relativePath: "sql", kind: "directory"),
    WorkspaceInitializationFileSpec(label: "Repos directory", relativePath: "repos", kind: "directory"),
    WorkspaceInitializationFileSpec(label: "Scripts directory", relativePath: "scripts", kind: "directory"),
    WorkspaceInitializationFileSpec(label: "Worktree script", relativePath: "scripts/worktree-commands.sh", kind: "script")
]

private enum NativeWorkspaceCreationStoreError: LocalizedError {
    case unconfirmed
    case emptyFolder
    case unsafeFolder(String)
    case workspaceAlreadyExists(String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "workspace creation requires explicit confirmation"
        case .emptyFolder:
            return "workspace folder is required"
        case .unsafeFolder(let folder):
            return "workspace folder is not a safe single directory name: \(folder)"
        case .workspaceAlreadyExists(let path):
            return "workspace already exists: \(path)"
        }
    }
}

private func agentsMarkdown(name: String, workspacePath: String, sourceReposRoot: String) -> String {
    """
    # Workspace Agent Guide

    - 需求名称: \(name)
    - 工作区: \(workspacePath)
    - 开发目录: `repos/<service>`
    - 源仓库目录: `\(sourceReposRoot)`

    ## Start Here

    每次继续需求前先读取：`requirements.md`、`acceptance.md`、`changes.md`、`workspace.md`、`STATUS.md`、`services.md`、`branches.md`、`tasks.md`、`handoff.md` 和 `交付记录.md`。

    ## Rules

    - 需求规则、边界、验收标准变化时，优先更新 `requirements.md` 和 `acceptance.md`。
    - 代码改动优先发生在 `repos/<service>` worktree 中。
    - 每次代码、SQL、业务逻辑、接口、DTO、配置或验证变化后，检查并更新 `changes.md` 与 `交付记录.md`。
    - 凡是 `交付记录.md` 任意位置声明实际 SQL 变更，必须在 `sql/` 下同步正式 SQL 文件和回滚 SQL 文件。
    - 交付收尾前必须复核 `acceptance.md`、`交付记录.md` 和 `sql/`：不能只把 SQL 写在交付文档里。
    - 不直接切换源仓库分支，源仓库只作为 worktree 来源。

    """
}

private func workspaceMarkdown(name: String, createdDate: String, targetBranch: String, sourceReposRoot: String) -> String {
    """
    # \(name)

    - 需求名称: \(name)
    - 创建日期: \(createdDate)
    - 当前状态: analyzing
    - 目标分支: \(targetBranch)
    - 源仓库集合: \(sourceReposRoot)

    ## 需求描述

    待补充。

    ## 当前结论

    - 工作区已由 Nexus 创建。
    - 服务范围和目标分支可继续确认。

    """
}

private func statusMarkdown(createdDate: String, services: [String], targetBranch: String, sourceReposRoot: String) -> String {
    """
    # STATUS

    - 状态: analyzing
    - 当前焦点: 需求范围确认
    - 下一步: 确认服务范围、目标分支、是否创建 worktree
    - 更新时间: \(createdDate)

    ## Bootstrap Summary

    - 服务数量: \(services.count)
    - 目标分支: \(targetBranch)
    - 源仓库目录: `\(sourceReposRoot)`
    - Worktree 命令: `scripts/worktree-commands.sh`
    - 创建报告: `bootstrap-report.md`

    ## Blockers

    \(targetBranch == "待确认" ? "- 目标分支待确认时，不自动创建 worktree。" : "- worktree 尚未创建，需要人工确认后执行命令。")

    """
}

private func servicesMarkdown(services: [String], sourceReposRoot: String) -> String {
    let rows = services.isEmpty
        ? "| 待确认 | 待确认 | 待补充 |\n"
        : services.map { "| \($0) | `\(sourceReposRoot)/\($0)` | 初始确认 |\n" }.joined()
    return """
    # Services

    ## 已确认相关

    | 服务 | 源仓库 | 说明 |
    | --- | --- | --- |
    \(rows)
    ## 待验证范围

    | 服务 | 线索 | 说明 |
    | --- | --- | --- |

    """
}

private func branchesMarkdown(services: [String], targetBranch: String, sourceReposRoot: String) -> String {
    let rows = services.isEmpty
        ? "| 待确认 | 待确认 | 待确认 | 待创建 |\n"
        : services.map { "| \($0) | `\(sourceReposRoot)/\($0)` | \(targetBranch) | 待创建 |\n" }.joined()
    return """
    # Branches

    - 目标分支: \(targetBranch)

    | 服务 | 源仓库 | 目标分支 | Worktree |
    | --- | --- | --- | --- |
    \(rows)
    """
}

private func requirementsMarkdown(name: String, targetBranch: String, services: [String]) -> String {
    """
    # Requirements

    ## 需求概览

    - 需求名称: \(name)
    - 目标分支: \(targetBranch)
    - 涉及服务: \(services.isEmpty ? "待确认" : services.joined(separator: ", "))

    ## 业务规则

    | 编号 | 规则 | 来源 | 状态 |
    | --- | --- | --- | --- |
    | R1 | 待补充 | 用户确认 / 需求文档 / 代码现状 | 待确认 |

    ## 边界与不做范围

    | 编号 | 说明 | 原因 | 状态 |
    | --- | --- | --- | --- |
    | O1 | 待补充 | 待补充 | 待确认 |

    ## 兼容规则

    | 编号 | 兼容场景 | 处理方式 | 验收方式 |
    | --- | --- | --- | --- |
    | C1 | 待补充 | 待补充 | 待补充 |

    ## 待确认问题

    | 编号 | 问题 | 影响 | 结论 |
    | --- | --- | --- | --- |
    | Q1 | 待补充 | 待补充 | 待确认 |

    """
}

private func acceptanceMarkdown(name: String) -> String {
    """
    # Acceptance

    ## 验收目标

    - 需求名称: \(name)
    - 验收状态: 待补充

    ## 验收清单

    | 编号 | 对应规则 | 验收方式 | 证据位置 | 状态 |
    | --- | --- | --- | --- | --- |
    | A1 | R1 | 待补充接口/页面/日志/SQL 验证方式 | 待补充 | 待验证 |

    ## 回归范围

    | 场景 | 服务 | 验证方式 | 状态 |
    | --- | --- | --- | --- |
    | 待补充 | 待补充 | 待补充 | 待验证 |

    ## 验收结论

    待补充。

    """
}

private func changesMarkdown(name: String) -> String {
    """
    # Changes

    ## 变更日志

    - 需求名称: \(name)
    - 记录规则: 每次代码、SQL、业务逻辑、接口、DTO、配置或验证变化后追加一行。

    | 时间 | 类型 | 服务 | 文件/模块 | 说明 | 影响交付 |
    | --- | --- | --- | --- | --- | --- |
    | 待补充 | 待补充 | 待补充 | 待补充 | 待补充 | 待确认 |

    ## 待同步事项

    | 事项 | 需要同步到 | 状态 |
    | --- | --- | --- |
    | 待补充 | 交付记录.md / acceptance.md / sql/ | 待确认 |

    """
}

private func planMarkdown() -> String {
    """
    # Plan

    ## 分析步骤

    - [ ] 补齐需求规则
    - [ ] 建立验收清单
    - [ ] 确认涉及服务
    - [ ] 确认目标分支
    - [ ] 创建 worktree
    - [ ] 编码与验证
    - [ ] 记录变更日志
    - [ ] 更新交付记录

    """
}

private func tasksMarkdown() -> String {
    """
    # Tasks

    | 任务 | 状态 | 说明 |
    | --- | --- | --- |
    | 补齐需求规则 | 待办 | 在 requirements.md 中补充业务规则、边界、兼容和待确认问题 |
    | 建立验收清单 | 待办 | 在 acceptance.md 中把规则映射到验证方式和证据 |
    | 确认服务范围 | 待办 | 标记涉及服务和待验证服务 |
    | 确认目标分支 | 待办 | 多服务优先统一分支 |
    | 创建 worktree | 待办 | 分支确认后再执行 |
    | 记录变更日志 | 待办 | 代码/SQL/逻辑变更后更新 changes.md |
    | 更新交付记录 | 待办 | 代码/SQL/逻辑变更后必须更新；SQL 变更必须同步 sql/ 正式与回滚 SQL |

    """
}

private func decisionsMarkdown() -> String {
    """
    # Decisions

    | 时间 | 决策 | 原因 | 影响 |
    | --- | --- | --- | --- |

    """
}

private func handoffMarkdown() -> String {
    """
    # Handoff

    ## 当前状态

    待补充。

    ## 后续继续方式

    请先读取 `AGENTS.md`、`requirements.md`、`acceptance.md`、`changes.md`、`STATUS.md`、`services.md`、`branches.md`、`tasks.md` 和 `交付记录.md`。

    ## 收尾守门

    - `requirements.md` 中的业务规则必须能在 `acceptance.md` 找到对应验收方式。
    - 本轮代码/SQL/逻辑变化必须同步记录到 `changes.md`。
    - 如果 `交付记录.md` 任意位置记录实际 SQL 变更，必须同步检查 `sql/` 下是否已有正式 SQL 文件和回滚 SQL 文件；缺一项都不能视为交付完成。

    """
}

private func deliveryMarkdown() -> String {
    """
    # Delivery Notes

    ## 变更记录

    | 时间 | 类型 | 服务 | 内容 | 验证 |
    | --- | --- | --- | --- | --- |

    """
}

private func deliveryRecordMarkdown(name: String, folder: String, targetBranch: String, services: [String]) -> String {
    let serviceLines = services.isEmpty ? "待确认。" : services.map { "- \($0)" }.joined(separator: "\n")
    return """
    # 交付记录

    ## 需求信息

    - 需求名称: \(name)
    - 工作区: \(folder)
    - 分支: \(targetBranch)

    ## 涉及服务

    \(serviceLines)

    ## 代码变更

    暂无。

    ## SQL 变更

    - 是否有 SQL 变更：暂无。
    - 正式 SQL 文件：无
    - 回滚 SQL 文件：无
    - 文件规则：一旦本文档任意位置记录实际 SQL 变更，必须同步 `sql/` 下正式 SQL 与回滚 SQL 文件；不能只把 SQL 留在本文档中。

    ## 新增逻辑

    暂无。

    ## 验证结果

    暂无。

    ## 遗留风险

    - 创建后需要确认服务范围、分支和 worktree 状态。

    """
}

private func bootstrapReportMarkdown(
    name: String,
    folder: String,
    workspacePath: String,
    services: [String],
    targetBranch: String,
    sourceReposRoot: String,
    createdDate: String
) -> String {
    let serviceLines = services.isEmpty
        ? "- 服务范围待确认"
        : services.map { "- \($0): `\(sourceReposRoot)/\($0)` -> `repos/\($0)`" }.joined(separator: "\n")
    let initialRisks = targetBranch == "待确认"
        ? "- 目标分支未确认\n- worktree 尚未创建"
        : "- worktree 尚未创建"
    return """
    # Bootstrap Report

    - 需求名称: \(name)
    - 工作区: \(folder)
    - 创建日期: \(createdDate)
    - 目标分支: \(targetBranch)
    - 工作区路径: `\(workspacePath)`
    - 源仓库目录: `\(sourceReposRoot)`

    ## 服务范围

    \(serviceLines)

    ## 初始风险

    \(initialRisks)

    ## 下一步

    - [ ] 补充 `requirements.md` 的业务规则、边界和待确认问题。
    - [ ] 补充 `acceptance.md` 的验收方式和证据要求。
    - [ ] 确认目标分支。
    - [ ] 复核 `scripts/worktree-commands.sh` 后创建 worktree。
    - [ ] 编码或 SQL 变更后更新 `changes.md` 和 `交付记录.md`。
    - [ ] 若 `交付记录.md` 任意位置声明 SQL 变更，同步 `sql/` 下正式 SQL 和回滚 SQL 文件。

    """
}

private func worktreeCommandsMarkdown(
    workspaceURL: URL,
    services: [String],
    targetBranch: String,
    sourceReposRoot: String
) -> String {
    var lines = [
        "#!/usr/bin/env bash",
        "set -euo pipefail",
        "",
        "# Review before running. Prefer Nexus confirmed worktree setup when available.",
        ""
    ]
    if services.isEmpty || targetBranch == "待确认" {
        lines.append("# 服务范围或目标分支待确认，暂不生成可执行 worktree 命令。")
    } else {
        for service in services {
            lines.append("# \(service)")
            lines.append("git -C '\(sourceReposRoot)/\(service)' fetch origin")
            lines.append("git -C '\(sourceReposRoot)/\(service)' worktree add '\(workspaceURL.appendingPathComponent("repos/\(service)").path)' '\(targetBranch)'")
            lines.append("")
        }
    }
    return lines.joined(separator: "\n") + "\n"
}
