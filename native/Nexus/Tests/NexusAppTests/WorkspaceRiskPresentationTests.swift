import XCTest
@testable import NexusApp
import NexusBridge

final class WorkspaceRiskPresentationTests: XCTestCase {
    func testWorkflowReadinessDoesNotRaiseRiskBadgeButRealBranchFailureDoes() {
        let readiness = WorkspaceSummary(snapshot: snapshot(risks: ["交付记录待补充"]))
        let branchFailure = WorkspaceSummary(snapshot: snapshot(risks: ["目标分支不可用: order(feature/test)"]))

        XCTAssertEqual(readiness.riskLevel, .low)
        XCTAssertEqual(readiness.risks.map(\.detail), ["交付记录待补充"])
        XCTAssertEqual(branchFailure.riskLevel, .medium)
    }

    private func snapshot(risks: [String]) -> WorkspaceSnapshot {
        WorkspaceSnapshot(
            name: "Risk presentation",
            folder: "2026-07-12-risk-presentation",
            path: "/tmp/workspaces/2026-07-12-risk-presentation",
            state: "analyzing",
            targetBranch: "feature/test",
            sourceRoot: "/tmp/source-repos",
            confirmedServices: ["order"],
            candidateServices: [],
            taskCounts: TaskCountsSnapshot(done: 0, doing: 0, todo: 0, blocked: 0),
            decisionCount: 0,
            gitRows: [],
            risks: risks,
            riskCount: risks.count,
            updated: "2026-07-12",
            links: [:],
            worktreeCommand: ""
        )
    }
}
