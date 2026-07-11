import XCTest
@testable import NexusApp
import NexusBridge

final class FeatureWorkflowTests: XCTestCase {
    func testFeatureDocumentPreservesUnknownProseAndStableIDs() throws {
        let source = """
        # Features

        人工前言。

        ## F-001 Order snapshot

        - Status: in_progress
        - Verification: code
        - Auto complete: true
        - Source: z.png, a.png, z.png
        - Services: order-service
        - Tasks: T-004, T-003
        - Evidence: test_order_snapshot
        - Completed at:
        - Completed by:

        保留这段人工说明。

        ## F-002 Manual review

        - Status: todo
        - Verification: manual
        - Auto complete: false

        人工验收。
        """

        let document = try NativeFeatureStore.parse(source)

        XCTAssertEqual(document.features.map(\.id), ["F-001", "F-002"])
        XCTAssertEqual(document.features[0].verification, .code)
        let rendered = NativeFeatureStore.render(document)
        XCTAssertTrue(rendered.contains("人工前言。"))
        XCTAssertTrue(rendered.contains("保留这段人工说明。"))
        XCTAssertTrue(rendered.contains("- Source: a.png, z.png"))
        XCTAssertTrue(rendered.contains("- Tasks: T-003, T-004"))
    }

    func testFeatureDocumentRejectsInvalidConfirmedFacts() throws {
        let invalidDocuments = [
            "## F-01 Too short\n- Status: todo\n- Verification: code\n- Auto complete: true\n",
            "## F-001\n- Status: todo\n- Verification: code\n- Auto complete: true\n",
            "## F-001 Missing status\n- Verification: code\n- Auto complete: true\n",
            "## F-001 Bad status\n- Status: unknown\n- Verification: code\n- Auto complete: true\n",
            "## F-001 Duplicate\n- Status: todo\n- Status: done\n- Verification: code\n- Auto complete: true\n",
            "## F-001 First\n- Status: todo\n- Verification: code\n- Auto complete: true\n\n## F-001 Second\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        ]

        for source in invalidDocuments {
            XCTAssertThrowsError(try NativeFeatureStore.parse(source), source)
        }
    }

    func testFeatureWriteRejectsInvalidReplacementBeforePublish() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let original = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        try original.write(to: featuresURL, atomically: true, encoding: .utf8)
        let expected = try XCTUnwrap(
            NativeFeatureStore.load(workspacePath: root.path).document.features.first
        )
        var replacement = expected
        replacement.title = ""
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .update(expected: expected, replacement: replacement)
        )

        XCTAssertThrowsError(try NativeFeatureStore.write(plan: plan, confirmed: true))
        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), original)
    }

    func testFeatureWriteRejectsExternalChangeAfterConfirmation() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let original = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        try original.write(to: featuresURL, atomically: true, encoding: .utf8)
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .setStatus(id: "F-001", status: .done, completionNote: "manual")
        )
        let external = original + "\nexternal edit\n"
        try external.write(to: featuresURL, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try NativeFeatureStore.write(plan: plan, confirmed: true))
        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), external)
    }

    func testFeatureLoadRejectsUnsafeOrInvalidFeatureFiles() throws {
        for kind in 0..<3 {
            let root = try temporaryDemandWorkspace()
            defer { try? FileManager.default.removeItem(at: root) }
            let featuresURL = root.appendingPathComponent("FEATURES.md")
            switch kind {
            case 0:
                let external = root.appendingPathComponent("external.md")
                try "outside".write(to: external, atomically: true, encoding: .utf8)
                try FileManager.default.createSymbolicLink(at: featuresURL, withDestinationURL: external)
            case 1:
                try FileManager.default.createDirectory(at: featuresURL, withIntermediateDirectories: false)
            default:
                try Data([0xFF, 0xFE]).write(to: featuresURL)
            }
            XCTAssertThrowsError(try NativeFeatureStore.load(workspacePath: root.path))
        }
    }

    func testFeatureWriteReturnsAuditErrorAfterSuccessfulPrimaryWrite() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        try "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n".write(
            to: featuresURL,
            atomically: true,
            encoding: .utf8
        )
        let auditRoot = root.appendingPathComponent("audit-file")
        try Data().write(to: auditRoot)
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .setStatus(id: "F-001", status: .done, completionNote: "manual")
        )

        let response = try NativeFeatureStore.write(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot.path
        )

        XCTAssertEqual(response.document.features.first?.status, .done)
        XCTAssertNotNil(response.auditError)
        XCTAssertEqual(try NativeFeatureStore.load(workspacePath: root.path).document.features.first?.status, .done)
    }

    func testFeatureWriteAppliesExactlyOneConfirmedMutation() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        try "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n".write(
            to: featuresURL,
            atomically: true,
            encoding: .utf8
        )
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .setStatus(id: "F-001", status: .done, completionNote: "manual")
        )

        XCTAssertThrowsError(try NativeFeatureStore.write(plan: plan, confirmed: false))
        let response = try NativeFeatureStore.write(plan: plan, confirmed: true)
        let document = try NativeFeatureStore.load(workspacePath: root.path).document
        XCTAssertEqual(document.features.count, 1)
        XCTAssertEqual(document.features[0].status, .done)
        XCTAssertEqual(document.features[0].completionNote, "manual")
        XCTAssertNil(response.auditError)
    }

    func testFeatureTaskAttributionRequiresOneValidDetailMarker() {
        let content = """
        | 任务 | 状态 | 详情 |
        | --- | --- | --- |
        | linked | 待办 | feature=F-001 |
        | multiple | 待办 | feature=F-001 feature=F-002 |
        | malformed | 待办 | feature=F-01 |
        | title F-003 | 待办 | no marker |
        """

        let rows = NativeWorkspaceTaskParser.rows(from: content, folder: "demo")

        XCTAssertEqual(rows.map(\.featureID), ["F-001", nil, nil, nil])
        XCTAssertNil(rows[0].featureWarning)
        XCTAssertNotNil(rows[1].featureWarning)
        XCTAssertNotNil(rows[2].featureWarning)
        XCTAssertNil(rows[3].featureWarning)
    }

    @MainActor
    func testFeatureAppStateRequiresConfirmationBeforeWriteAndRefreshesAfterConfirm() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let original = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        try original.write(to: featuresURL, atomically: true, encoding: .utf8)
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)

        appState.requestFeatureWrite(
            .setStatus(id: "F-001", status: .done, completionNote: "manual"),
            in: workspace
        )
        for _ in 0..<100 where appState.pendingFeatureWrite == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(appState.pendingFeatureWrite)
        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), original)

        await appState.confirmPendingFeatureWrite(confirmed: false)
        XCTAssertNil(appState.pendingFeatureWrite)
        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), original)

        appState.requestFeatureWrite(
            .setStatus(id: "F-001", status: .done, completionNote: "manual"),
            in: workspace
        )
        for _ in 0..<100 where appState.pendingFeatureWrite == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        await appState.confirmPendingFeatureWrite(confirmed: true)

        XCTAssertEqual(appState.featuresByWorkspace[workspace.id]?.features.first?.status, .done)
        XCTAssertNil(appState.pendingFeatureWrite)
    }

    @MainActor
    func testFeatureWorkspaceAutosavePolicySuppressesOnlyProgrammaticChangeAndCapturesWorkspaceDraft() async throws {
        let policy = FeatureWorkspaceAutosavePolicy(delayNanoseconds: 20_000_000)
        let loaded = DemandInputDraft(requirement: "loaded", links: [], attachments: [])
        var saves: [(String, DemandInputDraft)] = []

        policy.prepareProgrammaticUpdate(loaded)
        policy.draftChanged(loaded, workspaceID: "workspace-a") { workspaceID, draft in
            saves.append((workspaceID, draft))
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertTrue(saves.isEmpty)

        let edited = DemandInputDraft(requirement: "edited", links: [], attachments: [])
        policy.draftChanged(edited, workspaceID: "workspace-a") { workspaceID, draft in
            saves.append((workspaceID, draft))
        }
        policy.cancel()
        policy.draftChanged(
            DemandInputDraft(requirement: "workspace b", links: [], attachments: []),
            workspaceID: "workspace-b"
        ) { workspaceID, draft in
            saves.append((workspaceID, draft))
        }
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(saves.map(\.0), ["workspace-b"])
        XCTAssertEqual(saves.map(\.1.requirement), ["workspace b"])

        policy.prepareProgrammaticUpdate(loaded)
        let realEditWithoutProgrammaticOnChange = DemandInputDraft(
            requirement: "real edit after equal assignment",
            links: [],
            attachments: []
        )
        policy.draftChanged(realEditWithoutProgrammaticOnChange, workspaceID: "workspace-b") { workspaceID, draft in
            saves.append((workspaceID, draft))
        }
        try await Task.sleep(nanoseconds: 40_000_000)
        XCTAssertEqual(saves.last?.1, realEditWithoutProgrammaticOnChange)
    }

    func testFeatureWorkspaceAutosaveContinuesWhileAttachmentOperationIsActive() {
        XCTAssertTrue(
            FeatureWorkspaceDraftPolicy.shouldScheduleAutosave(
                isLoading: false,
                isAttaching: true
            )
        )
        XCTAssertFalse(
            FeatureWorkspaceDraftPolicy.shouldScheduleAutosave(
                isLoading: true,
                isAttaching: false
            )
        )
    }

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

    func testDemandInputRequirementRoundTripsEveryCharacterWithMarkersAndMarkdown() throws {
        let requirements = [
            "",
            "\n",
            "\n\nleading\ntrailing\n\n",
            "## Links\n\n- not metadata\n\n## Attachments\n\n- `not-metadata`",
            "before\n<!-- nexus:demand-requirement:end -->\n\n## Links\n\n- fake\n\n## Attachments\n\n- `fake`\nafter\n<!-- nexus:demand-requirement:start -->"
        ]

        for requirement in requirements {
            let root = try temporaryDemandWorkspace()
            defer { try? FileManager.default.removeItem(at: root) }
            let draft = DemandInputDraft(
                requirement: requirement,
                links: ["https://example.com/spec"],
                attachments: ["需求/attachments/prototype.png"]
            )

            _ = try NativeDemandInputStore.save(
                draft: draft,
                workspacePath: root.path,
                expectedRevision: .missing
            )

            let saved = try String(
                contentsOf: root.appendingPathComponent("需求/intake-draft.md"),
                encoding: .utf8
            )
            XCTAssertTrue(saved.contains("<!-- nexus:demand-requirement:start -->"))
            XCTAssertTrue(saved.contains("<!-- nexus:demand-requirement:end -->"))
            XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: root.path).draft, draft)
        }
    }

    func testDemandInputLoadKeepsLegacyUnmarkedTailCompatibility() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let demandURL = root.appendingPathComponent("需求")
        try FileManager.default.createDirectory(at: demandURL, withIntermediateDirectories: true)
        try """
        # Demand Intake Draft

        ## Requirement

        legacy requirement

        ## Links

        - https://example.com/legacy

        ## Attachments

        - `需求/attachments/legacy.txt`

        """.write(
            to: demandURL.appendingPathComponent("intake-draft.md"),
            atomically: true,
            encoding: .utf8
        )

        XCTAssertEqual(
            try NativeDemandInputStore.load(workspacePath: root.path).draft,
            DemandInputDraft(
                requirement: "legacy requirement",
                links: ["https://example.com/legacy"],
                attachments: ["需求/attachments/legacy.txt"]
            )
        )
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

    func testDemandIORejectsDemandDirectoryReplacedWithSymlinkBeforeOpen() throws {
        let root = try temporaryDemandWorkspace()
        let external = try temporaryDemandWorkspace()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: external)
        }
        let initial = try NativeDemandInputStore.save(
            draft: DemandInputDraft(requirement: "inside", links: [], attachments: []),
            workspacePath: root.path,
            expectedRevision: .missing
        )
        let externalDraft = external.appendingPathComponent("intake-draft.md")
        try "outside".write(to: externalDraft, atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(
            at: external.appendingPathComponent("attachments"),
            withIntermediateDirectories: true
        )
        let externalAttachment = external.appendingPathComponent("attachments/prototype.png")
        try Data("outside attachment".utf8).write(to: externalAttachment)
        let source = root.appendingPathComponent("prototype.png")
        try Data("inside attachment".utf8).write(to: source)
        let attachmentPlan = try NativeDemandInputStore.makeAttachmentPlan(
            workspacePath: root.path,
            sourceURLs: [source]
        )

        func replaceDemandDirectory() throws {
            let demand = root.appendingPathComponent("需求")
            try FileManager.default.moveItem(at: demand, to: root.appendingPathComponent("original-demand"))
            try FileManager.default.createSymbolicLink(at: demand, withDestinationURL: external)
        }

        XCTAssertThrowsError(
            try NativeDemandInputStore.load(
                workspacePath: root.path,
                beforeDemandDirectoryOpen: replaceDemandDirectory
            )
        )

        XCTAssertEqual(try String(contentsOf: externalDraft, encoding: .utf8), "outside")
        XCTAssertEqual(try Data(contentsOf: externalAttachment), Data("outside attachment".utf8))
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: external.path)), ["attachments", "intake-draft.md"])
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: external.appendingPathComponent("attachments").path)), ["prototype.png"])
        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "must not escape", links: [], attachments: []),
                workspacePath: root.path,
                expectedRevision: initial.revision
            )
        )
        XCTAssertThrowsError(try NativeDemandInputStore.copyAttachments(plan: attachmentPlan, confirmed: true))
        XCTAssertEqual(try String(contentsOf: externalDraft, encoding: .utf8), "outside")
        XCTAssertEqual(try Data(contentsOf: externalAttachment), Data("outside attachment".utf8))
    }

    func testDemandAttachmentPlanAndCopyRejectLeafSymlinkSources() throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let external = fixture.root.appendingPathComponent("external.png")
        try Data("external".utf8).write(to: external)

        XCTAssertThrowsError(
            try NativeDemandInputStore.makeAttachmentPlan(
                workspacePath: fixture.workspace.path,
                sourceURLs: [fixture.source],
                beforeSourceRead: {
                    try FileManager.default.removeItem(at: fixture.source)
                    try FileManager.default.createSymbolicLink(at: fixture.source, withDestinationURL: external)
                }
            )
        )

        try FileManager.default.removeItem(at: fixture.source)
        try Data("prototype".utf8).write(to: fixture.source)
        let plan = try NativeDemandInputStore.makeAttachmentPlan(
            workspacePath: fixture.workspace.path,
            sourceURLs: [fixture.source]
        )

        let response = try NativeDemandInputStore.copyAttachments(
            plan: plan,
            confirmed: true,
            beforeSourceRead: { _ in
                try FileManager.default.removeItem(at: fixture.source)
                try FileManager.default.createSymbolicLink(at: fixture.source, withDestinationURL: external)
            }
        )

        XCTAssertTrue(response.copiedPaths.isEmpty)
        XCTAssertEqual(response.errors.map(\.sourcePath), [fixture.source.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.items[0].destinationURL.path))
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

    func testDemandInputSaveRollsBackWhenExistingDraftChangesInPlaceAfterFinalCheck() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = try NativeDemandInputStore.save(
            draft: DemandInputDraft(requirement: "initial", links: [], attachments: []),
            workspacePath: root.path,
            expectedRevision: .missing
        )
        let draftURL = URL(fileURLWithPath: initial.path)
        let inode = try inodeNumber(at: draftURL)

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "Nexus write", links: [], attachments: []),
                workspacePath: root.path,
                expectedRevision: initial.revision,
                beforeDraftPublish: {
                    try Data("external same-inode update".utf8).write(to: draftURL, options: [])
                    XCTAssertEqual(try self.inodeNumber(at: draftURL), inode)
                }
            )
        )

        XCTAssertEqual(try inodeNumber(at: draftURL), inode)
        XCTAssertEqual(try Data(contentsOf: draftURL), Data("external same-inode update".utf8))
    }

    func testDemandInputTempCreationFailurePreservesRegularFileReplacingTemporaryName() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let demandURL = root.appendingPathComponent("需求")
        var replacementURL: URL?

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "not published", links: [], attachments: []),
                workspacePath: root.path,
                expectedRevision: .missing,
                afterTempOpen: { temporaryName in
                    let temporaryURL = demandURL.appendingPathComponent(temporaryName)
                    try FileManager.default.removeItem(at: temporaryURL)
                    try "external replacement".write(to: temporaryURL, atomically: false, encoding: .utf8)
                    replacementURL = temporaryURL
                }
            )
        )

        let replacement = try XCTUnwrap(replacementURL)
        XCTAssertEqual(try String(contentsOf: replacement, encoding: .utf8), "external replacement")
        XCTAssertFalse(FileManager.default.fileExists(atPath: demandURL.appendingPathComponent("intake-draft.md").path))
    }

    func testDemandInputTempWriteFailurePreservesSameInodeContentWithoutExpectedFingerprint() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let demandURL = root.appendingPathComponent("需求")
        var temporaryURL: URL?
        var temporaryInode: UInt64?

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "not published", links: [], attachments: []),
                workspacePath: root.path,
                expectedRevision: .missing,
                afterTempOpen: { temporaryName in
                    let url = demandURL.appendingPathComponent(temporaryName)
                    temporaryURL = url
                    temporaryInode = try self.inodeNumber(at: url)
                    try Data(repeating: 0x78, count: 16_384).write(to: url, options: [])
                    XCTAssertEqual(try self.inodeNumber(at: url), temporaryInode)
                }
            )
        )

        let preserved = try XCTUnwrap(temporaryURL)
        XCTAssertEqual(try inodeNumber(at: preserved), temporaryInode)
        XCTAssertEqual(try Data(contentsOf: preserved).count, 16_384)
        XCTAssertFalse(FileManager.default.fileExists(atPath: demandURL.appendingPathComponent("intake-draft.md").path))
    }

    func testDemandInputSaveRejectsReplacedTemporaryNameAndPreservesExistingDraft() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let initialDraft = DemandInputDraft(requirement: "original", links: [], attachments: [])
        let initial = try NativeDemandInputStore.save(
            draft: initialDraft,
            workspacePath: root.path,
            expectedRevision: .missing
        )
        let demandURL = root.appendingPathComponent("需求")
        let external = root.appendingPathComponent("external.md")
        try "external target".write(to: external, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "replacement", links: [], attachments: []),
                workspacePath: root.path,
                expectedRevision: initial.revision,
                beforeFinalRevisionCheck: {
                    let temporary = try XCTUnwrap(
                        FileManager.default.contentsOfDirectory(atPath: demandURL.path)
                            .first(where: { $0.hasPrefix(".intake-draft.md.") && $0.hasSuffix(".tmp") })
                    )
                    let temporaryURL = demandURL.appendingPathComponent(temporary)
                    try FileManager.default.removeItem(at: temporaryURL)
                    try FileManager.default.createSymbolicLink(at: temporaryURL, withDestinationURL: external)
                }
            )
        )

        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: root.path).draft, initialDraft)
        XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), "external target")
    }

    func testDemandInputExistingDraftRollsBackWhenPostPublishVerificationIsInterrupted() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = DemandInputDraft(requirement: "original", links: [], attachments: [])
        let initial = try NativeDemandInputStore.save(
            draft: original,
            workspacePath: root.path,
            expectedRevision: .missing
        )

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "replacement", links: [], attachments: []),
                workspacePath: root.path,
                expectedRevision: initial.revision,
                afterPublishBeforeVerify: {
                    throw PublishFailure.injected
                }
            )
        )

        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: root.path).draft, original)
    }

    func testDemandInputFirstSaveRejectsReplacedTemporaryNameAndCanRetry() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let demandURL = root.appendingPathComponent("需求")
        let draftURL = demandURL.appendingPathComponent("intake-draft.md")
        let external = root.appendingPathComponent("external.md")
        try "external target".write(to: external, atomically: true, encoding: .utf8)
        let draft = DemandInputDraft(requirement: "first", links: [], attachments: [])

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: draft,
                workspacePath: root.path,
                expectedRevision: .missing,
                beforeFinalRevisionCheck: {
                    let temporary = try XCTUnwrap(
                        FileManager.default.contentsOfDirectory(atPath: demandURL.path)
                            .first(where: { $0.hasPrefix(".intake-draft.md.") && $0.hasSuffix(".tmp") })
                    )
                    let temporaryURL = demandURL.appendingPathComponent(temporary)
                    try FileManager.default.removeItem(at: temporaryURL)
                    try FileManager.default.createSymbolicLink(at: temporaryURL, withDestinationURL: external)
                }
            )
        )

        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: draftURL.path), external.path)
        XCTAssertEqual(try String(contentsOf: external, encoding: .utf8), "external target")
        try FileManager.default.removeItem(at: draftURL)
        for name in try FileManager.default.contentsOfDirectory(atPath: demandURL.path)
            where name.hasPrefix(".intake-draft.md.") && name.hasSuffix(".tmp") {
            try FileManager.default.removeItem(at: demandURL.appendingPathComponent(name))
        }
        _ = try NativeDemandInputStore.save(
            draft: draft,
            workspacePath: root.path,
            expectedRevision: .missing
        )
        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: root.path).draft, draft)
    }

    func testDemandInputFirstSavePreservesRegularFileReplacingPublishedName() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let draftURL = root.appendingPathComponent("需求/intake-draft.md")
        let draft = DemandInputDraft(requirement: "Nexus staged", links: [], attachments: [])

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: draft,
                workspacePath: root.path,
                expectedRevision: .missing,
                afterPublishBeforeVerify: {
                    try FileManager.default.removeItem(at: draftURL)
                    try "external replacement".write(to: draftURL, atomically: false, encoding: .utf8)
                }
            )
        )

        XCTAssertEqual(try String(contentsOf: draftURL, encoding: .utf8), "external replacement")
        XCTAssertNotEqual(try NativeDemandInputStore.load(workspacePath: root.path).draft, draft)
    }

    func testDemandInputFirstSavePreservesPublishedDraftChangedInPlaceBeforeCleanup() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let draftURL = root.appendingPathComponent("需求/intake-draft.md")
        var publishedInode: UInt64?

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "Nexus staged", links: [], attachments: []),
                workspacePath: root.path,
                expectedRevision: .missing,
                afterPublishBeforeVerify: {
                    publishedInode = try self.inodeNumber(at: draftURL)
                    try Data("external same-inode draft".utf8).write(to: draftURL, options: [])
                    XCTAssertEqual(try self.inodeNumber(at: draftURL), publishedInode)
                }
            )
        )

        XCTAssertEqual(try inodeNumber(at: draftURL), publishedInode)
        XCTAssertEqual(try Data(contentsOf: draftURL), Data("external same-inode draft".utf8))
    }

    func testDemandInputFirstSavePreservesRegularFileReplacingTemporaryName() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let demandURL = root.appendingPathComponent("需求")

        XCTAssertThrowsError(
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "first", links: [], attachments: []),
                workspacePath: root.path,
                expectedRevision: .missing,
                beforeFinalRevisionCheck: {
                    let temporary = try XCTUnwrap(
                        FileManager.default.contentsOfDirectory(atPath: demandURL.path)
                            .first(where: { $0.hasPrefix(".intake-draft.md.") && $0.hasSuffix(".tmp") })
                    )
                    let temporaryURL = demandURL.appendingPathComponent(temporary)
                    try FileManager.default.removeItem(at: temporaryURL)
                    try "other regular file".write(to: temporaryURL, atomically: false, encoding: .utf8)
                }
            )
        )

        XCTAssertEqual(
            try String(contentsOf: demandURL.appendingPathComponent("intake-draft.md"), encoding: .utf8),
            "other regular file"
        )
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

    func testDemandAttachmentCopyCleansTemporaryFileWhenPublishFailsAndCanRetry() throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try NativeDemandInputStore.makeAttachmentPlan(
            workspacePath: fixture.workspace.path,
            sourceURLs: [fixture.source]
        )

        let failed = try NativeDemandInputStore.copyAttachments(
            plan: plan,
            confirmed: true,
            beforeAttachmentPublish: { _ in
                throw PublishFailure.injected
            }
        )

        XCTAssertTrue(failed.copiedPaths.isEmpty)
        XCTAssertEqual(failed.errors.map(\.sourcePath), [fixture.source.path])
        XCTAssertFalse(FileManager.default.fileExists(atPath: plan.items[0].destinationURL.path))
        XCTAssertEqual(
            try FileManager.default.contentsOfDirectory(atPath: plan.items[0].destinationURL.deletingLastPathComponent().path),
            []
        )

        let retried = try NativeDemandInputStore.copyAttachments(plan: plan, confirmed: true)

        XCTAssertEqual(retried.copiedPaths, [plan.items[0].destinationURL.path])
        XCTAssertTrue(retried.errors.isEmpty)
    }

    func testDemandAttachmentCopyRejectsReplacedTemporaryNameAndCanRetry() throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try NativeDemandInputStore.makeAttachmentPlan(
            workspacePath: fixture.workspace.path,
            sourceURLs: [fixture.source]
        )
        let attachmentsURL = plan.items[0].destinationURL.deletingLastPathComponent()
        let external = fixture.root.appendingPathComponent("external.png")
        try Data("external target".utf8).write(to: external)

        let failed = try NativeDemandInputStore.copyAttachments(
            plan: plan,
            confirmed: true,
            beforeAttachmentPublish: { _ in
                let temporary = try XCTUnwrap(
                    FileManager.default.contentsOfDirectory(atPath: attachmentsURL.path)
                        .first(where: { $0.hasPrefix(".attachment.") && $0.hasSuffix(".tmp") })
                )
                let temporaryURL = attachmentsURL.appendingPathComponent(temporary)
                try FileManager.default.removeItem(at: temporaryURL)
                try FileManager.default.createSymbolicLink(at: temporaryURL, withDestinationURL: external)
            }
        )

        XCTAssertTrue(failed.copiedPaths.isEmpty)
        XCTAssertEqual(failed.errors.map(\.sourcePath), [fixture.source.path])
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(atPath: plan.items[0].destinationURL.path),
            external.path
        )
        XCTAssertEqual(try Data(contentsOf: external), Data("external target".utf8))

        try FileManager.default.removeItem(at: plan.items[0].destinationURL)
        for name in try FileManager.default.contentsOfDirectory(atPath: attachmentsURL.path)
            where name.hasPrefix(".attachment.") && name.hasSuffix(".tmp") {
            try FileManager.default.removeItem(at: attachmentsURL.appendingPathComponent(name))
        }
        let retried = try NativeDemandInputStore.copyAttachments(plan: plan, confirmed: true)
        XCTAssertEqual(retried.copiedPaths, [plan.items[0].destinationURL.path])
        XCTAssertEqual(retried.copiedRelativePaths, ["需求/attachments/prototype.png"])
    }

    func testDemandAttachmentCopyPreservesSymlinkReplacingPublishedNameAndCanRetry() throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try NativeDemandInputStore.makeAttachmentPlan(
            workspacePath: fixture.workspace.path,
            sourceURLs: [fixture.source]
        )
        let destination = plan.items[0].destinationURL
        let external = fixture.root.appendingPathComponent("external.png")
        try Data("external target".utf8).write(to: external)

        let failed = try NativeDemandInputStore.copyAttachments(
            plan: plan,
            confirmed: true,
            afterPublishBeforeVerify: { _ in
                try FileManager.default.removeItem(at: destination)
                try FileManager.default.createSymbolicLink(at: destination, withDestinationURL: external)
            }
        )

        XCTAssertTrue(failed.copiedPaths.isEmpty)
        XCTAssertEqual(failed.errors.map(\.sourcePath), [fixture.source.path])
        XCTAssertEqual(try FileManager.default.destinationOfSymbolicLink(atPath: destination.path), external.path)
        XCTAssertEqual(try Data(contentsOf: external), Data("external target".utf8))

        try FileManager.default.removeItem(at: destination)
        let retried = try NativeDemandInputStore.copyAttachments(plan: plan, confirmed: true)
        XCTAssertEqual(retried.copiedRelativePaths, ["需求/attachments/prototype.png"])
    }

    func testDemandAttachmentCopyPreservesPublishedFileChangedInPlaceBeforeCleanup() throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try NativeDemandInputStore.makeAttachmentPlan(
            workspacePath: fixture.workspace.path,
            sourceURLs: [fixture.source]
        )
        let destination = plan.items[0].destinationURL
        var publishedInode: UInt64?

        let response = try NativeDemandInputStore.copyAttachments(
            plan: plan,
            confirmed: true,
            afterPublishBeforeVerify: { _ in
                publishedInode = try self.inodeNumber(at: destination)
                try Data("external same-inode attachment".utf8).write(to: destination, options: [])
                XCTAssertEqual(try self.inodeNumber(at: destination), publishedInode)
            }
        )

        XCTAssertTrue(response.copiedPaths.isEmpty)
        XCTAssertEqual(response.errors.map(\.sourcePath), [fixture.source.path])
        XCTAssertEqual(try inodeNumber(at: destination), publishedInode)
        XCTAssertEqual(try Data(contentsOf: destination), Data("external same-inode attachment".utf8))
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

        let prompt = await appState.featureIntakePrompt(for: workspace)

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
    func testAppStateSerializesDemandSavesPerWorkspaceAndKeepsLastDraftAfterCallerCancellation() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        let first = DemandInputDraft(requirement: "first", links: [], attachments: [])
        let second = DemandInputDraft(requirement: "second", links: ["https://example.com/latest"], attachments: [])
        let firstReachedSave = expectation(description: "first save reached detached IO")
        let releaseFirstSave = DispatchSemaphore(value: 0)
        let secondReachedSave = expectation(description: "second save reached detached IO")
        let releaseSecondSave = DispatchSemaphore(value: 0)
        defer {
            releaseFirstSave.signal()
            releaseSecondSave.signal()
        }

        let firstOperation = Task { @MainActor in
            await appState.saveDemandInputDraft(first, in: workspace) {
                firstReachedSave.fulfill()
                releaseFirstSave.wait()
            }
        }
        await fulfillment(of: [firstReachedSave], timeout: 2)

        let secondCaller = Task { @MainActor in
            await appState.saveDemandInputDraft(second, in: workspace) {
                secondReachedSave.fulfill()
                releaseSecondSave.wait()
            }
        }
        await Task.yield()
        secondCaller.cancel()

        XCTAssertTrue(appState.isDemandInputSaveActive(for: workspace))
        XCTAssertEqual(appState.demandInputSavingWorkspaceID, workspace.id)
        XCTAssertFalse(FileManager.default.fileExists(atPath: NativeDemandInputStore.canonicalDraftPath(workspacePath: workspace.path)))

        releaseFirstSave.signal()
        await fulfillment(of: [secondReachedSave], timeout: 2)
        let firstResult = await firstOperation.value

        XCTAssertTrue(firstResult.succeeded)
        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: workspace.path).draft, first)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft, first)
        XCTAssertTrue(appState.isDemandInputSaveActive(for: workspace))

        releaseSecondSave.signal()
        let secondResult = await secondCaller.value

        XCTAssertTrue(secondResult.succeeded)
        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: workspace.path).draft, second)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft, second)
        XCTAssertEqual(appState.demandInputSaveStatus(for: workspace), .saved)
        XCTAssertFalse(appState.hasDemandInputRecoveryDraft(for: workspace))
        XCTAssertFalse(appState.isDemandInputSaveActive(for: workspace))
        XCTAssertNil(appState.demandInputSavingWorkspaceID)
    }

    @MainActor
    func testAppStateDemandSaveQueuesAreIndependentAcrossWorkspaces() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstRoot = root.appendingPathComponent("first")
        let secondRoot = root.appendingPathComponent("second")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        let firstWorkspace = demandInputWorkspace(id: "first", path: firstRoot.path)
        let secondWorkspace = demandInputWorkspace(id: "second", path: secondRoot.path)
        let appState = makeAppState(workspaces: [firstWorkspace, secondWorkspace], root: root)
        let firstReachedSave = expectation(description: "first workspace reached detached IO")
        let releaseFirstSave = DispatchSemaphore(value: 0)
        defer { releaseFirstSave.signal() }

        let blocked = Task { @MainActor in
            await appState.saveDemandInputDraft(
                DemandInputDraft(requirement: "blocked", links: [], attachments: []),
                in: firstWorkspace
            ) {
                firstReachedSave.fulfill()
                releaseFirstSave.wait()
            }
        }
        await fulfillment(of: [firstReachedSave], timeout: 2)

        let independent = await appState.saveDemandInputDraft(
            DemandInputDraft(requirement: "independent", links: [], attachments: []),
            in: secondWorkspace
        )

        XCTAssertTrue(independent.succeeded)
        XCTAssertTrue(appState.isDemandInputSaveActive(for: firstWorkspace))
        XCTAssertFalse(appState.isDemandInputSaveActive(for: secondWorkspace))
        releaseFirstSave.signal()
        let blockedResult = await blocked.value
        XCTAssertTrue(blockedResult.succeeded)
    }

    @MainActor
    func testFeatureIntakePromptPathProbeRunsOffMainActor() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        let probeStarted = expectation(description: "changes path probe started")
        let releaseProbe = DispatchSemaphore(value: 0)
        defer { releaseProbe.signal() }

        let promptTask = Task { @MainActor in
            await appState.featureIntakePrompt(for: workspace) {
                probeStarted.fulfill()
                releaseProbe.wait()
            }
        }

        await fulfillment(of: [probeStarted], timeout: 2)
        appState.query = "main actor remained responsive during path probe"
        releaseProbe.signal()
        _ = await promptTask.value

        XCTAssertEqual(appState.query, "main actor remained responsive during path probe")
    }

    @MainActor
    func testFeatureIntakePromptReadsLatestDraftAfterPathProbe() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        let oldDraft = DemandInputDraft(requirement: "old prompt draft", links: [], attachments: [])
        let latestDraft = DemandInputDraft(
            requirement: "latest prompt draft",
            links: ["https://example.com/latest-prompt"],
            attachments: []
        )
        _ = await appState.saveDemandInputDraft(oldDraft, in: workspace)
        let probeStarted = expectation(description: "prompt probe started")
        let releaseProbe = DispatchSemaphore(value: 0)
        defer { releaseProbe.signal() }

        let promptTask = Task { @MainActor in
            await appState.featureIntakePrompt(for: workspace) {
                probeStarted.fulfill()
                releaseProbe.wait()
            }
        }
        await fulfillment(of: [probeStarted], timeout: 2)
        let saved = await appState.saveDemandInputDraft(latestDraft, in: workspace)
        XCTAssertTrue(saved.succeeded)
        releaseProbe.signal()
        let prompt = await promptTask.value

        XCTAssertTrue(prompt.contains(latestDraft.requirement))
        XCTAssertTrue(prompt.contains(latestDraft.links[0]))
        XCTAssertFalse(prompt.contains(oldDraft.requirement))
    }

    func testDemandStoreLocksDifferentWorkspacesIndependentlyInsideSaveCriticalSection() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let firstRoot = root.appendingPathComponent("first-store")
        let secondRoot = root.appendingPathComponent("second-store")
        try FileManager.default.createDirectory(at: firstRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: secondRoot, withIntermediateDirectories: true)
        let firstInsideLock = expectation(description: "first store save entered critical section")
        let secondCompleted = expectation(description: "second store save completed")
        let releaseFirst = DispatchSemaphore(value: 0)
        defer { releaseFirst.signal() }

        let first = Task.detached {
            try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "first", links: [], attachments: []),
                workspacePath: firstRoot.path,
                expectedRevision: .missing,
                beforeFinalRevisionCheck: {
                    firstInsideLock.fulfill()
                    releaseFirst.wait()
                }
            )
        }
        await fulfillment(of: [firstInsideLock], timeout: 2)

        let second = Task.detached {
            let response = try NativeDemandInputStore.save(
                draft: DemandInputDraft(requirement: "second", links: [], attachments: []),
                workspacePath: secondRoot.path,
                expectedRevision: .missing
            )
            secondCompleted.fulfill()
            return response
        }
        await fulfillment(of: [secondCompleted], timeout: 1)

        releaseFirst.signal()
        _ = try await first.value
        _ = try await second.value
    }

    @MainActor
    func testNativeAuditAppendRunsOffMainActor() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        let appendStarted = expectation(description: "audit append started")
        let releaseAppend = DispatchSemaphore(value: 0)
        defer { releaseAppend.signal() }

        let appendTask = Task { @MainActor in
            try await NativeAuditEventStore.appendAsync(
                auditRoot: root.appendingPathComponent("audit").path,
                event: AuditEventInput(
                    actor: "Nexus Native",
                    action: "test.appended",
                    target: root.path,
                    summary: "Test async audit append"
                )
            ) {
                appendStarted.fulfill()
                releaseAppend.wait()
            }
        }

        await fulfillment(of: [appendStarted], timeout: 2)
        appState.query = "main actor remained responsive during audit append"
        releaseAppend.signal()
        _ = try await appendTask.value

        XCTAssertEqual(appState.query, "main actor remained responsive during audit append")
        XCTAssertEqual(try NativeAuditEventStore.loadRecent(auditRoot: root.appendingPathComponent("audit").path, limit: 1).first?.action, "test.appended")
    }

    func testNativeAuditConcurrentAsyncAppendsPreserveEveryJSONLine() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let auditRoot = root.appendingPathComponent("audit").path
        let appendCount = 20

        let operations = (0..<appendCount).map { index in
            Task {
                await Task.yield()
                _ = try await NativeAuditEventStore.appendAsync(
                    auditRoot: auditRoot,
                    event: AuditEventInput(
                        actor: "Nexus Native",
                        action: "test.concurrent.\(index)",
                        target: root.path,
                        summary: "Concurrent audit append \(index)"
                    )
                )
            }
        }

        for operation in operations {
            _ = try await operation.value
        }

        let events = try NativeAuditEventStore.loadRecent(auditRoot: auditRoot, limit: appendCount)
        XCTAssertEqual(events.count, appendCount)
        XCTAssertEqual(Set(events.map(\.id)).count, appendCount)
        XCTAssertEqual(
            Set(events.map(\.action)),
            Set((0..<appendCount).map { "test.concurrent.\($0)" })
        )

        let fileURL = URL(fileURLWithPath: auditRoot).appendingPathComponent(NativeAuditEventStore.fileName)
        let lines = try String(contentsOf: fileURL, encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: true)
        XCTAssertEqual(lines.count, appendCount)
        for line in lines {
            XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(line.utf8)))
        }
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
        XCTAssertEqual(appState.demandInputSaveStatus(for: workspace), .failed(result.message!))

        await appState.loadDemandInput(for: workspace)
        let recovered = await appState.saveDemandInputDraft(edited, in: workspace)

        XCTAssertTrue(recovered.succeeded)
        XCTAssertEqual(appState.demandInputSaveStatus(for: workspace), .saved)
    }

    @MainActor
    func testAppStateFirstSaveFailureKeepsLiveDraftAcrossReloadAndRecovers() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let external = root.appendingPathComponent("external-demand")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let demandURL = root.appendingPathComponent("需求")
        try FileManager.default.createSymbolicLink(at: demandURL, withDestinationURL: external)
        let workspace = demandInputWorkspace(path: root.path + "/child/..")
        let appState = makeAppState(workspace: workspace, root: root)
        let liveDraft = DemandInputDraft(
            requirement: "recover this requirement",
            links: ["https://example.com/recovery"],
            attachments: ["需求/attachments/recovery.txt"]
        )

        let failed = await appState.saveDemandInputDraft(liveDraft, in: workspace)

        XCTAssertFalse(failed.succeeded)
        XCTAssertTrue(appState.hasDemandInputRecoveryDraft(for: workspace))
        let recovery = try XCTUnwrap(appState.demandInputSnapshot(for: workspace))
        XCTAssertEqual(recovery.draft, liveDraft)
        guard case .invalid = recovery.revision else {
            return XCTFail("Recovery snapshot must carry an invalid disk revision")
        }
        XCTAssertEqual(recovery.path, root.appendingPathComponent("需求/intake-draft.md").path)
        XCTAssertEqual(
            FeatureWorkspaceDraftPolicy.refreshedDraft(current: .empty, snapshot: recovery),
            liveDraft
        )

        await appState.loadDemandInput(for: workspace)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft, liveDraft)

        try FileManager.default.removeItem(at: demandURL)
        await appState.loadDemandInput(for: workspace)
        await appState.loadDemandInput(for: workspace)
        await appState.loadDemandInput(for: workspace)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft, liveDraft)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.revision, .missing)
        XCTAssertTrue(appState.hasDemandInputRecoveryDraft(for: workspace))
        let recovered = await appState.saveDemandInputDraft(liveDraft, in: workspace)

        XCTAssertTrue(recovered.succeeded)
        guard case .regularUTF8 = appState.demandInputSnapshot(for: workspace)?.revision else {
            return XCTFail("Successful recovery must restore a regular revision")
        }
        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: workspace.path).draft, liveDraft)
        XCTAssertEqual(appState.demandInputSaveStatus(for: workspace), .saved)
        XCTAssertFalse(appState.hasDemandInputRecoveryDraft(for: workspace))
    }

    @MainActor
    func testAppStateAttachmentCopySavesLiveDraftBeforePlanningAndKeepsAllFields() async throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let workspace = demandInputWorkspace(path: fixture.workspace.path)
        let appState = makeAppState(workspace: workspace, root: fixture.root)
        _ = await appState.saveDemandInputDraft(
            DemandInputDraft(requirement: "stale", links: ["https://stale.example"], attachments: []),
            in: workspace
        )
        let liveDraft = DemandInputDraft(
            requirement: "live requirement",
            links: ["https://live.example/spec"],
            attachments: []
        )

        let response = await appState.attachDemandMaterials(
            [fixture.source],
            liveDraft: liveDraft,
            to: workspace,
            confirmed: true
        )

        let expected = DemandInputDraft(
            requirement: "live requirement",
            links: ["https://live.example/spec"],
            attachments: ["需求/attachments/prototype.png"]
        )
        XCTAssertEqual(response?.copiedPaths, ["\(fixture.workspace.path)/需求/attachments/prototype.png"])
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft, expected)
        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: workspace.path).draft, expected)
    }

    @MainActor
    func testCanonicalWorkspaceAttachmentCopyRegistersVerifiedRelativePathEverywhere() async throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let nonCanonicalPath = fixture.workspace.path + "/child/.."
        let workspace = demandInputWorkspace(path: nonCanonicalPath)
        XCTAssertTrue(workspace.path.hasSuffix("/child/.."))
        let appState = makeAppState(workspace: workspace, root: fixture.root)
        let liveDraft = DemandInputDraft(requirement: "live", links: ["https://example.com"], attachments: [])

        let response = await appState.attachDemandMaterials(
            [fixture.source],
            liveDraft: liveDraft,
            to: workspace,
            confirmed: true
        )

        let relativePath = "需求/attachments/prototype.png"
        XCTAssertEqual(response?.copiedRelativePaths, [relativePath])
        let snapshot = try XCTUnwrap(appState.demandInputSnapshot(for: workspace))
        XCTAssertEqual(snapshot.draft.attachments, [relativePath])
        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: workspace.path).draft.attachments, [relativePath])
        XCTAssertEqual(
            FeatureWorkspaceDraftPolicy.refreshedDraft(current: liveDraft, snapshot: snapshot).attachments,
            [relativePath]
        )
        XCTAssertEqual(
            response?.copiedPaths,
            [fixture.workspace.appendingPathComponent(relativePath).path]
        )
    }

    @MainActor
    func testAppStateAttachmentCopyDoesNotCopyWhenLiveDraftSaveFails() async throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let workspace = demandInputWorkspace(path: fixture.workspace.path)
        let appState = makeAppState(workspace: workspace, root: fixture.root)
        _ = await appState.saveDemandInputDraft(
            DemandInputDraft(requirement: "saved", links: [], attachments: []),
            in: workspace
        )
        let diskSnapshot = try XCTUnwrap(appState.demandInputSnapshot(for: workspace))
        try "external".write(to: URL(fileURLWithPath: diskSnapshot.path), atomically: true, encoding: .utf8)
        let liveDraft = DemandInputDraft(
            requirement: "live requirement",
            links: ["https://live.example/spec"],
            attachments: []
        )

        let response = await appState.attachDemandMaterials(
            [fixture.source],
            liveDraft: liveDraft,
            to: workspace,
            confirmed: true
        )

        XCTAssertNil(response)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft, liveDraft)
        XCTAssertNotNil(appState.lastError)
        XCTAssertFalse(FileManager.default.fileExists(atPath: fixture.workspace.appendingPathComponent("需求/attachments/prototype.png").path))
    }

    @MainActor
    func testAppStateAttachmentCopyPreservesCopiedPathsWhenFollowUpLoadFails() async throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let workspace = demandInputWorkspace(path: fixture.workspace.path)
        let appState = makeAppState(workspace: workspace, root: fixture.root)
        let external = fixture.root.appendingPathComponent("external-demand")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)

        let response = await appState.attachDemandMaterials(
            [fixture.source],
            liveDraft: .empty,
            to: workspace,
            confirmed: true,
            beforeAttachmentResponse: {
                let demand = fixture.workspace.appendingPathComponent("需求")
                try? FileManager.default.moveItem(at: demand, to: fixture.workspace.appendingPathComponent("original-demand"))
                try? FileManager.default.createSymbolicLink(at: demand, withDestinationURL: external)
            }
        )

        XCTAssertEqual(response?.copiedPaths.count, 1)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft.attachments, ["需求/attachments/prototype.png"])
        XCTAssertNotNil(appState.lastError)
    }

    @MainActor
    func testAppStateAttachmentCopyMergesConcurrentUIEditsAndKeepsOperationBusy() async throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let workspace = demandInputWorkspace(path: fixture.workspace.path)
        let appState = makeAppState(workspace: workspace, root: fixture.root)
        let captured = DemandInputDraft(requirement: "captured", links: [], attachments: [])
        var currentUI = captured
        var wasBusyBeforeResponse = false

        let response = await appState.attachDemandMaterials(
            [fixture.source],
            liveDraft: captured,
            currentDraft: { currentUI },
            to: workspace,
            confirmed: true,
            beforeAttachmentResponse: {
                currentUI.requirement = "edited while attaching"
                currentUI.links = ["https://example.com/during-attachment"]
                wasBusyBeforeResponse = appState.isDemandAttachmentOperationActive(for: workspace)
            }
        )

        let expected = DemandInputDraft(
            requirement: "edited while attaching",
            links: ["https://example.com/during-attachment"],
            attachments: ["需求/attachments/prototype.png"]
        )
        XCTAssertTrue(wasBusyBeforeResponse)
        XCTAssertFalse(appState.isDemandAttachmentOperationActive(for: workspace))
        XCTAssertEqual(response?.copiedRelativePaths, expected.attachments)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft, expected)
        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: workspace.path).draft, expected)
    }

    @MainActor
    func testAppStateAttachmentCopyRunsDiskIOOffMainActorAndMergesCurrentDraft() async throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let workspace = demandInputWorkspace(path: fixture.workspace.path)
        let appState = makeAppState(workspace: workspace, root: fixture.root)
        let captured = DemandInputDraft(requirement: "captured", links: [], attachments: [])
        var currentUI = captured
        let copyReachedWrite = expectation(description: "copy reached destination write")
        let releaseCopy = DispatchSemaphore(value: 0)

        let operation = Task { @MainActor in
            await appState.attachDemandMaterials(
                [fixture.source],
                liveDraft: captured,
                currentDraft: { currentUI },
                to: workspace,
                confirmed: true,
                beforeDestinationWrite: { _ in
                    copyReachedWrite.fulfill()
                    releaseCopy.wait()
                }
            )
        }

        await fulfillment(of: [copyReachedWrite], timeout: 2)
        appState.query = "main actor remained responsive"
        currentUI = DemandInputDraft(
            requirement: "edited while background copy was blocked",
            links: ["https://example.com/background-copy"],
            attachments: []
        )
        let concurrentAutosave = await appState.saveDemandInputDraft(currentUI, in: workspace)
        XCTAssertTrue(concurrentAutosave.succeeded)
        releaseCopy.signal()
        let response = await operation.value

        let expected = DemandInputDraft(
            requirement: currentUI.requirement,
            links: currentUI.links,
            attachments: ["需求/attachments/prototype.png"]
        )
        XCTAssertEqual(appState.query, "main actor remained responsive")
        XCTAssertEqual(response?.copiedRelativePaths, expected.attachments)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft, expected)
        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: workspace.path).draft, expected)
    }

    @MainActor
    func testAppStateAttachmentFailureStillSavesLatestUIEdits() async throws {
        let fixture = try demandAttachmentFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let workspace = demandInputWorkspace(path: fixture.workspace.path)
        let appState = makeAppState(workspace: workspace, root: fixture.root)
        let captured = DemandInputDraft(requirement: "captured", links: [], attachments: [])
        let latest = DemandInputDraft(
            requirement: "edited before copy failed",
            links: ["https://example.com/latest"],
            attachments: []
        )
        let external = fixture.root.appendingPathComponent("external-attachments")
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: true)
        let attachments = fixture.workspace.appendingPathComponent("需求/attachments")
        try FileManager.default.createDirectory(
            at: attachments.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(at: attachments, withDestinationURL: external)

        let response = await appState.attachDemandMaterials(
            [fixture.source],
            liveDraft: captured,
            currentDraft: { latest },
            to: workspace,
            confirmed: true
        )

        XCTAssertNil(response)
        XCTAssertEqual(appState.demandInputSnapshot(for: workspace)?.draft, latest)
        XCTAssertEqual(try NativeDemandInputStore.load(workspacePath: workspace.path).draft, latest)
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

    private func inodeNumber(at url: URL) throws -> UInt64 {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        return try XCTUnwrap((attributes[.systemFileNumber] as? NSNumber)?.uint64Value)
    }

    private func demandInputWorkspace(id: String = "demand-input-workspace", path: String) -> WorkspaceSummary {
        WorkspaceSummary(
            id: id,
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

    @MainActor
    private func makeAppState(workspace: WorkspaceSummary, root: URL) -> AppState {
        makeAppState(workspaces: [workspace], root: root)
    }

    @MainActor
    private func makeAppState(workspaces: [WorkspaceSummary], root: URL) -> AppState {
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsSuite) }
        return AppState(
            workspaces: workspaces,
            agentStatus: AgentStatus(title: "Ready", detail: "Tests", connectedTools: []),
            bridge: PreviewNexusBridge(),
            workspaceRoot: root.path,
            sourceReposRoot: root.path,
            docsRoot: root.path,
            defaults: defaults
        )
    }

    private enum PublishFailure: Error {
        case injected
    }
}
