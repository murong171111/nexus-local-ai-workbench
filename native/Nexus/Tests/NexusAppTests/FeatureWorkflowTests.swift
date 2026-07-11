import XCTest
@testable import NexusApp
import NexusBridge

final class FeatureWorkflowTests: XCTestCase {
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

    @MainActor
    private func makeAppState(workspace: WorkspaceSummary, root: URL) -> AppState {
        let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: defaultsSuite)!
        addTeardownBlock { defaults.removePersistentDomain(forName: defaultsSuite) }
        return AppState(
            workspaces: [workspace],
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
