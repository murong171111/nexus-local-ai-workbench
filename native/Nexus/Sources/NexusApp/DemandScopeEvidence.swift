import Foundation
import NexusBridge

struct DemandIntakeReadinessCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
}

struct DemandIntakeReadinessEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let evidence: [String]
    let checks: [DemandIntakeReadinessCheck]
    let unresolvedP0Count: Int
    let requirementHasContent: Bool
    let scopeFrozen: Bool
    let requirementTasksReady: Bool

    var ready: Bool {
        status == .ready
    }

    var blockerChecks: [DemandIntakeReadinessCheck] {
        checks.filter { $0.status == .blocked || $0.status == .review }
    }

    static func resolve(status: DemandIntakeStatus, workspace: WorkspaceSummary) -> DemandIntakeReadinessEvidence {
        if !status.exists {
            return DemandIntakeReadinessEvidence(
                status: .blocked,
                reason: "当前工作区还没有 需求/ 目录。先初始化需求预检，再整理蓝湖材料和补充说明。",
                evidence: ["需求/"],
                checks: [
                    DemandIntakeReadinessCheck(
                        id: "directory",
                        label: "需求目录 / Demand folder",
                        detail: "固定目录 需求/ 尚未创建。",
                        status: .blocked,
                        systemImage: "folder.badge.plus",
                        path: status.directoryPath
                    )
                ],
                unresolvedP0Count: 0,
                requirementHasContent: false,
                scopeFrozen: false,
                requirementTasksReady: false
            )
        }

        if !status.ready {
            let missingFiles = status.files.filter { !$0.exists }
            return DemandIntakeReadinessEvidence(
                status: .review,
                reason: "需求目录已存在，但仍缺 \(status.missingCount) 个固定文件。先补齐 requirement、questions、scope、tasks 和 delivery。",
                evidence: status.files.map { "需求/\($0.filename)" },
                checks: missingFiles.map { file in
                    DemandIntakeReadinessCheck(
                        id: "missing-\(file.key)",
                        label: file.label,
                        detail: "\(file.filename) 尚未创建。",
                        status: .blocked,
                        systemImage: "doc.badge.plus",
                        path: file.path
                    )
                },
                unresolvedP0Count: 0,
                requirementHasContent: false,
                scopeFrozen: false,
                requirementTasksReady: false
            )
        }

        let requirementFile = status.files.first { $0.key == "requirement" }
        let questionsFile = status.files.first { $0.key == "questions" }
        let scopeFile = status.files.first { $0.key == "scope" }
        let tasksFile = status.files.first { $0.key == "tasks" }
        let requirement = readText(at: requirementFile?.path)
        let questions = readText(at: questionsFile?.path)
        let scope = readText(at: scopeFile?.path)
        let tasks = readText(at: tasksFile?.path)

        let requirementHasContent = hasMeaningfulRequirementContent(requirement)
        let unresolvedP0Count = unresolvedP0Items(in: questions).count
        let scopeFrozen = isScopeFrozen(scope)
        let requirementTasksReady = hasRequirementTaskItems(tasks)

        let checks = [
            DemandIntakeReadinessCheck(
                id: "requirement-content",
                label: "需求内容 / Requirement",
                detail: requirementHasContent ? "requirement.md 已包含非占位需求内容。" : "requirement.md 仍像骨架模板，请先补充真实需求目标、流程和验收标准。",
                status: requirementHasContent ? .ready : .blocked,
                systemImage: requirementHasContent ? "doc.text.magnifyingglass" : "doc.badge.ellipsis",
                path: requirementFile?.path
            ),
            DemandIntakeReadinessCheck(
                id: "p0-questions",
                label: "P0 问题 / P0",
                detail: unresolvedP0Count == 0 ? "questions.md 中没有发现未解决 P0 阻塞项。" : "questions.md 中仍有 \(unresolvedP0Count) 个未解决 P0 项。",
                status: unresolvedP0Count == 0 ? .ready : .blocked,
                systemImage: unresolvedP0Count == 0 ? "checkmark.circle" : "exclamationmark.triangle",
                path: questionsFile?.path
            ),
            DemandIntakeReadinessCheck(
                id: "scope-freeze",
                label: "范围冻结 / Scope",
                detail: scopeFrozen ? "scope.md 已标记本次开发范围冻结。" : "scope.md 尚未冻结；需求预检完成后会进入独立的范围冻结阶段。",
                status: scopeFrozen ? .ready : .pending,
                systemImage: scopeFrozen ? "scope" : "scope",
                path: scopeFile?.path
            ),
            DemandIntakeReadinessCheck(
                id: "requirement-tasks",
                label: "需求列表 / Tasks",
                detail: requirementTasksReady ? "需求/tasks.md 已包含非模板需求点，可作为执行任务来源。" : "需求/tasks.md 仍只有预检模板任务，请先拆出真实需求点。",
                status: requirementTasksReady ? .ready : .review,
                systemImage: "checklist",
                path: tasksFile?.path
            )
        ]

        let blockingChecks = checks.filter { $0.status == .blocked }
        let reviewChecks = checks.filter { $0.status == .review }
        let resolvedStatus: WorkflowPathStatus
        let reason: String
        if blockingChecks.isEmpty && reviewChecks.isEmpty {
            resolvedStatus = .ready
            reason = scopeFrozen
                ? "需求预检内容已就绪，可以继续服务分支确认。"
                : "需求预检内容已就绪，下一步进入范围冻结。"
        } else if !blockingChecks.isEmpty {
            resolvedStatus = .blocked
            reason = blockingChecks.map(\.detail).joined(separator: " ")
        } else {
            resolvedStatus = .review
            reason = reviewChecks.map(\.detail).joined(separator: " ")
        }

        return DemandIntakeReadinessEvidence(
            status: resolvedStatus,
            reason: reason,
            evidence: status.files.map { "需求/\($0.filename)" },
            checks: checks,
            unresolvedP0Count: unresolvedP0Count,
            requirementHasContent: requirementHasContent,
            scopeFrozen: scopeFrozen,
            requirementTasksReady: requirementTasksReady
        )
    }

    private static func readText(at path: String?) -> String {
        guard let path else { return "" }
        return (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    private static func hasMeaningfulRequirementContent(_ text: String) -> Bool {
        meaningfulLines(in: text).count >= 3
    }

    private static func unresolvedP0Items(in text: String) -> [String] {
        var inP0Section = false
        var items: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            if line.hasPrefix("##") {
                inP0Section = lowercased.contains("p0")
                continue
            }
            guard inP0Section || lowercased.contains("p0") else { continue }
            guard looksLikeOpenQuestion(line) else { continue }
            items.append(line)
        }

        return items
    }

    private static func looksLikeOpenQuestion(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        guard !line.isEmpty, !line.hasPrefix("| ---") else { return false }
        if lowercased.contains("清零前") || lowercased.contains("结论") {
            return false
        }
        let resolvedMarkers = ["[x]", "已解决", "已确认", "无", "暂无", "none", "resolved", "closed", "done"]
        if resolvedMarkers.contains(where: { lowercased.contains($0) }) {
            return false
        }
        return line.hasPrefix("-")
            || line.hasPrefix("*")
            || line.hasPrefix("|")
            || lowercased.contains("p0")
    }

    private static func isScopeFrozen(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            if lowercased.contains("[ ]") && line.contains("冻结") {
                return false
            }
            if lowercased.contains("[x]") && line.contains("冻结") {
                return true
            }
            if line.contains("范围已冻结") || line.contains("已冻结本次开发范围") {
                return true
            }
            if line.contains("冻结状态") && line.contains("已冻结") {
                return true
            }
            return lowercased.contains("scope frozen")
        }
    }

    private static func hasRequirementTaskItems(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard line.hasPrefix("|") else { return false }
            guard !line.contains("---") else { return false }
            let templateRows = ["整理 requirement.md", "整理 questions.md", "冻结 scope.md", "需求点"]
            guard !templateRows.contains(where: { line.contains($0) }) else { return false }
            return !placeholderOnly(line)
        }
    }

    private static func meaningfulLines(in text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { return nil }
            guard !line.hasPrefix("#"), !line.hasPrefix("| ---"), !line.hasPrefix(">") else { return nil }
            guard !placeholderOnly(line) else { return nil }
            return line
        }
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

struct ScopeFreezeCheck: Hashable, Identifiable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
    let path: String?
}

struct ScopeFreezeEvidence: Hashable {
    let status: WorkflowPathStatus
    let reason: String
    let evidence: [String]
    let checks: [ScopeFreezeCheck]
    let scopePath: String
    let revision: NativeScopeDocumentRevision
    let hasInScope: Bool
    let hasOutOfScope: Bool
    let scopeFrozen: Bool
    let scopeChangeDeclared: Bool
    let scopeChangeAudited: Bool
    let unresolvedP0Count: Int

    var ready: Bool {
        status == .ready
    }

    static func resolve(status: DemandIntakeStatus, workspace: WorkspaceSummary) -> ScopeFreezeEvidence {
        let scopePath = status.files.first { $0.key == "scope" }?.path
            ?? "\(workspace.path)/需求/scope.md"
        let snapshot = NativeScopeFreezeStore.inspectDocument(at: scopePath, fileManager: .default)
        let text = snapshot.content ?? ""

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return ScopeFreezeEvidence(
                status: .blocked,
                reason: "尚未读取到 需求/scope.md。先打开范围文档，确认本次做什么、不做什么和待确认项。",
                evidence: ["需求/scope.md"],
                checks: [
                    ScopeFreezeCheck(
                        id: "scope-file",
                        label: "范围文档 / Scope file",
                        detail: "scope.md 为空或不可读。",
                        status: .blocked,
                        systemImage: "doc.badge.ellipsis",
                        path: scopePath
                    )
                ],
                scopePath: scopePath,
                revision: snapshot.revision,
                hasInScope: false,
                hasOutOfScope: false,
                scopeFrozen: false,
                scopeChangeDeclared: false,
                scopeChangeAudited: false,
                unresolvedP0Count: 0
            )
        }

        let hasInScope = hasSectionContent(
            in: text,
            headingMarkers: ["已确认并实现", "本次实现", "本次做", "in scope", "included"]
        )
        let hasOutOfScope = hasSectionContent(
            in: text,
            headingMarkers: ["暂不实现", "不做", "out of scope", "excluded"]
        )
        let pendingP0Items = unresolvedPendingP0Items(in: text)
        let scopeFrozen = isScopeFrozen(text)
        let scopeChangeDeclared = declaresScopeChange(text)
        let scopeChangeAudited = !scopeChangeDeclared || hasScopeChangeAudit(text)

        let checks = [
            ScopeFreezeCheck(
                id: "in-scope",
                label: "本次实现 / In scope",
                detail: hasInScope ? "scope.md 已写明本次确认实现的范围。" : "scope.md 缺少非占位的“已确认并实现 / 本次做”内容。",
                status: hasInScope ? .ready : .review,
                systemImage: "checklist",
                path: scopePath
            ),
            ScopeFreezeCheck(
                id: "out-of-scope",
                label: "暂不实现 / Out",
                detail: hasOutOfScope ? "scope.md 已写明暂不实现或排除范围。" : "scope.md 缺少非占位的“暂不实现 / 不做”内容。",
                status: hasOutOfScope ? .ready : .review,
                systemImage: "minus.circle",
                path: scopePath
            ),
            ScopeFreezeCheck(
                id: "pending-p0",
                label: "待确认 P0 / Pending P0",
                detail: pendingP0Items.isEmpty ? "未发现仍开放的 P0 范围项。" : "仍有 \(pendingP0Items.count) 个 P0 范围项未解决或未显式延期。",
                status: pendingP0Items.isEmpty ? .ready : .blocked,
                systemImage: pendingP0Items.isEmpty ? "checkmark.circle" : "exclamationmark.triangle",
                path: scopePath
            ),
            ScopeFreezeCheck(
                id: "freeze-marker",
                label: "冻结标记 / Freeze",
                detail: scopeFrozen ? "scope.md 已勾选或声明本次开发范围已冻结。" : "scope.md 尚未显式冻结；请勾选冻结项或写明范围已冻结。",
                status: scopeFrozen ? .ready : .blocked,
                systemImage: "scope",
                path: scopePath
            ),
            ScopeFreezeCheck(
                id: "scope-change-audit",
                label: "变更记录 / Change",
                detail: scopeChangeDeclared
                    ? (scopeChangeAudited
                        ? "scope.md 已记录范围变更，并包含原因和影响说明。"
                        : "scope.md 提到范围变更，但缺少原因或影响说明。")
                    : "未发现范围变更声明；当前冻结范围无需额外变更记录。",
                status: scopeChangeAudited ? .ready : .review,
                systemImage: scopeChangeAudited ? "clock.arrow.circlepath" : "exclamationmark.arrow.triangle.2.circlepath",
                path: scopePath
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
            reason = "scope.md 已写明本次做什么、不做什么，并且没有开放 P0 范围项，可以进入服务和分支确认。"
        }

        return ScopeFreezeEvidence(
            status: resolvedStatus,
            reason: reason,
            evidence: ["需求/scope.md"],
            checks: checks,
            scopePath: scopePath,
            revision: snapshot.revision,
            hasInScope: hasInScope,
            hasOutOfScope: hasOutOfScope,
            scopeFrozen: scopeFrozen,
            scopeChangeDeclared: scopeChangeDeclared,
            scopeChangeAudited: scopeChangeAudited,
            unresolvedP0Count: pendingP0Items.count
        )
    }

    private static func hasSectionContent(in text: String, headingMarkers: [String]) -> Bool {
        let lines = sectionLines(in: text, headingMarkers: headingMarkers)
        return lines.contains { line in
            let cleaned = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !cleaned.isEmpty, !cleaned.hasPrefix("| ---") else { return false }
            return !placeholderOnly(cleaned)
        }
    }

    private static func unresolvedPendingP0Items(in text: String) -> [String] {
        sectionLines(in: text, headingMarkers: ["仍待确认", "待确认", "待定", "pending"])
            .filter { line in
                let lowercased = line.lowercased()
                guard lowercased.contains("p0") else { return false }
                guard !placeholderOnly(line) else { return false }
                let resolvedMarkers = ["[x]", "已解决", "已确认", "无", "暂无", "none", "resolved", "closed", "done", "延期", "deferred", "非阻塞", "accepted"]
                return !resolvedMarkers.contains { lowercased.contains($0) }
            }
    }

    private static func sectionLines(in text: String, headingMarkers: [String]) -> [String] {
        var isInsideTargetSection = false
        var lines: [String] = []

        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            if line.hasPrefix("#") {
                isInsideTargetSection = headingMarkers.contains { marker in
                    lowercased.contains(marker.lowercased())
                }
                continue
            }
            if isInsideTargetSection {
                lines.append(line)
            }
        }

        return lines
    }

    private static func isScopeFrozen(_ text: String) -> Bool {
        text.components(separatedBy: .newlines).contains { rawLine in
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            let lowercased = line.lowercased()
            if lowercased.contains("[ ]") && line.contains("冻结") {
                return false
            }
            if lowercased.contains("[x]") && line.contains("冻结") {
                return true
            }
            if line.contains("范围已冻结") || line.contains("已冻结本次开发范围") {
                return true
            }
            if line.contains("冻结状态") && line.contains("已冻结") {
                return true
            }
            return lowercased.contains("scope frozen")
        }
    }

    private static func declaresScopeChange(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let markers = [
            "范围变更",
            "范围变化",
            "范围调整",
            "范围追加",
            "追加范围",
            "新增范围",
            "scope change",
            "scope changed",
            "change request"
        ]
        return markers.contains { normalized.contains($0.lowercased()) }
    }

    private static func hasScopeChangeAudit(_ text: String) -> Bool {
        let normalized = text.lowercased()
        let reasonMarkers = ["原因", "为什么", "背景", "reason", "rationale", "why"]
        let impactMarkers = ["影响", "涉及服务", "影响服务", "任务", "sql", "交付", "impact", "affected", "service", "task"]
        let hasReason = reasonMarkers.contains { normalized.contains($0.lowercased()) }
        let hasImpact = impactMarkers.contains { normalized.contains($0.lowercased()) }
        return hasReason && hasImpact
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

struct ScopeFreezeWritePlanItem: Identifiable, Hashable {
    let id: String
    let label: String
    let detail: String
    let status: WorkflowPathStatus
    let systemImage: String
}

struct ScopeFreezeWritePlan: Identifiable, Hashable {
    let id: String
    let workspaceID: WorkspaceSummary.ID
    let workspaceName: String
    let scopePath: String
    let status: WorkflowPathStatus
    let summary: String
    let items: [ScopeFreezeWritePlanItem]
    let appendedMarkdown: String
    let expectedRevision: NativeScopeDocumentRevision

    var canWrite: Bool {
        guard case .regularUTF8 = expectedRevision else { return false }
        return status == .next
            && !appendedMarkdown.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func resolve(
        workspace: WorkspaceSummary,
        evidence: ScopeFreezeEvidence,
        fileManager: FileManager = .default
    ) -> ScopeFreezeWritePlan {
        let id = "\(workspace.id)-scope-freeze"
        let expectedRevision = evidence.revision
        let currentRevision = NativeScopeFreezeStore.inspectRevision(
            at: evidence.scopePath,
            fileManager: fileManager
        )
        let unsafeDocumentReason: String?
        switch (expectedRevision, currentRevision) {
        case (.missing, _):
            unsafeDocumentReason = "scope document evidence is missing: \((evidence.scopePath as NSString).expandingTildeInPath); refresh and review scope.md before confirming"
        case (.invalid(let reason), _):
            unsafeDocumentReason = "\(reason); restore a regular UTF-8 scope.md, then refresh and review it before confirming"
        case (_, .missing):
            unsafeDocumentReason = "scope document is missing: \((evidence.scopePath as NSString).expandingTildeInPath); refresh and review scope.md before confirming"
        case (_, .invalid(let reason)):
            unsafeDocumentReason = "\(reason); restore a regular UTF-8 scope.md, then refresh and review it before confirming"
        case (.regularUTF8, .regularUTF8) where expectedRevision != currentRevision:
            unsafeDocumentReason = "scope document changed while preparing confirmation: \((evidence.scopePath as NSString).expandingTildeInPath); refresh and review scope.md again before confirming"
        case (.regularUTF8, .regularUTF8):
            unsafeDocumentReason = nil
        }
        if let unsafeDocumentReason {
            return ScopeFreezeWritePlan(
                id: id,
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                scopePath: evidence.scopePath,
                status: .blocked,
                summary: unsafeDocumentReason,
                items: [
                    ScopeFreezeWritePlanItem(
                        id: "unsafe-scope-document",
                        label: "范围文档 / Scope",
                        detail: unsafeDocumentReason,
                        status: .blocked,
                        systemImage: "exclamationmark.triangle"
                    )
                ],
                appendedMarkdown: "",
                expectedRevision: expectedRevision
            )
        }

        if evidence.scopeFrozen {
            return ScopeFreezeWritePlan(
                id: id,
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                scopePath: evidence.scopePath,
                status: .ready,
                summary: "scope.md 已包含冻结标记，无需重复写入。",
                items: [
                    ScopeFreezeWritePlanItem(
                        id: "already-frozen",
                        label: "冻结标记 / Freeze",
                        detail: "已检测到范围已冻结，可以继续服务和分支确认。",
                        status: .ready,
                        systemImage: "checkmark.seal"
                    )
                ],
                appendedMarkdown: "",
                expectedRevision: expectedRevision
            )
        }

        let blockers = buildBlockers(from: evidence)
        if !blockers.isEmpty {
            return ScopeFreezeWritePlan(
                id: id,
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                scopePath: evidence.scopePath,
                status: .blocked,
                summary: "范围冻结前仍有 \(blockers.count) 个前置项需要处理，Nexus 不会替用户补造范围结论。",
                items: blockers,
                appendedMarkdown: "",
                expectedRevision: expectedRevision
            )
        }

        let markdown = freezeMarkdown(workspace: workspace)
        return ScopeFreezeWritePlan(
            id: id,
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            scopePath: evidence.scopePath,
            status: .next,
            summary: "范围内容、P0 和变更审计已满足冻结条件；确认后只会向 scope.md 追加冻结确认块。",
            items: [
                ScopeFreezeWritePlanItem(
                    id: "append-freeze-marker",
                    label: "追加冻结块 / Append",
                    detail: "写入勾选的范围冻结标记、确认时间和后续变更规则，不改写已有范围内容。",
                    status: .next,
                    systemImage: "square.and.pencil"
                )
            ],
            appendedMarkdown: markdown,
            expectedRevision: expectedRevision
        )
    }

    private static func buildBlockers(from evidence: ScopeFreezeEvidence) -> [ScopeFreezeWritePlanItem] {
        var blockers: [ScopeFreezeWritePlanItem] = []

        if !evidence.hasInScope {
            blockers.append(
                ScopeFreezeWritePlanItem(
                    id: "missing-in-scope",
                    label: "本次实现 / In scope",
                    detail: "先在 scope.md 写清本次确认实现的范围，再冻结。",
                    status: .blocked,
                    systemImage: "checklist"
                )
            )
        }

        if !evidence.hasOutOfScope {
            blockers.append(
                ScopeFreezeWritePlanItem(
                    id: "missing-out-of-scope",
                    label: "暂不实现 / Out",
                    detail: "先在 scope.md 写清暂不实现或排除范围，避免开发时扩散。",
                    status: .blocked,
                    systemImage: "minus.circle"
                )
            )
        }

        if evidence.unresolvedP0Count > 0 {
            blockers.append(
                ScopeFreezeWritePlanItem(
                    id: "pending-p0",
                    label: "待确认 P0 / Pending P0",
                    detail: "仍有 \(evidence.unresolvedP0Count) 个 P0 范围项未解决或未显式延期。",
                    status: .blocked,
                    systemImage: "exclamationmark.triangle"
                )
            )
        }

        if !evidence.scopeChangeAudited {
            blockers.append(
                ScopeFreezeWritePlanItem(
                    id: "scope-change-audit",
                    label: "变更记录 / Change",
                    detail: "范围变更需要补齐原因和影响说明后才能冻结。",
                    status: .review,
                    systemImage: "clock.arrow.circlepath"
                )
            )
        }

        return blockers
    }

    private static func freezeMarkdown(workspace: WorkspaceSummary) -> String {
        """

        ## 范围冻结确认 / Scope Freeze Confirmation

        - [x] 范围已冻结：本次开发只按上方 In scope / Out of scope 推进。
        - 确认来源：Nexus Native confirmed write。
        - 工作区：\(workspace.name)
        - 后续范围变更：必须在本文件追加原因、影响服务/任务/SQL/交付说明后再继续开发。
        """
    }
}
