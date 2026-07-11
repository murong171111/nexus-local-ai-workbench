import CryptoKit
import Darwin
import Foundation
import NexusBridge

enum NativeFeatureStore {
    private static let fileName = "FEATURES.md"
    private static let draftFileName = "FEATURES.draft.md"
    private static let idPattern = try! NSRegularExpression(pattern: #"^F-[0-9]{3,}$"#)
    private static let draftIDPattern = try! NSRegularExpression(pattern: #"^DRAFT-[0-9]{3,}$"#)
    private static let headingPattern = try! NSRegularExpression(
        pattern: #"^## ([A-Z][A-Z0-9]*-[0-9]+)(?: (.*))?$"#
    )
    private static let metadataLabels = [
        "Status", "Verification", "Auto complete", "Source", "Services", "Tasks", "Evidence",
        "Completed at", "Completed by", "Completion note", "Evidence stale"
    ]
    private static let lockRegistry = NSLock()
    private static var locksByWorkspace: [String: NSLock] = [:]

    static func inspect(workspacePath: String) -> FeatureDocumentSnapshot {
        do {
            return try load(workspacePath: workspacePath)
        } catch {
            let path = featureURL(workspacePath).path
            return FeatureDocumentSnapshot(
                document: .empty,
                revision: .invalid(reason: error.localizedDescription),
                path: path
            )
        }
    }

    static func load(workspacePath: String) throws -> FeatureDocumentSnapshot {
        let workspaceURL = canonicalWorkspaceURL(workspacePath)
        let path = workspaceURL.appendingPathComponent(fileName).path
        return try withWorkspaceDirectory(workspaceURL) { workspaceFD in
            try snapshot(workspaceFD: workspaceFD, path: path)
        }
    }

    static func makePlan(workspacePath: String, mutation: FeatureMutation) throws -> FeatureWritePlan {
        let snapshot = try load(workspacePath: workspacePath)
        let expectedFeature: WorkspaceFeature?
        switch mutation {
        case .add:
            expectedFeature = nil
        case .update(let expected, _):
            expectedFeature = expected
        case .setStatus(let id, _, _), .revertCompletion(let id, _), .cancel(let id, _):
            expectedFeature = snapshot.document.features.first { $0.id == id }
            guard expectedFeature != nil else { throw NativeFeatureStoreError.featureNotFound(id) }
        }
        return FeatureWritePlan(
            workspacePath: workspacePath,
            path: snapshot.path,
            revision: snapshot.revision,
            document: snapshot.document,
            expectedFeature: expectedFeature,
            mutation: mutation
        )
    }

    static func makeAutoCompletionPlan(
        workspacePath: String,
        evaluations: [FeatureCompletionEvaluation],
        evidenceByFeatureID: [String: FeatureEvidence],
        expectedRevision: FeatureDocumentRevision? = nil
    ) throws -> FeatureAutoCompletionPlan {
        let snapshot = try load(workspacePath: workspacePath)
        if let expectedRevision { try requireRevision(snapshot.revision, expected: expectedRevision) }
        var evaluationsByID: [String: FeatureCompletionEvaluation] = [:]
        for evaluation in evaluations {
            guard evaluationsByID.updateValue(evaluation, forKey: evaluation.featureID) == nil else {
                throw NativeFeatureStoreError.malformedPlan(snapshot.path)
            }
        }
        let items = try snapshot.document.features.compactMap { feature -> FeatureAutoCompletionPlanItem? in
            guard let evaluation = evaluationsByID[feature.id],
                  [.autoComplete, .markEvidenceStale].contains(evaluation.decision),
                  let evidence = evidenceByFeatureID[feature.id] else { return nil }
            guard FeatureCompletionEvaluator.evaluate(feature: feature, evidence: evidence) == evaluation else {
                throw NativeFeatureStoreError.staleFeature(feature.id)
            }
            if evaluation.decision == .autoComplete, !feature.autoComplete {
                throw NativeFeatureStoreError.unconfirmed
            }
            return FeatureAutoCompletionPlanItem(
                expectedFeature: feature,
                evaluation: evaluation,
                evidence: evidence
            )
        }
        return FeatureAutoCompletionPlan(
            workspacePath: workspacePath,
            path: snapshot.path,
            revision: snapshot.revision,
            document: snapshot.document,
            items: items
        )
    }

    static func applyAutoCompletions(
        plan: FeatureAutoCompletionPlan,
        confirmed: Bool,
        actor: String,
        completedAt: String = ISO8601DateFormatter().string(from: Date()),
        auditRoot: String? = nil
    ) throws -> FeatureAutoCompletionResponse {
        guard confirmed else { throw NativeFeatureStoreError.unconfirmed }
        if let item = plan.items.first(where: { $0.evaluation.decision == .autoComplete }),
           ISO8601DateFormatter().date(from: completedAt) == nil {
            throw NativeFeatureStoreError.invalidMetadata("Completed at", item.expectedFeature.id)
        }
        let workspaceURL = canonicalWorkspaceURL(plan.workspacePath)
        let featurePath = workspaceURL.appendingPathComponent(fileName).path
        guard plan.workspacePath == workspaceURL.path, plan.path == featurePath else {
            throw NativeFeatureStoreError.malformedPlan(plan.path)
        }

        let result = try writeLock(for: plan.workspacePath).withLock {
            () -> (FeatureDocument, FeatureDocumentRevision, [FeatureCompletionTransition]) in
            try withWorkspaceDirectory(workspaceURL) { workspaceFD in
                let current = try snapshot(workspaceFD: workspaceFD, path: featurePath)
                try requireRevision(current.revision, expected: plan.revision)
                guard current.document == plan.document else {
                    throw NativeFeatureStoreError.staleRevision(
                        expected: plan.revision.label,
                        current: current.revision.label
                    )
                }
                var document = current.document
                var transitions: [FeatureCompletionTransition] = []
                for item in plan.items {
                    guard let index = document.features.firstIndex(of: item.expectedFeature),
                          FeatureCompletionEvaluator.evaluate(
                            feature: document.features[index], evidence: item.evidence
                          ) == item.evaluation else {
                        throw NativeFeatureStoreError.staleFeature(item.expectedFeature.id)
                    }
                    let previous = document.features[index].status
                    let action: String
                    switch item.evaluation.decision {
                    case .autoComplete:
                        guard document.features[index].autoComplete else {
                            throw NativeFeatureStoreError.unconfirmed
                        }
                        document.features[index].status = .done
                        document.features[index].completedAt = completedAt
                        document.features[index].completedBy = actor
                        document.features[index].completionNote = completionEvidenceSummary(item.evidence)
                        document.features[index].evidenceStale = false
                        action = "feature.auto_completed"
                    case .markEvidenceStale:
                        document.features[index].evidenceStale = true
                        action = "feature.evidence_stale"
                    default:
                        continue
                    }
                    transitions.append(
                        FeatureCompletionTransition(
                            featureID: item.expectedFeature.id,
                            action: action,
                            previousStatus: previous,
                            nextStatus: document.features[index].status,
                            evidenceIDs: completionEvidenceIDs(item.evidence)
                        )
                    )
                }
                guard !transitions.isEmpty else { return (current.document, current.revision, []) }
                try validate(document)
                let data = try validatedRenderedData(document)
                let temporaryName = ".\(fileName).\(UUID().uuidString).tmp"
                let staged = try createVerifiedTemporaryFile(data, parentFD: workspaceFD, name: temporaryName)
                var temporaryCleanupIdentity: FileIdentity? = staged.identity
                defer {
                    close(staged.fd)
                    if let temporaryCleanupIdentity {
                        _ = unlinkNamedFileIfIdentityMatches(
                            parentFD: workspaceFD,
                            name: temporaryName,
                            identity: temporaryCleanupIdentity,
                            fingerprint: staged.fingerprint
                        )
                    }
                }
                try requireRevision(
                    snapshot(workspaceFD: workspaceFD, path: featurePath).revision,
                    expected: plan.revision
                )
                try replaceFeatureFile(
                    workspaceFD: workspaceFD,
                    path: featurePath,
                    temporaryName: temporaryName,
                    expectedRevision: plan.revision,
                    staged: staged,
                    expectedData: data,
                    afterPublishBeforeVerify: nil,
                    temporaryCleanupIdentity: &temporaryCleanupIdentity
                )
                let written = try snapshot(workspaceFD: workspaceFD, path: featurePath)
                return (written.document, written.revision, transitions)
            }
        }

        var auditErrors: [String] = []
        for transition in result.2 {
            let policy = plan.items.first {
                $0.expectedFeature.id == transition.featureID
            }?.expectedFeature.verification.rawValue ?? ""
            let audit = NativeAuditEventStore.appendFeedback(
                auditRoot: auditRoot,
                event: AuditEventInput(
                    actor: actor,
                    action: transition.action,
                    target: plan.path,
                    summary: "Feature evidence transition: \(transition.featureID)",
                    metadata: [
                        "workspace": plan.workspacePath,
                        "featureID": transition.featureID,
                        "policy": policy,
                        "previousStatus": transition.previousStatus.rawValue,
                        "nextStatus": transition.nextStatus.rawValue,
                        "evidenceIDs": transition.evidenceIDs.joined(separator: ","),
                        "sourceRevision": plan.revision.label,
                        "revision": result.1.label
                    ]
                )
            )
            if let error = audit.error { auditErrors.append("\(transition.featureID): \(error)") }
        }
        return FeatureAutoCompletionResponse(
            path: plan.path,
            revision: result.1,
            document: result.0,
            transitions: result.2,
            auditErrors: auditErrors
        )
    }

    static func inspectProposal(workspacePath: String) -> FeatureProposalReview {
        do {
            let plan = try makeMergePlan(workspacePath: workspacePath)
            return FeatureProposalReview(
                diff: FeatureProposalDiff(items: plan.items),
                confirmedRevision: plan.confirmedRevision,
                draftRevision: plan.draftRevision,
                error: nil
            )
        } catch {
            return FeatureProposalReview(
                diff: nil,
                confirmedRevision: nil,
                draftRevision: nil,
                error: error.localizedDescription
            )
        }
    }

    static func makeMergePlan(
        workspacePath: String,
        selectedItemIDs: Set<String>? = nil,
        replacements: [String: WorkspaceFeature] = [:],
        confirmedRevision: FeatureDocumentRevision? = nil,
        draftRevision: FeatureDocumentRevision? = nil
    ) throws -> FeatureProposalMergePlan {
        let workspaceURL = canonicalWorkspaceURL(workspacePath)
        guard workspacePath == workspaceURL.path else {
            throw NativeFeatureStoreError.invalidWorkspace(workspacePath)
        }
        let confirmedPath = workspaceURL.appendingPathComponent(fileName).path
        let draftPath = workspaceURL.appendingPathComponent(draftFileName).path
        return try withWorkspaceDirectory(workspaceURL) { workspaceFD in
            let confirmed = try snapshot(workspaceFD: workspaceFD, path: confirmedPath)
            let draft = try proposalSnapshot(workspaceFD: workspaceFD, path: draftPath)
            if case .missing = draft.revision { throw NativeFeatureStoreError.missingDraft(draftPath) }
            if let confirmedRevision { try requireRevision(confirmed.revision, expected: confirmedRevision) }
            if let draftRevision { try requireDraftRevision(draft.revision, expected: draftRevision) }
            let confirmedIDs = Set(confirmed.document.features.map(\.id))
            if let unknown = draft.document.features.first(where: {
                $0.id.hasPrefix("F-") && !confirmedIDs.contains($0.id)
            }) {
                throw NativeFeatureStoreError.unknownConfirmedFeature(unknown.id)
            }
            let diff = FeatureProposalDiff.resolve(
                confirmed: confirmed.document,
                draft: draft.document
            )
            let availableIDs = Set(diff.actionableItems.map(\.id))
            let selected = selectedItemIDs ?? Set(diff.actionableItems.map(\.id))
            let replaceableIDs = Set(diff.actionableItems.filter {
                $0.kind == .add || $0.kind == .change
            }.map(\.id))
            guard selected.isSubset(of: availableIDs),
                  Set(replacements.keys).isSubset(of: selected.intersection(replaceableIDs)) else {
                throw NativeFeatureStoreError.invalidProposalSelection
            }
            return FeatureProposalMergePlan(
                workspacePath: workspacePath,
                confirmedPath: confirmedPath,
                draftPath: draftPath,
                confirmedRevision: confirmed.revision,
                draftRevision: draft.revision,
                confirmedDocument: confirmed.document,
                draftDocument: draft.document,
                items: diff.items,
                selectedItemIDs: selected,
                replacements: replacements
            )
        }
    }

    static func merge(
        plan: FeatureProposalMergePlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        archiveTimestamp: String? = nil,
        afterWorkspaceOpen: (() throws -> Void)? = nil,
        beforeFinalRevisionCheck: (() throws -> Void)? = nil,
        beforePublish: (() throws -> Void)? = nil,
        afterPublishBeforeVerify: (() throws -> Void)? = nil,
        beforeArchive: (() throws -> Void)? = nil,
        afterArchiveRenameBeforeVerify: (() throws -> Void)? = nil
    ) throws -> FeatureProposalMergeResponse {
        guard confirmed else { throw NativeFeatureStoreError.unconfirmedProposal }
        let workspaceURL = canonicalWorkspaceURL(plan.workspacePath)
        guard plan.workspacePath == workspaceURL.path,
              plan.confirmedPath == workspaceURL.appendingPathComponent(fileName).path,
              plan.draftPath == workspaceURL.appendingPathComponent(draftFileName).path else {
            throw NativeFeatureStoreError.malformedPlan(plan.confirmedPath)
        }

        let selectedItems = plan.items.filter { plan.selectedItemIDs.contains($0.id) }
        let counts = (
            add: selectedItems.filter { $0.kind == .add }.count,
            change: selectedItems.filter { $0.kind == .change }.count,
            cancel: selectedItems.filter { $0.kind == .cancel }.count
        )
        let result = try writeLock(for: plan.workspacePath).withLock {
            () -> (FeatureDocument, FeatureDocumentRevision) in
            try withWorkspaceDirectory(workspaceURL) { workspaceFD in
                try afterWorkspaceOpen?()
                let current = try snapshot(workspaceFD: workspaceFD, path: plan.confirmedPath)
                let currentDraft = try proposalSnapshot(workspaceFD: workspaceFD, path: plan.draftPath)
                try requireRevision(current.revision, expected: plan.confirmedRevision)
                try requireDraftRevision(currentDraft.revision, expected: plan.draftRevision)
                let currentDiff = FeatureProposalDiff.resolve(
                    confirmed: current.document,
                    draft: currentDraft.document
                )
                let actionableIDs = Set(currentDiff.actionableItems.map(\.id))
                let replaceableIDs = Set(currentDiff.actionableItems.filter {
                    $0.kind == .add || $0.kind == .change
                }.map(\.id))
                guard current.document == plan.confirmedDocument,
                      currentDraft.document == plan.draftDocument,
                      currentDiff.items == plan.items else {
                    throw NativeFeatureStoreError.malformedPlan(plan.confirmedPath)
                }
                guard plan.selectedItemIDs.isSubset(of: actionableIDs),
                      Set(plan.replacements.keys).isSubset(
                        of: plan.selectedItemIDs.intersection(replaceableIDs)
                      ) else {
                    throw NativeFeatureStoreError.invalidProposalSelection
                }

                var document = current.document
                try applyProposal(plan, to: &document)
                try validate(document)
                let data = try validatedRenderedData(document)
                let temporaryName = ".\(fileName).\(UUID().uuidString).tmp"
                let staged = try createVerifiedTemporaryFile(data, parentFD: workspaceFD, name: temporaryName)
                var temporaryCleanupIdentity: FileIdentity? = staged.identity
                defer {
                    close(staged.fd)
                    if let temporaryCleanupIdentity {
                        _ = unlinkNamedFileIfIdentityMatches(
                            parentFD: workspaceFD,
                            name: temporaryName,
                            identity: temporaryCleanupIdentity,
                            fingerprint: staged.fingerprint
                        )
                    }
                }

                try beforeFinalRevisionCheck?()
                try requireRevision(
                    snapshot(workspaceFD: workspaceFD, path: plan.confirmedPath).revision,
                    expected: plan.confirmedRevision
                )
                try requireDraftRevision(
                    proposalSnapshot(workspaceFD: workspaceFD, path: plan.draftPath).revision,
                    expected: plan.draftRevision
                )
                try beforePublish?()
                try requireRevision(
                    snapshot(workspaceFD: workspaceFD, path: plan.confirmedPath).revision,
                    expected: plan.confirmedRevision
                )
                try requireDraftRevision(
                    proposalSnapshot(workspaceFD: workspaceFD, path: plan.draftPath).revision,
                    expected: plan.draftRevision
                )
                try replaceFeatureFile(
                    workspaceFD: workspaceFD,
                    path: plan.confirmedPath,
                    temporaryName: temporaryName,
                    expectedRevision: plan.confirmedRevision,
                    staged: staged,
                    expectedData: data,
                    afterPublishBeforeVerify: afterPublishBeforeVerify,
                    temporaryCleanupIdentity: &temporaryCleanupIdentity
                )
                let written = try snapshot(workspaceFD: workspaceFD, path: plan.confirmedPath)
                return (written.document, written.revision)
            }
        }

        let mergeActor = actor ?? "Nexus Native"
        let audit = NativeAuditEventStore.appendFeedback(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: mergeActor,
                action: "feature.proposal_merged",
                target: plan.confirmedPath,
                summary: "Confirmed Codex feature proposal",
                metadata: [
                    "workspace": plan.workspacePath,
                    "addCount": String(counts.add),
                    "changeCount": String(counts.change),
                    "cancelCount": String(counts.cancel),
                    "confirmedSourceRevision": plan.confirmedRevision.label,
                    "draftSourceRevision": plan.draftRevision.label,
                    "revision": result.1.label
                ]
            )
        )
        let archive: (path: String?, error: String?)
        do {
            try beforeArchive?()
            archive = archiveAcceptedDraft(
                plan: plan,
                timestamp: archiveTimestamp ?? archiveTimestampString(),
                afterRenameBeforeVerify: afterArchiveRenameBeforeVerify
            )
        } catch {
            archive = (nil, error.localizedDescription)
        }
        return FeatureProposalMergeResponse(
            path: plan.confirmedPath,
            revision: result.1,
            document: result.0,
            addCount: counts.add,
            changeCount: counts.change,
            cancelCount: counts.cancel,
            auditEventID: audit.response?.event.id,
            auditEventPath: audit.response?.path,
            auditError: audit.error,
            archivePath: archive.path,
            archiveError: archive.error
        )
    }

    static func write(
        plan: FeatureWritePlan,
        confirmed: Bool,
        auditRoot: String? = nil,
        actor: String? = nil,
        afterWorkspaceOpen: (() throws -> Void)? = nil,
        beforeFinalRevisionCheck: (() throws -> Void)? = nil,
        beforePublish: (() throws -> Void)? = nil,
        afterPublishBeforeVerify: (() throws -> Void)? = nil
    ) throws -> FeatureWriteResponse {
        guard confirmed else { throw NativeFeatureStoreError.unconfirmed }
        if case .invalid(let reason) = plan.revision {
            throw NativeFeatureStoreError.invalidDocument(reason)
        }

        let workspaceURL = canonicalWorkspaceURL(plan.workspacePath)
        let featurePath = workspaceURL.appendingPathComponent(fileName).path
        guard plan.workspacePath == workspaceURL.path, plan.path == featurePath else {
            throw NativeFeatureStoreError.malformedPlan(plan.path)
        }

        let mutationActor = actor ?? "Nexus Native"
        let result = try writeLock(for: plan.workspacePath).withLock {
            () -> (FeatureDocument, FeatureDocumentRevision) in
            try withWorkspaceDirectory(workspaceURL) { workspaceFD in
                try afterWorkspaceOpen?()
                let current = try snapshot(workspaceFD: workspaceFD, path: featurePath)
                try requireRevision(current.revision, expected: plan.revision)
                if let expected = plan.expectedFeature,
                   current.document.features.first(where: { $0.id == expected.id }) != expected {
                    throw NativeFeatureStoreError.staleFeature(expected.id)
                }

                var document = current.document
                try apply(plan.mutation, actor: mutationActor, to: &document)
                try validate(document)
                let data = try validatedRenderedData(document)
                let temporaryName = ".\(fileName).\(UUID().uuidString).tmp"
                let staged = try createVerifiedTemporaryFile(data, parentFD: workspaceFD, name: temporaryName)
                var temporaryCleanupIdentity: FileIdentity? = staged.identity
                defer {
                    close(staged.fd)
                    if let temporaryCleanupIdentity {
                        _ = unlinkNamedFileIfIdentityMatches(
                            parentFD: workspaceFD,
                            name: temporaryName,
                            identity: temporaryCleanupIdentity,
                            fingerprint: staged.fingerprint
                        )
                    }
                }

                try beforeFinalRevisionCheck?()
                try requireRevision(
                    snapshot(workspaceFD: workspaceFD, path: featurePath).revision,
                    expected: plan.revision
                )
                try beforePublish?()
                try replaceFeatureFile(
                    workspaceFD: workspaceFD,
                    path: featurePath,
                    temporaryName: temporaryName,
                    expectedRevision: plan.revision,
                    staged: staged,
                    expectedData: data,
                    afterPublishBeforeVerify: afterPublishBeforeVerify,
                    temporaryCleanupIdentity: &temporaryCleanupIdentity
                )
                let written = try snapshot(workspaceFD: workspaceFD, path: featurePath)
                return (written.document, written.revision)
            }
        }

        let id = mutationID(plan.mutation)
        let writtenFeature = result.0.features.first { $0.id == id }
        let audit = NativeAuditEventStore.appendFeedback(
            auditRoot: auditRoot,
            event: AuditEventInput(
                actor: mutationActor,
                action: auditAction(plan.mutation),
                target: plan.path,
                summary: auditSummary(plan.mutation),
                metadata: [
                    "workspace": plan.workspacePath,
                    "featureID": id,
                    "policy": writtenFeature?.verification.rawValue ?? "",
                    "evidenceIDs": writtenFeature?.evidenceIDs.joined(separator: ",") ?? "",
                    "previousStatus": plan.expectedFeature?.status.rawValue ?? "missing",
                    "nextStatus": writtenFeature?.status.rawValue ?? "missing",
                    "sourceRevision": plan.revision.label,
                    "revision": result.1.label
                ]
            )
        )
        return FeatureWriteResponse(
            path: plan.path,
            revision: result.1,
            document: result.0,
            auditEventID: audit.response?.event.id,
            auditEventPath: audit.response?.path,
            auditError: audit.error
        )
    }

    static func parse(_ source: String) throws -> FeatureDocument {
        try parse(source, allowsDraftIDs: false)
    }

    static func parseProposal(_ source: String) throws -> FeatureDocument {
        try parse(source, allowsDraftIDs: true)
    }

    private static func parse(_ source: String, allowsDraftIDs: Bool) throws -> FeatureDocument {
        let lines = source.components(separatedBy: "\n")
        var preamble: [String] = []
        var blocks: [(id: String, title: String, lines: [String])] = []
        var current: (id: String, title: String, lines: [String])?

        for line in lines {
            if let heading = featureHeading(line) {
                if let current { blocks.append(current) }
                current = (heading.id, heading.title, [])
            } else if (allowsDraftIDs && line.hasPrefix("## DRAFT-"))
                        || line.range(of: #"^## F-[0-9]"#, options: .regularExpression) != nil {
                throw NativeFeatureStoreError.invalidHeading(line)
            } else if current == nil {
                preamble.append(line)
            } else {
                current!.lines.append(line)
            }
        }
        if let current { blocks.append(current) }

        var ids = Set<String>()
        let features = try blocks.map { block -> WorkspaceFeature in
            guard validID(block.id) || (allowsDraftIDs && validDraftID(block.id)) else {
                throw NativeFeatureStoreError.invalidID(block.id)
            }
            guard ids.insert(block.id).inserted else { throw NativeFeatureStoreError.duplicateID(block.id) }
            return try parseFeature(block)
        }
        let layouts = Dictionary(uniqueKeysWithValues: blocks.map { block in
            (
                block.id,
                FeatureBlockLayout(lines: block.lines.map { line in
                    recognizedMetadata(line).map { .metadata($0.label) } ?? .prose(line)
                })
            )
        })
        return FeatureDocument(preamble: preamble, features: features, layoutsByFeatureID: layouts)
    }

    static func render(_ document: FeatureDocument) -> String {
        guard !document.layoutsByFeatureID.isEmpty else { return canonicalRender(document) }
        var lines = document.preamble
        for feature in document.features {
            guard let layout = document.layoutsByFeatureID[feature.id] else {
                appendCanonical(feature, to: &lines)
                continue
            }
            lines.append("## \(feature.id) \(feature.title)")
            var renderedBlock: [String] = []
            var renderedLabels = Set<String>()
            var lastMetadataIndex: Int?
            let layoutProse = layout.lines.compactMap { item -> String? in
                guard case .prose(let line) = item else { return nil }
                return line
            }
            let replacementProse = feature.preservedLines.flatMap {
                $0.components(separatedBy: "\n")
            }
            let proseChanged = layoutProse != replacementProse
            var insertedReplacementProse = false
            for item in layout.lines {
                switch item {
                case .metadata(let label):
                    renderedBlock.append(metadataLine(label, feature: feature, includeEmpty: true)!)
                    renderedLabels.insert(label)
                    lastMetadataIndex = renderedBlock.endIndex
                case .prose(let line):
                    if !proseChanged {
                        renderedBlock.append(line)
                    } else if !insertedReplacementProse {
                        renderedBlock.append(contentsOf: replacementProse)
                        insertedReplacementProse = true
                    }
                }
            }
            let missing = metadataLabels.compactMap { label -> String? in
                guard !renderedLabels.contains(label) else { return nil }
                return metadataLine(label, feature: feature, includeEmpty: false)
            }
            renderedBlock.insert(contentsOf: missing, at: lastMetadataIndex ?? 0)
            if proseChanged, !insertedReplacementProse {
                renderedBlock.insert(
                    contentsOf: replacementProse,
                    at: (lastMetadataIndex ?? 0) + missing.count
                )
            }
            lines.append(contentsOf: renderedBlock)
        }
        return lines.joined(separator: "\n")
    }

    private static func canonicalRender(_ document: FeatureDocument) -> String {
        var lines = document.preamble
        while lines.last == "" { lines.removeLast() }
        for feature in document.features { appendCanonical(feature, to: &lines) }
        while lines.last == "" { lines.removeLast() }
        return lines.joined(separator: "\n") + "\n"
    }

    private static func appendCanonical(_ feature: WorkspaceFeature, to lines: inout [String]) {
        if !lines.isEmpty, lines.last != "" { lines.append("") }
        lines.append("## \(feature.id) \(feature.title)")
        lines.append("")
        lines.append("- Status: \(feature.status.rawValue)")
        lines.append("- Verification: \(feature.verification.rawValue)")
        lines.append("- Auto complete: \(feature.autoComplete)")
        appendList("Source", feature.sources, to: &lines)
        appendList("Services", feature.services, to: &lines)
        appendList("Tasks", feature.taskIDs, to: &lines)
        appendList("Evidence", feature.evidenceIDs, to: &lines)
        lines.append("- Completed at: \(feature.completedAt ?? "")")
        lines.append("- Completed by: \(feature.completedBy ?? "")")
        if let note = feature.completionNote { lines.append("- Completion note: \(note)") }
        if feature.evidenceStale { lines.append("- Evidence stale: true") }
        if !feature.preservedLines.isEmpty {
            if feature.preservedLines.first != "" { lines.append("") }
            lines.append(contentsOf: feature.preservedLines)
        }
    }

    private static func parseFeature(
        _ block: (id: String, title: String, lines: [String])
    ) throws -> WorkspaceFeature {
        let title = block.title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw NativeFeatureStoreError.missingRequired("title", block.id) }
        var values: [String: String] = [:]
        var preserved: [String] = []
        for line in block.lines {
            guard let metadata = recognizedMetadata(line) else {
                preserved.append(line)
                continue
            }
            guard values[metadata.label] == nil else {
                throw NativeFeatureStoreError.duplicateMetadata(metadata.label, block.id)
            }
            values[metadata.label] = metadata.value
        }
        guard let statusValue = values["Status"], let status = FeatureStatus(rawValue: statusValue) else {
            throw NativeFeatureStoreError.missingRequired("valid Status", block.id)
        }
        guard let verificationValue = values["Verification"],
              let verification = FeatureVerificationPolicy(rawValue: verificationValue) else {
            throw NativeFeatureStoreError.missingRequired("valid Verification", block.id)
        }
        guard let autoValue = values["Auto complete"], let autoComplete = Bool(autoValue) else {
            throw NativeFeatureStoreError.missingRequired("valid Auto complete", block.id)
        }
        if let staleValue = values["Evidence stale"], Bool(staleValue) == nil {
            throw NativeFeatureStoreError.invalidMetadata("Evidence stale", block.id)
        }
        let description = preserved
            .joined(separator: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return WorkspaceFeature(
            id: block.id,
            title: title,
            status: status,
            verification: verification,
            autoComplete: autoComplete,
            sources: list(values["Source"]),
            services: list(values["Services"]),
            taskIDs: list(values["Tasks"]),
            evidenceIDs: list(values["Evidence"]),
            description: description,
            completedAt: optional(values["Completed at"]),
            completedBy: optional(values["Completed by"]),
            completionNote: optional(values["Completion note"]),
            evidenceStale: values["Evidence stale"].flatMap(Bool.init) ?? false,
            preservedLines: preserved
        )
    }

    private static func apply(
        _ mutation: FeatureMutation,
        actor: String,
        to document: inout FeatureDocument
    ) throws {
        switch mutation {
        case .add(let feature):
            guard validID(feature.id) else { throw NativeFeatureStoreError.invalidID(feature.id) }
            guard !document.features.contains(where: { $0.id == feature.id }) else {
                throw NativeFeatureStoreError.duplicateID(feature.id)
            }
            document.features.append(feature)
        case .update(let expected, let replacement):
            guard expected.id == replacement.id else { throw NativeFeatureStoreError.changedID }
            guard let index = document.features.firstIndex(of: expected) else {
                throw NativeFeatureStoreError.staleFeature(expected.id)
            }
            document.features[index] = replacement
        case .setStatus(let id, let status, let completionNote):
            guard let index = document.features.firstIndex(where: { $0.id == id }) else {
                throw NativeFeatureStoreError.featureNotFound(id)
            }
            document.features[index].status = status
            document.features[index].completionNote = completionNote
            if status == .done {
                document.features[index].completedAt = ISO8601DateFormatter().string(from: Date())
                document.features[index].completedBy = actor
            } else {
                document.features[index].completedAt = nil
                document.features[index].completedBy = nil
            }
        case .revertCompletion(let id, let reason):
            guard let index = document.features.firstIndex(where: { $0.id == id }),
                  document.features[index].status == .done else {
                throw NativeFeatureStoreError.staleFeature(id)
            }
            guard !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NativeFeatureStoreError.invalidMetadata("Completion note", id)
            }
            document.features[index].status = .verifying
            document.features[index].completionNote = reason
            document.features[index].completedAt = nil
            document.features[index].completedBy = nil
            document.features[index].evidenceStale = false
        case .cancel(let id, let reason):
            guard let index = document.features.firstIndex(where: { $0.id == id }) else {
                throw NativeFeatureStoreError.featureNotFound(id)
            }
            document.features[index].status = .cancelled
            document.features[index].completionNote = reason
            document.features[index].completedAt = nil
            document.features[index].completedBy = nil
        }
    }

    private static func applyProposal(
        _ plan: FeatureProposalMergePlan,
        to document: inout FeatureDocument
    ) throws {
        for item in plan.items where plan.selectedItemIDs.contains(item.id) {
            switch item.kind {
            case .add:
                guard let assignedID = item.assignedFeatureID,
                      let proposed = plan.replacements[item.id] ?? item.proposed else {
                    throw NativeFeatureStoreError.invalidProposalReplacement(item.id)
                }
                let replacement = newProposalFeature(proposed, id: assignedID)
                guard !document.features.contains(where: { $0.id == assignedID }) else {
                    throw NativeFeatureStoreError.duplicateID(assignedID)
                }
                document.features.append(replacement)
            case .change:
                guard let index = document.features.firstIndex(where: { $0.id == item.id }),
                      let proposed = plan.replacements[item.id] ?? item.proposed else {
                    throw NativeFeatureStoreError.invalidProposalReplacement(item.id)
                }
                document.features[index] = proposalScope(proposed, appliedTo: document.features[index])
            case .cancel:
                guard let index = document.features.firstIndex(where: { $0.id == item.id }) else {
                    throw NativeFeatureStoreError.featureNotFound(item.id)
                }
                document.features[index].status = .cancelled
                document.features[index].completionNote = "Cancelled by feature proposal"
                document.features[index].completedAt = nil
                document.features[index].completedBy = nil
            case .unchanged:
                break
            }
        }
    }

    private static func proposalScope(
        _ proposed: WorkspaceFeature,
        appliedTo current: WorkspaceFeature
    ) -> WorkspaceFeature {
        var current = current
        current.title = proposed.title
        current.verification = proposed.verification
        current.autoComplete = proposed.autoComplete
        current.sources = proposed.sources
        current.services = proposed.services
        current.taskIDs = proposed.taskIDs
        current.evidenceIDs = proposed.evidenceIDs
        current.description = proposed.description
        current.preservedLines = proposed.preservedLines
        return current
    }

    private static func newProposalFeature(_ proposed: WorkspaceFeature, id: String) -> WorkspaceFeature {
        WorkspaceFeature(
            id: id,
            title: proposed.title,
            status: .todo,
            verification: proposed.verification,
            autoComplete: proposed.autoComplete,
            sources: proposed.sources,
            services: proposed.services,
            taskIDs: proposed.taskIDs,
            evidenceIDs: proposed.evidenceIDs,
            description: proposed.description,
            completedAt: nil,
            completedBy: nil,
            completionNote: nil,
            evidenceStale: false,
            preservedLines: proposed.preservedLines
        )
    }

    private static func validate(_ document: FeatureDocument) throws {
        var ids = Set<String>()
        for feature in document.features {
            guard validID(feature.id) else { throw NativeFeatureStoreError.invalidID(feature.id) }
            guard ids.insert(feature.id).inserted else {
                throw NativeFeatureStoreError.duplicateID(feature.id)
            }
            guard !feature.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw NativeFeatureStoreError.missingRequired("title", feature.id)
            }
        }
    }

    private static func featureHeading(_ line: String) -> (id: String, title: String)? {
        let range = NSRange(line.startIndex..., in: line)
        guard let match = headingPattern.firstMatch(in: line, range: range),
              let idRange = Range(match.range(at: 1), in: line),
              let titleRange = Range(match.range(at: 2), in: line) else { return nil }
        return (String(line[idRange]), String(line[titleRange]))
    }

    private static func recognizedMetadata(_ line: String) -> (label: String, value: String)? {
        for label in metadataLabels {
            let prefix = "- \(label):"
            if line.hasPrefix(prefix) {
                return (label, String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces))
            }
        }
        return nil
    }

    private static func validID(_ id: String) -> Bool {
        idPattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil
    }

    private static func validDraftID(_ id: String) -> Bool {
        draftIDPattern.firstMatch(in: id, range: NSRange(id.startIndex..., in: id)) != nil
    }

    private static func list(_ value: String?) -> [String] {
        guard let value else { return [] }
        return value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    private static func optional(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private static func appendList(_ label: String, _ values: [String], to lines: inout [String]) {
        let normalized = Array(Set(values.filter { !$0.isEmpty })).sorted()
        if !normalized.isEmpty { lines.append("- \(label): \(normalized.joined(separator: ", "))") }
    }

    private static func metadataLine(
        _ label: String,
        feature: WorkspaceFeature,
        includeEmpty: Bool
    ) -> String? {
        let value: String?
        switch label {
        case "Status": value = feature.status.rawValue
        case "Verification": value = feature.verification.rawValue
        case "Auto complete": value = String(feature.autoComplete)
        case "Source": value = normalizedList(feature.sources)
        case "Services": value = normalizedList(feature.services)
        case "Tasks": value = normalizedList(feature.taskIDs)
        case "Evidence": value = normalizedList(feature.evidenceIDs)
        case "Completed at": value = feature.completedAt
        case "Completed by": value = feature.completedBy
        case "Completion note": value = feature.completionNote
        case "Evidence stale": value = feature.evidenceStale ? "true" : nil
        default: value = nil
        }
        guard includeEmpty || value != nil else { return nil }
        return "- \(label): \(value ?? "")"
    }

    private static func normalizedList(_ values: [String]) -> String? {
        let values = Array(Set(values.filter { !$0.isEmpty })).sorted()
        return values.isEmpty ? nil : values.joined(separator: ", ")
    }

    private static func validatedRenderedData(_ document: FeatureDocument) throws -> Data {
        let rendered = render(document)
        let parsed: FeatureDocument
        do {
            parsed = try parse(rendered)
        } catch {
            throw NativeFeatureStoreError.invalidDocument("rendered feature document is invalid: \(error.localizedDescription)")
        }
        guard parsed.preamble == document.preamble,
              normalizedFeatures(parsed.features) == normalizedFeatures(document.features) else {
            throw NativeFeatureStoreError.invalidDocument("rendered feature document does not match the confirmed mutation")
        }
        return Data(rendered.utf8)
    }

    private static func normalizedFeatures(_ features: [WorkspaceFeature]) -> [WorkspaceFeature] {
        features.map { feature in
            var normalized = feature
            normalized.sources = Array(Set(feature.sources.filter { !$0.isEmpty })).sorted()
            normalized.services = Array(Set(feature.services.filter { !$0.isEmpty })).sorted()
            normalized.taskIDs = Array(Set(feature.taskIDs.filter { !$0.isEmpty })).sorted()
            normalized.evidenceIDs = Array(Set(feature.evidenceIDs.filter { !$0.isEmpty })).sorted()
            var preservedLines = feature.preservedLines.flatMap {
                $0.components(separatedBy: "\n")
            }
            while preservedLines.first == "" { preservedLines.removeFirst() }
            while preservedLines.last == "" { preservedLines.removeLast() }
            normalized.preservedLines = preservedLines
            return normalized
        }
    }

    private static func snapshot(workspaceFD: Int32, path: String) throws -> FeatureDocumentSnapshot {
        try snapshot(workspaceFD: workspaceFD, name: fileName, path: path, parser: parse)
    }

    private static func proposalSnapshot(workspaceFD: Int32, path: String) throws -> FeatureDocumentSnapshot {
        try snapshot(workspaceFD: workspaceFD, name: draftFileName, path: path, parser: parseProposal)
    }

    private static func snapshot(
        workspaceFD: Int32,
        name: String,
        path: String,
        parser: (String) throws -> FeatureDocument
    ) throws -> FeatureDocumentSnapshot {
        let fileFD = openat(workspaceFD, name, O_RDONLY | O_NOFOLLOW)
        if fileFD < 0 {
            if errno == ENOENT {
                return FeatureDocumentSnapshot(document: .empty, revision: .missing, path: path)
            }
            throw NativeFeatureStoreError.unreadable(path)
        }
        defer { close(fileFD) }
        var info = stat()
        guard fstat(fileFD, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw NativeFeatureStoreError.notRegularFile(path)
        }
        let data = try readData(fileFD)
        guard let content = String(data: data, encoding: .utf8) else {
            throw NativeFeatureStoreError.invalidUTF8(path)
        }
        return FeatureDocumentSnapshot(
            document: try parser(content),
            revision: revision(data),
            path: path
        )
    }

    private static func requireRevision(
        _ current: FeatureDocumentRevision,
        expected: FeatureDocumentRevision
    ) throws {
        guard current == expected else {
            throw NativeFeatureStoreError.staleRevision(
                expected: expected.label,
                current: current.label
            )
        }
    }

    private static func requireDraftRevision(
        _ current: FeatureDocumentRevision,
        expected: FeatureDocumentRevision
    ) throws {
        guard current == expected else {
            throw NativeFeatureStoreError.staleDraftRevision(
                expected: expected.label,
                current: current.label
            )
        }
    }

    private static func withWorkspaceDirectory<T>(
        _ workspaceURL: URL,
        body: (Int32) throws -> T
    ) throws -> T {
        let workspaceFD = open(workspaceURL.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW)
        guard workspaceFD >= 0 else {
            throw NativeFeatureStoreError.invalidWorkspace(workspaceURL.path)
        }
        defer { close(workspaceFD) }
        return try body(workspaceFD)
    }

    private static func canonicalWorkspaceURL(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    private static func featureURL(_ workspacePath: String) -> URL {
        canonicalWorkspaceURL(workspacePath).appendingPathComponent(fileName)
    }

    private static func archiveAcceptedDraft(
        plan: FeatureProposalMergePlan,
        timestamp: String,
        afterRenameBeforeVerify: (() throws -> Void)?
    ) -> (path: String?, error: String?) {
        guard timestamp.range(of: #"^[A-Za-z0-9_-]+$"#, options: .regularExpression) != nil else {
            return (nil, "invalid feature proposal archive timestamp")
        }
        let archiveName = "FEATURES.draft.accepted-\(timestamp).md"
        let workspaceURL = canonicalWorkspaceURL(plan.workspacePath)
        let archivePath = workspaceURL.appendingPathComponent(archiveName).path
        do {
            try writeLock(for: plan.workspacePath).withLock {
                try withWorkspaceDirectory(workspaceURL) { workspaceFD in
                    let current = try proposalSnapshot(workspaceFD: workspaceFD, path: plan.draftPath)
                    try requireDraftRevision(current.revision, expected: plan.draftRevision)
                    guard entryKind(at: workspaceFD, name: archiveName) == .missing else {
                        throw NativeFeatureStoreError.archiveExists(archivePath)
                    }
                    let sourceIdentity = try namedRegularFileIdentity(
                        parentFD: workspaceFD,
                        name: draftFileName,
                        path: plan.draftPath
                    )
                    guard case .regularUTF8(let sha256, let byteCount) = plan.draftRevision else {
                        throw NativeFeatureStoreError.archiveConflict(archivePath)
                    }
                    let sourceFingerprint = FileContentFingerprint(
                        byteCount: byteCount,
                        sha256: sha256
                    )
                    guard renameatx_np(
                        workspaceFD,
                        draftFileName,
                        workspaceFD,
                        archiveName,
                        UInt32(RENAME_EXCL)
                    ) == 0 else {
                        throw NativeFeatureStoreError.archiveConflict(archivePath)
                    }
                    do {
                        try afterRenameBeforeVerify?()
                        let archived = try snapshot(
                            workspaceFD: workspaceFD,
                            name: archiveName,
                            path: archivePath,
                            parser: parseProposal
                        )
                        guard archived.revision == plan.draftRevision,
                              try namedRegularFileIdentity(
                                parentFD: workspaceFD,
                                name: archiveName,
                                path: archivePath
                              ) == sourceIdentity else {
                            throw NativeFeatureStoreError.archiveConflict(archivePath)
                        }
                    } catch {
                        guard entryKind(at: workspaceFD, name: draftFileName) == .missing,
                              namedFileMatches(
                                parentFD: workspaceFD,
                                name: archiveName,
                                identity: sourceIdentity,
                                fingerprint: sourceFingerprint
                              ),
                              renameatx_np(
                                workspaceFD,
                                archiveName,
                                workspaceFD,
                                draftFileName,
                                UInt32(RENAME_EXCL)
                              ) == 0 else {
                            throw NativeFeatureStoreError.archiveRecoveryRequired(archivePath)
                        }
                        throw error
                    }
                }
            }
            return (archivePath, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    private static func archiveTimestampString() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: Date())
            .replacingOccurrences(of: "-", with: "")
            .replacingOccurrences(of: ":", with: "")
    }

    private static func createVerifiedTemporaryFile(
        _ data: Data,
        parentFD: Int32,
        name: String
    ) throws -> OpenTemporaryFile {
        let fileFD = openat(parentFD, name, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW, mode_t(0o600))
        guard fileFD >= 0 else { throw posixError() }
        let identity: FileIdentity
        do {
            identity = try fileIdentity(fileFD, path: name)
        } catch {
            close(fileFD)
            throw error
        }
        do {
            try FileHandle(fileDescriptor: fileFD, closeOnDealloc: false).write(contentsOf: data)
            guard fsync(fileFD) == 0 else { throw posixError() }
            let written = try readData(fileFD)
            guard written == data else {
                throw NativeFeatureStoreError.publicationConflict(name)
            }
            return OpenTemporaryFile(
                fd: fileFD,
                identity: identity,
                fingerprint: FileContentFingerprint(data: written)
            )
        } catch {
            close(fileFD)
            _ = unlinkNamedFileIfIdentityMatches(
                parentFD: parentFD,
                name: name,
                identity: identity,
                fingerprint: FileContentFingerprint(data: data)
            )
            throw error
        }
    }

    private static func replaceFeatureFile(
        workspaceFD: Int32,
        path: String,
        temporaryName: String,
        expectedRevision: FeatureDocumentRevision,
        staged: OpenTemporaryFile,
        expectedData: Data,
        afterPublishBeforeVerify: (() throws -> Void)?,
        temporaryCleanupIdentity: inout FileIdentity?
    ) throws {
        switch expectedRevision {
        case .missing:
            guard entryKind(at: workspaceFD, name: fileName) == .missing,
                  linkat(workspaceFD, temporaryName, workspaceFD, fileName, 0) == 0 else {
                let current = try? snapshot(workspaceFD: workspaceFD, path: path).revision
                throw NativeFeatureStoreError.staleRevision(
                    expected: expectedRevision.label,
                    current: current?.label ?? "unsafe"
                )
            }
            do {
                try afterPublishBeforeVerify?()
                try verifyPublishedFile(
                    parentFD: workspaceFD,
                    name: fileName,
                    path: path,
                    staged: staged,
                    expectedData: expectedData
                )
                guard unlinkNamedFileIfIdentityMatches(
                    parentFD: workspaceFD,
                    name: temporaryName,
                    identity: staged.identity,
                    fingerprint: staged.fingerprint
                ) else { throw NativeFeatureStoreError.publicationConflict(temporaryName) }
                temporaryCleanupIdentity = nil
            } catch {
                guard unlinkNamedFileIfIdentityMatches(
                    parentFD: workspaceFD,
                    name: fileName,
                    identity: staged.identity,
                    fingerprint: staged.fingerprint
                ) else { throw NativeFeatureStoreError.publicationConflict(path) }
                throw error
            }
        case .regularUTF8(let expectedSHA256, let expectedByteCount):
            try requireRevision(
                snapshot(workspaceFD: workspaceFD, path: path).revision,
                expected: expectedRevision
            )
            let previousIdentity = try namedRegularFileIdentity(
                parentFD: workspaceFD,
                name: fileName,
                path: path
            )
            guard renameatx_np(
                workspaceFD,
                temporaryName,
                workspaceFD,
                fileName,
                UInt32(RENAME_SWAP)
            ) == 0 else { throw NativeFeatureStoreError.publicationConflict(path) }
            temporaryCleanupIdentity = previousIdentity
            do {
                try afterPublishBeforeVerify?()
                try verifyPublishedFile(
                    parentFD: workspaceFD,
                    name: fileName,
                    path: path,
                    staged: staged,
                    expectedData: expectedData
                )
                guard unlinkNamedFileIfIdentityMatches(
                    parentFD: workspaceFD,
                    name: temporaryName,
                    identity: previousIdentity,
                    fingerprint: FileContentFingerprint(
                        byteCount: expectedByteCount,
                        sha256: expectedSHA256
                    )
                ) else { throw NativeFeatureStoreError.publicationConflict(temporaryName) }
                temporaryCleanupIdentity = nil
            } catch {
                let previousFingerprint = FileContentFingerprint(
                    byteCount: expectedByteCount,
                    sha256: expectedSHA256
                )
                guard namedFileMatches(
                    parentFD: workspaceFD,
                    name: fileName,
                    identity: staged.identity,
                    fingerprint: staged.fingerprint
                ), namedFileMatches(
                    parentFD: workspaceFD,
                    name: temporaryName,
                    identity: previousIdentity,
                    fingerprint: previousFingerprint
                ) else {
                    temporaryCleanupIdentity = nil
                    throw NativeFeatureStoreError.recoveryRequired(path, temporaryName)
                }
                guard renameatx_np(
                    workspaceFD,
                    temporaryName,
                    workspaceFD,
                    fileName,
                    UInt32(RENAME_SWAP)
                ) == 0 else {
                    temporaryCleanupIdentity = nil
                    throw NativeFeatureStoreError.recoveryRequired(path, temporaryName)
                }
                temporaryCleanupIdentity = staged.identity
                throw error
            }
        case .invalid(let reason):
            throw NativeFeatureStoreError.invalidDocument(reason)
        }
    }

    private static func verifyPublishedFile(
        parentFD: Int32,
        name: String,
        path: String,
        staged: OpenTemporaryFile,
        expectedData: Data
    ) throws {
        let fileFD = openat(parentFD, name, O_RDONLY | O_NOFOLLOW)
        guard fileFD >= 0 else { throw NativeFeatureStoreError.publicationConflict(path) }
        defer { close(fileFD) }
        guard try fileIdentity(fileFD, path: path) == staged.identity,
              try readData(fileFD) == expectedData else {
            throw NativeFeatureStoreError.publicationConflict(path)
        }
    }

    private static func unlinkNamedFileIfIdentityMatches(
        parentFD: Int32,
        name: String,
        identity: FileIdentity,
        fingerprint: FileContentFingerprint
    ) -> Bool {
        let fileFD = openat(parentFD, name, O_RDONLY | O_NOFOLLOW)
        guard fileFD >= 0 else { return false }
        defer { close(fileFD) }
        guard (try? fileIdentity(fileFD, path: name)) == identity,
              let data = try? readData(fileFD),
              FileContentFingerprint(data: data) == fingerprint else { return false }
        return unlinkat(parentFD, name, 0) == 0
    }

    private static func namedFileMatches(
        parentFD: Int32,
        name: String,
        identity: FileIdentity,
        fingerprint: FileContentFingerprint
    ) -> Bool {
        let fileFD = openat(parentFD, name, O_RDONLY | O_NOFOLLOW)
        guard fileFD >= 0 else { return false }
        defer { close(fileFD) }
        guard (try? fileIdentity(fileFD, path: name)) == identity,
              let data = try? readData(fileFD) else { return false }
        return FileContentFingerprint(data: data) == fingerprint
    }

    private static func namedRegularFileIdentity(
        parentFD: Int32,
        name: String,
        path: String
    ) throws -> FileIdentity {
        let fileFD = openat(parentFD, name, O_RDONLY | O_NOFOLLOW)
        guard fileFD >= 0 else { throw NativeFeatureStoreError.publicationConflict(path) }
        defer { close(fileFD) }
        return try fileIdentity(fileFD, path: path)
    }

    private static func fileIdentity(_ fileFD: Int32, path: String) throws -> FileIdentity {
        var info = stat()
        guard fstat(fileFD, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG else {
            throw NativeFeatureStoreError.notRegularFile(path)
        }
        return FileIdentity(device: UInt64(info.st_dev), inode: UInt64(info.st_ino))
    }

    private static func entryKind(at parentFD: Int32, name: String) -> EntryKind {
        var info = stat()
        guard fstatat(parentFD, name, &info, AT_SYMLINK_NOFOLLOW) == 0 else {
            return errno == ENOENT ? .missing : .other
        }
        return (info.st_mode & S_IFMT) == S_IFREG ? .regular : .other
    }

    private static func readData(_ fileFD: Int32) throws -> Data {
        guard lseek(fileFD, 0, SEEK_SET) >= 0 else { throw posixError() }
        return try FileHandle(fileDescriptor: fileFD, closeOnDealloc: false).readToEnd() ?? Data()
    }

    private static func revision(_ data: Data) -> FeatureDocumentRevision {
        .regularUTF8(sha256: sha256Hex(data), byteCount: data.count)
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }

    private static func writeLock(for workspacePath: String) -> NSLock {
        lockRegistry.withLock {
            if let lock = locksByWorkspace[workspacePath] { return lock }
            let lock = NSLock()
            locksByWorkspace[workspacePath] = lock
            return lock
        }
    }

    private static func mutationID(_ mutation: FeatureMutation) -> String {
        switch mutation {
        case .add(let feature): return feature.id
        case .update(let expected, _): return expected.id
        case .setStatus(let id, _, _), .revertCompletion(let id, _), .cancel(let id, _): return id
        }
    }

    private static func auditAction(_ mutation: FeatureMutation) -> String {
        switch mutation {
        case .add: return "feature.added"
        case .update: return "feature.updated"
        case .setStatus: return "feature.status_changed"
        case .revertCompletion: return "feature.completion_reverted"
        case .cancel: return "feature.cancelled"
        }
    }

    private static func auditSummary(_ mutation: FeatureMutation) -> String {
        "Confirmed feature mutation: \(auditAction(mutation))"
    }

    private static func completionEvidenceIDs(_ evidence: FeatureEvidence) -> [String] {
        Array(Set(
            evidence.linkedTaskIDs
                + evidence.relatedChangeIDs
                + evidence.requiredTestIDs
                + evidence.formalSQLPaths
                + evidence.rollbackSQLPaths
                + evidence.documentationPaths
        )).sorted()
    }

    private static func completionEvidenceSummary(_ evidence: FeatureEvidence) -> String {
        "Automatic completion evidence: \(completionEvidenceIDs(evidence).joined(separator: ", "))"
    }
}

private struct FileIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
}

private struct FileContentFingerprint: Equatable {
    let byteCount: Int
    let sha256: String

    init(byteCount: Int, sha256: String) {
        self.byteCount = byteCount
        self.sha256 = sha256
    }

    init(data: Data) {
        byteCount = data.count
        sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct OpenTemporaryFile {
    let fd: Int32
    let identity: FileIdentity
    let fingerprint: FileContentFingerprint
}

private enum EntryKind {
    case missing
    case regular
    case other
}

private enum NativeFeatureStoreError: LocalizedError {
    case unconfirmed
    case unconfirmedProposal
    case invalidWorkspace(String)
    case unreadable(String)
    case notRegularFile(String)
    case invalidUTF8(String)
    case invalidDocument(String)
    case invalidHeading(String)
    case invalidID(String)
    case duplicateID(String)
    case duplicateMetadata(String, String)
    case missingRequired(String, String)
    case invalidMetadata(String, String)
    case staleRevision(expected: String, current: String)
    case staleDraftRevision(expected: String, current: String)
    case staleFeature(String)
    case featureNotFound(String)
    case changedID
    case malformedPlan(String)
    case missingDraft(String)
    case unknownConfirmedFeature(String)
    case invalidProposalSelection
    case invalidProposalReplacement(String)
    case publicationConflict(String)
    case recoveryRequired(String, String)
    case archiveExists(String)
    case archiveConflict(String)
    case archiveRecoveryRequired(String)

    var errorDescription: String? {
        switch self {
        case .unconfirmed: return "feature write requires explicit confirmation"
        case .unconfirmedProposal: return "feature proposal merge requires explicit confirmation"
        case .invalidWorkspace(let path): return "workspace is not a regular directory: \(path)"
        case .unreadable(let path): return "feature document is unreadable: \(path)"
        case .notRegularFile(let path): return "feature document is not a regular file: \(path)"
        case .invalidUTF8(let path): return "feature document is not valid UTF-8: \(path)"
        case .invalidDocument(let reason): return reason
        case .invalidHeading(let heading): return "invalid feature heading: \(heading)"
        case .invalidID(let id): return "invalid feature ID: \(id)"
        case .duplicateID(let id): return "duplicate feature ID: \(id)"
        case .duplicateMetadata(let label, let id): return "duplicate \(label) metadata for \(id)"
        case .missingRequired(let field, let id): return "missing \(field) metadata for \(id)"
        case .invalidMetadata(let field, let id): return "invalid \(field) metadata for \(id)"
        case .staleRevision(let expected, let current):
            return "FEATURES.md changed since confirmation; expected \(expected); current \(current)"
        case .staleDraftRevision(let expected, let current):
            return "FEATURES.draft.md changed since confirmation; expected \(expected); current \(current)"
        case .staleFeature(let id): return "feature changed since confirmation: \(id)"
        case .featureNotFound(let id): return "feature not found: \(id)"
        case .changedID: return "feature IDs cannot be changed"
        case .malformedPlan(let path): return "malformed feature write plan: \(path)"
        case .missingDraft(let path): return "feature proposal draft is missing: \(path)"
        case .unknownConfirmedFeature(let id):
            return "proposal references unknown confirmed feature ID: \(id)"
        case .invalidProposalSelection: return "feature proposal selection is invalid"
        case .invalidProposalReplacement(let id): return "feature proposal replacement is invalid: \(id)"
        case .publicationConflict(let path): return "FEATURES.md publication conflict: \(path)"
        case .recoveryRequired(let path, let temporaryName):
            return "FEATURES.md recovery required for \(path); staged file: \(temporaryName)"
        case .archiveExists(let path): return "feature proposal archive already exists: \(path)"
        case .archiveConflict(let path): return "feature proposal archive conflict: \(path)"
        case .archiveRecoveryRequired(let path):
            return "feature proposal archive recovery required: \(path)"
        }
    }
}
