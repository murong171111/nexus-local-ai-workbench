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

    func testFeatureDocumentRejectsIdentifierShapedNonFeatureHeading() {
        XCTAssertThrowsError(
            try NativeFeatureStore.parse(
                "## G-001 Wrong namespace\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
            )
        )
        XCTAssertNoThrow(try NativeFeatureStore.parse("# Features\n\n## Notes\n\nOrdinary prose.\n"))
        XCTAssertNoThrow(try NativeFeatureStore.parse("# Features\n\n## API-Notes\n\nOrdinary prose.\n"))
        XCTAssertNoThrow(try NativeFeatureStore.parse("# Features\n\n## F-series notes\n\nOrdinary prose.\n"))
    }

    func testFeatureRenderPreservesOriginalLayoutForMetadataOnlyEdit() throws {
        let source = """
        # Features


        ## F-001 Snapshot
        prose before metadata
        - Status: todo

        prose between fields
        - Verification: code
        - Auto complete: true
        - Source: z.png, a.png


        """ + "\n"
        let document = try NativeFeatureStore.parse(source)
        var feature = try XCTUnwrap(document.features.first)
        feature.title = "Renamed"
        feature.status = .blocked
        feature.sources = ["b.png", "a.png", "a.png"]
        var edited = document
        edited.features[0] = feature

        XCTAssertEqual(
            NativeFeatureStore.render(edited),
            source
                .replacingOccurrences(of: "## F-001 Snapshot", with: "## F-001 Renamed")
                .replacingOccurrences(of: "- Status: todo", with: "- Status: blocked")
                .replacingOccurrences(of: "- Source: z.png, a.png", with: "- Source: a.png, b.png")
        )
    }

    func testFeatureEditPreservesOriginalMarkdownWhenDescriptionIsUnchanged() throws {
        let source = """
        ## F-001 Snapshot
        - Status: todo
        - Verification: code
        - Auto complete: true

        Description.

            indented code

        """
        let original = try XCTUnwrap(NativeFeatureStore.parse(source).features.first)

        let replacement = FeatureEditState.makeFeature(
            original: original,
            title: "Renamed",
            verification: .manual,
            autoComplete: false,
            sources: [],
            services: [],
            taskIDs: [],
            evidenceIDs: [],
            description: original.description
        )

        XCTAssertEqual(replacement.preservedLines, original.preservedLines)
        XCTAssertTrue(NativeFeatureStore.render(FeatureDocument(preamble: [], features: [replacement])).contains("\n    indented code\n"))
    }

    func testFeatureUpdateWritesChangedDescriptionWithoutDisturbingOtherLayout() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let source = """
        # Features

        Intro.

        ## F-001 Snapshot
        old prose first
        - Status: todo

        old prose second
        - Verification: code
        - Auto complete: true

        ## F-002 Untouched

        - Status: todo
        - Verification: manual
        - Auto complete: false

        keep these bytes
        """ + "\n"
        try source.write(to: featuresURL, atomically: true, encoding: .utf8)
        let original = try XCTUnwrap(
            NativeFeatureStore.load(workspacePath: root.path).document.features.first
        )
        var replacement = FeatureEditState.makeFeature(
            original: original,
            title: original.title,
            verification: original.verification,
            autoComplete: original.autoComplete,
            sources: original.sources,
            services: original.services,
            taskIDs: original.taskIDs,
            evidenceIDs: original.evidenceIDs,
            description: "new prose first\nnew prose second"
        )
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .update(expected: original, replacement: replacement)
        )

        _ = try NativeFeatureStore.write(plan: plan, confirmed: true)

        let written = try String(contentsOf: featuresURL, encoding: .utf8)
        XCTAssertTrue(written.contains("new prose first\nnew prose second"))
        XCTAssertFalse(written.contains("old prose first"))
        XCTAssertFalse(written.contains("old prose second"))
        XCTAssertTrue(written.hasPrefix("# Features\n\nIntro.\n\n"))
        XCTAssertEqual(
            written.components(separatedBy: "## F-002 Untouched").last,
            source.components(separatedBy: "## F-002 Untouched").last
        )
        let reloaded = try NativeFeatureStore.load(workspacePath: root.path).document.features[0]
        replacement.preservedLines = ["", "new prose first", "new prose second"]
        XCTAssertEqual(reloaded, replacement)
    }

    func testFeatureRenderInsertsChangedDescriptionAfterMetadataWhenLayoutHadNoProse() throws {
        let source = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true"
        var document = try NativeFeatureStore.parse(source)
        document.features[0].description = "new first\nnew second"
        document.features[0].preservedLines = ["new first\nnew second"]

        let rendered = NativeFeatureStore.render(document)

        XCTAssertEqual(
            rendered,
            "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\nnew first\nnew second"
        )
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

    func testFeatureWriteRejectsCompleteInjectedFeatureBeforePublish() throws {
        try assertFeatureInjectionRejectedBeforePublish(
            "\n## F-999 Injected\n- Status: todo\n- Verification: manual\n- Auto complete: false\n"
        )
    }

    func testFeatureWriteRejectsMalformedInjectedFeatureBeforePublish() throws {
        try assertFeatureInjectionRejectedBeforePublish("\n## F-999 Broken\n- Status: todo\n")
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

    func testFeatureWriteKeepsOpenedWorkspaceWhenWorkspacePathIsReplaced() throws {
        let parent = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: parent) }
        let workspace = parent.appendingPathComponent("workspace")
        let openedWorkspace = parent.appendingPathComponent("opened-workspace")
        let external = parent.appendingPathComponent("external")
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        try FileManager.default.createDirectory(at: external, withIntermediateDirectories: false)
        let original = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        try original.write(to: workspace.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8)
        try "outside".write(to: external.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8)
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: workspace.path,
            mutation: .setStatus(id: "F-001", status: .done, completionNote: "manual")
        )

        _ = try NativeFeatureStore.write(
            plan: plan,
            confirmed: true,
            afterWorkspaceOpen: {
                try FileManager.default.moveItem(at: workspace, to: openedWorkspace)
                try FileManager.default.createSymbolicLink(at: workspace, withDestinationURL: external)
            }
        )

        XCTAssertEqual(try String(contentsOf: external.appendingPathComponent("FEATURES.md"), encoding: .utf8), "outside")
        XCTAssertEqual(
            try NativeFeatureStore.load(workspacePath: openedWorkspace.path).document.features.first?.status,
            .done
        )
    }

    func testFeatureWriteRejectsLeafReplacedWithSymlinkBeforeFinalCheck() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let externalURL = root.appendingPathComponent("external.md")
        let original = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        try original.write(to: featuresURL, atomically: true, encoding: .utf8)
        try "outside".write(to: externalURL, atomically: true, encoding: .utf8)
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .setStatus(id: "F-001", status: .done, completionNote: "manual")
        )

        XCTAssertThrowsError(
            try NativeFeatureStore.write(
                plan: plan,
                confirmed: true,
                beforeFinalRevisionCheck: {
                    try FileManager.default.removeItem(at: featuresURL)
                    try FileManager.default.createSymbolicLink(at: featuresURL, withDestinationURL: externalURL)
                }
            )
        )
        XCTAssertEqual(try String(contentsOf: externalURL, encoding: .utf8), "outside")
    }

    func testFeatureWritePreservesExistingExternalChangeAfterFinalCheck() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let original = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        try original.write(to: featuresURL, atomically: true, encoding: .utf8)
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .setStatus(id: "F-001", status: .done, completionNote: "manual")
        )

        XCTAssertThrowsError(
            try NativeFeatureStore.write(
                plan: plan,
                confirmed: true,
                beforePublish: {
                    try Data("external after check".utf8).write(to: featuresURL, options: [])
                }
            )
        )
        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), "external after check")
    }

    func testFeatureWritePreservesExternalReplacementAndRecoverableOriginalAfterSwap() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let original = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        let external = "external replacement"
        try original.write(to: featuresURL, atomically: true, encoding: .utf8)
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .setStatus(id: "F-001", status: .done, completionNote: "manual")
        )

        XCTAssertThrowsError(
            try NativeFeatureStore.write(
                plan: plan,
                confirmed: true,
                afterPublishBeforeVerify: {
                    try external.write(to: featuresURL, atomically: true, encoding: .utf8)
                }
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("recovery required"))
        }
        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), external)
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".FEATURES.md.") && $0.pathExtension == "tmp" }
        XCTAssertEqual(recoveryFiles.count, 1)
        XCTAssertEqual(try String(contentsOf: recoveryFiles[0], encoding: .utf8), original)
    }

    func testFeatureWriteRollsBackWhenPostPublishHookThrowsWithoutChangingFiles() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let original = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        try original.write(to: featuresURL, atomically: true, encoding: .utf8)
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .setStatus(id: "F-001", status: .done, completionNote: "manual")
        )

        XCTAssertThrowsError(
            try NativeFeatureStore.write(
                plan: plan,
                confirmed: true,
                afterPublishBeforeVerify: { throw PublishFailure.injected }
            )
        )

        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), original)
        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.hasPrefix(".FEATURES.md.") && $0.hasSuffix(".tmp") }
                .isEmpty
        )
    }

    func testFeatureWriteDoesNotRollbackTargetChangedInPlaceAfterSwap() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let original = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        let external = "external same-inode feature"
        try original.write(to: featuresURL, atomically: true, encoding: .utf8)
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .setStatus(id: "F-001", status: .done, completionNote: "manual")
        )
        var publishedInode: UInt64?

        XCTAssertThrowsError(
            try NativeFeatureStore.write(
                plan: plan,
                confirmed: true,
                afterPublishBeforeVerify: {
                    publishedInode = try self.inodeNumber(at: featuresURL)
                    try Data(external.utf8).write(to: featuresURL, options: [])
                    XCTAssertEqual(try self.inodeNumber(at: featuresURL), publishedInode)
                }
            )
        ) { error in
            XCTAssertTrue(error.localizedDescription.contains("recovery required"))
        }

        XCTAssertEqual(try inodeNumber(at: featuresURL), publishedInode)
        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), external)
        let recoveryFiles = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix(".FEATURES.md.") && $0.pathExtension == "tmp" }
        XCTAssertEqual(recoveryFiles.count, 1)
        XCTAssertEqual(try String(contentsOf: recoveryFiles[0], encoding: .utf8), original)
    }

    func testFeatureFirstWriteDoesNotOverwriteFileCreatedAfterFinalCheck() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let feature = WorkspaceFeature(
            id: "F-001", title: "Snapshot", status: .todo, verification: .code,
            autoComplete: true, sources: [], services: [], taskIDs: [], evidenceIDs: [],
            description: "", completedAt: nil, completedBy: nil, completionNote: nil,
            evidenceStale: false, preservedLines: []
        )
        let plan = try NativeFeatureStore.makePlan(workspacePath: root.path, mutation: .add(feature))

        XCTAssertThrowsError(
            try NativeFeatureStore.write(
                plan: plan,
                confirmed: true,
                beforePublish: {
                    try "external first writer".write(to: featuresURL, atomically: false, encoding: .utf8)
                }
            )
        )
        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), "external first writer")
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

    func testFeatureProposalParserAcceptsDraftAndExistingIDsWithoutRelaxingConfirmedParser() throws {
        let proposal = try NativeFeatureStore.parseProposal(
            featureSource(id: "F-001", title: "Changed")
                + "\n" + featureSource(id: "DRAFT-001", title: "Added")
        )

        XCTAssertEqual(proposal.features.map(\.id), ["F-001", "DRAFT-001"])
        XCTAssertThrowsError(try NativeFeatureStore.parse(featureSource(id: "DRAFT-001", title: "Added")))
        XCTAssertThrowsError(try NativeFeatureStore.parseProposal(featureSource(id: "DRAFT-01", title: "Bad"))) {
            XCTAssertEqual($0.localizedDescription, "invalid feature ID: DRAFT-01")
        }
        XCTAssertThrowsError(
            try NativeFeatureStore.parseProposal(
                featureSource(id: "DRAFT-001", title: "First")
                    + "\n" + featureSource(id: "DRAFT-001", title: "Second")
            )
        ) {
            XCTAssertEqual($0.localizedDescription, "duplicate feature ID: DRAFT-001")
        }
    }

    func testFeatureProposalParserRejectsEveryMalformedDraftPrefixedHeading() {
        for heading in ["## DRAFT-ABC Bad", "## DRAFT-01 Bad", "## DRAFT-001"] {
            XCTAssertThrowsError(
                try NativeFeatureStore.parseProposal(
                    "\(heading)\n- Status: draft\n- Verification: code\n- Auto complete: true\n"
                ),
                heading
            )
        }
        XCTAssertNoThrow(try NativeFeatureStore.parse("## F-series notes\n\nOrdinary prose.\n"))
        XCTAssertThrowsError(
            try NativeFeatureStore.parse(
                "## F-01 Bad\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
            )
        )
    }

    func testFeatureProposalDiffSeparatesAddsChangesAndCancellationsDeterministically() throws {
        let confirmed = try NativeFeatureStore.parse(
            featureSource(id: "F-010", title: "Changed")
                + "\n" + featureSource(id: "F-002", title: "Cancelled", status: "cancelled")
                + "\n" + featureSource(id: "F-007", title: "Omitted")
        )
        let draft = try NativeFeatureStore.parseProposal(
            featureSource(id: "F-010", title: "Changed title")
                + "\n" + featureSource(id: "DRAFT-002", title: "Second add", status: "draft")
                + "\n" + featureSource(id: "DRAFT-001", title: "First add", status: "draft")
        )

        let diff = FeatureProposalDiff.resolve(confirmed: confirmed, draft: draft)

        XCTAssertEqual(diff.items.map(\.kind), [.change, .unchanged, .cancel, .add, .add])
        XCTAssertEqual(diff.items.map(\.id), ["F-010", "F-002", "F-007", "DRAFT-002", "DRAFT-001"])
        XCTAssertEqual(diff.items.compactMap(\.assignedFeatureID), ["F-011", "F-012"])
    }

    func testFeatureProposalDiffIgnoresLifecycleAndCompletionHistory() throws {
        let confirmed = try NativeFeatureStore.parse(
            featureSourceWithHistory(id: "F-001", title: "Same", description: "Same prose")
        )
        let draft = try NativeFeatureStore.parseProposal(
            featureSource(id: "F-001", title: "Same") + "\nSame prose\n"
        )

        XCTAssertEqual(
            FeatureProposalDiff.resolve(confirmed: confirmed, draft: draft).items.first?.kind,
            .unchanged
        )
    }

    func testFeatureProposalChangePreservesCurrentLifecycleAndCompletionHistory() throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try featureSourceWithHistory(id: "F-001", title: "Done title", description: "Old prose").write(
            to: root.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8
        )
        try (featureSource(id: "F-001", title: "Changed title", status: "todo") + "\nNew prose\n").write(
            to: root.appendingPathComponent("FEATURES.draft.md"), atomically: true, encoding: .utf8
        )

        let response = try NativeFeatureStore.merge(
            plan: NativeFeatureStore.makeMergePlan(workspacePath: root.path),
            confirmed: true
        )
        let feature = try XCTUnwrap(response.document.features.first)

        XCTAssertEqual(feature.title, "Changed title")
        XCTAssertEqual(feature.description, "New prose")
        XCTAssertEqual(feature.status, .done)
        XCTAssertEqual(feature.completedAt, "2026-07-11T01:02:03Z")
        XCTAssertEqual(feature.completedBy, "Reviewer")
        XCTAssertEqual(feature.completionNote, "Accepted before proposal")
        XCTAssertTrue(feature.evidenceStale)
    }

    func testFeatureProposalAddClearsForgedLifecycleAndCompletionHistory() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let initial = try NativeFeatureStore.makeMergePlan(
            workspacePath: root.path,
            selectedItemIDs: ["DRAFT-001"]
        )
        var forged = try XCTUnwrap(initial.items.first { $0.id == "DRAFT-001" }?.proposed)
        forged.status = .done
        forged.completedAt = "2026-07-11T01:02:03Z"
        forged.completedBy = "Forger"
        forged.completionNote = "Forged history"
        forged.evidenceStale = true
        let plan = try NativeFeatureStore.makeMergePlan(
            workspacePath: root.path,
            selectedItemIDs: ["DRAFT-001"],
            replacements: ["DRAFT-001": forged]
        )

        let added = try XCTUnwrap(
            NativeFeatureStore.merge(plan: plan, confirmed: true).document.features.first { $0.id == "F-003" }
        )

        XCTAssertEqual(added.status, .todo)
        XCTAssertNil(added.completedAt)
        XCTAssertNil(added.completedBy)
        XCTAssertNil(added.completionNote)
        XCTAssertFalse(added.evidenceStale)
    }

    func testFeatureProposalMergeAppliesOnlyCapturedSelectionsAndEditsInOneWrite() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        var edited = try XCTUnwrap(
            NativeFeatureStore.parseProposal(featureSource(id: "F-001", title: "Edited by user")).features.first
        )
        edited.description = "captured replacement"
        edited.preservedLines = ["", "captured replacement"]
        let plan = try NativeFeatureStore.makeMergePlan(
            workspacePath: root.path,
            selectedItemIDs: ["F-001", "DRAFT-001"],
            replacements: ["F-001": edited]
        )

        edited.title = "changed after capture"
        let response = try NativeFeatureStore.merge(plan: plan, confirmed: true)

        XCTAssertEqual(response.document.features.map(\.id), ["F-001", "F-002", "F-003"])
        XCTAssertEqual(response.document.features[0].title, "Edited by user")
        XCTAssertEqual(response.document.features[0].description, "captured replacement")
        XCTAssertEqual(response.document.features[1].status, .todo, "unselected cancellation must be ignored")
        XCTAssertEqual(response.document.features[2].title, "Added")
        XCTAssertEqual(response.document.features[2].status, .todo)
    }

    func testFeatureProposalMergeRejectsUnconfirmedAndPreservesBothFiles() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let facts = root.appendingPathComponent("FEATURES.md")
        let draft = root.appendingPathComponent("FEATURES.draft.md")
        let originalFacts = try Data(contentsOf: facts)
        let originalDraft = try Data(contentsOf: draft)
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)

        XCTAssertThrowsError(try NativeFeatureStore.merge(plan: plan, confirmed: false))
        XCTAssertEqual(try Data(contentsOf: facts), originalFacts)
        XCTAssertEqual(try Data(contentsOf: draft), originalDraft)
    }

    func testFeatureProposalMergeRejectsChangedDraftRevision() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let facts = root.appendingPathComponent("FEATURES.md")
        let originalFacts = try Data(contentsOf: facts)
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)
        try "external draft".write(
            to: root.appendingPathComponent("FEATURES.draft.md"), atomically: true, encoding: .utf8
        )

        XCTAssertThrowsError(try NativeFeatureStore.merge(plan: plan, confirmed: true)) {
            XCTAssertTrue($0.localizedDescription.contains("FEATURES.draft.md changed since confirmation"))
        }
        XCTAssertEqual(try Data(contentsOf: facts), originalFacts)
    }

    func testFeatureProposalMergeRejectsChangedConfirmedRevision() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let facts = root.appendingPathComponent("FEATURES.md")
        let draft = root.appendingPathComponent("FEATURES.draft.md")
        let originalDraft = try Data(contentsOf: draft)
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)
        try "external facts".write(to: facts, atomically: true, encoding: .utf8)

        XCTAssertThrowsError(try NativeFeatureStore.merge(plan: plan, confirmed: true)) {
            XCTAssertTrue($0.localizedDescription.contains("FEATURES.md changed since confirmation"))
        }
        XCTAssertEqual(try Data(contentsOf: draft), originalDraft)
        XCTAssertEqual(try String(contentsOf: facts, encoding: .utf8), "external facts")
    }

    func testFeatureProposalMergeRejectsForgedItemsWithoutChangingFacts() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)
        var forgedItems = plan.items
        let index = try XCTUnwrap(forgedItems.firstIndex { $0.id == "F-001" })
        var forgedFeature = try XCTUnwrap(forgedItems[index].proposed)
        forgedFeature.title = "Forged item"
        forgedItems[index] = FeatureProposalItem(
            id: forgedItems[index].id,
            kind: forgedItems[index].kind,
            confirmed: forgedItems[index].confirmed,
            proposed: forgedFeature,
            assignedFeatureID: forgedItems[index].assignedFeatureID
        )

        try assertRejectedProposalMergePreservesFacts(
            forgedProposalPlan(plan, items: forgedItems),
            root: root
        )
    }

    func testFeatureProposalMergeRejectsForgedAssignedIDWithoutChangingFacts() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)
        var forgedItems = plan.items
        let index = try XCTUnwrap(forgedItems.firstIndex { $0.id == "DRAFT-001" })
        let item = forgedItems[index]
        forgedItems[index] = FeatureProposalItem(
            id: item.id,
            kind: item.kind,
            confirmed: item.confirmed,
            proposed: item.proposed,
            assignedFeatureID: "F-999"
        )

        try assertRejectedProposalMergePreservesFacts(
            forgedProposalPlan(plan, items: forgedItems),
            root: root
        )
    }

    func testFeatureProposalMergeRejectsForgedSelectionWithoutChangingFacts() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)

        try assertRejectedProposalMergePreservesFacts(
            forgedProposalPlan(plan, selectedItemIDs: plan.selectedItemIDs.union(["forged-selection"])),
            root: root
        )
    }

    func testFeatureProposalMergeRejectsForgedReplacementKeyWithoutChangingFacts() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)
        let cancelReplacement = try XCTUnwrap(plan.items.first { $0.id == "F-002" }?.confirmed)

        try assertRejectedProposalMergePreservesFacts(
            forgedProposalPlan(plan, replacements: ["F-002": cancelReplacement]),
            root: root
        )
    }

    func testFeatureProposalLoadRejectsDraftSymlinkAndInvalidUTF8WithoutChangingFacts() throws {
        for invalidKind in 0..<2 {
            let root = try featureProposalWorkspace()
            defer { try? FileManager.default.removeItem(at: root) }
            let facts = root.appendingPathComponent("FEATURES.md")
            let draft = root.appendingPathComponent("FEATURES.draft.md")
            let originalFacts = try Data(contentsOf: facts)
            try FileManager.default.removeItem(at: draft)
            if invalidKind == 0 {
                let external = root.appendingPathComponent("external.md")
                try featureSource(id: "DRAFT-001", title: "Outside").write(
                    to: external, atomically: true, encoding: .utf8
                )
                try FileManager.default.createSymbolicLink(at: draft, withDestinationURL: external)
            } else {
                try Data([0xFF, 0xFE]).write(to: draft)
            }

            XCTAssertThrowsError(try NativeFeatureStore.makeMergePlan(workspacePath: root.path))
            XCTAssertEqual(try Data(contentsOf: facts), originalFacts)
        }
    }

    func testFeatureProposalMergeRejectsEitherDocumentChangedAfterFinalCheck() throws {
        for changedName in ["FEATURES.md", "FEATURES.draft.md"] {
            let root = try featureProposalWorkspace()
            defer { try? FileManager.default.removeItem(at: root) }
            let facts = root.appendingPathComponent("FEATURES.md")
            let draft = root.appendingPathComponent("FEATURES.draft.md")
            let originalFacts = try Data(contentsOf: facts)
            let originalDraft = try Data(contentsOf: draft)
            let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)

            XCTAssertThrowsError(
                try NativeFeatureStore.merge(
                    plan: plan,
                    confirmed: true,
                    beforePublish: {
                        try Data("external after final check".utf8).write(
                            to: root.appendingPathComponent(changedName), options: []
                        )
                    }
                )
            )
            if changedName == "FEATURES.md" {
                XCTAssertEqual(try String(contentsOf: facts, encoding: .utf8), "external after final check")
                XCTAssertEqual(try Data(contentsOf: draft), originalDraft)
            } else {
                XCTAssertEqual(try Data(contentsOf: facts), originalFacts)
                XCTAssertEqual(try String(contentsOf: draft, encoding: .utf8), "external after final check")
            }
        }
    }

    func testFeatureProposalMergeReportsArchiveCollisionWithoutDamagingMainWriteOrDraft() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = root.appendingPathComponent("FEATURES.draft.md")
        let originalDraft = try Data(contentsOf: draft)
        let archiveName = "FEATURES.draft.accepted-20260711T120000Z.md"
        let archive = root.appendingPathComponent(archiveName)
        try "existing archive".write(to: archive, atomically: true, encoding: .utf8)
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)

        let response = try NativeFeatureStore.merge(
            plan: plan,
            confirmed: true,
            archiveTimestamp: "20260711T120000Z"
        )

        XCTAssertEqual(response.document.features.map(\.id), ["F-001", "F-002", "F-003"])
        XCTAssertNil(response.archivePath)
        XCTAssertNotNil(response.archiveError)
        XCTAssertEqual(try String(contentsOf: archive, encoding: .utf8), "existing archive")
        XCTAssertEqual(try Data(contentsOf: draft), originalDraft)
    }

    func testFeatureProposalMergeArchivesMatchingDraftAndAuditsCountsAndSourceRevisions() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let auditRoot = root.appendingPathComponent("audit").path
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)

        let response = try NativeFeatureStore.merge(
            plan: plan,
            confirmed: true,
            auditRoot: auditRoot,
            archiveTimestamp: "20260711T120001Z"
        )

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("FEATURES.draft.md").path))
        XCTAssertEqual(response.archivePath, root.appendingPathComponent("FEATURES.draft.accepted-20260711T120001Z.md").path)
        let event = try XCTUnwrap(NativeAuditEventStore.loadRecent(auditRoot: auditRoot, limit: 1).first)
        XCTAssertEqual(event.action, "feature.proposal_merged")
        XCTAssertEqual(event.metadata["addCount"], "1")
        XCTAssertEqual(event.metadata["changeCount"], "1")
        XCTAssertEqual(event.metadata["cancelCount"], "1")
        XCTAssertEqual(event.metadata["confirmedSourceRevision"], plan.confirmedRevision.label)
        XCTAssertEqual(event.metadata["draftSourceRevision"], plan.draftRevision.label)
    }

    func testFeatureProposalMergeKeepsSuccessfulMainWriteWhenAuditFails() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let auditFile = root.appendingPathComponent("audit-file")
        try Data().write(to: auditFile)
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)

        let response = try NativeFeatureStore.merge(
            plan: plan,
            confirmed: true,
            auditRoot: auditFile.path,
            archiveTimestamp: "20260711T120002Z"
        )

        XCTAssertEqual(response.document.features.count, 3)
        XCTAssertNotNil(response.auditError)
    }

    func testFeatureProposalArchiveKeepsDraftChangedAfterSuccessfulMainWrite() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = root.appendingPathComponent("FEATURES.draft.md")
        let externalDraft = featureSource(id: "DRAFT-009", title: "New external proposal", status: "draft")
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)

        let response = try NativeFeatureStore.merge(
            plan: plan,
            confirmed: true,
            archiveTimestamp: "20260711T120003Z",
            beforeArchive: {
                try externalDraft.write(to: draft, atomically: true, encoding: .utf8)
            }
        )

        XCTAssertEqual(response.document.features.map(\.id), ["F-001", "F-002", "F-003"])
        XCTAssertNil(response.archivePath)
        XCTAssertTrue(response.archiveError?.contains("FEATURES.draft.md changed since confirmation") == true)
        XCTAssertEqual(try String(contentsOf: draft, encoding: .utf8), externalDraft)
    }

    func testFeatureProposalArchiveHookFailureSafelyRollsBackOriginalDraft() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = root.appendingPathComponent("FEATURES.draft.md")
        let archive = root.appendingPathComponent("FEATURES.draft.accepted-hook-error.md")
        let original = try Data(contentsOf: draft)
        let originalInode = try inodeNumber(at: draft)
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)

        let response = try NativeFeatureStore.merge(
            plan: plan,
            confirmed: true,
            archiveTimestamp: "hook-error",
            afterArchiveRenameBeforeVerify: { throw PublishFailure.injected }
        )

        XCTAssertNil(response.archivePath)
        XCTAssertNotNil(response.archiveError)
        XCTAssertEqual(try Data(contentsOf: draft), original)
        XCTAssertEqual(try inodeNumber(at: draft), originalInode)
        XCTAssertFalse(FileManager.default.fileExists(atPath: archive.path))
    }

    func testFeatureProposalArchiveExternalReplacementRequiresRecoveryWithoutMovingExternalFile() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let draft = root.appendingPathComponent("FEATURES.draft.md")
        let archive = root.appendingPathComponent("FEATURES.draft.accepted-external-replacement.md")
        let recovery = root.appendingPathComponent("original-draft.recovery.md")
        let original = try Data(contentsOf: draft)
        let external = featureSource(id: "DRAFT-999", title: "External replacement", status: "draft")
        let plan = try NativeFeatureStore.makeMergePlan(workspacePath: root.path)

        let response = try NativeFeatureStore.merge(
            plan: plan,
            confirmed: true,
            archiveTimestamp: "external-replacement",
            afterArchiveRenameBeforeVerify: {
                try FileManager.default.moveItem(at: archive, to: recovery)
                try external.write(to: archive, atomically: true, encoding: .utf8)
            }
        )

        XCTAssertNil(response.archivePath)
        XCTAssertTrue(response.archiveError?.contains("archive recovery required") == true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.path))
        XCTAssertEqual(try String(contentsOf: archive, encoding: .utf8), external)
        XCTAssertEqual(try Data(contentsOf: recovery), original)
    }

    func testFeatureProposalLoadRejectsDirectoryDraftWithoutChangingFacts() throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let facts = root.appendingPathComponent("FEATURES.md")
        let draft = root.appendingPathComponent("FEATURES.draft.md")
        let originalFacts = try Data(contentsOf: facts)
        try FileManager.default.removeItem(at: draft)
        try FileManager.default.createDirectory(at: draft, withIntermediateDirectories: false)

        XCTAssertThrowsError(try NativeFeatureStore.makeMergePlan(workspacePath: root.path)) {
            XCTAssertTrue($0.localizedDescription.contains("not a regular file"))
        }
        XCTAssertEqual(try Data(contentsOf: facts), originalFacts)
    }

    func testFeatureProposalMissingOrMalformedDraftReturnsExactErrorAndPreservesFacts() throws {
        for source in [nil, featureSource(id: "DRAFT-001", title: "First") + "\n" + featureSource(id: "DRAFT-001", title: "Second")] {
            let root = try temporaryDemandWorkspace()
            defer { try? FileManager.default.removeItem(at: root) }
            let facts = root.appendingPathComponent("FEATURES.md")
            let original = featureSource(id: "F-001", title: "Confirmed")
            try original.write(to: facts, atomically: true, encoding: .utf8)
            if let source {
                try source.write(
                    to: root.appendingPathComponent("FEATURES.draft.md"), atomically: true, encoding: .utf8
                )
            }

            let review = NativeFeatureStore.inspectProposal(workspacePath: root.path)

            XCTAssertFalse(review.canConfirm)
            if source == nil {
                XCTAssertEqual(review.error, "feature proposal draft is missing: \(root.path)/FEATURES.draft.md")
            } else {
                XCTAssertEqual(review.error, "duplicate feature ID: DRAFT-001")
            }
            XCTAssertEqual(try String(contentsOf: facts, encoding: .utf8), original)
        }
    }

    @MainActor
    func testFeatureProposalAppStateBindsPendingMergeToWorkspaceAndConsumesOnce() async throws {
        let rootA = try featureProposalWorkspace()
        let rootB = try featureProposalWorkspace()
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let workspaceA = demandInputWorkspace(id: "proposal-a", path: rootA.path)
        let workspaceB = demandInputWorkspace(id: "proposal-b", path: rootB.path)
        let appState = makeAppState(workspaces: [workspaceA, workspaceB], root: rootA)

        await appState.refreshFeatureProposal(for: workspaceA)
        XCTAssertTrue(appState.featureProposalReview(for: workspaceA)?.canConfirm == true)
        await appState.requestFeatureProposalMerge(in: workspaceA).value
        XCTAssertNotNil(appState.pendingFeatureProposalMerge(for: workspaceA))
        XCTAssertNil(appState.pendingFeatureProposalMerge(for: workspaceB))
        XCTAssertNotNil(appState.takePendingFeatureProposalMerge())
        XCTAssertNil(appState.takePendingFeatureProposalMerge())

        await appState.requestFeatureProposalMerge(in: workspaceA).value
        appState.selectedWorkspaceID = workspaceB.id
        XCTAssertNil(appState.pendingFeatureProposalMerge(for: workspaceA))
    }

    @MainActor
    func testFeatureProposalAppStateCapturesSelectionAndInlineReplacement() async throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        await appState.refreshFeatureProposal(for: workspace)
        let item = try XCTUnwrap(
            appState.featureProposalReview(for: workspace)?.diff?.items.first(where: { $0.id == "F-001" })
        )
        var replacement = try XCTUnwrap(item.proposed)
        replacement.title = "Inline edit"
        appState.updateFeatureProposalItem(
            itemID: item.id,
            selected: true,
            replacement: replacement,
            in: workspace
        )
        appState.updateFeatureProposalItem(
            itemID: "F-002",
            selected: false,
            replacement: nil,
            in: workspace
        )

        await appState.requestFeatureProposalMerge(in: workspace).value
        let plan = try XCTUnwrap(appState.pendingFeatureProposalMerge(for: workspace))

        XCTAssertEqual(plan.selectedItemIDs, ["F-001", "DRAFT-001"])
        XCTAssertEqual(plan.replacements["F-001"]?.title, "Inline edit")
        XCTAssertEqual(plan.confirmedRevision, appState.featureProposalReview(for: workspace)?.confirmedRevision)
        XCTAssertEqual(plan.draftRevision, appState.featureProposalReview(for: workspace)?.draftRevision)
    }

    @MainActor
    func testFeatureProposalRequestRejectsChangedReviewedRevisionAndRefreshesReview() async throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        await appState.refreshFeatureProposal(for: workspace)
        let reviewedRevision = try XCTUnwrap(appState.featureProposalReview(for: workspace)?.draftRevision)
        let reviewedItem = try XCTUnwrap(
            appState.featureProposalReview(for: workspace)?.diff?.items.first { $0.id == "F-001" }
        )
        var edited = try XCTUnwrap(reviewedItem.proposed)
        edited.title = "User edit for reviewed A"
        appState.updateFeatureProposalItem(
            itemID: reviewedItem.id,
            selected: true,
            replacement: edited,
            in: workspace
        )
        try (
            featureSource(id: "F-001", title: "Changed proposal B")
                + "\n" + featureSource(id: "DRAFT-001", title: "Added", status: "draft")
        ).write(
            to: root.appendingPathComponent("FEATURES.draft.md"), atomically: true, encoding: .utf8
        )

        await appState.requestFeatureProposalMerge(in: workspace).value

        XCTAssertNil(appState.pendingFeatureProposalMerge(for: workspace))
        XCTAssertNotEqual(appState.featureProposalReview(for: workspace)?.draftRevision, reviewedRevision)
        XCTAssertEqual(
            appState.featureProposalReview(for: workspace)?.diff?.items.first { $0.id == "F-001" }?.proposed?.title,
            "Changed proposal B"
        )
        XCTAssertTrue(appState.lastError?.contains("changed since confirmation") == true)
    }

    @MainActor
    func testFeatureProposalOlderRefreshCannotOverwriteNewerWorkspaceReview() async throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        let oldInspectFinished = expectation(description: "old inspect finished")
        let releaseOldRefresh = DispatchSemaphore(value: 0)
        let oldRefresh = Task {
            await appState.refreshFeatureProposal(for: workspace, afterInspect: {
                oldInspectFinished.fulfill()
                releaseOldRefresh.wait()
            })
        }
        await fulfillment(of: [oldInspectFinished], timeout: 2)
        try (
            featureSource(id: "F-001", title: "Newest proposal")
                + "\n" + featureSource(id: "DRAFT-001", title: "Added", status: "draft")
        ).write(
            to: root.appendingPathComponent("FEATURES.draft.md"), atomically: true, encoding: .utf8
        )

        await appState.refreshFeatureProposal(for: workspace)
        releaseOldRefresh.signal()
        await oldRefresh.value

        XCTAssertEqual(
            appState.featureProposalReview(for: workspace)?.diff?.items.first { $0.id == "F-001" }?.proposed?.title,
            "Newest proposal"
        )
    }

    @MainActor
    func testFeatureProposalConfirmationTakeAndCancellationAreSynchronousAndIdempotent() async throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        await appState.refreshFeatureProposal(for: workspace)
        await appState.requestFeatureProposalMerge(in: workspace).value

        XCTAssertNotNil(appState.takePendingFeatureProposalMerge())
        appState.cancelPendingFeatureProposalMerge()
        XCTAssertEqual(
            appState.featureProposalMergeWorkspaceID,
            workspace.id,
            "dismissal after confirm must not clear merge busy"
        )
        appState.cancelPendingFeatureProposalMerge()
        XCTAssertEqual(appState.featureProposalMergeWorkspaceID, workspace.id)

        await appState.requestFeatureProposalMerge(in: workspace).value
        appState.cancelPendingFeatureProposalMerge()
        XCTAssertNil(appState.pendingFeatureProposalMerge)
        XCTAssertNil(appState.featureProposalMergeWorkspaceID)
        appState.cancelPendingFeatureProposalMerge()
        XCTAssertNil(appState.featureProposalMergeWorkspaceID)
    }

    @MainActor
    func testFeatureProposalConfirmThenDialogDismissalCannotCancelInFlightWrite() async throws {
        let root = try featureProposalWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        await appState.refreshFeatureProposal(for: workspace)
        await appState.requestFeatureProposalMerge(in: workspace).value
        let operation = try XCTUnwrap(appState.takePendingFeatureProposalMerge())
        let writeStarted = expectation(description: "proposal write started")
        let releaseWrite = DispatchSemaphore(value: 0)
        let write = Task {
            await appState.writeConfirmedFeatureProposal(operation, beforeWrite: {
                writeStarted.fulfill()
                releaseWrite.wait()
            })
        }
        await fulfillment(of: [writeStarted], timeout: 2)

        appState.cancelPendingFeatureProposalMerge()
        XCTAssertEqual(appState.featureProposalMergeWorkspaceID, workspace.id)
        releaseWrite.signal()
        await write.value

        XCTAssertNil(appState.featureProposalMergeWorkspaceID)
        XCTAssertEqual(appState.featuresByWorkspace[workspace.id]?.features.map(\.id), ["F-001", "F-002", "F-003"])
    }

    @MainActor
    func testOldFeatureProposalWriteCannotClearNewWorkspacePendingMerge() async throws {
        let rootA = try featureProposalWorkspace()
        let rootB = try featureProposalWorkspace()
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let workspaceA = demandInputWorkspace(id: "proposal-a", path: rootA.path)
        let workspaceB = demandInputWorkspace(id: "proposal-b", path: rootB.path)
        let appState = makeAppState(workspaces: [workspaceA, workspaceB], root: rootA)
        await appState.refreshFeatureProposal(for: workspaceA)
        await appState.requestFeatureProposalMerge(in: workspaceA).value
        let operationA = try XCTUnwrap(appState.takePendingFeatureProposalMerge())
        let writeStarted = expectation(description: "old proposal write started")
        let releaseWrite = DispatchSemaphore(value: 0)
        let writeA = Task {
            await appState.writeConfirmedFeatureProposal(operationA, beforeWrite: {
                writeStarted.fulfill()
                releaseWrite.wait()
            })
        }
        await fulfillment(of: [writeStarted], timeout: 2)

        appState.selectedWorkspaceID = workspaceB.id
        await appState.refreshFeatureProposal(for: workspaceB)
        await appState.requestFeatureProposalMerge(in: workspaceB).value
        let pendingB = try XCTUnwrap(appState.pendingFeatureProposalMerge(for: workspaceB))
        releaseWrite.signal()
        await writeA.value

        XCTAssertEqual(appState.featureProposalMergeWorkspaceID, workspaceB.id)
        XCTAssertEqual(appState.pendingFeatureProposalMerge(for: workspaceB), pendingB)
        XCTAssertNil(appState.lastError)
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

    func testFeatureTaskAttributionWarnsForMarkerLikeSpacing() {
        for detail in ["feature =F-001", "feature = F-001", "feature= F-001"] {
            let attribution = NativeWorkspaceTaskParser.featureAttribution(in: detail)
            XCTAssertNil(attribution.id, detail)
            XCTAssertNotNil(attribution.warning, detail)
        }
        XCTAssertEqual(NativeWorkspaceTaskParser.featureAttribution(in: "feature=F-001").id, "F-001")
        let capitalized = NativeWorkspaceTaskParser.featureAttribution(in: "Feature=F-001")
        XCTAssertNil(capitalized.id)
        XCTAssertNotNil(capitalized.warning)
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

        appState.cancelPendingFeatureWrite()
        XCTAssertNil(appState.pendingFeatureWrite)
        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), original)

        appState.requestFeatureWrite(
            .setStatus(id: "F-001", status: .done, completionNote: "manual"),
            in: workspace
        )
        for _ in 0..<100 where appState.pendingFeatureWrite == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        if let operation = appState.takePendingFeatureWrite() {
            await appState.writeConfirmedFeature(operation)
        }

        XCTAssertEqual(appState.featuresByWorkspace[workspace.id]?.features.first?.status, .done)
        XCTAssertNil(appState.pendingFeatureWrite)
    }

    @MainActor
    func testFeaturePendingConfirmationIsBoundToCurrentWorkspace() async throws {
        let rootA = try temporaryDemandWorkspace()
        let rootB = try temporaryDemandWorkspace()
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let source = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        try source.write(to: rootA.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8)
        try source.write(to: rootB.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8)
        let workspaceA = demandInputWorkspace(id: "workspace-a", path: rootA.path)
        let workspaceB = demandInputWorkspace(id: "workspace-b", path: rootB.path)
        let appState = makeAppState(workspaces: [workspaceA, workspaceB], root: rootA)

        appState.requestFeatureWrite(
            .setStatus(id: "F-001", status: .done, completionNote: "A"),
            in: workspaceA
        )
        for _ in 0..<100 where appState.pendingFeatureWrite == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTAssertNotNil(appState.pendingFeatureWrite(for: workspaceA))
        XCTAssertNil(appState.pendingFeatureWrite(for: workspaceB))

        appState.selectedWorkspaceID = workspaceB.id

        XCTAssertNil(appState.pendingFeatureWrite)
        if let operation = appState.takePendingFeatureWrite() {
            await appState.writeConfirmedFeature(operation)
        }
        XCTAssertEqual(try String(contentsOf: rootA.appendingPathComponent("FEATURES.md"), encoding: .utf8), source)
        XCTAssertEqual(try String(contentsOf: rootB.appendingPathComponent("FEATURES.md"), encoding: .utf8), source)
    }

    @MainActor
    func testFeaturePlanningWorkspaceSwitchClearsBusyAndIgnoresOldPlan() async throws {
        let rootA = try temporaryDemandWorkspace()
        let rootB = try temporaryDemandWorkspace()
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let source = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        try source.write(to: rootA.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8)
        let workspaceA = demandInputWorkspace(id: "workspace-a", path: rootA.path)
        let workspaceB = demandInputWorkspace(id: "workspace-b", path: rootB.path)
        let appState = makeAppState(workspaces: [workspaceA, workspaceB], root: rootA)
        let planningStarted = expectation(description: "planning started")
        let releasePlanning = DispatchSemaphore(value: 0)

        let planningTask = appState.requestFeatureWrite(
            .setStatus(id: "F-001", status: .done, completionNote: "A"),
            in: workspaceA,
            beforePlan: {
                planningStarted.fulfill()
                releasePlanning.wait()
            }
        )
        await fulfillment(of: [planningStarted], timeout: 2)
        XCTAssertEqual(appState.featureWriteWorkspaceID, workspaceA.id)

        appState.selectedWorkspaceID = workspaceB.id
        XCTAssertNil(appState.featureWriteWorkspaceID)
        releasePlanning.signal()
        await planningTask.value

        XCTAssertNil(appState.pendingFeatureWrite)
        XCTAssertNil(appState.featureWriteWorkspaceID)
    }

    @MainActor
    func testFeatureConfirmationTakeAndCancellationAreSynchronousAndIdempotent() async throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let feature = WorkspaceFeature(
            id: "F-001", title: "Snapshot", status: .todo, verification: .code,
            autoComplete: true, sources: [], services: [], taskIDs: [], evidenceIDs: [],
            description: "", completedAt: nil, completedBy: nil, completionNote: nil,
            evidenceStale: false, preservedLines: []
        )
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)

        await appState.requestFeatureWrite(.add(feature), in: workspace).value
        XCTAssertEqual(appState.takePendingFeatureWrite()?.plan.mutation, .add(feature))
        appState.cancelPendingFeatureWrite()
        XCTAssertEqual(appState.featureWriteWorkspaceID, workspace.id, "dismissal after confirm must not clear write busy")

        await appState.requestFeatureWrite(.add(feature), in: workspace).value
        appState.cancelPendingFeatureWrite()
        XCTAssertNil(appState.pendingFeatureWrite)
        XCTAssertNil(appState.featureWriteWorkspaceID)
        appState.cancelPendingFeatureWrite()
        XCTAssertNil(appState.featureWriteWorkspaceID)
    }

    @MainActor
    func testOldSuccessfulFeatureWriteCannotClearNewWorkspacePendingWrite() async throws {
        try await assertOldFeatureWriteCannotClearNewWorkspacePendingWrite(failOldWrite: false)
    }

    @MainActor
    func testOldFailedFeatureWriteCannotClearNewWorkspacePendingWriteOrSetError() async throws {
        try await assertOldFeatureWriteCannotClearNewWorkspacePendingWrite(failOldWrite: true)
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
            applicationSupportRoot: root.appendingPathComponent("application-support").path,
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
        XCTAssertLessThanOrEqual(prompt.utf8.count, 6_144)
        XCTAssertTrue(prompt.contains("<!-- generated-by: Nexus Native -->"))
        XCTAssertEqual(
            prompt,
            try String(contentsOf: root.appendingPathComponent("handoff.md"), encoding: .utf8)
        )
        XCTAssertFalse(prompt.contains("FULL DELIVERY BODY"))
    }

    @MainActor
    func testFeatureIntakePromptRebuildsOnceWhenHandoffSourceTurnsStale() async throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        appState.selectedWorkspaceID = workspace.id
        let secondAttempt = expectation(description: "handoff rebuilt after stale source")

        let prompt = await appState.featureIntakePrompt(
            for: workspace,
            beforeHandoffWrite: { attempt in
                if attempt == 0 {
                    try? "# Tasks\n\nexternal source update\n".write(
                        to: root.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8
                    )
                } else {
                    secondAttempt.fulfill()
                }
            }
        )

        await fulfillment(of: [secondAttempt], timeout: 1)
        XCTAssertFalse(prompt.isEmpty)
        XCTAssertEqual(prompt, try String(contentsOf: root.appendingPathComponent("handoff.md"), encoding: .utf8))
        XCTAssertNil(appState.lastError)
    }

    @MainActor
    func testFeatureIntakePromptRebuildsFeatureFactsAfterPrePlanStale() async throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try featureSource(id: "F-001", title: "Old feature fact").write(
            to: root.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8
        )
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        appState.selectedWorkspaceID = workspace.id

        let prompt = await appState.featureIntakePrompt(
            for: workspace,
            beforeHandoffWrite: { attempt in
            if attempt == 0 {
                try? self.featureSource(id: "F-001", title: "Fresh feature fact").write(
                    to: root.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8
                )
            }
            }
        )

        XCTAssertTrue(prompt.contains("Fresh feature fact"))
        XCTAssertFalse(prompt.contains("Old feature fact"))
        let snapshot = try NativeSessionChangeStore.contextSourceSnapshot(
            workspacePath: root.path,
            workspaceFolder: workspace.folder
        )
        XCTAssertTrue(prompt.contains("FEATURES.md=\(snapshot.sourceRevisions["FEATURES.md"]!.token)"))
    }

    @MainActor
    func testFeatureIntakePromptRebuildsChangeEntriesAfterPrePlanStale() async throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        appState.selectedWorkspaceID = workspace.id

        let prompt = await appState.featureIntakePrompt(
            for: workspace,
            beforeHandoffWrite: { attempt in
            if attempt == 0 {
                try? "# Changes\n\n## newest\n- Fresh change fact\n".write(
                    to: root.appendingPathComponent("changes.md"), atomically: true, encoding: .utf8
                )
            }
            }
        )

        XCTAssertTrue(prompt.contains("Fresh change fact"))
        let snapshot = try NativeSessionChangeStore.contextSourceSnapshot(
            workspacePath: root.path,
            workspaceFolder: workspace.folder
        )
        XCTAssertTrue(prompt.contains("changes.md=\(snapshot.sourceRevisions["changes.md"]!.token)"))
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

    func testSessionChangeReviewPolicyRequiresPreviewConfirmationAndIdleWriter() {
        XCTAssertFalse(FeatureWorkspaceSessionChangePolicy.canWrite(hasDraft: false, confirmed: true, isBusy: false))
        XCTAssertFalse(FeatureWorkspaceSessionChangePolicy.canWrite(hasDraft: true, confirmed: false, isBusy: false))
        XCTAssertFalse(FeatureWorkspaceSessionChangePolicy.canWrite(hasDraft: true, confirmed: true, isBusy: true))
        XCTAssertTrue(FeatureWorkspaceSessionChangePolicy.canWrite(hasDraft: true, confirmed: true, isBusy: false))
    }

    func testContextPackFitsUnicodeBudgetWithoutSplittingLines() {
        var input = contextPackInput()
        input.confirmedChanges = (1...8).map { index in
            "## 2026-07-\(String(format: "%02d", index))\n- 变化 \(index) 中文 emoji 🚀 "
                + String(repeating: "内容", count: 240)
        }

        let pack = NativeContextPackBuilder.build(input: input, maximumUTF8Bytes: 6_144)

        XCTAssertEqual(pack.status, .ready)
        XCTAssertLessThanOrEqual(pack.markdown.utf8.count, 6_144)
        XCTAssertTrue(pack.markdown.contains("F-003"))
        XCTAssertTrue(pack.markdown.contains("按需读取"))
        XCTAssertFalse(pack.markdown.contains("FULL DELIVERY BODY"))
        XCTAssertEqual(String(data: Data(pack.markdown.utf8), encoding: .utf8), pack.markdown)
        XCTAssertTrue(pack.markdown.hasSuffix("\n"))
    }

    func testContextPackRetainsSelectedFeatureAndOmitsOldestChangesFirst() {
        var input = contextPackInput()
        input.confirmedChanges = [
            "## newest\n- newest change",
            "## middle\n- middle change",
            "## oldest\n- oldest change " + String(repeating: "old ", count: 600)
        ]

        let pack = NativeContextPackBuilder.build(input: input, maximumUTF8Bytes: 1_700)

        XCTAssertEqual(pack.status, .ready)
        XCTAssertTrue(pack.markdown.contains("F-003"))
        XCTAssertTrue(pack.markdown.contains("T-003"))
        XCTAssertTrue(pack.markdown.contains("newest change"))
        XCTAssertFalse(pack.markdown.contains("oldest change"))
        XCTAssertTrue(pack.omittedSections.contains("confirmed-change:oldest"))
    }

    func testContextPackReportsRequiredOverflowWithoutProducingOversizeText() {
        var input = contextPackInput()
        input.selectedFeature = NativeContextFeature(
            id: "F-003",
            title: String(repeating: "必须保留", count: 300),
            status: "blocked",
            detail: "required"
        )

        let pack = NativeContextPackBuilder.build(input: input, maximumUTF8Bytes: 256)

        guard case .overflow = pack.status else { return XCTFail("expected overflow") }
        XCTAssertLessThanOrEqual(pack.markdown.utf8.count, 256)
        XCTAssertTrue(pack.markdown.isEmpty)
        XCTAssertTrue(pack.omittedSections.contains("required-content-overflow"))
    }

    func testContextPackNeverDropsServiceGitOrLatestCheckToFitBudget() {
        var input = contextPackInput()
        input.services = [
            NativeContextService(
                name: "order-service",
                branch: "feature/order",
                gitSummary: String(repeating: "required-git-fact ", count: 35)
            )
        ]
        input.latestRelevantCheck = String(repeating: "required-check-fact ", count: 35)
        input.confirmedChanges = ["## old\n- " + String(repeating: "optional change ", count: 80)]
        input.evidence = input.evidence.map {
            NativeContextEvidence(path: $0.path, summary: String(repeating: "optional summary ", count: 30))
        }

        let pack = NativeContextPackBuilder.build(input: input, maximumUTF8Bytes: 1_100)

        guard case .overflow = pack.status else { return XCTFail("required service/check facts must overflow") }
        XCTAssertTrue(pack.markdown.isEmpty)
        XCTAssertFalse(pack.omittedSections.contains("latest-relevant-check"))
        XCTAssertFalse(pack.omittedSections.contains("service-branch-git"))
    }

    func testHandoffWriteRejectsStaleSourceRevisionAndPreservesProjection() throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = "external handoff\n"
        try original.write(to: root.appendingPathComponent("handoff.md"), atomically: true, encoding: .utf8)
        let source = try NativeSessionChangeStore.contextSourceSnapshot(
            workspacePath: root.path,
            workspaceFolder: "workspace"
        )
        var input = contextPackInput(workspacePath: root.path)
        input.sourceRevisions = source.sourceRevisions.mapValues(\.token)
        let plan = try NativeSessionChangeStore.makeHandoffPlan(
            workspacePath: root.path,
            input: input,
            expectedSourceRevisions: source.sourceRevisions
        )
        try "# Tasks\n\nexternal\n".write(
            to: root.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8
        )

        XCTAssertThrowsError(try NativeSessionChangeStore.writeHandoff(plan: plan))
        XCTAssertEqual(try String(contentsOf: root.appendingPathComponent("handoff.md"), encoding: .utf8), original)
    }

    func testHandoffWriteIncludesGeneratedMetadataAndExactSourceRevisions() throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try NativeSessionChangeStore.contextSourceSnapshot(
            workspacePath: root.path,
            workspaceFolder: "workspace"
        )
        var input = contextPackInput(workspacePath: root.path)
        input.sourceRevisions = source.sourceRevisions.mapValues(\.token)
        let plan = try NativeSessionChangeStore.makeHandoffPlan(
            workspacePath: root.path,
            input: input,
            expectedSourceRevisions: source.sourceRevisions
        )

        let response = try NativeSessionChangeStore.writeHandoff(plan: plan)
        let written = try String(contentsOfFile: response.path, encoding: .utf8)

        XCTAssertTrue(written.contains("<!-- generated-by: Nexus Native -->"))
        XCTAssertTrue(written.contains("<!-- selected-feature: F-003 -->"))
        XCTAssertTrue(written.contains("FEATURES.md="))
        XCTAssertTrue(written.contains("tasks.md="))
        XCTAssertTrue(written.contains("changes.md="))
        XCTAssertEqual(response.pack.markdown.utf8.count <= 6_144, true)
    }

    func testSessionChangeBaselineCodableAndMissingBaselineCannotClaimPriorDiff() throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let baseline = SessionChangeBaseline(
            sessionID: "session-1",
            workspacePath: root.path,
            startedAt: "2026-07-11T01:02:03Z",
            repositoryHeads: ["order-service": "abc123"],
            featureRevision: "feature-rev",
            taskRevision: "task-rev"
        )
        XCTAssertEqual(try JSONDecoder().decode(SessionChangeBaseline.self, from: JSONEncoder().encode(baseline)), baseline)

        let result = try NativeSessionChangeStore.loadOrCreateBaseline(
            workspacePath: root.path,
            current: baseline
        )

        XCTAssertFalse(result.canClaimPriorDiff)
        XCTAssertTrue(result.notice.contains("不能声称此前差异"))
        XCTAssertEqual(try NativeSessionChangeStore.loadBaseline(workspacePath: root.path), baseline)
    }

    func testSessionDraftFactsAndRevisionsComeFromTheSameSourceSnapshot() throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try featureSource(id: "F-001", title: "Snapshot feature").write(
            to: root.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8
        )
        try "| 任务 | 状态 | 详情 |\n| --- | --- | --- |\n| Old task | todo | feature=F-001 |\n".write(
            to: root.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8
        )
        let source = try NativeSessionChangeStore.contextSourceSnapshot(
            workspacePath: root.path,
            workspaceFolder: "workspace"
        )
        try "| 任务 | 状态 | 详情 |\n| --- | --- | --- |\n| Fresh task | todo | feature=F-001 |\n".write(
            to: root.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8
        )
        let baseline = SessionChangeBaseline(
            sessionID: "session-source",
            workspacePath: root.path,
            startedAt: "2026-07-11T01:02:03Z",
            repositoryHeads: [:],
            featureRevision: source.sourceRevisions["FEATURES.md"]?.token,
            taskRevision: source.sourceRevisions["tasks.md"]?.token
        )
        let input = SessionChangeDraftInput(
            workspacePath: root.path,
            baseline: baseline,
            currentRepositoryHeads: [:],
            repositoryDiffs: [:],
            featureRevision: source.sourceRevisions["FEATURES.md"]?.token,
            taskRevision: source.sourceRevisions["tasks.md"]?.token,
            latestTest: nil,
            sqlAndDeliveryRevisions: [:],
            codexSummary: nil,
            featureAndTaskFacts: source.featureDocument.features.map(\.title)
                + source.tasks.map(\.title)
        )

        XCTAssertThrowsError(
            try NativeSessionChangeStore.writeDraft(
                input: input,
                expectedSourceRevisions: source.sourceRevisions
            )
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("changes.draft.md").path))
    }

    func testSessionChangeAppendRejectsChangedChangesOrDraftRevision() throws {
        for changedName in ["changes.md", "changes.draft.md"] {
            let fixture = try sessionChangeDraftFixture()
            defer { try? FileManager.default.removeItem(at: fixture.root) }
            let plan = try NativeSessionChangeStore.makeWritePlan(draft: fixture.draft)
            let changesBefore = try Data(contentsOf: fixture.root.appendingPathComponent("changes.md"))
            try Data("external \(changedName)\n".utf8).write(
                to: fixture.root.appendingPathComponent(changedName), options: .atomic
            )

            XCTAssertThrowsError(try NativeSessionChangeStore.append(plan: plan, confirmed: true))
            if changedName == "changes.draft.md" {
                XCTAssertEqual(try Data(contentsOf: fixture.root.appendingPathComponent("changes.md")), changesBefore)
            }
        }
    }

    func testSessionChangeAppendRejectsSymlinkDirectoryAndInvalidUTF8WithoutMutation() throws {
        for unsafeName in ["changes.md", "changes.draft.md"] {
            for kind in ["symlink", "directory", "invalid-utf8"] {
                let fixture = try sessionChangeDraftFixture()
                let target = fixture.root.appendingPathComponent(unsafeName)
                try FileManager.default.removeItem(at: target)
                if kind == "symlink" {
                    let external = fixture.root.appendingPathComponent("external")
                    try Data("external".utf8).write(to: external)
                    try FileManager.default.createSymbolicLink(at: target, withDestinationURL: external)
                } else if kind == "directory" {
                    try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
                } else {
                    try Data([0xFF, 0xFE]).write(to: target)
                }
                let untouched = unsafeName == "changes.md"
                    ? nil
                    : try Data(contentsOf: fixture.root.appendingPathComponent("changes.md"))

                XCTAssertThrowsError(try NativeSessionChangeStore.makeWritePlan(draft: fixture.draft), "\(unsafeName) \(kind)")
                if let untouched {
                    XCTAssertEqual(try Data(contentsOf: fixture.root.appendingPathComponent("changes.md")), untouched)
                }
                try? FileManager.default.removeItem(at: fixture.root)
            }
        }
    }

    func testSessionChangeAppendRejectsFinalCheckRaceAndPreservesUnknownProse() throws {
        let fixture = try sessionChangeDraftFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try NativeSessionChangeStore.makeWritePlan(draft: fixture.draft)
        let changesURL = fixture.root.appendingPathComponent("changes.md")
        let external = "# Changes\n\n人工未知说明。\n\nexternal race\n"

        XCTAssertThrowsError(
            try NativeSessionChangeStore.append(
                plan: plan,
                confirmed: true,
                beforeFinalRevisionCheck: {
                    try external.write(to: changesURL, atomically: true, encoding: .utf8)
                }
            )
        )
        XCTAssertEqual(try String(contentsOf: changesURL, encoding: .utf8), external)
    }

    func testSessionChangeConfirmedAppendPreservesUnknownProseAndSeparatesAuditFailure() throws {
        let fixture = try sessionChangeDraftFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let plan = try NativeSessionChangeStore.makeWritePlan(draft: fixture.draft)
        let auditFile = fixture.root.appendingPathComponent("audit-blocker")
        try Data("not a directory".utf8).write(to: auditFile)

        let response = try NativeSessionChangeStore.append(
            plan: plan,
            confirmed: true,
            timestamp: "2026-07-11T02:03:04Z",
            auditRoot: auditFile.path
        )
        let changes = try String(contentsOfFile: response.path, encoding: .utf8)

        XCTAssertTrue(changes.contains("人工未知说明。"))
        XCTAssertTrue(changes.contains("## 2026-07-11T02:03:04Z"))
        XCTAssertTrue(changes.contains("head abc123 -> def456"))
        XCTAssertNotNil(response.auditError)
        XCTAssertNotNil(response.archivedDraftPath)
    }

    @MainActor
    func testSessionChangePendingPlanIsWorkspaceBoundAndConsumedOnceAcrossDismissal() throws {
        let rootA = try sessionChangeWorkspace()
        let rootB = try sessionChangeWorkspace()
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let workspaceA = demandInputWorkspace(id: "workspace-a", path: rootA.path)
        let workspaceB = demandInputWorkspace(id: "workspace-b", path: rootB.path)
        let appState = makeAppState(workspaces: [workspaceA, workspaceB], root: rootA)
        appState.selectedWorkspaceID = workspaceA.id
        let planA = try NativeSessionChangeStore.makeWritePlan(draft: try writeSessionChangeDraft(at: rootA))
        appState.requestSessionChangeWrite(planA, in: workspaceA)

        let operation = try XCTUnwrap(appState.takePendingSessionChangeWrite())
        appState.cancelPendingSessionChangeWrite()
        XCTAssertNil(appState.takePendingSessionChangeWrite())
        XCTAssertEqual(operation.plan.workspacePath, rootA.path)

        let planB = try NativeSessionChangeStore.makeWritePlan(draft: try writeSessionChangeDraft(at: rootB))
        appState.requestSessionChangeWrite(planB, in: workspaceB)
        XCTAssertNil(appState.pendingSessionChangeWrite(for: workspaceB))
        appState.selectedWorkspaceID = workspaceB.id
        appState.requestSessionChangeWrite(planB, in: workspaceB)
        XCTAssertNotNil(appState.pendingSessionChangeWrite(for: workspaceB))
        appState.selectedWorkspaceID = workspaceA.id
        XCTAssertNil(appState.pendingSessionChangeWrite(for: workspaceB))
    }

    @MainActor
    func testAppStateGeneratesSessionChangeDraftAndExplainsMissingBaseline() async throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        appState.selectedWorkspaceID = workspace.id

        let draft = await appState.generateSessionChangeDraft(
            in: workspace,
            codexSummary: "Codex summary"
        )

        let generated = try XCTUnwrap(draft)
        XCTAssertFalse(generated.canClaimPriorDiff)
        XCTAssertTrue(generated.notice.contains("不能声称此前差异"))
        XCTAssertEqual(appState.sessionChangeDraftsByWorkspace[workspace.id], generated)
        XCTAssertEqual(appState.sessionChangeNotice(for: workspace), generated.notice)
        XCTAssertTrue(generated.markdown.contains("order-service"))
        XCTAssertTrue(generated.markdown.contains("Codex summary"))
        XCTAssertNotNil(try NativeSessionChangeStore.loadBaseline(workspacePath: root.path))
    }

    @MainActor
    func testAppStateConfirmsRevisionBoundSessionChangeAndClearsArchivedPreview() async throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = demandInputWorkspace(path: root.path)
        let appState = makeAppState(workspace: workspace, root: root)
        appState.selectedWorkspaceID = workspace.id
        let generated = await appState.generateSessionChangeDraft(in: workspace)
        let draft = try XCTUnwrap(generated)

        await appState.prepareSessionChangeWrite(draft, in: workspace)
        let operation = try XCTUnwrap(appState.takePendingSessionChangeWrite())
        await appState.writeConfirmedSessionChange(operation)

        let changes = try String(contentsOf: root.appendingPathComponent("changes.md"), encoding: .utf8)
        XCTAssertTrue(changes.contains("Session change confirmed"))
        XCTAssertNil(appState.sessionChangeDraftsByWorkspace[workspace.id])
        XCTAssertNil(appState.sessionChangeWriteWorkspaceID)
        XCTAssertNil(appState.lastError)
    }

    func testConsoleLayoutKeepsOnePrimaryActionAndFilesCollapsed() {
        let summary = WorkspaceConsoleLayoutPolicy().auditSummary

        XCTAssertEqual(summary.stageGroups, [.created, .demandAndFeatures, .development, .delivery, .archive])
        XCTAssertEqual(summary.prominentPrimaryActionCount, 1)
        XCTAssertTrue(summary.filesAreCollapsed)
        XCTAssertTrue(summary.currentSignalsAreSecondary)
    }

    func testCodeFeatureAutoCompletesOnlyWithFreshExplicitEvidence() {
        let changedAt = Date(timeIntervalSince1970: 100)
        var evidence = featureEvidence(
            relatedChangeIDs: ["commit-1"],
            latestRelatedChangeAt: changedAt,
            requiredTestIDs: ["test-order"],
            latestTestAt: changedAt.addingTimeInterval(1)
        )
        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(
                feature: completionFeature(verification: .code),
                evidence: evidence
            ).decision,
            .autoComplete
        )

        evidence.latestTestAt = changedAt.addingTimeInterval(-1)
        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(
                feature: completionFeature(verification: .code),
                evidence: evidence
            ).decision,
            .keepVerifying
        )
    }

    func testManualFeatureNeverAutoCompletes() {
        let evaluation = FeatureCompletionEvaluator.evaluate(
            feature: completionFeature(verification: .manual),
            evidence: featureEvidence(
                relatedChangeIDs: ["commit-1"],
                latestRelatedChangeAt: Date(timeIntervalSince1970: 100),
                requiredTestIDs: ["test-order"],
                latestTestAt: Date(timeIntervalSince1970: 101),
                formalSQLPaths: ["sql/formal/F-001.sql"],
                rollbackSQLPaths: ["sql/rollback/F-001.sql"],
                documentationPaths: ["docs/F-001.md"]
            )
        )

        XCTAssertEqual(evaluation.decision, .requiresManualCompletion)
    }

    func testSQLAndDocumentationFeaturesRequireTheirExplicitArtifacts() {
        let sqlFeature = completionFeature(verification: .sql)
        let incompleteSQL = FeatureCompletionEvaluator.evaluate(
            feature: sqlFeature,
            evidence: featureEvidence(formalSQLPaths: ["sql/formal/F-001.sql"])
        )
        XCTAssertEqual(incompleteSQL.decision, .keepVerifying)
        let completeSQL = FeatureCompletionEvaluator.evaluate(
            feature: sqlFeature,
            evidence: featureEvidence(
                formalSQLPaths: ["sql/formal/F-001.sql"],
                rollbackSQLPaths: ["sql/rollback/F-001.sql"]
            )
        )
        XCTAssertEqual(completeSQL.decision, .autoComplete)

        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(
                feature: completionFeature(verification: .documentation),
                evidence: featureEvidence()
            ).decision,
            .noChange
        )
        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(
                feature: completionFeature(verification: .documentation),
                evidence: featureEvidence(documentationPaths: ["docs/F-001.md"])
            ).decision,
            .autoComplete
        )
    }

    func testFeatureCompletionBlocksReadErrorsBlockersIncompleteTasksAndMissingAttribution() {
        let feature = completionFeature(verification: .code)
        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(
                feature: feature,
                evidence: featureEvidence(readErrors: ["git failed"])
            ).decision,
            .keepVerifying
        )
        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(
                feature: feature,
                evidence: featureEvidence(blockers: ["risk open"])
            ).decision,
            .keepVerifying
        )
        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(
                feature: feature,
                evidence: featureEvidence(linkedTaskIDs: ["T-1"], incompleteTaskIDs: ["T-1"])
            ).decision,
            .keepVerifying
        )
        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(feature: feature, evidence: featureEvidence()).decision,
            .noChange
        )
    }

    func testDoneFeatureWithNewerRelatedChangeMarksEvidenceStale() {
        var feature = completionFeature(verification: .code)
        feature.status = .done
        feature.completedAt = "1970-01-01T00:01:40Z"
        let evaluation = FeatureCompletionEvaluator.evaluate(
            feature: feature,
            evidence: featureEvidence(
                relatedChangeIDs: ["commit-2"],
                latestRelatedChangeAt: Date(timeIntervalSince1970: 101),
                requiredTestIDs: ["test-order"],
                latestTestAt: Date(timeIntervalSince1970: 100)
            )
        )

        XCTAssertEqual(evaluation.decision, .markEvidenceStale)
    }

    func testFeatureWithoutAutoCompleteAuthorizationAdvancesButDoesNotFinish() {
        var feature = completionFeature(verification: .documentation)
        feature.autoComplete = false
        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(
                feature: feature,
                evidence: featureEvidence(documentationPaths: ["docs/F-001.md"])
            ).decision,
            .startProgress
        )
    }

    func testFeatureEvidenceCollectionUsesOnlyExplicitTasksGitReceiptsAndPaths() throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        var feature = completionFeature(verification: .code)
        feature.sources = ["sql/formal/F-001.sql", "sql/rollback/F-001.sql", "docs/F-001.md"]
        feature.evidenceIDs = ["test_order_snapshot"]
        let receipts = FeatureEvidenceReceiptDocument(
            version: 1,
            receipts: [
                FeatureEvidenceReceipt(
                    id: "test_order_snapshot",
                    kind: .test,
                    featureIDs: ["F-001"],
                    status: .passed,
                    recordedAt: "2026-07-11T02:00:00Z",
                    path: nil
                )
            ]
        )
        try JSONEncoder().encode(receipts).write(to: root.appendingPathComponent("feature-evidence.json"))
        let workspace = featureEvidenceWorkspace(
            root: root,
            tasks: [
                WorkspaceTask(
                    id: "T-1", title: "linked", status: "done", detail: "feature=F-001",
                    priority: "medium", source: "tasks.md", sourceEventID: nil, sourceLine: 2
                ),
                WorkspaceTask(
                    id: "T-2", title: "unrelated", status: "todo", detail: "feature=F-002",
                    priority: "high", source: "tasks.md", sourceEventID: nil, sourceLine: 3
                )
            ],
            riskDetails: ["F-002 unrelated risk"]
        )

        let evidence = NativeFeatureEvidenceStore.collect(
            feature: feature,
            workspace: workspace,
            now: Date(timeIntervalSince1970: 200)
        ) { _, arguments in
            switch arguments.first {
            case "log": return "abc123\t2026-07-11T01:00:00Z\tImplement feature=F-001\nzzz999\t2026-07-11T01:30:00Z\tUnrelated cleanup\n"
            case "status": return ""
            default: throw CocoaError(.fileReadUnknown)
            }
        }

        XCTAssertEqual(evidence.linkedTaskIDs, ["T-1"])
        XCTAssertTrue(evidence.incompleteTaskIDs.isEmpty)
        XCTAssertEqual(evidence.relatedChangeIDs, ["abc123"])
        XCTAssertEqual(evidence.requiredTestIDs, ["test_order_snapshot"])
        XCTAssertTrue(evidence.failedOrMissingTestIDs.isEmpty)
        XCTAssertNotNil(evidence.latestTestAt)
        XCTAssertEqual(evidence.formalSQLPaths, ["sql/formal/F-001.sql"])
        XCTAssertEqual(evidence.rollbackSQLPaths, ["sql/rollback/F-001.sql"])
        XCTAssertEqual(evidence.documentationPaths, ["docs/F-001.md"])
        XCTAssertTrue(evidence.blockers.isEmpty)
        XCTAssertTrue(evidence.readErrors.isEmpty)
    }

    func testFeatureEvidenceCollectionTreatsMalformedReceiptAndGitFailureAsReadErrors() throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("{".utf8).write(to: root.appendingPathComponent("feature-evidence.json"))
        let workspace = featureEvidenceWorkspace(root: root)

        let evidence = NativeFeatureEvidenceStore.collect(
            feature: completionFeature(verification: .code),
            workspace: workspace
        ) { _, _ in
            throw CocoaError(.fileReadUnknown)
        }

        XCTAssertEqual(evidence.readErrors.count, 2)
        XCTAssertTrue(evidence.readErrors.contains { $0.contains("feature-evidence.json") })
        XCTAssertTrue(evidence.readErrors.contains { $0.contains("order-service") })
    }

    func testFeatureEvidenceCollectionTreatsMissingDeclaredDocumentAsReadError() throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        var feature = completionFeature(verification: .documentation)
        feature.services = []
        feature.sources = ["docs/missing-F-001.md"]

        let evidence = NativeFeatureEvidenceStore.collect(
            feature: feature,
            workspace: featureEvidenceWorkspace(root: root)
        )

        XCTAssertEqual(evidence.readErrors, ["declared documentation path is unavailable: docs/missing-F-001.md"])
        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(feature: feature, evidence: evidence).decision,
            .keepVerifying
        )
    }

    func testFeatureEvidenceCollectionAcceptsTestReceiptAttributedByFeatureID() throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let receipt = FeatureEvidenceReceiptDocument(
            version: 1,
            receipts: [
                FeatureEvidenceReceipt(
                    id: "test_direct_attribution",
                    kind: .test,
                    featureIDs: ["F-001"],
                    status: .passed,
                    recordedAt: "2026-07-11T02:00:00Z",
                    path: nil
                )
            ]
        )
        try JSONEncoder().encode(receipt).write(to: root.appendingPathComponent("feature-evidence.json"))
        var feature = completionFeature(verification: .code)
        feature.services = []

        let evidence = NativeFeatureEvidenceStore.collect(
            feature: feature,
            workspace: featureEvidenceWorkspace(root: root)
        )

        XCTAssertEqual(evidence.requiredTestIDs, ["test_direct_attribution"])
        XCTAssertTrue(evidence.failedOrMissingTestIDs.isEmpty)
        XCTAssertNotNil(evidence.latestTestAt)
    }

    func testFeatureEvidenceCollectionRejectsInvalidReceiptTimeAndMissingArtifact() throws {
        let root = try sessionChangeWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let receipt = FeatureEvidenceReceiptDocument(
            version: 1,
            receipts: [
                FeatureEvidenceReceipt(
                    id: "doc_bad",
                    kind: .documentation,
                    featureIDs: ["F-001"],
                    status: .passed,
                    recordedAt: "not-a-date",
                    path: "docs/missing.md"
                )
            ]
        )
        try JSONEncoder().encode(receipt).write(to: root.appendingPathComponent("feature-evidence.json"))
        var feature = completionFeature(verification: .documentation)
        feature.services = []

        let evidence = NativeFeatureEvidenceStore.collect(
            feature: feature,
            workspace: featureEvidenceWorkspace(root: root)
        )

        XCTAssertEqual(evidence.readErrors.count, 2)
        XCTAssertFalse(evidence.documentationPaths.contains("docs/missing.md"))
        XCTAssertEqual(
            FeatureCompletionEvaluator.evaluate(feature: feature, evidence: evidence).decision,
            .keepVerifying
        )
    }

    func testFeatureAutoCompletionBatchWritesExactEvidenceAndAudit() throws {
        let root = try temporaryFeatureWorkspace(
            "## F-001 Snapshot\n- Status: verifying\n- Verification: code\n- Auto complete: true\n- Evidence: test_order_snapshot\n"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let evidence = featureEvidence(
            relatedChangeIDs: ["abc123"],
            latestRelatedChangeAt: Date(timeIntervalSince1970: 100),
            requiredTestIDs: ["test_order_snapshot"],
            latestTestAt: Date(timeIntervalSince1970: 101)
        )
        let feature = try NativeFeatureStore.load(workspacePath: root.path).document.features[0]
        let evaluation = FeatureCompletionEvaluator.evaluate(feature: feature, evidence: evidence)
        let plan = try NativeFeatureStore.makeAutoCompletionPlan(
            workspacePath: root.path,
            evaluations: [evaluation],
            evidenceByFeatureID: [feature.id: evidence]
        )

        let response = try NativeFeatureStore.applyAutoCompletions(
            plan: plan,
            confirmed: true,
            actor: "Nexus Local Check",
            completedAt: "2026-07-11T03:00:00Z",
            auditRoot: root.appendingPathComponent("audit").path
        )

        let written = try XCTUnwrap(response.document.features.first)
        XCTAssertEqual(written.status, .done)
        XCTAssertEqual(written.completedAt, "2026-07-11T03:00:00Z")
        XCTAssertEqual(written.completedBy, "Nexus Local Check")
        XCTAssertTrue(written.completionNote?.contains("abc123") == true)
        XCTAssertEqual(response.transitions.map(\.action), ["feature.auto_completed"])
        XCTAssertTrue(response.auditErrors.isEmpty)
        let event = try XCTUnwrap(
            NativeAuditEventStore.loadRecent(
                auditRoot: root.appendingPathComponent("audit").path,
                limit: 1
            ).first
        )
        XCTAssertEqual(event.action, "feature.auto_completed")
        XCTAssertEqual(event.metadata["policy"], "code")
        XCTAssertTrue(event.metadata["evidenceIDs"]?.contains("abc123") == true)
    }

    func testFeatureAutoCompletionBatchRejectsPassiveOrStaleWriteWithoutMutation() throws {
        for passive in [true, false] {
            let original = "## F-001 Snapshot\n- Status: verifying\n- Verification: documentation\n- Auto complete: true\n"
            let root = try temporaryFeatureWorkspace(original)
            defer { try? FileManager.default.removeItem(at: root) }
            let evidence = featureEvidence(documentationPaths: ["docs/F-001.md"])
            let feature = try NativeFeatureStore.load(workspacePath: root.path).document.features[0]
            let evaluation = FeatureCompletionEvaluator.evaluate(feature: feature, evidence: evidence)
            let plan = try NativeFeatureStore.makeAutoCompletionPlan(
                workspacePath: root.path,
                evaluations: [evaluation],
                evidenceByFeatureID: [feature.id: evidence]
            )
            if !passive {
                try (original + "external edit\n").write(
                    to: root.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8
                )
            }

            XCTAssertThrowsError(
                try NativeFeatureStore.applyAutoCompletions(
                    plan: plan,
                    confirmed: !passive,
                    actor: "Nexus Local Check"
                )
            )
            let current = try String(
                contentsOf: root.appendingPathComponent("FEATURES.md"), encoding: .utf8
            )
            XCTAssertEqual(current, passive ? original : original + "external edit\n")
        }
    }

    func testFeatureAutoCompletionPlanRejectsFeatureChangeAfterEvidenceCollection() throws {
        let original = "## F-001 Docs\n- Status: verifying\n- Verification: documentation\n- Auto complete: true\n- Source: docs/F-001.md\n"
        let root = try temporaryFeatureWorkspace(original)
        defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = try NativeFeatureStore.load(workspacePath: root.path)
        let evidence = featureEvidence(documentationPaths: ["docs/F-001.md"])
        let evaluation = FeatureCompletionEvaluator.evaluate(
            feature: snapshot.document.features[0], evidence: evidence
        )
        try original.replacingOccurrences(of: "docs/F-001.md", with: "docs/F-002.md").write(
            to: root.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8
        )

        XCTAssertThrowsError(
            try NativeFeatureStore.makeAutoCompletionPlan(
                workspacePath: root.path,
                evaluations: [evaluation],
                evidenceByFeatureID: ["F-001": evidence],
                expectedRevision: snapshot.revision
            )
        )
    }

    func testFeatureAutoCompletionMarksDoneEvidenceStaleWithoutReopening() throws {
        let root = try temporaryFeatureWorkspace(
            "## F-001 Snapshot\n- Status: done\n- Verification: code\n- Auto complete: true\n- Completed at: 1970-01-01T00:01:40Z\n- Completed by: Nexus Local Check\n"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let evidence = featureEvidence(
            relatedChangeIDs: ["new-change"],
            latestRelatedChangeAt: Date(timeIntervalSince1970: 101)
        )
        let feature = try NativeFeatureStore.load(workspacePath: root.path).document.features[0]
        let evaluation = FeatureCompletionEvaluator.evaluate(feature: feature, evidence: evidence)
        let plan = try NativeFeatureStore.makeAutoCompletionPlan(
            workspacePath: root.path,
            evaluations: [evaluation],
            evidenceByFeatureID: [feature.id: evidence]
        )

        let response = try NativeFeatureStore.applyAutoCompletions(
            plan: plan,
            confirmed: true,
            actor: "Nexus Local Check"
        )

        XCTAssertEqual(response.document.features[0].status, .done)
        XCTAssertTrue(response.document.features[0].evidenceStale)
        XCTAssertEqual(response.transitions.map(\.action), ["feature.evidence_stale"])
    }

    func testFeatureAutoCompletionPreservesWriteWhenAuditFails() throws {
        let root = try temporaryFeatureWorkspace(
            "## F-001 Docs\n- Status: verifying\n- Verification: documentation\n- Auto complete: true\n"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let auditBlocker = root.appendingPathComponent("audit-blocker")
        try Data("not a directory".utf8).write(to: auditBlocker)
        let evidence = featureEvidence(documentationPaths: ["docs/F-001.md"])
        let feature = try NativeFeatureStore.load(workspacePath: root.path).document.features[0]
        let evaluation = FeatureCompletionEvaluator.evaluate(feature: feature, evidence: evidence)
        let plan = try NativeFeatureStore.makeAutoCompletionPlan(
            workspacePath: root.path,
            evaluations: [evaluation],
            evidenceByFeatureID: [feature.id: evidence]
        )

        let response = try NativeFeatureStore.applyAutoCompletions(
            plan: plan,
            confirmed: true,
            actor: "Nexus Local Check",
            auditRoot: auditBlocker.path
        )

        XCTAssertEqual(response.document.features[0].status, .done)
        XCTAssertEqual(response.auditErrors.count, 1)
        XCTAssertEqual(
            try NativeFeatureStore.load(workspacePath: root.path).document.features[0].status,
            .done
        )
    }

    @MainActor
    func testAppStateExplicitFeatureCompletionCheckUpdatesFactsAndEvaluation() async throws {
        let root = try temporaryFeatureWorkspace(
            "## F-001 Docs\n- Status: verifying\n- Verification: documentation\n- Auto complete: true\n- Source: docs/F-001.md\n"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = featureEvidenceWorkspace(root: root)
        let appState = makeAppState(workspace: workspace, root: root)
        appState.selectedWorkspaceID = workspace.id

        let transitions = await appState.applyFeatureCompletionEvidence(
            actor: "Nexus Local Check",
            confirmedTrigger: true
        )

        XCTAssertEqual(transitions.map(\.action), ["feature.auto_completed"])
        XCTAssertEqual(appState.featuresByWorkspace[workspace.id]?.features[0].status, .done)
        XCTAssertEqual(
            appState.featureCompletionEvaluationsByWorkspace[workspace.id]?["F-001"]?.decision,
            .autoComplete
        )
        XCTAssertEqual(
            appState.featureEvidenceByWorkspace[workspace.id]?["F-001"]?.documentationPaths,
            ["docs/F-001.md"]
        )
    }

    @MainActor
    func testAppStatePassiveFeatureScanCannotWrite() async throws {
        let root = try temporaryFeatureWorkspace(
            "## F-001 Docs\n- Status: verifying\n- Verification: documentation\n- Auto complete: true\n- Source: docs/F-001.md\n"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let workspace = featureEvidenceWorkspace(root: root)
        let appState = makeAppState(workspace: workspace, root: root)

        let transitions = await appState.applyFeatureCompletionEvidence(
            actor: "Nexus Refresh",
            confirmedTrigger: false
        )

        XCTAssertTrue(transitions.isEmpty)
        XCTAssertEqual(
            try NativeFeatureStore.load(workspacePath: root.path).document.features[0].status,
            .verifying
        )
    }

    func testFeatureCompletionReversalHasDedicatedAuditActionAndReason() throws {
        let root = try temporaryFeatureWorkspace(
            "## F-001 Snapshot\n- Status: done\n- Verification: code\n- Auto complete: true\n- Completed at: 2026-07-11T03:00:00Z\n- Completed by: Nexus Local Check\n"
        )
        defer { try? FileManager.default.removeItem(at: root) }
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .revertCompletion(id: "F-001", reason: "New acceptance issue")
        )

        let response = try NativeFeatureStore.write(
            plan: plan,
            confirmed: true,
            auditRoot: root.appendingPathComponent("audit").path,
            actor: "Reviewer"
        )

        XCTAssertEqual(response.document.features[0].status, .verifying)
        XCTAssertEqual(response.document.features[0].completionNote, "New acceptance issue")
        XCTAssertNil(response.document.features[0].completedAt)
        XCTAssertFalse(response.document.features[0].evidenceStale)
        XCTAssertEqual(
            try NativeAuditEventStore.loadRecent(
                auditRoot: root.appendingPathComponent("audit").path,
                limit: 1
            ).first?.action,
            "feature.completion_reverted"
        )
    }

    func testLocalAutomationCheckSurfacesFeatureCompletionAndStaleEvidenceSignals() {
        let base = NativeLocalAutomationCheck.response(
            workspaces: [],
            generatedAt: "2026-07-11T03:00:00Z"
        )
        let transitions = [
            FeatureCompletionTransition(
                featureID: "F-001",
                action: "feature.auto_completed",
                previousStatus: .verifying,
                nextStatus: .done,
                evidenceIDs: ["test_order"]
            ),
            FeatureCompletionTransition(
                featureID: "F-002",
                action: "feature.evidence_stale",
                previousStatus: .done,
                nextStatus: .done,
                evidenceIDs: ["commit-2"]
            )
        ]

        let response = NativeLocalAutomationCheck.appendingFeatureCompletionSignals(
            to: base,
            transitions: transitions
        )

        XCTAssertEqual(response.status, "review")
        XCTAssertTrue(response.signals.contains { $0.id == "feature.auto-completed" && $0.count == 1 })
        XCTAssertTrue(response.signals.contains { $0.id == "feature.evidence-stale" && $0.action == "review-feature-evidence" })
        XCTAssertTrue(response.summary.contains("F-001"))
        XCTAssertTrue(response.summary.contains("F-002"))
    }

    func testFeatureEvidencePresentationSurfacesExactSignalsWithoutBroadSuccess() {
        let evidence = featureEvidence(
            linkedTaskIDs: ["T-1"],
            relatedChangeIDs: ["abc123"],
            latestRelatedChangeAt: Date(timeIntervalSince1970: 100),
            requiredTestIDs: ["test_order"],
            latestTestAt: Date(timeIntervalSince1970: 101),
            formalSQLPaths: ["sql/formal/F-001.sql"],
            rollbackSQLPaths: ["sql/rollback/F-001.sql"],
            documentationPaths: ["docs/F-001.md"],
            blockers: ["risk open"],
            readErrors: ["git failed"]
        )
        let evaluation = FeatureCompletionEvaluation(
            featureID: "F-001",
            decision: .keepVerifying,
            reasons: ["Blocker: risk open"]
        )

        let lines = FeatureWorkspaceEvidencePresentation.lines(
            evidence: evidence,
            evaluation: evaluation
        )

        for value in [
            "T-1", "abc123", "test_order", "sql/formal/F-001.sql",
            "sql/rollback/F-001.sql", "docs/F-001.md", "risk open", "git failed"
        ] {
            XCTAssertTrue(lines.contains { $0.contains(value) })
        }
        XCTAssertFalse(lines.contains { $0.contains("workspace passed") })
    }

    private func assertFeatureInjectionRejectedBeforePublish(_ injectedLines: String) throws {
        let root = try temporaryDemandWorkspace()
        defer { try? FileManager.default.removeItem(at: root) }
        let featuresURL = root.appendingPathComponent("FEATURES.md")
        let original = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        try original.write(to: featuresURL, atomically: true, encoding: .utf8)
        let expected = try XCTUnwrap(
            NativeFeatureStore.load(workspacePath: root.path).document.features.first
        )
        var replacement = expected
        replacement.preservedLines.append(injectedLines)
        let plan = try NativeFeatureStore.makePlan(
            workspacePath: root.path,
            mutation: .update(expected: expected, replacement: replacement)
        )
        var reachedPublish = false

        XCTAssertThrowsError(
            try NativeFeatureStore.write(
                plan: plan,
                confirmed: true,
                beforePublish: { reachedPublish = true }
            )
        )
        XCTAssertFalse(reachedPublish)
        XCTAssertEqual(try String(contentsOf: featuresURL, encoding: .utf8), original)
    }

    private func completionFeature(
        verification: FeatureVerificationPolicy
    ) -> WorkspaceFeature {
        WorkspaceFeature(
            id: "F-001",
            title: "Order snapshot",
            status: .todo,
            verification: verification,
            autoComplete: true,
            sources: [],
            services: ["order-service"],
            taskIDs: [],
            evidenceIDs: [],
            description: "",
            completedAt: nil,
            completedBy: nil,
            completionNote: nil,
            evidenceStale: false,
            preservedLines: []
        )
    }

    private func featureEvidence(
        linkedTaskIDs: [String] = [],
        incompleteTaskIDs: [String] = [],
        relatedChangeIDs: [String] = [],
        latestRelatedChangeAt: Date? = nil,
        requiredTestIDs: [String] = [],
        failedOrMissingTestIDs: [String] = [],
        latestTestAt: Date? = nil,
        formalSQLPaths: [String] = [],
        rollbackSQLPaths: [String] = [],
        documentationPaths: [String] = [],
        blockers: [String] = [],
        readErrors: [String] = []
    ) -> FeatureEvidence {
        FeatureEvidence(
            featureID: "F-001",
            linkedTaskIDs: linkedTaskIDs,
            incompleteTaskIDs: incompleteTaskIDs,
            relatedChangeIDs: relatedChangeIDs,
            latestRelatedChangeAt: latestRelatedChangeAt,
            requiredTestIDs: requiredTestIDs,
            failedOrMissingTestIDs: failedOrMissingTestIDs,
            latestTestAt: latestTestAt,
            formalSQLPaths: formalSQLPaths,
            rollbackSQLPaths: rollbackSQLPaths,
            documentationPaths: documentationPaths,
            blockers: blockers,
            readErrors: readErrors
        )
    }

    private func featureEvidenceWorkspace(
        root: URL,
        tasks: [WorkspaceTask] = [],
        riskDetails: [String] = []
    ) -> WorkspaceSummary {
        let base = demandInputWorkspace(path: root.path)
        return WorkspaceSummary(
            id: base.id,
            name: base.name,
            folder: base.folder,
            path: base.path,
            branch: base.branch,
            state: base.state,
            riskLevel: base.riskLevel,
            aiState: base.aiState,
            worktreeState: base.worktreeState,
            documentLinks: base.documentLinks,
            sqlFiles: [
                WorkspaceSqlFile(
                    relativePath: "sql/formal/F-001.sql",
                    path: root.appendingPathComponent("sql/formal/F-001.sql").path,
                    kind: "formal"
                ),
                WorkspaceSqlFile(
                    relativePath: "sql/rollback/F-001.sql",
                    path: root.appendingPathComponent("sql/rollback/F-001.sql").path,
                    kind: "rollback"
                )
            ],
            sqlDocuments: [
                WorkspaceSqlDocument(
                    relativePath: "docs/F-001.md",
                    path: root.appendingPathComponent("docs/F-001.md").path,
                    kind: "documentation"
                )
            ],
            services: [
                ServiceStatus(
                    name: "order-service",
                    branch: "feature/order",
                    worktree: root.appendingPathComponent("repo").path,
                    gitSummary: "clean",
                    worktreeExists: true,
                    sourceExists: true
                )
            ],
            activities: base.activities,
            risks: riskDetails.map { RiskAlert(title: "risk", detail: $0) },
            healthChecks: base.healthChecks,
            sessionActions: base.sessionActions,
            lifecycle: base.lifecycle,
            tasks: tasks
        )
    }

    private func temporaryFeatureWorkspace(_ source: String) throws -> URL {
        let root = try temporaryDemandWorkspace()
        try source.write(
            to: root.appendingPathComponent("FEATURES.md"),
            atomically: true,
            encoding: .utf8
        )
        return root
    }

    @MainActor
    private func assertOldFeatureWriteCannotClearNewWorkspacePendingWrite(
        failOldWrite: Bool
    ) async throws {
        let rootA = try temporaryDemandWorkspace()
        let rootB = try temporaryDemandWorkspace()
        defer {
            try? FileManager.default.removeItem(at: rootA)
            try? FileManager.default.removeItem(at: rootB)
        }
        let source = "## F-001 Snapshot\n- Status: todo\n- Verification: code\n- Auto complete: true\n"
        let featuresA = rootA.appendingPathComponent("FEATURES.md")
        try source.write(to: featuresA, atomically: true, encoding: .utf8)
        try source.write(to: rootB.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8)
        let workspaceA = demandInputWorkspace(id: "workspace-a", path: rootA.path)
        let workspaceB = demandInputWorkspace(id: "workspace-b", path: rootB.path)
        let appState = makeAppState(workspaces: [workspaceA, workspaceB], root: rootA)
        let writeStarted = expectation(description: "old write reached detached IO")
        let releaseWrite = DispatchSemaphore(value: 0)
        defer { releaseWrite.signal() }

        await appState.requestFeatureWrite(
            .setStatus(id: "F-001", status: .done, completionNote: "A"),
            in: workspaceA
        ).value
        let operationA = try XCTUnwrap(appState.takePendingFeatureWrite())
        let writeA = Task { @MainActor in
            await appState.writeConfirmedFeature(operationA) {
                writeStarted.fulfill()
                releaseWrite.wait()
            }
        }
        await fulfillment(of: [writeStarted], timeout: 2)

        appState.selectedWorkspaceID = workspaceB.id
        await appState.requestFeatureWrite(
            .setStatus(id: "F-001", status: .done, completionNote: "B"),
            in: workspaceB
        ).value
        let pendingB = try XCTUnwrap(appState.pendingFeatureWrite(for: workspaceB))
        XCTAssertEqual(appState.featureWriteWorkspaceID, workspaceB.id)
        if failOldWrite {
            try (source + "external\n").write(to: featuresA, atomically: true, encoding: .utf8)
        }

        releaseWrite.signal()
        await writeA.value

        XCTAssertEqual(appState.featureWriteWorkspaceID, workspaceB.id)
        XCTAssertEqual(appState.pendingFeatureWrite(for: workspaceB), pendingB)
        XCTAssertNil(appState.lastError)
    }

    private func temporaryDemandWorkspace() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("nexus-demand-input-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func contextPackInput(workspacePath: String = "/tmp/nexus-context") -> NativeContextPackInput {
        NativeContextPackInput(
            generatedAt: "2026-07-11T01:02:03Z",
            workspaceName: "订单工作区",
            workspacePath: workspacePath,
            selectedFeature: NativeContextFeature(id: "F-003", title: "订单快照 🚀", status: "blocked", detail: "保留 Unicode"),
            activeLinkedTasks: [NativeContextTask(id: "T-003", title: "实现快照", status: "blocked", detail: "等待 schema")],
            blockers: ["schema 尚未确认"],
            nextAction: "确认 schema 后实现",
            services: [NativeContextService(name: "order-service", branch: "feature/order", gitSummary: "clean")],
            gitSummary: ["order-service: clean @ abc123"],
            latestRelevantCheck: "PASS 337 tests",
            confirmedChanges: ["## latest\n- confirmed change"],
            evidence: [
                NativeContextEvidence(path: "FEATURES.md", summary: "confirmed scope"),
                NativeContextEvidence(path: "tasks.md", summary: "active tasks"),
                NativeContextEvidence(
                    path: "交付记录.md",
                    summary: "FULL DELIVERY BODY " + String(repeating: "delivery content ", count: 40)
                )
            ],
            sourceRevisions: ["FEATURES.md": "feature-rev", "tasks.md": "task-rev", "changes.md": "changes-rev"]
        )
    }

    private func sessionChangeWorkspace() throws -> URL {
        let root = try temporaryDemandWorkspace()
        try "# Features\n".write(to: root.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8)
        try "# Tasks\n".write(to: root.appendingPathComponent("tasks.md"), atomically: true, encoding: .utf8)
        try "# Changes\n\n人工未知说明。\n".write(to: root.appendingPathComponent("changes.md"), atomically: true, encoding: .utf8)
        return root
    }

    private func writeSessionChangeDraft(at root: URL) throws -> SessionChangeDraft {
        let baseline = SessionChangeBaseline(
            sessionID: "session-1",
            workspacePath: root.path,
            startedAt: "2026-07-11T01:02:03Z",
            repositoryHeads: ["order-service": "abc123"],
            featureRevision: "feature-old",
            taskRevision: "task-old"
        )
        return try NativeSessionChangeStore.writeDraft(
            input: SessionChangeDraftInput(
                workspacePath: root.path,
                baseline: baseline,
                currentRepositoryHeads: ["order-service": "def456"],
                repositoryDiffs: ["order-service": "M Sources/Order.swift"],
                featureRevision: "feature-new",
                taskRevision: "task-new",
                latestTest: "PASS FeatureWorkflowTests",
                sqlAndDeliveryRevisions: ["sql/order.sql": "sql-rev", "交付记录.md": "delivery-rev"],
                codexSummary: "Added bounded context"
            )
        )
    }

    private func sessionChangeDraftFixture() throws -> (root: URL, draft: SessionChangeDraft) {
        let root = try sessionChangeWorkspace()
        return (root, try writeSessionChangeDraft(at: root))
    }

    private func featureProposalWorkspace() throws -> URL {
        let root = try temporaryDemandWorkspace()
        try (
            featureSource(id: "F-001", title: "Original")
                + "\n" + featureSource(id: "F-002", title: "Omitted")
        ).write(
            to: root.appendingPathComponent("FEATURES.md"), atomically: true, encoding: .utf8
        )
        try (
            featureSource(id: "F-001", title: "Changed")
                + "\n" + featureSource(id: "DRAFT-001", title: "Added", status: "draft")
        ).write(
            to: root.appendingPathComponent("FEATURES.draft.md"), atomically: true, encoding: .utf8
        )
        return root
    }

    private func forgedProposalPlan(
        _ plan: FeatureProposalMergePlan,
        items: [FeatureProposalItem]? = nil,
        selectedItemIDs: Set<String>? = nil,
        replacements: [String: WorkspaceFeature]? = nil
    ) -> FeatureProposalMergePlan {
        FeatureProposalMergePlan(
            workspacePath: plan.workspacePath,
            confirmedPath: plan.confirmedPath,
            draftPath: plan.draftPath,
            confirmedRevision: plan.confirmedRevision,
            draftRevision: plan.draftRevision,
            confirmedDocument: plan.confirmedDocument,
            draftDocument: plan.draftDocument,
            items: items ?? plan.items,
            selectedItemIDs: selectedItemIDs ?? plan.selectedItemIDs,
            replacements: replacements ?? plan.replacements
        )
    }

    private func assertRejectedProposalMergePreservesFacts(
        _ plan: FeatureProposalMergePlan,
        root: URL
    ) throws {
        let facts = root.appendingPathComponent("FEATURES.md")
        let original = try Data(contentsOf: facts)
        XCTAssertThrowsError(try NativeFeatureStore.merge(plan: plan, confirmed: true))
        XCTAssertEqual(try Data(contentsOf: facts), original)
    }

    private func featureSource(
        id: String,
        title: String,
        status: String = "todo"
    ) -> String {
        """
        ## \(id) \(title)
        - Status: \(status)
        - Verification: code
        - Auto complete: true
        """ + "\n"
    }

    private func featureSourceWithHistory(id: String, title: String, description: String) -> String {
        """
        ## \(id) \(title)
        - Status: done
        - Verification: code
        - Auto complete: true
        - Completed at: 2026-07-11T01:02:03Z
        - Completed by: Reviewer
        - Completion note: Accepted before proposal
        - Evidence stale: true

        \(description)
        """ + "\n"
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
            applicationSupportRoot: root.appendingPathComponent("application-support").path,
            defaults: defaults
        )
    }

    private enum PublishFailure: Error {
        case injected
    }
}
