import XCTest
import NexusBridge
@testable import NexusApp

final class ModelBehaviorTests: XCTestCase {
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
            bridgeMode: "preview"
        )

        XCTAssertEqual(summary.menuTitle, "Nexus 1")
        XCTAssertEqual(summary.systemImage, "pause.circle.fill")
        XCTAssertEqual(summary.statusLine, "1 blocked workspaces need attention")
        XCTAssertTrue(summary.clipboardText.contains("Active workspace: Pay Log"))
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

        XCTAssertTrue(TaskCenterFilter.high.matches(blocked))
        XCTAssertTrue(TaskCenterFilter.agent.matches(agentDeferred))
        XCTAssertTrue(TaskCenterFilter.deferred.matches(agentDeferred))
        XCTAssertFalse(TaskCenterFilter.agent.matches(blocked))
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
            worktreeCommand: ""
        )

        let workspace = WorkspaceSummary(snapshot: snapshot)

        XCTAssertEqual(workspace.sqlFiles.map(\.relativePath), ["pay_log.sql", "pay_log_rollback.sql"])
        XCTAssertEqual(workspace.sqlFiles.map(\.kindLabel), ["正式 SQL / Formal", "回滚 SQL / Rollback"])
        XCTAssertEqual(workspace.sqlFiles.first?.fileName, "pay_log.sql")
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

    private func workspaceForWorkflowSummary(
        stage: String,
        id: String? = nil,
        name: String = "Workflow Summary",
        folder: String? = nil,
        path: String? = nil,
        healthChecks: [WorkspaceHealthCheck] = [],
        risks: [RiskAlert] = [],
        sqlFiles: [WorkspaceSqlFile] = []
    ) -> WorkspaceSummary {
        let workspaceID = id ?? "workflow-summary-\(stage)"
        let workspaceFolder = folder ?? workspaceID
        let workspacePath = path ?? "~/ks_project/workspaces/\(workspaceFolder)"

        return WorkspaceSummary(
            id: workspaceID,
            name: name,
            folder: workspaceFolder,
            path: workspacePath,
            branch: "feature/workflow-summary",
            state: .developing,
            riskLevel: risks.isEmpty ? .low : .medium,
            aiState: "Ready",
            worktreeState: "Ready",
            documentLinks: ["delivery": "\(workspacePath)/交付记录.md"],
            sqlFiles: sqlFiles,
            services: [
                ServiceStatus(name: "order", branch: "feature/workflow-summary", worktree: "ready", gitSummary: "clean", worktreeExists: true, sourceExists: true)
            ],
            activities: [],
            risks: risks,
            healthChecks: healthChecks,
            sessionActions: [],
            lifecycle: WorkspaceLifecycle(
                stage: stage,
                label: "Workflow",
                detail: "Workflow test fixture",
                progress: 80,
                nextAction: "Continue",
                documentKey: "delivery"
            ),
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
}
