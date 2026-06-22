import Foundation

enum NativeLocalCoreDomain: String, CaseIterable, Hashable {
    case workspaceScanning
    case documentInventory
    case demandIntake
    case readiness
    case gitWorktreeStatus
    case audit
    case settings

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
            return "NexusBridge.localAutomationCheck"
        case .gitWorktreeStatus:
            return "NexusBridge.scanWorkspaces / setupWorktrees"
        case .audit:
            return "NexusBridge.appendAuditEvent"
        case .settings:
            return "NexusBridge scan roots and profile import/export contracts"
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
        return "\(readyCount)/\(domains.count) Native domains"
    }

    static func resolve(
        bridgeMode: String,
        nativeDomains: Set<NativeLocalCoreDomain> = []
    ) -> NativeLocalCoreEvidence {
        let domains = NativeLocalCoreDomain.allCases.map { domain in
            domainEvidence(domain: domain, bridgeMode: bridgeMode, nativeDomains: nativeDomains)
        }
        let blockers = domains.filter { $0.status == .blocked }
        let status: WorkflowPathStatus = blockers.isEmpty ? .ready : .blocked
        let reason = blockers.isEmpty
            ? "M2 Native Local Core 已覆盖工作区扫描、文档、需求、就绪、git/worktree、审计和设置。"
            : "M2 仍有 \(blockers.count) 个本地核心域依赖 legacy bridge：\(blockers.map { $0.domain.label }.joined(separator: ", "))。"
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
        nativeDomains: Set<NativeLocalCoreDomain>
    ) -> NativeLocalCoreDomainEvidence {
        if nativeDomains.contains(domain) {
            return NativeLocalCoreDomainEvidence(
                domain: domain,
                status: .ready,
                detail: "\(domain.label) 已由 Swift Native 本地核心接管。",
                evidence: domain.nativeEvidence
            )
        }

        return NativeLocalCoreDomainEvidence(
            domain: domain,
            status: .blocked,
            detail: "\(domain.label) 仍通过 \(domain.bridgeContract) 运行；当前 bridge mode：\(bridgeMode)。",
            evidence: [domain.bridgeContract]
        )
    }
}

private extension NativeLocalCoreDomain {
    var nativeEvidence: [String] {
        switch self {
        case .workspaceScanning:
            ["native/Nexus/Sources/NexusApp/AppState.swift"]
        case .documentInventory:
            ["native/Nexus/Sources/NexusApp/WorkspaceEvidenceDocuments.swift"]
        case .demandIntake:
            ["native/Nexus/Sources/NexusApp/DemandScopeEvidence.swift"]
        case .readiness:
            [
                "native/Nexus/Sources/NexusApp/MainWorkflowAcceptanceEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeDistributionReadinessEvidence.swift"
            ]
        case .gitWorktreeStatus:
            ["native/Nexus/Sources/NexusApp/ServiceWorktreeEvidence.swift"]
        case .audit:
            ["native/Nexus/Sources/NexusApp/AppState.swift"]
        case .settings:
            ["native/Nexus/Sources/NexusApp/AppState.swift"]
        }
    }
}
