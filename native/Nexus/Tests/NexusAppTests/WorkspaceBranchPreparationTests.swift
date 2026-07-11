import Foundation
import XCTest
@testable import NexusApp
import NexusBridge

final class WorkspaceBranchPreparationTests: XCTestCase {
    func testMissingTargetBranchRoutesToConfirmedBranchAndWorktreeCreation() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let dashboard = try NativeWorkspaceScanner.scan(
            workspacesRoot: fixture.workspacesRoot.path,
            sourceReposRoot: fixture.sourceReposRoot.path,
            docsRoot: fixture.root.appendingPathComponent("docs").path
        )
        let workspace = WorkspaceSummary(snapshot: try XCTUnwrap(dashboard.workspaces.first))
        let serviceBranch = ServiceBranchEvidence.resolve(workspace: workspace)
        let worktree = WorktreeSetupEvidence.resolve(workspace: workspace)

        XCTAssertEqual(serviceBranch.status, .ready)
        XCTAssertEqual(worktree.primaryActionLabel, "创建分支与 Worktree")
        XCTAssertEqual(worktree.primaryAction, .worktree)
        XCTAssertTrue(worktree.mutationPolicy.canRequestConfirmation)
    }

    func testSetupCreatesMissingTargetBranchAndWorktreeFromDefaultBranch() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let request = SetupWorktreesRequest(
            workspacePath: fixture.workspace.path,
            sourceReposRoot: fixture.sourceReposRoot.path,
            services: ["order"],
            targetBranch: "feature/created-by-nexus",
            confirmed: true
        )
        let plan = try NativeWorktreeSetupStore.makePlan(request: request)
        let response = try NativeWorktreeSetupStore.setup(plan: plan, confirmed: true)

        XCTAssertEqual(response.created.map(\.service), ["order"])
        XCTAssertTrue(response.failed.isEmpty)
        XCTAssertNotNil(try gitRevision("feature/created-by-nexus", in: fixture.source))
        XCTAssertEqual(
            try gitRevision("HEAD", in: fixture.workspace.appendingPathComponent("repos/order")),
            try gitRevision("main", in: fixture.source)
        )
    }

    @MainActor
    func testNewWorkspaceOffersBranchAndWorktreeSetupWhenScopeIsReady() throws {
        let fixture = try makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }

        let dashboard = try NativeWorkspaceScanner.scan(
            workspacesRoot: fixture.workspacesRoot.path,
            sourceReposRoot: fixture.sourceReposRoot.path,
            docsRoot: fixture.root.appendingPathComponent("docs").path
        )
        let workspace = WorkspaceSummary(snapshot: try XCTUnwrap(dashboard.workspaces.first))

        XCTAssertTrue(AppState.shouldPresentWorktreeSetupAfterCreation(for: workspace))
    }

    private func makeFixture() throws -> (
        root: URL,
        workspacesRoot: URL,
        sourceReposRoot: URL,
        workspace: URL,
        source: URL
    ) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-branch-preparation-\(UUID().uuidString)")
        let workspacesRoot = root.appendingPathComponent("workspaces")
        let sourceReposRoot = root.appendingPathComponent("source-repos")
        let workspace = workspacesRoot.appendingPathComponent("2026-07-12-demo")
        let source = sourceReposRoot.appendingPathComponent("order")
        let remote = root.appendingPathComponent("remote-order.git")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sourceReposRoot, withIntermediateDirectories: true)
        try runGit(["init", "--bare", "-b", "main", remote.path], in: root)
        try runGit(["clone", remote.path, source.path], in: root)
        try runGit(["config", "user.email", "nexus@example.com"], in: source)
        try runGit(["config", "user.name", "Nexus Test"], in: source)
        try "demo\n".write(to: source.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "README.md"], in: source)
        try runGit(["commit", "-m", "init"], in: source)
        try runGit(["push", "-u", "origin", "main"], in: source)

        try """
        # Demo

        <!-- template-version: 2 -->

        - 需求名称: Demo
        - 当前状态: analyzing
        - 目标分支: feature/created-by-nexus
        - 源仓库集合: \(sourceReposRoot.path)
        """.write(to: workspace.appendingPathComponent("workspace.md"), atomically: true, encoding: .utf8)
        try """
        # Services

        ## 已确认相关

        | 服务 | 源仓库 | 说明 |
        | --- | --- | --- |
        | order | `\(source.path)` | test |
        """.write(to: workspace.appendingPathComponent("services.md"), atomically: true, encoding: .utf8)
        try """
        # Branches

        - 目标分支: feature/created-by-nexus

        | 服务 | 源仓库 | 目标分支 | Worktree |
        | --- | --- | --- | --- |
        | order | `\(source.path)` | feature/created-by-nexus | 待创建 |
        """.write(to: workspace.appendingPathComponent("branches.md"), atomically: true, encoding: .utf8)

        return (root, workspacesRoot, sourceReposRoot, workspace, source)
    }

    private func runGit(_ arguments: [String], in directory: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        let stderr = Pipe()
        process.standardError = stderr
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let detail = String(data: stderr.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw NSError(domain: "WorkspaceBranchPreparationTests", code: Int(process.terminationStatus), userInfo: [NSLocalizedDescriptionKey: detail])
        }
    }

    private func gitRevision(_ reference: String, in directory: URL) throws -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["rev-parse", "--verify", "\(reference)^{commit}"]
        process.currentDirectoryURL = directory
        let stdout = Pipe()
        process.standardOutput = stdout
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        return String(data: stdout.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
