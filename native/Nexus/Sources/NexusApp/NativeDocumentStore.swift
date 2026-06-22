import Foundation
import NexusBridge

enum NativeDocumentStore {
    private static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkdn"]

    static func read(path: String, fileManager: FileManager = .default) throws -> DocumentSnapshot {
        let url = expandedURL(for: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let ext = url.pathExtension.lowercased()
        return DocumentSnapshot(
            path: url.path,
            name: url.lastPathComponent,
            extension: ext,
            isMarkdown: markdownExtensions.contains(ext),
            content: content
        )
    }

    static func createWorkspaceDocument(
        workspacePath: String,
        documentKey: String,
        relativePath: String,
        confirmed: Bool,
        fileManager: FileManager = .default
    ) throws -> CreateWorkspaceDocumentResponse {
        guard confirmed else {
            throw NativeDocumentStoreError.unconfirmed
        }

        let workspaceURL = expandedURL(for: workspacePath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: workspaceURL.path, isDirectory: &isDirectory) else {
            throw NativeDocumentStoreError.workspaceMissing(workspaceURL.path)
        }
        guard isDirectory.boolValue else {
            throw NativeDocumentStoreError.workspaceNotDirectory(workspaceURL.path)
        }

        let normalizedRelativePath = try standardRelativePath(documentKey: documentKey, relativePath: relativePath)
        let documentURL = workspaceURL.appendingPathComponent(normalizedRelativePath, isDirectory: false)
        var documentIsDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: documentURL.path, isDirectory: &documentIsDirectory) {
            guard !documentIsDirectory.boolValue else {
                throw NativeDocumentStoreError.documentPathNotFile(documentURL.path)
            }
            return CreateWorkspaceDocumentResponse(
                path: documentURL.path,
                documentKey: documentKey,
                relativePath: normalizedRelativePath,
                created: false,
                alreadyExists: true
            )
        }

        let parentURL = documentURL.deletingLastPathComponent()
        try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        try template(for: documentKey).write(to: documentURL, atomically: true, encoding: .utf8)
        return CreateWorkspaceDocumentResponse(
            path: documentURL.path,
            documentKey: documentKey,
            relativePath: normalizedRelativePath,
            created: true,
            alreadyExists: false
        )
    }

    private static func expandedURL(for path: String) -> URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
    }

    private static func standardRelativePath(documentKey: String, relativePath: String) throws -> String {
        guard let expected = expectedRelativePaths[documentKey] else {
            throw NativeDocumentStoreError.unsupportedDocumentKey(documentKey)
        }
        let trimmed = relativePath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw NativeDocumentStoreError.missingRelativePath
        }

        guard !(trimmed as NSString).isAbsolutePath else {
            throw NativeDocumentStoreError.absoluteRelativePath
        }
        let components = trimmed.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !components.contains("..") else {
            throw NativeDocumentStoreError.parentDirectoryRelativePath
        }
        let normalized = components.filter { $0 != "." }.joined(separator: "/")
        guard normalized == expected else {
            throw NativeDocumentStoreError.relativePathMismatch(documentKey: documentKey, expected: expected)
        }
        return expected
    }

    private static let expectedRelativePaths: [String: String] = [
        "workspace": "workspace.md",
        "status": "STATUS.md",
        "services": "services.md",
        "branches": "branches.md",
        "requirements": "requirements.md",
        "acceptance": "acceptance.md",
        "changes": "changes.md",
        "tasks": "tasks.md",
        "delivery": "交付记录.md",
        "handoff": "handoff.md",
        "bootstrap": "bootstrap-report.md",
        "worktreeScript": "scripts/worktree-commands.sh"
    ]

    private static func template(for documentKey: String) -> String {
        switch documentKey {
        case "workspace":
            return "# Workspace\n\n- 需求名称: 待补充\n- 当前状态: analyzing\n- 目标分支: 待确认\n- 源仓库集合: 待确认\n\n## 需求范围\n\n待补充。\n"
        case "status":
            return "# Status\n\n- 当前状态: analyzing\n- 下一步: 补齐工作区文档\n- 更新时间: 待补充\n\n## Blockers\n\n- 文档由 Nexus 恢复流程创建，请补充真实状态。\n"
        case "services":
            return "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n"
        case "branches":
            return "# Branches\n\n| 服务 | 目标分支 | 当前分支 | 说明 |\n| --- | --- | --- | --- |\n"
        case "requirements":
            return "# Requirements\n\n## 需求概览\n\n- 需求名称: 待补充\n- 目标分支: 待确认\n- 涉及服务: 待确认\n\n## 业务规则\n\n| 编号 | 规则 | 来源 | 状态 |\n| --- | --- | --- | --- |\n| R1 | 待补充 | 待补充 | 待确认 |\n\n## 边界与不做范围\n\n| 编号 | 说明 | 原因 | 状态 |\n| --- | --- | --- | --- |\n\n## 兼容规则\n\n| 编号 | 兼容场景 | 处理方式 | 验收方式 |\n| --- | --- | --- | --- |\n\n## 待确认问题\n\n| 编号 | 问题 | 影响 | 结论 |\n| --- | --- | --- | --- |\n"
        case "acceptance":
            return "# Acceptance\n\n## 验收目标\n\n- 验收状态: 待补充\n\n## 验收清单\n\n| 编号 | 对应规则 | 验收方式 | 证据位置 | 状态 |\n| --- | --- | --- | --- | --- |\n| A1 | R1 | 待补充 | 待补充 | 待验证 |\n\n## 回归范围\n\n| 场景 | 服务 | 验证方式 | 状态 |\n| --- | --- | --- | --- |\n\n## 验收结论\n\n待补充。\n"
        case "changes":
            return "# Changes\n\n## 变更日志\n\n| 时间 | 类型 | 服务 | 文件/模块 | 说明 | 影响交付 |\n| --- | --- | --- | --- | --- | --- |\n| 待补充 | 待补充 | 待补充 | 待补充 | 待补充 | 待确认 |\n"
        case "tasks":
            return "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n"
        case "delivery":
            return "# 交付记录\n\n## 需求要点\n\n待补充。\n\n## 涉及服务\n\n待补充。\n\n## SQL / 配置\n\n- 是否有 SQL 变动：无\n- 正式 SQL 文件：无\n- 回滚 SQL 文件：无\n- 文件规则：如本文档任意位置记录 SQL 变更，或本段落记录 `变更类型：DDL/DML`、影响表、新增字段、回填脚本、数据修复等变更元数据，必须同步 `sql/` 下正式 SQL 与回滚 SQL 文件。\n\n## 验证记录\n\n待补充。\n\n## 风险与后续\n\n待补充。\n"
        case "handoff":
            return "# Handoff\n\n## Codex 上下文\n\n待补充。\n\n## 下一步\n\n- 读取 requirements.md、acceptance.md、changes.md、workspace.md、STATUS.md、services.md、branches.md、tasks.md 和交付记录。\n"
        case "bootstrap":
            return "# Bootstrap Report\n\n- 状态: 待复核\n- 说明: 该文件由 Nexus 文档恢复流程创建，请补充真实初始化记录。\n"
        case "worktreeScript":
            return "#!/usr/bin/env bash\nset -euo pipefail\n\n# TODO: Regenerate worktree commands from Nexus after services and target branch are confirmed.\n"
        default:
            return "# Document\n\n待补充。\n"
        }
    }
}

private enum NativeDocumentStoreError: LocalizedError {
    case unconfirmed
    case workspaceMissing(String)
    case workspaceNotDirectory(String)
    case documentPathNotFile(String)
    case unsupportedDocumentKey(String)
    case missingRelativePath
    case absoluteRelativePath
    case parentDirectoryRelativePath
    case relativePathMismatch(documentKey: String, expected: String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "workspace document creation requires explicit confirmation"
        case .workspaceMissing(let path):
            return "workspace does not exist: \(path)"
        case .workspaceNotDirectory(let path):
            return "workspace is not a directory: \(path)"
        case .documentPathNotFile(let path):
            return "document path exists but is not a file: \(path)"
        case .unsupportedDocumentKey(let documentKey):
            return "unsupported workspace document key: \(documentKey)"
        case .missingRelativePath:
            return "workspace document relative path is required"
        case .absoluteRelativePath:
            return "workspace document path must be relative"
        case .parentDirectoryRelativePath:
            return "workspace document path cannot contain parent directories"
        case .relativePathMismatch(let documentKey, let expected):
            return "workspace document key \(documentKey) must use relative path \(expected)"
        }
    }
}
