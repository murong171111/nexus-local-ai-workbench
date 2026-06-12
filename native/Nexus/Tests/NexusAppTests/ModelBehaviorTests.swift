import NexusBridge
import AppKit
import XCTest
@testable import NexusApp

final class ModelBehaviorTests: XCTestCase {
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
                    branch: "feature/service-branch",
                    worktree: "missing",
                    gitSummary: "source clean",
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
        XCTAssertEqual(worktree.status, .next)
        XCTAssertEqual(worktree.missingServices, ["order"])
        XCTAssertEqual(stage.id, .worktreeSetup)
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
        XCTAssertEqual(stage.id, .worktreeSetup)
        XCTAssertEqual(stage.primaryAction, .worktree)
    }

    func testWorktreeSetupEvidenceBlocksBranchMismatch() {
        let workspace = workspaceForWorkflowSummary(
            stage: "developing",
            id: "worktree-mismatch",
            branch: "feature/worktree",
            services: [
                ServiceStatus(
                    name: "order",
                    branch: "dev",
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

        XCTAssertEqual(worktree.status, .blocked)
        XCTAssertEqual(worktree.branchMismatchServices, ["order(dev)"])
        XCTAssertEqual(worktree.setupPlan.map(\.action), [.blocked])
        XCTAssertEqual(worktree.setupPlan.first?.currentBranch, "dev")
        XCTAssertEqual(stage.id, .worktreeSetup)
        XCTAssertEqual(stage.primaryAction, .document("branches"))
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
        XCTAssertNotEqual(stage.id, .worktreeSetup)
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
        XCTAssertEqual(stage.id, .development)
        XCTAssertEqual(stage.primaryAction, .task("first-high"))
        XCTAssertTrue(stage.reason.contains("Implement first high priority task"))
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
        XCTAssertEqual(delivery.blockerCount, 0)
        XCTAssertEqual(stage.id, .archived)
        XCTAssertEqual(stage.primaryAction, .lifecycle(.delivery))
        XCTAssertFalse(stage.nextStageAllowed)
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
        XCTAssertEqual(stage.id, .archived)
        XCTAssertEqual(stage.status, .ready)
        XCTAssertEqual(stage.primaryAction, .lifecycle(.archived))
        XCTAssertTrue(stage.nextStageAllowed)
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
        XCTAssertEqual(stage.id, .archived)
        XCTAssertEqual(stage.status, .archived)
        XCTAssertEqual(stage.primaryAction, .document("handoff"))
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

    @MainActor
    func testAutomationBranchHandoffPromptTargetsBranchMismatchWorkspace() {
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
                    id: "branch-alignment",
                    label: "分支一致",
                    detail: "不一致: order(chen/old-branch)",
                    status: "fail",
                    action: "branches"
                )
            ],
            risks: [
                RiskAlert(title: "分支不一致", detail: "order(chen/old-branch)")
            ]
        )
        let appState = appStateForAutomationTests(workspaces: [selectedCleanWorkspace, branchWorkspace])
        appState.selectedWorkspaceID = selectedCleanWorkspace.id

        let prompt = appState.automationSignalHandoffPrompt(for: branchSignal())

        XCTAssertTrue(prompt.contains("- 当前工作区: Branch Workspace"))
        XCTAssertTrue(prompt.contains("- 分支记录: /tmp/workspaces/2026-05-31-branch-workspace/branches.md"))
        XCTAssertTrue(prompt.contains("order(chen/old-branch)"))
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

        let copiedPrompt = NSPasteboard.general.string(forType: .string) ?? ""
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
            activities: [],
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
            title: "分支检查 / Branch check",
            detail: "1 workspaces have branch alignment issues.",
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
}
