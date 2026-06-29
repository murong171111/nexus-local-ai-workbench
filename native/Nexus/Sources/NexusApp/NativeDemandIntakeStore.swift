import Foundation
import NexusBridge

enum NativeDemandIntakeStore {
    private static let directoryName = "需求"
    private static let files: [(key: String, label: String, filename: String)] = [
        ("requirement", "需求确认卡", "requirement.md"),
        ("questions", "待确认问题", "questions.md"),
        ("scope", "开发范围", "scope.md"),
        ("tasks", "需求列表", "tasks.md"),
        ("delivery", "需求交付", "delivery.md")
    ]

    static func status(workspacePath: String, fileManager: FileManager = .default) throws -> DemandIntakeStatus {
        let workspaceURL = try checkedWorkspaceURL(workspacePath, fileManager: fileManager)
        return status(for: workspaceURL, fileManager: fileManager)
    }

    static func initialize(
        workspacePath: String,
        demandName: String,
        lanhuLink: String,
        notes: String,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default
    ) throws -> InitializeDemandIntakeResponse {
        guard confirmed else {
            throw NativeDemandIntakeStoreError.unconfirmed
        }

        let workspaceURL = try checkedWorkspaceURL(workspacePath, fileManager: fileManager)
        let demandURL = workspaceURL.appendingPathComponent(directoryName, isDirectory: true)
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: demandURL.path, isDirectory: &isDirectory), !isDirectory.boolValue {
            throw NativeDemandIntakeStoreError.demandPathNotDirectory(demandURL.path)
        }

        try fileManager.createDirectory(at: demandURL, withIntermediateDirectories: true)
        for file in files {
            let fileURL = demandURL.appendingPathComponent(file.filename, isDirectory: false)
            var fileIsDirectory: ObjCBool = false
            if fileManager.fileExists(atPath: fileURL.path, isDirectory: &fileIsDirectory), fileIsDirectory.boolValue {
                throw NativeDemandIntakeStoreError.filePathNotFile(fileURL.path)
            }
        }

        let normalizedDemandName = nonEmpty(demandName, fallback: "待补充")
        let normalizedLanhuLink = nonEmpty(lanhuLink, fallback: "待补充")
        let normalizedNotes = nonEmpty(notes, fallback: "待补充")
        var createdFiles: [String] = []

        for file in files {
            let fileURL = demandURL.appendingPathComponent(file.filename, isDirectory: false)
            guard !fileManager.fileExists(atPath: fileURL.path) else {
                continue
            }
            try template(
                for: file.key,
                demandName: normalizedDemandName,
                lanhuLink: normalizedLanhuLink,
                notes: normalizedNotes
            )
            .write(to: fileURL, atomically: true, encoding: .utf8)
            createdFiles.append(file.filename)
        }

        let response = InitializeDemandIntakeResponse(
            status: status(for: workspaceURL, fileManager: fileManager),
            createdFiles: createdFiles
        )
        appendAuditEvent(
            workspacePath: workspaceURL.path,
            demandName: normalizedDemandName,
            lanhuLink: normalizedLanhuLink,
            response: response,
            auditRoot: auditRoot,
            actor: actor
        )
        return response
    }

    private static func appendAuditEvent(
        workspacePath: String,
        demandName: String,
        lanhuLink: String,
        response: InitializeDemandIntakeResponse,
        auditRoot: String?,
        actor: String?
    ) {
        guard let auditRoot = auditRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
              !auditRoot.isEmpty else {
            return
        }
        _ = try? NativeAuditEventStore.append(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: actor ?? "Nexus Native",
                action: "demand_intake.initialized",
                target: response.status.directoryPath,
                summary: "Initialized demand intake files for \(demandName)",
                metadata: [
                    "workspacePath": workspacePath,
                    "demandName": demandName,
                    "lanhuLink": lanhuLink,
                    "createdFiles": response.createdFiles.joined(separator: ","),
                    "missingCount": "\(response.status.missingCount)"
                ]
            )
        )
    }

    private static func checkedWorkspaceURL(_ workspacePath: String, fileManager: FileManager) throws -> URL {
        let url = URL(fileURLWithPath: (workspacePath as NSString).expandingTildeInPath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDirectory) else {
            throw NativeDemandIntakeStoreError.workspaceMissing(url.path)
        }
        guard isDirectory.boolValue else {
            throw NativeDemandIntakeStoreError.workspaceNotDirectory(url.path)
        }
        return url
    }

    private static func status(for workspaceURL: URL, fileManager: FileManager) -> DemandIntakeStatus {
        let demandURL = workspaceURL.appendingPathComponent(directoryName, isDirectory: true)
        var isDirectory: ObjCBool = false
        let exists = fileManager.fileExists(atPath: demandURL.path, isDirectory: &isDirectory) && isDirectory.boolValue
        let fileStatuses = files.map { file in
            let path = demandURL.appendingPathComponent(file.filename, isDirectory: false).path
            var fileIsDirectory: ObjCBool = false
            let fileExists = fileManager.fileExists(atPath: path, isDirectory: &fileIsDirectory) && !fileIsDirectory.boolValue
            return DemandIntakeFileStatus(
                key: file.key,
                label: file.label,
                filename: file.filename,
                path: path,
                exists: fileExists
            )
        }
        let missingCount = fileStatuses.filter { !$0.exists }.count
        return DemandIntakeStatus(
            directoryPath: demandURL.path,
            exists: exists,
            ready: exists && missingCount == 0,
            missingCount: missingCount,
            files: fileStatuses
        )
    }

    private static func nonEmpty(_ value: String, fallback: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? fallback : trimmed
    }

    private static func template(for key: String, demandName: String, lanhuLink: String, notes: String) -> String {
        switch key {
        case "requirement":
            return "# 需求确认卡：\(demandName)\n\n## 1. 需求目标\n\n- 待整理。\n\n## 2. 页面和入口\n\n- 页面：待确认\n- 入口：待确认\n- 角色/权限：待确认\n\n## 3. 用户流程\n\n1. 待整理。\n\n## 4. UI 与交互规则\n\n- 字段：待确认\n- 按钮：待确认\n- 状态：待确认\n- 校验：待确认\n- 空状态/异常：待确认\n\n## 5. 已确认需求点\n\n- 待整理。\n\n## 6. 推断内容\n\n- 暂无。\n\n## 7. 待确认问题\n\n- P0: 待整理\n- P1: 待整理\n- P2: 待整理\n\n## 8. 建议开发范围\n\n- 本次建议实现：待确认\n- 暂不实现：待确认\n\n## 9. 验收标准\n\n- 待整理。\n\n## 输入材料\n\n- 蓝湖链接：\(lanhuLink)\n\n### 补充说明\n\n\(notes)\n"
        case "questions":
            return "# 待确认问题：\(demandName)\n\n## P0 阻塞开发\n\n- [ ] 待整理。\n\n## P1 可先做主流程但影响边界\n\n- [ ] 待整理。\n\n## P2 不阻塞开发的细节\n\n- [ ] 待整理。\n\n## 结论\n\n- P0 清零前不要进入编码。\n"
        case "scope":
            return "# 本次开发范围：\(demandName)\n\n## 已确认并实现\n\n- 待确认。\n\n## 暂不实现\n\n- 待确认。\n\n## 仍待确认\n\n- 待确认。\n\n## 进入开发条件\n\n- [ ] requirement.md 已整理。\n- [ ] questions.md 中 P0 已清零或有明确处理结论。\n- [ ] 本文件已冻结本次开发范围。\n"
        case "tasks":
            return "# 需求列表：\(demandName)\n\n> 由需求预检阶段维护。后续开发按未完成需求顺序推进，完成后回写状态。\n\n| 需求点 | 状态 | 优先级 | 来源 | 说明 |\n| --- | --- | --- | --- | --- |\n| 整理 requirement.md | 待办 | P0 | 需求预检 | 从蓝湖材料和补充说明提炼需求确认卡 |\n| 整理 questions.md | 待办 | P0 | 需求预检 | 按 P0/P1/P2 分级缺口 |\n| 冻结 scope.md | 待办 | P0 | 产品确认 | P0 清零后确认开发范围 |\n\n## 开发顺序规则\n\n- 优先处理状态为 `进行中` 或 `待办` 的 P0/P1 需求点。\n- 开发前先确认 `scope.md` 已冻结。\n- 完成需求点后，将状态更新为 `已完成`，并在 delivery.md 或 交付记录.md 补充结果。\n"
        case "delivery":
            return "# 需求交付记录：\(demandName)\n\n## 预检结论\n\n- 待整理。\n\n## 范围确认\n\n- 待整理。\n\n## 开发与验证记录\n\n- 暂无。\n\n## 遗留问题\n\n- 暂无。\n"
        default:
            return "# Document\n\n待补充。\n"
        }
    }
}

private enum NativeDemandIntakeStoreError: LocalizedError {
    case unconfirmed
    case workspaceMissing(String)
    case workspaceNotDirectory(String)
    case demandPathNotDirectory(String)
    case filePathNotFile(String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "demand intake initialization requires explicit confirmation"
        case .workspaceMissing(let path):
            return "workspace does not exist: \(path)"
        case .workspaceNotDirectory(let path):
            return "workspace path is not a directory: \(path)"
        case .demandPathNotDirectory(let path):
            return "demand intake path exists but is not a directory: \(path)"
        case .filePathNotFile(let path):
            return "demand intake file path exists but is not a file: \(path)"
        }
    }
}
