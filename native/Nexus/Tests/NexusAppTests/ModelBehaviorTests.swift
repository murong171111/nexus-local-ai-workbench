import XCTest
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
    }
}
