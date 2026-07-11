import NexusBridge
import AppKit
import XCTest
@testable import NexusApp

final class ModelBehaviorTests: XCTestCase {
    @MainActor
    func testDefaultAppStateStartsWithoutSampleWorkspaces() {
        let appState = AppState.preview()

        XCTAssertTrue(appState.workspaces.isEmpty)
        XCTAssertEqual(appState.agentStatus.title, "Loading")
    }

    func testPreviewBridgeOptionalFeedsAreEmpty() async throws {
        let bridge = PreviewNexusBridge()

        let events = try await bridge.readAgentEvents(
            request: ReadAgentEventsRequest(eventsRoot: "/tmp/events", limit: 8)
        )
        let results = try await bridge.searchIndex(
            request: SearchIndexRequest(indexPath: "/tmp/index", query: "demo")
        )

        XCTAssertTrue(events.isEmpty)
        XCTAssertTrue(results.isEmpty)
    }

    func testPreviewBridgeRejectsAuthoritativeLocalReads() async {
        let bridge = PreviewNexusBridge()

        await assertThrowsUnavailable {
            _ = try await bridge.scanWorkspaces(
                request: ScanWorkspacesRequest(
                    workspacesRoot: "/tmp/workspaces",
                    sourceReposRoot: "/tmp/source-repos",
                    docsRoot: "/tmp/docs"
                )
            )
        }
        await assertThrowsUnavailable {
            _ = try await bridge.scanSourceRepos(
                request: ScanSourceReposRequest(sourceReposRoot: "/tmp/source-repos")
            )
        }
        await assertThrowsUnavailable {
            _ = try await bridge.readDocument(
                request: ReadDocumentRequest(path: "/missing/tasks.md")
            )
        }
        await assertThrowsUnavailable {
            _ = try await bridge.readDemandIntakeStatus(
                request: DemandIntakeStatusRequest(workspacePath: "/tmp/workspaces/demo")
            )
        }
        await assertThrowsUnavailable {
            _ = try await bridge.widgetSnapshot(
                request: WidgetSnapshotRequest(
                    workspacesRoot: "/tmp/workspaces",
                    sourceReposRoot: "/tmp/source-repos",
                    docsRoot: "/tmp/docs",
                    activeFolder: "demo",
                    generatedAt: "2026-07-10T00:00:00Z"
                )
            )
        }
        await assertThrowsUnavailable {
            _ = try await bridge.localAutomationCheck(
                request: LocalAutomationCheckRequest(
                    workspacesRoot: "/tmp/workspaces",
                    sourceReposRoot: "/tmp/source-repos",
                    docsRoot: "/tmp/docs",
                    generatedAt: "2026-07-10T00:00:00Z"
                )
            )
        }
    }

    @MainActor
    func testAppStateDemandIntakeStatusFailureDoesNotFallBackToPreviewBridge() async {
        let workspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "missing-demand-workspace",
            path: "/tmp/nexus-missing-demand-workspace-\(UUID().uuidString)"
        )
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        let appState = AppState(
            workspaces: [workspace],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: "/tmp/workspaces",
            sourceReposRoot: "/tmp/source-repos",
            docsRoot: "/tmp/docs",
            defaults: defaults
        )

        await appState.refreshDemandIntakeStatus(for: workspace)

        XCTAssertTrue(appState.lastError?.contains("workspace does not exist") == true)
        XCTAssertFalse(appState.lastError?.contains("Nexus Core bridge") == true)
        XCTAssertFalse(appState.demandIntakeDisplayStatus(for: workspace).exists)
        XCTAssertEqual(appState.demandIntakeDisplayStatus(for: workspace).missingCount, 5)
    }

    @MainActor
    func testAppStateDemandIntakeInitializationUsesConfirmedPlanWithoutBridgeFallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-app-state-demand-plan-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let docsRoot = root.appendingPathComponent("docs")
        let applicationSupportRoot = root.appendingPathComponent("app-support")
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        for directory in [workspacesRoot, sourceRoot, docsRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let created = try NativeWorkspaceCreationStore.create(
            request: CreateWorkspaceRequest(
                name: "Demand plan",
                folder: "demand-plan",
                workspacesRoot: workspacesRoot.path,
                sourceReposRoot: sourceRoot.path,
                services: [],
                targetBranch: "",
                confirmed: true
            )
        )
        let workspace = try scannedWorkspace(
            folder: created.folder,
            workspacesRoot: workspacesRoot,
            sourceRoot: sourceRoot
        )
        let appState = AppState(
            workspaces: [workspace],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path,
            applicationSupportRoot: applicationSupportRoot.path,
            defaults: defaults
        )
        let plan = appState.demandIntakeInitializationPlan(
            for: workspace,
            demandName: "Demand plan",
            lanhuLink: "",
            notes: ""
        )
        let demandURL = URL(fileURLWithPath: created.path).appendingPathComponent("需求")
        let externallyCreatedRequirement = "# External requirement\n"
        try FileManager.default.createDirectory(at: demandURL, withIntermediateDirectories: true)
        try externallyCreatedRequirement.write(
            to: demandURL.appendingPathComponent("requirement.md"),
            atomically: true,
            encoding: .utf8
        )

        let response = await appState.initializeDemandIntake(
            in: workspace,
            plan: plan,
            confirmed: true
        )

        XCTAssertNil(response)
        XCTAssertTrue(appState.lastError?.contains("changed since confirmation") == true)
        XCTAssertFalse(appState.lastError?.contains("Nexus Core bridge") == true)
        XCTAssertFalse(appState.isInitializingDemandIntake)
        XCTAssertEqual(
            try String(contentsOf: demandURL.appendingPathComponent("requirement.md"), encoding: .utf8),
            externallyCreatedRequirement
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: demandURL.appendingPathComponent("questions.md").path))
        XCTAssertNil(appState.localWriteFeedback)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: applicationSupportRoot
                .appendingPathComponent("audit/\(NativeAuditEventStore.fileName)").path
        ))
    }

    @MainActor
    func testAppStateCreationRoutesNewWorkspaceToDemandIntakeWithoutOpeningHandoff() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-app-state-create-demand-first-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let docsRoot = root.appendingPathComponent("docs")
        let applicationSupportRoot = root.appendingPathComponent("app-support")
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        for directory in [workspacesRoot, sourceRoot, docsRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let appState = AppState(
            workspaces: [],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path,
            applicationSupportRoot: applicationSupportRoot.path,
            defaults: defaults
        )

        await appState.createWorkspace(
            draft: CreateWorkspaceDraft(
                name: "Demand first",
                folder: "demand-first",
                services: [],
                targetBranch: "",
                confirmed: true
            )
        )

        let workspace = try XCTUnwrap(appState.selectedWorkspace)
        XCTAssertNil(appState.lastError)
        XCTAssertEqual(workspace.folder, "demand-first")
        XCTAssertTrue(appState.lastCreatedWorkspace?.isVisibleAfterRefresh == true)
        XCTAssertNil(appState.documentPreview)
        XCTAssertNil(appState.documentFocusHint)
        XCTAssertFalse(appState.demandIntakeDisplayStatus(for: workspace).exists)
        XCTAssertEqual(appState.mainWorkflowStage(for: workspace).id, .created)
        XCTAssertEqual(appState.mainWorkflowStage(for: workspace).primaryAction, .demandIntake)
    }

    func testNativeModelLayeringKeepsWorkflowLogicOutOfBaseModels() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSources = packageRoot.appendingPathComponent("Sources/NexusApp")
        let modelsPath = appSources.appendingPathComponent("Models.swift")
        let models = try String(contentsOf: modelsPath, encoding: .utf8)

        let forbiddenModelSymbols = [
            "enum WorkspaceBoardLaneID",
            "struct WorkspaceBoardLane",
            "struct MenuBarStatusSummary",
            "struct WorkspaceLifecycle",
            "struct WorkspaceWorkflowSummary",
            "struct WorkspaceSqlSummary",
            "struct DemandTaskTransferPlan",
            "struct AgentActionSurface",
            "struct DeliveryGateEvidence",
            "struct DevelopmentTaskEvidence",
            "struct DevelopmentTaskSource",
            "struct WorktreeSetupEvidence",
            "struct WorktreeSetupMutationPolicy",
            "struct MainWorkflowAcceptanceEvidence",
            "struct MainWorkflowLegacyBoundary",
            "struct NativeLocalCoreEvidence",
            "struct NativeDistributionReadinessEvidence",
            "struct NativeLifecycleProofEvidence",
            "struct DemandIntakeReadinessEvidence",
            "struct DemandIntakeM1ActionPolicy",
            "struct TaskStatusUpdate",
            "struct TaskStatusMutationPolicy",
            "struct CommandCenterLayoutPolicy",
            "struct CommandCenterLayoutAuditSummary",
            "struct WorkspaceDetailActionHierarchyPolicy",
            "struct ServiceWorktreeRowState",
            "struct WorkspaceMainStageEvidenceLink",
            "struct WorkspaceStageAnswer",
            "struct WorkspaceListStageBadge",
            "struct WorkspaceListSummary",
            "struct NativeStatusDiagnostics",
            "enum WorkspaceBoardEmptyStateReason",
            "struct WorkspaceDetailNavigationItem",
            "func mainStage("
        ]

        for symbol in forbiddenModelSymbols {
            XCTAssertFalse(
                models.contains(symbol),
                "\(symbol) belongs in a dedicated workflow/evidence file, not Models.swift"
            )
        }

        let ownedWorkflowFiles = [
            "PrimaryWorkflowStageResolver.swift",
            "DemandScopeEvidence.swift",
            "ServiceWorktreeEvidence.swift",
            "DevelopmentTaskEvidence.swift",
            "DeliveryLifecycleEvidence.swift",
            "DemandTaskTransfer.swift",
            "WorkspaceEvidenceDocuments.swift",
            "WorkspaceWorkflowSummary.swift",
            "WorkspaceBoardModels.swift",
            "MenuBarStatusModels.swift",
            "AgentWorkflowModels.swift",
            "WorkspaceLifecycleModels.swift",
            "TaskStatusWritebackModels.swift",
            "WorkspaceMainStageEvidence.swift",
            "WorkspaceListStageBadges.swift",
            "WorkspaceListSummary.swift",
            "NativeStatusDiagnostics.swift",
            "NativeOnboardingPath.swift",
            "WorkspaceDetailNavigation.swift",
            "NativeLifecycleProofEvidence.swift",
            "DemandIntakeActions.swift",
            "CommandCenterLayout.swift"
        ]

        for fileName in ownedWorkflowFiles {
            XCTAssertTrue(
                FileManager.default.fileExists(atPath: appSources.appendingPathComponent(fileName).path),
                "\(fileName) is part of the Native model layering guardrail"
            )
        }
    }

    func testNativeSetupReadinessSkipsInitializationWhenEnvironmentIsReady() {
        let readiness = NativeSetupReadiness(
            health: environmentHealth(ready: true, workspaceCount: 2, sourceRepoCount: 5),
            workspaceCount: 2,
            profileImported: false
        )

        XCTAssertEqual(readiness.status, .ready)
        XCTAssertEqual(readiness.status.environmentStatus, "pass")
        XCTAssertEqual(readiness.primaryActionLabel, "刷新")
        XCTAssertTrue(readiness.detail.contains("不需要初始化"))
        XCTAssertTrue(readiness.detail.contains("现有工作区"))
    }

    func testNativeSetupReadinessRoutesEmptyReadyEnvironmentToWorkspaceCreation() {
        let readiness = NativeSetupReadiness(
            health: environmentHealth(ready: true, workspaceCount: 0, sourceRepoCount: 3),
            workspaceCount: 0,
            profileImported: true
        )

        XCTAssertEqual(readiness.status, .ready)
        XCTAssertEqual(readiness.primaryActionLabel, "新建")
        XCTAssertTrue(readiness.detail.contains("新建第一个工作区"))
    }

    func testNativeSetupReadinessHighlightsUncheckedAndBlockedSettings() {
        let unchecked = NativeSetupReadiness(
            health: nil,
            workspaceCount: 0,
            profileImported: true
        )
        XCTAssertEqual(unchecked.status, .unchecked)
        XCTAssertEqual(unchecked.status.environmentStatus, "warning")
        XCTAssertTrue(unchecked.detail.contains("已导入 Profile"))

        let blocked = NativeSetupReadiness(
            health: environmentHealth(
                ready: false,
                workspaceCount: 0,
                sourceRepoCount: 0,
                blockers: ["工作区目录不存在"],
                warnings: ["源仓库目录下暂未识别到 git 服务仓库"]
            ),
            workspaceCount: 0,
            profileImported: false
        )
        XCTAssertEqual(blocked.status, .needsReview)
        XCTAssertEqual(blocked.status.environmentStatus, "blocker")
        XCTAssertTrue(blocked.detail.contains("1 blockers"))
        XCTAssertTrue(blocked.detail.contains("Settings"))
    }

    func testNativeOnboardingPathRoutesFirstRunToOneCurrentStep() {
        let noProfile = NativeOnboardingPath.resolve(
            readiness: NativeSetupReadiness(
                health: nil,
                workspaceCount: 0,
                profileImported: false
            ),
            workspaceCount: 0,
            profileImported: false
        )
        XCTAssertEqual(noProfile.currentStep?.id, .teamProfile)
        XCTAssertEqual(noProfile.currentActionLabel, "打开团队配置")
        XCTAssertEqual(noProfile.steps.filter(\.isCurrent).count, 1)
        XCTAssertEqual(noProfile.steps.map(\.id), NativeOnboardingStepID.allCases)
        XCTAssertEqual(noProfile.steps.first { $0.id == .environmentCheck }?.status, .review)

        let importedUnchecked = NativeOnboardingPath.resolve(
            readiness: NativeSetupReadiness(
                health: nil,
                workspaceCount: 0,
                profileImported: true
            ),
            workspaceCount: 0,
            profileImported: true
        )
        XCTAssertEqual(importedUnchecked.currentStep?.id, .environmentCheck)
        XCTAssertEqual(importedUnchecked.currentActionLabel, "运行环境检查")
    }

    func testNativeOnboardingPathRoutesReadyEnvironmentToWorkspaceOrMainPath() {
        let readyEmpty = NativeOnboardingPath.resolve(
            readiness: NativeSetupReadiness(
                health: environmentHealth(ready: true, workspaceCount: 0, sourceRepoCount: 2),
                workspaceCount: 0,
                profileImported: true
            ),
            workspaceCount: 0,
            profileImported: true
        )
        XCTAssertEqual(readyEmpty.currentStep?.id, .workspaceCreation)
        XCTAssertEqual(readyEmpty.currentStep?.status, .next)
        XCTAssertEqual(readyEmpty.currentActionLabel, "新建工作区")
        XCTAssertEqual(readyEmpty.steps.first { $0.id == .mainPath }?.status, .pending)

        let readyWithWorkspace = NativeOnboardingPath.resolve(
            readiness: NativeSetupReadiness(
                health: environmentHealth(ready: true, workspaceCount: 2, sourceRepoCount: 3),
                workspaceCount: 2,
                profileImported: true
            ),
            workspaceCount: 2,
            profileImported: true
        )
        XCTAssertEqual(readyWithWorkspace.currentStep?.id, .mainPath)
        XCTAssertEqual(readyWithWorkspace.steps.first { $0.id == .workspaceCreation }?.status, .ready)
        XCTAssertEqual(readyWithWorkspace.steps.first { $0.id == .mainPath }?.status, .ready)
    }

    func testNativeOnboardingPathKeepsBlockedEnvironmentCurrent() {
        let blocked = NativeOnboardingPath.resolve(
            readiness: NativeSetupReadiness(
                health: environmentHealth(
                    ready: false,
                    workspaceCount: 0,
                    sourceRepoCount: 0,
                    blockers: ["工作区目录不存在"]
                ),
                workspaceCount: 0,
                profileImported: false
            ),
            workspaceCount: 0,
            profileImported: false
        )
        XCTAssertEqual(blocked.currentStep?.id, .environmentCheck)
        XCTAssertEqual(blocked.currentStep?.status, .blocked)
        XCTAssertTrue(blocked.currentStep?.detail.contains("blockers") == true)
        XCTAssertEqual(blocked.steps.first { $0.id == .workspaceCreation }?.status, .pending)
    }

    func testWorkspaceBoardEmptyStateReasonSeparatesSetupDirectoryAndFilterStates() {
        let unchecked = NativeSetupReadiness(
            health: nil,
            workspaceCount: 0,
            profileImported: false
        )
        let readyEmpty = NativeSetupReadiness(
            health: environmentHealth(ready: true, workspaceCount: 0, sourceRepoCount: 2),
            workspaceCount: 0,
            profileImported: true
        )
        let workspace = workspaceForWorkflowSummary(stage: "developing", id: "empty-state-filtered")
        let filteredSummary = WorkspaceListSummary(workspaces: [workspace])

        XCTAssertEqual(
            WorkspaceBoardEmptyStateReason.resolve(
                summary: WorkspaceListSummary(workspaces: []),
                visibleCount: 0,
                readiness: unchecked
            ),
            .unconfigured
        )
        XCTAssertEqual(
            WorkspaceBoardEmptyStateReason.resolve(
                summary: WorkspaceListSummary(workspaces: []),
                visibleCount: 0,
                readiness: readyEmpty
            ),
            .configuredNoDirectories
        )
        XCTAssertEqual(
            WorkspaceBoardEmptyStateReason.resolve(
                summary: filteredSummary,
                visibleCount: 0,
                readiness: readyEmpty
            ),
            .filteredNoResults
        )
        XCTAssertNil(
            WorkspaceBoardEmptyStateReason.resolve(
                summary: filteredSummary,
                visibleCount: 1,
                readiness: readyEmpty
            )
        )
        XCTAssertEqual(WorkspaceBoardEmptyStateReason.unconfigured.title, "本地路径还未确认")
        XCTAssertEqual(WorkspaceBoardEmptyStateReason.unconfigured.helpText, "Setup needed")
        XCTAssertEqual(WorkspaceBoardEmptyStateReason.unconfigured.primaryActionLabel, "检查本机设置")
        XCTAssertEqual(WorkspaceBoardEmptyStateReason.configuredNoDirectories.primaryActionLabel, "新建工作区")
        XCTAssertEqual(WorkspaceBoardEmptyStateReason.filteredNoResults.primaryActionLabel, "查看全部工作区")
        XCTAssertFalse(WorkspaceBoardEmptyStateReason.configuredNoDirectories.title.contains("/"))
    }

    func testWorkspaceBoardLaneClassificationUsesWorkflowStageNotRisk() {
        func stage(_ id: WorkspaceMainStageID, _ status: WorkflowPathStatus) -> WorkspaceMainStage {
            WorkspaceMainStage(
                id: id,
                status: status,
                title: "Stage",
                reason: "Reason",
                primaryActionLabel: "Continue",
                primaryActionSystemImage: "arrow.right",
                primaryAction: .document("workspace"),
                evidence: ["workspace.md"],
                nextStageAllowed: false
            )
        }

        let cases: [(Bool, WorkspaceMainStageID, WorkflowPathStatus, WorkspaceBoardLaneID)] = [
            (false, .development, .blocked, .attention),
            (false, .demandIntake, .pending, .attention),
            (false, .demandIntake, .review, .attention),
            (false, .created, .next, .attention),
            (false, .development, .next, .active),
            (false, .deliveryCheck, .next, .active),
            (true, .development, .next, .completed)
        ]

        for (isArchived, id, status, expected) in cases {
            XCTAssertEqual(WorkspaceBoardLaneID.resolve(isArchived: isArchived, stage: stage(id, status)), expected)
        }

        let riskOnly = [RiskLevel.low, .medium, .high].map { riskLevel in
            workspaceForWorkflowSummary(
                stage: "scoping",
                id: "board-risk-\(riskLevel.rawValue)",
                riskLevel: riskLevel
            )
        }
        let lanes = WorkspaceBoardLane.lanes(for: riskOnly)
        XCTAssertEqual(Set(lanes.first { $0.id == .attention }?.workspaces.map(\.id) ?? []), Set(riskOnly.map(\.id)))
        XCTAssertTrue(lanes.first { $0.id == .active }?.workspaces.isEmpty == true)
    }

    func testWorkspaceBoardCopyStaysChineseFirstAndFocused() {
        XCTAssertEqual(WorkspaceBoardCopy.title, "工作区")
        XCTAssertEqual(WorkspaceBoardCopy.titleHelp, "Board")
        XCTAssertEqual(WorkspaceBoardCopy.activeWorkspaceCount(2), "2 个活跃项目")
        XCTAssertEqual(WorkspaceBoardCopy.showAllCompleted, "查看全部")
        XCTAssertEqual(WorkspaceBoardCopy.showRecentCompleted, "收起")
    }

    func testNativeStatusDiagnosticsReportsDirectoriesIndexWidgetAndAuditTarget() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-diagnostics-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let auditRoot = root.appendingPathComponent("audit")
        let target = root.appendingPathComponent("target.md")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspacesRoot, withIntermediateDirectories: true)
        try """
        # Workspaces

        | Workspace | State |
        | --- | --- |
        | Demo Feature | developing |
        """.write(to: workspacesRoot.appendingPathComponent("INDEX.md"), atomically: true, encoding: .utf8)
        try "target\n".write(to: target, atomically: true, encoding: .utf8)
        _ = try NativeAuditEventStore.append(
            auditRoot: auditRoot.path,
            event: AuditEventInput(
                actor: "Nexus Native",
                action: "workspace.created",
                target: target.path,
                summary: "Created workspace"
            )
        )

        let diagnostics = NativeStatusDiagnostics.resolve(
            workspaceRoot: workspacesRoot.path,
            health: environmentHealth(ready: true, workspaceCount: 3, sourceRepoCount: 2),
            widgetSnapshot: WidgetSnapshot(
                generatedAt: "2026-06-29T12:00:00Z",
                workspacesRoot: workspacesRoot.path,
                activeWorkspace: nil,
                activeWorkspaceFolder: nil,
                workspaceCount: 0,
                riskCount: 0,
                dirtyServiceCount: 0,
                missingWorktreeCount: 0,
                topRisks: [],
                deepLink: "nexus://"
            ),
            auditRoot: auditRoot.path
        )

        XCTAssertEqual(diagnostics.workspaceDirectoryCount, 3)
        XCTAssertEqual(diagnostics.indexRecordCount, 1)
        XCTAssertEqual(diagnostics.widgetUpdatedAt, "2026-06-29T12:00:00Z")
        XCTAssertEqual(diagnostics.latestAuditAction, "workspace.created")
        XCTAssertEqual(diagnostics.latestAuditTarget, target.path)
        XCTAssertEqual(diagnostics.latestAuditTargetExists, true)
        XCTAssertEqual(diagnostics.directoryValue, "3")
        XCTAssertEqual(diagnostics.indexValue, "1")
        XCTAssertEqual(diagnostics.widgetValue, "2026-06-29T12:00:00Z")
        XCTAssertTrue(diagnostics.auditValue.contains("目标存在"))
        XCTAssertEqual(diagnostics.diagnosticItems.map(\.id), ["directories", "index", "widget", "audit"])
        XCTAssertEqual(diagnostics.diagnosticItems.map(\.label), ["真实目录", "索引记录", "Widget 更新", "最近目标"])
        XCTAssertFalse(diagnostics.diagnosticItems.first { $0.id == "directories" }?.isAttention ?? true)
        XCTAssertFalse(diagnostics.diagnosticItems.first { $0.id == "audit" }?.isAttention ?? true)
        XCTAssertEqual(diagnostics.summary.title, "本地状态已对齐")
        XCTAssertEqual(diagnostics.summary.actionLabel, "继续主路径")
        XCTAssertEqual(diagnostics.summary.status, .ready)
    }

    func testNativeStatusDiagnosticsSummarizesIndexDirectoryMismatch() {
        let mismatch = NativeStatusDiagnostics(
            workspaceDirectoryCount: 0,
            indexRecordCount: 2,
            widgetUpdatedAt: nil,
            latestAuditAction: "workspace.created",
            latestAuditTarget: "/tmp/missing-workspace",
            latestAuditTargetExists: false
        )

        XCTAssertEqual(mismatch.summary.title, "索引有记录但真实目录为 0")
        XCTAssertTrue(mismatch.summary.detail.contains("2 条记录"))
        XCTAssertEqual(mismatch.summary.actionLabel, "检查路径设置")
        XCTAssertEqual(mismatch.summary.status, .blocked)

        let indexMissing = NativeStatusDiagnostics(
            workspaceDirectoryCount: 3,
            indexRecordCount: 0,
            widgetUpdatedAt: nil,
            latestAuditAction: nil,
            latestAuditTarget: nil,
            latestAuditTargetExists: nil
        )

        XCTAssertEqual(indexMissing.summary.title, "目录存在但索引为空")
        XCTAssertEqual(indexMissing.summary.actionLabel, "重新扫描")
        XCTAssertEqual(indexMissing.summary.status, .review)
    }

    func testWorkspaceStatusDiagnosticCardSurfacesOneDetailAction() {
        let diagnostics = NativeStatusDiagnostics(
            workspaceDirectoryCount: 0,
            indexRecordCount: 2,
            widgetUpdatedAt: nil,
            latestAuditAction: "workspace.created",
            latestAuditTarget: "/tmp/missing-workspace",
            latestAuditTargetExists: false
        )

        let card = diagnostics.workspaceDetailCard

        XCTAssertEqual(card.title, "状态诊断")
        XCTAssertEqual(card.helpText, "Status diagnostics")
        XCTAssertEqual(card.summary.title, "索引有记录但真实目录为 0")
        XCTAssertEqual(card.primaryActionLabel, "检查路径设置")
        XCTAssertEqual(card.status, .blocked)
        XCTAssertEqual(card.items.map(\.id), ["directories", "index", "widget", "audit"])
        XCTAssertEqual(card.visibleItems.map(\.id), ["directories", "widget"])
        XCTAssertEqual(card.collapsedItems.map(\.id), ["index", "audit"])
        XCTAssertTrue(card.detailsCollapsedByDefault)
        XCTAssertEqual(card.detailLabel, "诊断明细 / Diagnostics (2)")
        XCTAssertEqual(card.attentionCount, 3)
        XCTAssertFalse(card.isReady)
    }

    func testMenuBarStatusSummaryPrioritizesBlockedWorkspaces() {
        let summary = MenuBarStatusSummary(
            workspaceCount: 4,
            activeWorkspaceCount: 3,
            archivedWorkspaceCount: 1,
            riskyWorkspaceCount: 2,
            blockedWorkspaceCount: 1,
            openTaskCount: 7,
            highPriorityTaskCount: 3,
            agentTaskCount: 2,
            missingWorktreeCount: 1,
            dirtyServiceCount: 1,
            activeWorkspaceName: "Pay Log",
            activeStageLine: "交付检查 · 阻塞：SQL rollback evidence is missing. · 下一步: 查看 SQL · 证据: sql/release.sql",
            bridgeMode: "preview"
        )

        XCTAssertEqual(summary.menuTitle, "Nexus 1")
        XCTAssertEqual(summary.systemImage, "pause.circle.fill")
        XCTAssertEqual(summary.statusLine, "1 blocked workspaces need attention")
        XCTAssertTrue(summary.clipboardText.contains("Active workspace: Pay Log"))
        XCTAssertTrue(summary.clipboardText.contains("Active stage: 交付检查"))
        XCTAssertTrue(summary.clipboardText.contains("证据: sql/release.sql"))
        XCTAssertTrue(summary.clipboardText.contains("Archived workspaces: 1"))
    }

    func testMenuBarStatusSummaryPrioritizesWorktreeAttentionBeforeTasks() {
        let missing = MenuBarStatusSummary(
            workspaceCount: 3,
            activeWorkspaceCount: 3,
            archivedWorkspaceCount: 0,
            riskyWorkspaceCount: 0,
            blockedWorkspaceCount: 0,
            openTaskCount: 5,
            highPriorityTaskCount: 2,
            agentTaskCount: 1,
            missingWorktreeCount: 2,
            dirtyServiceCount: 0,
            activeWorkspaceName: "Checkout",
            activeStageLine: "Worktree · 阻塞：Missing worktree. · 下一步: 创建 worktree · 证据: scripts/worktree-commands.sh",
            bridgeMode: "ffi"
        )

        XCTAssertEqual(missing.menuTitle, "Nexus 2")
        XCTAssertEqual(missing.systemImage, "exclamationmark.triangle.fill")
        XCTAssertEqual(missing.statusLine, "2 worktrees are missing")
        XCTAssertTrue(missing.clipboardText.contains("Status: 2 worktrees are missing"))

        let dirty = MenuBarStatusSummary(
            workspaceCount: 2,
            activeWorkspaceCount: 2,
            archivedWorkspaceCount: 0,
            riskyWorkspaceCount: 0,
            blockedWorkspaceCount: 0,
            openTaskCount: 3,
            highPriorityTaskCount: 1,
            agentTaskCount: 0,
            missingWorktreeCount: 0,
            dirtyServiceCount: 4,
            activeWorkspaceName: nil,
            activeStageLine: nil,
            bridgeMode: "ffi"
        )

        XCTAssertEqual(dirty.menuTitle, "Nexus 4")
        XCTAssertEqual(dirty.statusLine, "4 services have uncommitted changes")
        XCTAssertTrue(dirty.clipboardText.contains("Status: 4 services have uncommitted changes"))
    }

    func testWorkspaceLifecycleFallsBackToSetupWhenWorktreesAreMissing() {
        let lifecycle = WorkspaceLifecycle(
            snapshot: nil,
            state: "developing",
            targetBranch: "feature/native-tests",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/native-tests",
                    worktree: "missing",
                    gitSummary: "source clean",
                    worktreeExists: false,
                    sourceExists: true
                )
            ],
            risks: [],
            tasks: []
        )

        XCTAssertEqual(lifecycle.stage, "setup")
        XCTAssertEqual(lifecycle.documentKey, "worktreeScript")
        XCTAssertEqual(lifecycle.normalizedProgress, 0.35)
    }

    func testWorkspaceLifecycleFallsBackToDoneWhenNoOpenTasksOrRisksRemain() {
        let lifecycle = WorkspaceLifecycle(
            snapshot: nil,
            state: "unknown",
            targetBranch: "feature/native-tests",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/native-tests",
                    worktree: "ready",
                    gitSummary: "clean",
                    worktreeExists: true,
                    sourceExists: true
                )
            ],
            risks: [],
            tasks: [
                WorkspaceTask(
                    id: "task-1",
                    title: "Ship",
                    status: "done",
                    detail: "Merged",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 12
                )
            ]
        )

        XCTAssertEqual(lifecycle.stage, "done")
        XCTAssertEqual(lifecycle.documentKey, "delivery")
        XCTAssertEqual(lifecycle.normalizedProgress, 0.95)
    }

    func testWorkspaceLifecycleHonorsExplicitRestoreDevelopmentState() {
        let lifecycle = WorkspaceLifecycle(
            snapshot: nil,
            state: "developing",
            targetBranch: "feature/native-tests",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/native-tests",
                    worktree: "ready",
                    gitSummary: "clean",
                    worktreeExists: true,
                    sourceExists: true
                )
            ],
            risks: [],
            tasks: [
                WorkspaceTask(
                    id: "task-1",
                    title: "Previously shipped",
                    status: "done",
                    detail: "Restored from archive for re-check",
                    priority: "normal",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 12
                )
            ]
        )

        XCTAssertEqual(lifecycle.stage, "developing")
        XCTAssertEqual(lifecycle.documentKey, "tasks")
        XCTAssertEqual(lifecycle.normalizedProgress, 0.6)
    }

    func testLifecycleRestorePostWriteChecksRequireLocalRecheck() {
        let workspace = workspaceForWorkflowSummary(
            stage: "archived",
            id: "restore-post-write",
            path: "/tmp/restore-post-write"
        )
        let checks = LifecycleStatusUpdate.postWriteChecks(
            for: .restoreDevelopment,
            workspace: workspace
        )
        let update = LifecycleStatusUpdate(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            currentStage: workspace.lifecycle.stage,
            currentLabel: workspace.lifecycle.label,
            nextState: LifecycleTransition.restoreDevelopment.state,
            nextLabel: LifecycleTransition.restoreDevelopment.label,
            focus: LifecycleTransition.restoreDevelopment.focus,
            nextAction: LifecycleTransition.restoreDevelopment.nextAction,
            postWriteChecks: checks
        )

        XCTAssertTrue(update.requiresLocalCheckAfterWrite)
        XCTAssertEqual(checks.map(\.id), ["local-check", "branch-worktree", "tasks-risks", "delivery-record"])
        XCTAssertTrue(update.evidencePaths.contains("/tmp/restore-post-write/交付记录.md"))
        XCTAssertTrue(checks.first?.detail.contains("重新计算阶段") == true)
    }

    func testLifecycleArchivePostWriteChecksKeepWorkspaceReadOnlyAndEvidenceVisible() {
        let workspace = workspaceForWorkflowSummary(
            stage: "done",
            id: "archive-post-write",
            path: "/tmp/archive-post-write"
        )
        let checks = LifecycleStatusUpdate.postWriteChecks(
            for: .archived,
            workspace: workspace
        )
        let update = LifecycleStatusUpdate(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            currentStage: workspace.lifecycle.stage,
            currentLabel: workspace.lifecycle.label,
            nextState: LifecycleTransition.archived.state,
            nextLabel: LifecycleTransition.archived.label,
            focus: LifecycleTransition.archived.focus,
            nextAction: LifecycleTransition.archived.nextAction,
            postWriteChecks: checks
        )

        XCTAssertFalse(update.requiresLocalCheckAfterWrite)
        XCTAssertEqual(checks.map(\.id), ["archive-refresh", "delivery-evidence", "handoff-evidence"])
        XCTAssertTrue(update.evidencePaths.contains("/tmp/archive-post-write/交付记录.md"))
        XCTAssertTrue(update.evidencePaths.contains("/tmp/archive-post-write/handoff.md"))
        XCTAssertTrue(checks.first?.detail.contains("退出活跃风险") == true)
    }

    func testTaskStatusWritebackChecksRequireLocalCheckWhenClosingActiveTask() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "task-writeback",
            path: "/tmp/task-writeback"
        )
        let task = WorkspaceTask(
            id: "task-1",
            title: "Finish Native task",
            status: "todo",
            detail: "ready",
            priority: "high",
            source: "workspace",
            sourceEventID: nil,
            sourceLine: 12
        )
        let checks = TaskStatusUpdate.postWriteChecks(
            for: task,
            workspace: workspace,
            nextStatus: "已完成"
        )
        let update = TaskStatusUpdate(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            taskID: task.id,
            taskTitle: task.title,
            taskDetail: task.detail,
            taskPriority: task.priority,
            taskSourceLine: task.sourceLine,
            currentStatus: task.status,
            nextStatus: "已完成",
            postWriteChecks: checks
        )

        XCTAssertTrue(update.requiresLocalCheckAfterWrite)
        XCTAssertTrue(update.requiresConfirmationSheet)
        XCTAssertEqual(update.mutationPolicy.kind, .close)
        XCTAssertEqual(update.mutationPolicy.targetDocumentName, "root tasks.md")
        XCTAssertEqual(checks.map(\.id), ["task-row", "next-task", "local-check"])
        XCTAssertEqual(update.tasksPath, "/tmp/task-writeback/tasks.md")
        XCTAssertTrue(update.evidencePaths.contains("/tmp/task-writeback/STATUS.md"))
        XCTAssertTrue(checks.first?.detail.contains("第 12 行") == true)
    }

    func testTaskStatusWritebackChecksKeepProgressUpdatesLightweight() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "task-progress-writeback",
            path: "/tmp/task-progress-writeback"
        )
        let task = WorkspaceTask(
            id: "task-1",
            title: "Continue Native task",
            status: "todo",
            detail: "ready",
            priority: "medium",
            source: "workspace",
            sourceEventID: nil,
            sourceLine: nil
        )
        let checks = TaskStatusUpdate.postWriteChecks(
            for: task,
            workspace: workspace,
            nextStatus: "doing"
        )

        XCTAssertFalse(checks.contains { $0.id == "local-check" })
        XCTAssertEqual(checks.map(\.id), ["task-row", "next-task"])
        XCTAssertTrue(checks.first?.detail.contains("root tasks.md") == true)

        let policy = TaskStatusMutationPolicy.resolve(nextStatus: "doing")
        XCTAssertEqual(policy.kind, .progress)
        XCTAssertTrue(policy.requiresConfirmationSheet)
        XCTAssertEqual(policy.targetDocumentName, "root tasks.md")
    }

    func testTaskCenterFiltersMatchHighPriorityAgentAndDeferredTasks() {
        let blocked = TaskCenterItem(
            workspaceID: "workspace-a",
            workspaceName: "Workspace A",
            workspaceFolder: "workspace-a",
            task: WorkspaceTask(
                id: "blocked",
                title: "Fix blocker",
                status: "blocked",
                detail: "blocked by approval",
                priority: "low",
                source: "workspace",
                sourceEventID: nil,
                sourceLine: 4
            )
        )
        let agentDeferred = TaskCenterItem(
            workspaceID: "workspace-b",
            workspaceName: "Workspace B",
            workspaceFolder: "workspace-b",
            task: WorkspaceTask(
                id: "agent",
                title: "Follow up",
                status: "todo",
                detail: "deferred until CI finishes",
                priority: "medium",
                source: "agent",
                sourceEventID: "event-1",
                sourceLine: nil
            )
        )
        let highDeferred = TaskCenterItem(
            workspaceID: "workspace-c",
            workspaceName: "Workspace C",
            workspaceFolder: "workspace-c",
            task: WorkspaceTask(
                id: "high-deferred",
                title: "Later high priority",
                status: "延期",
                detail: "deferred until release window",
                priority: "high",
                source: "workspace",
                sourceEventID: nil,
                sourceLine: nil
            )
        )

        XCTAssertTrue(TaskCenterFilter.high.matches(blocked))
        XCTAssertTrue(TaskCenterFilter.agent.matches(agentDeferred))
        XCTAssertTrue(TaskCenterFilter.deferred.matches(agentDeferred))
        XCTAssertTrue(TaskCenterFilter.deferred.matches(highDeferred))
        XCTAssertFalse(TaskCenterFilter.high.matches(highDeferred))
        XCTAssertFalse(TaskCenterFilter.agent.matches(blocked))
    }

    func testTaskCenterItemIdentitySeparatesDuplicateCanonicalTaskIDsBySourceLine() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-task-center-duplicate-id-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try "# Workspace\n\n- 当前状态: developing\n".write(
            to: workspaceURL.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | First Agent task | 进行中 | event=shared-event |
        | Second Agent task | 待办 | event=shared-event |
        """.write(
            to: workspaceURL.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )

        let dashboard = try NativeWorkspaceScanner.scan(
            workspacesRoot: root.path,
            sourceReposRoot: root.appendingPathComponent("source-repos").path,
            docsRoot: root.appendingPathComponent("docs").path
        )
        let workspace = WorkspaceSummary(snapshot: try XCTUnwrap(dashboard.workspaces.first))
        let items = workspace.tasks.map {
            TaskCenterItem(
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                workspaceFolder: workspace.folder,
                task: $0
            )
        }

        XCTAssertEqual(workspace.tasks.map(\.id), ["workspace:shared-event", "workspace:shared-event"])
        XCTAssertEqual(workspace.tasks.map(\.sourceLine), [5, 6])
        XCTAssertNotEqual(items[0].id, items[1].id)
        XCTAssertEqual(items[0].id, "workspace:workspace:shared-event:L5")
        XCTAssertEqual(items[1].id, "workspace:workspace:shared-event:L6")
        XCTAssertEqual(
            TaskCenterItem(
                workspaceID: workspace.id,
                workspaceName: workspace.name,
                workspaceFolder: workspace.folder,
                task: WorkspaceTask(
                    id: "workspace:shared-event",
                    title: "No line evidence",
                    status: "待办",
                    detail: "",
                    priority: "normal",
                    source: "agent",
                    sourceEventID: "shared-event",
                    sourceLine: nil
                )
            ).id,
            "workspace:workspace:shared-event:I0"
        )
    }

    @MainActor
    func testTaskCenterAppStatePresentationIndexSeparatesNilSourceLineDuplicateIDs() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "duplicate-nil-lines",
            tasks: [
                WorkspaceTask(
                    id: "duplicate",
                    title: "First duplicate",
                    status: "进行中",
                    detail: "",
                    priority: "normal",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: nil
                ),
                WorkspaceTask(
                    id: "duplicate",
                    title: "Second duplicate",
                    status: "待办",
                    detail: "",
                    priority: "normal",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: nil
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [workspace])
        let items = appState.taskCenterItems.filter { $0.task.id == "duplicate" }

        XCTAssertEqual(items.map(\.task.id), ["duplicate", "duplicate"])
        XCTAssertNotEqual(items[0].id, items[1].id)
        XCTAssertEqual(items.map(\.id), [
            "duplicate-nil-lines:duplicate:I0",
            "duplicate-nil-lines:duplicate:I1"
        ])
    }

    @MainActor
    func testTaskCenterContinuationPrefersSameWorkspaceActiveTask() {
        let sameWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "same-workspace",
            name: "Same Workspace",
            tasks: [
                WorkspaceTask(
                    id: "closed",
                    title: "Closed task",
                    status: "已完成",
                    detail: "Already done",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 7
                ),
                WorkspaceTask(
                    id: "same-next",
                    title: "Continue here",
                    status: "待办",
                    detail: "Next active task in the updated workspace",
                    priority: "medium",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 8
                )
            ]
        )
        let otherWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "other-workspace",
            name: "Other Workspace",
            tasks: [
                WorkspaceTask(
                    id: "other-next",
                    title: "Other active task",
                    status: "待办",
                    detail: "Should only be used as fallback",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 4
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [otherWorkspace, sameWorkspace])
        appState.setTaskCenterFilter(.high)
        let feedback = LocalWriteFeedback(
            title: "任务状态已写回 / Task updated",
            detail: "Closed task: 待办 -> 已完成。",
            timestamp: "2026-06-01 10:00",
            workspaceID: sameWorkspace.id,
            workspaceName: sameWorkspace.name,
            documentPath: "\(sameWorkspace.path)/tasks.md",
            documentLabel: "打开 tasks.md",
            systemImage: "checkmark.circle"
        )

        let nextTask = appState.nextTaskCenterItem(after: feedback)
        appState.focusNextTask(after: feedback)

        XCTAssertEqual(nextTask?.task.id, "same-next")
        XCTAssertEqual(appState.selectedTaskCenterFilter, .all)
        XCTAssertEqual(appState.selectedWorkspaceID, sameWorkspace.id)
        XCTAssertEqual(appState.focusedTaskCenterItemID, "\(sameWorkspace.id):same-next:L8")
    }

    func testWorkspaceFiltersMatchLifecycleRiskAndSearchQuery() {
        let workspaces = WorkspaceSummary.previewData

        XCTAssertEqual(workspaces.filter { WorkspaceFilter.all.matches($0) }.count, 2)
        XCTAssertEqual(workspaces.filter { WorkspaceFilter.active.matches($0) }.count, 2)
        XCTAssertEqual(workspaces.filter { WorkspaceFilter.risky.matches($0) }.count, 1)
        XCTAssertEqual(workspaces.filter { WorkspaceFilter.blocked.matches($0) }.count, 0)
        XCTAssertEqual(workspaces.filter { WorkspaceFilter.archived.matches($0) }.count, 0)

        XCTAssertEqual(
            workspaces.filter { WorkspaceFilter.all.matches($0, query: "pay_log") }.map(\.id),
            ["2026-05-25-yibao-pay-log"]
        )
        XCTAssertEqual(
            workspaces.filter { WorkspaceFilter.risky.matches($0, query: "pricing") }.map(\.id),
            []
        )
        XCTAssertEqual(
            workspaces.filter { WorkspaceFilter.active.matches($0, query: "pricing") }.map(\.id),
            ["2026-05-25-multi-price"]
        )
        XCTAssertEqual(
            workspaces.filter { WorkspaceFilter.all.matches($0, query: "backfill_rollback") }.map(\.id),
            ["2026-05-25-yibao-pay-log"]
        )
    }

    func testWorkspaceListSummaryExcludesArchivedWorkspacesFromActiveSignals() {
        let active = workspaceForWorkflowSummary(
            stage: "developing",
            id: "summary-active",
            riskLevel: .high,
            services: [
                ServiceStatus(
                    name: "orders",
                    branch: "feature/orders",
                    worktree: "missing",
                    gitSummary: "dirty",
                    worktreeExists: false,
                    sourceExists: true
                )
            ],
            tasks: [
                WorkspaceTask(
                    id: "active-high",
                    title: "Active high",
                    status: "todo",
                    detail: "Open",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 1
                )
            ]
        )
        let archived = workspaceForWorkflowSummary(
            stage: "archived",
            id: "summary-archived",
            riskLevel: .high,
            services: [
                ServiceStatus(
                    name: "payments",
                    branch: "feature/payments",
                    worktree: "missing",
                    gitSummary: "dirty",
                    worktreeExists: false,
                    sourceExists: true
                )
            ],
            tasks: [
                WorkspaceTask(
                    id: "archived-high",
                    title: "Archived high",
                    status: "todo",
                    detail: "Archived work should not count active signals.",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 2
                )
            ]
        )

        let summary = WorkspaceListSummary(workspaces: [active, archived])

        XCTAssertEqual(summary.totalWorkspaceCount, 2)
        XCTAssertEqual(summary.activeWorkspaceCount, 1)
        XCTAssertEqual(summary.archivedWorkspaceCount, 1)
        XCTAssertEqual(summary.riskyWorkspaceCount, 1)
        XCTAssertEqual(summary.openTaskCount, 1)
        XCTAssertEqual(summary.highPriorityTaskCount, 1)
        XCTAssertEqual(summary.missingWorktreeCount, 1)
        XCTAssertEqual(summary.dirtyServiceCount, 1)
        XCTAssertTrue(summary.archivedExclusionLabel.contains("活跃统计已排除"))
    }

    func testWorkspaceDetailNavigationMapOnlyRoutesToSections() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "detail-navigation",
            name: "Detail Navigation",
            tasks: [
                WorkspaceTask(
                    id: "blocked-task",
                    title: "Fix blocked task",
                    status: "blocked",
                    detail: "Waiting on dependency",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 42
                )
            ]
        )
        let mainStage = WorkspaceMainStage(
            id: .development,
            status: .blocked,
            title: "Development",
            reason: "Blocked task",
            primaryActionLabel: "查看任务",
            primaryActionSystemImage: "checklist",
            primaryAction: .task("blocked-task"),
            evidence: ["tasks.md"],
            nextStageAllowed: false
        )
        let demandStatus = DemandIntakeStatus(
            directoryPath: "\(workspace.path)/需求",
            exists: true,
            ready: false,
            missingCount: 1,
            files: []
        )

        let navigationMap = WorkspaceDetailNavigationMap(
            workspace: workspace,
            mainStage: mainStage,
            demandStatus: demandStatus
        )

        XCTAssertEqual(navigationMap.items.map(\.section), WorkspaceDetailSection.allCases)
        XCTAssertTrue(navigationMap.items.allSatisfy(\.isNavigationOnly))
        XCTAssertEqual(navigationMap.items.first { $0.section == .command }?.detail, WorkspaceMainStageID.development.shortLabel)
        XCTAssertEqual(navigationMap.items.first { $0.section == .demand }?.detail, "缺 1")
        XCTAssertEqual(navigationMap.items.first { $0.section == .workflow }?.detail, "1 阻塞")
    }

    func testMainStageKeepsFreshScopingWorkspaceAtCreatedBeforeDemandEvidence() {
        let workspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "fresh-workspace",
            name: "Fresh Workspace"
        )

        let stage = workspace.mainStage()

        XCTAssertEqual(stage.id, .created)
        XCTAssertEqual(stage.status, .next)
        XCTAssertEqual(stage.primaryAction, .demandIntake)
        XCTAssertTrue(stage.reason.contains("尚未读取到需求预检证据"))
        XCTAssertFalse(stage.nextStageAllowed)
    }

    func testMainStageTreatsMissingDemandDirectoryAsCreatedBeforeDemandIntake() {
        let workspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "missing-demand-directory",
            name: "Missing Demand Directory"
        )
        let demandStatus = DemandIntakeStatus(
            directoryPath: "\(workspace.path)/需求",
            exists: false,
            ready: false,
            missingCount: 5,
            files: []
        )
        let readiness = DemandIntakeReadinessEvidence.resolve(status: demandStatus, workspace: workspace)

        let stage = workspace.mainStage(
            demandIntakeStatus: demandStatus,
            demandReadiness: readiness
        )

        XCTAssertEqual(stage.id, .created)
        XCTAssertEqual(stage.primaryAction, .demandIntake)
        XCTAssertTrue(stage.evidenceSummary.contains("需求/"))
    }

    func testDemandIntakeM1ActionPolicyKeepsAIInvocationOutOfPrimaryFlow() {
        let workspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "demand-action-policy",
            name: "Demand Action Policy"
        )
        let status = DemandIntakeStatus(
            directoryPath: "\(workspace.path)/需求",
            exists: true,
            ready: false,
            missingCount: 1,
            files: []
        )
        let writablePlan = NativeDemandIntakeInitializationPlan(
            workspacePath: workspace.path,
            demandDirectoryPath: "\(workspace.path)/需求",
            demandName: workspace.name,
            lanhuLink: "",
            notes: "",
            expectedWorkspaceState: .directory,
            expectedDemandDirectoryState: .directory,
            filePlans: [
                NativeDemandIntakeFilePlan(
                    key: "requirement",
                    label: "需求确认卡",
                    filename: "requirement.md",
                    path: "\(workspace.path)/需求/requirement.md",
                    expectedState: .missing,
                    template: "# Requirement\n"
                )
            ],
            blockerSummary: nil
        )
        let completePlan = NativeDemandIntakeInitializationPlan(
            workspacePath: workspace.path,
            demandDirectoryPath: "\(workspace.path)/需求",
            demandName: workspace.name,
            lanhuLink: "",
            notes: "",
            expectedWorkspaceState: .directory,
            expectedDemandDirectoryState: .directory,
            filePlans: [
                NativeDemandIntakeFilePlan(
                    key: "requirement",
                    label: "需求确认卡",
                    filename: "requirement.md",
                    path: "\(workspace.path)/需求/requirement.md",
                    expectedState: .regularUTF8(sha256: "complete", byteCount: 1),
                    template: "# Requirement\n"
                )
            ],
            blockerSummary: "demand intake is already complete; no files will be created"
        )

        let unconfirmedPolicy = DemandIntakeM1ActionPolicy(
            status: status,
            confirmed: false,
            isInitializing: false,
            requirementFileExists: false,
            initializationPlan: writablePlan
        )
        let confirmedPolicy = DemandIntakeM1ActionPolicy(
            status: status,
            confirmed: true,
            isInitializing: false,
            requirementFileExists: true,
            initializationPlan: writablePlan
        )
        let completePolicy = DemandIntakeM1ActionPolicy(
            status: DemandIntakeStatus(
                directoryPath: status.directoryPath,
                exists: true,
                ready: true,
                missingCount: 0,
                files: []
            ),
            confirmed: true,
            isInitializing: false,
            requirementFileExists: true,
            initializationPlan: completePlan
        )

        XCTAssertEqual(unconfirmedPolicy.actions.map(\.kind), [.initializeOrRepair, .openRequirement, .copyHandoffPrompt])
        XCTAssertTrue(unconfirmedPolicy.keepsAIInvocationOutOfM1)
        XCTAssertFalse(unconfirmedPolicy.actions.first { $0.kind == .initializeOrRepair }?.isEnabled ?? true)
        XCTAssertFalse(unconfirmedPolicy.actions.first { $0.kind == .openRequirement }?.isEnabled ?? true)
        XCTAssertTrue(confirmedPolicy.actions.first { $0.kind == .initializeOrRepair }?.isEnabled ?? false)
        XCTAssertTrue(confirmedPolicy.actions.first { $0.kind == .openRequirement }?.isEnabled ?? false)
        XCTAssertTrue(confirmedPolicy.actions.first { $0.kind == .copyHandoffPrompt }?.label.contains("交接") ?? false)
        XCTAssertFalse(completePolicy.actions.first { $0.kind == .initializeOrRepair }?.isEnabled ?? true)
        XCTAssertFalse(completePolicy.actions.first { $0.kind == .initializeOrRepair }?.isPrimary ?? true)
        XCTAssertTrue(completePolicy.actions.first { $0.kind == .openRequirement }?.isPrimary ?? false)
    }

    func testMainStageAlwaysExplainsStageActionAndEvidence() {
        let workspaces = WorkspaceSummary.previewData + [
            workspaceForWorkflowSummary(
                stage: "scoping",
                id: "contract-created",
                name: "Contract Created"
            ),
            workspaceForWorkflowSummary(
                stage: "archived",
                id: "contract-archived",
                name: "Contract Archived"
            ),
            workspaceForWorkflowSummary(
                stage: "developing",
                id: "contract-active-task",
                name: "Contract Active Task",
                tasks: [
                    WorkspaceTask(
                        id: "contract-task",
                        title: "Keep main path explicit",
                        status: "待办",
                        detail: "Exercise development-stage explanation.",
                        priority: "high",
                        source: "workspace",
                        sourceEventID: nil,
                        sourceLine: 9
                    )
                ]
            )
        ]

        for workspace in workspaces {
            let stage = workspace.mainStage()

            XCTAssertTrue(
                WorkspaceMainStageID.allCases.contains(stage.id),
                "\(workspace.id) produced an unknown main stage: \(stage.id)"
            )
            XCTAssertFalse(stage.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, workspace.id)
            XCTAssertFalse(stage.reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, workspace.id)
            XCTAssertFalse(stage.primaryActionLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, workspace.id)
            XCTAssertFalse(stage.primaryActionSystemImage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, workspace.id)
            XCTAssertFalse(stage.evidence.isEmpty, workspace.id)
            XCTAssertFalse(stage.evidenceSummary.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, workspace.id)
        }
    }

    func testMainWorkflowAcceptanceEvidenceRequiresEveryM1Gate() {
        let stages = WorkspaceMainStageID.allCases.map { stageID in
            WorkspaceMainStage(
                id: stageID,
                status: stageID == .archived ? .ready : .next,
                title: stageID.label,
                reason: "Stage \(stageID.rawValue) is represented in the Native main path.",
                primaryActionLabel: "继续",
                primaryActionSystemImage: stageID.systemImage,
                primaryAction: .document("status"),
                evidence: ["STATUS.md"],
                nextStageAllowed: stageID == .archived
            )
        }
        let demand = DemandIntakeReadinessEvidence(
            status: .ready,
            reason: "Demand intake complete.",
            evidence: ["需求/requirement.md", "需求/questions.md", "需求/scope.md", "需求/tasks.md"],
            checks: [],
            unresolvedP0Count: 0,
            requirementHasContent: true,
            scopeFrozen: true,
            requirementTasksReady: true
        )
        let development = DevelopmentTaskEvidence(
            status: .ready,
            reason: "Tasks clear.",
            evidence: ["tasks.md", "需求/tasks.md"],
            sources: [
                DevelopmentTaskSource(
                    role: .executionQueue,
                    path: "/tmp/main-acceptance/tasks.md",
                    detail: "Root execution queue.",
                    participatesInExecutionQueue: true
                ),
                DevelopmentTaskSource(
                    role: .intakeEvidence,
                    path: "/tmp/main-acceptance/需求/tasks.md",
                    detail: "Demand intake evidence only.",
                    participatesInExecutionQueue: false
                )
            ],
            checks: [],
            tasksPath: "/tmp/main-acceptance/tasks.md",
            taskPlan: [],
            activeTasks: [],
            blockedTasks: [],
            deferredTaskCount: 0,
            doneTaskCount: 1,
            nextTask: nil
        )
        let worktreeRows = ServiceWorktreeRowStateKind.allCases.map { kind in
            ServiceWorktreeRowState(
                serviceName: kind.rawValue,
                kind: kind,
                label: kind.rawValue,
                detail: "Covered by acceptance fixture.",
                status: kind == .clean ? .ready : .review,
                systemImage: "checkmark.circle"
            )
        }
        let delivery = DeliveryGateEvidence(
            status: .ready,
            title: "Delivery ready",
            reason: "All delivery checks pass.",
            value: "ready",
            evidence: ["tasks.md", "交付记录.md", "sql/"],
            checks: ["tasks", "risks", "sql", "dirty-services"].map { id in
                DeliveryGateCheck(
                    id: id,
                    label: id,
                    detail: "Covered by acceptance fixture.",
                    status: .ready,
                    systemImage: "checkmark.circle",
                    path: "/tmp/main-acceptance/\(id).md",
                    action: .document("delivery")
                )
            },
            resolutionPlan: [],
            primaryActionLabel: "打开交付",
            primaryActionSystemImage: "doc.text",
            primaryAction: .document("delivery"),
            blockerCount: 0,
            warningCount: 0
        )
        let archive = ArchiveGateEvidence(
            status: .ready,
            title: "Ready to archive",
            reason: "Delivery gate reused.",
            value: "ready",
            evidence: ["交付记录.md", "handoff.md", "STATUS.md"],
            checks: [
                ArchiveGateCheck(
                    id: "delivery-tasks",
                    label: "Tasks",
                    detail: "Archive reuses delivery task gate.",
                    status: .ready,
                    systemImage: "checkmark.circle",
                    path: "/tmp/main-acceptance/tasks.md",
                    action: .document("tasks")
                )
            ],
            confirmationPlan: [
                ArchiveConfirmationPlanItem(
                    id: "delivery-reuse",
                    title: "Reuse delivery gate",
                    action: .archive,
                    status: .ready,
                    detail: "Archive confirmation depends on delivery evidence.",
                    evidencePath: "/tmp/main-acceptance/交付记录.md",
                    gateAction: .lifecycle(.archived),
                    confirmationHint: "Confirmed archive writeback."
                )
            ],
            primaryActionLabel: "归档",
            primaryActionSystemImage: "archivebox",
            primaryAction: .lifecycle(.archived),
            blockerCount: 0,
            warningCount: 0
        )

        let acceptance = MainWorkflowAcceptanceEvidence.resolve(
            stages: stages,
            demandReadiness: demand,
            developmentTasks: development,
            worktreeRows: worktreeRows,
            deliveryGate: delivery,
            archiveGate: archive,
            legacyBoundary: .nativeOnly
        )

        XCTAssertTrue(acceptance.ready)
        XCTAssertEqual(acceptance.status, .ready)
        XCTAssertEqual(acceptance.observedStages, WorkspaceMainStageID.allCases)
        XCTAssertTrue(acceptance.missingStages.isEmpty)
        XCTAssertTrue(acceptance.stagesMissingCurrentStateAnswer.isEmpty)
        XCTAssertTrue(acceptance.stagesMissingPrimaryAction.isEmpty)
        XCTAssertTrue(acceptance.stagesMissingEvidence.isEmpty)
        XCTAssertEqual(acceptance.coveredWorktreeStates, ServiceWorktreeRowStateKind.allCases)
        XCTAssertEqual(acceptance.checks.map(\.id), MainWorkflowAcceptanceRequirement.allCases)
        XCTAssertTrue(acceptance.reason.contains("M1 主链路验收证据"))
    }

    @MainActor
    func testAppStateBuildsGlobalMainWorkflowAcceptanceEvidence() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "appstate-main-acceptance",
            branch: "feature/native-main",
            services: [
                ServiceStatus(
                    name: "missing-source",
                    branch: "feature/native-main",
                    worktree: "missing",
                    gitSummary: "source missing",
                    worktreeExists: false,
                    sourceExists: false
                ),
                ServiceStatus(
                    name: "missing-worktree",
                    branch: "feature/native-main",
                    worktree: "missing",
                    gitSummary: "source clean",
                    worktreeExists: false,
                    sourceExists: true
                ),
                ServiceStatus(
                    name: "branch-mismatch",
                    branch: "develop",
                    worktree: "ready",
                    gitSummary: "target branch missing: feature/native-main",
                    worktreeExists: true,
                    sourceExists: true
                ),
                ServiceStatus(
                    name: "dirty",
                    branch: "feature/native-main",
                    worktree: "dirty",
                    gitSummary: "dirty",
                    worktreeExists: true,
                    sourceExists: true
                ),
                ServiceStatus(
                    name: "clean",
                    branch: "origin/feature/native-main",
                    worktree: "ready",
                    gitSummary: "clean",
                    worktreeExists: true,
                    sourceExists: true
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [workspace])

        let acceptance = appState.globalMainWorkflowAcceptanceEvidence()

        XCTAssertEqual(acceptance.checks.map(\.id), MainWorkflowAcceptanceRequirement.allCases)
        XCTAssertEqual(acceptance.coveredWorktreeStates, ServiceWorktreeRowStateKind.allCases)
        XCTAssertTrue(acceptance.missingWorktreeStates.isEmpty)
        XCTAssertEqual(acceptance.checks.first { $0.id == .legacyBoundary }?.status, .ready)
        XCTAssertEqual(acceptance.checks.first { $0.id == .worktreeStateCoverage }?.status, .ready)
        XCTAssertEqual(acceptance.checks.first { $0.id == .stageCoverage }?.status, .blocked)
    }

    func testMainWorkflowAcceptanceEvidenceAggregatesCandidateGatesOrderIndependently() {
        let blockedDemand = DemandIntakeReadinessEvidence(
            status: .blocked,
            reason: "P0 remains unresolved.",
            evidence: ["/tmp/blocked/需求/questions.md"],
            checks: [],
            unresolvedP0Count: 1,
            requirementHasContent: true,
            scopeFrozen: false,
            requirementTasksReady: true
        )
        let readyDemand = readyDemandReadiness()

        let forward = MainWorkflowAcceptanceEvidence.resolveGlobal(
            stages: [],
            demandReadinessCandidates: [blockedDemand, readyDemand],
            developmentTaskCandidates: [],
            worktreeRows: [],
            deliveryGateCandidates: [],
            archiveGateCandidates: [],
            legacyBoundary: .nativeOnly
        )
        let reversed = MainWorkflowAcceptanceEvidence.resolveGlobal(
            stages: [],
            demandReadinessCandidates: [readyDemand, blockedDemand],
            developmentTaskCandidates: [],
            worktreeRows: [],
            deliveryGateCandidates: [],
            archiveGateCandidates: [],
            legacyBoundary: .nativeOnly
        )

        let forwardDemand = forward.checks.first { $0.id == .demandBlocksDevelopment }
        let reversedDemand = reversed.checks.first { $0.id == .demandBlocksDevelopment }
        XCTAssertEqual(forwardDemand, reversedDemand)
        XCTAssertEqual(forwardDemand?.status, .ready)
        XCTAssertTrue(forwardDemand?.evidence.contains("需求/") == true)
    }

    func testNativeLocalCoreEvidenceTracksM2BridgeDependencies() {
        let preview = NativeLocalCoreEvidence.resolve(
            bridgeMode: "Preview bridge: set NEXUS_CORE_LIBRARY to load Rust Core"
        )
        let partiallyNative = NativeLocalCoreEvidence.resolve(
            bridgeMode: "Rust Core bridge: /tmp/libnexus_ffi.dylib",
            nativeDomains: [.workspaceScanning, .documentInventory, .audit, .searchIndex, .widgetSnapshot],
            partialNativeDomains: [.gitWorktreeStatus]
        )
        let fullyNative = NativeLocalCoreEvidence.resolve(
            bridgeMode: "Swift Native local core",
            nativeDomains: Set(NativeLocalCoreDomain.allCases)
        )

        XCTAssertEqual(preview.status, .blocked)
        XCTAssertTrue(preview.bridgeIsLegacyDependency)
        XCTAssertEqual(preview.migrationSummary, "0/11 Native domains")
        XCTAssertEqual(preview.domains.map(\.status), Array(repeating: .blocked, count: NativeLocalCoreDomain.allCases.count))
        XCTAssertEqual(preview.confirmedWriteSummary, "0/11 confirmed writes")
        XCTAssertEqual(preview.confirmedWriteCoverage.map(\.status), Array(repeating: .blocked, count: NativeConfirmedWriteCapability.allCases.count))
        XCTAssertEqual(preview.confirmedWriteAuditSummary.status, .blocked)
        XCTAssertEqual(preview.confirmedWriteAuditSummary.readyCapabilityCount, 0)
        XCTAssertEqual(partiallyNative.status, .blocked)
        XCTAssertEqual(partiallyNative.migrationSummary, "5/11 Native domains · 1 partial")
        XCTAssertEqual(partiallyNative.domains.filter { $0.status == .ready }.map(\.domain), [.workspaceScanning, .documentInventory, .audit, .widgetSnapshot, .searchIndex])
        XCTAssertEqual(
            partiallyNative.domains.first { $0.domain == .documentInventory }?.evidence,
            [
                "native/Nexus/Sources/NexusApp/WorkspaceEvidenceDocuments.swift",
                "native/Nexus/Sources/NexusApp/NativeDocumentStore.swift"
            ]
        )
        XCTAssertTrue(
            fullyNative.domains.first { $0.domain == .workspaceScanning }?.evidence.contains(
                "native/Nexus/Sources/NexusApp/NativeWorkspaceCreationStore.swift"
            ) ?? false
        )
        XCTAssertEqual(
            fullyNative.domains.first { $0.domain == .demandIntake }?.evidence,
            [
                "native/Nexus/Sources/NexusApp/DemandScopeEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeDemandIntakeStore.swift",
                "native/Nexus/Sources/NexusApp/NativeScopeFreezeStore.swift",
                "native/Nexus/Sources/NexusApp/NativeDemandTaskTransferStore.swift"
            ]
        )
        XCTAssertTrue(
            fullyNative.domains.first { $0.domain == .readiness }?.evidence.contains(
                "native/Nexus/Sources/NexusApp/NativeAuditEventStore.swift"
            ) ?? false
        )
        XCTAssertEqual(
            fullyNative.domains.first { $0.domain == .confirmedWrites }?.evidence,
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
        )
        XCTAssertTrue(
            fullyNative.domains.first { $0.domain == .confirmedWrites }?.detail.contains(
                "确认写入"
            ) ?? false
        )
        XCTAssertTrue(
            fullyNative.domains.first { $0.domain == .confirmedWrites }?.evidence.contains(
                "native/Nexus/Sources/NexusApp/NativeWorkspaceTaskStore.swift"
            ) ?? false
        )
        XCTAssertTrue(
            fullyNative.domains.first { $0.domain == .confirmedWrites }?.evidence.contains(
                "native/Nexus/Sources/NexusApp/NativeWorkspaceLifecycleStore.swift"
            ) ?? false
        )
        XCTAssertEqual(fullyNative.confirmedWriteSummary, "11/11 confirmed writes")
        XCTAssertEqual(fullyNative.confirmedWriteAuditSummary.status, .ready)
        XCTAssertEqual(fullyNative.confirmedWriteAuditSummary.identitySummary, "11/11 audit identities")
        XCTAssertEqual(fullyNative.confirmedWriteAuditSummary.uniqueAuditActionCount, 10)
        XCTAssertEqual(fullyNative.confirmedWriteAuditSummary.uniqueAuditIdentityCount, 11)
        XCTAssertEqual(fullyNative.confirmedWriteAuditSummary.duplicateAuditActions, ["workspace_lifecycle.updated"])
        XCTAssertTrue(fullyNative.confirmedWriteAuditSummary.unqualifiedDuplicateAuditActions.isEmpty)
        XCTAssertTrue(fullyNative.confirmedWriteAuditSummary.detail.contains("metadata-qualified"))
        XCTAssertEqual(fullyNative.confirmedWriteCoverage.map(\.capability), NativeConfirmedWriteCapability.allCases)
        XCTAssertEqual(fullyNative.confirmedWriteCoverage.map(\.status), Array(repeating: .ready, count: NativeConfirmedWriteCapability.allCases.count))
        XCTAssertEqual(
            fullyNative.confirmedWriteCoverage.map(\.auditAction),
            [
                "demand_intake.initialized",
                "scope.freeze_confirmed",
                "demand_tasks.transferred",
                "workspace_task.updated",
                "worktree_setup.executed",
                "delivery_record.snapshot_appended",
                "validation_pr.snapshot_appended",
                "archive_checklist.snapshot_appended",
                "workspace_lifecycle.updated",
                "workspace_lifecycle.updated",
                "native_lifecycle_proof.exported"
            ]
        )
        XCTAssertTrue(
            fullyNative.confirmedWriteCoverage.first { $0.capability == .archiveLifecycle }?.confirmation.contains(
                "archived 状态"
            ) ?? false
        )
        XCTAssertEqual(
            fullyNative.confirmedWriteCoverage.first { $0.capability == .archiveLifecycle }?.auditMetadata,
            "state=archived"
        )
        XCTAssertTrue(
            fullyNative.confirmedWriteCoverage.first { $0.capability == .restoreLifecycle }?.confirmation.contains(
                "confirmation sheet"
            ) ?? false
        )
        XCTAssertEqual(
            fullyNative.confirmedWriteCoverage.first { $0.capability == .restoreLifecycle }?.auditLine,
            "workspace_lifecycle.updated · state=developing"
        )
        XCTAssertEqual(
            fullyNative.confirmedWriteCoverage.first { $0.capability == .restoreLifecycle }?.auditIdentity,
            "workspace_lifecycle.updated#state=developing"
        )
        XCTAssertTrue(
            fullyNative.confirmedWriteCoverage.first { $0.capability == .lifecycleProofExport }?.evidence.contains(
                "native/Nexus/Sources/NexusApp/NativeLifecycleProofBundle.swift"
            ) ?? false
        )
        XCTAssertEqual(
            partiallyNative.domains.filter { $0.status == .review }.map(\.domain),
            [.gitWorktreeStatus]
        )
        XCTAssertEqual(
            partiallyNative.domains.first { $0.domain == .gitWorktreeStatus }?.evidence,
            [
                "native/Nexus/Sources/NexusApp/ServiceWorktreeEvidence.swift",
                "native/Nexus/Sources/NexusApp/NativeSourceRepositoryStore.swift",
                "native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift",
                "native/Nexus/Sources/NexusApp/NativeWorktreeSetupStore.swift",
                "NexusBridge.scanWorkspaces / setupWorktrees"
            ]
        )
        XCTAssertEqual(
            partiallyNative.domains.first { $0.domain == .audit }?.evidence,
            [
                "native/Nexus/Sources/NexusApp/NativeAuditEventStore.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift"
            ]
        )
        XCTAssertEqual(
            partiallyNative.domains.first { $0.domain == .widgetSnapshot }?.evidence,
            [
                "native/Nexus/Sources/NexusApp/NativeWidgetSnapshotBuilder.swift",
                "native/Nexus/Sources/NexusApp/NativeWidgetSnapshotStore.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift"
            ]
        )
        XCTAssertEqual(
            partiallyNative.domains.first { $0.domain == .searchIndex }?.evidence,
            [
                "native/Nexus/Sources/NexusApp/NativeSearchIndexStore.swift",
                "native/Nexus/Sources/NexusApp/AppState.swift",
                "native/Nexus/Sources/NexusApp/Models.swift"
            ]
        )
        XCTAssertEqual(fullyNative.status, .ready)
        XCTAssertEqual(fullyNative.migrationSummary, "11/11 Native domains")
        XCTAssertFalse(fullyNative.bridgeIsLegacyDependency)
        XCTAssertTrue(fullyNative.reason.contains("M2 Native Local Core"))
    }

    func testNativeConfirmedWriteAuditSummaryBlocksUnqualifiedDuplicateActions() {
        let coverage = [
            NativeConfirmedWriteEvidence(
                capability: .archiveLifecycle,
                status: .ready,
                confirmation: "Confirmed archive write.",
                auditAction: "workspace_lifecycle.updated",
                auditMetadata: nil,
                evidence: ["archive"]
            ),
            NativeConfirmedWriteEvidence(
                capability: .restoreLifecycle,
                status: .ready,
                confirmation: "Confirmed restore write.",
                auditAction: "workspace_lifecycle.updated",
                auditMetadata: nil,
                evidence: ["restore"]
            )
        ]

        let summary = NativeConfirmedWriteAuditSummary.resolve(coverage: coverage)

        XCTAssertEqual(summary.status, .blocked)
        XCTAssertEqual(summary.uniqueAuditActionCount, 1)
        XCTAssertEqual(summary.uniqueAuditIdentityCount, 1)
        XCTAssertEqual(summary.duplicateAuditActions, ["workspace_lifecycle.updated"])
        XCTAssertEqual(summary.unqualifiedDuplicateAuditActions, ["workspace_lifecycle.updated"])
        XCTAssertTrue(summary.detail.contains("Audit identity collision"))
    }

    func testNativeLocalCoreEvidenceReviewsPartialDomainsWithoutBlockers() {
        let evidence = NativeLocalCoreEvidence.resolve(
            bridgeMode: "Swift Native local core",
            nativeDomains: Set(NativeLocalCoreDomain.allCases).subtracting([.workspaceScanning, .gitWorktreeStatus]),
            partialNativeDomains: [.workspaceScanning, .gitWorktreeStatus]
        )

        XCTAssertEqual(evidence.status, .review)
        XCTAssertEqual(evidence.migrationSummary, "9/11 Native domains · 2 partial")
        XCTAssertTrue(evidence.reason.contains("已无 blocked 域"))
        XCTAssertEqual(evidence.domains.filter { $0.status == .review }.map(\.domain), [.workspaceScanning, .gitWorktreeStatus])
    }

    func testNativeWorkspaceCreationStoreWritesStandardWorkspaceAndAudit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-create-workspace-\(UUID().uuidString)")
        let auditRoot = root.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let response = try NativeWorkspaceCreationStore.create(
            request: CreateWorkspaceRequest(
                name: "Demo Feature",
                folder: "2026-06-29-demo-feature",
                workspacesRoot: root.path,
                sourceReposRoot: "~/source-repos",
                services: [" order ", "", "store-cashier"],
                targetBranch: "chen/demo-feature",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        )
        let workspaceURL = URL(fileURLWithPath: response.path)
        let servicesContent = try String(contentsOf: workspaceURL.appendingPathComponent("services.md"), encoding: .utf8)
        let deliveryContent = try String(contentsOf: workspaceURL.appendingPathComponent("交付记录.md"), encoding: .utf8)
        let agentsContent = try String(contentsOf: workspaceURL.appendingPathComponent("AGENTS.md"), encoding: .utf8)
        let indexContent = try String(contentsOf: root.appendingPathComponent("INDEX.md"), encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertEqual(response.folder, "2026-06-29-demo-feature")
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("repos").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspaceURL.appendingPathComponent("scripts/worktree-commands.sh").path))
        XCTAssertTrue(response.generatedFiles?.contains { $0.relativePath == "STATUS.md" && $0.exists } ?? false)
        XCTAssertTrue(response.initializationChecks?.contains { $0.id == "status-initial-state" && $0.status == "pass" } ?? false)
        XCTAssertTrue(response.initializationChecks?.contains { $0.id == "service-scope" && $0.status == "pass" } ?? false)
        XCTAssertTrue(servicesContent.contains("| order | `~/source-repos/order` | 初始确认 |"))
        XCTAssertTrue(servicesContent.contains("| store-cashier | `~/source-repos/store-cashier` | 初始确认 |"))
        XCTAssertTrue(deliveryContent.contains("- 分支: chen/demo-feature"))
        XCTAssertTrue(deliveryContent.contains("正式 SQL 与回滚 SQL 文件"))
        XCTAssertTrue(agentsContent.contains("交付收尾前必须复核 `acceptance.md`、`交付记录.md` 和 `sql/`"))
        XCTAssertTrue(indexContent.contains("| Demo Feature | analyzing | chen/demo-feature | order, store-cashier | `2026-06-29-demo-feature` |"))
        XCTAssertEqual(response.auditEventID, events.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(events.first?.action, "workspace.created")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["services"], "order,store-cashier")

        let invalidAuditRoot = root.appendingPathComponent("invalid-audit")
        try "not a directory".write(to: invalidAuditRoot, atomically: true, encoding: .utf8)
        let auditFailure = try NativeWorkspaceCreationStore.create(
            request: CreateWorkspaceRequest(
                name: "Audit Failure Demo",
                folder: "2026-06-29-audit-failure-demo",
                workspacesRoot: root.path,
                sourceReposRoot: "~/source-repos",
                services: [],
                targetBranch: "待确认",
                confirmed: true,
                auditRoot: invalidAuditRoot.path,
                actor: "Nexus Test"
            )
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: auditFailure.path))
        XCTAssertNotNil(auditFailure.auditError)
    }

    func testNativeWorkspaceCreationStoreRequiresConfirmationAndSafeFolder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-create-workspace-reject-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        XCTAssertThrowsError(
            try NativeWorkspaceCreationStore.create(
                request: CreateWorkspaceRequest(
                    name: "Unsafe",
                    folder: "2026-06-29-unsafe",
                    workspacesRoot: root.path,
                    sourceReposRoot: "~/source-repos",
                    services: [],
                    targetBranch: "",
                    confirmed: false
                )
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("explicit confirmation"))
        }
        XCTAssertThrowsError(
            try NativeWorkspaceCreationStore.create(
                request: CreateWorkspaceRequest(
                    name: "Unsafe",
                    folder: "../unsafe",
                    workspacesRoot: root.path,
                    sourceReposRoot: "~/source-repos",
                    services: [],
                    targetBranch: "",
                    confirmed: true
                )
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("safe single directory"))
        }
    }

    @MainActor
    func testWorkspaceCreationResponseRecordsScanVisibilityAfterRefresh() {
        let response = CreateWorkspaceResponse(
            path: "/tmp/workspaces/created-visible",
            folder: "created-visible",
            generatedFiles: [],
            initializationChecks: [
                WorkspaceInitializationCheck(
                    id: "standard-files",
                    label: "标准文件 / Standard files",
                    detail: "ok",
                    status: "pass"
                )
            ],
            auditEventID: "audit-create-1",
            auditEventPath: "/tmp/audit/events.jsonl"
        )
        let visibleWorkspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "created-visible",
            folder: "created-visible",
            path: "/tmp/workspaces/created-visible"
        )

        let visibleResponse = AppState.workspaceCreationResponse(response, verifiedAgainst: [visibleWorkspace])
        let visibleCheck = visibleResponse.initializationChecks?.first { $0.id == "workspace-scan-visible" }
        XCTAssertEqual(visibleCheck?.status, "pass")
        XCTAssertTrue(visibleCheck?.detail.contains("已扫描到新工作区") == true)
        XCTAssertEqual(visibleResponse.scanVisibilityCheck?.id, "workspace-scan-visible")
        XCTAssertEqual(visibleResponse.auditEventID, "audit-create-1")
        XCTAssertEqual(visibleResponse.auditEventPath, "/tmp/audit/events.jsonl")
        XCTAssertEqual(visibleResponse.isVisibleAfterRefresh, true)
        XCTAssertFalse(visibleResponse.needsVisibilityRecovery)
        XCTAssertTrue(visibleResponse.visibilityRecoveryTitle.contains("已出现在扫描结果"))
        XCTAssertEqual(visibleResponse.visibilityFeedback.status, .ready)
        XCTAssertEqual(visibleResponse.visibilityFeedback.actionLabel, "继续下一步")
        XCTAssertEqual(visibleResponse.visibilityFeedback.systemImage, "checkmark.seal")

        let missingResponse = AppState.workspaceCreationResponse(response, verifiedAgainst: [])
        let missingCheck = missingResponse.initializationChecks?.first { $0.id == "workspace-scan-visible" }
        XCTAssertEqual(missingCheck?.status, "warning")
        XCTAssertTrue(missingCheck?.detail.contains("创建记录已写入") == true)
        XCTAssertEqual(missingResponse.initializationChecks?.filter { $0.id == "workspace-scan-visible" }.count, 1)
        XCTAssertEqual(missingResponse.isVisibleAfterRefresh, false)
        XCTAssertTrue(missingResponse.needsVisibilityRecovery)
        XCTAssertTrue(missingResponse.visibilityRecoveryTitle.contains("扫描未命中新工作区"))
        XCTAssertTrue(missingResponse.visibilityRecoveryDetail.contains("目录扫描未返回"))
        XCTAssertEqual(missingResponse.visibilityFeedback.status, .review)
        XCTAssertEqual(missingResponse.visibilityFeedback.actionLabel, "重新扫描")
        XCTAssertEqual(missingResponse.visibilityFeedback.systemImage, "exclamationmark.triangle")
    }

    func testNativeWorkspaceTaskStoreRequiresConfirmationAndRewritesStatus() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-task-status-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("2026-05-28-task-status")
        let auditRoot = root.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let tasksURL = workspaceURL.appendingPathComponent("tasks.md")
        let originalTasks = """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | 核对任务中心 | 进行中 | priority=high |
        | Review permission request | 待办 | priority=medium event=agent-1 |
        """ + "\n"
        try originalTasks.write(to: tasksURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try NativeWorkspaceTaskStore.update(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: workspaceURL.path,
                    taskId: "2026-05-28-task-status:task-0",
                    status: "已完成",
                    confirmed: false
                ),
                expectedTitle: "核对任务中心",
                expectedStatus: "进行中",
                expectedDetail: "priority=high",
                expectedPriority: "high",
                expectedSourceLine: 5
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("explicit confirmation"))
        }

        let completed = try NativeWorkspaceTaskStore.update(
            request: UpdateWorkspaceTaskRequest(
                workspacePath: workspaceURL.path,
                taskId: "2026-05-28-task-status:task-0",
                status: "已完成",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedTitle: "核对任务中心",
            expectedStatus: "进行中",
            expectedDetail: "priority=high",
            expectedPriority: "high",
            expectedSourceLine: 5
        )
        let deferred = try NativeWorkspaceTaskStore.update(
            request: UpdateWorkspaceTaskRequest(
                workspacePath: workspaceURL.path,
                taskId: "2026-05-28-task-status:agent-1",
                status: "延期",
                detail: "priority=medium event=agent-1 deferred=2026-05-28",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedTitle: "Review permission request",
            expectedStatus: "待办",
            expectedDetail: "priority=medium event=agent-1",
            expectedPriority: "medium",
            expectedSourceLine: 6
        )
        let content = try String(contentsOf: tasksURL, encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertEqual(completed.path, tasksURL.path)
        XCTAssertEqual(completed.previousStatus, "进行中")
        XCTAssertEqual(completed.task.title, "核对任务中心")
        XCTAssertEqual(completed.task.status, "已完成")
        XCTAssertEqual(completed.task.priority, "high")
        XCTAssertEqual(deferred.previousStatus, "待办")
        XCTAssertEqual(deferred.task.id, "2026-05-28-task-status:agent-1")
        XCTAssertEqual(deferred.task.source, "agent")
        XCTAssertEqual(deferred.task.sourceEventId, "agent-1")
        XCTAssertTrue(content.contains("| 核对任务中心 | 已完成 | priority=high |"))
        XCTAssertTrue(content.contains("| Review permission request | 延期 | priority=medium event=agent-1 deferred=2026-05-28 |"))
        XCTAssertTrue(content.hasSuffix("\n"))
        XCTAssertEqual(deferred.auditEventID, events.first?.id)
        XCTAssertEqual(deferred.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(completed.auditEventID, events.dropFirst().first?.id)
        XCTAssertEqual(completed.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(events.first?.action, "workspace_task.updated")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["taskId"], "2026-05-28-task-status:agent-1")
        XCTAssertEqual(events.first?.metadata["status"], "延期")
    }

    func testNativeWorkspaceTaskStoreReportsAuditFailureAfterSuccessfulWrite() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-task-audit-failure-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("2026-07-10-task-audit-failure")
        let auditRoot = root.appendingPathComponent("audit")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let tasksURL = workspaceURL.appendingPathComponent("tasks.md")
        try """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | 核对审计反馈 | 进行中 | priority=high |
        """.appending("\n").write(to: tasksURL, atomically: true, encoding: .utf8)
        try "not a directory".write(to: auditRoot, atomically: true, encoding: .utf8)

        let response = try NativeWorkspaceTaskStore.update(
            request: UpdateWorkspaceTaskRequest(
                workspacePath: workspaceURL.path,
                taskId: "2026-07-10-task-audit-failure:task-0",
                status: "已完成",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedTitle: "核对审计反馈",
            expectedStatus: "进行中",
            expectedDetail: "priority=high",
            expectedPriority: "high",
            expectedSourceLine: 5
        )

        let content = try String(contentsOf: tasksURL, encoding: .utf8)
        XCTAssertTrue(content.contains("| 核对审计反馈 | 已完成 | priority=high |"))
        XCTAssertNil(response.auditEventID)
        XCTAssertNil(response.auditEventPath)
        XCTAssertNotNil(response.auditError)
    }

    func testNativeConfirmedDocumentWritesReportAuditFailureAfterSuccessfulMutation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-document-audit-failure-\(UUID().uuidString)")
        let demandDir = root.appendingPathComponent("需求")
        let auditRoot = root.appendingPathComponent("audit")
        defer { try? FileManager.default.removeItem(at: root) }

        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
        try writeDemandIntakeFixture(
            demandDir: demandDir,
            scope: """
            # 本次开发范围

            ## 已确认并实现

            - 保存订单时记录交易快照。

            ## 暂不实现

            - 不补历史数据。

            ## 仍待确认

            - 无 P0 待确认项。

            ## 进入开发条件

            - [ ] 本文件已冻结本次开发范围。
            """
        )
        try """
        # 需求列表

        | 需求点 | 状态 | 优先级 | 来源 | 说明 |
        | --- | --- | --- | --- | --- |
        | 新增交易快照写入 | 待办 | P0 | 蓝湖 | 保存订单时记录快照 |
        """.appending("\n").write(
            to: demandDir.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        let tasksURL = root.appendingPathComponent("tasks.md")
        try """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        """.appending("\n").write(to: tasksURL, atomically: true, encoding: .utf8)
        let deliveryURL = root.appendingPathComponent("交付记录.md")
        try "# 交付记录\n".write(to: deliveryURL, atomically: true, encoding: .utf8)
        try "not a directory".write(to: auditRoot, atomically: true, encoding: .utf8)

        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "document-audit-failure",
            name: "Document Audit Failure",
            path: root.path,
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "delivery-record",
                    label: "交付记录",
                    detail: "交付记录可用",
                    status: "pass",
                    action: "delivery"
                ),
                WorkspaceHealthCheck(
                    id: "sql-directory",
                    label: "SQL",
                    detail: "未声明 SQL 变更。",
                    status: "pass",
                    action: "sql"
                )
            ]
        )
        let intakeStatus = demandIntakeStatus(at: demandDir)
        let scopePlan = ScopeFreezeWritePlan.resolve(
            workspace: workspace,
            evidence: ScopeFreezeEvidence.resolve(status: intakeStatus, workspace: workspace)
        )
        let transferPlan = DemandTaskTransferPlan.resolve(workspace: workspace, status: intakeStatus)
        let deliveryPlan = DeliveryRecordWritePlan.resolve(
            workspace: workspace,
            gate: DeliveryGateEvidence.resolve(workspace: workspace)
        )

        let scope = try NativeScopeFreezeStore.write(
            plan: scopePlan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        let transfer = try NativeDemandTaskTransferStore.transfer(
            plan: transferPlan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        let delivery = try NativeDeliveryRecordStore.appendDeliverySnapshot(
            plan: deliveryPlan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )

        XCTAssertNotNil(scope.auditError)
        XCTAssertNotNil(transfer.auditError)
        XCTAssertNotNil(delivery.auditError)
        XCTAssertTrue(try String(contentsOf: demandDir.appendingPathComponent("scope.md"), encoding: .utf8)
            .contains("## 范围冻结确认 / Scope Freeze Confirmation"))
        XCTAssertTrue(try String(contentsOf: tasksURL, encoding: .utf8)
            .contains("新增交易快照写入"))
        XCTAssertTrue(try String(contentsOf: deliveryURL, encoding: .utf8)
            .contains("Delivery Gate"))
    }

    func testNativeWorkspaceTaskStoreRejectsStaleStatusAndShiftedTaskID() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-task-stale-\(UUID().uuidString)")
        let staleURL = root.appendingPathComponent("stale")
        let shiftedURL = root.appendingPathComponent("shifted")
        let fingerprintShiftedURL = root.appendingPathComponent("fingerprint-shifted")
        let duplicateFingerprintURL = root.appendingPathComponent("duplicate-fingerprint")
        let changedEvidenceURL = root.appendingPathComponent("changed-evidence")
        let auditRoot = root.appendingPathComponent("audit")
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in [staleURL, shiftedURL, fingerprintShiftedURL, duplicateFingerprintURL, changedEvidenceURL] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let staleContent = "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| Original | 阻塞 | externally changed |\n"
        try staleContent.write(
            to: staleURL.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try NativeWorkspaceTaskStore.update(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: staleURL.path,
                    taskId: "stale:task-0",
                    status: "已完成",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedTitle: "Original",
                expectedStatus: "进行中",
                expectedDetail: "previous detail",
                expectedPriority: "normal",
                expectedSourceLine: 5
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
            XCTAssertTrue(error.localizedDescription.contains("Original"))
            XCTAssertTrue(error.localizedDescription.contains("进行中"))
            XCTAssertTrue(error.localizedDescription.contains("阻塞"))
        }
        XCTAssertEqual(
            try String(contentsOf: staleURL.appendingPathComponent("tasks.md"), encoding: .utf8),
            staleContent
        )

        let shiftedContent = """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | Inserted | 进行中 | new first row |
        | Original | 进行中 | expected task moved |
        """ + "\n"
        try shiftedContent.write(
            to: shiftedURL.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try NativeWorkspaceTaskStore.update(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: shiftedURL.path,
                    taskId: "shifted:task-0",
                    status: "已完成",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedTitle: "Original",
                expectedStatus: "进行中",
                expectedDetail: "expected task moved",
                expectedPriority: "normal",
                expectedSourceLine: 5
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("Original"))
            XCTAssertTrue(error.localizedDescription.contains("Inserted"))
        }
        XCTAssertEqual(
            try String(contentsOf: shiftedURL.appendingPathComponent("tasks.md"), encoding: .utf8),
            shiftedContent
        )

        let fingerprintShiftedContent = """
        # Tasks

        | 任务 | 状态 | 说明 | 优先级 |
        | --- | --- | --- | --- |
        | Original | 进行中 | inserted detail | low |
        | Original | 进行中 | confirmed detail | high |
        """ + "\n"
        try fingerprintShiftedContent.write(
            to: fingerprintShiftedURL.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try NativeWorkspaceTaskStore.update(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: fingerprintShiftedURL.path,
                    taskId: "fingerprint-shifted:task-0",
                    status: "已完成",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedTitle: "Original",
                expectedStatus: "进行中",
                expectedDetail: "confirmed detail",
                expectedPriority: "high",
                expectedSourceLine: 5
            )
        )
        XCTAssertEqual(
            try String(contentsOf: fingerprintShiftedURL.appendingPathComponent("tasks.md"), encoding: .utf8),
            fingerprintShiftedContent
        )

        let duplicateFingerprintContent = """
        # Tasks

        | 任务 | 状态 | 说明 | 优先级 |
        | --- | --- | --- | --- |
        | Original | 进行中 | confirmed detail | high |
        | Original | 进行中 | confirmed detail | high |
        """ + "\n"
        try duplicateFingerprintContent.write(
            to: duplicateFingerprintURL.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try NativeWorkspaceTaskStore.update(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: duplicateFingerprintURL.path,
                    taskId: "duplicate-fingerprint:task-0",
                    status: "已完成",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedTitle: "Original",
                expectedStatus: "进行中",
                expectedDetail: "confirmed detail",
                expectedPriority: "high",
                expectedSourceLine: 5
            )
        )
        XCTAssertEqual(
            try String(contentsOf: duplicateFingerprintURL.appendingPathComponent("tasks.md"), encoding: .utf8),
            duplicateFingerprintContent
        )

        let changedEvidenceContent = """
        # Tasks

        | 任务 | 状态 | 说明 | 优先级 |
        | --- | --- | --- | --- |
        | Original | 进行中 | changed detail | low |
        """ + "\n"
        try changedEvidenceContent.write(
            to: changedEvidenceURL.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try NativeWorkspaceTaskStore.update(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: changedEvidenceURL.path,
                    taskId: "changed-evidence:task-0",
                    status: "已完成",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedTitle: "Original",
                expectedStatus: "进行中",
                expectedDetail: "confirmed detail",
                expectedPriority: "high",
                expectedSourceLine: 5
            )
        )
        XCTAssertEqual(
            try String(contentsOf: changedEvidenceURL.appendingPathComponent("tasks.md"), encoding: .utf8),
            changedEvidenceContent
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeWorkspaceTaskStoreAllowsNonTaskLineDriftWhenTaskEvidenceUnchanged() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-task-line-drift-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let tasksURL = workspaceURL.appendingPathComponent("tasks.md")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let currentContent = """
        # Tasks

        This note was added after confirmation.

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | Original | 进行中 | keep |
        | Next | 待办 | remain active |
        """ + "\n"
        try currentContent.write(to: tasksURL, atomically: true, encoding: .utf8)

        let response = try NativeWorkspaceTaskStore.update(
            request: UpdateWorkspaceTaskRequest(
                workspacePath: workspaceURL.path,
                taskId: "workspace:task-0",
                status: "已完成",
                confirmed: true
            ),
            expectedTitle: "Original",
            expectedStatus: "进行中",
            expectedDetail: "keep",
            expectedPriority: "medium",
            expectedSourceLine: 5
        )
        let updated = try String(contentsOf: tasksURL, encoding: .utf8)

        XCTAssertEqual(response.task.id, "workspace:task-0")
        XCTAssertEqual(response.task.sourceLine, 7)
        XCTAssertTrue(updated.contains("This note was added after confirmation."))
        XCTAssertTrue(updated.contains("| Original | 已完成 | keep |"))
        XCTAssertTrue(updated.contains("| Next | 待办 | remain active |"))
    }

    func testNativeWorkspaceScannerTaskStoreRoundTripPreservesAgentEvidenceAndPriority() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-agent-round-trip-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try "# Workspace\n\n- 当前状态: developing\n".write(
            to: workspaceURL.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # Tasks

        | 任务 | 状态 | 说明 | 优先级 |
        | --- | --- | --- | --- |
        | Agent work | 进行中 | event=agent-42 | high |
        """.write(
            to: workspaceURL.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )

        let scanned = try scannedWorkspace(
            folder: "workspace",
            workspacesRoot: root,
            sourceRoot: root.appendingPathComponent("source-repos")
        )
        let task = try XCTUnwrap(scanned.tasks.first)
        _ = try NativeWorkspaceTaskStore.update(
            request: UpdateWorkspaceTaskRequest(
                workspacePath: workspaceURL.path,
                taskId: task.id,
                status: "已完成",
                confirmed: true
            ),
            expectedTitle: task.title,
            expectedStatus: task.status,
            expectedDetail: task.detail,
            expectedPriority: task.priority,
            expectedSourceLine: task.sourceLine
        )

        let rescanned = try scannedWorkspace(
            folder: "workspace",
            workspacesRoot: root,
            sourceRoot: root.appendingPathComponent("source-repos")
        )
        let updated = try XCTUnwrap(rescanned.tasks.first)

        XCTAssertEqual(updated.id, "workspace:agent-42")
        XCTAssertEqual(updated.title, "Agent work")
        XCTAssertEqual(updated.status, "已完成")
        XCTAssertEqual(updated.source, "agent")
        XCTAssertEqual(updated.sourceEventID, "agent-42")
        XCTAssertEqual(updated.sourceLine, task.sourceLine)
        XCTAssertEqual(updated.priority, "high")
    }

    @MainActor
    func testAppStateTaskStatusConfirmationKeepsStalePendingThenRefreshesSuccessfulWrite() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-app-state-task-confirmation-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let workspaceURL = workspacesRoot.appendingPathComponent("workspace")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let docsRoot = root.appendingPathComponent("docs")
        let applicationSupportRoot = root.appendingPathComponent("app-support")
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        for directory in [workspaceURL, sourceRoot, docsRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "# Workspace\n\n- 当前状态: developing\n".write(
            to: workspaceURL.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        let originalTasks = """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | Original | 进行中 | update me |
        | Next | 待办 | remain active |
        """ + "\n"
        let tasksURL = workspaceURL.appendingPathComponent("tasks.md")
        try originalTasks.write(to: tasksURL, atomically: true, encoding: .utf8)
        let initialWorkspace = try scannedWorkspace(
            folder: "workspace",
            workspacesRoot: workspacesRoot,
            sourceRoot: sourceRoot
        )
        let appState = AppState(
            workspaces: [initialWorkspace],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path,
            applicationSupportRoot: applicationSupportRoot.path,
            defaults: defaults
        )
        let auditRoot = applicationSupportRoot.appendingPathComponent("audit")
        let auditCountBefore = (try? NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 200).count) ?? 0
        let item = try XCTUnwrap(appState.taskCenterItems.first { $0.task.id == "workspace:task-0" })

        appState.requestTaskStatusUpdate(item, status: "已完成")
        let staleTasks = originalTasks.replacingOccurrences(of: "| Original | 进行中 |", with: "| Changed | 阻塞 |")
        try staleTasks.write(to: tasksURL, atomically: true, encoding: .utf8)
        await appState.confirmPendingTaskStatusUpdate(confirmed: true)

        XCTAssertNotNil(appState.pendingTaskStatusUpdate)
        XCTAssertTrue(appState.lastError?.contains("changed since confirmation") == true)
        XCTAssertFalse(appState.isUpdatingTask)
        XCTAssertEqual(try String(contentsOf: tasksURL, encoding: .utf8), staleTasks)
        XCTAssertEqual(
            (try? NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 200).count) ?? 0,
            auditCountBefore
        )

        try originalTasks.write(to: tasksURL, atomically: true, encoding: .utf8)
        await appState.confirmPendingTaskStatusUpdate(confirmed: true)
        await appState.refreshFromBridge()

        XCTAssertNil(appState.pendingTaskStatusUpdate)
        XCTAssertNil(appState.lastError)
        XCTAssertFalse(appState.isUpdatingTask)
        XCTAssertEqual(appState.workspaces.first?.tasks.first?.status, "已完成")
        XCTAssertNotNil(appState.localWriteFeedback)
        XCTAssertEqual(appState.focusedTaskCenterItemID, "workspace:workspace:task-1:L6")
        XCTAssertNotNil(appState.widgetSnapshot)
        XCTAssertTrue(appState.widgetSnapshotStoragePaths.contains { $0.hasPrefix(applicationSupportRoot.path) })
        XCTAssertEqual(
            try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 10)
                .filter { $0.action == "workspace_task.updated" }
                .count,
            1
        )
    }

    @MainActor
    func testAppStateDeliveryRecordConfirmationKeepsStalePendingEvidence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-app-state-delivery-confirmation-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let workspaceURL = workspacesRoot.appendingPathComponent("workspace")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let docsRoot = root.appendingPathComponent("docs")
        let applicationSupportRoot = root.appendingPathComponent("app-support")
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        for directory in [workspaceURL, sourceRoot, docsRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "# Workspace\n\n- 需求名称: Delivery Conflict\n- 当前状态: developing\n- 目标分支: feature/delivery-conflict\n".write(
            to: workspaceURL.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# STATUS\n\n- 当前状态: developing\n- 当前焦点: Delivery conflict test\n".write(
            to: workspaceURL.appendingPathComponent("STATUS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| Delivery proof | 已完成 | ready |\n".write(
            to: workspaceURL.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        let deliveryURL = workspaceURL.appendingPathComponent("交付记录.md")
        let original = "# 交付记录\n\n## 人工记录\n\n原始内容。\n"
        try original.write(to: deliveryURL, atomically: true, encoding: .utf8)

        let workspace = try scannedWorkspace(
            folder: "workspace",
            workspacesRoot: workspacesRoot,
            sourceRoot: sourceRoot
        )
        let appState = AppState(
            workspaces: [workspace],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path,
            applicationSupportRoot: applicationSupportRoot.path,
            defaults: defaults
        )

        appState.requestDeliveryRecordWrite(in: workspace)
        let pending = try XCTUnwrap(appState.pendingDeliveryRecordWrite)
        XCTAssertTrue(pending.canWrite)
        let externallyEdited = original + "\n## 外部修改\n\n确认后写入。\n"
        try externallyEdited.write(to: deliveryURL, atomically: true, encoding: .utf8)

        await appState.confirmPendingDeliveryRecordWrite(confirmed: true)

        XCTAssertEqual(appState.pendingDeliveryRecordWrite, pending)
        XCTAssertTrue(appState.lastError?.contains("changed since confirmation") == true)
        XCTAssertFalse(appState.isUpdatingDeliveryRecord)
        XCTAssertEqual(try String(contentsOf: deliveryURL, encoding: .utf8), externallyEdited)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: applicationSupportRoot
                .appendingPathComponent("audit/\(NativeAuditEventStore.fileName)").path
        ))
    }

    @MainActor
    func testAppStateScopeFreezeConfirmationKeepsStalePendingEvidence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-app-state-scope-freeze-confirmation-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let workspaceURL = workspacesRoot.appendingPathComponent("workspace")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let docsRoot = root.appendingPathComponent("docs")
        let applicationSupportRoot = root.appendingPathComponent("app-support")
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        for directory in [workspaceURL, sourceRoot, docsRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "# Workspace\n\n- 需求名称: Scope freeze conflict\n- 当前状态: scoping\n".write(
            to: workspaceURL.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# STATUS\n\n- 当前状态: scoping\n- 当前焦点: Confirm scope freeze\n".write(
            to: workspaceURL.appendingPathComponent("STATUS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| Freeze scope | 待办 | waiting for confirmation |\n".write(
            to: workspaceURL.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        let demandURL = workspaceURL.appendingPathComponent("需求")
        try FileManager.default.createDirectory(at: demandURL, withIntermediateDirectories: true)
        try "# 需求确认卡\n\n- 真实需求目标：验证范围冻结冲突反馈。\n".write(
            to: demandURL.appendingPathComponent("requirement.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 待确认问题\n\n## P0 阻塞开发\n\n- [x] 无 P0 待确认项。\n".write(
            to: demandURL.appendingPathComponent("questions.md"),
            atomically: true,
            encoding: .utf8
        )
        let scopeURL = demandURL.appendingPathComponent("scope.md")
        let original = """
        # 本次开发范围

        ## 已确认并实现

        - 验证范围冻结的外部编辑保护。

        ## 暂不实现

        - 不覆盖确认后的人工修改。

        ## 仍待确认

        - 无 P0 待确认项。

        ## 进入开发条件

        - [ ] 本文件已冻结本次开发范围。
        """ + "\n"
        try original.write(to: scopeURL, atomically: true, encoding: .utf8)
        try "# 需求列表\n\n| 需求点 | 状态 | 优先级 | 来源 | 说明 |\n| --- | --- | --- | --- | --- |\n| 范围冻结保护 | 待办 | P0 | 测试 | 验证冲突反馈 |\n".write(
            to: demandURL.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 需求交付\n\n- 验证范围冻结确认后的外部修改保护。\n".write(
            to: demandURL.appendingPathComponent("delivery.md"),
            atomically: true,
            encoding: .utf8
        )

        let workspace = try scannedWorkspace(
            folder: "workspace",
            workspacesRoot: workspacesRoot,
            sourceRoot: sourceRoot
        )
        let appState = AppState(
            workspaces: [workspace],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path,
            applicationSupportRoot: applicationSupportRoot.path,
            defaults: defaults
        )

        appState.requestScopeFreezeWrite(in: workspace)
        let pending = try XCTUnwrap(appState.pendingScopeFreezeWrite)
        XCTAssertTrue(pending.canWrite)
        let externallyEdited = original + "\n- 外部人工备注：不要覆盖。\n"
        try externallyEdited.write(to: scopeURL, atomically: true, encoding: .utf8)

        await appState.confirmPendingScopeFreezeWrite(confirmed: true)

        XCTAssertEqual(appState.pendingScopeFreezeWrite, pending)
        XCTAssertTrue(appState.lastError?.contains("changed since confirmation") == true)
        XCTAssertFalse(appState.isInitializingDemandIntake)
        XCTAssertNil(appState.localWriteFeedback)
        XCTAssertEqual(try String(contentsOf: scopeURL, encoding: .utf8), externallyEdited)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: applicationSupportRoot
                .appendingPathComponent("audit/\(NativeAuditEventStore.fileName)").path
        ))
    }

    @MainActor
    func testAppStateDemandTaskTransferConfirmationKeepsStalePendingEvidence() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-app-state-demand-transfer-confirmation-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let workspaceURL = workspacesRoot.appendingPathComponent("workspace")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let docsRoot = root.appendingPathComponent("docs")
        let applicationSupportRoot = root.appendingPathComponent("app-support")
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        for directory in [workspaceURL, sourceRoot, docsRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "# Workspace\n\n- 需求名称: Demand transfer conflict\n- 当前状态: developing\n".write(
            to: workspaceURL.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# STATUS\n\n- 当前状态: developing\n- 当前焦点: Confirm demand task transfer\n".write(
            to: workspaceURL.appendingPathComponent("STATUS.md"),
            atomically: true,
            encoding: .utf8
        )
        let executionURL = workspaceURL.appendingPathComponent("tasks.md")
        let originalExecution = """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | Existing root task | 待办 | keep this task |
        """ + "\n"
        try originalExecution.write(to: executionURL, atomically: true, encoding: .utf8)
        let demandURL = workspaceURL.appendingPathComponent("需求")
        try FileManager.default.createDirectory(at: demandURL, withIntermediateDirectories: true)
        try writeDemandIntakeFixture(
            demandDir: demandURL,
            scope: """
            # 本次开发范围

            ## 已确认并实现

            - 验证需求任务转入确认后的冲突反馈。

            ## 暂不实现

            - 不覆盖确认后的 root tasks.md 外部编辑。

            ## 仍待确认

            - 无 P0 待确认项。

            ## 进入开发条件

            - [x] 本文件已冻结本次开发范围。
            """ + "\n"
        )
        let intakeURL = demandURL.appendingPathComponent("tasks.md")
        let originalIntake = try String(contentsOf: intakeURL, encoding: .utf8)

        let workspace = try scannedWorkspace(
            folder: "workspace",
            workspacesRoot: workspacesRoot,
            sourceRoot: sourceRoot
        )
        let appState = AppState(
            workspaces: [workspace],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path,
            applicationSupportRoot: applicationSupportRoot.path,
            defaults: defaults
        )

        appState.requestDemandTaskTransfer(in: workspace)
        let pending = try XCTUnwrap(appState.pendingDemandTaskTransfer)
        XCTAssertTrue(pending.hasTransferableItems)
        let externallyEdited = originalExecution + "\n| External root task | 进行中 | added after confirmation |\n"
        try externallyEdited.write(to: executionURL, atomically: true, encoding: .utf8)

        await appState.confirmPendingDemandTaskTransfer(confirmed: true)

        XCTAssertEqual(appState.pendingDemandTaskTransfer, pending)
        XCTAssertTrue(appState.lastError?.contains("changed since confirmation") == true)
        XCTAssertFalse(appState.isUpdatingTask)
        XCTAssertEqual(try String(contentsOf: executionURL, encoding: .utf8), externallyEdited)
        XCTAssertEqual(try String(contentsOf: intakeURL, encoding: .utf8), originalIntake)
        XCTAssertNil(appState.localWriteFeedback)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: applicationSupportRoot
                .appendingPathComponent("audit/\(NativeAuditEventStore.fileName)").path
        ))
    }

    func testNativeWorkspaceTaskStoreRejectsSymlinkBeforeWriting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-task-symlink-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let tasksURL = workspaceURL.appendingPathComponent("tasks.md")
        let targetURL = root.appendingPathComponent("external-tasks.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let original = "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| External | 进行中 | keep |\n"
        try original.write(to: targetURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: tasksURL, withDestinationURL: targetURL)

        XCTAssertThrowsError(
            try NativeWorkspaceTaskStore.update(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: workspaceURL.path,
                    taskId: "workspace:task-0",
                    status: "已完成",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedTitle: "External",
                expectedStatus: "进行中",
                expectedDetail: "keep",
                expectedPriority: "normal",
                expectedSourceLine: 5
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("tasks.md is not a file"))
        }
        XCTAssertEqual(try String(contentsOf: targetURL, encoding: .utf8), original)
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: tasksURL.path), targetURL.path)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeWorkspaceTaskStoreRejectsDuplicateAgentTaskID() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-task-duplicate-id-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let tasksURL = workspaceURL.appendingPathComponent("tasks.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let original = """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | First | 进行中 | event=agent-1 |
        | Second | 待办 | event=agent-1 |
        """ + "\n"
        try original.write(to: tasksURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try NativeWorkspaceTaskStore.update(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: workspaceURL.path,
                    taskId: "workspace:agent-1",
                    status: "已完成",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedTitle: "First",
                expectedStatus: "进行中",
                expectedDetail: "event=agent-1",
                expectedPriority: "normal",
                expectedSourceLine: 5
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("matches 2 rows"))
        }
        XCTAssertEqual(try String(contentsOf: tasksURL, encoding: .utf8), original)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeWorkspaceTaskStoreRejectsInvalidUTF8BeforeWriting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-task-invalid-utf8-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let tasksURL = workspaceURL.appendingPathComponent("tasks.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let original = Data([0x23, 0x20, 0x54, 0x61, 0x73, 0x6B, 0x73, 0x0A, 0xC3, 0x28, 0x0A])
        try original.write(to: tasksURL)

        XCTAssertThrowsError(
            try NativeWorkspaceTaskStore.update(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: workspaceURL.path,
                    taskId: "workspace:task-0",
                    status: "已完成",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedTitle: "Unknown",
                expectedStatus: "进行中",
                expectedDetail: "",
                expectedPriority: "normal",
                expectedSourceLine: 5
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("tasks.md is unreadable"))
        }
        XCTAssertEqual(try Data(contentsOf: tasksURL), original)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeWorkspaceLifecycleStoreRejectsInvalidStatusBeforeChangingWorkspace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-invalid-status-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let workspaceDocumentURL = workspaceURL.appendingPathComponent("workspace.md")
        let statusDocumentURL = workspaceURL.appendingPathComponent("STATUS.md")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let originalWorkspace = "# Workspace\n\n- 当前状态: developing\n"
        try originalWorkspace.write(to: workspaceDocumentURL, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: statusDocumentURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try NativeWorkspaceLifecycleStore.update(
                request: UpdateWorkspaceLifecycleRequest(
                    workspacePath: workspaceURL.path,
                    state: "archived",
                    confirmed: true
                ),
                expectedState: "developing"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("lifecycle document is not a file"))
        }

        XCTAssertEqual(try String(contentsOf: workspaceDocumentURL, encoding: .utf8), originalWorkspace)
    }

    func testNativeWorkspaceLifecycleStoreRejectsSymlinkBeforeWriting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-symlink-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let workspaceDocumentURL = workspaceURL.appendingPathComponent("workspace.md")
        let statusDocumentURL = workspaceURL.appendingPathComponent("STATUS.md")
        let statusTargetURL = root.appendingPathComponent("status-target.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let originalWorkspace = "# Workspace\n\n- 当前状态: developing\n"
        let originalTarget = "# STATUS\n\n- 状态: developing\n"
        try originalWorkspace.write(to: workspaceDocumentURL, atomically: true, encoding: .utf8)
        try originalTarget.write(to: statusTargetURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: statusDocumentURL, withDestinationURL: statusTargetURL)

        var writeCount = 0
        XCTAssertThrowsError(
            try NativeWorkspaceLifecycleStore.update(
                request: UpdateWorkspaceLifecycleRequest(
                    workspacePath: workspaceURL.path,
                    state: "archived",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedState: "developing",
                writeFile: { content, url in
                    writeCount += 1
                    try content.write(to: url, atomically: true, encoding: .utf8)
                }
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("lifecycle document is not a file"))
        }

        XCTAssertEqual(writeCount, 0)
        XCTAssertEqual(try String(contentsOf: workspaceDocumentURL, encoding: .utf8), originalWorkspace)
        XCTAssertEqual(try String(contentsOf: statusTargetURL, encoding: .utf8), originalTarget)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: statusDocumentURL.path),
            statusTargetURL.path
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeWorkspaceLifecycleStoreRejectsStaleAndConflictingEvidenceBeforeWriting() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-conflicts-\(UUID().uuidString)")
        let staleURL = root.appendingPathComponent("stale")
        let conflictURL = root.appendingPathComponent("conflict")
        let auditRoot = root.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        for directory in [staleURL, conflictURL] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        let staleWorkspace = "# Workspace\n\n- 当前状态: delivery\n"
        let staleStatus = "# STATUS\n\n- 状态: delivery\n- 当前焦点: External edit\n"
        try staleWorkspace.write(to: staleURL.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
        try staleStatus.write(to: staleURL.appendingPathComponent("STATUS.md"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try NativeWorkspaceLifecycleStore.update(
                request: UpdateWorkspaceLifecycleRequest(
                    workspacePath: staleURL.path,
                    state: "archived",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedState: "developing"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("expected developing, found delivery"))
        }
        XCTAssertEqual(try String(contentsOf: staleURL.appendingPathComponent("workspace.md"), encoding: .utf8), staleWorkspace)
        XCTAssertEqual(try String(contentsOf: staleURL.appendingPathComponent("STATUS.md"), encoding: .utf8), staleStatus)

        let conflictWorkspace = "# Workspace\n\n- 当前状态: developing\n"
        let conflictStatus = "# STATUS\n\n- 状态: archived\n"
        try conflictWorkspace.write(to: conflictURL.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
        try conflictStatus.write(to: conflictURL.appendingPathComponent("STATUS.md"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try NativeWorkspaceLifecycleStore.update(
                request: UpdateWorkspaceLifecycleRequest(
                    workspacePath: conflictURL.path,
                    state: "delivery",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedState: "blocked"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("workspace.md=developing"))
            XCTAssertTrue(error.localizedDescription.contains("STATUS.md=archived"))
        }

        XCTAssertEqual(try String(contentsOf: conflictURL.appendingPathComponent("workspace.md"), encoding: .utf8), conflictWorkspace)
        XCTAssertEqual(try String(contentsOf: conflictURL.appendingPathComponent("STATUS.md"), encoding: .utf8), conflictStatus)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeWorkspaceLifecycleStoreCanonicalizesStateAliasesAcrossRescanAndSecondUpdate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-aliases-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("2026-07-10-lifecycle-aliases")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try "# Workspace\n\n- 状态: developing\n".write(
            to: workspaceURL.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# STATUS\n\n- 当前状态: developing\n".write(
            to: workspaceURL.appendingPathComponent("STATUS.md"),
            atomically: true,
            encoding: .utf8
        )

        _ = try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: "archived",
                confirmed: true
            ),
            expectedState: "developing"
        )
        let rescanned = try NativeWorkspaceScanner.scan(
            workspacesRoot: root.path,
            sourceReposRoot: root.appendingPathComponent("source-repos").path,
            docsRoot: root.appendingPathComponent("docs").path
        )
        let rescannedWorkspace = try XCTUnwrap(rescanned.workspaces.first)

        XCTAssertEqual(rescannedWorkspace.lifecycle?.stage, "archived")
        XCTAssertFalse(rescannedWorkspace.risks.contains { $0.contains("生命周期状态冲突") })

        _ = try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: "developing",
                confirmed: true
            ),
            expectedState: "archived"
        )
        let workspaceContent = try String(
            contentsOf: workspaceURL.appendingPathComponent("workspace.md"),
            encoding: .utf8
        )
        let statusContent = try String(
            contentsOf: workspaceURL.appendingPathComponent("STATUS.md"),
            encoding: .utf8
        )

        XCTAssertEqual(workspaceContent.components(separatedBy: "- 当前状态:").count - 1, 1)
        XCTAssertFalse(workspaceContent.contains("- 状态:"))
        XCTAssertEqual(statusContent.components(separatedBy: "- 状态:").count - 1, 1)
        XCTAssertFalse(statusContent.contains("- 当前状态:"))
    }

    func testNativeWorkspaceLifecycleStoreResolvesRecognizedStateWhenOtherStateIsEmpty() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-one-empty-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try "# Workspace\n\n- 当前状态:   \n".write(
            to: workspaceURL.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# STATUS\n\n- 状态: developing\n".write(
            to: workspaceURL.appendingPathComponent("STATUS.md"),
            atomically: true,
            encoding: .utf8
        )

        let response = try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: "archived",
                confirmed: true
            ),
            expectedState: "developing"
        )

        XCTAssertEqual(response.previousState, "developing")
        XCTAssertEqual(response.state, "archived")
    }

    func testNativeWorkspaceLifecycleStoreTreatsBothEmptyStatesAsUnknown() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-both-empty-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try "# Workspace\n\n- 当前状态:\n".write(
            to: workspaceURL.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# STATUS\n\n- 状态: ` `\n".write(
            to: workspaceURL.appendingPathComponent("STATUS.md"),
            atomically: true,
            encoding: .utf8
        )

        let response = try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: "developing",
                confirmed: true
            ),
            expectedState: "unknown"
        )

        XCTAssertEqual(response.previousState, "unknown")
        XCTAssertEqual(response.state, "developing")
    }

    func testNativeWorkspaceLifecycleStoreRejectsConflictingAliasesWithinOneDocument() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-single-doc-conflict-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let workspaceDocumentURL = workspaceURL.appendingPathComponent("workspace.md")
        let statusDocumentURL = workspaceURL.appendingPathComponent("STATUS.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let originalWorkspace = """
        # Workspace

        - 当前状态: developing
        - 状态: archived
        - 需求名称: Single doc conflict
        """ + "\n"
        let originalStatus = """
        # STATUS

        - 状态: developing
        - 当前焦点: Hold steady
        """ + "\n"
        try originalWorkspace.write(to: workspaceDocumentURL, atomically: true, encoding: .utf8)
        try originalStatus.write(to: statusDocumentURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try NativeWorkspaceLifecycleStore.update(
                request: UpdateWorkspaceLifecycleRequest(
                    workspacePath: workspaceURL.path,
                    state: "delivery",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedState: "developing"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("workspace.md"))
            XCTAssertTrue(error.localizedDescription.contains("developing"))
            XCTAssertTrue(error.localizedDescription.contains("archived"))
        }

        XCTAssertEqual(try String(contentsOf: workspaceDocumentURL, encoding: .utf8), originalWorkspace)
        XCTAssertEqual(try String(contentsOf: statusDocumentURL, encoding: .utf8), originalStatus)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeWorkspaceLifecycleStoreUsesRecognizedAliasAfterEmptyFirstAliasInSameDocument() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-same-doc-empty-first-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let workspaceDocumentURL = workspaceURL.appendingPathComponent("workspace.md")
        let statusDocumentURL = workspaceURL.appendingPathComponent("STATUS.md")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try """
        # Workspace

        - 当前状态:
        - 状态: developing
        - 需求名称: Empty first alias
        """.write(
            to: workspaceDocumentURL,
            atomically: true,
            encoding: .utf8
        )
        try "# STATUS\n\n".write(
            to: statusDocumentURL,
            atomically: true,
            encoding: .utf8
        )

        let response = try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: "archived",
                confirmed: true
            ),
            expectedState: "developing"
        )
        let workspaceContent = try String(contentsOf: workspaceDocumentURL, encoding: .utf8)
        let statusContent = try String(contentsOf: statusDocumentURL, encoding: .utf8)

        XCTAssertEqual(response.previousState, "developing")
        XCTAssertEqual(response.state, "archived")
        XCTAssertEqual(workspaceContent.components(separatedBy: "- 当前状态:").count - 1, 1)
        XCTAssertFalse(workspaceContent.contains("- 状态:"))
        XCTAssertEqual(statusContent.components(separatedBy: "- 状态:").count - 1, 1)
    }

    func testNativeWorkspaceLifecycleStoreRollsBackBothDocumentsWhenSecondWriteFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-rollback-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let workspaceDocumentURL = workspaceURL.appendingPathComponent("workspace.md")
        let statusDocumentURL = workspaceURL.appendingPathComponent("STATUS.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let originalWorkspace = "# Workspace\n\n- 当前状态: developing\n- 需求名称: Rollback Demo\n"
        let originalStatus = "# STATUS\n\n- 状态: developing\n- 当前焦点: Before write\n- 下一步: Keep original\n"
        try originalWorkspace.write(to: workspaceDocumentURL, atomically: true, encoding: .utf8)
        try originalStatus.write(to: statusDocumentURL, atomically: true, encoding: .utf8)

        var writeCount = 0
        XCTAssertThrowsError(
            try NativeWorkspaceLifecycleStore.update(
                request: UpdateWorkspaceLifecycleRequest(
                    workspacePath: workspaceURL.path,
                    state: "archived",
                    focus: "Should roll back",
                    nextAction: "Keep both originals",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedState: "developing",
                writeFile: { content, url in
                    writeCount += 1
                    if writeCount == 2 {
                        try content.write(to: url, atomically: true, encoding: .utf8)
                        throw NSError(
                            domain: "NativeWorkspaceLifecycleStoreTests",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "injected STATUS.md write failure"]
                        )
                    }
                    try content.write(to: url, atomically: true, encoding: .utf8)
                }
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("injected STATUS.md write failure"))
        }

        XCTAssertEqual(writeCount, 4)
        XCTAssertEqual(try String(contentsOf: workspaceDocumentURL, encoding: .utf8), originalWorkspace)
        XCTAssertEqual(try String(contentsOf: statusDocumentURL, encoding: .utf8), originalStatus)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeWorkspaceLifecycleStoreRemovesOriginallyMissingDocumentsAfterWriteFailure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-missing-rollback-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let workspaceDocumentURL = workspaceURL.appendingPathComponent("workspace.md")
        let statusDocumentURL = workspaceURL.appendingPathComponent("STATUS.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        var writeCount = 0
        XCTAssertThrowsError(
            try NativeWorkspaceLifecycleStore.update(
                request: UpdateWorkspaceLifecycleRequest(
                    workspacePath: workspaceURL.path,
                    state: "developing",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedState: "unknown",
                writeFile: { content, url in
                    writeCount += 1
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    if writeCount == 2 {
                        throw NSError(
                            domain: "NativeWorkspaceLifecycleStoreTests",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "injected write failure after creating STATUS.md"]
                        )
                    }
                }
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("injected write failure after creating STATUS.md"))
        }

        XCTAssertEqual(writeCount, 2)
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspaceDocumentURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: statusDocumentURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeWorkspaceLifecycleStoreContinuesRollbackAndReportsRollbackFailure() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-rollback-failure-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let workspaceDocumentURL = workspaceURL.appendingPathComponent("workspace.md")
        let statusDocumentURL = workspaceURL.appendingPathComponent("STATUS.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let originalWorkspace = "# Workspace\n\n- 当前状态: developing\n- 需求名称: Rollback Failure\n"
        let originalStatus = "# STATUS\n\n- 状态: developing\n- 当前焦点: Before write\n"
        try originalWorkspace.write(to: workspaceDocumentURL, atomically: true, encoding: .utf8)
        try originalStatus.write(to: statusDocumentURL, atomically: true, encoding: .utf8)

        var writeCount = 0
        XCTAssertThrowsError(
            try NativeWorkspaceLifecycleStore.update(
                request: UpdateWorkspaceLifecycleRequest(
                    workspacePath: workspaceURL.path,
                    state: "archived",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedState: "developing",
                writeFile: { content, url in
                    writeCount += 1
                    if writeCount == 3 {
                        throw NSError(
                            domain: "NativeWorkspaceLifecycleStoreTests",
                            code: 3,
                            userInfo: [NSLocalizedDescriptionKey: "injected STATUS.md rollback failure"]
                        )
                    }
                    try content.write(to: url, atomically: true, encoding: .utf8)
                    if writeCount == 2 {
                        throw NSError(
                            domain: "NativeWorkspaceLifecycleStoreTests",
                            code: 2,
                            userInfo: [NSLocalizedDescriptionKey: "injected STATUS.md target write failure"]
                        )
                    }
                }
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("rollback is incomplete"))
            XCTAssertTrue(error.localizedDescription.contains("injected STATUS.md target write failure"))
            XCTAssertTrue(error.localizedDescription.contains("injected STATUS.md rollback failure"))
        }

        XCTAssertEqual(writeCount, 4)
        XCTAssertEqual(try String(contentsOf: workspaceDocumentURL, encoding: .utf8), originalWorkspace)
        XCTAssertNotEqual(try String(contentsOf: statusDocumentURL, encoding: .utf8), originalStatus)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeWorkspaceLifecycleStoreRequiresConfirmationAndRewritesStatusDocuments() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("2026-05-28-lifecycle")
        let auditRoot = root.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let workspaceMarkdown = """
        # Lifecycle

        - 需求名称: Lifecycle Demo
        - 当前状态: developing
        - 目标分支: chen/lifecycle
        """ + "\n"
        let statusMarkdown = """
        # STATUS

        - 状态: developing
        - 当前焦点: 编码
        - 下一步: 继续验证
        - 更新时间: old
        """ + "\n"
        try workspaceMarkdown.write(to: workspaceURL.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
        try statusMarkdown.write(to: workspaceURL.appendingPathComponent("STATUS.md"), atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try NativeWorkspaceLifecycleStore.update(
                request: UpdateWorkspaceLifecycleRequest(
                    workspacePath: workspaceURL.path,
                    state: "archived",
                    confirmed: false
                ),
                expectedState: "developing"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("explicit confirmation"))
        }

        let response = try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: "archived",
                focus: "保留历史上下文",
                nextAction: "需要再次开发时从 handoff 恢复上下文",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedState: "developing"
        )
        let workspaceContent = try String(contentsOf: workspaceURL.appendingPathComponent("workspace.md"), encoding: .utf8)
        let statusContent = try String(contentsOf: workspaceURL.appendingPathComponent("STATUS.md"), encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertTrue(response.updated)
        XCTAssertEqual(response.previousState, "developing")
        XCTAssertEqual(response.state, "archived")
        XCTAssertEqual(response.workspaceDocumentPath, workspaceURL.appendingPathComponent("workspace.md").path)
        XCTAssertEqual(response.statusDocumentPath, workspaceURL.appendingPathComponent("STATUS.md").path)
        XCTAssertTrue(workspaceContent.contains("- 当前状态: archived"))
        XCTAssertTrue(statusContent.contains("- 状态: archived"))
        XCTAssertTrue(statusContent.contains("- 当前焦点: 保留历史上下文"))
        XCTAssertTrue(statusContent.contains("- 下一步: 需要再次开发时从 handoff 恢复上下文"))
        XCTAssertTrue(statusContent.contains("- 更新时间: "))
        XCTAssertTrue(statusContent.hasSuffix("\n"))
        XCTAssertEqual(response.auditEventID, events.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(events.first?.action, "workspace_lifecycle.updated")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["previousState"], "developing")
        XCTAssertEqual(events.first?.metadata["state"], "archived")

        let invalidAuditRoot = root.appendingPathComponent("invalid-audit")
        try "not a directory".write(to: invalidAuditRoot, atomically: true, encoding: .utf8)
        let auditFailure = try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: "developing",
                confirmed: true,
                auditRoot: invalidAuditRoot.path,
                actor: "Nexus Test"
            ),
            expectedState: "archived"
        )
        XCTAssertEqual(auditFailure.state, "developing")
        XCTAssertNotNil(auditFailure.auditError)
    }

    func testNativeDocumentStoreReadsLocalSnapshots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-document-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let markdownURL = root.appendingPathComponent("STATUS.md")
        let sourceURL = root.appendingPathComponent("change.sql")
        try "# Status\n\nReady for native preview.\n".write(to: markdownURL, atomically: true, encoding: .utf8)
        try "select 1;\n".write(to: sourceURL, atomically: true, encoding: .utf8)

        let markdown = try NativeDocumentStore.read(path: markdownURL.path)
        let source = try NativeDocumentStore.read(path: sourceURL.path)

        XCTAssertEqual(markdown.path, markdownURL.path)
        XCTAssertEqual(markdown.name, "STATUS.md")
        XCTAssertEqual(markdown.extension, "md")
        XCTAssertEqual(markdown.isMarkdown, true)
        XCTAssertTrue(markdown.content.contains("Ready for native preview"))
        XCTAssertEqual(source.name, "change.sql")
        XCTAssertEqual(source.extension, "sql")
        XCTAssertEqual(source.isMarkdown, false)
        XCTAssertEqual(source.content, "select 1;\n")
    }

    func testNativeDocumentStoreCreatesStandardDocumentsWithoutOverwriting() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-create-document-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let created = try NativeDocumentStore.createWorkspaceDocument(
            workspacePath: workspaceURL.path,
            documentKey: "tasks",
            relativePath: "tasks.md",
            confirmed: true
        )
        let existing = try NativeDocumentStore.createWorkspaceDocument(
            workspacePath: workspaceURL.path,
            documentKey: "tasks",
            relativePath: "./tasks.md",
            confirmed: true
        )
        let content = try String(contentsOf: workspaceURL.appendingPathComponent("tasks.md"), encoding: .utf8)

        XCTAssertEqual(created.path, workspaceURL.appendingPathComponent("tasks.md").path)
        XCTAssertEqual(created.relativePath, "tasks.md")
        XCTAssertEqual(created.created, true)
        XCTAssertEqual(created.alreadyExists, false)
        XCTAssertTrue(content.contains("| 任务 | 状态 | 说明 |"))
        XCTAssertEqual(existing.created, false)
        XCTAssertEqual(existing.alreadyExists, true)
    }

    func testNativeDocumentStoreRejectsUnsafeDocumentCreation() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-create-document-reject-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try NativeDocumentStore.createWorkspaceDocument(
                workspacePath: workspaceURL.path,
                documentKey: "tasks",
                relativePath: "tasks.md",
                confirmed: false
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("explicit confirmation"))
        }
        XCTAssertThrowsError(
            try NativeDocumentStore.createWorkspaceDocument(
                workspacePath: workspaceURL.path,
                documentKey: "tasks",
                relativePath: "../tasks.md",
                confirmed: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("parent directories"))
        }
        XCTAssertThrowsError(
            try NativeDocumentStore.createWorkspaceDocument(
                workspacePath: workspaceURL.path,
                documentKey: "sql",
                relativePath: "sql/change.sql",
                confirmed: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("unsupported workspace document key"))
        }
    }

    func testNativeDocumentStoreRejectsSymlinksAndPreservesExternalFileRace() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-document-safety-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let externalURL = root.appendingPathComponent("external")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalURL, withIntermediateDirectories: true)

        let linkedWorkspaceURL = root.appendingPathComponent("linked-workspace")
        try FileManager.default.createSymbolicLink(at: linkedWorkspaceURL, withDestinationURL: workspaceURL)
        XCTAssertThrowsError(
            try NativeDocumentStore.createWorkspaceDocument(
                workspacePath: linkedWorkspaceURL.path,
                documentKey: "tasks",
                relativePath: "tasks.md",
                confirmed: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("not a real directory"))
        }

        let externalTasksURL = externalURL.appendingPathComponent("tasks.md")
        try "# External tasks\n".write(to: externalTasksURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: workspaceURL.appendingPathComponent("tasks.md"),
            withDestinationURL: externalTasksURL
        )
        XCTAssertThrowsError(
            try NativeDocumentStore.createWorkspaceDocument(
                workspacePath: workspaceURL.path,
                documentKey: "tasks",
                relativePath: "tasks.md",
                confirmed: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("not a regular file"))
        }

        try FileManager.default.createSymbolicLink(
            at: workspaceURL.appendingPathComponent("scripts"),
            withDestinationURL: externalURL
        )
        XCTAssertThrowsError(
            try NativeDocumentStore.createWorkspaceDocument(
                workspacePath: workspaceURL.path,
                documentKey: "worktreeScript",
                relativePath: "scripts/worktree-commands.sh",
                confirmed: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("parent path is not a real directory"))
        }

        let raceWorkspaceURL = root.appendingPathComponent("race-workspace")
        try FileManager.default.createDirectory(at: raceWorkspaceURL, withIntermediateDirectories: true)
        let raceExternalContent = Data("# External race\n".utf8)
        XCTAssertThrowsError(
            try NativeDocumentStore.createWorkspaceDocument(
                workspacePath: raceWorkspaceURL.path,
                documentKey: "tasks",
                relativePath: "tasks.md",
                confirmed: true,
                fileWriter: { data, url in
                    try raceExternalContent.write(to: url, options: [.withoutOverwriting])
                    try data.write(to: url, options: [.withoutOverwriting])
                }
            )
        )
        XCTAssertEqual(
            try Data(contentsOf: raceWorkspaceURL.appendingPathComponent("tasks.md")),
            raceExternalContent
        )
    }

    @MainActor
    func testAppStateDocumentRecoveryPreservesNativeErrorWithoutBridgeFallback() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-app-state-document-native-only-\(UUID().uuidString)")
        let workspaceURL = root.appendingPathComponent("workspace")
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let workspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "document-native-only",
            path: workspaceURL.path
        )
        let appState = AppState(
            workspaces: [workspace],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: root.path,
            sourceReposRoot: root.path,
            docsRoot: root.path,
            defaults: defaults
        )

        let response = await appState.createWorkspaceDocument(
            in: workspace,
            documentKey: "tasks",
            relativePath: "../tasks.md",
            documentLabel: "tasks.md",
            confirmed: true
        )

        XCTAssertNil(response)
        XCTAssertTrue(appState.lastError?.contains("cannot contain parent directories") == true)
        XCTAssertFalse(appState.lastError?.contains("Nexus Core bridge") == true)
        XCTAssertFalse(appState.isCreatingDocument)
    }

    func testNativeDemandIntakeStoreReportsStatusFromWorkspaceFiles() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-status-\(UUID().uuidString)")
        let demandURL = workspaceURL.appendingPathComponent("需求")
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: demandURL, withIntermediateDirectories: true)
        try "# 需求确认卡\n".write(to: demandURL.appendingPathComponent("requirement.md"), atomically: true, encoding: .utf8)
        try "# 待确认问题\n".write(to: demandURL.appendingPathComponent("questions.md"), atomically: true, encoding: .utf8)

        let status = try NativeDemandIntakeStore.status(workspacePath: workspaceURL.path)

        XCTAssertEqual(status.directoryPath, demandURL.path)
        XCTAssertEqual(status.exists, true)
        XCTAssertEqual(status.ready, false)
        XCTAssertEqual(status.missingCount, 3)
        XCTAssertEqual(status.files.map(\.filename), ["requirement.md", "questions.md", "scope.md", "tasks.md", "delivery.md"])
        XCTAssertEqual(status.files.filter { $0.exists }.map(\.filename), ["requirement.md", "questions.md"])
    }

    func testNativeDemandIntakeStoreStatusRejectsUnsafeEntryEvidence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-unsafe-status-\(UUID().uuidString)")
        let externalDirectory = root.appendingPathComponent("external-demand")
        let externalTasks = root.appendingPathComponent("external-tasks.md")
        let linkedDirectoryWorkspace = root.appendingPathComponent("linked-directory-workspace")
        let linkedFileWorkspace = root.appendingPathComponent("linked-file-workspace")
        let directoryFileWorkspace = root.appendingPathComponent("directory-file-workspace")
        let invalidFileWorkspace = root.appendingPathComponent("invalid-file-workspace")
        let linkedWorkspace = root.appendingPathComponent("linked-workspace")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDirectory, withIntermediateDirectories: true)
        try "# External tasks\n".write(to: externalTasks, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: linkedDirectoryWorkspace, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: linkedDirectoryWorkspace.appendingPathComponent("需求"),
            withDestinationURL: externalDirectory
        )

        for workspace in [linkedFileWorkspace, directoryFileWorkspace, invalidFileWorkspace] {
            try FileManager.default.createDirectory(
                at: workspace.appendingPathComponent("需求"),
                withIntermediateDirectories: true
            )
        }
        try FileManager.default.createSymbolicLink(
            at: linkedFileWorkspace.appendingPathComponent("需求/tasks.md"),
            withDestinationURL: externalTasks
        )
        try FileManager.default.createDirectory(
            at: directoryFileWorkspace.appendingPathComponent("需求/tasks.md"),
            withIntermediateDirectories: true
        )
        try Data([0x23, 0x20, 0xC3, 0x28, 0x0A]).write(
            to: invalidFileWorkspace.appendingPathComponent("需求/tasks.md")
        )
        try FileManager.default.createSymbolicLink(at: linkedWorkspace, withDestinationURL: linkedFileWorkspace)

        let linkedDirectoryStatus = try NativeDemandIntakeStore.status(workspacePath: linkedDirectoryWorkspace.path)
        let linkedFileStatus = try NativeDemandIntakeStore.status(workspacePath: linkedFileWorkspace.path)
        let directoryFileStatus = try NativeDemandIntakeStore.status(workspacePath: directoryFileWorkspace.path)
        let invalidFileStatus = try NativeDemandIntakeStore.status(workspacePath: invalidFileWorkspace.path)

        XCTAssertFalse(linkedDirectoryStatus.exists)
        XCTAssertFalse(linkedDirectoryStatus.ready)
        XCTAssertEqual(linkedDirectoryStatus.missingCount, 5)
        XCTAssertFalse(linkedFileStatus.files.first { $0.key == "tasks" }?.exists ?? true)
        XCTAssertFalse(directoryFileStatus.files.first { $0.key == "tasks" }?.exists ?? true)
        XCTAssertFalse(invalidFileStatus.files.first { $0.key == "tasks" }?.exists ?? true)
        XCTAssertThrowsError(
            try NativeDemandIntakeStore.status(workspacePath: linkedWorkspace.path)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("workspace path is not a real directory"))
        }
    }

    func testNativeDemandIntakeInitializationPlanCapturesStatesTemplatesAndNoOp() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-initialization-plan-\(UUID().uuidString)")
        let missingWorkspace = root.appendingPathComponent("missing-workspace")
        let partialWorkspace = root.appendingPathComponent("partial-workspace")
        let unsafeDirectoryWorkspace = root.appendingPathComponent("unsafe-directory-workspace")
        let unsafeFileWorkspace = root.appendingPathComponent("unsafe-file-workspace")
        let completeWorkspace = root.appendingPathComponent("complete-workspace")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for workspace in [missingWorkspace, partialWorkspace, unsafeDirectoryWorkspace, unsafeFileWorkspace, completeWorkspace] {
            try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        }
        try FileManager.default.createDirectory(
            at: partialWorkspace.appendingPathComponent("需求"),
            withIntermediateDirectories: true
        )
        try "# Existing questions\n".write(
            to: partialWorkspace.appendingPathComponent("需求/questions.md"),
            atomically: true,
            encoding: .utf8
        )

        let externalDemandDirectory = root.appendingPathComponent("external-demand-directory")
        try FileManager.default.createDirectory(at: externalDemandDirectory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(
            at: unsafeDirectoryWorkspace.appendingPathComponent("需求"),
            withDestinationURL: externalDemandDirectory
        )
        try FileManager.default.createDirectory(
            at: unsafeFileWorkspace.appendingPathComponent("需求"),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: unsafeFileWorkspace.appendingPathComponent("需求/tasks.md"),
            withIntermediateDirectories: true
        )
        let completeDemandDirectory = completeWorkspace.appendingPathComponent("需求")
        try FileManager.default.createDirectory(at: completeDemandDirectory, withIntermediateDirectories: true)
        for filename in ["requirement.md", "questions.md", "scope.md", "tasks.md", "delivery.md"] {
            try "# Complete\n".write(
                to: completeDemandDirectory.appendingPathComponent(filename),
                atomically: true,
                encoding: .utf8
            )
        }

        var demandName = "  会员权益页  "
        var lanhuLink = "  https://lanhu.example/design  "
        var notes = "  先确认首屏  "
        let missingPlan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: missingWorkspace.path,
            demandName: demandName,
            lanhuLink: lanhuLink,
            notes: notes
        )
        demandName = "Changed demand"
        lanhuLink = "https://changed.example/design"
        notes = "Changed notes"
        let partialPlan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: partialWorkspace.path,
            demandName: demandName,
            lanhuLink: lanhuLink,
            notes: notes
        )
        let unsafeDirectoryPlan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: unsafeDirectoryWorkspace.path,
            demandName: demandName,
            lanhuLink: lanhuLink,
            notes: notes
        )
        let unsafeFilePlan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: unsafeFileWorkspace.path,
            demandName: demandName,
            lanhuLink: lanhuLink,
            notes: notes
        )
        let completePlan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: completeWorkspace.path,
            demandName: demandName,
            lanhuLink: lanhuLink,
            notes: notes
        )

        XCTAssertEqual(missingPlan.expectedDemandDirectoryState, .missing)
        XCTAssertEqual(
            missingPlan.createdFiles,
            ["requirement.md", "questions.md", "scope.md", "tasks.md", "delivery.md"]
        )
        XCTAssertTrue(missingPlan.canInitialize)
        XCTAssertTrue(missingPlan.filePlans.first { $0.key == "requirement" }?.template.contains("会员权益页") == true)
        XCTAssertTrue(missingPlan.filePlans.first { $0.key == "requirement" }?.template.contains("https://lanhu.example/design") == true)
        XCTAssertEqual(missingPlan.demandName, "会员权益页")
        XCTAssertEqual(missingPlan.lanhuLink, "https://lanhu.example/design")
        XCTAssertEqual(missingPlan.notes, "先确认首屏")

        XCTAssertEqual(partialPlan.createdFiles, ["requirement.md", "scope.md", "tasks.md", "delivery.md"])
        XCTAssertNil(partialPlan.blockerSummary)
        XCTAssertTrue(partialPlan.canInitialize)

        XCTAssertTrue(unsafeDirectoryPlan.blockerSummary?.contains("not a real directory") == true)
        XCTAssertTrue(unsafeFilePlan.blockerSummary?.contains("not a regular UTF-8 file") == true)
        XCTAssertFalse(unsafeFilePlan.canInitialize)

        XCTAssertTrue(completePlan.createdFiles.isEmpty)
        XCTAssertTrue(completePlan.blockerSummary?.contains("already complete") == true)
        XCTAssertFalse(completePlan.canInitialize)
    }

    func testNativeDemandIntakeStoreInitializesMissingFilesWithoutOverwriting() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-init-\(UUID().uuidString)")
        let demandURL = workspaceURL.appendingPathComponent("需求")
        let auditRoot = workspaceURL.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: demandURL, withIntermediateDirectories: true)
        try "# Existing questions\n".write(to: demandURL.appendingPathComponent("questions.md"), atomically: true, encoding: .utf8)

        let plan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: workspaceURL.path,
            demandName: "会员权益页",
            lanhuLink: "https://lanhu.example/design",
            notes: "先确认首屏"
        )
        let response = try NativeDemandIntakeStore.initialize(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertEqual(response.status.ready, true)
        XCTAssertEqual(response.status.missingCount, 0)
        XCTAssertEqual(response.createdFiles, ["requirement.md", "scope.md", "tasks.md", "delivery.md"])
        XCTAssertTrue(try String(contentsOf: demandURL.appendingPathComponent("requirement.md"), encoding: .utf8).contains("会员权益页"))
        XCTAssertTrue(try String(contentsOf: demandURL.appendingPathComponent("requirement.md"), encoding: .utf8).contains("https://lanhu.example/design"))
        XCTAssertEqual(try String(contentsOf: demandURL.appendingPathComponent("questions.md"), encoding: .utf8), "# Existing questions\n")
        XCTAssertEqual(response.auditEventID, events.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(events.first?.action, "demand_intake.initialized")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["workspacePath"], workspaceURL.path)
        XCTAssertEqual(events.first?.metadata["createdFiles"], "requirement.md,scope.md,tasks.md,delivery.md")

        let auditFailureWorkspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-audit-failure-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: auditFailureWorkspace) }
        try FileManager.default.createDirectory(at: auditFailureWorkspace, withIntermediateDirectories: true)
        let invalidAuditRoot = auditFailureWorkspace.appendingPathComponent("audit")
        try "not a directory".write(to: invalidAuditRoot, atomically: true, encoding: .utf8)
        let auditFailurePlan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: auditFailureWorkspace.path,
            demandName: "审计失败仍保留需求文件",
            lanhuLink: "",
            notes: ""
        )
        let auditFailure = try NativeDemandIntakeStore.initialize(
            plan: auditFailurePlan,
            confirmed: true,
            auditRoot: invalidAuditRoot.path,
            actor: "Nexus Test"
        )
        XCTAssertTrue(auditFailure.status.ready)
        XCTAssertNotNil(auditFailure.auditError)
    }

    func testNativeDemandIntakeStoreRejectsChangedEntriesBeforeMutation() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-stale-plan-\(UUID().uuidString)")
        let demandURL = workspaceURL.appendingPathComponent("需求")
        let auditRoot = workspaceURL.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let plan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: workspaceURL.path,
            demandName: "Stale plan",
            lanhuLink: "",
            notes: ""
        )
        try FileManager.default.createDirectory(at: demandURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try NativeDemandIntakeStore.initialize(
                plan: plan,
                confirmed: true,
                auditRoot: auditRoot.path
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }
        XCTAssertTrue(FileManager.default.fileExists(atPath: demandURL.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: demandURL.appendingPathComponent("requirement.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeDemandIntakeStoreRollsBackPartialWriteFailure() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-rollback-\(UUID().uuidString)")
        let demandURL = workspaceURL.appendingPathComponent("需求")
        let auditRoot = workspaceURL.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let plan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: workspaceURL.path,
            demandName: "Rollback",
            lanhuLink: "",
            notes: ""
        )
        var writeCount = 0

        XCTAssertThrowsError(
            try NativeDemandIntakeStore.initialize(
                plan: plan,
                confirmed: true,
                auditRoot: auditRoot.path,
                fileWriter: { data, url in
                    writeCount += 1
                    if writeCount == 3 {
                        throw NSError(domain: "NexusTests", code: 1)
                    }
                    try data.write(to: url, options: [.withoutOverwriting])
                }
            )
        )
        XCTAssertEqual(writeCount, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: demandURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeDemandIntakeStorePreservesExternalNoOverwriteRaceAndRollsBack() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-race-\(UUID().uuidString)")
        let demandURL = workspaceURL.appendingPathComponent("需求")
        let auditRoot = workspaceURL.appendingPathComponent("audit")
        let externalContent = Data("# External scope\n".utf8)
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let plan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: workspaceURL.path,
            demandName: "Race",
            lanhuLink: "",
            notes: ""
        )
        var writeCount = 0

        XCTAssertThrowsError(
            try NativeDemandIntakeStore.initialize(
                plan: plan,
                confirmed: true,
                auditRoot: auditRoot.path,
                fileWriter: { data, url in
                    writeCount += 1
                    if writeCount == 3 {
                        try externalContent.write(to: url, options: [.withoutOverwriting])
                    }
                    try data.write(to: url, options: [.withoutOverwriting])
                }
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("cleanup needs review"))
        }
        XCTAssertEqual(writeCount, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: demandURL.path))
        XCTAssertEqual(
            try Data(contentsOf: demandURL.appendingPathComponent("scope.md")),
            externalContent
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: demandURL.appendingPathComponent("requirement.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: demandURL.appendingPathComponent("questions.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: demandURL.appendingPathComponent("tasks.md").path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: demandURL.appendingPathComponent("delivery.md").path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeDemandIntakeStoreRejectsNoOpAndSecondSubmissionWithoutAudit() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-noop-\(UUID().uuidString)")
        let auditRoot = workspaceURL.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let initialPlan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: workspaceURL.path,
            demandName: "No-op",
            lanhuLink: "",
            notes: ""
        )

        _ = try NativeDemandIntakeStore.initialize(
            plan: initialPlan,
            confirmed: true,
            auditRoot: auditRoot.path
        )
        XCTAssertThrowsError(
            try NativeDemandIntakeStore.initialize(
                plan: initialPlan,
                confirmed: true,
                auditRoot: auditRoot.path
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }

        let completePlan = NativeDemandIntakeStore.makeInitializationPlan(
            workspacePath: workspaceURL.path,
            demandName: "No-op",
            lanhuLink: "",
            notes: ""
        )
        XCTAssertFalse(completePlan.canInitialize)
        XCTAssertThrowsError(
            try NativeDemandIntakeStore.initialize(
                plan: completePlan,
                confirmed: true,
                auditRoot: auditRoot.path
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("cannot write"))
        }
        XCTAssertEqual(
            try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 10)
                .filter { $0.action == "demand_intake.initialized" }
                .count,
            1
        )
    }

    func testNativeDemandIntakeStoreRequiresConfirmationAndFileEntries() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-reject-\(UUID().uuidString)")
        let demandURL = workspaceURL.appendingPathComponent("需求")
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: demandURL, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try NativeDemandIntakeStore.initialize(
                workspacePath: workspaceURL.path,
                demandName: "",
                lanhuLink: "",
                notes: "",
                confirmed: false
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("explicit confirmation"))
        }

        try FileManager.default.createDirectory(at: demandURL.appendingPathComponent("tasks.md"), withIntermediateDirectories: true)
        XCTAssertThrowsError(
            try NativeDemandIntakeStore.initialize(
                workspacePath: workspaceURL.path,
                demandName: "Demo",
                lanhuLink: "",
                notes: "",
                confirmed: true
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("not a regular UTF-8 file"))
        }
    }

    @MainActor
    func testRealDemandFilesKeepNativeStageSurfacesAligned() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-stage-evidence-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let docsRoot = root.appendingPathComponent("docs")
        let auditRoot = root.appendingPathComponent("audit")
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        for directory in [workspacesRoot, sourceRoot, docsRoot, auditRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let created = try NativeWorkspaceCreationStore.create(
            request: CreateWorkspaceRequest(
                name: "Stage Evidence",
                folder: "2026-07-10-stage-evidence",
                workspacesRoot: workspacesRoot.path,
                sourceReposRoot: sourceRoot.path,
                services: [],
                targetBranch: "",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Tests"
            )
        )
        _ = try NativeDemandIntakeStore.initialize(
            workspacePath: created.path,
            demandName: "Stage Evidence",
            lanhuLink: "https://lanhu.example/stage-evidence",
            notes: "Keep every Native surface aligned.",
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Tests"
        )
        let dashboard = try NativeWorkspaceScanner.scan(
            workspacesRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path
        )
        let workspace = try XCTUnwrap(
            dashboard.workspaces.map(WorkspaceSummary.init(snapshot:)).first
        )
        let appState = AppState(
            workspaces: [workspace],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path,
            defaults: defaults
        )

        let canonicalStage = appState.mainWorkflowStage(for: workspace)
        let directStage = workspace.mainStage()
        let boardLanes = WorkspaceBoardLane.lanes(for: [workspace])
        let summary = WorkspaceListSummary(workspaces: [workspace])
        let widget = NativeWidgetSnapshotBuilder.build(
            generatedAt: "2026-07-10T00:00:00Z",
            workspacesRoot: workspacesRoot.path,
            workspaces: [workspace],
            activeWorkspaceID: workspace.id
        )

        XCTAssertEqual(canonicalStage.id, .demandIntake)
        XCTAssertEqual(directStage, canonicalStage)
        XCTAssertEqual(boardLanes.first { $0.id == .attention }?.workspaces.count, 1)
        XCTAssertEqual(boardLanes.first { $0.id == .active }?.workspaces.count, 0)
        XCTAssertEqual(summary.blockedWorkspaceCount, 1)
        XCTAssertTrue(appState.menuBarSummary.activeStageLine?.contains(canonicalStage.answer.stageLabel) == true)
        XCTAssertEqual(widget.mainStage, canonicalStage.answer.stageLabel)
        XCTAssertEqual(widget.mainStageStatus, canonicalStage.answer.status.displayLabel)
        XCTAssertEqual(widget.mainStageNextAction, canonicalStage.answer.nextActionLabel)
        XCTAssertEqual(widget.mainStageEvidence, canonicalStage.answer.primaryEvidenceLink?.label)
    }

    func testNativeSourceRepositoryStoreSortsAndFiltersDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-source-repos-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("order"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("commodity"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("dist"), withIntermediateDirectories: true)
        try "not a repo".write(to: root.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let repos = try NativeSourceRepositoryStore.scan(sourceReposRoot: root.path)

        XCTAssertEqual(repos.map(\.name), ["commodity", "order"])
        XCTAssertEqual(repos.map(\.isGit), [false, false])
        XCTAssertEqual(repos.map(\.branch), ["非 git worktree", "非 git worktree"])
        XCTAssertEqual(repos.map(\.summary), ["目录存在但不是 git worktree", "目录存在但不是 git worktree"])
        XCTAssertTrue(try NativeSourceRepositoryStore.scan(sourceReposRoot: root.appendingPathComponent("missing").path).isEmpty)
    }

    func testNativeSourceRepositoryStoreReadsGitStatus() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-source-git-\(UUID().uuidString)")
        let repo = root.appendingPathComponent("order")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: repo, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repo)
        try "dirty\n".write(to: repo.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)

        let repos = try NativeSourceRepositoryStore.scan(sourceReposRoot: root.path)

        XCTAssertEqual(repos.count, 1)
        XCTAssertEqual(repos.first?.name, "order")
        XCTAssertEqual(repos.first?.isGit, true)
        XCTAssertEqual(repos.first?.branch, "main")
        XCTAssertEqual(repos.first?.dirty, true)
        XCTAssertEqual(repos.first?.summary, "有未提交改动")
    }

    func testNativeWorkspaceScannerBuildsDashboardFromLocalFiles() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-workspace-scan-\(UUID().uuidString)")
        let workspace = root.appendingPathComponent("2026-06-23-native-dashboard")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: workspace.appendingPathComponent("sql"), withIntermediateDirectories: true)
        try """
        # Native Dashboard

        - 需求名称: Swift Native 仪表盘
        - 目标分支: feature/native-dashboard
        """.write(to: workspace.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
        try """
        # STATUS

        - 当前状态: developing
        - 风险: Rust scanWorkspaces 尚未完全替换
        """.write(to: workspace.appendingPathComponent("STATUS.md"), atomically: true, encoding: .utf8)
        try """
        # Tasks

        | 任务 | 状态 | 说明 | 优先级 |
        | --- | --- | --- | --- |
        | 接入 Native scanner | 进行中 | AppState Native-first | high |
        | 删除 bridge 兜底 | 待办 | 等 Git/worktree 规则补齐 event=agent-1 | medium |
        """.write(to: workspace.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8)
        try """
        | 服务 | 范围 |
        | --- | --- |
        | nexus-app | confirmed |
        | nexus-cli | candidate |
        """.write(to: workspace.appendingPathComponent("services.md"), atomically: true, encoding: .utf8)
        try "select 1;\n".write(to: workspace.appendingPathComponent("sql/change.sql"), atomically: true, encoding: .utf8)
        try "# SQL notes\n".write(to: workspace.appendingPathComponent("sql/README.md"), atomically: true, encoding: .utf8)

        let dashboard = try NativeWorkspaceScanner.scan(
            workspacesRoot: root.path,
            sourceReposRoot: "/tmp/source-repos",
            docsRoot: "/tmp/docs",
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(dashboard.generatedAt, "1970-01-01T00:00:00Z")
        XCTAssertEqual(dashboard.workspaces.map(\.folder), ["2026-06-23-native-dashboard"])
        let snapshot = try XCTUnwrap(dashboard.workspaces.first)
        XCTAssertEqual(snapshot.name, "Swift Native 仪表盘")
        XCTAssertEqual(snapshot.state, "developing")
        XCTAssertEqual(snapshot.targetBranch, "feature/native-dashboard")
        XCTAssertEqual(snapshot.confirmedServices, ["nexus-app"])
        XCTAssertEqual(snapshot.candidateServices, ["nexus-cli"])
        XCTAssertEqual(snapshot.taskCounts.doing, 1)
        XCTAssertEqual(snapshot.taskCounts.todo, 1)
        XCTAssertEqual(snapshot.riskCount, 3)
        XCTAssertEqual(snapshot.gitRows.map(\.service), ["nexus-app"])
        XCTAssertEqual(snapshot.gitRows.first?.worktree.exists, false)
        XCTAssertEqual(snapshot.gitRows.first?.source.exists, false)
        XCTAssertEqual(snapshot.links["workspace"]?.hasSuffix("/2026-06-23-native-dashboard/workspace.md"), true)
        XCTAssertEqual(snapshot.sqlFiles?.map(\.relativePath), ["sql/change.sql"])
        XCTAssertEqual(snapshot.sqlDocuments?.map(\.relativePath), ["sql/README.md"])
        XCTAssertEqual(
            snapshot.tasks?.map(\.id),
            [
                "2026-06-23-native-dashboard:task-0",
                "2026-06-23-native-dashboard:agent-1"
            ]
        )
        XCTAssertEqual(snapshot.tasks?.map(\.source), ["workspace", "agent"])
        XCTAssertEqual(snapshot.tasks?.map(\.sourceEventId), [nil, "agent-1"])
        XCTAssertEqual(snapshot.tasks?.map(\.sourceLine), [5, 6])
        XCTAssertEqual(snapshot.tasks?.map(\.priority), ["high", "medium"])
    }

    func testNativeWorkspaceScannerBuildsConservativeLifecycleFromMarkdownEvidence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-lifecycle-scan-\(UUID().uuidString)")
        let explicit = root.appendingPathComponent("2026-07-10-explicit-lifecycle")
        let missing = root.appendingPathComponent("2026-07-10-missing-lifecycle")
        let conflict = root.appendingPathComponent("2026-07-10-conflicting-lifecycle")
        let unsupported = root.appendingPathComponent("2026-07-10-unsupported-lifecycle")
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        for directory in [explicit, missing, conflict, unsupported] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }

        try """
        # Explicit Lifecycle

        - 需求名称: Explicit Lifecycle
        - 当前状态: developing
        - 目标分支: feature/lifecycle-scan
        """.write(to: explicit.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
        try """
        # STATUS

        - 状态: development
        - 当前焦点: Verify file-backed lifecycle
        - 下一步: Run lifecycle scan tests
        """.write(to: explicit.appendingPathComponent("STATUS.md"), atomically: true, encoding: .utf8)
        try """
        | 服务 | 范围 |
        | --- | --- |
        | order | confirmed |
        """.write(to: explicit.appendingPathComponent("services.md"), atomically: true, encoding: .utf8)

        try """
        # Missing Lifecycle

        - 需求名称: Missing Lifecycle
        """.write(to: missing.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)

        try """
        # Conflicting Lifecycle

        - 需求名称: Conflicting Lifecycle
        - 当前状态: developing
        """.write(to: conflict.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
        try """
        # STATUS

        - 状态: archived
        """.write(to: conflict.appendingPathComponent("STATUS.md"), atomically: true, encoding: .utf8)

        try """
        # Unsupported Lifecycle

        - 需求名称: Unsupported Lifecycle
        - 当前状态: waiting-for-magic
        """.write(to: unsupported.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)

        let dashboard = try NativeWorkspaceScanner.scan(
            workspacesRoot: root.path,
            sourceReposRoot: root.appendingPathComponent("source-repos").path,
            docsRoot: root.appendingPathComponent("docs").path,
            now: Date(timeIntervalSince1970: 0)
        )
        let snapshots = Dictionary(uniqueKeysWithValues: dashboard.workspaces.map { ($0.folder, $0) })

        let explicitSnapshot = try XCTUnwrap(snapshots[explicit.lastPathComponent])
        XCTAssertEqual(explicitSnapshot.state, "developing")
        XCTAssertEqual(explicitSnapshot.lifecycle?.stage, "developing")
        XCTAssertEqual(explicitSnapshot.lifecycle?.detail, "Verify file-backed lifecycle")
        XCTAssertEqual(explicitSnapshot.lifecycle?.nextAction, "Run lifecycle scan tests")
        XCTAssertEqual(explicitSnapshot.lifecycle?.documentKey, "status")
        XCTAssertEqual(WorkspaceSummary(snapshot: explicitSnapshot).lifecycle.stage, "developing")

        let missingSnapshot = try XCTUnwrap(snapshots[missing.lastPathComponent])
        XCTAssertEqual(missingSnapshot.state, "unknown")
        XCTAssertEqual(missingSnapshot.lifecycle?.stage, "unknown")
        XCTAssertEqual(missingSnapshot.lifecycle?.progress, 0)

        let conflictSnapshot = try XCTUnwrap(snapshots[conflict.lastPathComponent])
        XCTAssertEqual(conflictSnapshot.state, "blocked")
        XCTAssertEqual(conflictSnapshot.lifecycle?.stage, "blocked")
        XCTAssertTrue(conflictSnapshot.lifecycle?.detail.contains("developing") == true)
        XCTAssertTrue(conflictSnapshot.lifecycle?.detail.contains("archived") == true)
        XCTAssertTrue(conflictSnapshot.risks.contains {
            $0.contains("生命周期状态冲突") && $0.contains("workspace.md=developing") && $0.contains("STATUS.md=archived")
        })

        let unsupportedSnapshot = try XCTUnwrap(snapshots[unsupported.lastPathComponent])
        XCTAssertEqual(unsupportedSnapshot.state, "unknown")
        XCTAssertEqual(unsupportedSnapshot.lifecycle?.stage, "unknown")
        XCTAssertTrue(unsupportedSnapshot.lifecycle?.detail.contains("waiting-for-magic") == true)
        XCTAssertTrue(unsupportedSnapshot.risks.contains {
            $0.contains("生命周期状态无法识别") && $0.contains("workspace.md=waiting-for-magic")
        })
    }

    @MainActor
    func testNativeWorkspaceRecognitionAlignsDashboardAndEnvironmentCounts() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-workspace-identity-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let docsRoot = root.appendingPathComponent("docs")
        let workspaceRecord = workspacesRoot.appendingPathComponent("2026-07-10-workspace-record")
        let statusRecord = workspacesRoot.appendingPathComponent("2026-07-10-status-record")
        let scratch = workspacesRoot.appendingPathComponent("scratch")
        let dashboardDirectory = workspacesRoot.appendingPathComponent("dashboard")
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: defaultsSuite)
        }

        for directory in [workspaceRecord, statusRecord, scratch, dashboardDirectory, sourceRoot, docsRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try "# Workspace\n".write(
            to: workspaceRecord.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Status\n\n- 当前状态: created\n".write(
            to: statusRecord.appendingPathComponent("STATUS.md"),
            atomically: true,
            encoding: .utf8
        )
        try "notes\n".write(
            to: scratch.appendingPathComponent("notes.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# Dashboard\n".write(
            to: dashboardDirectory.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )

        let dashboard = try NativeWorkspaceScanner.scan(
            workspacesRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path
        )
        let appState = AppState(
            workspaces: [],
            agentStatus: AgentStatus(title: "Loading", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path,
            defaults: defaults
        )

        await appState.checkNativeEnvironment()

        XCTAssertEqual(
            dashboard.workspaces.map(\.folder),
            ["2026-07-10-status-record", "2026-07-10-workspace-record"]
        )
        XCTAssertEqual(appState.nativeEnvironmentHealth?.workspaceCount, dashboard.workspaces.count)
    }

    @MainActor
    func testNativeEnvironmentHealthPreservesExistingWriteMarkerFiles() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-read-only-environment-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let docsRoot = root.appendingPathComponent("docs")
        let configuredRoots = [workspacesRoot, sourceRoot, docsRoot]
        let markerName = ".nexus-write-check"
        let markerContent = "user-owned diagnostic sentinel\n"
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer {
            defaults.removePersistentDomain(forName: defaultsSuite)
            try? FileManager.default.removeItem(at: root)
        }

        for directory in configuredRoots {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try markerContent.write(
                to: directory.appendingPathComponent(markerName),
                atomically: true,
                encoding: .utf8
            )
        }

        let appState = AppState(
            workspaces: [],
            agentStatus: AgentStatus(title: "Loading", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: docsRoot.path,
            defaults: defaults
        )

        await appState.checkNativeEnvironment()

        for directory in configuredRoots {
            let markerURL = directory.appendingPathComponent(markerName)
            XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
            XCTAssertEqual(try String(contentsOf: markerURL, encoding: .utf8), markerContent)
        }
    }

    func testNativeWorkspaceScannerBuildsGitRowsForWorkspaceWorktrees() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-workspace-git-\(UUID().uuidString)")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let workspace = root.appendingPathComponent("workspaces/2026-06-23-native-git")
        let sourceOrder = sourceRoot.appendingPathComponent("order")
        let worktreeOrder = workspace.appendingPathComponent("repos/order")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: sourceOrder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: worktreeOrder, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: sourceOrder)
        try runGit(["config", "user.email", "nexus@example.com"], in: sourceOrder)
        try runGit(["config", "user.name", "Nexus Test"], in: sourceOrder)
        try "demo\n".write(to: sourceOrder.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: sourceOrder)
        try runGit(["commit", "-m", "init"], in: sourceOrder)
        try runGit(["branch", "feature/native-git"], in: sourceOrder)
        try runGit(["init", "-b", "feature/native-git"], in: worktreeOrder)
        try """
        # Native Git

        - 需求名称: Native Git
        - 当前状态: developing
        """.write(to: workspace.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
        try "- 目标分支: feature/native-git\n".write(
            to: workspace.appendingPathComponent("branches.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # Services

        ## 已确认相关

        | 服务 | 源仓库 | 说明 |
        | --- | --- | --- |
        | order | `~/source-repos/order` | core |
        | cashier | `~/source-repos/cashier` | missing |

        ## 待验证范围

        | 服务 | 线索 | 说明 |
        | --- | --- | --- |
        | coupon | maybe | 待确认 |
        """.write(to: workspace.appendingPathComponent("services.md"), atomically: true, encoding: .utf8)

        let dashboard = try NativeWorkspaceScanner.scan(
            workspacesRoot: workspace.deletingLastPathComponent().path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: "/tmp/docs"
        )

        let snapshot = try XCTUnwrap(dashboard.workspaces.first)
        XCTAssertEqual(snapshot.targetBranch, "feature/native-git")
        XCTAssertEqual(snapshot.confirmedServices, ["cashier", "order"])
        XCTAssertEqual(snapshot.candidateServices, ["coupon"])
        XCTAssertEqual(snapshot.gitRows.map(\.service), ["cashier", "order"])
        XCTAssertEqual(snapshot.gitRows.first { $0.service == "order" }?.worktree.exists, true)
        XCTAssertEqual(snapshot.gitRows.first { $0.service == "order" }?.worktree.branch, "feature/native-git")
        XCTAssertEqual(snapshot.gitRows.first { $0.service == "order" }?.source.exists, true)
        XCTAssertEqual(snapshot.gitRows.first { $0.service == "order" }?.source.branch, "main")
        XCTAssertTrue(snapshot.gitRows.first { $0.service == "order" }?.source.summary.contains("target branch available: feature/native-git") ?? false)
        XCTAssertEqual(snapshot.gitRows.first { $0.service == "cashier" }?.worktree.exists, false)
        XCTAssertEqual(snapshot.gitRows.first { $0.service == "cashier" }?.source.exists, false)

        let summary = WorkspaceSummary(snapshot: snapshot)
        XCTAssertEqual(summary.services.map(\.name), ["cashier", "order"])
        XCTAssertEqual(summary.services.first { $0.name == "order" }?.worktreeExists, true)
        XCTAssertEqual(summary.services.first { $0.name == "cashier" }?.sourceExists, false)
        XCTAssertTrue(summary.risks.contains { $0.detail.contains("worktree 未创建: cashier") })
        XCTAssertTrue(summary.risks.contains { $0.detail.contains("源仓库缺失: cashier") })
    }

    func testNativeWorkspaceScannerReturnsEmptyDashboardForMissingRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-workspace-missing-\(UUID().uuidString)")

        let dashboard = try NativeWorkspaceScanner.scan(
            workspacesRoot: root.path,
            sourceReposRoot: "/tmp/source-repos",
            docsRoot: "/tmp/docs",
            now: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(dashboard.generatedAt, "1970-01-01T00:00:00Z")
        XCTAssertEqual(dashboard.workspacesRoot, root.path)
        XCTAssertTrue(dashboard.workspaces.isEmpty)
    }

    func testNativeSearchModelsGroupAndScopeResultsWithoutBridge() {
        let results = [
            SearchResult(
                workspaceFolder: "demo",
                workspaceName: "Demo",
                documentKey: "workspace",
                documentName: "Workspace",
                documentPath: "/tmp/demo/workspace.md",
                kind: "workspace",
                snippet: "Main workspace record"
            ),
            SearchResult(
                workspaceFolder: "demo",
                workspaceName: "Demo",
                documentKey: "tasks",
                documentName: "Tasks",
                documentPath: "/tmp/demo/tasks.md",
                kind: "tasks",
                snippet: "Implement native search fallback"
            ),
            SearchResult(
                workspaceFolder: "demo",
                workspaceName: "Demo",
                documentKey: "sql",
                documentName: "SQL",
                documentPath: "/tmp/demo/sql/change.sql",
                kind: "sql",
                snippet: "alter table"
            )
        ]

        let groups = groupSearchResults(results)

        XCTAssertEqual(groups.map(\.id), ["workspace", "workflow", "sql"])
        XCTAssertEqual(SearchScope.workflow.matches(results[1]), true)
        XCTAssertEqual(SearchScope.workflow.matches(results[2]), false)
        XCTAssertEqual(results[1].stableID, "demo-tasks-/tmp/demo/tasks.md")
    }

    func testNativeSearchIndexStoreBuildsWorkspaceFallbackResults() {
        let workspaces = [
            workspaceForWorkflowSummary(
                stage: "development",
                id: "native-search",
                name: "Native Search Migration",
                folder: "native-search",
                branch: "feature/native-search",
                activities: [],
                risks: [
                    RiskAlert(title: "Index bridge", detail: "search index rebuild still depends on bridge")
                ],
                tasks: [
                    WorkspaceTask(
                        id: "task-search",
                        title: "Move search fallback to Swift",
                        status: "doing",
                        detail: "Native fallback should still find workspace metadata",
                        priority: "high",
                        source: "workspace",
                        sourceEventID: nil,
                        sourceLine: 8
                    )
                ]
            ),
            workspaceForWorkflowSummary(
                stage: "development",
                id: "other",
                name: "Other Workspace"
            )
        ]

        let results = NativeSearchIndexStore.fallbackResults(matching: "fallback", in: workspaces)

        XCTAssertEqual(results.map(\.workspaceFolder), ["native-search"])
        XCTAssertEqual(results.first?.documentKey, "workspace")
        XCTAssertTrue(results.first?.snippet.contains("feature/native-search") == true)
    }

    func testNativeSearchIndexStoreBuildsSummaryFromWorkspaceDocuments() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-search-summary-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("sql"), withIntermediateDirectories: true)
        try "# Workspace\n".write(to: root.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
        try "select 1;\n".write(to: root.appendingPathComponent("sql/change.sql"), atomically: true, encoding: .utf8)
        let workspace = workspaceForWorkflowSummary(stage: "development", id: "native-index", path: root.path)

        let summary = NativeSearchIndexStore.rebuildSummary(indexPath: "~/Library/Application Support/Nexus/index.sqlite3", workspaces: [workspace])

        XCTAssertEqual(summary.workspaceCount, 1)
        XCTAssertEqual(summary.documentCount, 2)
        XCTAssertTrue(summary.path.hasSuffix("Library/Application Support/Nexus/index.sqlite3"))
    }

    func testNativeSearchIndexStoreFindsLocalDocumentContentBeforeMetadataFallback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-search-content-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try "# Tasks\n\n| Pay log backfill | 待办 | unique-native-token |\n".write(
            to: root.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        let workspace = workspaceForWorkflowSummary(stage: "development", id: "native-content", path: root.path)

        let results = NativeSearchIndexStore.searchResults(matching: "unique-native-token", in: [workspace])

        XCTAssertEqual(results.map(\.documentKey), ["tasks"])
        XCTAssertEqual(results.first?.documentName, "tasks.md")
        XCTAssertTrue(results.first?.snippet.contains("unique-native-token") == true)
    }

    func testNativeCodexSessionStoreWritesCurrentShapeAndReadsLegacyShape() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-codex-sessions-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)
        let link = CodexSessionLink(
            id: "session-1",
            title: "Implementation thread",
            url: "codex://thread/session-1",
            notes: "Native continuation",
            createdAt: "2026-06-23T05:50:00Z",
            lastOpenedAt: nil
        )

        let writtenURL = try NativeCodexSessionStore.write([link], workspacePath: workspaceURL.path)
        let storedPayload = try Data(contentsOf: writtenURL)
        let stored = try JSONDecoder().decode(CodexSessionLinkStore.self, from: storedPayload)

        XCTAssertEqual(writtenURL.lastPathComponent, NativeCodexSessionStore.fileName)
        XCTAssertEqual(stored.schemaVersion, CodexSessionLinkStore.currentSchemaVersion)
        XCTAssertEqual(NativeCodexSessionStore.load(workspacePath: workspaceURL.path), [link])

        let legacyLink = CodexSessionLink(
            id: "legacy-session",
            title: "Legacy array",
            url: "codex://thread/legacy",
            notes: "Imported from older shape",
            createdAt: "2026-06-22T00:00:00Z",
            lastOpenedAt: "2026-06-23T00:00:00Z"
        )
        let legacyPayload = try JSONEncoder().encode([legacyLink])
        try legacyPayload.write(to: writtenURL, options: .atomic)

        XCTAssertEqual(NativeCodexSessionStore.load(workspacePath: workspaceURL.path), [legacyLink])
    }

    func testNativeAuditEventStoreAppendsJsonlEvents() throws {
        let auditRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-audit-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: auditRoot)
        }

        let response = try NativeAuditEventStore.append(
            auditRoot: auditRoot.path,
            event: AuditEventInput(
                actor: "Nexus Native",
                action: "workspace.tested",
                target: "/tmp/workspace",
                summary: "Recorded a native audit event",
                metadata: ["workspaceFolder": "demo"]
            ),
            now: Date(timeIntervalSince1970: 0),
            id: "audit-1"
        )

        let payload = try String(contentsOfFile: response.path, encoding: .utf8)
        let lines = payload.split(separator: "\n")
        XCTAssertEqual(response.path, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(lines.count, 1)
        XCTAssertTrue(payload.hasSuffix("\n"))
        XCTAssertEqual(response.event.id, "audit-1")
        XCTAssertEqual(response.event.timestamp, "1970-01-01T00:00:00Z")
        XCTAssertTrue(payload.contains("\"action\":\"workspace.tested\""))
        XCTAssertTrue(payload.contains("\"workspaceFolder\":\"demo\""))
    }

    func testNativeAuditEventStoreLoadsRecentEventsNewestFirst() throws {
        let auditRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-audit-load-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: auditRoot)
        }

        _ = try NativeAuditEventStore.append(
            auditRoot: auditRoot.path,
            event: AuditEventInput(actor: "Nexus Native", action: "old.event", target: "/tmp/old", summary: "Old"),
            now: Date(timeIntervalSince1970: 1),
            id: "old"
        )
        _ = try NativeAuditEventStore.append(
            auditRoot: auditRoot.path,
            event: AuditEventInput(actor: "Nexus Native", action: "new.event", target: "/tmp/new", summary: "New"),
            now: Date(timeIntervalSince1970: 2),
            id: "new"
        )

        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 1)

        XCTAssertEqual(events.map(\.id), ["new"])
        XCTAssertEqual(try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 0), [])
    }

    func testNativeWidgetSnapshotStoreWritesApplicationAndGroupSnapshots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-widget-snapshot-\(UUID().uuidString)")
        let appSupportRoot = root.appendingPathComponent("Application Support").path
        let appGroupURL = root.appendingPathComponent("App Group")
        let fileName = "widget-snapshot.json"
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let snapshot = WidgetSnapshot(
            generatedAt: "2026-06-23T05:45:00Z",
            workspacesRoot: "/tmp/workspaces",
            activeWorkspace: "Demo",
            activeWorkspaceFolder: "demo-workspace",
            workspaceCount: 1,
            riskCount: 0,
            dirtyServiceCount: 0,
            missingWorktreeCount: 0,
            topRisks: [],
            mainStage: "开发任务 / Development",
            mainStageStatus: "下一步 / next",
            mainStageBlockerSummary: "可以继续开发。",
            mainStageNextAction: "打开任务",
            mainStageEvidence: "tasks.md",
            deepLink: "nexus://workspace/demo-workspace"
        )

        let paths = try NativeWidgetSnapshotStore.write(
            snapshot: snapshot,
            applicationSupportRoot: appSupportRoot,
            appGroupURL: appGroupURL,
            fileName: fileName
        )

        XCTAssertEqual(paths.count, 2)
        XCTAssertTrue(paths.allSatisfy { $0.hasSuffix(fileName) })
        let payloads = try paths.map { try Data(contentsOf: URL(fileURLWithPath: $0)) }
        let decodedSnapshots = try payloads.map { try JSONDecoder().decode(WidgetSnapshot.self, from: $0) }
        XCTAssertTrue(decodedSnapshots.allSatisfy { $0.mainStage == "开发任务 / Development" })
        XCTAssertEqual(payloads[0], payloads[1])
    }

    func testNativeWidgetSnapshotBuilderUsesCurrentWorkspaceState() {
        let blockedWorkspace = workspaceForWorkflowSummary(
            stage: "development",
            id: "blocked-widget",
            name: "Blocked Widget",
            folder: "blocked widget",
            risks: [
                RiskAlert(title: "SQL risk", detail: "Rollback evidence missing")
            ],
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/widget",
                    worktree: "/tmp/workspace/repos/order",
                    gitSummary: "dirty",
                    worktreeExists: true,
                    sourceExists: true
                ),
                ServiceStatus(
                    name: "cashier",
                    branch: "未创建",
                    worktree: "/tmp/workspace/repos/cashier",
                    gitSummary: "missing",
                    worktreeExists: false,
                    sourceExists: true
                )
            ]
        )
        let readyWorkspace = workspaceForWorkflowSummary(stage: "development", id: "ready-widget", name: "Ready Widget")

        let snapshot = NativeWidgetSnapshotBuilder.build(
            generatedAt: "2026-06-23T06:20:00Z",
            workspacesRoot: "/tmp/workspaces",
            workspaces: [readyWorkspace, blockedWorkspace],
            activeWorkspaceID: "blocked-widget"
        )

        XCTAssertEqual(snapshot.generatedAt, "2026-06-23T06:20:00Z")
        XCTAssertEqual(snapshot.activeWorkspace, "Blocked Widget")
        XCTAssertEqual(snapshot.activeWorkspaceFolder, "blocked widget")
        XCTAssertEqual(snapshot.workspaceCount, 2)
        XCTAssertEqual(snapshot.riskCount, 1)
        XCTAssertEqual(snapshot.dirtyServiceCount, 1)
        XCTAssertEqual(snapshot.missingWorktreeCount, 1)
        XCTAssertEqual(snapshot.topRisks, ["Blocked Widget: Rollback evidence missing"])
        XCTAssertNotNil(snapshot.mainStage)
        XCTAssertNotNil(snapshot.mainStageNextAction)
        XCTAssertEqual(snapshot.deepLink, "nexus://workspace/blocked%20widget")
    }

    @MainActor
    func testAppStateMergesNativeAuditEventsIntoWorkspaceActivities() {
        let workspace = workspaceForWorkflowSummary(
            stage: "development",
            id: "demo-id",
            name: "Demo",
            folder: "demo-workspace",
            activities: [
                ActivityEvent(time: "08:00", title: "Bridge activity", detail: "From scan")
            ]
        )
        let events = [
            AuditEvent(
                id: "matched-new",
                timestamp: "2026-06-23T05:40:00Z",
                actor: "Nexus Native",
                action: "workspace.deeplink.copied",
                target: "nexus://workspace/demo-workspace",
                summary: "Copied workspace Nexus deep link",
                metadata: ["workspaceFolder": "demo-workspace"]
            ),
            AuditEvent(
                id: "unmatched",
                timestamp: "2026-06-23T05:41:00Z",
                actor: "Nexus Native",
                action: "workspace.unmatched",
                target: "/tmp/other",
                summary: "Other workspace",
                metadata: ["workspaceFolder": "other"]
            )
        ]

        let enriched = AppState.workspaces([workspace], applyingNativeAuditEvents: events)

        XCTAssertEqual(enriched.first?.activities.first?.title, "工作区链接已复制 / Deep link copied")
        XCTAssertEqual(enriched.first?.activities.first?.detail, "Nexus Native · Copied workspace Nexus deep link")
        let activityTitles = enriched.first?.activities.map { $0.title } ?? []
        XCTAssertFalse(activityTitles.contains("workspace unmatched"))
        XCTAssertEqual(enriched.first?.activities.count, 2)
    }

    func testNativeDistributionReadinessBlocksUntilInstallWidgetLegacyAndReleaseAreNative() {
        let root = "/repo"
        let files: Set<String> = [
            "\(root)/native/Nexus/Package.swift",
            "\(root)/widget/NexusWidget/NexusWidget.swift",
            "\(root)/docs/legacy-retirement-audit.md",
            "\(root)/docs/distribution.md",
            "\(root)/docs/release-process.md",
            "\(root)/docs/native-release-notes-and-updater.md",
            "\(root)/native/Nexus/Sources/NexusApp/AppState.swift",
            "\(root)/native/Nexus/Sources/NexusApp/Views/RootView.swift",
            "\(root)/native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift",
            "\(root)/package.json",
            "\(root)/.github/workflows/ci.yml",
            "\(root)/.github/workflows/release.yml"
        ]
        let directories: Set<String> = ["\(root)/src", "\(root)/src-tauri", "\(root)/crates"]
        let evidence = NativeDistributionReadinessEvidence.resolve(
            repositoryRoot: root,
            m1Ready: true,
            m2Ready: false,
            realLifecycleProven: false,
            fileExists: { files.contains($0) },
            directoryExists: { directories.contains($0) },
            fileContains: { path, needle in
                path.hasSuffix("ci.yml") && needle == "swift test"
                    || path.hasSuffix("release.yml") && needle == "tauri"
                    || path.hasSuffix("release-process.md") && needle == "Tauri"
                    || path.hasSuffix("legacy-retirement-audit.md") && needle == "Native Deletion Order"
                    || path.hasSuffix("legacy-retirement-audit.md") && needle == "Current Legacy Surfaces"
            }
        )

        XCTAssertEqual(evidence.status, .blocked)
        XCTAssertEqual(evidence.checks.map(\.requirement), NativeDistributionRequirement.allCases)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .installTarget }?.status, .blocked)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .widgetExtension }?.status, .blocked)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .legacyDeletion }?.status, .blocked)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .releaseReadiness }?.status, .blocked)
        XCTAssertEqual(evidence.readinessSummary, "0/4 Ready checks")
        XCTAssertEqual(evidence.legacyDeletionConditions.map(\.condition), NativeLegacyDeletionCondition.allCases)
        XCTAssertEqual(evidence.legacyDeletionConditions.first { $0.condition == .nativeLocalCore }?.status, .blocked)
        XCTAssertEqual(evidence.legacyDeletionConditions.first { $0.condition == .realLifecycleProof }?.status, .blocked)
        XCTAssertEqual(evidence.legacyDeletionConditions.first { $0.condition == .releaseDocsNativeOnly }?.status, .blocked)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .legacyDeletion }?.detail.contains("M2 Native Local Core is not ready") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .legacyDeletion }?.detail.contains("No real archived workspace lifecycle proof") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .legacyDeletion }?.detail.contains("Next step: follow the Native deletion order") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .legacyDeletion }?.evidence.contains("\(root)/src-tauri") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .releaseReadiness }?.detail.contains("Release workflow does not build a Native app artifact") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .releaseReadiness }?.detail.contains("Release workflow does not verify Native app, DMG, checksum, and manifest outputs") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .releaseReadiness }?.detail.contains("Release notes gate is missing or incomplete") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .releaseReadiness }?.detail.contains("Updater policy gate is missing or incomplete") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .releaseReadiness }?.detail.contains("Release manifest metadata is missing or incomplete") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .releaseReadiness }?.detail.contains("Release docs or workflows still point to Tauri artifacts") == true)
        XCTAssertTrue(evidence.reason.contains("M3"))
    }

    func testNativeDistributionReadinessTracksUnsignedNativeReleaseWorkflowBeforeInstallTargetExists() {
        let root = "/repo"
        let files: Set<String> = [
            "\(root)/native/Nexus/Package.swift",
            "\(root)/native/Nexus/Scripts/package-dmg.sh",
            "\(root)/widget/NexusWidget/NexusWidget.swift",
            "\(root)/docs/legacy-retirement-audit.md",
            "\(root)/docs/distribution.md",
            "\(root)/docs/release-process.md",
            "\(root)/.github/workflows/ci.yml",
            "\(root)/.github/workflows/release.yml"
        ]
        let directories: Set<String> = ["\(root)/src", "\(root)/src-tauri", "\(root)/crates"]
        let evidence = NativeDistributionReadinessEvidence.resolve(
            repositoryRoot: root,
            m1Ready: true,
            m2Ready: true,
            realLifecycleProven: true,
            fileExists: { files.contains($0) },
            directoryExists: { directories.contains($0) },
            fileContains: { path, needle in
                switch needle {
                case "swift test",
                     "npm run native:build",
                     "npm run widget:typecheck":
                    return path.hasSuffix("ci.yml")
                        || path.hasSuffix("package.json")
                case "testNativeStoresCanProveEndToEndWorkspaceLifecycle",
                     "testNativeWorkspaceCreationStoreWritesStandardWorkspaceAndAudit":
                    return path.hasSuffix("ModelBehaviorTests.swift")
                case "native/Nexus", "NexusNative", "Swift":
                    return path.hasSuffix("release.yml")
                        || path.hasSuffix("distribution.md")
                        || path.hasSuffix("release-process.md")
                case "package-dmg.sh", ".dmg":
                    return path.hasSuffix("release.yml")
                case "Native Deletion Order", "Current Legacy Surfaces":
                    return path.hasSuffix("legacy-retirement-audit.md")
                default:
                    return false
                }
            }
        )

        let releaseReadiness = evidence.checks.first { $0.requirement == .releaseReadiness }
        XCTAssertEqual(releaseReadiness?.status, .blocked)
        XCTAssertFalse(releaseReadiness?.detail.contains("Release workflow does not build a Native app artifact.") == true)
        XCTAssertFalse(releaseReadiness?.detail.contains("Release workflow does not package Native DMG artifacts.") == true)
        XCTAssertTrue(releaseReadiness?.detail.contains("Release workflow does not publish Native DMG checksums.") == true)
        XCTAssertTrue(releaseReadiness?.detail.contains("Release workflow does not publish Native update manifest metadata.") == true)
        XCTAssertTrue(releaseReadiness?.detail.contains("Release workflow does not verify Native app, DMG, checksum, and manifest outputs.") == true)
        XCTAssertTrue(releaseReadiness?.detail.contains("Release workflow does not sign and notarize Native artifacts.") == true)
        XCTAssertTrue(releaseReadiness?.detail.contains("Release workflow does not verify Native codesign, Gatekeeper, and stapled notarization evidence.") == true)
        XCTAssertTrue(releaseReadiness?.detail.contains("Release workflow does not import Apple Developer signing certificates.") == true)
        XCTAssertTrue(releaseReadiness?.detail.contains("Release notes gate is missing or incomplete") == true)
        XCTAssertTrue(releaseReadiness?.detail.contains("Updater policy gate is missing or incomplete") == true)
        XCTAssertTrue(releaseReadiness?.detail.contains("Release manifest metadata is missing or incomplete") == true)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .installTarget }?.status, .blocked)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .widgetExtension }?.status, .blocked)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .legacyDeletion }?.status, .blocked)
        XCTAssertEqual(evidence.readinessSummary, "0/4 Ready checks")
    }

    func testNativeReleasePolicyEvidenceRequiresReleaseNotesUpdaterAndManifestPolicy() {
        let root = "/repo"
        let files: Set<String> = [
            "\(root)/docs/native-release-notes-and-updater.md",
            "\(root)/docs/release-process.md",
            "\(root)/docs/distribution.md",
            "\(root)/native/Nexus/Scripts/generate-release-manifest.sh",
            "\(root)/native/Nexus/Scripts/verify-release-bundle.sh",
            "\(root)/native/Nexus/Scripts/verify-release-notes.sh",
            "\(root)/.github/workflows/release.yml"
        ]
        let incomplete = NativeReleasePolicyEvidence.resolve(
            repositoryRoot: root,
            fileExists: { files.contains($0) },
            fileContains: { path, needle in
                path.hasSuffix("native-release-notes-and-updater.md") && needle == "Release Notes Gate"
            }
        )

        XCTAssertEqual(incomplete.status, .blocked)
        XCTAssertEqual(incomplete.checks.map(\.requirement), NativeReleasePolicyRequirement.allCases)
        XCTAssertTrue(incomplete.blockerDetails.contains { $0.contains("Updater policy gate is missing or incomplete") })
        XCTAssertTrue(incomplete.blockerDetails.contains { $0.contains("Settings update channel gate is missing or incomplete") })
        XCTAssertTrue(incomplete.blockerDetails.contains { $0.contains("Release manifest metadata is missing or incomplete") })
        XCTAssertTrue(incomplete.blockerDetails.contains { $0.contains("Public-release blocker policy is missing or incomplete") })

        let ready = NativeReleasePolicyEvidence.resolve(
            repositoryRoot: root,
            fileExists: {
                files.contains($0)
                    || $0 == "\(root)/native/Nexus/Sources/NexusApp/AppState.swift"
                    || $0 == "\(root)/native/Nexus/Sources/NexusApp/Views/RootView.swift"
            },
            fileContains: { path, needle in
                switch needle {
                case "Release Notes Gate",
                     "version/tag",
                     "native artifact names",
                     "checksums",
                     "signing/notarization status",
                     "migration and rollback notes",
                     "known blockers",
                     "release manifest metadata",
                     "manifest SHA-256 values",
                     "metadata is requested remotely",
                     "Updater Gate",
                     "Automatic updates disabled",
                     "Do not enable automatic updates",
                     "Settings exposes a user-visible update channel",
                     "must not silently check for, download, or install updates":
                    return path.hasSuffix("native-release-notes-and-updater.md")
                case "validation summary":
                    return path.hasSuffix("native-release-notes-and-updater.md")
                        || path.hasSuffix("verify-release-notes.sh")
                case "nexus-native-release-manifest.json":
                    return path.hasSuffix("generate-release-manifest.sh")
                        || path.hasSuffix("AppState.swift")
                        || path.hasSuffix("verify-release-notes.sh")
                case "--notes",
                     "--tag",
                     "--assets-dir",
                     "--manifest",
                     "nexus-native-*.dmg",
                     ".dmg.sha256",
                     "manifest SHA-256",
                     "checksum sidecar",
                     "Release manifest sha256 must match checksum sidecar",
                     "metadata requested remotely",
                     "Release manifest releaseTag must match --tag",
                     "Release manifest updateChannel must be manual-github-release",
                     "Release manifest automaticUpdatesEnabled must be false":
                    return path.hasSuffix("verify-release-notes.sh")
                        || path.hasSuffix("verify-release-bundle.sh")
                case "signing/notarization",
                     "known blocker",
                     "migration",
                     "rollback":
                    return path.hasSuffix("verify-release-notes.sh")
                        || path.hasSuffix("native-release-notes-and-updater.md")
                case "verify-release-notes.sh":
                    return path.hasSuffix("release.yml")
                case "struct NativeUpdateChannelStatus",
                     "automaticUpdatesEnabled: false",
                     "Manual download",
                     "No silent update checks, downloads, or installs":
                    return path.hasSuffix("AppState.swift")
                case "NativeUpdateChannelStatusView",
                     "status.checkMode",
                     "status.automaticUpdatesLabel",
                     "status.manifestFilename",
                     "manual-github-release keeps automaticUpdatesEnabled=false":
                    return path.hasSuffix("RootView.swift")
                case "manual-github-release",
                     "automaticUpdatesEnabled",
                     "\"automaticUpdatesEnabled\": False",
                     "\"updateChannel\": \"manual-github-release\"",
                     "does not enable automatic updates":
                    return path.hasSuffix("generate-release-manifest.sh")
                        || path.hasSuffix("verify-release-bundle.sh")
                        || path.hasSuffix("AppState.swift")
                case "sidecar_checksums",
                     "updateChannel",
                     "Release manifest schemaVersion must be 1",
                     "Release manifest app must be Nexus",
                     "Release manifest sizeBytes must match DMG size",
                     "sizeBytes":
                    return path.hasSuffix("verify-release-bundle.sh")
                case "signed WidgetKit",
                     "real-credential notarized release run",
                     "updater signing keys",
                     "appcast metadata",
                     "rollback instructions":
                    return path.hasSuffix("native-release-notes-and-updater.md")
                        || path.hasSuffix("release-process.md")
                        || path.hasSuffix("distribution.md")
                default:
                    return false
                }
            }
        )

        XCTAssertTrue(ready.ready, ready.reason)
        XCTAssertTrue(ready.checks.allSatisfy { $0.status == .ready })
    }

    @MainActor
    func testNativeUpdateChannelStatusKeepsManualManifestAndNoSilentUpdates() {
        let appState = appStateForAutomationTests(workspaces: [])
        let status = appState.nativeUpdateChannelStatus()

        XCTAssertEqual(status.channelID, "manual-github-release")
        XCTAssertEqual(status.channelLabel, "Manual GitHub Release")
        XCTAssertFalse(status.automaticUpdatesEnabled)
        XCTAssertEqual(status.automaticUpdatesLabel, "Automatic updates disabled")
        XCTAssertEqual(status.manifestFilename, "nexus-native-release-manifest.json")
        XCTAssertEqual(status.checkMode, "Manual download")
        XCTAssertTrue(status.remoteMetadataPolicy.contains("No silent update checks"))
    }

    func testNativeDistributionReadinessAcceptsSwiftPMAppBundleEvidence() {
        let root = "/repo"
        let files: Set<String> = [
            "\(root)/native/Nexus/Package.swift",
            "\(root)/native/Nexus/Scripts/build-app-bundle.sh",
            "\(root)/native/Nexus/Packaging/Info.plist",
            "\(root)/widget/NexusWidget/NexusWidget.swift",
            "\(root)/docs/legacy-retirement-audit.md",
            "\(root)/docs/distribution.md",
            "\(root)/docs/release-process.md",
            "\(root)/.github/workflows/ci.yml",
            "\(root)/.github/workflows/release.yml"
        ]
        let evidence = NativeDistributionReadinessEvidence.resolve(
            repositoryRoot: root,
            m1Ready: true,
            m2Ready: true,
            realLifecycleProven: true,
            fileExists: { files.contains($0) },
            directoryExists: { _ in false },
            fileContains: { path, needle in
                switch needle {
                case "swift test":
                    return path.hasSuffix("ci.yml")
                case "native/Nexus", "NexusNative", "Swift":
                    return path.hasSuffix("release.yml")
                        || path.hasSuffix("distribution.md")
                        || path.hasSuffix("release-process.md")
                case "package-dmg.sh", ".dmg":
                    return path.hasSuffix("release.yml")
                case "Native Deletion Order", "Current Legacy Surfaces":
                    return path.hasSuffix("legacy-retirement-audit.md")
                default:
                    return false
                }
            }
        )

        let installTarget = evidence.checks.first { $0.requirement == .installTarget }
        XCTAssertEqual(installTarget?.status, .ready)
        XCTAssertTrue(installTarget?.detail.contains("installable app bundle path") == true)
        XCTAssertTrue(installTarget?.evidence.contains("\(root)/native/Nexus/Scripts/build-app-bundle.sh") == true)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .widgetExtension }?.status, .blocked)
    }

    func testNativeDistributionReadinessRequiresWidgetTargetMetadata() {
        let root = "/repo"
        let readyFiles: Set<String> = [
            "\(root)/native/Nexus/Package.swift",
            "\(root)/widget/NexusWidget/NexusWidget.swift",
            "\(root)/native/NexusWidget/Sources/NexusWidget/NexusWidget.swift",
            "\(root)/native/NexusWidget/Info.plist",
            "\(root)/native/NexusWidget/NexusWidget.entitlements",
            "\(root)/native/Nexus/Scripts/build-app-bundle.sh",
            "\(root)/native/Nexus/Scripts/verify-release-bundle.sh",
            "\(root)/docs/legacy-retirement-audit.md",
            "\(root)/docs/distribution.md",
            "\(root)/docs/release-process.md",
            "\(root)/docs/native-release-notes-and-updater.md",
            "\(root)/native/Nexus/Sources/NexusApp/AppState.swift",
            "\(root)/native/Nexus/Sources/NexusApp/Views/RootView.swift",
            "\(root)/native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift",
            "\(root)/package.json",
            "\(root)/.github/workflows/ci.yml",
            "\(root)/.github/workflows/release.yml"
        ]
        let missingEntitlements = readyFiles.subtracting(["\(root)/native/NexusWidget/NexusWidget.entitlements"])
        let missingEmbeddingContract = readyFiles.subtracting([
            "\(root)/native/Nexus/Scripts/build-app-bundle.sh",
            "\(root)/native/Nexus/Scripts/verify-release-bundle.sh"
        ])
        func evidence(files: Set<String>) -> NativeDistributionReadinessEvidence {
            NativeDistributionReadinessEvidence.resolve(
                repositoryRoot: root,
                m1Ready: true,
                m2Ready: true,
                realLifecycleProven: true,
                fileExists: { files.contains($0) },
                directoryExists: { $0 == "\(root)/native/NexusWidget" },
                fileContains: { path, needle in
                    switch needle {
                    case "com.apple.widgetkit-extension":
                        return path.hasSuffix("Info.plist")
                            || path.hasSuffix("verify-release-bundle.sh")
                    case "group.com.ks.nexus":
                        return path.hasSuffix("NexusWidget.entitlements")
                    case "Native Deletion Order", "Current Legacy Surfaces":
                        return path.hasSuffix("legacy-retirement-audit.md")
                    case "swift test":
                        return path.hasSuffix("ci.yml")
                    case "native/Nexus", "NexusNative", "Swift":
                        return path.hasSuffix("release.yml")
                            || path.hasSuffix("distribution.md")
                            || path.hasSuffix("release-process.md")
                    case "--widget-extension", "Contents/PlugIns", "NexusWidget.appex":
                        return path.hasSuffix("build-app-bundle.sh")
                    case "--require-widget", "Contents/PlugIns/NexusWidget.appex":
                        return path.hasSuffix("verify-release-bundle.sh")
                    default:
                        return false
                    }
                }
            )
        }

        XCTAssertEqual(evidence(files: missingEntitlements).checks.first { $0.requirement == .widgetExtension }?.status, .blocked)
        XCTAssertEqual(evidence(files: missingEmbeddingContract).checks.first { $0.requirement == .widgetExtension }?.status, .blocked)
        let widgetTarget = evidence(files: readyFiles).checks.first { $0.requirement == .widgetExtension }
        XCTAssertEqual(widgetTarget?.status, .ready)
        XCTAssertTrue(widgetTarget?.detail.contains("app-bundle embedding") == true)
    }

    func testNativeDistributionReadinessCanPassAfterNativeInstallAndDeletionProof() {
        let root = "/repo"
        let files: Set<String> = [
            "\(root)/native/Nexus/Package.swift",
            "\(root)/native/Nexus/Nexus.xcodeproj/project.pbxproj",
            "\(root)/native/Nexus/Scripts/build-app-bundle.sh",
            "\(root)/native/Nexus/Scripts/package-dmg.sh",
            "\(root)/native/Nexus/Scripts/sign-and-notarize.sh",
            "\(root)/native/Nexus/Scripts/verify-signing-notarization.sh",
            "\(root)/native/Nexus/Scripts/import-apple-certificate.sh",
            "\(root)/native/Nexus/Scripts/generate-release-manifest.sh",
            "\(root)/native/Nexus/Scripts/verify-release-bundle.sh",
            "\(root)/native/Nexus/Scripts/verify-release-notes.sh",
            "\(root)/widget/NexusWidget/NexusWidget.swift",
            "\(root)/native/NexusWidget/Sources/NexusWidget/NexusWidget.swift",
            "\(root)/native/NexusWidget/Info.plist",
            "\(root)/native/NexusWidget/NexusWidget.entitlements",
            "\(root)/docs/legacy-retirement-audit.md",
            "\(root)/docs/distribution.md",
            "\(root)/docs/release-process.md",
            "\(root)/docs/native-release-notes-and-updater.md",
            "\(root)/native/Nexus/Sources/NexusApp/AppState.swift",
            "\(root)/native/Nexus/Sources/NexusApp/Views/RootView.swift",
            "\(root)/native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift",
            "\(root)/package.json",
            "\(root)/.github/workflows/ci.yml",
            "\(root)/.github/workflows/release.yml"
        ]
        let directories: Set<String> = ["\(root)/native/NexusWidget"]
        let evidence = NativeDistributionReadinessEvidence.resolve(
            repositoryRoot: root,
            m1Ready: true,
            m2Ready: true,
            realLifecycleProven: true,
            fileExists: { files.contains($0) },
            directoryExists: { directories.contains($0) },
            fileContains: { path, needle in
                switch needle {
                case "swift test",
                     "npm run native:build",
                     "npm run widget:typecheck":
                    return path.hasSuffix("ci.yml")
                        || path.hasSuffix("package.json")
                case "testNativeStoresCanProveEndToEndWorkspaceLifecycle",
                     "testNativeWorkspaceCreationStoreWritesStandardWorkspaceAndAudit":
                    return path.hasSuffix("ModelBehaviorTests.swift")
                case "native/Nexus", "NexusNative", "Swift":
                    return path.hasSuffix("release.yml")
                        || path.hasSuffix("distribution.md")
                        || path.hasSuffix("release-process.md")
                case "native:build":
                    return path.hasSuffix("release.yml")
                case "package-dmg.sh", ".dmg", "sign-and-notarize.sh", "shasum -a 256", "*.sha256", "generate-release-manifest.sh", "verify-release-bundle.sh", "--app dist/Nexus.app", "--assets-dir release-assets", "import-apple-certificate.sh", "APPLE_CERTIFICATE", "APPLE_CERTIFICATE_PASSWORD":
                    return path.hasSuffix("release.yml")
                case "verify-signing-notarization.sh":
                    return path.hasSuffix("release.yml")
                case "--require-app-signature", "--require-notarization":
                    return path.hasSuffix("release.yml")
                        || path.hasSuffix("verify-signing-notarization.sh")
                case "--require-dmg-signature":
                    return path.hasSuffix("verify-signing-notarization.sh")
                case "codesign --verify", "spctl --assess", "stapler validate":
                    return path.hasSuffix("verify-signing-notarization.sh")
                case ".dmg.sha256":
                    return path.hasSuffix("release.yml")
                        || path.hasSuffix("verify-release-notes.sh")
                case "verify-release-notes.sh":
                    return path.hasSuffix("release.yml")
                case "--notes",
                     "--tag",
                     "--assets-dir",
                     "--manifest",
                     "nexus-native-*.dmg",
                     "manifest SHA-256",
                     "checksum sidecar",
                     "Release manifest sha256 must match checksum sidecar",
                     "metadata requested remotely",
                     "Release manifest releaseTag must match --tag",
                     "Release manifest updateChannel must be manual-github-release",
                     "Release manifest automaticUpdatesEnabled must be false":
                    return path.hasSuffix("verify-release-notes.sh")
                        || path.hasSuffix("verify-release-bundle.sh")
                case "signing/notarization",
                     "known blocker",
                     "migration",
                     "rollback":
                    return path.hasSuffix("verify-release-notes.sh")
                        || path.hasSuffix("native-release-notes-and-updater.md")
                case "nexus-native-release-manifest.json":
                    return path.hasSuffix("release.yml")
                        || path.hasSuffix("generate-release-manifest.sh")
                        || path.hasSuffix("verify-release-bundle.sh")
                        || path.hasSuffix("AppState.swift")
                        || path.hasSuffix("verify-release-notes.sh")
                case "validation summary":
                    return path.hasSuffix("native-release-notes-and-updater.md")
                        || path.hasSuffix("verify-release-notes.sh")
                case "Contents/Info.plist":
                    return path.hasSuffix("verify-release-bundle.sh")
                case "--widget-extension", "Contents/PlugIns", "NexusWidget.appex":
                    return path.hasSuffix("build-app-bundle.sh")
                case "--require-widget", "Contents/PlugIns/NexusWidget.appex":
                    return path.hasSuffix("verify-release-bundle.sh")
                case "codesign", "notarytool":
                    return path.hasSuffix("sign-and-notarize.sh")
                case "security import", "security create-keychain", "set-key-partition-list":
                    return path.hasSuffix("import-apple-certificate.sh")
                case "manual-github-release",
                     "automaticUpdatesEnabled",
                     "\"automaticUpdatesEnabled\": False",
                     "\"updateChannel\": \"manual-github-release\"",
                     "does not enable automatic updates":
                    return path.hasSuffix("generate-release-manifest.sh")
                        || path.hasSuffix("verify-release-bundle.sh")
                        || path.hasSuffix("AppState.swift")
                case "sidecar_checksums",
                     "updateChannel",
                     "Release manifest schemaVersion must be 1",
                     "Release manifest app must be Nexus",
                     "Release manifest sizeBytes must match DMG size",
                     "sizeBytes":
                    return path.hasSuffix("verify-release-bundle.sh")
                case "struct NativeUpdateChannelStatus",
                     "automaticUpdatesEnabled: false",
                     "Manual download",
                     "No silent update checks, downloads, or installs":
                    return path.hasSuffix("AppState.swift")
                case "NativeUpdateChannelStatusView",
                     "status.checkMode",
                     "status.automaticUpdatesLabel",
                     "status.manifestFilename",
                     "manual-github-release keeps automaticUpdatesEnabled=false":
                    return path.hasSuffix("RootView.swift")
                case "com.apple.widgetkit-extension":
                    return path.hasSuffix("Info.plist")
                        || path.hasSuffix("verify-release-bundle.sh")
                case "group.com.ks.nexus":
                    return path.hasSuffix("NexusWidget.entitlements")
                case "Native Deletion Order", "Current Legacy Surfaces":
                    return path.hasSuffix("legacy-retirement-audit.md")
                case "Release Notes Gate", "version/tag", "native artifact names", "checksums", "signing/notarization status", "migration and rollback notes", "known blockers", "release manifest metadata", "manifest SHA-256 values", "metadata is requested remotely":
                    return path.hasSuffix("native-release-notes-and-updater.md")
                case "Updater Gate", "Automatic updates disabled", "Do not enable automatic updates", "Settings exposes a user-visible update channel", "must not silently check for, download, or install updates":
                    return path.hasSuffix("native-release-notes-and-updater.md")
                case "signed WidgetKit", "real-credential notarized release run", "updater signing keys", "appcast metadata", "rollback instructions":
                    return path.hasSuffix("native-release-notes-and-updater.md")
                        || path.hasSuffix("release-process.md")
                        || path.hasSuffix("distribution.md")
                default:
                    return false
                }
            }
        )

        let diagnostic = evidence.checks
            .map { "\($0.requirement.rawValue): \($0.status) \($0.detail)" }
            .joined(separator: "\n")
        XCTAssertTrue(evidence.ready, diagnostic)
        XCTAssertEqual(evidence.status, .ready, diagnostic)
        XCTAssertEqual(evidence.readinessSummary, "4/4 Ready checks", diagnostic)
        XCTAssertTrue(evidence.checks.allSatisfy { $0.status == .ready }, diagnostic)
        XCTAssertEqual(evidence.legacyDeletionConditions.map(\.condition), NativeLegacyDeletionCondition.allCases)
        XCTAssertTrue(evidence.legacyDeletionConditions.allSatisfy { $0.status == .ready }, diagnostic)
    }

    @MainActor
    func testAppStateExposesNativeLocalCoreEvidenceFromBridgeMode() {
        let appState = appStateForAutomationTests(workspaces: [])

        let evidence = appState.nativeLocalCoreEvidence()

        XCTAssertEqual(evidence.status, .ready)
        XCTAssertEqual(evidence.domains.map(\.domain), NativeLocalCoreDomain.allCases)
        XCTAssertEqual(evidence.migrationSummary, "11/11 Native domains")
        XCTAssertEqual(
            evidence.domains.filter { $0.status == .ready }.map(\.domain),
            [
                .workspaceScanning,
                .documentInventory,
                .demandIntake,
                .readiness,
                .confirmedWrites,
                .gitWorktreeStatus,
                .audit,
                .settings,
                .widgetSnapshot,
                .codexSessions,
                .searchIndex
            ]
        )
        XCTAssertTrue(evidence.domains.filter { $0.status == .review }.isEmpty)
        XCTAssertTrue(evidence.reason.contains("已覆盖工作区扫描"))
    }

    @MainActor
    func testAppStateExposesNativeDistributionReadinessEvidence() {
        let appState = appStateForAutomationTests(workspaces: [])

        let evidence = appState.nativeDistributionReadinessEvidence(repositoryRoot: "/missing")

        XCTAssertEqual(evidence.checks.map(\.requirement), NativeDistributionRequirement.allCases)
        XCTAssertEqual(evidence.status, .blocked)
    }

    @MainActor
    func testAppStateDerivesNativeLifecycleProofFromArchivedWorkspace() {
        let archived = workspaceForWorkflowSummary(
            stage: "archived",
            id: "archived-proof",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/workflow-summary",
                    worktree: "ready",
                    gitSummary: "clean",
                    worktreeExists: true,
                    sourceExists: true
                )
            ],
            tasks: [
                WorkspaceTask(
                    id: "done-task",
                    title: "Done",
                    status: "done",
                    detail: "Done",
                    priority: "normal",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: nil
                )
            ]
        )
        let blocked = workspaceForWorkflowSummary(
            stage: "archived",
            id: "archived-blocked",
            risks: [RiskAlert(title: "Risk", detail: "Open risk")]
        )

        let proofEvents = lifecycleProofAuditEvents(for: archived)
        let proof = NativeLifecycleProofEvidence.resolve(workspace: archived, auditEvents: proofEvents)

        XCTAssertFalse(appStateForAutomationTests(workspaces: [archived]).nativeLifecycleProofAvailable(auditEvents: []))
        XCTAssertTrue(appStateForAutomationTests(workspaces: [archived]).nativeLifecycleProofAvailable(auditEvents: proofEvents))
        XCTAssertFalse(appStateForAutomationTests(workspaces: [archived]).nativeLifecycleProofBundleAvailable(auditEvents: proofEvents))
        XCTAssertTrue(proof.ready)
        XCTAssertEqual(proof.missingActions, [])
        XCTAssertEqual(proof.orderedActions, NativeLifecycleProofEvidence.requiredAuditActions)
        XCTAssertFalse(appStateForAutomationTests(workspaces: [blocked]).nativeLifecycleProofAvailable())
        XCTAssertFalse(appStateForAutomationTests(workspaces: []).nativeLifecycleProofAvailable())

        let missingDemand = proofEvents.filter { $0.action != "demand_intake.initialized" }
        let incomplete = NativeLifecycleProofEvidence.resolve(workspace: archived, auditEvents: missingDemand)
        XCTAssertFalse(incomplete.ready)
        XCTAssertTrue(incomplete.missingActions.contains("demand_intake.initialized"))

        let outOfOrderActions = [
            "workspace.created",
            "demand_intake.initialized",
            "worktree_setup.executed",
            "scope.freeze_confirmed",
            "demand_tasks.transferred",
            "workspace_task.updated",
            "delivery_record.snapshot_appended",
            "archive_checklist.snapshot_appended",
            "workspace_lifecycle.updated"
        ]
        let outOfOrderEvents = Array(outOfOrderActions.enumerated().map { offset, action in
            AuditEvent(
                id: "out-of-order-proof-\(offset)",
                timestamp: String(format: "2026-06-30T01:%02d:00Z", offset),
                actor: "Nexus Test",
                action: action,
                target: archived.path,
                summary: "Out-of-order lifecycle proof \(action) for \(archived.folder)",
                metadata: action == "workspace_lifecycle.updated"
                    ? ["workspace": archived.path, "state": "archived"]
                    : ["workspace": archived.path]
            )
        }.reversed())
        let outOfOrderProof = NativeLifecycleProofEvidence.resolve(
            workspace: archived,
            auditEvents: outOfOrderEvents
        )
        XCTAssertFalse(outOfOrderProof.ready)
        XCTAssertEqual(outOfOrderProof.missingActions, [])
        XCTAssertTrue(outOfOrderProof.detail.contains("audit order is incomplete"))

        let developingLifecycle = proofEvents.map { event in
            guard event.action == "workspace_lifecycle.updated" else { return event }
            return AuditEvent(
                id: event.id,
                timestamp: event.timestamp,
                actor: event.actor,
                action: event.action,
                target: event.target,
                summary: event.summary,
                metadata: ["workspace": archived.path, "state": "developing"]
            )
        }
        let invalidArchiveProof = NativeLifecycleProofEvidence.resolve(workspace: archived, auditEvents: developingLifecycle)
        XCTAssertFalse(invalidArchiveProof.ready)
        XCTAssertFalse(invalidArchiveProof.orderedActions.contains("workspace_lifecycle.updated"))
        XCTAssertTrue(invalidArchiveProof.missingActions.contains("workspace_lifecycle.updated:archived"))
    }

    func testWidgetSnapshotCarriesMainStageAnswerCompatibly() throws {
        let snapshot = WidgetSnapshot(
            generatedAt: "2026-06-23T05:00:00Z",
            workspacesRoot: "/tmp/workspaces",
            activeWorkspace: "Delivery Workspace",
            activeWorkspaceFolder: "2026-06-23-delivery",
            workspaceCount: 1,
            riskCount: 0,
            dirtyServiceCount: 0,
            missingWorktreeCount: 0,
            topRisks: [],
            mainStage: "交付检查 / Delivery",
            mainStageStatus: "阻塞 / block",
            mainStageBlockerSummary: "阻塞：SQL rollback evidence is missing.",
            mainStageNextAction: "查看 SQL",
            mainStageEvidence: "sql/release.sql",
            deepLink: "nexus://workspace/2026-06-23-delivery"
        )

        let encoded = try JSONEncoder().encode(snapshot)
        let encodedText = String(decoding: encoded, as: UTF8.self)

        XCTAssertTrue(encodedText.contains("mainStage"))
        XCTAssertTrue(encodedText.contains("mainStageEvidence"))
        XCTAssertEqual(snapshot.mainStageLine, "交付检查 / Delivery · 查看 SQL · sql/release.sql")

        let legacyJSON = """
        {
          "generatedAt": "2026-06-23T05:00:00Z",
          "workspacesRoot": "/tmp/workspaces",
          "activeWorkspace": "Delivery Workspace",
          "activeWorkspaceFolder": "2026-06-23-delivery",
          "workspaceCount": 1,
          "riskCount": 0,
          "dirtyServiceCount": 0,
          "missingWorktreeCount": 0,
          "topRisks": [],
          "deepLink": "nexus://workspace/2026-06-23-delivery"
        }
        """

        let decodedLegacy = try JSONDecoder().decode(WidgetSnapshot.self, from: Data(legacyJSON.utf8))
        XCTAssertNil(decodedLegacy.mainStage)
        XCTAssertNil(decodedLegacy.mainStageEvidence)
        XCTAssertNil(decodedLegacy.mainStageLine)
    }

    func testMainWorkflowAcceptanceEvidenceBlocksMissingStagesAndEvidence() {
        let stages = [
            WorkspaceMainStage(
                id: .created,
                status: .next,
                title: "工作区已建档",
                reason: "Created stage is present.",
                primaryActionLabel: "开始预检",
                primaryActionSystemImage: "folder.badge.plus",
                primaryAction: .demandIntake,
                evidence: ["workspace.md"],
                nextStageAllowed: false
            ),
            WorkspaceMainStage(
                id: .demandIntake,
                status: .blocked,
                title: "完成需求预检",
                reason: "Demand intake still needs evidence.",
                primaryActionLabel: "",
                primaryActionSystemImage: "text.badge.checkmark",
                primaryAction: .demandIntake,
                evidence: [],
                nextStageAllowed: false
            )
        ]

        let acceptance = MainWorkflowAcceptanceEvidence.resolve(stages: stages)

        XCTAssertFalse(acceptance.ready)
        XCTAssertEqual(acceptance.status, .blocked)
        XCTAssertEqual(acceptance.observedStages, [.created, .demandIntake])
        XCTAssertEqual(
            acceptance.missingStages,
            [.scopeFreeze, .serviceBranchConfirm, .worktreeSetup, .development, .deliveryCheck, .archived]
        )
        XCTAssertEqual(acceptance.stagesMissingPrimaryAction, [.demandIntake])
        XCTAssertEqual(acceptance.stagesMissingEvidence, [.demandIntake])
        XCTAssertEqual(acceptance.stagesMissingCurrentStateAnswer, [.demandIntake])
        XCTAssertTrue(acceptance.reason.contains("还缺阶段"))
        XCTAssertTrue(acceptance.reason.contains("缺完整阶段回答"))
        XCTAssertTrue(acceptance.reason.contains("缺主动作"))
        XCTAssertTrue(acceptance.reason.contains("缺可路由证据"))
        XCTAssertTrue(acceptance.reason.contains("缺少需求预检 evidence"))
        XCTAssertTrue(acceptance.reason.contains("缺少开发任务 evidence"))
        XCTAssertTrue(acceptance.reason.contains("Worktree 行状态仍缺"))
        XCTAssertTrue(acceptance.reason.contains("缺少交付或归档 evidence"))
        XCTAssertTrue(acceptance.reason.contains("缺少 legacy 边界 evidence"))
        XCTAssertEqual(acceptance.missingWorktreeStates, ServiceWorktreeRowStateKind.allCases)
    }

    func testWorkspaceStageAnswerKeepsCurrentStateReasonActionAndEvidenceTogether() {
        let stage = WorkspaceMainStage(
            id: .deliveryCheck,
            status: .blocked,
            title: "交付检查 / Delivery",
            reason: "SQL rollback evidence is missing.",
            primaryActionLabel: "查看 SQL",
            primaryActionSystemImage: "cylinder.split.1x2",
            primaryAction: .document("sql"),
            evidence: ["sql/release.sql", "交付记录.md", "manual note"],
            nextStageAllowed: false
        )

        let answer = stage.answer

        XCTAssertEqual(answer.stageID, .deliveryCheck)
        XCTAssertEqual(answer.status, .blocked)
        XCTAssertEqual(answer.reason, "SQL rollback evidence is missing.")
        XCTAssertEqual(answer.blockerSummary, "阻塞：SQL rollback evidence is missing.")
        XCTAssertEqual(answer.nextActionLabel, "查看 SQL")
        XCTAssertEqual(answer.nextAction, .document("sql"))
        XCTAssertEqual(answer.evidenceLinks.map(\.label), stage.evidence)
        XCTAssertEqual(answer.routedEvidenceLinks.map(\.label), ["sql/release.sql", "交付记录.md"])
        XCTAssertEqual(answer.primaryEvidenceLink?.label, "sql/release.sql")
        XCTAssertEqual(answer.visibleEvidenceLinks.map(\.label), ["sql/release.sql"])
        XCTAssertEqual(answer.collapsedEvidenceLinks.map(\.label), ["交付记录.md", "manual note"])
        XCTAssertTrue(answer.evidenceDetailsCollapsedByDefault)
        XCTAssertEqual(answer.evidenceDetailLabel, "证据详情 / Evidence details (2)")
        XCTAssertTrue(answer.canAnswerCurrentState)
    }

    func testWorkspaceStageAnswerRequiresRoutedEvidenceFile() {
        let stage = WorkspaceMainStage(
            id: .development,
            status: .next,
            title: "开发任务 / Development",
            reason: "Task evidence exists only as plain text.",
            primaryActionLabel: "继续任务",
            primaryActionSystemImage: "checklist",
            primaryAction: .task("task-1"),
            evidence: ["task needs follow-up"],
            nextStageAllowed: false
        )

        XCTAssertTrue(stage.answer.routedEvidenceLinks.isEmpty)
        XCTAssertNil(stage.answer.primaryEvidenceLink)
        XCTAssertFalse(stage.answer.canAnswerCurrentState)
    }

    func testWorkspaceStageAnswerSummarizesReadyStateWithoutBlockers() {
        let stage = WorkspaceMainStage(
            id: .archived,
            status: .ready,
            title: "归档完成 / Archived",
            reason: "All archive evidence is present.",
            primaryActionLabel: "查看交付",
            primaryActionSystemImage: "doc.text",
            primaryAction: .document("delivery"),
            evidence: ["交付记录.md"],
            nextStageAllowed: true
        )

        XCTAssertEqual(stage.answer.blockerSummary, "无阻塞：可以进入下一阶段。")
        XCTAssertTrue(stage.answer.canAnswerCurrentState)
    }

    func testMainStageEvidenceLinksOpenKnownEvidenceSources() {
        let stage = WorkspaceMainStage(
            id: .development,
            status: .next,
            title: "Continue task",
            reason: "Evidence links should route back to their files.",
            primaryActionLabel: "Continue",
            primaryActionSystemImage: "play.circle",
            primaryAction: .task("task-1"),
            evidence: [
                "需求/scope.md",
                "tasks.md:L12",
                "交付记录.md",
                "/tmp/workspace/STATUS.md",
                "恢复开发需要确认写回",
                "归档依赖交付门禁"
            ],
            nextStageAllowed: false
        )
        let links = stage.evidenceLinks

        XCTAssertEqual(links.map(\.label), stage.evidence)
        XCTAssertEqual(links[0].action, .document("scope"))
        XCTAssertEqual(links[1].action, .document("tasks"))
        XCTAssertEqual(links[2].action, .document("delivery"))
        XCTAssertEqual(links[3].action, .path("/tmp/workspace/STATUS.md"))
        XCTAssertEqual(links[4].action, .lifecycle(.restoreDevelopment))
        XCTAssertNil(links[5].action)
    }

    func testCommandCenterLayoutKeepsSecondaryActionsBelowEvidence() {
        let layout = CommandCenterLayoutPolicy()

        XCTAssertEqual(layout.sections, [
            .primaryStageAction,
            .workflowPathEvidence,
            .statusMetrics,
            .secondaryActions,
            .localCheckReceipt
        ])
        XCTAssertTrue(layout.keepsSecondaryActionsAfterEvidence)
        XCTAssertTrue(layout.exposesSingleProminentPrimaryAction)
        XCTAssertEqual(layout.prominentPrimaryActionLimit, 1)
        XCTAssertEqual(layout.pathActionPlacement, .menu)
        XCTAssertTrue(layout.secondaryActions.isSecondarySurface)
        XCTAssertFalse(layout.secondaryActions.usesProminentButtons)
        XCTAssertEqual(layout.secondaryActions.groups, [.handoff, .next, .local])
        XCTAssertEqual(layout.secondaryActions.title, "快捷动作")
        XCTAssertEqual(layout.secondaryActions.helpText, "Quick actions")
        XCTAssertEqual(layout.secondaryActions.groups.map(\.title), [
            "交接",
            "下一步",
            "本地打开"
        ])
        XCTAssertEqual(layout.secondaryActions.groups.map(\.helpText), [
            "Handoff",
            "Next",
            "Local"
        ])
        XCTAssertEqual(layout.auditSummary.status, .ready)
        XCTAssertEqual(layout.auditSummary.title, "主动作优先")
        XCTAssertEqual(layout.auditSummary.helpText, "Primary action first")
        XCTAssertTrue(layout.auditSummary.detail.contains("只暴露 1 个 prominent 主动作"))
        XCTAssertTrue(layout.auditSummary.detail.contains("菜单 / Menu"))
        XCTAssertEqual(layout.auditSummary.evidence, [
            "prominentPrimaryActionCount=1",
            "workflowPathPlacement=menu",
            "secondaryActionGroups=3",
            "secondaryAfterEvidence=true"
        ])

        let crowded = CommandCenterLayoutPolicy(prominentPrimaryActionLimit: 2)
        XCTAssertFalse(crowded.exposesSingleProminentPrimaryAction)
        XCTAssertEqual(crowded.auditSummary.status, .blocked)
        XCTAssertTrue(crowded.auditSummary.detail.contains("主动作层级未收敛"))
    }

    func testWorkspaceDetailActionHierarchyKeepsOneTopPrimaryAction() {
        let policy = WorkspaceDetailActionHierarchyPolicy()

        XCTAssertEqual(policy.topLevelProminentAreas, [.mainWorkflow])
        XCTAssertEqual(policy.secondaryAreas, [.statusDiagnostics, .detailNavigation, .creationFollowUp])
        XCTAssertEqual(policy.scopedProminentAreas, [.commandCenter])
        XCTAssertEqual(policy.topLevelProminentActionCount, 1)
        XCTAssertTrue(policy.keepsDiagnosticsSecondary)
        XCTAssertTrue(policy.keepsCreationFollowUpSecondary)
        XCTAssertTrue(policy.isolatesCommandCenterProminentAction)
        XCTAssertEqual(policy.status, .ready)
        XCTAssertEqual(policy.evidence, [
            "topLevelProminent=mainWorkflow",
            "secondary=statusDiagnostics,detailNavigation,creationFollowUp",
            "scopedProminent=commandCenter"
        ])

        let crowded = WorkspaceDetailActionHierarchyPolicy(
            topLevelProminentAreas: [.mainWorkflow, .creationFollowUp],
            secondaryAreas: [.statusDiagnostics, .detailNavigation],
            scopedProminentAreas: [.commandCenter]
        )
        XCTAssertEqual(crowded.topLevelProminentActionCount, 2)
        XCTAssertFalse(crowded.keepsCreationFollowUpSecondary)
        XCTAssertEqual(crowded.status, .blocked)
    }

    func testWorkspaceListStageBadgesComeFromMainStage() {
        let blockedStage = WorkspaceMainStage(
            id: .worktreeSetup,
            status: .blocked,
            title: "Create worktree",
            reason: "Missing source repository.",
            primaryActionLabel: "修复来源",
            primaryActionSystemImage: "folder.badge.questionmark",
            primaryAction: .document("services"),
            evidence: ["services.md"],
            nextStageAllowed: false
        )
        let blockedBadges = blockedStage.listBadges

        XCTAssertEqual(blockedBadges.map(\.id), ["stage", "status", "action", "evidence"])
        XCTAssertEqual(blockedBadges.map(\.label), ["Worktree", "阻塞 / block", "修复来源", "services.md"])
        XCTAssertTrue(blockedBadges.allSatisfy { $0.status == .blocked })

        let readyStage = WorkspaceMainStage(
            id: .archived,
            status: .ready,
            title: "Ready to archive",
            reason: "Delivery complete.",
            primaryActionLabel: "归档",
            primaryActionSystemImage: "archivebox",
            primaryAction: .lifecycle(.archived),
            evidence: ["交付记录.md"],
            nextStageAllowed: true
        )
        let readyBadges = readyStage.listBadges

        XCTAssertEqual(readyBadges.map(\.label), ["归档", "就绪 / ready", "归档", "交付记录.md"])
        XCTAssertEqual(readyBadges.last?.id, "evidence")
        XCTAssertEqual(readyBadges.last?.status, .ready)
    }

    func testWorkspaceBoardLanesOrderProjectsAndLimitCompletedToFive() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-board-ordering-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Board\n\n<!-- template-version: 2 -->\n".write(
            to: root.appendingPathComponent("workspace.md"),
            atomically: true,
            encoding: .utf8
        )
        try "## F-001 Board\n- Status: todo\n- Verification: code\n- Auto complete: true\n".write(
            to: root.appendingPathComponent("FEATURES.md"),
            atomically: true,
            encoding: .utf8
        )

        let attention = [
            workspaceForWorkflowSummary(
                stage: "developing",
                id: "blocked",
                folder: "2026-07-01-blocked",
                path: root.path,
                branch: "tbd",
                riskLevel: .low
            ),
            workspaceForWorkflowSummary(
                stage: "developing",
                id: "review",
                folder: "2026-07-04-review",
                path: root.path,
                riskLevel: .low
            ),
            workspaceForWorkflowSummary(
                stage: "scoping",
                id: "next-high-new",
                folder: "2026-07-04-next",
                riskLevel: .high
            ),
            workspaceForWorkflowSummary(
                stage: "scoping",
                id: "next-high-old",
                folder: "2026-07-02-next",
                riskLevel: .high
            ),
            workspaceForWorkflowSummary(
                stage: "scoping",
                id: "next-low",
                folder: "2026-07-05-next",
                riskLevel: .low
            )
        ]
        XCTAssertEqual(attention.map { $0.mainStage().status }, [.blocked, .review, .next, .next, .next])
        XCTAssertEqual(
            attention.map { $0.mainStage().id },
            [.serviceBranchConfirm, .serviceBranchConfirm, .created, .created, .created]
        )
        XCTAssertEqual(
            WorkspaceBoardLane.lanes(for: attention).first { $0.id == .attention }?.workspaces.map(\.id),
            ["blocked", "review", "next-high-new", "next-high-old", "next-low"]
        )

        try writeBranchPolicyFixture(workspaceRoot: root, branch: "feature/board-ordering")
        let todo = WorkspaceTask(
            id: "todo",
            title: "Todo",
            status: "todo",
            detail: "Todo",
            priority: "normal",
            source: "workspace",
            sourceEventID: nil,
            sourceLine: nil
        )
        let active = [
            workspaceForWorkflowSummary(
                stage: "developing",
                id: "active-old",
                name: "Older",
                folder: "2026-07-02-active",
                path: root.path,
                branch: "feature/board-ordering",
                tasks: [todo]
            ),
            workspaceForWorkflowSummary(
                stage: "developing",
                id: "active-zulu",
                name: "Zulu",
                folder: "2026-07-03-active",
                path: root.path,
                branch: "feature/board-ordering",
                tasks: [todo]
            ),
            workspaceForWorkflowSummary(
                stage: "developing",
                id: "active-alpha",
                name: "Alpha",
                folder: "2026-07-03-active",
                path: root.path,
                branch: "feature/board-ordering",
                tasks: [todo]
            )
        ]
        XCTAssertEqual(active.map { $0.mainStage().status }, [.next, .next, .next])
        XCTAssertEqual(active.map { $0.mainStage().id }, [.development, .development, .development])
        XCTAssertEqual(
            WorkspaceBoardLane.lanes(for: active).first { $0.id == .active }?.workspaces.map(\.id),
            ["active-alpha", "active-zulu", "active-old"]
        )

        let archived = (1...7).map { index in
            workspaceForWorkflowSummary(
                stage: "archived",
                id: "archive-\(index)",
                folder: String(format: "2026-07-%02d-archive", index)
            )
        }
        let limited = WorkspaceBoardLane.lanes(for: archived)
        let completed = limited.first { $0.id == .completed }
        XCTAssertEqual(limited.map(\.id), [.attention, .active, .completed])
        XCTAssertEqual(completed?.totalCount, 7)
        XCTAssertEqual(completed?.workspaces.map(\.id), ["archive-7", "archive-6", "archive-5", "archive-4", "archive-3"])
        XCTAssertTrue(completed?.hasHiddenWorkspaces == true)

        let expanded = WorkspaceBoardLane.lanes(for: archived, showsAllCompleted: true)
        XCTAssertEqual(
            expanded.first { $0.id == .completed }?.workspaces.map(\.id),
            ["archive-7", "archive-6", "archive-5", "archive-4", "archive-3", "archive-2", "archive-1"]
        )
    }

    func testWorkspaceSummaryMapsSqlFilesFromBridgeSnapshot() {
        let snapshot = WorkspaceSnapshot(
            name: "SQL Workspace",
            folder: "2026-05-31-sql-workspace",
            path: "/tmp/workspaces/2026-05-31-sql-workspace",
            state: "delivery",
            targetBranch: "chen/sql-workspace",
            sourceRoot: "/tmp/source-repos",
            confirmedServices: [],
            candidateServices: [],
            taskCounts: TaskCountsSnapshot(done: 0, doing: 0, todo: 0, blocked: 0),
            decisionCount: 0,
            gitRows: [],
            risks: [],
            riskCount: 0,
            updated: "2026-05-31",
            links: [:],
            sqlFiles: [
                WorkspaceSqlFileSnapshot(
                    relativePath: "pay_log.sql",
                    path: "/tmp/workspaces/2026-05-31-sql-workspace/sql/pay_log.sql",
                    kind: "formal"
                ),
                WorkspaceSqlFileSnapshot(
                    relativePath: "pay_log_rollback.sql",
                    path: "/tmp/workspaces/2026-05-31-sql-workspace/sql/pay_log_rollback.sql",
                    kind: "rollback"
                )
            ],
            sqlDocuments: [
                WorkspaceSqlDocumentSnapshot(
                    relativePath: "SQL变更说明.md",
                    path: "/tmp/workspaces/2026-05-31-sql-workspace/sql/SQL变更说明.md",
                    kind: "markdown"
                )
            ],
            worktreeCommand: ""
        )

        let workspace = WorkspaceSummary(snapshot: snapshot)

        XCTAssertEqual(workspace.sqlFiles.map(\.relativePath), ["pay_log.sql", "pay_log_rollback.sql"])
        XCTAssertEqual(workspace.sqlFiles.map(\.kindLabel), ["正式 SQL / Formal", "回滚 SQL / Rollback"])
        XCTAssertEqual(workspace.sqlFiles.first?.fileName, "pay_log.sql")
        XCTAssertEqual(workspace.sqlDocuments.map(\.relativePath), ["SQL变更说明.md"])
        XCTAssertEqual(workspace.sqlDocuments.first?.kindLabel, "SQL 说明文档 / Markdown")
    }

    func testWorkspaceDocumentRoleMapsStandardGateResponsibilities() {
        let tasks = WorkspaceDocumentRole.standard(for: "tasks")
        let delivery = WorkspaceDocumentRole.standard(for: "delivery")
        let handoff = WorkspaceDocumentRole.standard(for: "handoff")
        let unknown = WorkspaceDocumentRole.standard(for: "custom")

        XCTAssertEqual(tasks.purpose, "唯一的工程执行任务来源，参与 Task Center 和交付阻塞判断。")
        XCTAssertEqual(tasks.gate, "development, delivery_check")
        XCTAssertTrue(tasks.participatesInGate)
        XCTAssertEqual(delivery.gateLabel, "delivery_check, archived")
        XCTAssertTrue(delivery.updateTiming.contains("SQL"))
        XCTAssertFalse(handoff.participatesInGate)
        XCTAssertEqual(handoff.gateLabel, "参考 / Reference")
        XCTAssertEqual(unknown.key, "custom")
        XCTAssertFalse(unknown.participatesInGate)
    }

    func testWorkspaceDocumentRoleTreatsSqlArtifactsAsReviewOnlyGateEvidence() {
        let role = WorkspaceDocumentRole.sqlArtifact(for: "sql/V5__add_pay_log.sql")

        XCTAssertEqual(role.gate, "delivery_check, archived")
        XCTAssertEqual(role.gateLabel, "delivery_check, archived")
        XCTAssertTrue(role.participatesInGate)
        XCTAssertTrue(role.purpose.contains("可回退"))
        XCTAssertTrue(role.createPolicy.contains("不会自动生成 SQL 产物"))
    }

    func testWorkspaceDocumentPresentationSeparatesMarkdownPreviewFromSqlSourceReview() {
        let markdown = WorkspaceDocumentPresentation.resolve(
            key: "delivery",
            path: "/tmp/workspace/交付记录.md",
            isMarkdown: true
        )
        XCTAssertFalse(markdown.prefersSource)
        XCTAssertTrue(markdown.allowsRenderedPreview)
        XCTAssertFalse(markdown.reviewOnly)

        let plainSource = WorkspaceDocumentPresentation.resolve(
            key: "worktreeScript",
            path: "/tmp/workspace/scripts/worktree-commands.sh",
            isMarkdown: false
        )
        XCTAssertTrue(plainSource.prefersSource)
        XCTAssertFalse(plainSource.allowsRenderedPreview)
        XCTAssertFalse(plainSource.reviewOnly)

        let sql = WorkspaceDocumentPresentation.resolve(
            key: "sql/V5__add_pay_log.sql",
            path: "/tmp/workspace/sql/V5__add_pay_log.sql",
            isMarkdown: false
        )
        XCTAssertTrue(sql.prefersSource)
        XCTAssertFalse(sql.allowsRenderedPreview)
        XCTAssertTrue(sql.reviewOnly)
        XCTAssertTrue(sql.detail.contains("只做源码复查"))

        let sqlNote = WorkspaceDocumentPresentation.resolve(
            key: "sql-doc/SQL变更说明.md",
            path: "/tmp/workspace/sql/SQL变更说明.md",
            isMarkdown: true
        )
        XCTAssertTrue(sqlNote.prefersSource)
        XCTAssertFalse(sqlNote.allowsRenderedPreview)
        XCTAssertTrue(sqlNote.reviewOnly)
    }

    func testWorkspaceSqlSummaryPromotesSqlToTopLevelStatus() {
        let missingRollback = workspaceForWorkflowSummary(
            stage: "delivery",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "sql-directory",
                    label: "SQL 产物",
                    detail: "交付记录包含 SQL 变更，但 sql/ 下缺少回滚 SQL 文件。",
                    status: "fail",
                    action: "sql"
                )
            ],
            sqlFiles: [
                WorkspaceSqlFile(
                    relativePath: "pay_log.sql",
                    path: "/tmp/workspaces/sql/sql/pay_log.sql",
                    kind: "formal"
                )
            ]
        )
        let clean = workspaceForWorkflowSummary(
            stage: "delivery",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "sql-directory",
                    label: "SQL 产物",
                    detail: "SQL 变更已有正式 SQL 1 个、回滚 SQL 1 个。",
                    status: "pass",
                    action: "sql"
                )
            ],
            sqlFiles: [
                WorkspaceSqlFile(
                    relativePath: "pay_log.sql",
                    path: "/tmp/workspaces/sql/sql/pay_log.sql",
                    kind: "formal"
                ),
                WorkspaceSqlFile(
                    relativePath: "pay_log_rollback.sql",
                    path: "/tmp/workspaces/sql/sql/pay_log_rollback.sql",
                    kind: "rollback"
                )
            ]
        )
        let unchecked = workspaceForWorkflowSummary(
            stage: "developing",
            sqlFiles: [
                WorkspaceSqlFile(
                    relativePath: "draft.sql",
                    path: "/tmp/workspaces/sql/sql/draft.sql",
                    kind: "formal"
                )
            ]
        )

        XCTAssertEqual(WorkspaceSqlSummary(workspace: missingRollback).value, "缺产物")
        XCTAssertEqual(WorkspaceSqlSummary(workspace: missingRollback).status, .blocked)
        XCTAssertEqual(WorkspaceSqlSummary(workspace: clean).value, "已匹配")
        XCTAssertEqual(WorkspaceSqlSummary(workspace: clean).status, .ready)
        XCTAssertEqual(WorkspaceSqlSummary(workspace: unchecked).value, "1 文件")
        XCTAssertEqual(WorkspaceSqlSummary(workspace: unchecked).status, .review)
    }

    func testScopeFreezeEvidenceOwnsScopeGateAfterDemandIntake() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-scope-freeze-\(UUID().uuidString)")
        let demandDir = root.appendingPathComponent("需求")
        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try "# 需求确认卡\n\n- 真实需求目标：补齐交易快照。\n- 用户流程：保存订单时写入快照。\n- 验收标准：可查询历史快照。\n".write(
            to: demandDir.appendingPathComponent("requirement.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 待确认问题\n\n## P0 阻塞开发\n\n- [x] 已确认无需新增字段。\n".write(
            to: demandDir.appendingPathComponent("questions.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # 本次开发范围

        ## 已确认并实现

        - 保存订单时记录交易快照。

        ## 暂不实现

        - 不补历史数据。

        ## 仍待确认

        - P0: 快照是否需要额外字段？

        ## 进入开发条件

        - [ ] 本文件已冻结本次开发范围。
        """.write(
            to: demandDir.appendingPathComponent("scope.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # 需求列表

        | 需求点 | 状态 | 优先级 | 来源 | 说明 |
        | --- | --- | --- | --- | --- |
        | 新增交易快照写入 | 待办 | P0 | 蓝湖 | 保存订单时记录快照 |
        """.write(
            to: demandDir.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 需求交付\n\n- 预检完成。\n".write(
            to: demandDir.appendingPathComponent("delivery.md"),
            atomically: true,
            encoding: .utf8
        )

        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "scope-freeze",
            name: "Scope Freeze",
            path: root.path
        )
        let status = demandIntakeStatus(at: demandDir)
        let readiness = DemandIntakeReadinessEvidence.resolve(status: status, workspace: workspace)
        let scope = ScopeFreezeEvidence.resolve(status: status, workspace: workspace)
        let stage = workspace.mainStage(
            demandIntakeStatus: status,
            demandReadiness: readiness,
            scopeFreeze: scope
        )

        XCTAssertTrue(readiness.ready)
        XCTAssertFalse(scope.ready)
        XCTAssertEqual(scope.status, .blocked)
        XCTAssertEqual(scope.unresolvedP0Count, 1)
        XCTAssertEqual(stage.id, .scopeFreeze)
        XCTAssertEqual(stage.primaryAction, .path(demandDir.appendingPathComponent("scope.md").path))
    }

    func testScopeFreezeEvidenceRequiresAuditWhenScopeChangeIsDeclared() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-scope-change-review-\(UUID().uuidString)")
        let demandDir = root.appendingPathComponent("需求")
        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try writeDemandIntakeFixture(
            demandDir: demandDir,
            scope: """
            # 本次开发范围

            ## 已确认并实现

            - 保存订单时记录交易快照。

            ## 暂不实现

            - 不补历史数据。

            ## 仍待确认

            - 无 P0 待确认项。

            ## 范围变更

            - 新增交易快照导出。

            ## 进入开发条件

            - [x] 本文件已冻结本次开发范围。
            """
        )

        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "scope-change-review",
            path: root.path
        )
        let status = demandIntakeStatus(at: demandDir)
        let scope = ScopeFreezeEvidence.resolve(status: status, workspace: workspace)

        XCTAssertEqual(scope.status, .review)
        XCTAssertTrue(scope.scopeChangeDeclared)
        XCTAssertFalse(scope.scopeChangeAudited)
        XCTAssertEqual(scope.checks.first { $0.id == "scope-change-audit" }?.status, .review)
    }

    func testScopeFreezeWritePlanBlocksBeforeScopeContentIsReady() {
        let workspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "scope-freeze-write-blocked",
            path: "/tmp/scope-freeze-write-blocked"
        )
        let evidence = ScopeFreezeEvidence(
            status: .blocked,
            reason: "missing scope",
            evidence: ["需求/scope.md"],
            checks: [],
            scopePath: #filePath,
            revision: NativeScopeFreezeStore.inspectRevision(at: #filePath),
            hasInScope: false,
            hasOutOfScope: true,
            scopeFrozen: false,
            scopeChangeDeclared: false,
            scopeChangeAudited: true,
            unresolvedP0Count: 1
        )
        let plan = ScopeFreezeWritePlan.resolve(workspace: workspace, evidence: evidence)

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertFalse(plan.canWrite)
        XCTAssertEqual(plan.items.map(\.id), ["missing-in-scope", "pending-p0"])
        XCTAssertTrue(plan.appendedMarkdown.isEmpty)
        XCTAssertTrue(plan.summary.contains("不会替用户补造范围结论"))
    }

    func testScopeFreezeWritePlanRejectsRevisionDetachedFromEvidence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-scope-revision-detached-\(UUID().uuidString)")
        let demandDir = root.appendingPathComponent("需求")
        let scopeURL = demandDir.appendingPathComponent("scope.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)

        try writeDemandIntakeFixture(
            demandDir: demandDir,
            scope: """
            # 本次开发范围

            ## 已确认并实现

            - 保存订单时记录交易快照。

            ## 暂不实现

            - 不补历史数据。

            ## 仍待确认

            - 无 P0 待确认项。

            ## 进入开发条件

            - [ ] 本文件已冻结本次开发范围。
            """
        )
        let workspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "scope-revision-detached",
            path: root.path
        )
        let evidence = ScopeFreezeEvidence.resolve(
            status: demandIntakeStatus(at: demandDir),
            workspace: workspace
        )
        XCTAssertTrue(evidence.hasInScope)
        XCTAssertTrue(evidence.hasOutOfScope)
        XCTAssertEqual(evidence.unresolvedP0Count, 0)

        let changed = """
        # 本次开发范围

        ## 已确认并实现

        - 改为保存订单时覆盖交易快照。

        ## 暂不实现

        - 不补历史数据。

        ## 仍待确认

        - P0：覆盖规则尚未确认。

        ## 进入开发条件

        - [ ] 本文件已冻结本次开发范围。
        """ + "\n"
        let changedBytes = Data(changed.utf8)
        try changedBytes.write(to: scopeURL, options: .atomic)

        let plan = ScopeFreezeWritePlan.resolve(workspace: workspace, evidence: evidence)

        XCTAssertEqual(plan.status, .blocked)
        XCTAssertFalse(plan.canWrite)
        XCTAssertTrue(plan.appendedMarkdown.isEmpty)
        XCTAssertEqual(plan.items.map(\.id), ["unsafe-scope-document"])
        XCTAssertTrue(plan.summary.contains("changed while preparing confirmation"))
        XCTAssertThrowsError(
            try NativeScopeFreezeStore.write(
                plan: plan,
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        )
        XCTAssertEqual(try Data(contentsOf: scopeURL), changedBytes)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testScopeFreezeWritePlanCapturesStrictDocumentRevision() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-scope-revision-\(UUID().uuidString)")
        let regularURL = root.appendingPathComponent("regular/需求/scope.md")
        let missingURL = root.appendingPathComponent("missing/需求/scope.md")
        let linkedURL = root.appendingPathComponent("linked/需求/scope.md")
        let invalidURL = root.appendingPathComponent("invalid/需求/scope.md")
        let externalURL = root.appendingPathComponent("external-scope.md")
        defer { try? FileManager.default.removeItem(at: root) }
        for url in [regularURL, missingURL, linkedURL, invalidURL] {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        let original = "# Scope\n\n## In scope\n\n- Real.\n\n## Out of scope\n\n- None.\n"
        try original.write(to: regularURL, atomically: true, encoding: .utf8)
        try original.write(to: externalURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: linkedURL, withDestinationURL: externalURL)
        try Data([0x23, 0x20, 0xC3, 0x28, 0x0A]).write(to: invalidURL)

        func plan(id: String, path: URL) -> ScopeFreezeWritePlan {
            let workspace = workspaceForWorkflowSummary(
                stage: "scoping",
                id: id,
                path: path.deletingLastPathComponent().deletingLastPathComponent().path
            )
            let evidence = ScopeFreezeEvidence(
                status: .blocked,
                reason: "ready to freeze",
                evidence: [path.path],
                checks: [],
                scopePath: path.path,
                revision: NativeScopeFreezeStore.inspectRevision(at: path.path),
                hasInScope: true,
                hasOutOfScope: true,
                scopeFrozen: false,
                scopeChangeDeclared: false,
                scopeChangeAudited: true,
                unresolvedP0Count: 0
            )
            return ScopeFreezeWritePlan.resolve(workspace: workspace, evidence: evidence)
        }

        let regular = plan(id: "scope-revision-regular", path: regularURL)
        let missing = plan(id: "scope-revision-missing", path: missingURL)
        let linked = plan(id: "scope-revision-linked", path: linkedURL)
        let invalid = plan(id: "scope-revision-invalid", path: invalidURL)

        guard case .regularUTF8(let sha256, let byteCount) = regular.expectedRevision else {
            return XCTFail("expected regular UTF-8 scope revision")
        }
        XCTAssertEqual(sha256.count, 64)
        XCTAssertEqual(byteCount, original.data(using: .utf8)?.count)
        XCTAssertTrue(regular.canWrite)
        XCTAssertEqual(missing.expectedRevision, .missing)
        XCTAssertFalse(missing.canWrite)
        XCTAssertTrue(missing.summary.contains("missing"))
        guard case .invalid(let linkedReason) = linked.expectedRevision else {
            return XCTFail("expected invalid symlink scope revision")
        }
        XCTAssertTrue(linkedReason.contains("not a regular file"))
        XCTAssertFalse(linked.canWrite)
        guard case .invalid(let invalidReason) = invalid.expectedRevision else {
            return XCTFail("expected invalid UTF-8 scope revision")
        }
        XCTAssertTrue(invalidReason.contains("not valid UTF-8"))
        XCTAssertFalse(invalid.canWrite)
        XCTAssertEqual(try String(contentsOf: externalURL, encoding: .utf8), original)
    }

    func testScopeFreezeWritePlanAppendsOnlyFreezeConfirmationWhenReady() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-scope-freeze-write-ready-\(UUID().uuidString)")
        let demandDir = root.appendingPathComponent("需求")
        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try writeDemandIntakeFixture(
            demandDir: demandDir,
            scope: """
            # 本次开发范围

            ## 已确认并实现

            - 保存订单时记录交易快照。

            ## 暂不实现

            - 不补历史数据。

            ## 仍待确认

            - 无 P0 待确认项。

            ## 进入开发条件

            - [ ] 本文件已冻结本次开发范围。
            """
        )

        let workspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "scope-freeze-write-ready",
            name: "Scope Freeze Ready",
            path: root.path
        )
        let status = demandIntakeStatus(at: demandDir)
        let evidence = ScopeFreezeEvidence.resolve(status: status, workspace: workspace)
        let plan = ScopeFreezeWritePlan.resolve(workspace: workspace, evidence: evidence)

        XCTAssertEqual(evidence.status, .blocked)
        XCTAssertFalse(evidence.scopeFrozen)
        XCTAssertEqual(plan.status, .next)
        XCTAssertTrue(plan.canWrite)
        XCTAssertEqual(plan.expectedRevision, evidence.revision)
        XCTAssertEqual(plan.items.map(\.id), ["append-freeze-marker"])
        XCTAssertTrue(plan.appendedMarkdown.contains("范围已冻结"))
        XCTAssertTrue(plan.appendedMarkdown.contains("Nexus Native confirmed write"))
        XCTAssertFalse(plan.appendedMarkdown.contains("保存订单时记录交易快照"))

        XCTAssertThrowsError(
            try NativeScopeFreezeStore.write(plan: plan, confirmed: false)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("explicit confirmation"))
        }

        let auditRoot = root.appendingPathComponent("audit")
        let response = try NativeScopeFreezeStore.write(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        let scopeContent = try String(contentsOf: demandDir.appendingPathComponent("scope.md"), encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertTrue(response.appended)
        XCTAssertEqual(response.path, demandDir.appendingPathComponent("scope.md").path)
        XCTAssertTrue(scopeContent.contains("保存订单时记录交易快照"))
        XCTAssertTrue(scopeContent.contains("## 范围冻结确认 / Scope Freeze Confirmation"))
        XCTAssertTrue(scopeContent.contains("- [x] 范围已冻结：本次开发只按上方 In scope / Out of scope 推进。"))
        XCTAssertTrue(scopeContent.hasSuffix("\n"))
        XCTAssertEqual(response.auditEventID, events.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(events.first?.action, "scope.freeze_confirmed")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["scopePath"], response.path)
        XCTAssertEqual(events.first?.metadata["status"], "next")
    }

    func testNativeScopeFreezeStoreRejectsChangedDeletedAndUnsafeEvidence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-scope-write-safety-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let original = """
        # 本次开发范围

        ## 已确认并实现

        - 保存订单时记录交易快照。

        ## 暂不实现

        - 不补历史数据。

        ## 仍待确认

        - 无 P0 待确认项。

        ## 进入开发条件

        - [ ] 本文件已冻结本次开发范围。
        """

        func writablePlan(at directory: URL, id: String) throws -> ScopeFreezeWritePlan {
            let demandDir = directory.appendingPathComponent("需求")
            try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
            try writeDemandIntakeFixture(demandDir: demandDir, scope: original)
            let workspace = workspaceForWorkflowSummary(
                stage: "scoping",
                id: id,
                name: id,
                path: directory.path
            )
            let evidence = ScopeFreezeEvidence.resolve(
                status: demandIntakeStatus(at: demandDir),
                workspace: workspace
            )
            let plan = ScopeFreezeWritePlan.resolve(workspace: workspace, evidence: evidence)
            XCTAssertTrue(plan.canWrite)
            return plan
        }

        let changedRoot = root.appendingPathComponent("changed")
        let changedAuditRoot = changedRoot.appendingPathComponent("audit")
        let changedPlan = try writablePlan(at: changedRoot, id: "scope-freeze-changed")
        let changedScopeURL = changedRoot.appendingPathComponent("需求/scope.md")
        let externalEdit = "\n- 外部人工备注：不要覆盖。\n"
        let changedHandle = try FileHandle(forWritingTo: changedScopeURL)
        try changedHandle.seekToEnd()
        try changedHandle.write(contentsOf: Data(externalEdit.utf8))
        try changedHandle.close()

        XCTAssertThrowsError(
            try NativeScopeFreezeStore.write(
                plan: changedPlan,
                confirmed: true,
                auditRoot: changedAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }
        XCTAssertEqual(try String(contentsOf: changedScopeURL, encoding: .utf8), original + externalEdit)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: changedAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))

        let deletedRoot = root.appendingPathComponent("deleted")
        let deletedAuditRoot = deletedRoot.appendingPathComponent("audit")
        let deletedPlan = try writablePlan(at: deletedRoot, id: "scope-freeze-deleted")
        let deletedScopeURL = deletedRoot.appendingPathComponent("需求/scope.md")
        try FileManager.default.removeItem(at: deletedScopeURL)

        XCTAssertThrowsError(
            try NativeScopeFreezeStore.write(
                plan: deletedPlan,
                confirmed: true,
                auditRoot: deletedAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedScopeURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: deletedAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))

        let symlinkRoot = root.appendingPathComponent("symlink")
        let symlinkAuditRoot = symlinkRoot.appendingPathComponent("audit")
        let symlinkPlan = try writablePlan(at: symlinkRoot, id: "scope-freeze-symlink")
        let symlinkScopeURL = symlinkRoot.appendingPathComponent("需求/scope.md")
        let externalURL = root.appendingPathComponent("external-scope.md")
        let externalContent = "# 外部范围\n\n不得写入。\n"
        try externalContent.write(to: externalURL, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(at: symlinkScopeURL)
        try FileManager.default.createSymbolicLink(at: symlinkScopeURL, withDestinationURL: externalURL)

        XCTAssertThrowsError(
            try NativeScopeFreezeStore.write(
                plan: symlinkPlan,
                confirmed: true,
                auditRoot: symlinkAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("not a regular file"))
        }
        XCTAssertEqual(try String(contentsOf: externalURL, encoding: .utf8), externalContent)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: symlinkScopeURL.path),
            externalURL.path
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: symlinkAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))

        let invalidRoot = root.appendingPathComponent("invalid-utf8")
        let invalidAuditRoot = invalidRoot.appendingPathComponent("audit")
        let invalidPlan = try writablePlan(at: invalidRoot, id: "scope-freeze-invalid")
        let invalidScopeURL = invalidRoot.appendingPathComponent("需求/scope.md")
        let invalidBytes = Data([0x23, 0x20, 0xC3, 0x28, 0x0A])
        try invalidBytes.write(to: invalidScopeURL)

        XCTAssertThrowsError(
            try NativeScopeFreezeStore.write(
                plan: invalidPlan,
                confirmed: true,
                auditRoot: invalidAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("not valid UTF-8"))
        }
        XCTAssertEqual(try Data(contentsOf: invalidScopeURL), invalidBytes)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: invalidAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeScopeFreezeStoreRejectsSecondSubmissionWithoutDuplicateAudit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-scope-duplicate-\(UUID().uuidString)")
        let demandDir = root.appendingPathComponent("需求")
        let auditRoot = root.appendingPathComponent("audit")
        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try writeDemandIntakeFixture(
            demandDir: demandDir,
            scope: """
            # 本次开发范围

            ## 已确认并实现

            - 保存订单时记录交易快照。

            ## 暂不实现

            - 不补历史数据。

            ## 仍待确认

            - 无 P0 待确认项。

            ## 进入开发条件

            - [ ] 本文件已冻结本次开发范围。
            """
        )
        let workspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "scope-freeze-duplicate",
            name: "Scope Freeze Duplicate",
            path: root.path
        )
        let plan = ScopeFreezeWritePlan.resolve(
            workspace: workspace,
            evidence: ScopeFreezeEvidence.resolve(
                status: demandIntakeStatus(at: demandDir),
                workspace: workspace
            )
        )

        let first = try NativeScopeFreezeStore.write(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )

        XCTAssertThrowsError(
            try NativeScopeFreezeStore.write(
                plan: plan,
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }

        let content = try String(contentsOf: demandDir.appendingPathComponent("scope.md"), encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 10)
        XCTAssertEqual(content.components(separatedBy: "## 范围冻结确认 / Scope Freeze Confirmation").count - 1, 1)
        XCTAssertEqual(events.filter { $0.action == "scope.freeze_confirmed" }.count, 1)
        XCTAssertNotNil(first.auditEventID)
    }

    func testScopeFreezeEvidenceAllowsAuditedScopeChanges() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-scope-change-audited-\(UUID().uuidString)")
        let demandDir = root.appendingPathComponent("需求")
        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try writeDemandIntakeFixture(
            demandDir: demandDir,
            scope: """
            # 本次开发范围

            ## 已确认并实现

            - 保存订单时记录交易快照。

            ## 暂不实现

            - 不补历史数据。

            ## 仍待确认

            - 无 P0 待确认项。

            ## 范围变更记录

            - 变更原因：蓝湖补充要求导出交易快照。
            - 影响服务：order。
            - 影响任务：新增导出任务。

            ## 进入开发条件

            - [x] 本文件已冻结本次开发范围。
            """
        )

        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "scope-change-audited",
            path: root.path
        )
        let status = demandIntakeStatus(at: demandDir)
        let scope = ScopeFreezeEvidence.resolve(status: status, workspace: workspace)

        XCTAssertEqual(scope.status, .ready)
        XCTAssertTrue(scope.scopeChangeDeclared)
        XCTAssertTrue(scope.scopeChangeAudited)
        XCTAssertEqual(scope.checks.first { $0.id == "scope-change-audit" }?.status, .ready)
    }

    func testServiceBranchEvidenceBlocksMissingBranchAndServiceScope() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "service-branch-missing",
            branch: "待确认",
            services: []
        )
        let serviceBranch = ServiceBranchEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: serviceBranch
        )

        XCTAssertEqual(serviceBranch.status, .blocked)
        XCTAssertFalse(serviceBranch.branchConfirmed)
        XCTAssertFalse(serviceBranch.servicesConfirmed)
        XCTAssertEqual(stage.id, .serviceBranchConfirm)
        XCTAssertEqual(stage.primaryAction, .document("branches"))
    }

    func testServiceBranchEvidenceAllowsReadyWorkspacePastServiceBranchGate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-service-branch-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try """
        # Branches

        - 目标分支: feature/service-branch
        - 基线: master
        - 分支策略: 多服务沿用同一需求分支。
        """.write(
            to: root.appendingPathComponent("branches.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # Services

        ## 已确认相关

        | 服务 | 源仓库 | 说明 |
        | --- | --- | --- |
        | order | ~/source-repos/order | core |
        """.write(
            to: root.appendingPathComponent("services.md"),
            atomically: true,
            encoding: .utf8
        )

        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "service-branch-ready",
            path: root.path,
            branch: "feature/service-branch",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/service-branch",
                    worktree: "ready",
                    gitSummary: "clean",
                    worktreeExists: true,
                    sourceExists: true
                )
            ]
        )
        let serviceBranch = ServiceBranchEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: serviceBranch
        )

        XCTAssertEqual(serviceBranch.status, .ready)
        XCTAssertTrue(serviceBranch.branchConfirmed)
        XCTAssertTrue(serviceBranch.servicesConfirmed)
        XCTAssertTrue(serviceBranch.branchPolicyRecorded)
        XCTAssertTrue(serviceBranch.missingSourceServices.isEmpty)
        XCTAssertTrue(serviceBranch.targetBranchMissingServices.isEmpty)
        XCTAssertNotEqual(stage.id, .serviceBranchConfirm)
    }

    func testServiceBranchEvidenceRequiresRealBranchesDocumentForPolicy() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-service-branch-missing-document-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "service-branch-missing-document",
            path: root.path,
            branch: "feature/service-branch",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/service-branch",
                    worktree: "missing",
                    gitSummary: "target branch available: feature/service-branch",
                    worktreeExists: false,
                    sourceExists: true
                )
            ]
        )

        let serviceBranch = ServiceBranchEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: serviceBranch
        )

        XCTAssertFalse(serviceBranch.branchPolicyRecorded)
        XCTAssertEqual(serviceBranch.status, .review)
        XCTAssertEqual(serviceBranch.checks.first { $0.id == "branch-policy" }?.status, .review)
        XCTAssertEqual(stage.id, .serviceBranchConfirm)
        XCTAssertEqual(stage.primaryAction, .document("branches"))
    }

    func testServiceBranchEvidenceRejectsLinkedBranchesDocument() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-service-branch-linked-document-\(UUID().uuidString)")
        let workspaceRoot = root.appendingPathComponent("workspace")
        let externalBranches = root.appendingPathComponent("external-branches.md")
        try FileManager.default.createDirectory(at: workspaceRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try """
        # External branches

        - 目标分支: feature/service-branch
        - 基线: main
        - 分支策略: 外部文件不得作为工作区证据。
        """.write(to: externalBranches, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: workspaceRoot.appendingPathComponent("branches.md"),
            withDestinationURL: externalBranches
        )
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "service-branch-linked-document",
            path: workspaceRoot.path,
            branch: "feature/service-branch",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/service-branch",
                    worktree: "missing",
                    gitSummary: "target branch available: feature/service-branch",
                    worktreeExists: false,
                    sourceExists: true
                )
            ]
        )

        let serviceBranch = ServiceBranchEvidence.resolve(workspace: workspace)

        XCTAssertFalse(serviceBranch.branchPolicyRecorded)
        XCTAssertEqual(serviceBranch.status, .review)
        XCTAssertEqual(serviceBranch.primaryAction, .document("branches"))
    }

    func testServiceBranchEvidenceRoutesUnavailableTargetBranchToWorktreeSetup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-service-branch-create-target-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try """
        # Branches

        - 目标分支: feature/missing-branch
        - 基线: origin/HEAD
        - 分支策略: 目标分支不存在时由 Nexus 确认创建。
        """.write(
            to: root.appendingPathComponent("branches.md"),
            atomically: true,
            encoding: .utf8
        )
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "service-branch-unavailable-target",
            path: root.path,
            branch: "feature/missing-branch",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/missing-branch",
                    worktree: "missing",
                    gitSummary: "remote missing: origin/feature/missing-branch",
                    worktreeExists: false,
                    sourceExists: true
                )
            ]
        )
        let serviceBranch = ServiceBranchEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: serviceBranch
        )

        XCTAssertEqual(serviceBranch.status, .ready)
        XCTAssertEqual(serviceBranch.targetBranchMissingServices, ["order"])
        XCTAssertEqual(serviceBranch.checks.first { $0.id == "target-branch-availability" }?.status, .next)
        XCTAssertEqual(stage.id, .worktreeSetup)
        XCTAssertEqual(stage.primaryAction, .worktree)
    }

    func testServiceBranchEvidenceKeepsMissingWorktreeInWorktreeGate() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-service-branch-worktree-gate-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try """
        # Branches

        - 目标分支: feature/service-branch
        - 基线: main
        - 分支策略: 使用已存在的目标分支创建 workspace-local worktree。
        """.write(
            to: root.appendingPathComponent("branches.md"),
            atomically: true,
            encoding: .utf8
        )
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "service-branch-missing-worktree",
            path: root.path,
            branch: "feature/service-branch",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "main",
                    worktree: "missing",
                    gitSummary: "source current: main; target branch available: feature/service-branch",
                    worktreeExists: false,
                    sourceExists: true
                )
            ]
        )
        let serviceBranch = ServiceBranchEvidence.resolve(workspace: workspace)
        let worktree = WorktreeSetupEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: serviceBranch,
            worktreeSetup: worktree
        )

        XCTAssertEqual(serviceBranch.status, .ready)
        XCTAssertTrue(serviceBranch.targetBranchMissingServices.isEmpty)
        XCTAssertTrue(
            serviceBranch.checks.first { $0.id == "target-branch-availability" }?.detail.contains("source 当前检出分支不作为阻塞条件") ?? false
        )
        XCTAssertEqual(worktree.status, .next)
        XCTAssertEqual(worktree.missingServices, ["order"])
        XCTAssertEqual(stage.id, .worktreeSetup)
    }

    func testSourceRepositoryAccessKeepsSourceReposReadOnly() {
        let available = SourceRepositoryAccess.resolve(
            service: ServiceStatus(
                name: "orders",
                branch: "feature/orders",
                worktree: "missing",
                gitSummary: "source repo clean",
                worktreeExists: false,
                sourceExists: true
            )
        )

        XCTAssertEqual(available.status, .review)
        XCTAssertEqual(available.actionLabel, "源仓库复查")
        XCTAssertTrue(available.canReveal)
        XCTAssertTrue(available.reviewOnly)
        XCTAssertTrue(available.detail.contains("不会在这里切分支"))
        XCTAssertTrue(available.nextStepHint.contains("确认流程"))

        let missing = SourceRepositoryAccess.resolve(
            service: ServiceStatus(
                name: "payments",
                branch: "feature/payments",
                worktree: "missing",
                gitSummary: "missing source",
                worktreeExists: false,
                sourceExists: false
            )
        )

        XCTAssertEqual(missing.status, .blocked)
        XCTAssertEqual(missing.actionLabel, "服务文档")
        XCTAssertFalse(missing.canReveal)
        XCTAssertTrue(missing.reviewOnly)
        XCTAssertTrue(missing.nextStepHint.contains("services.md"))
    }

    func testServiceWorktreeRowStateDistinguishesFiveExplicitStates() {
        let targetBranch = "feature/worktree"
        let services = [
            ServiceStatus(
                name: "missing-source",
                branch: targetBranch,
                worktree: "missing",
                gitSummary: "source missing",
                worktreeExists: false,
                sourceExists: false
            ),
            ServiceStatus(
                name: "missing-worktree",
                branch: targetBranch,
                worktree: "missing",
                gitSummary: "source clean",
                worktreeExists: false,
                sourceExists: true
            ),
            ServiceStatus(
                name: "branch-mismatch",
                branch: "dev",
                worktree: "ready",
                gitSummary: "target branch missing: feature/worktree",
                worktreeExists: true,
                sourceExists: true
            ),
            ServiceStatus(
                name: "dirty",
                branch: targetBranch,
                worktree: "ready",
                gitSummary: "dirty",
                worktreeExists: true,
                sourceExists: true
            ),
            ServiceStatus(
                name: "clean",
                branch: "origin/feature/worktree",
                worktree: "ready",
                gitSummary: "clean",
                worktreeExists: true,
                sourceExists: true
            )
        ]

        let states = services.map { service in
            ServiceWorktreeRowState.resolve(service: service, targetBranch: targetBranch)
        }

        XCTAssertEqual(states.map(\.kind), ServiceWorktreeRowStateKind.allCases)
        XCTAssertEqual(states.map(\.label), ["source 缺失", "缺 worktree", "目标分支缺失", "未提交", "clean"])
        XCTAssertEqual(states.map(\.status), [.blocked, .next, .blocked, .review, .ready])
        XCTAssertTrue(states.first { $0.kind == .branchMismatch }?.detail.contains("feature/worktree") ?? false)
    }

    func testServiceWorktreeRowStatePrioritizesRepositoryAndBranchBlockersBeforeDirty() {
        let missingSourceAndDirty = ServiceWorktreeRowState.resolve(
            service: ServiceStatus(
                name: "orders",
                branch: "dev",
                worktree: "ready dirty",
                gitSummary: "dirty",
                worktreeExists: true,
                sourceExists: false
            ),
            targetBranch: "feature/worktree"
        )
        let branchMismatchAndDirty = ServiceWorktreeRowState.resolve(
            service: ServiceStatus(
                name: "payments",
                branch: "dev",
                worktree: "ready",
                gitSummary: "dirty; target branch missing: feature/worktree",
                worktreeExists: true,
                sourceExists: true
            ),
            targetBranch: "feature/worktree"
        )
        let differentCurrentBranchAndDirty = ServiceWorktreeRowState.resolve(
            service: ServiceStatus(
                name: "cashier",
                branch: "dev",
                worktree: "ready",
                gitSummary: "dirty; target branch available: feature/worktree",
                worktreeExists: true,
                sourceExists: true
            ),
            targetBranch: "feature/worktree"
        )

        XCTAssertEqual(missingSourceAndDirty.kind, .missingSourceRepo)
        XCTAssertEqual(branchMismatchAndDirty.kind, .branchMismatch)
        XCTAssertEqual(differentCurrentBranchAndDirty.kind, .dirty)
    }

    func testServiceWorktreeRowStateAllowsDifferentCurrentBranchWhenTargetBranchExists() {
        let state = ServiceWorktreeRowState.resolve(
            service: ServiceStatus(
                name: "order",
                branch: "dev",
                worktree: "ready",
                gitSummary: "target branch available: feature/worktree",
                worktreeExists: true,
                sourceExists: true
            ),
            targetBranch: "feature/worktree"
        )

        XCTAssertEqual(state.kind, .clean)
        XCTAssertTrue(state.detail.contains("目标分支未缺失"))
    }

    func testServiceWorktreeRowStateWaitsForConfirmedTargetBeforeAvailabilityCheck() {
        let pendingTarget = ServiceWorktreeRowState.resolve(
            service: ServiceStatus(
                name: "orders",
                branch: "dev",
                worktree: "ready",
                gitSummary: "clean",
                worktreeExists: true,
                sourceExists: true
            ),
            targetBranch: "待确认"
        )

        XCTAssertEqual(pendingTarget.kind, .clean)
    }

    func testWorktreeSetupEvidenceRoutesMissingWorktreesToSetup() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-worktree-missing-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("scripts"),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try "#!/usr/bin/env bash\n".write(
            to: root.appendingPathComponent("scripts/worktree-commands.sh"),
            atomically: true,
            encoding: .utf8
        )

        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "worktree-missing",
            path: root.path,
            branch: "feature/worktree",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/worktree",
                    worktree: "missing",
                    gitSummary: "source clean",
                    worktreeExists: false,
                    sourceExists: true
                )
            ]
        )
        let worktree = WorktreeSetupEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: worktree
        )

        XCTAssertEqual(worktree.status, .next)
        XCTAssertEqual(worktree.missingServices, ["order"])
        XCTAssertEqual(worktree.setupPlan.map(\.action), [.create])
        XCTAssertEqual(worktree.setupPlan.first?.targetPath, root.appendingPathComponent("repos/order").path)
        XCTAssertEqual(worktree.setupPlan.first?.targetBranch, "feature/worktree")
        XCTAssertTrue(worktree.branchMismatchServices.isEmpty)
        XCTAssertTrue(worktree.mutationPolicy.requiresConfirmationSheet)
        XCTAssertEqual(worktree.mutationPolicy.targetRoot, "repos/")
        XCTAssertEqual(worktree.mutationPolicy.allowedServices, ["order"])
        XCTAssertTrue(worktree.mutationPolicy.blockedServices.isEmpty)
        XCTAssertTrue(worktree.mutationPolicy.canRequestConfirmation)
        XCTAssertFalse(worktree.mutationPolicy.canRun(afterConfirmation: false))
        XCTAssertTrue(worktree.mutationPolicy.canRun(afterConfirmation: true))
        XCTAssertEqual(stage.id, .worktreeSetup)
        XCTAssertEqual(stage.primaryAction, .worktree)
    }

    func testWorktreeSetupEvidenceCreatesUnavailableTargetBranchWithMissingWorktree() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "worktree-mismatch",
            branch: "feature/worktree",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "dev",
                    worktree: "missing",
                    gitSummary: "target branch missing: feature/worktree",
                    worktreeExists: false,
                    sourceExists: true
                )
            ]
        )
        let worktree = WorktreeSetupEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: worktree
        )

        XCTAssertEqual(worktree.status, .next)
        XCTAssertEqual(worktree.branchMismatchServices, ["order(feature/worktree)"])
        XCTAssertEqual(worktree.setupPlan.map(\.action), [.create])
        XCTAssertEqual(worktree.setupPlan.first?.currentBranch, "dev")
        XCTAssertTrue(worktree.setupPlan.first?.reason.contains("默认基线") ?? false)
        XCTAssertTrue(worktree.mutationPolicy.blockedServices.isEmpty)
        XCTAssertTrue(worktree.mutationPolicy.canRequestConfirmation)
        XCTAssertTrue(worktree.mutationPolicy.canRun(afterConfirmation: true))
        XCTAssertEqual(stage.id, .worktreeSetup)
        XCTAssertEqual(stage.primaryAction, .worktree)
    }

    func testWorktreeSetupEvidenceAllowsDifferentCurrentBranchWhenTargetBranchExists() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "worktree-current-branch-differs",
            branch: "feature/worktree",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "dev",
                    worktree: "ready",
                    gitSummary: "target branch available: feature/worktree",
                    worktreeExists: true,
                    sourceExists: true
                )
            ]
        )
        let worktree = WorktreeSetupEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: worktree
        )

        XCTAssertEqual(worktree.status, .ready)
        XCTAssertTrue(worktree.branchMismatchServices.isEmpty)
        XCTAssertEqual(worktree.setupPlan.map(\.action), [.skip])
        XCTAssertEqual(worktree.setupPlan.first?.currentBranch, "dev")
        XCTAssertTrue(worktree.setupPlan.first?.reason.contains("目标分支 feature/worktree 可用") ?? false)
        XCTAssertNotEqual(stage.id, .worktreeSetup)
    }

    func testWorktreeSetupEvidenceCreatesMissingWorktreeWhenSourceCurrentBranchDiffersButTargetExists() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "worktree-source-current-branch-differs",
            branch: "feature/worktree",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "main",
                    worktree: "missing",
                    gitSummary: "source current: main; target branch available: feature/worktree",
                    worktreeExists: false,
                    sourceExists: true
                )
            ]
        )
        let worktree = WorktreeSetupEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: worktree
        )

        XCTAssertEqual(worktree.status, .next)
        XCTAssertTrue(worktree.branchMismatchServices.isEmpty)
        XCTAssertEqual(worktree.setupPlan.map(\.action), [.create])
        XCTAssertEqual(worktree.setupPlan.first?.currentBranch, "main")
        XCTAssertEqual(stage.id, .worktreeSetup)
    }

    func testWorktreeSetupEvidenceBlocksMissingSourceRepos() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "worktree-source-missing",
            branch: "feature/worktree",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/worktree",
                    worktree: "missing",
                    gitSummary: "source missing",
                    worktreeExists: false,
                    sourceExists: false
                )
            ]
        )
        let worktree = WorktreeSetupEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: worktree
        )

        XCTAssertEqual(worktree.status, .blocked)
        XCTAssertEqual(worktree.missingSourceServices, ["order"])
        XCTAssertEqual(worktree.setupPlan.map(\.action), [.blocked])
        XCTAssertFalse(worktree.setupPlan.first?.sourceAvailable ?? true)
        XCTAssertEqual(worktree.mutationPolicy.blockedServices, ["order"])
        XCTAssertTrue(worktree.mutationPolicy.blockerReasons.contains { $0.contains("source repo") })
        XCTAssertFalse(worktree.mutationPolicy.canRequestConfirmation)
        XCTAssertEqual(stage.id, .worktreeSetup)
        XCTAssertEqual(stage.primaryAction, .document("services"))
    }

    func testWorktreeSetupEvidenceAllowsReadyWorktreesPastSetupGate() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "worktree-ready",
            branch: "feature/worktree",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "origin/feature/worktree",
                    worktree: "ready",
                    gitSummary: "clean",
                    worktreeExists: true,
                    sourceExists: true
                )
            ]
        )
        let worktree = WorktreeSetupEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: worktree
        )

        XCTAssertEqual(worktree.status, .ready)
        XCTAssertTrue(worktree.missingServices.isEmpty)
        XCTAssertTrue(worktree.branchMismatchServices.isEmpty)
        XCTAssertEqual(worktree.setupPlan.map(\.action), [.skip])
        XCTAssertEqual(worktree.mutationPolicy.skippedServices, ["order"])
        XCTAssertFalse(worktree.mutationPolicy.canRequestConfirmation)
        XCTAssertNotEqual(stage.id, .worktreeSetup)
    }

    func testWorktreeSetupRecoveryActionsClassifyMissingSourceRepo() {
        let response = setupWorktreeResponse(
            failed: [
                WorktreeSetupResult(
                    service: "order",
                    sourcePath: "/source/order",
                    worktreePath: "/workspace/repos/order",
                    status: "failed",
                    detail: "source repository does not exist"
                )
            ]
        )

        let actions = WorktreeSetupRecoveryAction.actions(for: response)

        XCTAssertEqual(actions.count, 1)
        XCTAssertEqual(actions.first?.serviceName, "order")
        XCTAssertEqual(actions.first?.document, .services)
        XCTAssertEqual(actions.first?.status, .blocked)
        XCTAssertTrue(actions.first?.detail.contains("/source/order") ?? false)
    }

    func testWorktreeSetupRecoveryActionsClassifyFetchFailure() {
        let response = setupWorktreeResponse(
            failed: [
                WorktreeSetupResult(
                    service: "store-cashier",
                    sourcePath: "/source/store-cashier",
                    worktreePath: "/workspace/repos/store-cashier",
                    status: "failed",
                    detail: "git fetch failed: remote rejected"
                )
            ]
        )

        let actions = WorktreeSetupRecoveryAction.actions(for: response)

        XCTAssertEqual(actions.first?.document, .branches)
        XCTAssertEqual(actions.first?.systemImage, "arrow.triangle.branch")
        XCTAssertTrue(actions.first?.title.contains("Fetch") ?? false)
    }

    func testWorktreeSetupRecoveryActionsRouteCleanResultToLocalCheck() {
        let response = setupWorktreeResponse(
            created: [
                WorktreeSetupResult(
                    service: "order",
                    sourcePath: "/source/order",
                    worktreePath: "/workspace/repos/order",
                    status: "created",
                    detail: "worktree created"
                )
            ]
        )

        let actions = WorktreeSetupRecoveryAction.actions(for: response)

        XCTAssertEqual(actions.map(\.id), ["run-local-check"])
        XCTAssertNil(actions.first?.document)
        XCTAssertEqual(actions.first?.status, .next)
    }

    func testNativeWorktreeSetupStoreCreatesAndSkipsLocalWorktrees() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-worktree-setup-\(UUID().uuidString)")
        let remote = root.appendingPathComponent("remote-order.git")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let source = sourceRoot.appendingPathComponent("order")
        let workspace = root.appendingPathComponent("workspace")
        let auditRoot = root.appendingPathComponent("audit")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try runGit(["init", "--bare", remote.path], in: root)
        try runGit(["clone", remote.path, source.path], in: root)
        try runGit(["config", "user.email", "nexus@example.com"], in: source)
        try runGit(["config", "user.name", "Nexus Test"], in: source)
        try "demo\n".write(to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: source)
        try runGit(["commit", "-m", "init"], in: source)
        try runGit(["branch", "feature/native-setup"], in: source)
        try runGit(["push", "origin", "HEAD:main"], in: source)
        try runGit(["push", "origin", "feature/native-setup"], in: source)

        let response = try NativeWorktreeSetupStore.setup(
            request: SetupWorktreesRequest(
                workspacePath: workspace.path,
                sourceReposRoot: sourceRoot.path,
                services: ["order"],
                targetBranch: "feature/native-setup",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        )
        let firstEvents = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertEqual(response.created.map(\.service), ["order"])
        XCTAssertTrue(response.skipped.isEmpty)
        XCTAssertTrue(response.failed.isEmpty)
        XCTAssertTrue(response.command.contains("git -C"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("repos/order/.git").path))
        XCTAssertEqual(response.auditEventID, firstEvents.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(firstEvents.first?.action, "worktree_setup.executed")
        XCTAssertEqual(firstEvents.first?.actor, "Nexus Test")
        XCTAssertEqual(firstEvents.first?.metadata["created"], "1")
        XCTAssertEqual(firstEvents.first?.metadata["createdServices"], "order")

        let second = try NativeWorktreeSetupStore.setup(
            request: SetupWorktreesRequest(
                workspacePath: workspace.path,
                sourceReposRoot: sourceRoot.path,
                services: ["order"],
                targetBranch: "feature/native-setup",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        )
        let secondEvents = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertTrue(second.created.isEmpty)
        XCTAssertEqual(second.skipped.map(\.service), ["order"])
        XCTAssertTrue(second.failed.isEmpty)
        XCTAssertEqual(second.auditEventID, secondEvents.first?.id)
        XCTAssertEqual(second.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(secondEvents.first?.metadata["created"], "0")
        XCTAssertEqual(secondEvents.first?.metadata["skipped"], "1")
        XCTAssertEqual(secondEvents.first?.metadata["skippedServices"], "order")
    }

    func testNativeWorktreeSetupStorePreservesGitResultWhenAuditWriteFails() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-worktree-audit-failure-\(UUID().uuidString)")
        let remote = root.appendingPathComponent("remote-order.git")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let source = sourceRoot.appendingPathComponent("order")
        let workspace = root.appendingPathComponent("workspace")
        let invalidAuditRoot = root.appendingPathComponent("audit-root-file")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try runGit(["init", "--bare", remote.path], in: root)
        try runGit(["clone", remote.path, source.path], in: root)
        try runGit(["config", "user.email", "nexus@example.com"], in: source)
        try runGit(["config", "user.name", "Nexus Test"], in: source)
        try "demo\n".write(to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: source)
        try runGit(["commit", "-m", "init"], in: source)
        try runGit(["branch", "feature/native-audit-failure"], in: source)
        try runGit(["push", "origin", "HEAD:main"], in: source)
        try runGit(["push", "origin", "feature/native-audit-failure"], in: source)
        try "not a directory\n".write(to: invalidAuditRoot, atomically: true, encoding: .utf8)

        let plan = try NativeWorktreeSetupStore.makePlan(
            request: SetupWorktreesRequest(
                workspacePath: workspace.path,
                sourceReposRoot: sourceRoot.path,
                services: ["order"],
                targetBranch: "feature/native-audit-failure",
                confirmed: false,
                auditRoot: invalidAuditRoot.path,
                actor: "Nexus Test"
            )
        )
        let response = try NativeWorktreeSetupStore.setup(plan: plan, confirmed: true)

        XCTAssertEqual(response.created.map(\.service), ["order"])
        XCTAssertTrue(response.skipped.isEmpty)
        XCTAssertTrue(response.failed.isEmpty)
        XCTAssertNil(response.auditEventID)
        XCTAssertNil(response.auditEventPath)
        XCTAssertTrue(response.auditError?.contains("audit-root-file") == true)
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("repos/order/.git").path))
    }

    func testNativeWorktreeSetupStoreRejectsChangedConfirmedBranchBeforeMutation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-worktree-stale-plan-\(UUID().uuidString)")
        let remote = root.appendingPathComponent("remote-order.git")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let source = sourceRoot.appendingPathComponent("order")
        let workspace = root.appendingPathComponent("workspace")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try runGit(["init", "--bare", remote.path], in: root)
        try runGit(["clone", remote.path, source.path], in: root)
        try runGit(["config", "user.email", "nexus@example.com"], in: source)
        try runGit(["config", "user.name", "Nexus Test"], in: source)
        try "first\n".write(to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: source)
        try runGit(["commit", "-m", "first"], in: source)
        try runGit(["branch", "feature/native-stale-plan"], in: source)
        try runGit(["push", "origin", "HEAD:main"], in: source)
        try runGit(["push", "origin", "feature/native-stale-plan"], in: source)

        let plan = try NativeWorktreeSetupStore.makePlan(
            request: SetupWorktreesRequest(
                workspacePath: workspace.path,
                sourceReposRoot: sourceRoot.path,
                services: ["order"],
                targetBranch: "feature/native-stale-plan",
                confirmed: false
            )
        )
        XCTAssertEqual(plan.services, ["order"])
        XCTAssertEqual(plan.targetBranch, "feature/native-stale-plan")
        XCTAssertNotNil(plan.sourceRevisions["order"])

        try "second\n".write(to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: source)
        try runGit(["commit", "-m", "second"], in: source)
        try runGit(["branch", "-f", "feature/native-stale-plan", "HEAD"], in: source)

        XCTAssertThrowsError(
            try NativeWorktreeSetupStore.setup(plan: plan, confirmed: true)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("repos").path))
    }

    func testNativeWorktreeSetupStoreRejectsTargetCreatedAfterConfirmation() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-worktree-target-conflict-\(UUID().uuidString)")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let source = sourceRoot.appendingPathComponent("order")
        let workspace = root.appendingPathComponent("workspace")
        let target = workspace.appendingPathComponent("repos/order")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try runGit(["init"], in: source)
        try runGit(["config", "user.email", "nexus@example.com"], in: source)
        try runGit(["config", "user.name", "Nexus Test"], in: source)
        try "demo\n".write(to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: source)
        try runGit(["commit", "-m", "init"], in: source)
        try runGit(["branch", "feature/native-target-conflict"], in: source)

        let plan = try NativeWorktreeSetupStore.makePlan(
            request: SetupWorktreesRequest(
                workspacePath: workspace.path,
                sourceReposRoot: sourceRoot.path,
                services: ["order"],
                targetBranch: "feature/native-target-conflict",
                confirmed: false
            )
        )
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try NativeWorktreeSetupStore.setup(plan: plan, confirmed: true)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: target.appendingPathComponent(".git").path))
    }

    func testNativeWorktreeSetupStoreRequiresConfirmation() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-worktree-unconfirmed-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: workspace)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try NativeWorktreeSetupStore.setup(
                request: SetupWorktreesRequest(
                    workspacePath: workspace.path,
                    sourceReposRoot: "/tmp/source-repos",
                    services: ["order"],
                    targetBranch: "feature/native-setup",
                    confirmed: false
                )
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("explicit confirmation"))
        }
    }

    func testNativeWorktreeSetupStoreRejectsNoServicesBeforeCreatingReposDirectory() throws {
        let workspace = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-worktree-empty-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: workspace)
        }
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)

        XCTAssertThrowsError(
            try NativeWorktreeSetupStore.setup(
                request: SetupWorktreesRequest(
                    workspacePath: workspace.path,
                    sourceReposRoot: "/tmp/source-repos",
                    services: [],
                    targetBranch: "feature/native-setup",
                    confirmed: true
                )
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("no services"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("repos").path))
    }

    func testNativeWorktreeSetupStoreRejectsLinkedWorkspaceAndReposRoots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-worktree-linked-roots-\(UUID().uuidString)")
        let realWorkspace = root.appendingPathComponent("real-workspace")
        let linkedWorkspace = root.appendingPathComponent("linked-workspace")
        let workspaceWithLinkedRepos = root.appendingPathComponent("workspace-linked-repos")
        let externalRepos = root.appendingPathComponent("external-repos")
        let sourceRoot = root.appendingPathComponent("source-repos")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        for directory in [realWorkspace, workspaceWithLinkedRepos, externalRepos, sourceRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: linkedWorkspace, withDestinationURL: realWorkspace)
        try FileManager.default.createSymbolicLink(
            at: workspaceWithLinkedRepos.appendingPathComponent("repos"),
            withDestinationURL: externalRepos
        )

        for workspacePath in [linkedWorkspace.path, workspaceWithLinkedRepos.path] {
            XCTAssertThrowsError(
                try NativeWorktreeSetupStore.setup(
                    request: SetupWorktreesRequest(
                        workspacePath: workspacePath,
                        sourceReposRoot: sourceRoot.path,
                        services: ["order"],
                        targetBranch: "feature/native-setup",
                        confirmed: true
                    )
                )
            ) { error in
                XCTAssertTrue(error.localizedDescription.contains("symbolic links"))
            }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: realWorkspace.appendingPathComponent("repos").path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: externalRepos.path).isEmpty)
    }

    func testNativeWorktreeSetupStoreRejectsLinkedTargetInsteadOfSkippingIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-worktree-linked-target-\(UUID().uuidString)")
        let workspace = root.appendingPathComponent("workspace")
        let repos = workspace.appendingPathComponent("repos")
        let externalTarget = root.appendingPathComponent("external-order")
        let linkedTarget = repos.appendingPathComponent("order")
        let sourceRoot = root.appendingPathComponent("source-repos")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        for directory in [repos, externalTarget, sourceRoot] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try FileManager.default.createSymbolicLink(at: linkedTarget, withDestinationURL: externalTarget)

        let response = try NativeWorktreeSetupStore.setup(
            request: SetupWorktreesRequest(
                workspacePath: workspace.path,
                sourceReposRoot: sourceRoot.path,
                services: ["order"],
                targetBranch: "feature/native-setup",
                confirmed: true
            )
        )

        XCTAssertTrue(response.created.isEmpty)
        XCTAssertTrue(response.skipped.isEmpty)
        XCTAssertEqual(response.failed.map(\.service), ["order"])
        XCTAssertTrue(response.failed.first?.detail.contains("symbolic link") == true)
    }

    @MainActor
    func testNativeStoresCanProveEndToEndWorkspaceLifecycle() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-e2e-lifecycle-\(UUID().uuidString)")
        let remote = root.appendingPathComponent("remote-order.git")
        let sourceRoot = root.appendingPathComponent("source-repos")
        let source = sourceRoot.appendingPathComponent("order")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let auditRoot = root.appendingPathComponent("audit")
        let branch = "feature/native-e2e"
        let folder = "2026-06-29-native-e2e"
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try FileManager.default.createDirectory(at: sourceRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: workspacesRoot, withIntermediateDirectories: true)
        try runGit(["init", "--bare", remote.path], in: root)
        try runGit(["clone", remote.path, source.path], in: root)
        try runGit(["config", "user.email", "nexus@example.com"], in: source)
        try runGit(["config", "user.name", "Nexus Test"], in: source)
        try "native e2e\n".write(to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: source)
        try runGit(["commit", "-m", "init"], in: source)
        try runGit(["branch", branch], in: source)
        try runGit(["push", "origin", "HEAD:main"], in: source)
        try runGit(["push", "origin", branch], in: source)

        let created = try NativeWorkspaceCreationStore.create(
            request: CreateWorkspaceRequest(
                name: "Native E2E Lifecycle",
                folder: folder,
                workspacesRoot: workspacesRoot.path,
                sourceReposRoot: sourceRoot.path,
                services: ["order"],
                targetBranch: branch,
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        )
        let workspaceURL = URL(fileURLWithPath: created.path)
        let demandURL = workspaceURL.appendingPathComponent("需求")

        _ = try NativeDemandIntakeStore.initialize(
            workspacePath: workspaceURL.path,
            demandName: "Native E2E Lifecycle",
            lanhuLink: "https://lanhu.example/native-e2e",
            notes: "Build one real lifecycle proof from native stores.",
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        try """
        # 需求确认卡

        - 真实需求目标：Native stores 端到端写入生命周期证据。
        - 用户流程：创建工作区、冻结范围、转入任务、完成交付并归档。
        - 验收标准：AppState nativeLifecycleProofAvailable 返回 true。
        """.write(to: demandURL.appendingPathComponent("requirement.md"), atomically: true, encoding: .utf8)
        try "# 待确认问题\n\n## P0 阻塞开发\n\n- [x] 无 P0 待确认项。\n".write(
            to: demandURL.appendingPathComponent("questions.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # 本次开发范围

        ## 已确认并实现

        - 用 Native stores 写入生命周期证据。

        ## 暂不实现

        - 不触发真实 GitHub PR 或 Apple notarization。

        ## 仍待确认

        - 无 P0 待确认项。

        ## 进入开发条件

        - [ ] 本文件已冻结本次开发范围。
        """.write(to: demandURL.appendingPathComponent("scope.md"), atomically: true, encoding: .utf8)
        try """
        # 需求列表

        | 需求点 | 状态 | 优先级 | 来源 | 说明 |
        | --- | --- | --- | --- | --- |
        | 建立 Native 生命周期证据 | 待办 | P0 | 路线图 | create -> demand -> worktree -> delivery -> archive |
        """.write(to: demandURL.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8)
        try "# 需求交付\n\n- 预检完成，进入 Native lifecycle proof。\n".write(
            to: demandURL.appendingPathComponent("delivery.md"),
            atomically: true,
            encoding: .utf8
        )

        var workspace = try scannedWorkspace(
            folder: folder,
            workspacesRoot: workspacesRoot,
            sourceRoot: sourceRoot
        )
        let demandStatus = try NativeDemandIntakeStore.status(workspacePath: workspaceURL.path)
        let scopeEvidence = ScopeFreezeEvidence.resolve(status: demandStatus, workspace: workspace)
        let scopePlan = ScopeFreezeWritePlan.resolve(workspace: workspace, evidence: scopeEvidence)
        XCTAssertTrue(scopePlan.canWrite)
        _ = try NativeScopeFreezeStore.write(
            plan: scopePlan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )

        let transferPlan = DemandTaskTransferPlan.resolve(workspace: workspace, status: demandStatus)
        XCTAssertEqual(transferPlan.transferableItems.map(\.title), ["建立 Native 生命周期证据"])
        let transferred = try NativeDemandTaskTransferStore.transfer(
            plan: transferPlan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        XCTAssertEqual(transferred.transferredCount, 1)

        let worktree = try NativeWorktreeSetupStore.setup(
            request: SetupWorktreesRequest(
                workspacePath: workspaceURL.path,
                sourceReposRoot: sourceRoot.path,
                services: ["order"],
                targetBranch: branch,
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        )
        XCTAssertEqual(worktree.created.map(\.service), ["order"])

        workspace = try scannedWorkspace(
            folder: folder,
            workspacesRoot: workspacesRoot,
            sourceRoot: sourceRoot
        )
        XCTAssertEqual(workspace.tasks.count, 7 + transferred.transferredCount)
        for task in workspace.tasks {
            _ = try NativeWorkspaceTaskStore.update(
                request: UpdateWorkspaceTaskRequest(
                    workspacePath: workspaceURL.path,
                    taskId: task.id,
                    status: "已完成",
                    detail: "Native E2E proof completed.",
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                expectedTitle: task.title,
                expectedStatus: task.status,
                expectedDetail: task.detail,
                expectedPriority: task.priority,
                expectedSourceLine: task.sourceLine
            )
        }

        workspace = try scannedWorkspace(folder: folder, workspacesRoot: workspacesRoot, sourceRoot: sourceRoot)
        XCTAssertTrue(workspace.services.allSatisfy { $0.sourceExists && $0.worktreeExists })
        XCTAssertTrue(workspace.tasks.allSatisfy { !$0.isActive })
        XCTAssertTrue(workspace.risks.isEmpty)

        let deliveryGate = DeliveryGateEvidence.resolve(workspace: workspace)
        let deliveryPlan = DeliveryRecordWritePlan.resolve(workspace: workspace, gate: deliveryGate)
        XCTAssertTrue(deliveryPlan.canWrite)
        _ = try NativeDeliveryRecordStore.appendDeliverySnapshot(
            plan: deliveryPlan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )

        let validation = ValidationPrEvidence.resolve(workspace: workspace, deliveryGate: deliveryGate)
        let validationPlan = ValidationPrWritePlan.resolve(workspace: workspace, evidence: validation)
        XCTAssertTrue(validationPlan.canWrite)
        _ = try NativeDeliveryRecordStore.appendValidationPrSnapshot(
            plan: validationPlan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )

        let archive = ArchiveGateEvidence.resolve(workspace: workspace, deliveryGate: deliveryGate, validationPr: validation)
        let archivePlan = ArchiveChecklistWritePlan.resolve(workspace: workspace, archiveGate: archive)
        XCTAssertTrue(archivePlan.canWrite)
        _ = try NativeDeliveryRecordStore.appendArchiveChecklist(
            plan: archivePlan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )

        _ = try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: "archived",
                focus: "Native lifecycle proof captured",
                nextAction: "Keep delivery record as audit evidence",
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedState: workspace.lifecycle.stage
        )

        let archived = try scannedWorkspace(folder: folder, workspacesRoot: workspacesRoot, sourceRoot: sourceRoot)
        let deliveryRecord = try String(contentsOf: workspaceURL.appendingPathComponent("交付记录.md"), encoding: .utf8)
        let actions = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 20).map(\.action)

        XCTAssertEqual(archived.state, .archived)
        XCTAssertEqual(archived.lifecycle.stage, "archived")
        XCTAssertTrue(archived.documentLinks["delivery-cn"]?.hasSuffix("/交付记录.md") == true)
        XCTAssertTrue(archived.services.allSatisfy { $0.sourceExists && $0.worktreeExists })
        XCTAssertTrue(archived.tasks.allSatisfy { !$0.isActive })
        XCTAssertTrue(archived.risks.isEmpty)
        XCTAssertTrue(deliveryRecord.contains("## Nexus Delivery Gate Snapshot"))
        XCTAssertTrue(deliveryRecord.contains("## Nexus Validation / PR Snapshot"))
        XCTAssertTrue(deliveryRecord.contains("## Nexus Archive Checklist"))
        XCTAssertTrue(actions.contains("workspace.created"))
        XCTAssertTrue(actions.contains("scope.freeze_confirmed"))
        XCTAssertTrue(actions.contains("demand_tasks.transferred"))
        XCTAssertTrue(actions.contains("demand_intake.initialized"))
        XCTAssertTrue(actions.contains("worktree_setup.executed"))
        XCTAssertTrue(actions.contains("workspace_task.updated"))
        XCTAssertTrue(actions.contains("delivery_record.snapshot_appended"))
        XCTAssertTrue(actions.contains("validation_pr.snapshot_appended"))
        XCTAssertTrue(actions.contains("archive_checklist.snapshot_appended"))
        XCTAssertTrue(actions.contains("workspace_lifecycle.updated"))
        let proofEvents = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 40)
        XCTAssertTrue(appStateForAutomationTests(workspaces: [archived]).nativeLifecycleProofAvailable(auditEvents: proofEvents))
        XCTAssertFalse(appStateForAutomationTests(workspaces: [archived]).nativeLifecycleProofBundleAvailable(auditEvents: proofEvents))
        XCTAssertThrowsError(
            try NativeLifecycleProofBundleStore.write(
                workspace: archived,
                auditEvents: proofEvents,
                confirmed: false,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        )

        let proofBundleResponse = try NativeLifecycleProofBundleStore.write(
            workspace: archived,
            auditEvents: proofEvents,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        let proofBundleData = try Data(contentsOf: URL(fileURLWithPath: proofBundleResponse.path))
        let proofBundle = try JSONDecoder().decode(NativeLifecycleProofBundle.self, from: proofBundleData)
        let eventsAfterProofExport = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 50)
        let actionsAfterProofExport = eventsAfterProofExport.map(\.action)
        let proofExportEvent = eventsAfterProofExport.first { $0.action == "native_lifecycle_proof.exported" }

        XCTAssertTrue(proofBundleResponse.ready)
        XCTAssertEqual(proofBundleResponse.auditEventID, proofExportEvent?.id)
        XCTAssertEqual(proofBundleResponse.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertTrue(proofBundle.ready)
        XCTAssertEqual(proofBundle.workspace.lifecycleStage, "archived")
        XCTAssertEqual(proofBundle.proof.status, WorkflowPathStatus.ready.rawValue)
        XCTAssertTrue(proofBundle.evidenceFiles.allSatisfy(\.exists))
        XCTAssertTrue(proofBundle.evidenceFiles.allSatisfy { ($0.sizeBytes ?? 0) > 0 })
        XCTAssertTrue(proofBundle.evidenceFiles.allSatisfy { $0.sha256?.count == 64 })
        XCTAssertTrue(proofBundle.missingEvidenceFiles.isEmpty)
        XCTAssertTrue(proofBundle.unverifiedEvidenceFiles?.isEmpty == true)
        XCTAssertEqual(proofBundle.proof.requiredAuditActions, NativeLifecycleProofEvidence.requiredAuditActions)
        XCTAssertTrue(proofBundle.auditChain.map(\.action).contains("workspace.created"))
        XCTAssertTrue(proofBundle.auditChain.map(\.action).contains("workspace_lifecycle.updated"))
        XCTAssertTrue(actionsAfterProofExport.contains("native_lifecycle_proof.exported"))
        XCTAssertEqual(proofExportEvent?.metadata["bundleSHA256"], NativeLifecycleProofBundle.sha256Hex(data: proofBundleData))
        XCTAssertEqual(proofExportEvent?.metadata["unverifiedEvidenceFileCount"], "0")
        let invalidProofAuditRoot = root.appendingPathComponent("invalid-proof-audit")
        try "not a directory".write(to: invalidProofAuditRoot, atomically: true, encoding: .utf8)
        let proofAuditFailure = try NativeLifecycleProofBundleStore.write(
            workspace: archived,
            auditEvents: proofEvents,
            confirmed: true,
            auditRoot: invalidProofAuditRoot.path,
            actor: "Nexus Test"
        )
        XCTAssertTrue(FileManager.default.fileExists(atPath: proofAuditFailure.path))
        XCTAssertNotNil(proofAuditFailure.auditError)
        let proofAppState = appStateForAutomationTests(workspaces: [archived])
        XCTAssertTrue(proofAppState.nativeLifecycleProofBundleAvailable(auditEvents: proofEvents))
        let distributionEvidence = proofAppState.nativeDistributionReadinessEvidence(
            repositoryRoot: root.path,
            auditEvents: proofEvents
        )
        XCTAssertFalse(
            distributionEvidence.checks.first { $0.requirement == .legacyDeletion }?.detail
                .contains("No real archived workspace lifecycle proof") == true
        )

        let appState = AppState(
            workspaces: [archived],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: root.appendingPathComponent("docs").path,
            defaults: UserDefaults(suiteName: "NexusAppTests-\(UUID().uuidString)")!
        )
        appState.requestNativeLifecycleProofBundleExport(in: archived, auditEvents: proofEvents)
        XCTAssertEqual(appState.pendingLifecycleProofBundleExport?.path, proofBundleResponse.path)
        XCTAssertTrue(appState.pendingLifecycleProofBundleExport?.canWrite == true)

        await appState.confirmPendingNativeLifecycleProofBundleExport(confirmed: false, auditRoot: auditRoot.path)
        XCTAssertEqual(appState.lastError, "需要确认后才会导出生命周期证据包。")

        await appState.confirmPendingNativeLifecycleProofBundleExport(confirmed: true, auditRoot: auditRoot.path)
        let actionsAfterAppStateExport = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 60).map(\.action)

        XCTAssertNil(appState.lastError)
        XCTAssertNil(appState.pendingLifecycleProofBundleExport)
        XCTAssertEqual(appState.localWriteFeedback?.documentPath, proofBundleResponse.path)
        XCTAssertEqual(appState.localWriteFeedback?.documentLabel, "打开证据包")
        XCTAssertEqual(appState.selectedWorkspaceID, archived.id)
        XCTAssertTrue(actionsAfterAppStateExport.contains("native_lifecycle_proof.exported"))

        _ = try NativeWorkspaceLifecycleStore.update(
            request: UpdateWorkspaceLifecycleRequest(
                workspacePath: workspaceURL.path,
                state: LifecycleTransition.restoreDevelopment.state,
                focus: LifecycleTransition.restoreDevelopment.focus,
                nextAction: LifecycleTransition.restoreDevelopment.nextAction,
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            ),
            expectedState: "archived"
        )

        let restored = try scannedWorkspace(folder: folder, workspacesRoot: workspacesRoot, sourceRoot: sourceRoot)
        let actionsAfterRestore = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 30).map(\.action)
        let restoredSummary = WorkspaceListSummary(workspaces: [restored])

        XCTAssertEqual(restored.state, .developing)
        XCTAssertEqual(restored.lifecycle.stage, "developing")
        XCTAssertFalse(restored.isArchived)
        XCTAssertEqual(restored.lifecycleTransitions, [.delivery, .blocked])
        XCTAssertEqual(restoredSummary.activeWorkspaceCount, 1)
        XCTAssertEqual(restoredSummary.archivedWorkspaceCount, 0)
        XCTAssertEqual(actionsAfterRestore.filter { $0 == "workspace_lifecycle.updated" }.count, 2)
        XCTAssertFalse(appStateForAutomationTests(workspaces: [restored]).nativeLifecycleProofAvailable())
    }

    func testNativeLifecycleProofBundleDecodesLegacyEvidenceFileShape() throws {
        let json = """
        {
          "schemaVersion" : 1,
          "generatedAt" : "2026-06-30T00:00:00Z",
          "workspace" : {
            "id" : "legacy-proof",
            "name" : "Legacy Proof",
            "folder" : "legacy-proof",
            "path" : "/tmp/legacy-proof",
            "state" : "archived",
            "lifecycleStage" : "archived",
            "targetBranch" : "main",
            "serviceCount" : 1,
            "activeTaskCount" : 0,
            "riskCount" : 0
          },
          "proof" : {
            "ready" : true,
            "status" : "ready",
            "detail" : "ready",
            "orderedActions" : ["workspace.created"],
            "requiredAuditActions" : ["workspace.created"],
            "missingActions" : [],
            "missingEvidenceFiles" : []
          },
          "evidenceFiles" : [
            {
              "relativePath" : "workspace.md",
              "path" : "/tmp/legacy-proof/workspace.md",
              "exists" : true
            }
          ],
          "auditChain" : [],
          "missingEvidenceFiles" : []
        }
        """
        let bundle = try JSONDecoder().decode(NativeLifecycleProofBundle.self, from: Data(json.utf8))

        XCTAssertTrue(bundle.ready)
        XCTAssertNil(bundle.unverifiedEvidenceFiles)
        XCTAssertEqual(bundle.evidenceFiles.first?.relativePath, "workspace.md")
        XCTAssertNil(bundle.evidenceFiles.first?.sizeBytes)
        XCTAssertNil(bundle.evidenceFiles.first?.sha256)
    }

    func testDevelopmentTaskEvidenceRoutesNextActiveTask() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "development-next-task",
            tasks: [
                WorkspaceTask(
                    id: "later-low",
                    title: "Later low task",
                    status: "todo",
                    detail: "Can wait",
                    priority: "low",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 30
                ),
                WorkspaceTask(
                    id: "first-high",
                    title: "Implement first high priority task",
                    status: "doing",
                    detail: "Start here",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 12
                ),
                WorkspaceTask(
                    id: "second-high",
                    title: "Second high priority task",
                    status: "todo",
                    detail: "After first",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 18
                )
            ]
        )
        let evidence = DevelopmentTaskEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: evidence
        )

        XCTAssertEqual(evidence.status, .next)
        XCTAssertEqual(evidence.nextTask?.id, "first-high")
        XCTAssertEqual(evidence.taskValue, "开 3")
        XCTAssertEqual(evidence.taskPlan.map(\.action), [.continueTask, .queued, .queued])
        XCTAssertEqual(evidence.taskPlan.first?.taskID, "first-high")
        XCTAssertTrue(evidence.taskPlan.first?.writebackHint.contains("已完成") ?? false)
        XCTAssertEqual(stage.id, .development)
        XCTAssertEqual(stage.primaryAction, .task("first-high"))
        XCTAssertTrue(stage.reason.contains("Implement first high priority task"))
    }

    func testDevelopmentTaskEvidenceKeepsIntakeTasksOutOfExecutionQueue() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "development-source-roles",
            path: "/tmp/development-source-roles",
            tasks: [
                WorkspaceTask(
                    id: "root-task",
                    title: "Implement root execution task",
                    status: "todo",
                    detail: "Only root tasks.md should execute.",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 7
                )
            ]
        )

        let evidence = DevelopmentTaskEvidence.resolve(workspace: workspace)

        XCTAssertEqual(evidence.sources.map(\.role), [.executionQueue, .intakeEvidence])
        XCTAssertEqual(evidence.executionSources.map(\.path), ["/tmp/development-source-roles/tasks.md"])
        XCTAssertEqual(evidence.intakeEvidenceSources.map(\.path), ["/tmp/development-source-roles/需求/tasks.md"])
        XCTAssertTrue(evidence.executionSources.allSatisfy(\.participatesInExecutionQueue))
        XCTAssertTrue(evidence.intakeEvidenceSources.allSatisfy { !$0.participatesInExecutionQueue })
        XCTAssertTrue(evidence.evidence.contains("需求/tasks.md"))
        XCTAssertEqual(evidence.taskPlan.map(\.taskID), ["root-task"])
    }

    func testMainStageDoesNotTrustReadyDemandHealthCheckWhenWorkspaceReadFails() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-missing-demand-\(UUID().uuidString)")
            .path
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "demand-read-failure",
            path: missingPath,
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "demand-intake",
                    label: "需求预检",
                    detail: "健康检查报告需求预检已就绪。",
                    status: "pass",
                    action: "demandIntake"
                )
            ]
        )

        let stage = workspace.mainStage()

        XCTAssertEqual(stage.id, .demandIntake)
        XCTAssertEqual(stage.status, .pending)
        XCTAssertEqual(stage.primaryAction, .demandIntake)
    }

    func testMainStagePreservesBlockedDemandHealthCheckWhenWorkspaceReadFails() {
        let missingPath = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-missing-blocked-demand-\(UUID().uuidString)")
            .path
        let blockerDetail = "需求预检读取失败：工作区路径不可用。"
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "blocked-demand-read-failure",
            path: missingPath,
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "demand-intake",
                    label: "需求预检",
                    detail: blockerDetail,
                    status: "blocked",
                    action: "demandIntake"
                )
            ]
        )

        let stage = workspace.mainStage()

        XCTAssertEqual(stage.id, .demandIntake)
        XCTAssertEqual(stage.status, .blocked)
        XCTAssertEqual(stage.primaryAction, .demandIntake)
        XCTAssertTrue(stage.reason.contains(blockerDetail))
    }

    func testDevelopmentTaskEvidenceBlocksOnBlockedTasks() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "development-blocked-task",
            tasks: [
                WorkspaceTask(
                    id: "blocked-task",
                    title: "Resolve approval blocker",
                    status: "blocked",
                    detail: "blocked by product confirmation",
                    priority: "low",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 8
                ),
                WorkspaceTask(
                    id: "active-task",
                    title: "Normal active task",
                    status: "todo",
                    detail: "Ready after blocker",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 9
                )
            ]
        )
        let evidence = DevelopmentTaskEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: evidence
        )

        XCTAssertEqual(evidence.status, .blocked)
        XCTAssertEqual(evidence.blockedTasks.map(\.id), ["blocked-task"])
        XCTAssertEqual(evidence.taskPlan.map(\.action), [.resolveBlocker, .queued])
        XCTAssertEqual(evidence.taskPlan.first?.taskID, "blocked-task")
        XCTAssertTrue(evidence.taskPlan.first?.reason.contains("阻塞") ?? false)
        XCTAssertEqual(stage.id, .development)
        XCTAssertEqual(stage.status, .blocked)
        XCTAssertEqual(stage.primaryAction, .task("blocked-task"))
    }

    func testDevelopmentTaskEvidenceLetsCleanTasksEnterDeliveryGate() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "development-clean-tasks",
            tasks: [
                WorkspaceTask(
                    id: "done-task",
                    title: "Done task",
                    status: "done",
                    detail: "Complete",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 4
                ),
                WorkspaceTask(
                    id: "deferred-task",
                    title: "Deferred task",
                    status: "延期",
                    detail: "deferred until later demand",
                    priority: "medium",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 5
                )
            ]
        )
        let evidence = DevelopmentTaskEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: evidence
        )

        XCTAssertEqual(evidence.status, .ready)
        XCTAssertNil(evidence.nextTask)
        XCTAssertEqual(evidence.doneTaskCount, 1)
        XCTAssertEqual(evidence.deferredTaskCount, 1)
        XCTAssertEqual(evidence.taskPlan.map(\.action), [.closed, .closed])
        XCTAssertTrue(evidence.taskPlan.contains { $0.writebackHint.contains("无需写回") })
        XCTAssertEqual(stage.id, .deliveryCheck)
    }

    func testDeliveryGateEvidenceRequiresLocalChecksBeforeDeliveryReady() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-local-check-pending"
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: DevelopmentTaskEvidence.resolve(workspace: workspace),
            deliveryGate: delivery
        )

        XCTAssertEqual(delivery.status, .pending)
        XCTAssertEqual(delivery.primaryAction, .localCheck)
        XCTAssertEqual(delivery.resolutionPlan.prefix(2).map(\.action), [.runCheck, .runCheck])
        XCTAssertEqual(delivery.resolutionPlan.first?.checkID, "delivery-record")
        XCTAssertTrue(delivery.resolutionPlan.first?.handoffHint.contains("运行本地检查") == true)
        XCTAssertEqual(stage.id, .deliveryCheck)
        XCTAssertEqual(stage.primaryAction, .localCheck)
    }

    func testDeliveryGateEvidenceBlocksMissingSqlArtifacts() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-sql-blocked",
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "交付记录声明 SQL 变更，但 sql/ 缺少回滚 SQL。", status: "fail", action: "sql")
            ]
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: DevelopmentTaskEvidence.resolve(workspace: workspace),
            deliveryGate: delivery
        )

        XCTAssertEqual(delivery.status, .blocked)
        XCTAssertEqual(delivery.primaryAction, .document("sql"))
        XCTAssertEqual(delivery.resolutionPlan.first?.action, .resolveBlocker)
        XCTAssertEqual(delivery.resolutionPlan.first?.checkID, "sql")
        XCTAssertTrue(delivery.resolutionPlan.first?.handoffHint.contains("回滚 SQL") == true)
        XCTAssertEqual(stage.id, .deliveryCheck)
        XCTAssertEqual(stage.status, .blocked)
        XCTAssertEqual(stage.primaryAction, .document("sql"))
    }

    func testDeliveryGateEvidenceBlocksHighRiskBeforeDelivery() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-risk-blocked",
            riskLevel: .high,
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "SQL 产物匹配。", status: "pass", action: "sql")
            ],
            risks: [
                RiskAlert(title: "高风险逻辑变更", detail: "结算链路需要复核。")
            ]
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: DevelopmentTaskEvidence.resolve(workspace: workspace),
            deliveryGate: delivery
        )

        XCTAssertEqual(delivery.status, .blocked)
        XCTAssertEqual(delivery.primaryAction, .riskPrompt)
        XCTAssertEqual(delivery.resolutionPlan.first?.action, .resolveBlocker)
        XCTAssertEqual(delivery.resolutionPlan.first?.checkID, "risks")
        XCTAssertTrue(delivery.resolutionPlan.first?.handoffHint.contains("风险结论") == true)
        XCTAssertEqual(stage.id, .deliveryCheck)
        XCTAssertEqual(stage.primaryAction, .riskPrompt)
    }

    func testDeliveryGateEvidenceAllowsReadyDeliveryToOpenRecord() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-ready",
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: DevelopmentTaskEvidence.resolve(workspace: workspace),
            deliveryGate: delivery
        )

        XCTAssertEqual(delivery.status, .ready)
        XCTAssertEqual(delivery.primaryAction, .document("delivery"))
        XCTAssertTrue(delivery.resolutionPlan.allSatisfy { $0.action == .passed })
        XCTAssertEqual(Array(delivery.resolutionPlan.map(\.checkID).prefix(3)), ["branch", "services", "tasks"])
        XCTAssertTrue(delivery.resolutionPlan.contains { $0.checkID == "delivery-record" && $0.handoffHint.contains("PR") })
        XCTAssertEqual(delivery.blockerCount, 0)
        XCTAssertEqual(stage.id, .archived)
        XCTAssertEqual(stage.primaryAction, .lifecycle(.delivery))
        XCTAssertFalse(stage.nextStageAllowed)
    }

    func testDeliveryRecordWritePlansCaptureStrictDocumentRevisions() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-delivery-revision-\(UUID().uuidString)")
        let missing = root.appendingPathComponent("missing")
        let regular = root.appendingPathComponent("regular")
        let linked = root.appendingPathComponent("linked")
        let external = root.appendingPathComponent("external.md")
        defer { try? FileManager.default.removeItem(at: root) }
        for directory in [missing, regular, linked] {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        let original = "# 交付记录\n\n人工记录。\n"
        try original.write(to: regular.appendingPathComponent("交付记录.md"), atomically: true, encoding: .utf8)
        try original.write(to: external, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: linked.appendingPathComponent("交付记录.md"),
            withDestinationURL: external
        )
        let healthChecks = [
            WorkspaceHealthCheck(
                id: "delivery-record",
                label: "交付记录",
                detail: "交付记录可用",
                status: "pass",
                action: "delivery"
            ),
            WorkspaceHealthCheck(
                id: "sql-directory",
                label: "SQL",
                detail: "未声明 SQL 变更。",
                status: "pass",
                action: "sql"
            )
        ]

        let missingWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-revision-missing",
            path: missing.path,
            healthChecks: healthChecks
        )
        let regularWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-revision-regular",
            path: regular.path,
            healthChecks: healthChecks
        )
        let linkedWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-revision-linked",
            path: linked.path,
            healthChecks: healthChecks
        )

        let missingPlan = DeliveryRecordWritePlan.resolve(
            workspace: missingWorkspace,
            gate: DeliveryGateEvidence.resolve(workspace: missingWorkspace)
        )
        let regularPlan = DeliveryRecordWritePlan.resolve(
            workspace: regularWorkspace,
            gate: DeliveryGateEvidence.resolve(workspace: regularWorkspace)
        )
        let linkedPlan = DeliveryRecordWritePlan.resolve(
            workspace: linkedWorkspace,
            gate: DeliveryGateEvidence.resolve(workspace: linkedWorkspace)
        )

        XCTAssertEqual(missingPlan.expectedRevision, .missing)
        guard case .regularUTF8(let sha256, let byteCount) = regularPlan.expectedRevision else {
            return XCTFail("expected regular UTF-8 revision")
        }
        XCTAssertEqual(sha256.count, 64)
        XCTAssertEqual(byteCount, original.data(using: .utf8)?.count)
        guard case .invalid(let reason) = linkedPlan.expectedRevision else {
            return XCTFail("expected invalid symlink revision")
        }
        XCTAssertTrue(reason.contains("not a regular file"))
        XCTAssertFalse(linkedPlan.canWrite)
        XCTAssertTrue(linkedPlan.summary.contains("not a regular file"))
        XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), original)
    }

    func testInvalidDeliveryRecordRevisionBlocksArchiveAndValidationPlans() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-delivery-revision-followup-\(UUID().uuidString)")
        let linked = root.appendingPathComponent("linked")
        let external = root.appendingPathComponent("external.md")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: linked, withIntermediateDirectories: true)
        let original = "# 交付记录\n\n人工记录。\n"
        try original.write(to: external, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(
            at: linked.appendingPathComponent("交付记录.md"),
            withDestinationURL: external
        )
        let healthChecks = [
            WorkspaceHealthCheck(
                id: "delivery-record",
                label: "交付记录",
                detail: "交付记录可用",
                status: "pass",
                action: "delivery"
            ),
            WorkspaceHealthCheck(
                id: "sql-directory",
                label: "SQL",
                detail: "未声明 SQL 变更。",
                status: "pass",
                action: "sql"
            )
        ]
        let linkedWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-revision-followup-linked",
            path: linked.path,
            healthChecks: healthChecks
        )

        let archivePlan = ArchiveChecklistWritePlan.resolve(
            workspace: linkedWorkspace,
            archiveGate: ArchiveGateEvidence(
                status: .next,
                title: "coverage gap",
                reason: "coverage gap",
                value: "coverage gap",
                evidence: [linked.appendingPathComponent("交付记录.md").path],
                checks: [],
                confirmationPlan: [],
                primaryActionLabel: "归档",
                primaryActionSystemImage: "archivebox",
                primaryAction: .lifecycle(.archived),
                blockerCount: 0,
                warningCount: 0
            )
        )
        guard case .invalid(let archiveReason) = archivePlan.expectedRevision else {
            return XCTFail("expected invalid archive revision")
        }
        XCTAssertTrue(archiveReason.contains("not a regular file"))
        XCTAssertFalse(archivePlan.canWrite)
        XCTAssertTrue(archivePlan.summary.contains("not a regular file"))

        let validationPlan = ValidationPrWritePlan.resolve(
            workspace: linkedWorkspace,
            evidence: ValidationPrEvidence.resolve(
                workspace: linkedWorkspace,
                deliveryGate: DeliveryGateEvidence.resolve(workspace: linkedWorkspace)
            )
        )
        guard case .invalid(let validationReason) = validationPlan.expectedRevision else {
            return XCTFail("expected invalid validation revision")
        }
        XCTAssertTrue(validationReason.contains("not a regular file"))
        XCTAssertFalse(validationPlan.canWrite)
        XCTAssertTrue(validationPlan.summary.contains("not a regular file"))
        XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), original)
    }

    func testNativeDeliveryRecordStoreRejectsChangedCreatedDeletedAndInvalidEvidence() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-delivery-write-safety-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let healthChecks = [
            WorkspaceHealthCheck(
                id: "delivery-record",
                label: "交付记录",
                detail: "交付记录可用",
                status: "pass",
                action: "delivery"
            ),
            WorkspaceHealthCheck(
                id: "sql-directory",
                label: "SQL",
                detail: "未声明 SQL 变更。",
                status: "pass",
                action: "sql"
            )
        ]

        func workspace(at directory: URL, id: String) -> WorkspaceSummary {
            workspaceForWorkflowSummary(
                stage: "developing",
                id: id,
                name: id,
                path: directory.path,
                healthChecks: healthChecks
            )
        }

        func deliveryPlan(at directory: URL, id: String) -> DeliveryRecordWritePlan {
            let summary = workspace(at: directory, id: id)
            return DeliveryRecordWritePlan.resolve(
                workspace: summary,
                gate: DeliveryGateEvidence.resolve(workspace: summary)
            )
        }

        let changedRoot = root.appendingPathComponent("changed")
        let changedAuditRoot = changedRoot.appendingPathComponent("audit")
        try FileManager.default.createDirectory(at: changedRoot, withIntermediateDirectories: true)
        let changedDeliveryURL = changedRoot.appendingPathComponent("交付记录.md")
        let originalChangedContent = "# 交付记录\n\n## 人工记录\n\n原始版本。\n"
        let manualChangedContent = "# 交付记录\n\n## 人工记录\n\n人工修改后版本。\n"
        try originalChangedContent.write(to: changedDeliveryURL, atomically: true, encoding: .utf8)
        let changedPlan = deliveryPlan(at: changedRoot, id: "delivery-record-changed")
        try manualChangedContent.write(to: changedDeliveryURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try NativeDeliveryRecordStore.appendDeliverySnapshot(
                plan: changedPlan,
                confirmed: true,
                auditRoot: changedAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }
        let changedContent = try String(contentsOf: changedDeliveryURL, encoding: .utf8)
        XCTAssertEqual(changedContent, manualChangedContent)
        XCTAssertFalse(changedContent.contains("## Nexus Delivery Gate Snapshot"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: changedAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))

        let createdRoot = root.appendingPathComponent("created-after-missing")
        let createdAuditRoot = createdRoot.appendingPathComponent("audit")
        try FileManager.default.createDirectory(at: createdRoot, withIntermediateDirectories: true)
        let createdDeliveryURL = createdRoot.appendingPathComponent("交付记录.md")
        let createdPlan = deliveryPlan(at: createdRoot, id: "delivery-record-created-after-missing")
        let createdContent = "# 交付记录\n\n## 人工记录\n\n后来创建。\n"
        try createdContent.write(to: createdDeliveryURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try NativeDeliveryRecordStore.appendDeliverySnapshot(
                plan: createdPlan,
                confirmed: true,
                auditRoot: createdAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }
        let createdWrittenContent = try String(contentsOf: createdDeliveryURL, encoding: .utf8)
        XCTAssertEqual(createdWrittenContent, createdContent)
        XCTAssertFalse(createdWrittenContent.contains("## Nexus Delivery Gate Snapshot"))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: createdAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))

        let deletedRoot = root.appendingPathComponent("deleted-after-existing")
        let deletedAuditRoot = deletedRoot.appendingPathComponent("audit")
        try FileManager.default.createDirectory(at: deletedRoot, withIntermediateDirectories: true)
        let deletedDeliveryURL = deletedRoot.appendingPathComponent("交付记录.md")
        try "# 交付记录\n\n## 人工记录\n\n会被删除。\n".write(
            to: deletedDeliveryURL,
            atomically: true,
            encoding: .utf8
        )
        let deletedPlan = deliveryPlan(at: deletedRoot, id: "delivery-record-deleted-after-existing")
        try FileManager.default.removeItem(at: deletedDeliveryURL)

        XCTAssertThrowsError(
            try NativeDeliveryRecordStore.appendDeliverySnapshot(
                plan: deletedPlan,
                confirmed: true,
                auditRoot: deletedAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: deletedDeliveryURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: deletedAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))

        let linkedRoot = root.appendingPathComponent("symlink")
        let linkedAuditRoot = linkedRoot.appendingPathComponent("audit")
        let externalURL = root.appendingPathComponent("external-delivery.md")
        try FileManager.default.createDirectory(at: linkedRoot, withIntermediateDirectories: true)
        let linkedDeliveryURL = linkedRoot.appendingPathComponent("交付记录.md")
        let linkedOriginal = "# 交付记录\n\n外部链接。\n"
        try linkedOriginal.write(to: externalURL, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: linkedDeliveryURL, withDestinationURL: externalURL)
        let linkedPlan = deliveryPlan(at: linkedRoot, id: "delivery-record-symlink")

        XCTAssertThrowsError(
            try NativeDeliveryRecordStore.appendDeliverySnapshot(
                plan: linkedPlan,
                confirmed: true,
                auditRoot: linkedAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("not a regular file"))
        }
        XCTAssertEqual(try String(contentsOf: externalURL, encoding: .utf8), linkedOriginal)
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: linkedDeliveryURL.path),
            externalURL.path
        )
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: linkedAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))

        let becameSymlinkRoot = root.appendingPathComponent("became-symlink")
        let becameSymlinkAuditRoot = becameSymlinkRoot.appendingPathComponent("audit")
        let becameSymlinkExternalURL = root.appendingPathComponent("became-symlink-external.md")
        try FileManager.default.createDirectory(at: becameSymlinkRoot, withIntermediateDirectories: true)
        let becameSymlinkDeliveryURL = becameSymlinkRoot.appendingPathComponent("交付记录.md")
        let becameSymlinkOriginal = "# 交付记录\n\n## 人工记录\n\n会变成链接。\n"
        try becameSymlinkOriginal.write(
            to: becameSymlinkDeliveryURL,
            atomically: true,
            encoding: .utf8
        )
        let becameSymlinkPlan = deliveryPlan(at: becameSymlinkRoot, id: "delivery-record-became-symlink")
        let becameSymlinkExternalContent = "# 交付记录\n\n外部目标。\n"
        try becameSymlinkExternalContent.write(
            to: becameSymlinkExternalURL,
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.removeItem(at: becameSymlinkDeliveryURL)
        try FileManager.default.createSymbolicLink(
            at: becameSymlinkDeliveryURL,
            withDestinationURL: becameSymlinkExternalURL
        )

        XCTAssertThrowsError(
            try NativeDeliveryRecordStore.appendDeliverySnapshot(
                plan: becameSymlinkPlan,
                confirmed: true,
                auditRoot: becameSymlinkAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("not a regular file"))
        }
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: becameSymlinkDeliveryURL.path),
            becameSymlinkExternalURL.path
        )
        XCTAssertEqual(try String(contentsOf: becameSymlinkExternalURL, encoding: .utf8), becameSymlinkExternalContent)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: becameSymlinkAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))

        let invalidRoot = root.appendingPathComponent("invalid-utf8")
        let invalidAuditRoot = invalidRoot.appendingPathComponent("audit")
        try FileManager.default.createDirectory(at: invalidRoot, withIntermediateDirectories: true)
        let invalidDeliveryURL = invalidRoot.appendingPathComponent("交付记录.md")
        let invalidBytes = Data([0x23, 0x20, 0xE4, 0xBA, 0xA4, 0xE4, 0xBB, 0x98, 0x0A, 0xC3, 0x28, 0x0A])
        try invalidBytes.write(to: invalidDeliveryURL)
        let invalidPlan = deliveryPlan(at: invalidRoot, id: "delivery-record-invalid-utf8")

        XCTAssertThrowsError(
            try NativeDeliveryRecordStore.appendDeliverySnapshot(
                plan: invalidPlan,
                confirmed: true,
                auditRoot: invalidAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("not valid UTF-8"))
        }
        XCTAssertEqual(try Data(contentsOf: invalidDeliveryURL), invalidBytes)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: invalidAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))

        let becameInvalidRoot = root.appendingPathComponent("became-invalid-utf8")
        let becameInvalidAuditRoot = becameInvalidRoot.appendingPathComponent("audit")
        try FileManager.default.createDirectory(at: becameInvalidRoot, withIntermediateDirectories: true)
        let becameInvalidDeliveryURL = becameInvalidRoot.appendingPathComponent("交付记录.md")
        try "# 交付记录\n\n## 人工记录\n\n会变坏。\n".write(
            to: becameInvalidDeliveryURL,
            atomically: true,
            encoding: .utf8
        )
        let becameInvalidPlan = deliveryPlan(at: becameInvalidRoot, id: "delivery-record-became-invalid")
        let becameInvalidBytes = Data([0x23, 0x20, 0xE4, 0xBA, 0xA4, 0xE4, 0xBB, 0x98, 0x0A, 0xC3, 0x28, 0x0A])
        try becameInvalidBytes.write(to: becameInvalidDeliveryURL)

        XCTAssertThrowsError(
            try NativeDeliveryRecordStore.appendDeliverySnapshot(
                plan: becameInvalidPlan,
                confirmed: true,
                auditRoot: becameInvalidAuditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("not valid UTF-8"))
        }
        XCTAssertEqual(try Data(contentsOf: becameInvalidDeliveryURL), becameInvalidBytes)
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: becameInvalidAuditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
        ))
    }

    func testNativeDeliveryRecordStoreRejectsSecondSubmissionWithoutDuplicateAudit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-delivery-duplicate-\(UUID().uuidString)")
        let auditRoot = root.appendingPathComponent("audit")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let deliveryURL = root.appendingPathComponent("交付记录.md")
        try "# 交付记录\n\n## 人工记录\n\n保留。\n".write(
            to: deliveryURL,
            atomically: true,
            encoding: .utf8
        )
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-record-duplicate",
            name: "Delivery Record Duplicate",
            path: root.path,
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let gate = DeliveryGateEvidence.resolve(workspace: workspace)
        let plan = DeliveryRecordWritePlan.resolve(workspace: workspace, gate: gate)

        let first = try NativeDeliveryRecordStore.appendDeliverySnapshot(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )

        XCTAssertThrowsError(
            try NativeDeliveryRecordStore.appendDeliverySnapshot(
                plan: plan,
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }

        let content = try String(contentsOf: deliveryURL, encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 10)
        XCTAssertEqual(content.components(separatedBy: "## Nexus Delivery Gate Snapshot").count - 1, 1)
        XCTAssertEqual(events.filter { $0.action == "delivery_record.snapshot_appended" }.count, 1)
        XCTAssertNotNil(first.auditEventID)
    }

    func testNativeDeliveryRecordStoreCreatesMissingRecordAtExpandedTildePath() throws {
        let workspacePath = "~/../../private/tmp/nexus-delivery-tilde-\(UUID().uuidString)"
        let expandedWorkspacePath = (workspacePath as NSString).expandingTildeInPath
        let workspaceURL = URL(fileURLWithPath: expandedWorkspacePath, isDirectory: true)
        let deliveryURL = workspaceURL.appendingPathComponent("交付记录.md")
        let auditRoot = workspaceURL.appendingPathComponent("audit")
        defer { try? FileManager.default.removeItem(at: workspaceURL) }
        try FileManager.default.createDirectory(at: workspaceURL, withIntermediateDirectories: true)

        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-record-tilde",
            name: "Delivery Record Tilde",
            path: workspacePath,
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let gate = DeliveryGateEvidence.resolve(workspace: workspace)
        let plan = DeliveryRecordWritePlan.resolve(workspace: workspace, gate: gate)

        XCTAssertEqual(plan.expectedRevision, .missing)

        let response = try NativeDeliveryRecordStore.appendDeliverySnapshot(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )

        let content = try String(contentsOf: deliveryURL, encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 10)
        XCTAssertTrue(FileManager.default.fileExists(atPath: deliveryURL.path))
        XCTAssertTrue(content.hasPrefix("# 交付记录\n"))
        XCTAssertEqual(content.components(separatedBy: "## Nexus Delivery Gate Snapshot").count - 1, 1)
        XCTAssertEqual(events.filter { $0.action == "delivery_record.snapshot_appended" }.count, 1)
        XCTAssertEqual(response.path, "\(workspacePath)/交付记录.md")
    }

    func testNativeDeliveryRecordStoreCreatesMissingRecordWhenStillMissing() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-delivery-missing-create-\(UUID().uuidString)")
        let auditRoot = root.appendingPathComponent("audit")
        let deliveryURL = root.appendingPathComponent("交付记录.md")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-record-missing-create",
            name: "Delivery Record Missing Create",
            path: root.path,
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let gate = DeliveryGateEvidence.resolve(workspace: workspace)
        let plan = DeliveryRecordWritePlan.resolve(workspace: workspace, gate: gate)

        XCTAssertEqual(plan.expectedRevision, .missing)

        let response = try NativeDeliveryRecordStore.appendDeliverySnapshot(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )

        let content = try String(contentsOf: deliveryURL, encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 10)
        XCTAssertTrue(content.hasPrefix("# 交付记录\n"))
        XCTAssertEqual(content.components(separatedBy: "## Nexus Delivery Gate Snapshot").count - 1, 1)
        XCTAssertEqual(events.filter { $0.action == "delivery_record.snapshot_appended" }.count, 1)
        XCTAssertEqual(response.auditEventID, events.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
    }

    func testDeliveryRecordWritePlanAppendsCurrentGateSnapshot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-delivery-record-write-\(UUID().uuidString)")
        let auditRoot = root.appendingPathComponent("audit")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try "# 交付记录\n\n## 人工记录\n\n保留。\n".write(to: root.appendingPathComponent("交付记录.md"), atomically: true, encoding: .utf8)
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-record-write",
            name: "Delivery Record Write",
            path: root.path,
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let plan = DeliveryRecordWritePlan.resolve(workspace: workspace, gate: delivery)

        XCTAssertEqual(plan.status, .next)
        XCTAssertTrue(plan.canWrite)
        XCTAssertEqual(plan.items.map(\.id), ["branch", "services", "tasks", "risks", "delivery-record", "sql", "dirty-services"])
        XCTAssertTrue(plan.appendedMarkdown.contains("## Nexus Delivery Gate Snapshot"))
        XCTAssertTrue(plan.appendedMarkdown.contains("门禁状态：就绪 / ready"))
        XCTAssertTrue(plan.appendedMarkdown.contains("| 检查项 | 状态 | 证据 | 说明 |"))
        XCTAssertTrue(plan.appendedMarkdown.contains("Nexus Native confirmed write"))
        XCTAssertFalse(plan.appendedMarkdown.contains("## 完整交付结论"))

        XCTAssertThrowsError(
            try NativeDeliveryRecordStore.appendDeliverySnapshot(plan: plan, confirmed: false)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("explicit confirmation"))
        }

        let response = try NativeDeliveryRecordStore.appendDeliverySnapshot(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        let content = try String(contentsOf: root.appendingPathComponent("交付记录.md"), encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertTrue(response.appended)
        XCTAssertEqual(response.kind, .deliverySnapshot)
        XCTAssertEqual(response.path, root.appendingPathComponent("交付记录.md").path)
        XCTAssertTrue(content.contains("## 人工记录"))
        XCTAssertTrue(content.contains("## Nexus Delivery Gate Snapshot"))
        XCTAssertTrue(content.hasSuffix("\n"))
        XCTAssertEqual(response.auditEventID, events.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(events.first?.action, "delivery_record.snapshot_appended")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["itemCount"], "\(plan.items.count)")
    }

    func testDeliveryRecordWritePlanKeepsArchivedWorkspaceReadOnly() {
        let workspace = workspaceForWorkflowSummary(
            stage: "archived",
            id: "delivery-record-write-archived"
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let plan = DeliveryRecordWritePlan.resolve(workspace: workspace, gate: delivery)

        XCTAssertEqual(plan.status, .archived)
        XCTAssertFalse(plan.canWrite)
        XCTAssertTrue(plan.appendedMarkdown.isEmpty)
        XCTAssertTrue(plan.summary.contains("只读"))
    }

    func testArchiveGateEvidenceReusesDeliveryBlockersBeforeArchive() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "archive-delivery-pending"
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let archive = ArchiveGateEvidence.resolve(workspace: workspace, deliveryGate: delivery)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: DevelopmentTaskEvidence.resolve(workspace: workspace),
            deliveryGate: delivery,
            archiveGate: archive
        )

        XCTAssertEqual(archive.status, .pending)
        XCTAssertEqual(archive.title, "归档前先完成交付 / Finish delivery first")
        XCTAssertEqual(archive.primaryAction, .localCheck)
        XCTAssertFalse(archive.confirmationPlan.isEmpty)
        XCTAssertTrue(archive.confirmationPlan.allSatisfy { $0.action == .finishDelivery })
        XCTAssertEqual(archive.confirmationPlan.first?.gateAction, .localCheck)
        XCTAssertEqual(stage.id, .deliveryCheck)
        XCTAssertEqual(stage.primaryAction, .localCheck)
    }

    func testArchiveGateEvidenceRequiresDeliveryLifecycleBeforeDone() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "archive-enter-delivery",
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let archive = ArchiveGateEvidence.resolve(workspace: workspace, deliveryGate: delivery)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: DevelopmentTaskEvidence.resolve(workspace: workspace),
            deliveryGate: delivery,
            archiveGate: archive
        )

        XCTAssertEqual(delivery.status, .ready)
        XCTAssertEqual(archive.status, .next)
        XCTAssertEqual(archive.primaryAction, .lifecycle(.delivery))
        XCTAssertEqual(archive.confirmationPlan.map(\.action), [.reviewDelivery, .enterDelivery])
        XCTAssertEqual(archive.confirmationPlan.last?.gateAction, .lifecycle(.delivery))
        XCTAssertEqual(stage.id, .archived)
        XCTAssertEqual(stage.primaryAction, .lifecycle(.delivery))
        XCTAssertFalse(stage.nextStageAllowed)
    }

    func testArchiveGateEvidenceRequiresDoneBeforeArchive() {
        let workspace = workspaceForWorkflowSummary(
            stage: "delivery",
            id: "archive-mark-done",
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let archive = ArchiveGateEvidence.resolve(workspace: workspace, deliveryGate: delivery)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: DevelopmentTaskEvidence.resolve(workspace: workspace),
            deliveryGate: delivery,
            archiveGate: archive
        )

        XCTAssertEqual(archive.status, .next)
        XCTAssertEqual(archive.primaryAction, .lifecycle(.done))
        XCTAssertEqual(archive.confirmationPlan.map(\.action), [.reviewDelivery, .markDone])
        XCTAssertEqual(archive.confirmationPlan.last?.gateAction, .lifecycle(.done))
        XCTAssertEqual(stage.id, .archived)
        XCTAssertEqual(stage.primaryAction, .lifecycle(.done))
        XCTAssertFalse(stage.nextStageAllowed)
    }

    func testArchiveGateEvidenceAllowsDoneWorkspaceToArchive() {
        let workspace = workspaceForWorkflowSummary(
            stage: "done",
            id: "archive-ready",
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let archive = ArchiveGateEvidence.resolve(workspace: workspace, deliveryGate: delivery)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: DevelopmentTaskEvidence.resolve(workspace: workspace),
            deliveryGate: delivery,
            archiveGate: archive
        )

        XCTAssertEqual(archive.status, .ready)
        XCTAssertEqual(archive.primaryAction, .lifecycle(.archived))
        XCTAssertEqual(archive.blockerCount, 0)
        XCTAssertEqual(archive.confirmationPlan.map(\.action), [.reviewDelivery, .reviewValidation, .archive])
        XCTAssertEqual(archive.confirmationPlan.first(where: { $0.action == .reviewValidation })?.status, .review)
        XCTAssertEqual(archive.confirmationPlan.last?.gateAction, .lifecycle(.archived))
        XCTAssertEqual(stage.id, .archived)
        XCTAssertEqual(stage.status, .ready)
        XCTAssertEqual(stage.primaryAction, .lifecycle(.archived))
        XCTAssertTrue(stage.nextStageAllowed)
    }

    func testArchiveChecklistWritePlanAppendsFinalChecklistWithoutLifecycleWriteback() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-archive-checklist-write-\(UUID().uuidString)")
        let auditRoot = root.appendingPathComponent("audit")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try "# 交付记录\n".write(to: root.appendingPathComponent("交付记录.md"), atomically: true, encoding: .utf8)
        let workspace = workspaceForWorkflowSummary(
            stage: "done",
            id: "archive-checklist-write",
            path: root.path,
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let archive = ArchiveGateEvidence.resolve(workspace: workspace, deliveryGate: delivery)
        let plan = ArchiveChecklistWritePlan.resolve(workspace: workspace, archiveGate: archive)

        XCTAssertEqual(plan.status, .next)
        XCTAssertTrue(plan.canWrite)
        XCTAssertEqual(plan.items.map(\.action), [.reviewDelivery, .reviewValidation, .archive])
        XCTAssertTrue(plan.appendedMarkdown.contains("## Nexus Archive Checklist"))
        XCTAssertTrue(plan.appendedMarkdown.contains("归档状态：就绪 / ready"))
        XCTAssertTrue(plan.appendedMarkdown.contains("Nexus Native confirmed write"))
        XCTAssertTrue(plan.appendedMarkdown.contains("最终进入 delivery、done、archived 或 restore 仍需通过生命周期确认弹窗"))

        let response = try NativeDeliveryRecordStore.appendArchiveChecklist(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        let content = try String(contentsOf: root.appendingPathComponent("交付记录.md"), encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertTrue(response.appended)
        XCTAssertEqual(response.kind, .archiveChecklist)
        XCTAssertTrue(content.contains("## Nexus Archive Checklist"))
        XCTAssertTrue(content.contains("最终进入 delivery、done、archived 或 restore 仍需通过生命周期确认弹窗"))
        XCTAssertEqual(response.auditEventID, events.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(events.first?.action, "archive_checklist.snapshot_appended")
        XCTAssertEqual(events.first?.metadata["itemCount"], "\(plan.items.count)")
    }

    func testArchiveChecklistWritePlanKeepsArchivedWorkspaceReadOnly() {
        let workspace = workspaceForWorkflowSummary(
            stage: "archived",
            id: "archive-checklist-write-archived"
        )
        let archive = ArchiveGateEvidence.resolve(workspace: workspace)
        let plan = ArchiveChecklistWritePlan.resolve(workspace: workspace, archiveGate: archive)

        XCTAssertEqual(plan.status, .archived)
        XCTAssertFalse(plan.canWrite)
        XCTAssertTrue(plan.appendedMarkdown.isEmpty)
        XCTAssertTrue(plan.summary.contains("只读"))
    }

    func testArchiveGateEvidenceKeepsArchivedWorkspaceReadOnly() {
        let workspace = workspaceForWorkflowSummary(
            stage: "archived",
            id: "archive-already",
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let archive = ArchiveGateEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: WorktreeSetupEvidence.resolve(workspace: workspace),
            developmentTasks: DevelopmentTaskEvidence.resolve(workspace: workspace),
            deliveryGate: DeliveryGateEvidence.resolve(workspace: workspace),
            archiveGate: archive
        )

        XCTAssertEqual(archive.status, .archived)
        XCTAssertEqual(archive.primaryAction, .document("handoff"))
        XCTAssertEqual(archive.confirmationPlan.map(\.action), [.archived, .restore])
        XCTAssertEqual(archive.confirmationPlan.first?.gateAction, .document("handoff"))
        XCTAssertEqual(archive.confirmationPlan.last?.gateAction, .lifecycle(.restoreDevelopment))
        XCTAssertEqual(workspace.lifecycleTransitions, [.restoreDevelopment])
        XCTAssertEqual(stage.id, .archived)
        XCTAssertEqual(stage.status, .archived)
        XCTAssertEqual(stage.primaryAction, .document("handoff"))
        XCTAssertTrue(stage.reason.contains("默认只读"))
    }

    func testValidationPrEvidenceWaitsForDeliveryGate() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "validation-delivery-pending"
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let validation = ValidationPrEvidence.resolve(workspace: workspace, deliveryGate: delivery)

        XCTAssertEqual(delivery.status, .pending)
        XCTAssertEqual(validation.status, .pending)
        XCTAssertEqual(validation.primaryAction, .localCheck)
        XCTAssertEqual(validation.checks.map(\.id), ["delivery-gate"])
        XCTAssertTrue(validation.reason.contains("交付记录"))
    }

    func testValidationPrEvidencePromptsDoneWorkspaceWithoutPrCiEvidence() {
        let workspace = workspaceForWorkflowSummary(
            stage: "done",
            id: "validation-pr-review",
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let delivery = DeliveryGateEvidence.resolve(workspace: workspace)
        let validation = ValidationPrEvidence.resolve(workspace: workspace, deliveryGate: delivery)

        XCTAssertEqual(delivery.status, .ready)
        XCTAssertEqual(validation.status, .review)
        XCTAssertEqual(validation.primaryAction, .validationHandoff)
        XCTAssertEqual(validation.checks.first(where: { $0.id == "pr-ci" })?.status, .review)
        XCTAssertTrue(validation.reason.contains("PR"))
    }

    func testValidationPrWritePlanAppendsReviewSnapshotWithoutCallingGithub() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-validation-pr-write-\(UUID().uuidString)")
        let auditRoot = root.appendingPathComponent("audit")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        try "# 交付记录\n".write(to: root.appendingPathComponent("交付记录.md"), atomically: true, encoding: .utf8)
        let workspace = workspaceForWorkflowSummary(
            stage: "done",
            id: "validation-pr-write",
            path: root.path,
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let validation = ValidationPrEvidence.resolve(
            workspace: workspace,
            deliveryGate: DeliveryGateEvidence.resolve(workspace: workspace)
        )
        let plan = ValidationPrWritePlan.resolve(workspace: workspace, evidence: validation)

        XCTAssertEqual(plan.status, .review)
        XCTAssertTrue(plan.canWrite)
        XCTAssertEqual(plan.items.map(\.id), ["local-check", "delivery-record", "task-risk", "pr-ci", "lifecycle"])
        XCTAssertTrue(plan.appendedMarkdown.contains("## Nexus Validation / PR Snapshot"))
        XCTAssertTrue(plan.appendedMarkdown.contains("验证状态：复核 / review"))
        XCTAssertTrue(plan.appendedMarkdown.contains("不直接调用 GitHub"))
        XCTAssertTrue(plan.appendedMarkdown.contains("Nexus Native confirmed write"))

        let response = try NativeDeliveryRecordStore.appendValidationPrSnapshot(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        let content = try String(contentsOf: root.appendingPathComponent("交付记录.md"), encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertTrue(response.appended)
        XCTAssertEqual(response.kind, .validationPrSnapshot)
        XCTAssertTrue(content.contains("## Nexus Validation / PR Snapshot"))
        XCTAssertTrue(content.contains("不直接调用 GitHub"))
        XCTAssertEqual(response.auditEventID, events.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(events.first?.action, "validation_pr.snapshot_appended")
        XCTAssertEqual(events.first?.metadata["itemCount"], "\(plan.items.count)")
    }

    func testValidationPrWritePlanKeepsArchivedWorkspaceReadOnly() {
        let workspace = workspaceForWorkflowSummary(
            stage: "archived",
            id: "validation-pr-write-archived"
        )
        let validation = ValidationPrEvidence.resolve(workspace: workspace)
        let plan = ValidationPrWritePlan.resolve(workspace: workspace, evidence: validation)

        XCTAssertEqual(plan.status, .archived)
        XCTAssertFalse(plan.canWrite)
        XCTAssertTrue(plan.appendedMarkdown.isEmpty)
        XCTAssertTrue(plan.summary.contains("只读"))
    }

    func testValidationPrEvidenceReadyWhenDoneHasPrCiEvidence() {
        let workspace = workspaceForWorkflowSummary(
            stage: "done",
            id: "validation-pr-ready",
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ],
            activities: [
                ActivityEvent(time: "10:42", title: "PR #182 merged", detail: "CI passed and validation passed")
            ]
        )
        let validation = ValidationPrEvidence.resolve(
            workspace: workspace,
            deliveryGate: DeliveryGateEvidence.resolve(workspace: workspace)
        )

        XCTAssertEqual(validation.status, .ready)
        XCTAssertEqual(validation.primaryAction, .document("delivery"))
        XCTAssertEqual(validation.checks.first(where: { $0.id == "pr-ci" })?.status, .ready)
        XCTAssertEqual(validation.reviewCount, 0)
    }

    func testValidationPrEvidenceRoutesDeliveryWorkspaceToDoneWriteback() {
        let workspace = workspaceForWorkflowSummary(
            stage: "delivery",
            id: "validation-mark-done",
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery"),
                WorkspaceHealthCheck(id: "sql-directory", label: "SQL", detail: "未声明 SQL 变更。", status: "pass", action: "sql")
            ]
        )
        let validation = ValidationPrEvidence.resolve(
            workspace: workspace,
            deliveryGate: DeliveryGateEvidence.resolve(workspace: workspace)
        )

        XCTAssertEqual(validation.status, .next)
        XCTAssertEqual(validation.primaryAction, .lifecycle(.done))
        XCTAssertEqual(validation.checks.first(where: { $0.id == "lifecycle" })?.status, .next)
    }

    func testMainStageBlocksUnsafeDemandTaskTransferEvidence() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "demand-transfer-evidence-blocked",
            path: "/tmp/demand-transfer-evidence-blocked"
        )
        let intakeTasksPath = "\(workspace.path)/需求/tasks.md"
        let plan = DemandTaskTransferPlan(
            workspaceID: workspace.id,
            workspaceName: workspace.name,
            workspacePath: workspace.path,
            intakeTasksPath: intakeTasksPath,
            executionTasksPath: "\(workspace.path)/tasks.md",
            candidates: [],
            existingTitles: [],
            expectedIntakeRevision: .invalid(reason: "intake tasks.md is not valid UTF-8"),
            expectedExecutionRevision: .missing,
            blockerSummary: "intake tasks.md is not valid UTF-8",
            blockerPath: intakeTasksPath
        )
        let worktree = WorktreeSetupEvidence.resolve(workspace: workspace)
        let stage = workspace.mainStage(
            demandReadiness: readyDemandReadiness(),
            scopeFreeze: readyScopeFreeze(),
            serviceBranch: readyServiceBranch(for: workspace),
            worktreeSetup: worktree,
            demandTaskTransfer: plan
        )

        XCTAssertTrue(worktree.ready)
        XCTAssertEqual(stage.id, .development)
        XCTAssertEqual(stage.status, .blocked)
        XCTAssertEqual(stage.title, "需求任务证据不可用 / Task evidence unavailable")
        XCTAssertEqual(stage.reason, plan.blockerSummary)
        XCTAssertEqual(stage.primaryActionLabel, "打开需求任务")
        XCTAssertEqual(stage.primaryAction, .path(plan.intakeTasksPath))
        XCTAssertFalse(stage.nextStageAllowed)
    }

    func testDemandTaskTransferPlanFindsNewIntakeTasksAndUpdatesMainStage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-demand-task-transfer-\(UUID().uuidString)")
        let demandDir = root.appendingPathComponent("需求")
        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
        try writeBranchPolicyFixture(
            workspaceRoot: root,
            branch: "feature/workflow-summary"
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        try "# 需求确认卡\n\n- 真实需求目标：补齐交易快照。\n- 用户流程：保存订单时写入快照。\n- 验收标准：可查询历史快照。\n".write(
            to: demandDir.appendingPathComponent("requirement.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 待确认问题\n\n## P0 阻塞开发\n\n- [x] 已确认无需新增字段。\n".write(
            to: demandDir.appendingPathComponent("questions.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # 本次开发范围

        ## 已确认并实现

        - 保存订单时记录交易快照。

        ## 暂不实现

        - 不补历史数据。

        ## 仍待确认

        - 无 P0 待确认项。

        ## 进入开发条件

        - [x] 本文件已冻结本次开发范围。
        """.write(
            to: demandDir.appendingPathComponent("scope.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # 需求列表

        | 需求点 | 状态 | 优先级 | 来源 | 说明 |
        | --- | --- | --- | --- | --- |
        | 整理 requirement.md | 待办 | P0 | 需求预检 | 模板任务 |
        | 新增交易快照写入 | 待办 | P0 | 蓝湖 | 保存订单时记录快照 |
        | 已有执行任务 | 待办 | P1 | 需求预检 | 已经转入 root tasks.md |
        | 已完成的需求点 | 已完成 | P2 | 需求预检 | 不应转入 |
        """.write(
            to: demandDir.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 需求交付\n\n- 预检完成。\n".write(
            to: demandDir.appendingPathComponent("delivery.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | 已有执行任务 | 待办 | priority=medium |
        """.write(
            to: root.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )

        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "demand-transfer",
            name: "Demand Transfer",
            path: root.path,
            tasks: [
                WorkspaceTask(
                    id: "existing",
                    title: "已有执行任务",
                    status: "待办",
                    detail: "priority=medium",
                    priority: "medium",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 5
                )
            ]
        )
        let status = demandIntakeStatus(at: demandDir)
        let readiness = DemandIntakeReadinessEvidence.resolve(status: status, workspace: workspace)
        let scope = ScopeFreezeEvidence.resolve(status: status, workspace: workspace)
        let plan = DemandTaskTransferPlan.resolve(workspace: workspace, status: status)
        let stage = workspace.mainStage(
            demandIntakeStatus: status,
            demandReadiness: readiness,
            scopeFreeze: scope,
            demandTaskTransfer: plan
        )

        XCTAssertTrue(readiness.ready)
        XCTAssertTrue(scope.ready)
        XCTAssertEqual(plan.candidates.map(\.title), ["新增交易快照写入", "已有执行任务"])
        XCTAssertEqual(plan.transferableItems.map(\.title), ["新增交易快照写入"])
        XCTAssertEqual(plan.duplicateCount, 1)
        XCTAssertTrue(plan.transferableItems[0].markdownRow.contains("priority=high"))
        XCTAssertEqual(stage.id, .development)
        XCTAssertEqual(stage.primaryAction, .transferDemandTasks)

        XCTAssertThrowsError(
            try NativeDemandTaskTransferStore.transfer(plan: plan, confirmed: false)
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("explicit confirmation"))
        }

        let auditRoot = root.appendingPathComponent("audit")
        let response = try NativeDemandTaskTransferStore.transfer(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        let executionTasks = try String(contentsOf: root.appendingPathComponent("tasks.md"), encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 5)

        XCTAssertTrue(response.transferred)
        XCTAssertEqual(response.transferredCount, 1)
        XCTAssertEqual(response.duplicateCount, 1)
        XCTAssertTrue(executionTasks.contains("## Requirement Tasks"))
        XCTAssertTrue(executionTasks.contains("| 新增交易快照写入 | 待办 | priority=high; source=需求/tasks.md; L6; 来源: 蓝湖; 保存订单时记录快照; 预检状态: 待办 |"))
        XCTAssertEqual(response.auditEventID, events.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
        XCTAssertEqual(events.first?.action, "demand_tasks.transferred")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["transferredCount"], "1")
        XCTAssertEqual(events.first?.metadata["duplicateCount"], "1")
    }

    func testNativeDemandTaskTransferStoreRejectsChangedDeletedAndUnsafeEvidence() throws {
        enum Mutation: CaseIterable {
            case intakeChanged
            case intakeDeleted
            case intakeSymlink
            case intakeInvalidUTF8
            case executionChanged
            case executionDeleted
            case executionSymlink
            case executionInvalidUTF8
            case missingExecutionCreated

            var subject: String {
                switch self {
                case .intakeChanged, .intakeDeleted, .intakeSymlink, .intakeInvalidUTF8:
                    return "intake"
                case .executionChanged, .executionDeleted, .executionSymlink,
                     .executionInvalidUTF8, .missingExecutionCreated:
                    return "execution"
                }
            }

            var reason: String {
                switch self {
                case .intakeSymlink, .executionSymlink:
                    return "not a regular file"
                case .intakeInvalidUTF8, .executionInvalidUTF8:
                    return "not valid UTF-8"
                default:
                    return "changed since confirmation"
                }
            }
        }

        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-demand-task-transfer-safety-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let intake = """
        # 需求列表

        | 需求点 | 状态 | 优先级 | 来源 | 说明 |
        | --- | --- | --- | --- | --- |
        | 新增交易快照写入 | 待办 | P0 | 蓝湖 | 保存订单时记录快照 |
        """ + "\n"
        let execution = """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | 已有执行任务 | 待办 | priority=medium |
        """ + "\n"
        let invalidBytes = Data([0x23, 0x20, 0xC3, 0x28, 0x0A])

        for mutation in Mutation.allCases {
            let caseRoot = root.appendingPathComponent(String(describing: mutation))
            let demandDir = caseRoot.appendingPathComponent("需求")
            let intakeURL = demandDir.appendingPathComponent("tasks.md")
            let executionURL = caseRoot.appendingPathComponent("tasks.md")
            let auditRoot = caseRoot.appendingPathComponent("audit")
            let externalURL = root.appendingPathComponent("external-\(String(describing: mutation)).md")
            try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
            try intake.write(to: intakeURL, atomically: true, encoding: .utf8)
            if mutation != .missingExecutionCreated {
                try execution.write(to: executionURL, atomically: true, encoding: .utf8)
            }

            let workspace = workspaceForWorkflowSummary(
                stage: "developing",
                id: "demand-transfer-safety-\(String(describing: mutation))",
                path: caseRoot.path
            )
            let plan = DemandTaskTransferPlan.resolve(
                workspace: workspace,
                status: demandIntakeStatus(at: demandDir)
            )
            XCTAssertFalse(plan.isBlocked, "\(mutation)")
            XCTAssertTrue(plan.hasTransferableItems, "\(mutation)")

            let changedIntake = intake + "\n<!-- external intake edit -->\n"
            let changedExecution = execution + "\n<!-- external execution edit -->\n"
            let externalContent = "# External evidence\n\nDo not modify.\n"
            switch mutation {
            case .intakeChanged:
                try changedIntake.write(to: intakeURL, atomically: true, encoding: .utf8)
            case .intakeDeleted:
                try FileManager.default.removeItem(at: intakeURL)
            case .intakeSymlink:
                try externalContent.write(to: externalURL, atomically: true, encoding: .utf8)
                try FileManager.default.removeItem(at: intakeURL)
                try FileManager.default.createSymbolicLink(at: intakeURL, withDestinationURL: externalURL)
            case .intakeInvalidUTF8:
                try invalidBytes.write(to: intakeURL)
            case .executionChanged:
                try changedExecution.write(to: executionURL, atomically: true, encoding: .utf8)
            case .executionDeleted:
                try FileManager.default.removeItem(at: executionURL)
            case .executionSymlink:
                try externalContent.write(to: externalURL, atomically: true, encoding: .utf8)
                try FileManager.default.removeItem(at: executionURL)
                try FileManager.default.createSymbolicLink(at: executionURL, withDestinationURL: externalURL)
            case .executionInvalidUTF8:
                try invalidBytes.write(to: executionURL)
            case .missingExecutionCreated:
                try changedExecution.write(to: executionURL, atomically: true, encoding: .utf8)
            }

            XCTAssertThrowsError(
                try NativeDemandTaskTransferStore.transfer(
                    plan: plan,
                    confirmed: true,
                    auditRoot: auditRoot.path,
                    actor: "Nexus Test"
                ),
                "\(mutation)"
            ) { error in
                XCTAssertTrue(error.localizedDescription.contains(mutation.subject), "\(mutation): \(error)")
                XCTAssertTrue(error.localizedDescription.contains(mutation.reason), "\(mutation): \(error)")
            }

            switch mutation {
            case .intakeChanged:
                XCTAssertEqual(try Data(contentsOf: intakeURL), Data(changedIntake.utf8))
                XCTAssertEqual(try Data(contentsOf: executionURL), Data(execution.utf8))
            case .intakeDeleted:
                XCTAssertFalse(FileManager.default.fileExists(atPath: intakeURL.path))
                XCTAssertEqual(try Data(contentsOf: executionURL), Data(execution.utf8))
            case .intakeSymlink:
                XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: intakeURL.path), externalURL.path)
                XCTAssertEqual(try Data(contentsOf: externalURL), Data(externalContent.utf8))
                XCTAssertEqual(try Data(contentsOf: executionURL), Data(execution.utf8))
            case .intakeInvalidUTF8:
                XCTAssertEqual(try Data(contentsOf: intakeURL), invalidBytes)
                XCTAssertEqual(try Data(contentsOf: executionURL), Data(execution.utf8))
            case .executionChanged:
                XCTAssertEqual(try Data(contentsOf: intakeURL), Data(intake.utf8))
                XCTAssertEqual(try Data(contentsOf: executionURL), Data(changedExecution.utf8))
            case .executionDeleted:
                XCTAssertEqual(try Data(contentsOf: intakeURL), Data(intake.utf8))
                XCTAssertFalse(FileManager.default.fileExists(atPath: executionURL.path))
            case .executionSymlink:
                XCTAssertEqual(try Data(contentsOf: intakeURL), Data(intake.utf8))
                XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: executionURL.path), externalURL.path)
                XCTAssertEqual(try Data(contentsOf: externalURL), Data(externalContent.utf8))
            case .executionInvalidUTF8:
                XCTAssertEqual(try Data(contentsOf: intakeURL), Data(intake.utf8))
                XCTAssertEqual(try Data(contentsOf: executionURL), invalidBytes)
            case .missingExecutionCreated:
                XCTAssertEqual(try Data(contentsOf: intakeURL), Data(intake.utf8))
                XCTAssertEqual(try Data(contentsOf: executionURL), Data(changedExecution.utf8))
            }
            XCTAssertFalse(FileManager.default.fileExists(
                atPath: auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path
            ))
        }
    }

    func testNativeDemandTaskTransferStoreCreatesMissingOutputWhenStillMissing() throws {
        let workspacePath = "~/../../private/tmp/nexus-demand-task-transfer-missing-\(UUID().uuidString)"
        let root = URL(
            fileURLWithPath: (workspacePath as NSString).expandingTildeInPath,
            isDirectory: true
        ).standardizedFileURL
        let demandDir = root.appendingPathComponent("需求")
        let outputURL = root.appendingPathComponent("tasks.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
        try """
        # 需求列表

        | 需求点 | 状态 | 优先级 | 来源 | 说明 |
        | --- | --- | --- | --- | --- |
        | 新增交易快照写入 | 待办 | P0 | 蓝湖 | 保存订单时记录快照 |
        """.write(
            to: demandDir.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "demand-transfer-missing-output",
            path: workspacePath
        )
        let plan = DemandTaskTransferPlan.resolve(
            workspace: workspace,
            status: demandIntakeStatus(at: demandDir)
        )

        XCTAssertEqual(plan.expectedExecutionRevision, .missing)
        let response = try NativeDemandTaskTransferStore.transfer(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 10)
        let candidateRow = plan.transferableItems[0].markdownRow
        XCTAssertTrue(content.hasPrefix("# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n"))
        XCTAssertEqual(content.components(separatedBy: "## Requirement Tasks").count - 1, 1)
        XCTAssertEqual(content.components(separatedBy: candidateRow).count - 1, 1)
        XCTAssertEqual(events.filter { $0.action == "demand_tasks.transferred" }.count, 1)
        XCTAssertEqual(response.auditEventID, events.first?.id)
        XCTAssertEqual(response.auditEventPath, auditRoot.appendingPathComponent(NativeAuditEventStore.fileName).path)
    }

    func testNativeDemandTaskTransferStoreRejectsSecondSubmissionWithoutDuplicateAudit() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-demand-task-transfer-duplicate-\(UUID().uuidString)")
        let demandDir = root.appendingPathComponent("需求")
        let outputURL = root.appendingPathComponent("tasks.md")
        let auditRoot = root.appendingPathComponent("audit")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
        try """
        # 需求列表

        | 需求点 | 状态 | 优先级 | 来源 | 说明 |
        | --- | --- | --- | --- | --- |
        | 新增交易快照写入 | 待办 | P0 | 蓝湖 | 保存订单时记录快照 |
        """.write(
            to: demandDir.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        """.write(to: outputURL, atomically: true, encoding: .utf8)
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "demand-transfer-duplicate",
            path: root.path
        )
        let plan = DemandTaskTransferPlan.resolve(
            workspace: workspace,
            status: demandIntakeStatus(at: demandDir)
        )

        let first = try NativeDemandTaskTransferStore.transfer(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path,
            actor: "Nexus Test"
        )
        XCTAssertThrowsError(
            try NativeDemandTaskTransferStore.transfer(
                plan: plan,
                confirmed: true,
                auditRoot: auditRoot.path,
                actor: "Nexus Test"
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("execution"))
            XCTAssertTrue(error.localizedDescription.contains("changed since confirmation"))
        }

        let content = try String(contentsOf: outputURL, encoding: .utf8)
        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot.path, limit: 10)
        XCTAssertEqual(content.components(separatedBy: plan.transferableItems[0].markdownRow).count - 1, 1)
        XCTAssertEqual(events.filter { $0.action == "demand_tasks.transferred" }.count, 1)
        XCTAssertNotNil(first.auditEventID)
    }

    func testDemandTaskTransferPlanCapturesStrictInputAndOutputSnapshots() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-demand-task-transfer-revisions-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }

        let intake = """
        # 需求列表

        | 需求点 | 状态 | 优先级 | 来源 | 说明 |
        | --- | --- | --- | --- | --- |
        | 新增交易快照写入 | 待办 | P0 | 蓝湖 | 保存订单时记录快照 |
        """ + "\n"
        let execution = """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | 已有执行任务 | 待办 | priority=medium |
        """ + "\n"

        func intakeURL(for name: String) -> URL {
            root.appendingPathComponent(name).appendingPathComponent("需求/tasks.md")
        }

        func executionURL(for name: String) -> URL {
            root.appendingPathComponent(name).appendingPathComponent("tasks.md")
        }

        func write(_ content: String, to url: URL) throws {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try content.write(to: url, atomically: true, encoding: .utf8)
        }

        func plan(_ name: String) -> DemandTaskTransferPlan {
            let workspaceRoot = root.appendingPathComponent(name)
            return DemandTaskTransferPlan.resolve(
                workspace: workspaceForWorkflowSummary(
                    stage: "developing",
                    id: "demand-transfer-revisions-\(name)",
                    path: workspaceRoot.path
                ),
                status: demandIntakeStatus(at: workspaceRoot.appendingPathComponent("需求"))
            )
        }

        try write(intake, to: intakeURL(for: "regular"))
        try write(execution, to: executionURL(for: "regular"))
        try write(intake, to: intakeURL(for: "missing-output"))
        try write(execution, to: executionURL(for: "missing-intake"))
        try write(intake, to: root.appendingPathComponent("external-intake.md"))
        try FileManager.default.createDirectory(
            at: intakeURL(for: "linked-intake").deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: intakeURL(for: "linked-intake"),
            withDestinationURL: root.appendingPathComponent("external-intake.md")
        )
        try FileManager.default.createDirectory(
            at: intakeURL(for: "invalid-intake").deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x23, 0x20, 0xC3, 0x28, 0x0A]).write(to: intakeURL(for: "invalid-intake"))
        try write(intake, to: intakeURL(for: "linked-output"))
        try write(execution, to: root.appendingPathComponent("external-output.md"))
        try FileManager.default.createDirectory(
            at: executionURL(for: "linked-output").deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            at: executionURL(for: "linked-output"),
            withDestinationURL: root.appendingPathComponent("external-output.md")
        )
        try write(intake, to: intakeURL(for: "invalid-output"))
        try FileManager.default.createDirectory(
            at: executionURL(for: "invalid-output").deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data([0x23, 0x20, 0xC3, 0x28, 0x0A]).write(to: executionURL(for: "invalid-output"))

        let regular = plan("regular")
        let missingOutput = plan("missing-output")
        let missingIntake = plan("missing-intake")
        let linkedIntake = plan("linked-intake")
        let invalidIntake = plan("invalid-intake")
        let linkedOutput = plan("linked-output")
        let invalidOutput = plan("invalid-output")

        guard case .regularUTF8(let intakeSHA, let intakeBytes) = regular.expectedIntakeRevision else {
            return XCTFail("expected regular intake revision")
        }
        guard case .regularUTF8(let outputSHA, let outputBytes) = regular.expectedExecutionRevision else {
            return XCTFail("expected regular execution revision")
        }
        XCTAssertEqual(intakeSHA.count, 64)
        XCTAssertEqual(intakeBytes, Data(intake.utf8).count)
        XCTAssertEqual(outputSHA.count, 64)
        XCTAssertEqual(outputBytes, Data(execution.utf8).count)
        XCTAssertNil(regular.blockerSummary)
        XCTAssertEqual(regular.transferableItems.map(\.title), ["新增交易快照写入"])

        XCTAssertEqual(missingOutput.expectedExecutionRevision, .missing)
        XCTAssertNil(missingOutput.blockerSummary)
        XCTAssertTrue(missingOutput.hasTransferableItems)

        XCTAssertTrue(missingIntake.isBlocked)
        XCTAssertTrue(missingIntake.blockerSummary?.contains("missing") == true)
        XCTAssertFalse(missingIntake.hasTransferableItems)
        XCTAssertTrue(linkedIntake.blockerSummary?.contains("not a regular file") == true)
        XCTAssertTrue(invalidIntake.blockerSummary?.contains("not valid UTF-8") == true)
        XCTAssertTrue(linkedOutput.blockerSummary?.contains("not a regular file") == true)
        XCTAssertTrue(invalidOutput.blockerSummary?.contains("not valid UTF-8") == true)
    }

    func testDemandTaskTransferPlanUsesExactOutputSnapshotInsteadOfStaleWorkspaceTasks() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-demand-task-transfer-stale-workspace-\(UUID().uuidString)")
        let demandDir = root.appendingPathComponent("需求")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: demandDir, withIntermediateDirectories: true)
        try """
        # 需求列表

        | 需求点 | 状态 | 优先级 | 来源 | 说明 |
        | --- | --- | --- | --- | --- |
        | 重新加入任务 | 待办 | P1 | 蓝湖 | 当前 root tasks.md 中不存在 |
        """.write(to: demandDir.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8)
        try """
        # Tasks

        | 任务 | 状态 | 说明 |
        | --- | --- | --- |
        | 已有执行任务 | 待办 | priority=medium |
        """.write(to: root.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8)

        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "demand-transfer-stale-workspace",
            path: root.path,
            tasks: [
                WorkspaceTask(
                    id: "stale-task",
                    title: "重新加入任务",
                    status: "待办",
                    detail: "stale workspace summary",
                    priority: "medium",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 5
                )
            ]
        )

        let plan = DemandTaskTransferPlan.resolve(
            workspace: workspace,
            status: demandIntakeStatus(at: demandDir)
        )

        XCTAssertEqual(plan.transferableItems.map(\.title), ["重新加入任务"])
        XCTAssertEqual(plan.duplicateCount, 0)
    }

    func testWorkflowPathStatusLabelsStayChineseFirst() {
        XCTAssertEqual(WorkflowPathStatus.ready.displayLabel, "就绪 / ready")
        XCTAssertEqual(WorkflowPathStatus.review.displayLabel, "复核 / review")
        XCTAssertEqual(WorkflowPathStatus.blocked.displayLabel, "阻塞 / block")
        XCTAssertEqual(WorkflowPathStatus.pending.displayLabel, "待确认 / pending")
        XCTAssertEqual(WorkflowPathStatus.next.displayLabel, "下一步 / next")
        XCTAssertEqual(WorkflowPathStatus.archived.displayLabel, "归档 / archive")
    }

    func testWorkflowDeliveryRouteLabelsStayActionOriented() {
        XCTAssertEqual(WorkflowDeliveryRoute.runLocalCheck.displayLabel, "运行检查")
        XCTAssertEqual(WorkflowDeliveryRoute.updateDelivery.displayLabel, "交付交接")
        XCTAssertEqual(WorkflowDeliveryRoute.validationHandoff.displayLabel, "PR 交接")
        XCTAssertEqual(WorkflowDeliveryRoute.openDelivery.displayLabel, "打开文档")
    }

    func testAgentActionSurfaceBuildsApprovalResponsesWithoutExecutingCommands() {
        let event = AgentEvent(
            id: "agent-approval",
            timestamp: "2026-05-31T12:00:00Z",
            source: "codex",
            sessionId: "thread-1",
            workspaceFolder: "2026-05-31-demo",
            kind: "permission",
            title: "Permission requested",
            summary: "Codex wants to push a branch.",
            severity: "warning",
            metadata: ["command": "git push"]
        )

        let surface = AgentActionSurface(event: event)

        XCTAssertEqual(surface?.kind, .approval)
        XCTAssertEqual(surface?.kind.statusLabel, "需确认 / approval")
        XCTAssertTrue(surface?.safetyNote.contains("不会执行") == true)
        XCTAssertTrue(surface?.primaryResponse.payload.contains("Approved by user") == true)
        XCTAssertTrue(surface?.primaryResponse.payload.contains("git push") == true)
        XCTAssertTrue(surface?.secondaryResponse?.payload.contains("Not approved") == true)
    }

    func testAgentActionSurfaceBuildsQuestionAnswerTemplate() {
        let event = AgentEvent(
            id: "agent-question",
            timestamp: "2026-05-31T12:05:00Z",
            source: "codex",
            sessionId: "thread-2",
            workspaceFolder: nil,
            kind: "question",
            title: "Need service scope",
            summary: "Which service owns this change?",
            severity: "info",
            metadata: [:]
        )

        let surface = AgentActionSurface(event: event)

        XCTAssertEqual(surface?.kind, .answer)
        XCTAssertTrue(surface?.primaryResponse.payload.contains("Answer: <fill in the answer before sending>") == true)
        XCTAssertTrue(surface?.secondaryResponse?.payload.contains("Need more context") == true)
    }

    func testAgentInboxSummaryPrioritizesActionRequiredEvents() {
        let permission = AgentEvent(
            id: "agent-permission",
            timestamp: "2026-05-31T12:00:00Z",
            source: "codex",
            sessionId: "thread-1",
            workspaceFolder: "demo",
            kind: "permission",
            title: "Permission requested",
            summary: "Need git push approval.",
            severity: "warning",
            metadata: ["command": "git push"]
        )
        let status = AgentEvent(
            id: "agent-status",
            timestamp: "2026-05-31T12:01:00Z",
            source: "codex",
            sessionId: "thread-1",
            workspaceFolder: "demo",
            kind: "status",
            title: "Build passed",
            summary: "CI passed.",
            severity: "info",
            metadata: [:]
        )
        let error = AgentEvent(
            id: "agent-error",
            timestamp: "2026-05-31T12:02:00Z",
            source: "codex",
            sessionId: "thread-1",
            workspaceFolder: "demo",
            kind: "status",
            title: "Hook failed",
            summary: "Hook returned an error.",
            severity: "error",
            metadata: [:]
        )

        let inbox = AgentInboxSummary(events: [status, permission, error])

        XCTAssertEqual(inbox.totalCount, 3)
        XCTAssertEqual(inbox.actionRequired.map(\.id), ["agent-permission", "agent-error"])
        XCTAssertEqual(inbox.recent.map(\.id), ["agent-status"])
        XCTAssertEqual(inbox.pendingLabel, "2 pending")
    }

    func testAgentWorkflowSummaryExplainsInboxToTaskFlow() {
        let event = AgentEvent(
            id: "agent-question",
            timestamp: "2026-05-31T12:10:00Z",
            source: "codex",
            sessionId: "thread-3",
            workspaceFolder: "demo",
            kind: "question",
            title: "Need decision",
            summary: "Should this be turned into a task?",
            severity: "info",
            metadata: [:]
        )
        let inbox = AgentInboxSummary(events: [event])

        let activeFlow = AgentWorkflowSummary(inbox: inbox, agentTaskCount: 2, openTaskCount: 5)
        XCTAssertTrue(activeFlow.shouldShow)
        XCTAssertEqual(activeFlow.metricLabel, "1 inbox / 2 tasks")
        XCTAssertTrue(activeFlow.title.contains("Active flow"))
        XCTAssertTrue(activeFlow.detail.contains("tasks.md"))

        let noFlow = AgentWorkflowSummary(inbox: AgentInboxSummary(events: []), agentTaskCount: 0, openTaskCount: 0)
        XCTAssertFalse(noFlow.shouldShow)
    }

    @MainActor
    func testAgentWorkflowSummaryIgnoresDeferredAgentTasks() {
        let deferredAgentWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "deferred-agent-workspace",
            tasks: [
                WorkspaceTask(
                    id: "agent-deferred",
                    title: "稍后处理 Agent 建议",
                    status: "延期",
                    detail: "deferred until next release",
                    priority: "high",
                    source: "agent",
                    sourceEventID: "agent-event-1",
                    sourceLine: 12
                )
            ]
        )
        let activeAgentWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "active-agent-workspace",
            tasks: [
                WorkspaceTask(
                    id: "agent-active",
                    title: "今天处理 Agent 建议",
                    status: "todo",
                    detail: "需要继续处理。",
                    priority: "medium",
                    source: "agent",
                    sourceEventID: "agent-event-2",
                    sourceLine: 18
                )
            ]
        )
        let deferredOnlyState = appStateForAutomationTests(workspaces: [deferredAgentWorkspace])

        XCTAssertEqual(deferredOnlyState.taskCenterCount(for: .agent), 1)
        XCTAssertEqual(deferredOnlyState.taskCenterCount(for: .deferred), 1)
        XCTAssertEqual(deferredOnlyState.agentWorkflowSummary.agentTaskCount, 0)
        XCTAssertEqual(deferredOnlyState.agentWorkflowSummary.openTaskCount, 0)
        XCTAssertFalse(deferredOnlyState.agentWorkflowSummary.shouldShow)
        XCTAssertEqual(deferredOnlyState.menuBarSummary.agentTaskCount, 0)

        let mixedState = appStateForAutomationTests(workspaces: [deferredAgentWorkspace, activeAgentWorkspace])

        XCTAssertEqual(mixedState.taskCenterCount(for: .agent), 2)
        XCTAssertEqual(mixedState.taskCenterCount(for: .deferred), 1)
        XCTAssertEqual(mixedState.agentWorkflowSummary.agentTaskCount, 1)
        XCTAssertEqual(mixedState.agentWorkflowSummary.openTaskCount, 1)
        XCTAssertTrue(mixedState.agentWorkflowSummary.shouldShow)
        XCTAssertEqual(mixedState.menuBarSummary.agentTaskCount, 1)
    }

    func testWorkspaceWorkflowSummaryCombinesTaskAndDeliverySignals() {
        let payLogSummary = WorkspaceWorkflowSummary(workspace: WorkspaceSummary.previewData[0])

        XCTAssertEqual(payLogSummary.openTaskCount, 3)
        XCTAssertEqual(payLogSummary.blockedTaskCount, 0)
        XCTAssertEqual(payLogSummary.taskValue, "开 3")
        XCTAssertEqual(payLogSummary.taskStatus, .review)
        XCTAssertEqual(payLogSummary.deliveryValue, "需补充")
        XCTAssertEqual(payLogSummary.deliveryStatus, .review)
        XCTAssertTrue(payLogSummary.deliveryDetail.contains("交付记录"))
        XCTAssertEqual(payLogSummary.deliveryRoute, .updateDelivery)

        let readySummary = WorkspaceWorkflowSummary(workspace: WorkspaceSummary.previewData[1])

        XCTAssertEqual(readySummary.openTaskCount, 0)
        XCTAssertEqual(readySummary.taskValue, "已清理")
        XCTAssertEqual(readySummary.taskStatus, .ready)
        XCTAssertEqual(readySummary.deliveryValue, "待检查")
        XCTAssertEqual(readySummary.deliveryStatus, .pending)
        XCTAssertEqual(readySummary.deliveryRoute, .runLocalCheck)
    }

    func testWorkspaceWorkflowSummaryRoutesDoneDeliveryToValidationHandoff() {
        let doneWorkspace = workspaceForWorkflowSummary(stage: "done")
        let deliveryWorkspace = workspaceForWorkflowSummary(stage: "delivery")
        let passedWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            healthChecks: [
                WorkspaceHealthCheck(id: "delivery-record", label: "交付记录", detail: "交付记录可用", status: "pass", action: "delivery")
            ]
        )

        XCTAssertEqual(WorkspaceWorkflowSummary(workspace: doneWorkspace).deliveryRoute, .validationHandoff)
        XCTAssertEqual(WorkspaceWorkflowSummary(workspace: deliveryWorkspace).deliveryRoute, .updateDelivery)
        XCTAssertEqual(WorkspaceWorkflowSummary(workspace: passedWorkspace).deliveryRoute, .openDelivery)
    }

    @MainActor
    func testAutomationDeliveryHandoffPromptPrioritizesSqlArtifactWorkspace() {
        let genericDelivery = workspaceForWorkflowSummary(
            stage: "delivery",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "delivery-record",
                    label: "交付记录",
                    detail: "交付记录仍包含待补充内容",
                    status: "warning",
                    action: "delivery"
                )
            ]
        )
        let sqlWorkspace = workspaceForWorkflowSummary(
            stage: "delivery",
            id: "sql-delivery",
            name: "SQL Delivery",
            folder: "2026-05-31-sql-delivery",
            path: "/tmp/workspaces/2026-05-31-sql-delivery",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "sql-directory",
                    label: "SQL 产物",
                    detail: "交付记录包含 SQL 变更，但 sql/ 下缺少回滚 SQL 文件。",
                    status: "fail",
                    action: "sql"
                )
            ],
            sqlFiles: [
                WorkspaceSqlFile(
                    relativePath: "pay_log.sql",
                    path: "/tmp/workspaces/2026-05-31-sql-delivery/sql/pay_log.sql",
                    kind: "formal"
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [genericDelivery, sqlWorkspace])
        appState.selectedWorkspaceID = genericDelivery.id

        let prompt = appState.automationSignalHandoffPrompt(for: deliverySignal())

        XCTAssertTrue(prompt.contains("- 当前工作区: SQL Delivery"))
        XCTAssertTrue(prompt.contains("- SQL 文件: pay_log.sql"))
        XCTAssertTrue(prompt.contains("缺少回滚 SQL 文件"))
        XCTAssertFalse(prompt.contains("- 当前工作区: Workflow Summary"))
    }

    @MainActor
    func testAutomationDeliveryHandoffPromptFallsBackToDeliveryRecordIssue() {
        let cleanWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "clean-delivery",
            name: "Clean Delivery",
            folder: "2026-05-31-clean-delivery",
            path: "/tmp/workspaces/2026-05-31-clean-delivery",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "delivery-record",
                    label: "交付记录",
                    detail: "交付记录已存在且无明显占位内容",
                    status: "pass",
                    action: "delivery"
                ),
                WorkspaceHealthCheck(
                    id: "sql-directory",
                    label: "SQL 产物",
                    detail: "交付记录未声明 SQL 变更，sql/ 可留空。",
                    status: "pass",
                    action: "sql"
                )
            ]
        )
        let missingDelivery = workspaceForWorkflowSummary(
            stage: "delivery",
            id: "missing-delivery",
            name: "Missing Delivery",
            folder: "2026-05-31-missing-delivery",
            path: "/tmp/workspaces/2026-05-31-missing-delivery",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "delivery-record",
                    label: "交付记录",
                    detail: "缺少工作区交付记录",
                    status: "fail",
                    action: "delivery"
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [cleanWorkspace, missingDelivery])
        appState.selectedWorkspaceID = cleanWorkspace.id

        let prompt = appState.automationSignalHandoffPrompt(for: deliverySignal())

        XCTAssertTrue(prompt.contains("- 当前工作区: Missing Delivery"))
        XCTAssertTrue(prompt.contains("- 交付记录: /tmp/workspaces/2026-05-31-missing-delivery/交付记录.md"))
        XCTAssertTrue(prompt.contains("缺少工作区交付记录"))
        XCTAssertFalse(prompt.contains("- 当前工作区: Clean Delivery"))
    }

    @MainActor
    func testAutomationTaskHandoffPromptTargetsHighPriorityTaskWorkspace() {
        let selectedCleanWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "selected-clean",
            name: "Selected Clean",
            folder: "2026-05-31-selected-clean",
            path: "/tmp/workspaces/2026-05-31-selected-clean"
        )
        let taskWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "task-workspace",
            name: "Task Workspace",
            folder: "2026-05-31-task-workspace",
            path: "/tmp/workspaces/2026-05-31-task-workspace",
            tasks: [
                WorkspaceTask(
                    id: "task-high",
                    title: "补齐交付检查",
                    status: "todo",
                    detail: "需要先处理高优先任务。",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 12
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [selectedCleanWorkspace, taskWorkspace])
        appState.selectedWorkspaceID = selectedCleanWorkspace.id

        let prompt = appState.automationSignalHandoffPrompt(for: taskSignal())

        XCTAssertTrue(prompt.contains("- 当前工作区: Task Workspace"))
        XCTAssertTrue(prompt.contains("- 活跃任务: 1"))
        XCTAssertFalse(prompt.contains("- 当前工作区: Selected Clean"))
    }

    @MainActor
    func testAutomationTaskHandoffPromptSkipsDeferredTasks() {
        let deferredWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "deferred-task-workspace",
            name: "Deferred Task Workspace",
            folder: "2026-05-31-deferred-task-workspace",
            path: "/tmp/workspaces/2026-05-31-deferred-task-workspace",
            tasks: [
                WorkspaceTask(
                    id: "task-deferred-high",
                    title: "稍后复核",
                    status: "延期",
                    detail: "deferred until release window",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 18
                )
            ]
        )
        let activeWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "active-task-workspace",
            name: "Active Task Workspace",
            folder: "2026-05-31-active-task-workspace",
            path: "/tmp/workspaces/2026-05-31-active-task-workspace",
            tasks: [
                WorkspaceTask(
                    id: "task-active",
                    title: "继续验证",
                    status: "todo",
                    detail: "需要今天处理。",
                    priority: "medium",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 20
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [deferredWorkspace, activeWorkspace])
        appState.selectedWorkspaceID = deferredWorkspace.id

        let prompt = appState.automationSignalHandoffPrompt(for: taskSignal())

        XCTAssertTrue(prompt.contains("- 当前工作区: Active Task Workspace"))
        XCTAssertTrue(prompt.contains("- 活跃任务: 1"))
        XCTAssertFalse(prompt.contains("- 当前工作区: Deferred Task Workspace"))
    }

    func testNativeLocalAutomationCheckBuildsSignalsFromWorkspaceSummaries() {
        let activeWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "native-local-check-active",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "target-branch-availability",
                    label: "分支可用",
                    detail: "order missing target branch",
                    status: "fail",
                    action: "branches"
                )
            ],
            risks: [
                RiskAlert(title: "交付记录待补充", detail: "delivery record needs update"),
                RiskAlert(title: "目标分支不可用", detail: "order(feature/local-check)")
            ],
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "main",
                    worktree: "missing",
                    gitSummary: "target branch missing: feature/local-check",
                    worktreeExists: false,
                    sourceExists: true
                ),
                ServiceStatus(
                    name: "cashier",
                    branch: "feature/local-check",
                    worktree: "ready",
                    gitSummary: "dirty",
                    worktreeExists: true,
                    sourceExists: true
                )
            ],
            tasks: [
                WorkspaceTask(
                    id: "task-high",
                    title: "Fix blocker",
                    status: "todo",
                    detail: "priority=high",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 12
                ),
                WorkspaceTask(
                    id: "task-deferred",
                    title: "Later",
                    status: "延期",
                    detail: "deferred",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 20
                )
            ]
        )
        let archivedWorkspace = workspaceForWorkflowSummary(
            stage: "archived",
            id: "native-local-check-archived",
            risks: [RiskAlert(title: "归档风险", detail: "archived risk")],
            services: [
                ServiceStatus(
                    name: "archived-service",
                    branch: "main",
                    worktree: "missing",
                    gitSummary: "dirty",
                    worktreeExists: false,
                    sourceExists: true
                )
            ],
            tasks: [
                WorkspaceTask(
                    id: "archived-task",
                    title: "Archived task",
                    status: "todo",
                    detail: "priority=high",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 8
                )
            ]
        )

        let response = NativeLocalAutomationCheck.response(
            workspaces: [activeWorkspace, archivedWorkspace],
            generatedAt: "2026-06-29T04:30:00Z"
        )

        XCTAssertEqual(response.workspaceCount, 2)
        XCTAssertEqual(response.archivedWorkspaceCount, 1)
        XCTAssertEqual(response.riskCount, 2)
        XCTAssertEqual(response.deliveryIssueCount, 1)
        XCTAssertEqual(response.branchMismatchCount, 1)
        XCTAssertEqual(response.openTaskCount, 1)
        XCTAssertEqual(response.highPriorityTaskCount, 1)
        XCTAssertEqual(response.missingWorktreeCount, 1)
        XCTAssertEqual(response.dirtyServiceCount, 1)
        XCTAssertEqual(response.status, "review")
        XCTAssertEqual(
            response.signals.map { $0.id },
            [
                "refresh.completed",
                "risk.scan",
                "delivery.check",
                "branch.check",
                "worktree.check",
                "dirty-service.check",
                "task.check"
            ]
        )
    }

    func testNativeLocalAutomationCheckIgnoresCurrentBranchWhenTargetBranchExists() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "native-local-check-branch-available",
            branch: "feature/local-check",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "branch-alignment",
                    label: "分支对齐",
                    detail: "order current branch is main, target is feature/local-check",
                    status: "fail",
                    action: "branches"
                )
            ],
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "main",
                    worktree: "ready",
                    gitSummary: "source current: main; target branch available: feature/local-check",
                    worktreeExists: true,
                    sourceExists: true
                )
            ]
        )

        let response = NativeLocalAutomationCheck.response(
            workspaces: [workspace],
            generatedAt: "2026-06-29T04:45:00Z"
        )

        XCTAssertEqual(response.branchMismatchCount, 0)
        XCTAssertFalse(response.signals.contains { $0.id == "branch.check" })
        XCTAssertTrue(response.signals.contains { $0.id == "workspace.clean" })
    }

    func testNativeLocalAutomationCheckWritesNativeAuditMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-local-check-audit-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: root)
        }
        let response = NativeLocalAutomationCheck.response(
            workspaces: [
                workspaceForWorkflowSummary(
                    stage: "developing",
                    id: "native-local-check-clean",
                    services: []
                )
            ],
            generatedAt: "2026-06-29T04:35:00Z"
        )

        let audited = NativeLocalAutomationCheck.appendingAudit(
            to: response,
            auditRoot: root.path,
            actor: "Nexus Test",
            target: "/tmp/workspaces"
        )
        let events = try NativeAuditEventStore.loadRecent(auditRoot: root.path, limit: 1)

        XCTAssertNotNil(audited.auditEventId)
        XCTAssertNil(audited.auditError)
        XCTAssertEqual(events.first?.action, "automation.check.completed")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["signals"], response.signals.map { $0.id }.joined(separator: ","))
        XCTAssertEqual(events.first?.metadata["workspaceCount"], "1")
    }

    @MainActor
    func testAutomationBranchHandoffPromptTargetsUnavailableTargetBranchWorkspace() {
        let selectedCleanWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "selected-clean-branch",
            name: "Selected Clean Branch",
            folder: "2026-05-31-selected-clean-branch",
            path: "/tmp/workspaces/2026-05-31-selected-clean-branch"
        )
        let branchWorkspace = workspaceForWorkflowSummary(
            stage: "blocked",
            id: "branch-workspace",
            name: "Branch Workspace",
            folder: "2026-05-31-branch-workspace",
            path: "/tmp/workspaces/2026-05-31-branch-workspace",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "target-branch-availability",
                    label: "分支可用",
                    detail: "缺少目标分支: order(chen/target-branch)",
                    status: "fail",
                    action: "branches"
                )
            ],
            risks: [
                RiskAlert(title: "目标分支不可用", detail: "order(chen/target-branch)")
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [selectedCleanWorkspace, branchWorkspace])
        appState.selectedWorkspaceID = selectedCleanWorkspace.id

        let prompt = appState.automationSignalHandoffPrompt(for: branchSignal())

        XCTAssertTrue(prompt.contains("- 当前工作区: Branch Workspace"))
        XCTAssertTrue(prompt.contains("- 分支记录: /tmp/workspaces/2026-05-31-branch-workspace/branches.md"))
        XCTAssertTrue(prompt.contains("order(chen/target-branch)"))
        XCTAssertFalse(prompt.contains("- 当前工作区: Selected Clean Branch"))
    }

    @MainActor
    func testAutomationDirtyServiceHandoffPromptTargetsDirtyWorkspace() {
        let selectedCleanWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "selected-clean-dirty",
            name: "Selected Clean Dirty",
            folder: "2026-05-31-selected-clean-dirty",
            path: "/tmp/workspaces/2026-05-31-selected-clean-dirty"
        )
        let dirtyWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "dirty-workspace",
            name: "Dirty Workspace",
            folder: "2026-05-31-dirty-workspace",
            path: "/tmp/workspaces/2026-05-31-dirty-workspace",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "feature/workflow-summary",
                    worktree: "有未提交改动",
                    gitSummary: "干净",
                    worktreeExists: true,
                    sourceExists: true
                ),
                ServiceStatus(
                    name: "store-cashier",
                    branch: "feature/workflow-summary",
                    worktree: "干净",
                    gitSummary: "干净",
                    worktreeExists: true,
                    sourceExists: true
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [selectedCleanWorkspace, dirtyWorkspace])
        appState.selectedWorkspaceID = selectedCleanWorkspace.id

        let prompt = appState.automationSignalHandoffPrompt(for: dirtySignal())

        XCTAssertTrue(prompt.contains("- 当前工作区: Dirty Workspace"))
        XCTAssertTrue(prompt.contains("- Dirty 服务: order: worktree=有未提交改动, source=干净"))
        XCTAssertFalse(prompt.contains("- 当前工作区: Selected Clean Dirty"))
    }

    @MainActor
    func testAutomationWorktreeHandoffPromptIncludesMissingServiceEvidence() {
        let selectedCleanWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "selected-clean-worktree",
            name: "Selected Clean Worktree",
            folder: "2026-05-31-selected-clean-worktree",
            path: "/tmp/workspaces/2026-05-31-selected-clean-worktree"
        )
        let worktreeWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "worktree-workspace",
            name: "Worktree Workspace",
            folder: "2026-05-31-worktree-workspace",
            path: "/tmp/workspaces/2026-05-31-worktree-workspace",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "worktree-ready",
                    label: "Worktree 就绪",
                    detail: "缺少: commodity",
                    status: "fail",
                    action: "worktreeScript"
                )
            ],
            services: [
                ServiceStatus(
                    name: "commodity",
                    branch: "feature/workflow-summary",
                    worktree: "missing",
                    gitSummary: "source clean",
                    worktreeExists: false,
                    sourceExists: true
                ),
                ServiceStatus(
                    name: "order",
                    branch: "feature/workflow-summary",
                    worktree: "ready",
                    gitSummary: "clean",
                    worktreeExists: true,
                    sourceExists: true
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [selectedCleanWorkspace, worktreeWorkspace])
        appState.selectedWorkspaceID = selectedCleanWorkspace.id

        let prompt = appState.automationSignalHandoffPrompt(for: worktreeSignal())

        XCTAssertTrue(prompt.contains("- 当前工作区: Worktree Workspace"))
        XCTAssertTrue(prompt.contains("- 缺失 worktree: commodity: worktree=missing, source=exists, sourceGit=source clean"))
        XCTAssertTrue(prompt.contains("- Worktree 脚本: /tmp/workspaces/2026-05-31-worktree-workspace/scripts/worktree-commands.sh"))
        XCTAssertTrue(prompt.contains("Worktree 就绪 [fail]: 缺少: commodity"))
        XCTAssertTrue(prompt.contains("目标分支已确认"))
        XCTAssertFalse(prompt.contains("- 当前工作区: Selected Clean Worktree"))
    }

    @MainActor
    func testAutomationHandoffPromptIncludesNexusNextStepActions() {
        let scopingWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "scoping-workspace",
            name: "Scoping Workspace",
            folder: "2026-05-31-scoping-workspace",
            path: "/tmp/workspaces/2026-05-31-scoping-workspace",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "target-branch",
                    label: "目标分支",
                    detail: "目标分支待确认，后续 worktree 创建会被阻止。",
                    status: "fail",
                    action: "branches"
                )
            ],
            risks: [
                RiskAlert(title: "目标分支未确认", detail: "创建 worktree 前需要先定分支。")
            ],
            sessionActions: [
                WorkspaceSessionAction(
                    id: "confirm-target-branch",
                    label: "确认目标分支 / Confirm branch",
                    detail: "目标分支仍是待确认状态，创建 worktree 前需要先定分支。",
                    priority: "high",
                    status: "blocked",
                    instructionType: "git",
                    documentKey: "branches"
                ),
                WorkspaceSessionAction(
                    id: "confirm-services",
                    label: "确认服务范围 / Confirm services",
                    detail: "先补齐已确认服务，后续 worktree 和风险检查才有可靠目标。",
                    priority: "high",
                    status: "blocked",
                    instructionType: "risk",
                    documentKey: "services"
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [scopingWorkspace])

        let prompt = appState.automationSignalHandoffPrompt(for: riskSignal())

        XCTAssertTrue(prompt.contains("- 当前工作区: Scoping Workspace"))
        XCTAssertTrue(prompt.contains("- 主路径回答: 当前阶段:"))
        XCTAssertTrue(prompt.contains("主证据:"))
        XCTAssertTrue(prompt.contains("Nexus 推荐动作"))
        XCTAssertTrue(prompt.contains("[high/blocked] 确认目标分支 / Confirm branch"))
        XCTAssertTrue(prompt.contains("文档: branches"))
        XCTAssertTrue(prompt.contains("[high/blocked] 确认服务范围 / Confirm services"))
    }

    @MainActor
    func testAutomationRiskActionCopiesRiskReviewPromptForRiskWorkspace() async {
        let selectedCleanWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "selected-clean-risk",
            name: "Selected Clean Risk",
            folder: "2026-05-31-selected-clean-risk",
            path: "/tmp/workspaces/2026-05-31-selected-clean-risk"
        )
        let riskWorkspace = workspaceForWorkflowSummary(
            stage: "blocked",
            id: "risk-workspace",
            name: "Risk Workspace",
            folder: "2026-05-31-risk-workspace",
            path: "/tmp/workspaces/2026-05-31-risk-workspace",
            healthChecks: [
                WorkspaceHealthCheck(
                    id: "status-readiness",
                    label: "状态文档",
                    detail: "STATUS.md 仍是待补充。",
                    status: "warning",
                    action: "status"
                )
            ],
            risks: [
                RiskAlert(title: "状态待补充", detail: "需要先确认当前阻塞项。")
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [selectedCleanWorkspace, riskWorkspace])
        appState.selectedWorkspaceID = selectedCleanWorkspace.id
        NSPasteboard.general.clearContents()

        await appState.runAutomationSignalAction(riskSignal())

        let copiedPrompt = appState.lastCopiedCodexHandoffPayload
            ?? NSPasteboard.general.string(forType: .string)
            ?? ""
        XCTAssertEqual(appState.selectedFilter, .risky)
        XCTAssertEqual(appState.selectedWorkspaceID, riskWorkspace.id)
        XCTAssertTrue(copiedPrompt.contains("Risk Workspace"))
        XCTAssertTrue(copiedPrompt.contains("状态待补充"))
        XCTAssertTrue(copiedPrompt.contains("STATUS.md 仍是待补充"))
        XCTAssertTrue(appState.codexHandoffFeedback?.title.contains("风险复核") == true)
        XCTAssertFalse(copiedPrompt.contains("Selected Clean Risk"))
    }

    @MainActor
    func testCodexSessionLinksFlowIntoHandoffPrompts() async {
        let workspace = workspaceForWorkflowSummary(
            stage: "delivery",
            id: "session-workspace",
            name: "Session Workspace",
            folder: "2026-06-01-session-workspace",
            path: "/tmp/workspaces/2026-06-01-session-workspace",
            risks: [
                RiskAlert(title: "交付待复核", detail: "需要延续已有 Codex 会话。")
            ],
            tasks: [
                WorkspaceTask(
                    id: "session-task",
                    title: "Follow existing session",
                    status: "待办",
                    detail: "Continue from the bound Codex session.",
                    priority: "high",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: 12
                )
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [workspace])
        appState.selectedWorkspaceID = workspace.id
        appState.codexSessionLinksByWorkspace[workspace.id] = [
            CodexSessionLink(
                id: "session-1",
                title: "Architecture thread",
                url: "codex://thread/session-1",
                notes: "Resume design review",
                createdAt: "2026-06-01T10:00:00Z",
                lastOpenedAt: "2026-06-01T10:30:00Z"
            )
        ]

        let prompts = [
            appState.workspaceHandoffPrompt(for: workspace),
            appState.deliveryUpdatePrompt(for: workspace),
            appState.validationPrHandoffPrompt(for: workspace),
            appState.riskReviewPrompt(for: workspace),
            appState.automationSignalHandoffPrompt(for: riskSignal()),
            await appState.workspaceTaskHandoffPrompt(for: workspace.tasks[0], in: workspace)
        ]

        for prompt in prompts {
            XCTAssertTrue(prompt.contains("Architecture thread"))
            XCTAssertTrue(prompt.contains("codex://thread/session-1"))
        }
        XCTAssertTrue(prompts[0].contains("## 主路径回答"))
        XCTAssertTrue(prompts[0].contains("- 当前阶段:"))
        XCTAssertTrue(prompts[0].contains("- 主证据:"))
        XCTAssertTrue(prompts[0].contains("notes: Resume design review"))
        XCTAssertTrue(prompts[4].contains("- Codex 会话: Architecture thread: codex://thread/session-1"))
    }

    private func workspaceForWorkflowSummary(
        stage: String,
        id: String? = nil,
        name: String = "Workflow Summary",
        folder: String? = nil,
        path: String? = nil,
        branch: String = "feature/workflow-summary",
        riskLevel: RiskLevel? = nil,
        healthChecks: [WorkspaceHealthCheck] = [],
        activities: [ActivityEvent] = [],
        risks: [RiskAlert] = [],
        sqlFiles: [WorkspaceSqlFile] = [],
        sessionActions: [WorkspaceSessionAction] = [],
        services: [ServiceStatus]? = nil,
        tasks: [WorkspaceTask]? = nil
    ) -> WorkspaceSummary {
        let workspaceID = id ?? "workflow-summary-\(stage)"
        let workspaceFolder = folder ?? workspaceID
        let workspacePath = path ?? "~/ks_project/workspaces/\(workspaceFolder)"

        return WorkspaceSummary(
            id: workspaceID,
            name: name,
            folder: workspaceFolder,
            path: workspacePath,
            branch: branch,
            state: .developing,
            riskLevel: riskLevel ?? (risks.isEmpty ? .low : .medium),
            aiState: "Ready",
            worktreeState: "Ready",
            documentLinks: ["delivery": "\(workspacePath)/交付记录.md"],
            sqlFiles: sqlFiles,
            services: services ?? [
                ServiceStatus(name: "order", branch: "feature/workflow-summary", worktree: "ready", gitSummary: "clean", worktreeExists: true, sourceExists: true)
            ],
            activities: activities,
            risks: risks,
            healthChecks: healthChecks,
            sessionActions: sessionActions,
            lifecycle: WorkspaceLifecycle(
                stage: stage,
                label: "Workflow",
                detail: "Workflow test fixture",
                progress: 80,
                nextAction: "Continue",
                documentKey: "delivery"
            ),
            tasks: tasks ?? [
                WorkspaceTask(
                    id: "done-task",
                    title: "Done",
                    status: "done",
                    detail: "Done",
                    priority: "normal",
                    source: "workspace",
                    sourceEventID: nil,
                    sourceLine: nil
                )
            ]
        )
    }

    private func readyDemandReadiness() -> DemandIntakeReadinessEvidence {
        DemandIntakeReadinessEvidence(
            status: .ready,
            reason: "ready",
            evidence: ["需求/"],
            checks: [],
            unresolvedP0Count: 0,
            requirementHasContent: true,
            scopeFrozen: true,
            requirementTasksReady: true
        )
    }

    private func readyScopeFreeze() -> ScopeFreezeEvidence {
        ScopeFreezeEvidence(
            status: .ready,
            reason: "ready",
            evidence: ["需求/scope.md"],
            checks: [],
            scopePath: "/tmp/scope.md",
            revision: .missing,
            hasInScope: true,
            hasOutOfScope: true,
            scopeFrozen: true,
            scopeChangeDeclared: false,
            scopeChangeAudited: true,
            unresolvedP0Count: 0
        )
    }

    private func setupWorktreeResponse(
        created: [WorktreeSetupResult] = [],
        skipped: [WorktreeSetupResult] = [],
        failed: [WorktreeSetupResult] = []
    ) -> SetupWorktreesResponse {
        SetupWorktreesResponse(
            workspacePath: "/workspace",
            targetBranch: "feature/worktree",
            command: "git worktree add ...",
            created: created,
            skipped: skipped,
            failed: failed
        )
    }

    private func writeDemandIntakeFixture(demandDir: URL, scope: String) throws {
        try "# 需求确认卡\n\n- 真实需求目标：补齐交易快照。\n- 用户流程：保存订单时写入快照。\n- 验收标准：可查询历史快照。\n".write(
            to: demandDir.appendingPathComponent("requirement.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 待确认问题\n\n## P0 阻塞开发\n\n- [x] 已确认无需新增字段。\n".write(
            to: demandDir.appendingPathComponent("questions.md"),
            atomically: true,
            encoding: .utf8
        )
        try scope.write(
            to: demandDir.appendingPathComponent("scope.md"),
            atomically: true,
            encoding: .utf8
        )
        try """
        # 需求列表

        | 需求点 | 状态 | 优先级 | 来源 | 说明 |
        | --- | --- | --- | --- | --- |
        | 新增交易快照写入 | 待办 | P0 | 蓝湖 | 保存订单时记录快照 |
        """.write(
            to: demandDir.appendingPathComponent("tasks.md"),
            atomically: true,
            encoding: .utf8
        )
        try "# 需求交付\n\n- 预检完成。\n".write(
            to: demandDir.appendingPathComponent("delivery.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func writeBranchPolicyFixture(workspaceRoot: URL, branch: String) throws {
        try """
        # Branches

        - 目标分支: \(branch)
        - 基线: main
        - 分支策略: 使用已确认目标分支创建 workspace-local worktree。
        """.write(
            to: workspaceRoot.appendingPathComponent("branches.md"),
            atomically: true,
            encoding: .utf8
        )
    }

    private func readyServiceBranch(for workspace: WorkspaceSummary) -> ServiceBranchEvidence {
        ServiceBranchEvidence(
            status: .ready,
            reason: "ready",
            evidence: ["services.md", "branches.md"],
            checks: [],
            servicesPath: "\(workspace.path)/services.md",
            branchesPath: "\(workspace.path)/branches.md",
            branchConfirmed: true,
            servicesConfirmed: true,
            branchPolicyRecorded: true,
            missingSourceServices: [],
            targetBranchMissingServices: []
        )
    }

    private func demandIntakeStatus(at demandDir: URL) -> DemandIntakeStatus {
        let files: [(String, String, String)] = [
            ("requirement", "需求确认卡", "requirement.md"),
            ("questions", "待确认问题", "questions.md"),
            ("scope", "开发范围", "scope.md"),
            ("tasks", "需求列表", "tasks.md"),
            ("delivery", "需求交付", "delivery.md")
        ]
        let statuses = files.map { key, label, filename in
            let path = demandDir.appendingPathComponent(filename).path
            return DemandIntakeFileStatus(
                key: key,
                label: label,
                filename: filename,
                path: path,
                exists: FileManager.default.fileExists(atPath: path)
            )
        }
        return DemandIntakeStatus(
            directoryPath: demandDir.path,
            exists: true,
            ready: statuses.allSatisfy(\.exists),
            missingCount: statuses.filter { !$0.exists }.count,
            files: statuses
        )
    }

    @MainActor
    private func appStateForAutomationTests(workspaces: [WorkspaceSummary]) -> AppState {
        let defaults = UserDefaults(suiteName: "NexusAppTests-\(UUID().uuidString)")!
        return AppState(
            workspaces: workspaces,
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: "/tmp/workspaces",
            sourceReposRoot: "/tmp/source-repos",
            docsRoot: "/tmp/docs",
            defaults: defaults
        )
    }

    private func lifecycleProofAuditEvents(for workspace: WorkspaceSummary) -> [AuditEvent] {
        Array(NativeLifecycleProofEvidence.requiredAuditActions.enumerated().map { offset, action in
            AuditEvent(
                id: "proof-\(offset)",
                timestamp: String(format: "2026-06-30T00:%02d:00Z", offset),
                actor: "Nexus Test",
                action: action,
                target: workspace.path,
                summary: "Lifecycle proof \(action) for \(workspace.folder)",
                metadata: action == "workspace_lifecycle.updated"
                    ? ["workspace": workspace.path, "state": "archived"]
                    : ["workspace": workspace.path]
            )
        }.reversed())
    }

    private func scannedWorkspace(
        folder: String,
        workspacesRoot: URL,
        sourceRoot: URL
    ) throws -> WorkspaceSummary {
        let dashboard = try NativeWorkspaceScanner.scan(
            workspacesRoot: workspacesRoot.path,
            sourceReposRoot: sourceRoot.path,
            docsRoot: "/tmp/docs"
        )
        let snapshot = try XCTUnwrap(dashboard.workspaces.first { $0.folder == folder })
        return WorkspaceSummary(snapshot: snapshot)
    }

    private func environmentHealth(
        ready: Bool,
        workspaceCount: Int,
        sourceRepoCount: Int,
        blockers: [String] = [],
        warnings: [String] = []
    ) -> NativeEnvironmentHealth {
        NativeEnvironmentHealth(
            generatedAt: "2026-06-01T12:00:00Z",
            ready: ready,
            pathChecks: [],
            toolChecks: [],
            workspaceCount: workspaceCount,
            sourceRepoCount: sourceRepoCount,
            blockers: blockers,
            warnings: warnings
        )
    }

    private func deliverySignal() -> LocalAutomationSignal {
        LocalAutomationSignal(
            id: "delivery.check",
            kind: "delivery",
            severity: "warning",
            title: "交付检查 / Delivery check",
            detail: "2 workspaces need delivery-record attention.",
            count: 2,
            action: "update-delivery"
        )
    }

    private func taskSignal() -> LocalAutomationSignal {
        LocalAutomationSignal(
            id: "task.check",
            kind: "task",
            severity: "warning",
            title: "任务检查 / Task check",
            detail: "1 open tasks, 1 high priority.",
            count: 1,
            action: "review-tasks"
        )
    }

    private func branchSignal() -> LocalAutomationSignal {
        LocalAutomationSignal(
            id: "branch.check",
            kind: "branch",
            severity: "warning",
            title: "目标分支可用性 / Target branch availability",
            detail: "1 workspaces have missing or unavailable target branches.",
            count: 1,
            action: "review-branches"
        )
    }

    private func dirtySignal() -> LocalAutomationSignal {
        LocalAutomationSignal(
            id: "dirty-service.check",
            kind: "git",
            severity: "warning",
            title: "Git 状态检查 / Dirty services",
            detail: "1 services have uncommitted git changes.",
            count: 1,
            action: "review-dirty-services"
        )
    }

    private func worktreeSignal() -> LocalAutomationSignal {
        LocalAutomationSignal(
            id: "worktree.check",
            kind: "worktree",
            severity: "warning",
            title: "Worktree 检查 / Worktree check",
            detail: "1 workspace-local worktrees are missing.",
            count: 1,
            action: "review-worktrees"
        )
    }

    private func riskSignal() -> LocalAutomationSignal {
        LocalAutomationSignal(
            id: "risk.check",
            kind: "risk",
            severity: "warning",
            title: "风险检查 / Risk check",
            detail: "1 workspaces have active risk signals.",
            count: 1,
            action: "review-risk"
        )
    }

    private func assertThrowsUnavailable(
        _ expression: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        do {
            try await expression()
            XCTFail("Expected async expression to throw", file: file, line: line)
        } catch {
            XCTAssertTrue(
                error.localizedDescription.contains("unavailable"),
                error.localizedDescription,
                file: file,
                line: line
            )
        }
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        if process.terminationStatus != 0 {
            let error = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            XCTFail("git \(arguments.joined(separator: " ")) failed: \(error)")
        }
    }
}
