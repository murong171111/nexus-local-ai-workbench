import CryptoKit
import Foundation
import NexusBridge

enum NativeDemandIntakeEntryState: Hashable {
    case missing
    case directory
    case regularUTF8(sha256: String, byteCount: Int)
    case invalid(reason: String)

    var label: String {
        switch self {
        case .missing:
            return "missing"
        case .directory:
            return "directory"
        case .regularUTF8(let sha256, let byteCount):
            return "regular UTF-8 \(byteCount) bytes sha256=\(sha256)"
        case .invalid(let reason):
            return "invalid: \(reason)"
        }
    }
}

struct NativeDemandIntakeFilePlan: Hashable, Identifiable {
    let key: String
    let label: String
    let filename: String
    let path: String
    let expectedState: NativeDemandIntakeEntryState
    let template: String

    var id: String { key }
}

struct NativeDemandIntakeInitializationPlan: Hashable {
    let workspacePath: String
    let demandDirectoryPath: String
    let demandName: String
    let lanhuLink: String
    let notes: String
    let expectedWorkspaceState: NativeDemandIntakeEntryState
    let expectedDemandDirectoryState: NativeDemandIntakeEntryState
    let filePlans: [NativeDemandIntakeFilePlan]
    let blockerSummary: String?

    var createdFiles: [String] {
        filePlans.compactMap { $0.expectedState == .missing ? $0.filename : nil }
    }

    var canInitialize: Bool {
        blockerSummary == nil && !createdFiles.isEmpty
    }

    var summary: String {
        if let blockerSummary {
            return blockerSummary
        }
        let preservedCount = filePlans.count - createdFiles.count
        return "will create \(createdFiles.joined(separator: ", ")); preserve \(preservedCount) existing files"
    }
}

typealias NativeDemandIntakeFileWriter = (Data, URL) throws -> Void

private struct NativeDemandIntakeCreatedFile {
    let url: URL
    let expectedState: NativeDemandIntakeEntryState
}

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

    static func inspectEntry(
        at path: String,
        fileManager: FileManager = .default
    ) -> NativeDemandIntakeEntryState {
        let url = expandedURL(for: path)
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try fileManager.attributesOfItem(atPath: url.path)
        } catch let error as NSError
            where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
            return .missing
        } catch {
            return .invalid(reason: "entry is unreadable: \(url.path): \(error.localizedDescription)")
        }

        guard let type = attributes[.type] as? FileAttributeType else {
            return .invalid(reason: "entry has no file type: \(url.path)")
        }
        switch type {
        case .typeDirectory:
            return .directory
        case .typeRegular:
            do {
                let data = try Data(contentsOf: url)
                guard String(data: data, encoding: .utf8) != nil else {
                    return .invalid(reason: "entry is not valid UTF-8: \(url.path)")
                }
                let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
                return .regularUTF8(sha256: sha256, byteCount: data.count)
            } catch {
                return .invalid(reason: "entry is unreadable: \(url.path): \(error.localizedDescription)")
            }
        default:
            return .invalid(reason: "entry is not a real directory or regular UTF-8 file: \(url.path)")
        }
    }

    static func makeInitializationPlan(
        workspacePath: String,
        demandName: String,
        lanhuLink: String,
        notes: String,
        fileManager: FileManager = .default
    ) -> NativeDemandIntakeInitializationPlan {
        let workspaceURL = expandedURL(for: workspacePath)
        let demandURL = workspaceURL.appendingPathComponent(directoryName, isDirectory: true)
        let normalizedDemandName = nonEmpty(demandName, fallback: "待补充")
        let normalizedLanhuLink = nonEmpty(lanhuLink, fallback: "待补充")
        let normalizedNotes = nonEmpty(notes, fallback: "待补充")
        let workspaceState = inspectEntry(at: workspaceURL.path, fileManager: fileManager)
        let demandState = inspectEntry(at: demandURL.path, fileManager: fileManager)
        let filePlans = files.map { file in
            let fileURL = demandURL.appendingPathComponent(file.filename, isDirectory: false)
            return NativeDemandIntakeFilePlan(
                key: file.key,
                label: file.label,
                filename: file.filename,
                path: fileURL.path,
                expectedState: inspectEntry(at: fileURL.path, fileManager: fileManager),
                template: template(
                    for: file.key,
                    demandName: normalizedDemandName,
                    lanhuLink: normalizedLanhuLink,
                    notes: normalizedNotes
                )
            )
        }
        let blockerSummary: String?
        switch workspaceState {
        case .directory:
            switch demandState {
            case .missing, .directory:
                if let filePlan = filePlans.first(where: {
                    if case .invalid = $0.expectedState {
                        return true
                    }
                    if case .directory = $0.expectedState {
                        return true
                    }
                    return false
                }) {
                    blockerSummary = "demand intake file is not a regular UTF-8 file: \(filePlan.path)"
                } else if filePlans.allSatisfy({
                    if case .regularUTF8 = $0.expectedState {
                        return true
                    }
                    return false
                }) {
                    blockerSummary = "demand intake is already complete; no files will be created"
                } else {
                    blockerSummary = nil
                }
            default:
                blockerSummary = "demand intake path is not a real directory: \(demandURL.path)"
            }
        default:
            blockerSummary = "workspace path is not a real directory: \(workspaceURL.path)"
        }

        return NativeDemandIntakeInitializationPlan(
            workspacePath: workspaceURL.path,
            demandDirectoryPath: demandURL.path,
            demandName: normalizedDemandName,
            lanhuLink: normalizedLanhuLink,
            notes: normalizedNotes,
            expectedWorkspaceState: workspaceState,
            expectedDemandDirectoryState: demandState,
            filePlans: filePlans,
            blockerSummary: blockerSummary
        )
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
        let plan = makeInitializationPlan(
            workspacePath: workspacePath,
            demandName: demandName,
            lanhuLink: lanhuLink,
            notes: notes,
            fileManager: fileManager
        )
        return try initialize(
            plan: plan,
            confirmed: confirmed,
            auditRoot: auditRoot,
            actor: actor,
            fileManager: fileManager
        )
    }

    static func initialize(
        plan: NativeDemandIntakeInitializationPlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default
    ) throws -> InitializeDemandIntakeResponse {
        try initialize(
            plan: plan,
            confirmed: confirmed,
            auditRoot: auditRoot,
            actor: actor,
            fileManager: fileManager,
            fileWriter: { data, url in
                try data.write(to: url, options: [.withoutOverwriting])
            }
        )
    }

    static func initialize(
        plan: NativeDemandIntakeInitializationPlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        fileManager: FileManager = .default,
        fileWriter: NativeDemandIntakeFileWriter
    ) throws -> InitializeDemandIntakeResponse {
        guard confirmed else {
            throw NativeDemandIntakeStoreError.unconfirmed
        }
        guard plan.canInitialize else {
            throw NativeDemandIntakeStoreError.planNotWritable(plan.blockerSummary ?? "no demand intake files need creation")
        }

        let workspaceURL = expandedURL(for: plan.workspacePath)
        let demandURL = workspaceURL.appendingPathComponent(directoryName, isDirectory: true)
        try validatePlanShape(plan, workspaceURL: workspaceURL, demandURL: demandURL)
        try requireExpectedEntryState(
            at: workspaceURL.path,
            expected: plan.expectedWorkspaceState,
            fileManager: fileManager
        )
        try requireExpectedEntryState(
            at: demandURL.path,
            expected: plan.expectedDemandDirectoryState,
            fileManager: fileManager
        )
        for filePlan in plan.filePlans {
            try requireExpectedEntryState(
                at: filePlan.path,
                expected: filePlan.expectedState,
                fileManager: fileManager
            )
        }

        var createdFiles: [NativeDemandIntakeCreatedFile] = []
        var createdDemandDirectory = false

        do {
            if plan.expectedDemandDirectoryState == .missing {
                try fileManager.createDirectory(at: demandURL, withIntermediateDirectories: false)
                createdDemandDirectory = true
                try requireExpectedEntryState(
                    at: demandURL.path,
                    expected: .directory,
                    fileManager: fileManager
                )
            }

            for filePlan in plan.filePlans where filePlan.expectedState == .missing {
                let data = Data(filePlan.template.utf8)
                try fileWriter(data, URL(fileURLWithPath: filePlan.path))
                createdFiles.append(
                    NativeDemandIntakeCreatedFile(
                        url: URL(fileURLWithPath: filePlan.path),
                        expectedState: regularUTF8State(for: data)
                    )
                )
            }

            let resultStatus = status(for: workspaceURL, fileManager: fileManager)
            guard resultStatus.ready else {
                throw NativeDemandIntakeStoreError.finalStatusNotReady(resultStatus.directoryPath)
            }

            let response = InitializeDemandIntakeResponse(
                status: resultStatus,
                createdFiles: plan.createdFiles
            )
            let audit = appendAuditEvent(
                workspacePath: workspaceURL.path,
                demandName: plan.demandName,
                lanhuLink: plan.lanhuLink,
                response: response,
                auditRoot: auditRoot,
                actor: actor
            )
            return InitializeDemandIntakeResponse(
                status: response.status,
                createdFiles: response.createdFiles,
                auditEventID: audit.response?.event.id,
                auditEventPath: audit.response?.path,
                auditError: audit.error
            )
        } catch {
            let remainingPaths = rollback(
                createdFiles: createdFiles,
                createdDemandDirectory: createdDemandDirectory,
                demandURL: demandURL,
                fileManager: fileManager
            )
            guard remainingPaths.isEmpty else {
                throw NativeDemandIntakeStoreError.rollbackFailed(
                    writeFailure: error.localizedDescription,
                    remainingPaths: remainingPaths
                )
            }
            throw error
        }
    }

    private static func validatePlanShape(
        _ plan: NativeDemandIntakeInitializationPlan,
        workspaceURL: URL,
        demandURL: URL
    ) throws {
        guard plan.workspacePath == workspaceURL.path,
              plan.demandDirectoryPath == demandURL.path,
              plan.filePlans.count == files.count else {
            throw NativeDemandIntakeStoreError.malformedPlan(
                "workspace or file count does not match the fixed demand intake layout"
            )
        }

        for (definition, filePlan) in zip(files, plan.filePlans) {
            let expectedPath = demandURL.appendingPathComponent(definition.filename, isDirectory: false).path
            guard filePlan.key == definition.key,
                  filePlan.label == definition.label,
                  filePlan.filename == definition.filename,
                  filePlan.path == expectedPath else {
                throw NativeDemandIntakeStoreError.malformedPlan(
                    "file plan does not match the fixed demand intake layout"
                )
            }
        }
    }

    private static func requireExpectedEntryState(
        at path: String,
        expected: NativeDemandIntakeEntryState,
        fileManager: FileManager
    ) throws {
        let current = inspectEntry(at: path, fileManager: fileManager)
        guard current == expected else {
            throw NativeDemandIntakeStoreError.entryChanged(
                path: expandedURL(for: path).path,
                expected: expected.label,
                current: current.label
            )
        }
    }

    private static func regularUTF8State(for data: Data) -> NativeDemandIntakeEntryState {
        let sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        return .regularUTF8(sha256: sha256, byteCount: data.count)
    }

    private static func rollback(
        createdFiles: [NativeDemandIntakeCreatedFile],
        createdDemandDirectory: Bool,
        demandURL: URL,
        fileManager: FileManager
    ) -> [String] {
        var remainingPaths: [String] = []

        for file in createdFiles.reversed() {
            let current = inspectEntry(at: file.url.path, fileManager: fileManager)
            guard current != .missing else { continue }
            guard current == file.expectedState else {
                remainingPaths.append(file.url.path)
                continue
            }
            do {
                try fileManager.removeItem(at: file.url)
            } catch {
                remainingPaths.append(file.url.path)
            }
        }

        if createdDemandDirectory {
            do {
                let contents = try fileManager.contentsOfDirectory(
                    at: demandURL,
                    includingPropertiesForKeys: nil,
                    options: []
                )
                if contents.isEmpty {
                    try fileManager.removeItem(at: demandURL)
                } else {
                    remainingPaths.append(demandURL.path)
                }
            } catch let error as NSError
                where error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoSuchFileError {
                // A concurrent cleanup already removed the directory.
            } catch {
                remainingPaths.append(demandURL.path)
            }
        }

        return remainingPaths
    }

    private static func appendAuditEvent(
        workspacePath: String,
        demandName: String,
        lanhuLink: String,
        response: InitializeDemandIntakeResponse,
        auditRoot: String?,
        actor: String?
    ) -> NativeAuditAppendFeedback {
        NativeAuditEventStore.appendFeedback(
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
        let url = expandedURL(for: workspacePath)
        switch inspectEntry(at: url.path, fileManager: fileManager) {
        case .missing:
            throw NativeDemandIntakeStoreError.workspaceMissing(url.path)
        case .directory:
            return url
        default:
            throw NativeDemandIntakeStoreError.workspaceNotDirectory(url.path)
        }
    }

    private static func status(for workspaceURL: URL, fileManager: FileManager) -> DemandIntakeStatus {
        let demandURL = workspaceURL.appendingPathComponent(directoryName, isDirectory: true)
        let exists = inspectEntry(at: demandURL.path, fileManager: fileManager) == .directory
        let fileStatuses = files.map { file in
            let path = demandURL.appendingPathComponent(file.filename, isDirectory: false).path
            let fileExists: Bool
            if case .regularUTF8 = inspectEntry(at: path, fileManager: fileManager) {
                fileExists = true
            } else {
                fileExists = false
            }
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

    private static func expandedURL(for path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
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
    case planNotWritable(String)
    case malformedPlan(String)
    case entryChanged(path: String, expected: String, current: String)
    case finalStatusNotReady(String)
    case rollbackFailed(writeFailure: String, remainingPaths: [String])

    var errorDescription: String? {
        switch self {
        case .unconfirmed:
            return "demand intake initialization requires explicit confirmation"
        case .workspaceMissing(let path):
            return "workspace does not exist: \(path)"
        case .workspaceNotDirectory(let path):
            return "workspace path is not a real directory: \(path)"
        case .demandPathNotDirectory(let path):
            return "demand intake path exists but is not a directory: \(path)"
        case .filePathNotFile(let path):
            return "demand intake file path exists but is not a file: \(path)"
        case .planNotWritable(let reason):
            return "demand intake initialization plan cannot write: \(reason)"
        case .malformedPlan(let reason):
            return "demand intake initialization plan is invalid: \(reason)"
        case .entryChanged(let path, let expected, let current):
            return "demand intake entry changed since confirmation: \(path); expected \(expected), found \(current)"
        case .finalStatusNotReady(let path):
            return "demand intake initialization did not produce ready evidence: \(path)"
        case .rollbackFailed(let writeFailure, let remainingPaths):
            return "demand intake initialization failed and cleanup needs review: \(writeFailure); remaining \(remainingPaths.joined(separator: ", "))"
        }
    }
}
