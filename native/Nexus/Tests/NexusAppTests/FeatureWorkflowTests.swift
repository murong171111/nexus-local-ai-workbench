import XCTest
@testable import NexusApp
import NexusBridge

final class FeatureWorkflowTests: XCTestCase {
    func testDemandInputDraftRoundTripsWithoutCreatingLegacyTemplates() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = DemandInputDraft(
            requirement: "应用内描述需求并交给 Codex 梳理。",
            links: ["https://example.com/spec"],
            attachments: []
        )

        let response = try NativeDemandInputStore.save(
            draft: draft,
            workspacePath: root.path,
            expectedRevision: .missing
        )

        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: root.path).draft, draft)
        XCTAssertTrue(response.path.hasSuffix("/需求/intake-draft.md"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("需求/questions.md").path))
    }

    func testDemandInputSaveRejectsStaleDraftRevision() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = DemandInputDraft(requirement: "first", links: [], attachments: [])
        let response = try NativeDemandInputStore.save(
            draft: initial,
            workspacePath: root.path,
            expectedRevision: .missing
        )

        try "external change".write(
            to: URL(fileURLWithPath: response.path),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "second", links: [], attachments: []),
                workspacePath: root.path,
                expectedRevision: response.revision
            )
        )
    }

    func testDemandInputDraftRoundTripsRequirementContainingH2Sections() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = DemandInputDraft(
            requirement: """
            保存订单快照。

            ## 验收标准

            - 可以查询历史快照。

            ## 风险

            - 不回填历史数据。
            """,
            links: ["https://example.com/spec"],
            attachments: ["需求/attachments/order-flow.png"]
        )

        _ = try NativeDemandInputStore.save(
            draft: draft,
            workspacePath: root.path,
            expectedRevision: .missing
        )

        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: root.path).draft, draft)
    }

    func testDemandInputLoadRejectsSymlinkedDemandDirectory() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let externalDemand = root.appendingPathComponent("external-demand")
        try FileManager.default.createDirectory(at: externalDemand, withIntermediateDirectories: true)
        try "# Demand Intake Draft\n".write(
            to: externalDemand.appendingPathComponent("intake-draft.md"),
            atomically: true,
            encoding: .utf8
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("需求"),
            withDestinationURL: externalDemand
        )

        XCTAssertThrowsError(try NativeDemandInputStore.load(workspacePath: root.path))
    }

    func testDemandInputSaveRejectsRevisionChangedBeforeFinalReplacement() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = try NativeDemandInputStore.save(
            draft: DemandInputDraft(requirement: "initial", links: [], attachments: []),
            workspacePath: root.path,
            expectedRevision: .missing
        )
        let draftURL = URL(fileURLWithPath: initial.path)

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "Nexus write", links: [], attachments: []),
                workspacePath: root.path,
                expectedRevision: initial.revision,
                beforeFinalRevisionCheck: {
                    try "external write".write(to: draftURL, atomically: true, encoding: .utf8)
                }
            )
        )
        XCTAssertEqual(try String(contentsOf: draftURL, encoding: .utf8), "external write")
    }

    func testDemandAttachmentPlanRejectsDestinationCreatedAfterConfirmation() throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try NativeDemandInputStore.makeAttachmentPlan(
            workspacePath: fixture.workspace.path,
            sourceURLs: [fixture.source]
        )
        try "external".write(to: plan.items[0].destinationURL, atomically: true, encoding: .utf8)

        let response = try NativeDemandInputStore.copyAttachments(plan: plan, confirmed: true)

        XCTAssertTrue(response.copiedPaths.isEmpty)
        XCTAssertEqual(response.errors.map(\.sourcePath), [fixture.source.path])
    }

    func testDemandAttachmentCopyReturnsCopiedPathsWhenAnotherItemFails() throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let second = fixture.root.appendingPathComponent("second.png")
        try Data("second".utf8).write(to: second)
        let plan = try NativeDemandInputStore.makeAttachmentPlan(
            workspacePath: fixture.workspace.path,
            sourceURLs: [fixture.source, second]
        )
        try "external".write(to: plan.items[1].destinationURL, atomically: true, encoding: .utf8)

        let response = try NativeDemandInputStore.copyAttachments(plan: plan, confirmed: true)

        XCTAssertEqual(response.copiedPaths, [plan.items[0].destinationURL.path])
        XCTAssertEqual(response.errors.map(\.sourcePath), [second.path])
        XCTAssertEqual(try Data(contentsOf: plan.items[0].destinationURL), Data("prototype".utf8))
    }

    func testDemandAttachmentCopyWritesVerifiedDataInsteadOfRereadingSourcePath() throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try NativeDemandInputStore.makeAttachmentPlan(
            workspacePath: fixture.workspace.path,
            sourceURLs: [fixture.source]
        )

        let response = try NativeDemandInputStore.copyAttachments(
            plan: plan,
            confirmed: true,
            beforeDestinationWrite: { _ in
                try Data("changed".utf8).write(to: fixture.source)
            }
        )

        XCTAssertEqual(response.copiedPaths, [plan.items[0].destinationURL.path])
        XCTAssertTrue(response.errors.isEmpty)
        XCTAssertEqual(try Data(contentsOf: plan.items[0].destinationURL), Data("prototype".utf8))
    }

    func testDemandAttachmentCopyRejectsForgedPlanBeforeCreatingDemandDirectories() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.png")
        try Data("source".utf8).write(to: source)
        let forged = DemandAttachmentPlan(
            workspacePath: root.path,
            expectedDraftRevision: .missing,
            items: [
                DemandAttachmentPlanItem(
                    sourceURL: source,
                    destinationURL: root.appendingPathComponent("outside.png"),
                    expectedSizeBytes: 6,
                    expectedSHA256: String(repeating: "0", count: 64)
                )
            ]
        )

        XCTAssertThrowsError(try NativeDemandInputStore.copyAttachments(plan: forged, confirmed: true))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("需求").path))
    }

    @MainActor
    func testFeatureIntakePromptUsesSavedDemandAndStrictDraftContract() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try "# Changes\n\n## 2026-07-11\n\n- F-001: saved material.\n".write(
            to: root.appendingPathComponent("changes.md"),
            atomically: true,
            encoding: .utf8
        )
        let workspace = demandInputWorkspace(path: root.path)
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let appState = AppState(
            workspaces: [workspace],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: root.deletingLastPathComponent().path,
            sourceReposRoot: root.path,
            docsRoot: root.path,
            defaults: defaults
        )

        _ = await appState.saveDemandInputDraft(
            DemandInputDraft(
                requirement: "为订单保存增加快照。",
                links: ["https://example.com/prototype"],
                attachments: ["需求/attachments/order-flow.png"]
            ),
            in: workspace
        )

        let prompt = appState.featureIntakePrompt(for: workspace)

        XCTAssertTrue(prompt.contains(root.path))
        XCTAssertTrue(prompt.contains("为订单保存增加快照。"))
        XCTAssertTrue(prompt.contains("需求/attachments/order-flow.png"))
        XCTAssertTrue(prompt.contains("order-service"))
        XCTAssertTrue(prompt.contains("feature/order-snapshot"))
        XCTAssertTrue(prompt.contains("changes.md"))
        XCTAssertTrue(prompt.contains("Write a proposal to \(root.path)/FEATURES.draft.md."))
        XCTAssertTrue(prompt.contains("Do not modify FEATURES.md."))
        XCTAssertTrue(prompt.contains("DRAFT-001, DRAFT-002"))
    }

    @MainActor
    func testAppStateDemandSaveFailurePreservesEditedDraftAndReportsResult() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let appState = AppState(
            workspaces: [workspace],
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: root.deletingLastPathComponent().path,
            sourceReposRoot: root.path,
            docsRoot: root.path,
            defaults: defaults
        )
        let original = DemandInputDraft(requirement: "original", links: [], attachments: [])
        let initialResult = await appState.saveDemandInputDraft(original, in: workspace)
        XCTAssertTrue(initialResult.succeeded)
        let snapshot = try XCTUnwrap(appState.demandInputSnapshot(for: workspace))
        try "external".write(to: URL(fileURLWithPath: snapshot.path), atomically: true, encoding: .utf8)
        let edited = DemandInputDraft(requirement: "edited", links: [], attachments: [])

        let result = await appState.saveDemandInputDraft(edited, in: workspace)

        XCTAssertFalse(result.succeeded)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft, edited)
        XCTAssertEqual(appState.lastError, result.message)
    }

    func testConsoleRoutesDemandPrimaryActionToVisibleEditor() {
        XCTAssertEqual(
            WorkspaceConsoleTarget.resolve(action: .demandIntake),
            .demandInput
        )
    }

    func testConsoleLayoutKeepsOnePrimaryActionAndFilesCollapsed() {
        let summary = WorkspaceConsoleLayoutPolicy().auditSummary

        XCTAssertEqual(summary.stageGroups, [.created, .demandAndFeatures, .development, .delivery, .archive])
        XCTAssertEqual(summary.prominentPrimaryActionCount, 1)
        XCTAssertTrue(summary.filesAreCollapsed)
        XCTAssertTrue(summary.currentSignalsAreSecondary)
    }

    private func temporaryDemandWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-demand-input-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func demandAttachmentFixture() throws -> (root: URL, workspace: URL, source: URL) {
        let root = try temporaryDemandWorkspace()
        let workspace = root.appendingPathComponent("workspace")
        let source = root.appendingPathComponent("prototype.png")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: true)
        try Data("prototype".utf8).write(to: source)
        return (root, workspace, source)
    }

    private func demandInputWorkspace(path: String) -> WorkspaceSummary {
        WorkspaceSummary(
            id: "demand-input-workspace",
            name: "Demand Input",
            folder: "demand-input",
            path: path,
            branch: "feature/order-snapshot",
            state: .analyzing,
            riskLevel: .low,
            aiState: "Ready",
            worktreeState: "Ready",
            documentLinks: ["changes": "\(path)/changes.md"],
            services: [
                ServiceStatus(
                    name: "order-service",
                    branch: "feature/order-snapshot",
                    worktree: "ready",
                    gitSummary: "clean",
                    worktreeExists: true,
                    sourceExists: true
                )
            ],
            activities: [],
            risks: [],
            lifecycle: WorkspaceLifecycle(
                stage: "scoping",
                label: "Demand",
                detail: "Demand input fixture",
                progress: 20,
                nextAction: "Draft",
                documentKey: "changes"
            )
        )
    }
}
