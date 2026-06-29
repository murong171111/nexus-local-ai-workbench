import NexusBridge
import AppKit
import XCTest
@testable import NexusApp

final class ModelBehaviorTests: XCTestCase {
    func testNativeModelLayeringKeepsWorkflowLogicOutOfBaseModels() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let appSources = packageRoot.appendingPathComponent("Sources/NexusApp")
        let modelsPath = appSources.appendingPathComponent("Models.swift")
        let models = try String(contentsOf: modelsPath, encoding: .utf8)

        let forbiddenModelSymbols = [
            "struct WorkspaceBoardColumn",
            "enum WorkspaceBoardScope",
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
            "struct DemandIntakeReadinessEvidence",
            "struct DemandIntakeM1ActionPolicy",
            "struct TaskStatusUpdate",
            "struct TaskStatusMutationPolicy",
            "struct CommandCenterLayoutPolicy",
            "struct ServiceWorktreeRowState",
            "struct WorkspaceMainStageEvidenceLink",
            "struct WorkspaceStageAnswer",
            "struct WorkspaceListStageBadge",
            "struct WorkspaceListSummary",
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
            "WorkspaceDetailNavigation.swift",
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
        XCTAssertEqual(appState.focusedTaskCenterItemID, "\(sameWorkspace.id):same-next")
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

        let unconfirmedPolicy = DemandIntakeM1ActionPolicy(
            status: status,
            confirmed: false,
            isInitializing: false,
            requirementFileExists: false
        )
        let confirmedPolicy = DemandIntakeM1ActionPolicy(
            status: status,
            confirmed: true,
            isInitializing: false,
            requirementFileExists: true
        )

        XCTAssertEqual(unconfirmedPolicy.actions.map(\.kind), [.initializeOrRepair, .openRequirement, .copyHandoffPrompt])
        XCTAssertTrue(unconfirmedPolicy.keepsAIInvocationOutOfM1)
        XCTAssertFalse(unconfirmedPolicy.actions.first { $0.kind == .initializeOrRepair }?.isEnabled ?? true)
        XCTAssertFalse(unconfirmedPolicy.actions.first { $0.kind == .openRequirement }?.isEnabled ?? true)
        XCTAssertTrue(confirmedPolicy.actions.first { $0.kind == .initializeOrRepair }?.isEnabled ?? false)
        XCTAssertTrue(confirmedPolicy.actions.first { $0.kind == .openRequirement }?.isEnabled ?? false)
        XCTAssertTrue(confirmedPolicy.actions.first { $0.kind == .copyHandoffPrompt }?.label.contains("交接") ?? false)
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
                WorkspaceBoardColumn.visibleStageOrder.contains(stage.id),
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
    func testAppStateBuildsMainWorkflowAcceptanceEvidenceFromCurrentWorkspace() {
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

        let acceptance = appState.mainWorkflowAcceptanceEvidence(for: workspace)

        XCTAssertEqual(acceptance.checks.map(\.id), MainWorkflowAcceptanceRequirement.allCases)
        XCTAssertEqual(acceptance.coveredWorktreeStates, ServiceWorktreeRowStateKind.allCases)
        XCTAssertTrue(acceptance.missingWorktreeStates.isEmpty)
        XCTAssertEqual(acceptance.checks.first { $0.id == .legacyBoundary }?.status, .ready)
        XCTAssertEqual(acceptance.checks.first { $0.id == .worktreeStateCoverage }?.status, .ready)
        XCTAssertEqual(acceptance.checks.first { $0.id == .stageCoverage }?.status, .blocked)
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
        XCTAssertEqual(preview.migrationSummary, "0/10 Native domains")
        XCTAssertEqual(preview.domains.map(\.status), Array(repeating: .blocked, count: NativeLocalCoreDomain.allCases.count))
        XCTAssertEqual(partiallyNative.status, .blocked)
        XCTAssertEqual(partiallyNative.migrationSummary, "5/10 Native domains · 1 partial")
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
                "native/Nexus/Sources/NexusApp/NativeWorkspaceTaskStore.swift"
            ) ?? false
        )
        XCTAssertTrue(
            fullyNative.domains.first { $0.domain == .readiness }?.evidence.contains(
                "native/Nexus/Sources/NexusApp/NativeWorkspaceLifecycleStore.swift"
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
        XCTAssertEqual(fullyNative.migrationSummary, "10/10 Native domains")
        XCTAssertFalse(fullyNative.bridgeIsLegacyDependency)
        XCTAssertTrue(fullyNative.reason.contains("M2 Native Local Core"))
    }

    func testNativeLocalCoreEvidenceReviewsPartialDomainsWithoutBlockers() {
        let evidence = NativeLocalCoreEvidence.resolve(
            bridgeMode: "Swift Native local core",
            nativeDomains: Set(NativeLocalCoreDomain.allCases).subtracting([.workspaceScanning, .gitWorktreeStatus]),
            partialNativeDomains: [.workspaceScanning, .gitWorktreeStatus]
        )

        XCTAssertEqual(evidence.status, .review)
        XCTAssertEqual(evidence.migrationSummary, "8/10 Native domains · 2 partial")
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
        XCTAssertEqual(events.first?.action, "workspace.created")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["services"], "order,store-cashier")
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
                )
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
            )
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
            )
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
        XCTAssertEqual(events.first?.action, "workspace_task.updated")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["taskId"], "2026-05-28-task-status:agent-1")
        XCTAssertEqual(events.first?.metadata["status"], "延期")
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
                )
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
            )
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
        XCTAssertEqual(events.first?.action, "workspace_lifecycle.updated")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["previousState"], "developing")
        XCTAssertEqual(events.first?.metadata["state"], "archived")
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

    func testNativeDemandIntakeStoreInitializesMissingFilesWithoutOverwriting() throws {
        let workspaceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-native-demand-init-\(UUID().uuidString)")
        let demandURL = workspaceURL.appendingPathComponent("需求")
        defer {
            try? FileManager.default.removeItem(at: workspaceURL)
        }
        try FileManager.default.createDirectory(at: demandURL, withIntermediateDirectories: true)
        try "# Existing questions\n".write(to: demandURL.appendingPathComponent("questions.md"), atomically: true, encoding: .utf8)

        let response = try NativeDemandIntakeStore.initialize(
            workspacePath: workspaceURL.path,
            demandName: "会员权益页",
            lanhuLink: "https://lanhu.example/design",
            notes: "先确认首屏",
            confirmed: true
        )

        XCTAssertEqual(response.status.ready, true)
        XCTAssertEqual(response.status.missingCount, 0)
        XCTAssertEqual(response.createdFiles, ["requirement.md", "scope.md", "tasks.md", "delivery.md"])
        XCTAssertTrue(try String(contentsOf: demandURL.appendingPathComponent("requirement.md"), encoding: .utf8).contains("会员权益页"))
        XCTAssertTrue(try String(contentsOf: demandURL.appendingPathComponent("requirement.md"), encoding: .utf8).contains("https://lanhu.example/design"))
        XCTAssertEqual(try String(contentsOf: demandURL.appendingPathComponent("questions.md"), encoding: .utf8), "# Existing questions\n")
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
            XCTAssertTrue(error.localizedDescription.contains("file path exists but is not a file"))
        }
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
        | 删除 bridge 兜底 | 待办 | 等 Git/worktree 规则补齐 | medium |
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
        XCTAssertEqual(snapshot.tasks?.map(\.source), ["workspace", "workspace"])
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
        XCTAssertTrue(evidence.checks.first { $0.requirement == .legacyDeletion }?.detail.contains("M2 Native Local Core is not ready") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .legacyDeletion }?.detail.contains("No real archived workspace lifecycle proof") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .legacyDeletion }?.detail.contains("Next step: follow the Native deletion order") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .legacyDeletion }?.evidence.contains("\(root)/src-tauri") == true)
        XCTAssertTrue(evidence.checks.first { $0.requirement == .releaseReadiness }?.detail.contains("Release workflow does not build a Native app artifact") == true)
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

        let releaseReadiness = evidence.checks.first { $0.requirement == .releaseReadiness }
        XCTAssertEqual(releaseReadiness?.status, .blocked)
        XCTAssertFalse(releaseReadiness?.detail.contains("Release workflow does not build a Native app artifact.") == true)
        XCTAssertFalse(releaseReadiness?.detail.contains("Release workflow does not package Native DMG artifacts.") == true)
        XCTAssertTrue(releaseReadiness?.detail.contains("Release workflow does not sign and notarize Native artifacts.") == true)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .installTarget }?.status, .blocked)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .widgetExtension }?.status, .blocked)
        XCTAssertEqual(evidence.checks.first { $0.requirement == .legacyDeletion }?.status, .blocked)
        XCTAssertEqual(evidence.readinessSummary, "0/4 Ready checks")
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
            "\(root)/docs/legacy-retirement-audit.md",
            "\(root)/docs/distribution.md",
            "\(root)/docs/release-process.md",
            "\(root)/.github/workflows/ci.yml",
            "\(root)/.github/workflows/release.yml"
        ]
        let missingEntitlements = readyFiles.subtracting(["\(root)/native/NexusWidget/NexusWidget.entitlements"])
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
                    default:
                        return false
                    }
                }
            )
        }

        XCTAssertEqual(evidence(files: missingEntitlements).checks.first { $0.requirement == .widgetExtension }?.status, .blocked)
        let widgetTarget = evidence(files: readyFiles).checks.first { $0.requirement == .widgetExtension }
        XCTAssertEqual(widgetTarget?.status, .ready)
        XCTAssertTrue(widgetTarget?.detail.contains("App Group entitlements") == true)
    }

    func testNativeDistributionReadinessCanPassAfterNativeInstallAndDeletionProof() {
        let root = "/repo"
        let files: Set<String> = [
            "\(root)/native/Nexus/Package.swift",
            "\(root)/native/Nexus/Nexus.xcodeproj/project.pbxproj",
            "\(root)/native/Nexus/Scripts/package-dmg.sh",
            "\(root)/widget/NexusWidget/NexusWidget.swift",
            "\(root)/native/NexusWidget/Sources/NexusWidget/NexusWidget.swift",
            "\(root)/native/NexusWidget/Info.plist",
            "\(root)/native/NexusWidget/NexusWidget.entitlements",
            "\(root)/docs/legacy-retirement-audit.md",
            "\(root)/docs/distribution.md",
            "\(root)/docs/release-process.md",
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
                case "swift test":
                    return path.hasSuffix("ci.yml")
                case "native/Nexus", "NexusNative", "Swift":
                    return path.hasSuffix("release.yml")
                        || path.hasSuffix("distribution.md")
                        || path.hasSuffix("release-process.md")
                case "native:build":
                    return path.hasSuffix("release.yml")
                case "package-dmg.sh", ".dmg", "codesign", "notarytool":
                    return path.hasSuffix("release.yml")
                case "com.apple.widgetkit-extension":
                    return path.hasSuffix("Info.plist")
                case "group.com.ks.nexus":
                    return path.hasSuffix("NexusWidget.entitlements")
                case "Native Deletion Order", "Current Legacy Surfaces":
                    return path.hasSuffix("legacy-retirement-audit.md")
                default:
                    return false
                }
            }
        )

        XCTAssertTrue(evidence.ready)
        XCTAssertEqual(evidence.status, .ready)
        XCTAssertEqual(evidence.readinessSummary, "4/4 Ready checks")
        XCTAssertTrue(evidence.checks.allSatisfy { $0.status == .ready })
    }

    @MainActor
    func testAppStateExposesNativeLocalCoreEvidenceFromBridgeMode() {
        let appState = appStateForAutomationTests(workspaces: [])

        let evidence = appState.nativeLocalCoreEvidence()

        XCTAssertEqual(evidence.status, .ready)
        XCTAssertEqual(evidence.domains.map(\.domain), NativeLocalCoreDomain.allCases)
        XCTAssertEqual(evidence.migrationSummary, "10/10 Native domains")
        XCTAssertEqual(
            evidence.domains.filter { $0.status == .ready }.map(\.domain),
            [
                .workspaceScanning,
                .documentInventory,
                .demandIntake,
                .readiness,
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

        XCTAssertTrue(appStateForAutomationTests(workspaces: [archived]).nativeLifecycleProofAvailable())
        XCTAssertFalse(appStateForAutomationTests(workspaces: [blocked]).nativeLifecycleProofAvailable())
        XCTAssertFalse(appStateForAutomationTests(workspaces: []).nativeLifecycleProofAvailable())
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
        XCTAssertTrue(layout.secondaryActions.isSecondarySurface)
        XCTAssertEqual(layout.secondaryActions.groups, [.handoff, .next, .local])
        XCTAssertEqual(layout.secondaryActions.groups.map(\.title), [
            "交接 / Handoff",
            "下一步 / Next",
            "本地打开 / Local"
        ])
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

    func testWorkspaceBoardColumnsFollowMainWorkflowOrder() {
        let createdWorkspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "board-created",
            name: "已建档"
        )
        let deliveryWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "board-delivery",
            name: "交付检查",
            healthChecks: [
                WorkspaceHealthCheck(id: "demand-intake", label: "需求预检", detail: "需求预检已就绪", status: "pass", action: "demandIntake")
            ]
        )
        let archivedWorkspace = workspaceForWorkflowSummary(
            stage: "archived",
            id: "board-archive",
            name: "已归档"
        )

        let columns = WorkspaceBoardColumn.columns(for: [archivedWorkspace, deliveryWorkspace, createdWorkspace])

        XCTAssertEqual(columns.map(\.id), WorkspaceBoardColumn.visibleStageOrder)
        XCTAssertEqual(columns.first(where: { $0.id == .created })?.workspaces.map(\.id), ["board-created"])
        XCTAssertEqual(columns.first(where: { $0.id == .deliveryCheck })?.workspaces.map(\.id), ["board-delivery"])
        XCTAssertEqual(columns.first(where: { $0.id == .archived })?.workspaces.map(\.id), ["board-archive"])
    }

    func testWorkspaceBoardScopeFiltersWithoutChangingColumnOrder() {
        let createdWorkspace = workspaceForWorkflowSummary(
            stage: "scoping",
            id: "board-created",
            name: "已建档"
        )
        let deliveryWorkspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "board-delivery",
            name: "交付检查",
            healthChecks: [
                WorkspaceHealthCheck(id: "demand-intake", label: "需求预检", detail: "需求预检已就绪", status: "pass", action: "demandIntake")
            ]
        )
        let archivedWorkspace = workspaceForWorkflowSummary(
            stage: "archived",
            id: "board-archive",
            name: "已归档"
        )
        let workspaces = [archivedWorkspace, deliveryWorkspace, createdWorkspace]

        let attentionColumns = WorkspaceBoardColumn.columns(for: workspaces, scope: .attention)
        let deliveryColumns = WorkspaceBoardColumn.columns(for: workspaces, scope: .delivery)
        let archivedColumns = WorkspaceBoardColumn.columns(for: workspaces, scope: .archived)

        XCTAssertEqual(attentionColumns.map(\.id), WorkspaceBoardColumn.visibleStageOrder)
        XCTAssertEqual(attentionColumns.flatMap { $0.workspaces.map(\.id) }, ["board-created", "board-delivery"])
        XCTAssertEqual(deliveryColumns.flatMap { $0.workspaces.map(\.id) }, ["board-delivery"])
        XCTAssertEqual(archivedColumns.flatMap { $0.workspaces.map(\.id) }, ["board-archive"])
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
            scopePath: "\(workspace.path)/需求/scope.md",
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
        XCTAssertEqual(events.first?.action, "scope.freeze_confirmed")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["scopePath"], response.path)
        XCTAssertEqual(events.first?.metadata["status"], "next")
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

    func testServiceBranchEvidenceBlocksUnavailableTargetBranch() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "service-branch-unavailable-target",
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

        XCTAssertEqual(serviceBranch.status, .blocked)
        XCTAssertEqual(serviceBranch.targetBranchMissingServices, ["order"])
        XCTAssertEqual(serviceBranch.checks.first { $0.id == "target-branch-availability" }?.status, .blocked)
        XCTAssertEqual(stage.id, .serviceBranchConfirm)
        XCTAssertEqual(stage.primaryAction, .document("branches"))
    }

    func testServiceBranchEvidenceKeepsMissingWorktreeInWorktreeGate() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "service-branch-missing-worktree",
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

    func testWorktreeSetupEvidenceBlocksUnavailableTargetBranch() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "worktree-mismatch",
            branch: "feature/worktree",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "dev",
                    worktree: "ready",
                    gitSummary: "target branch missing: feature/worktree",
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

        XCTAssertEqual(worktree.status, .blocked)
        XCTAssertEqual(worktree.branchMismatchServices, ["order(feature/worktree)"])
        XCTAssertEqual(worktree.setupPlan.map(\.action), [.blocked])
        XCTAssertEqual(worktree.setupPlan.first?.currentBranch, "dev")
        XCTAssertTrue(worktree.setupPlan.first?.reason.contains("未发现目标分支") ?? false)
        XCTAssertEqual(worktree.mutationPolicy.blockedServices, ["order"])
        XCTAssertFalse(worktree.mutationPolicy.canRequestConfirmation)
        XCTAssertFalse(worktree.mutationPolicy.canRun(afterConfirmation: true))
        XCTAssertEqual(stage.id, .worktreeSetup)
        XCTAssertEqual(stage.primaryAction, .document("branches"))
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
                confirmed: true
            )
        )

        XCTAssertEqual(response.created.map(\.service), ["order"])
        XCTAssertTrue(response.skipped.isEmpty)
        XCTAssertTrue(response.failed.isEmpty)
        XCTAssertTrue(response.command.contains("git -C"))
        XCTAssertTrue(FileManager.default.fileExists(atPath: workspace.appendingPathComponent("repos/order/.git").path))

        let second = try NativeWorktreeSetupStore.setup(
            request: SetupWorktreesRequest(
                workspacePath: workspace.path,
                sourceReposRoot: sourceRoot.path,
                services: ["order"],
                targetBranch: "feature/native-setup",
                confirmed: true
            )
        )

        XCTAssertTrue(second.created.isEmpty)
        XCTAssertEqual(second.skipped.map(\.service), ["order"])
        XCTAssertTrue(second.failed.isEmpty)
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

    func testDeliveryRecordWritePlanAppendsCurrentGateSnapshot() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "delivery-record-write",
            name: "Delivery Record Write",
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

    func testArchiveChecklistWritePlanAppendsFinalChecklistWithoutLifecycleWriteback() {
        let workspace = workspaceForWorkflowSummary(
            stage: "done",
            id: "archive-checklist-write",
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

    func testValidationPrWritePlanAppendsReviewSnapshotWithoutCallingGithub() {
        let workspace = workspaceForWorkflowSummary(
            stage: "done",
            id: "validation-pr-write",
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

    func testDemandTaskTransferPlanFindsNewIntakeTasksAndUpdatesMainStage() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-demand-task-transfer-\(UUID().uuidString)")
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
        XCTAssertEqual(events.first?.action, "demand_tasks.transferred")
        XCTAssertEqual(events.first?.actor, "Nexus Test")
        XCTAssertEqual(events.first?.metadata["transferredCount"], "1")
        XCTAssertEqual(events.first?.metadata["duplicateCount"], "1")
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
