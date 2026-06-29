import Foundation

enum NativeLocalCoreDomain: String, CaseIterable, Hashable {
    case workspaceScanning
    case documentInventory
    case demandIntake
    case readiness
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

struct NativeLocalCoreEvidence: Hashable {
    let status: WorkflowPathStatus
    let bridgeMode: String
    let reason: String
    let domains: [NativeLocalCoreDomainEvidence]

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
            reason = "M2 Native Local Core 已覆盖工作区扫描、文档、需求、就绪、git/worktree、审计、设置、Widget 快照、Codex 会话和搜索索引。"
        }
        return NativeLocalCoreEvidence(
            status: status,
            bridgeMode: bridgeMode,
            reason: reason,
            domains: domains
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
}

private extension NativeLocalCoreDomain {
    var nativeEvidence: [String] {
        switch self {
        case .workspaceScanning:
            [
                "native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift",
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
                "native/Nexus/Sources/NexusApp/NativeDemandIntakeStore.swift"
            ]
        case .readiness:
            [
                "native/Nexus/Sources/NexusApp/NativeLocalAutomationCheck.swift",
                "native/Nexus/Sources/NexusApp/MainWorkflowAcceptanceEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeDistributionReadinessEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeAuditEventStore.swift"
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
