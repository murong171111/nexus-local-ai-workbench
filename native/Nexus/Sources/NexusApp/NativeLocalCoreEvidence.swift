import Foundation

enum NativeLocalCoreDomain: String, CaseIterable, Hashable {
    case workspaceScanning
    case documentInventory
    case demandIntake
    case readiness
    case confirmedWrites
    case gitWorktreeStatus
    case audit
    case settings
    case widgetSnapshot
    case codexSessions
    case searchIndex

    var label: String {
        switch self {
        case .workspaceScanning:
            return "工作区扫描 / Workspace scan"
        case .documentInventory:
            return "文档目录 / Documents"
        case .demandIntake:
            return "需求预检 / Demand intake"
        case .readiness:
            return "就绪门禁 / Readiness"
        case .confirmedWrites:
            return "确认写入 / Confirmed writes"
        case .gitWorktreeStatus:
            return "Git / Worktree"
        case .audit:
            return "审计日志 / Audit"
        case .settings:
            return "设置配置 / Settings"
        case .widgetSnapshot:
            return "Widget 快照 / Widget snapshot"
        case .codexSessions:
            return "Codex 会话 / Codex sessions"
        case .searchIndex:
            return "搜索索引 / Search index"
        }
    }

    var bridgeContract: String {
        switch self {
        case .workspaceScanning:
            return "NexusBridge.scanWorkspaces"
        case .documentInventory:
            return "NexusBridge.readDocument / createWorkspaceDocument"
        case .demandIntake:
            return "NexusBridge.readDemandIntakeStatus / initializeDemandIntake"
        case .readiness:
            return "NativeLocalAutomationCheck / NexusBridge.localAutomationCheck fallback"
        case .confirmedWrites:
            return "NexusBridge write fallbacks for demand, tasks, delivery, archive, and restore"
        case .gitWorktreeStatus:
            return "NexusBridge.scanWorkspaces / setupWorktrees"
        case .audit:
            return "NexusBridge.appendAuditEvent"
        case .settings:
            return "NexusBridge scan roots and profile import/export contracts"
        case .widgetSnapshot:
            return "NexusBridge.widgetSnapshot"
        case .codexSessions:
            return "codex-sessions.json Native store"
        case .searchIndex:
            return "NexusBridge.rebuildSearchIndex / searchIndex"
        }
    }
}

struct NativeLocalCoreDomainEvidence: Hashable, Identifiable {
    let domain: NativeLocalCoreDomain
    let status: WorkflowPathStatus
    let detail: String
    let evidence: [String]

    var id: NativeLocalCoreDomain { domain }
}

enum NativeConfirmedWriteCapability: String, CaseIterable, Hashable {
    case demandInitialization
    case scopeFreeze
    case demandTaskTransfer
    case taskStatusWriteback
    case worktreeSetup
    case deliveryEvidence
    case validationPrSnapshot
    case archiveChecklist
    case archiveLifecycle
    case restoreLifecycle
    case lifecycleProofExport

    var label: String {
        switch self {
        case .demandInitialization:
            "需求初始化"
        case .scopeFreeze:
            "范围冻结"
        case .demandTaskTransfer:
            "任务迁移"
        case .taskStatusWriteback:
            "任务状态写回"
        case .worktreeSetup:
            "Worktree 创建"
        case .deliveryEvidence:
            "交付证据"
        case .validationPrSnapshot:
            "验证/PR 快照"
        case .archiveChecklist:
            "归档检查单"
        case .archiveLifecycle:
            "归档生命周期"
        case .restoreLifecycle:
            "恢复生命周期"
        case .lifecycleProofExport:
            "生命周期证明导出"
        }
    }

    var auditAction: String {
        switch self {
        case .demandInitialization:
            "demand_intake.initialized"
        case .scopeFreeze:
            "scope.freeze_confirmed"
        case .demandTaskTransfer:
            "demand_tasks.transferred"
        case .taskStatusWriteback:
            "workspace_task.updated"
        case .worktreeSetup:
            "worktree_setup.executed"
        case .deliveryEvidence:
            "delivery_record.snapshot_appended"
        case .validationPrSnapshot:
            "validation_pr.snapshot_appended"
        case .archiveChecklist:
            "archive_checklist.snapshot_appended"
        case .archiveLifecycle, .restoreLifecycle:
            "workspace_lifecycle.updated"
        case .lifecycleProofExport:
            "native_lifecycle_proof.exported"
        }
    }

    var auditMetadata: String? {
        switch self {
        case .archiveLifecycle:
            "state=archived"
        case .restoreLifecycle:
            "state=developing"
        default:
            nil
        }
    }

    var confirmation: String {
        switch self {
        case .demandInitialization:
            "创建 需求/ 标准文件前要求 explicit confirmation。"
        case .scopeFreeze:
            "向 需求/scope.md 追加冻结确认块前要求 explicit confirmation。"
        case .demandTaskTransfer:
            "把 需求/tasks.md 迁入根 tasks.md 前要求 explicit confirmation。"
        case .taskStatusWriteback:
            "完成/延期任务行写回前要求 confirmation sheet。"
        case .worktreeSetup:
            "创建 workspace-local worktree 前要求 explicit confirmation。"
        case .deliveryEvidence:
            "追加 Delivery Gate 快照前要求 explicit confirmation。"
        case .validationPrSnapshot:
            "追加验证、PR、CI 与 release review 快照前要求 explicit confirmation。"
        case .archiveChecklist:
            "追加归档确认检查单前要求 explicit confirmation。"
        case .archiveLifecycle:
            "写回 workspace.md 与 STATUS.md 的 archived 状态前要求 confirmation sheet。"
        case .restoreLifecycle:
            "从 archived 恢复到 developing 状态前要求 confirmation sheet。"
        case .lifecycleProofExport:
            "写出 native-lifecycle-proof.json 前要求 explicit confirmation。"
        }
    }

    var evidence: [String] {
        switch self {
        case .demandInitialization:
            [
                "native/Nexus/Sources/NexusApp/NativeDemandIntakeStore.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift"
            ]
        case .scopeFreeze:
            [
                "native/Nexus/Sources/NexusApp/NativeScopeFreezeStore.swift",
                "native/Nexus/Sources/NexusApp/DemandScopeEvidence.swift"
            ]
        case .demandTaskTransfer:
            [
                "native/Nexus/Sources/NexusApp/NativeDemandTaskTransferStore.swift",
                "native/Nexus/Sources/NexusApp/DemandScopeEvidence.swift"
            ]
        case .taskStatusWriteback:
            [
                "native/Nexus/Sources/NexusApp/NativeWorkspaceTaskStore.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift"
            ]
        case .worktreeSetup:
            [
                "native/Nexus/Sources/NexusApp/NativeWorktreeSetupStore.swift",
                "native/Nexus/Sources/NexusApp/ServiceWorktreeEvidence.swift"
            ]
        case .deliveryEvidence:
            [
                "native/Nexus/Sources/NexusApp/NativeDeliveryRecordStore.swift",
                "native/Nexus/Sources/NexusApp/DeliveryLifecycleEvidence.swift"
            ]
        case .validationPrSnapshot:
            [
                "native/Nexus/Sources/NexusApp/NativeDeliveryRecordStore.swift",
                "native/Nexus/Sources/NexusApp/DeliveryLifecycleEvidence.swift"
            ]
        case .archiveChecklist:
            [
                "native/Nexus/Sources/NexusApp/NativeDeliveryRecordStore.swift",
                "native/Nexus/Sources/NexusApp/DeliveryLifecycleEvidence.swift"
            ]
        case .archiveLifecycle:
            [
                "native/Nexus/Sources/NexusApp/NativeWorkspaceLifecycleStore.swift",
                "native/Nexus/Sources/NexusApp/DeliveryLifecycleEvidence.swift"
            ]
        case .restoreLifecycle:
            [
                "native/Nexus/Sources/NexusApp/NativeWorkspaceLifecycleStore.swift",
                "native/Nexus/Sources/NexusApp/DeliveryLifecycleEvidence.swift"
            ]
        case .lifecycleProofExport:
            [
                "native/Nexus/Sources/NexusApp/NativeLifecycleProofBundle.swift",
                "native/Nexus/Sources/NexusApp/NativeLifecycleProofEvidence.swift"
            ]
        }
    }
}

struct NativeConfirmedWriteEvidence: Hashable, Identifiable {
    let capability: NativeConfirmedWriteCapability
    let status: WorkflowPathStatus
    let confirmation: String
    let auditAction: String
    let auditMetadata: String?
    let evidence: [String]

    var id: NativeConfirmedWriteCapability { capability }

    var detail: String {
        if let auditMetadata {
            return "\(confirmation) Audit action: \(auditAction)，metadata: \(auditMetadata)。"
        }
        return "\(confirmation) Audit action: \(auditAction)。"
    }

    var auditLine: String {
        if let auditMetadata {
            return "\(auditAction) · \(auditMetadata)"
        }
        return auditAction
    }

    var auditIdentity: String {
        if let auditMetadata {
            return "\(auditAction)#\(auditMetadata)"
        }
        return auditAction
    }
}

struct NativeConfirmedWriteAuditSummary: Hashable {
    let status: WorkflowPathStatus
    let readyCapabilityCount: Int
    let totalCapabilityCount: Int
    let uniqueAuditActionCount: Int
    let uniqueAuditIdentityCount: Int
    let duplicateAuditActions: [String]
    let unqualifiedDuplicateAuditActions: [String]

    var ready: Bool {
        status == .ready
    }

    var identitySummary: String {
        "\(uniqueAuditIdentityCount)/\(totalCapabilityCount) audit identities"
    }

    var detail: String {
        if readyCapabilityCount < totalCapabilityCount {
            return "\(readyCapabilityCount)/\(totalCapabilityCount) confirmed writes are ready; audit identity proof waits for full Native coverage."
        }
        if !unqualifiedDuplicateAuditActions.isEmpty {
            return "Audit identity collision: \(unqualifiedDuplicateAuditActions.joined(separator: ", ")) must be separated with metadata."
        }
        if !duplicateAuditActions.isEmpty {
            return "\(identitySummary); duplicate audit actions are metadata-qualified: \(duplicateAuditActions.joined(separator: ", "))."
        }
        return "\(identitySummary); every confirmed write has a distinct audit action."
    }

    static func resolve(coverage: [NativeConfirmedWriteEvidence]) -> NativeConfirmedWriteAuditSummary {
        let readyCount = coverage.filter { $0.status == .ready }.count
        let actions = Set(coverage.map(\.auditAction))
        let identities = Set(coverage.map(\.auditIdentity))
        let duplicateGroups = Dictionary(grouping: coverage, by: \.auditAction)
            .filter { $0.value.count > 1 }
        let duplicateActions = duplicateGroups.keys.sorted()
        let unqualifiedDuplicates = duplicateGroups
            .filter { _, writes in
                writes.contains { $0.auditMetadata == nil }
                    || Set(writes.map(\.auditIdentity)).count != writes.count
            }
            .map(\.key)
            .sorted()
        let status: WorkflowPathStatus
        if readyCount < coverage.count {
            status = .blocked
        } else if identities.count != coverage.count || !unqualifiedDuplicates.isEmpty {
            status = .blocked
        } else {
            status = .ready
        }
        return NativeConfirmedWriteAuditSummary(
            status: status,
            readyCapabilityCount: readyCount,
            totalCapabilityCount: coverage.count,
            uniqueAuditActionCount: actions.count,
            uniqueAuditIdentityCount: identities.count,
            duplicateAuditActions: duplicateActions,
            unqualifiedDuplicateAuditActions: unqualifiedDuplicates
        )
    }
}

struct NativeLocalCoreEvidence: Hashable {
    let status: WorkflowPathStatus
    let bridgeMode: String
    let reason: String
    let domains: [NativeLocalCoreDomainEvidence]
    let confirmedWriteCoverage: [NativeConfirmedWriteEvidence]
    let confirmedWriteAuditSummary: NativeConfirmedWriteAuditSummary

    var ready: Bool {
        status == .ready
    }

    var bridgeIsLegacyDependency: Bool {
        let normalized = bridgeMode.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return normalized.contains("rust core")
            || normalized.contains("preview")
            || normalized.contains("bridge")
            || normalized.contains("nexus_core_library")
            || normalized.contains("ffi")
    }

    var migrationSummary: String {
        let readyCount = domains.filter { $0.status == .ready }.count
        let partialCount = domains.filter { $0.status == .review }.count
        if partialCount > 0 {
            return "\(readyCount)/\(domains.count) Native domains · \(partialCount) partial"
        }
        return "\(readyCount)/\(domains.count) Native domains"
    }

    var confirmedWriteSummary: String {
        let readyCount = confirmedWriteCoverage.filter { $0.status == .ready }.count
        return "\(readyCount)/\(confirmedWriteCoverage.count) confirmed writes"
    }

    static func resolve(
        bridgeMode: String,
        nativeDomains: Set<NativeLocalCoreDomain> = [],
        partialNativeDomains: Set<NativeLocalCoreDomain> = []
    ) -> NativeLocalCoreEvidence {
        let domains = NativeLocalCoreDomain.allCases.map { domain in
            domainEvidence(
                domain: domain,
                bridgeMode: bridgeMode,
                nativeDomains: nativeDomains,
                partialNativeDomains: partialNativeDomains
            )
        }
        let blockers = domains.filter { $0.status == .blocked }
        let partials = domains.filter { $0.status == .review }
        let status: WorkflowPathStatus
        if !blockers.isEmpty {
            status = .blocked
        } else if !partials.isEmpty {
            status = .review
        } else {
            status = .ready
        }
        let reason: String
        if !blockers.isEmpty {
            reason = "M2 仍有 \(blockers.count) 个本地核心域依赖 legacy bridge：\(blockers.map { $0.domain.label }.joined(separator: ", "))。\(partialDetail(partials))"
        } else if !partials.isEmpty {
            reason = "M2 Native Local Core 已无 blocked 域；仍有 \(partials.count) 个域需要补齐 Native 规则：\(partials.map { $0.domain.label }.joined(separator: ", "))。"
        } else {
            reason = "M2 Native Local Core 已覆盖工作区扫描、文档、需求、就绪、confirmed writes、git/worktree、审计、设置、Widget 快照、Codex 会话和搜索索引。"
        }
        let confirmedWriteCoverage = confirmedWriteCoverage(
            status: domains.first { $0.domain == .confirmedWrites }?.status ?? .blocked
        )
        return NativeLocalCoreEvidence(
            status: status,
            bridgeMode: bridgeMode,
            reason: reason,
            domains: domains,
            confirmedWriteCoverage: confirmedWriteCoverage,
            confirmedWriteAuditSummary: NativeConfirmedWriteAuditSummary.resolve(
                coverage: confirmedWriteCoverage
            )
        )
    }

    private static func domainEvidence(
        domain: NativeLocalCoreDomain,
        bridgeMode: String,
        nativeDomains: Set<NativeLocalCoreDomain>,
        partialNativeDomains: Set<NativeLocalCoreDomain>
    ) -> NativeLocalCoreDomainEvidence {
        if nativeDomains.contains(domain) {
            return NativeLocalCoreDomainEvidence(
                domain: domain,
                status: .ready,
                detail: "\(domain.label) 已由 Swift Native 本地核心接管。",
                evidence: domain.nativeEvidence
            )
        }
        if partialNativeDomains.contains(domain) {
            return NativeLocalCoreDomainEvidence(
                domain: domain,
                status: .review,
                detail: "\(domain.label) 的 Swift Native 规则已接管一部分；剩余读写仍通过 \(domain.bridgeContract) 运行。",
                evidence: domain.nativeEvidence + [domain.bridgeContract]
            )
        }

        return NativeLocalCoreDomainEvidence(
            domain: domain,
            status: .blocked,
            detail: "\(domain.label) 仍通过 \(domain.bridgeContract) 运行；当前 bridge mode：\(bridgeMode)。",
            evidence: [domain.bridgeContract]
        )
    }

    private static func partialDetail(_ partials: [NativeLocalCoreDomainEvidence]) -> String {
        guard !partials.isEmpty else { return "" }
        return " 另有 \(partials.count) 个域已部分 Swift 化：\(partials.map { $0.domain.label }.joined(separator: ", "))。"
    }

    private static func confirmedWriteCoverage(status: WorkflowPathStatus) -> [NativeConfirmedWriteEvidence] {
        NativeConfirmedWriteCapability.allCases.map { capability in
            NativeConfirmedWriteEvidence(
                capability: capability,
                status: status,
                confirmation: capability.confirmation,
                auditAction: capability.auditAction,
                auditMetadata: capability.auditMetadata,
                evidence: capability.evidence
            )
        }
    }
}

private extension NativeLocalCoreDomain {
    var nativeEvidence: [String] {
        switch self {
        case .workspaceScanning:
            [
                "native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift",
                "native/Nexus/Sources/NexusApp/NativeWorkspaceCreationStore.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift"
            ]
        case .documentInventory:
            [
                "native/Nexus/Sources/NexusApp/WorkspaceEvidenceDocuments.swift",
                "native/Nexus/Sources/NexusApp/NativeDocumentStore.swift"
            ]
        case .demandIntake:
            [
                "native/Nexus/Sources/NexusApp/DemandScopeEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeDemandIntakeStore.swift",
                "native/Nexus/Sources/NexusApp/NativeScopeFreezeStore.swift",
                "native/Nexus/Sources/NexusApp/NativeDemandTaskTransferStore.swift"
            ]
        case .readiness:
            [
                "native/Nexus/Sources/NexusApp/NativeLocalAutomationCheck.swift",
                "native/Nexus/Sources/NexusApp/MainWorkflowAcceptanceEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeDistributionReadinessEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeReleasePolicyEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeAuditEventStore.swift"
            ]
        case .confirmedWrites:
            [
                "native/Nexus/Sources/NexusApp/NativeDemandIntakeStore.swift",
                "native/Nexus/Sources/NexusApp/NativeScopeFreezeStore.swift",
                "native/Nexus/Sources/NexusApp/NativeDemandTaskTransferStore.swift",
                "native/Nexus/Sources/NexusApp/NativeWorktreeSetupStore.swift",
                "native/Nexus/Sources/NexusApp/NativeDeliveryRecordStore.swift",
                "native/Nexus/Sources/NexusApp/NativeWorkspaceTaskStore.swift",
                "native/Nexus/Sources/NexusApp/NativeWorkspaceLifecycleStore.swift",
                "native/Nexus/Sources/NexusApp/NativeLifecycleProofEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeLifecycleProofBundle.swift",
                "native/Nexus/Sources/NexusApp/DeliveryLifecycleEvidence.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift"
            ]
        case .gitWorktreeStatus:
            [
                "native/Nexus/Sources/NexusApp/ServiceWorktreeEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeSourceRepositoryStore.swift",
                "native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift",
                "native/Nexus/Sources/NexusApp/NativeWorktreeSetupStore.swift"
            ]
        case .audit:
            [
                "native/Nexus/Sources/NexusApp/NativeAuditEventStore.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift"
            ]
        case .settings:
            ["native/Nexus/Sources/NexusApp/AppState.swift"]
        case .widgetSnapshot:
            [
                "native/Nexus/Sources/NexusApp/NativeWidgetSnapshotBuilder.swift",
                "native/Nexus/Sources/NexusApp/NativeWidgetSnapshotStore.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift"
            ]
        case .codexSessions:
            [
                "native/Nexus/Sources/NexusApp/NativeCodexSessionStore.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift"
            ]
        case .searchIndex:
            [
                "native/Nexus/Sources/NexusApp/NativeSearchIndexStore.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift",
                "native/Nexus/Sources/NexusApp/Models.swift"
            ]
        }
    }
}
