import Foundation

enum FeatureCompletionDecision: String, Hashable, Sendable {
    case noChange
    case startProgress
    case keepVerifying
    case autoComplete
    case requiresManualCompletion
    case markEvidenceStale
}

struct FeatureEvidence: Hashable, Sendable {
    let featureID: String
    let workspacePath: String
    let linkedTaskIDs: [String]
    let incompleteTaskIDs: [String]
    let relatedChangeIDs: [String]
    let latestRelatedChangeAt: Date?
    let requiredTestIDs: [String]
    let failedOrMissingTestIDs: [String]
    var latestTestAt: Date?
    let formalSQLPaths: [String]
    let rollbackSQLPaths: [String]
    let documentationPaths: [String]
    let blockers: [String]
    let readErrors: [String]
    let sourceRevisions: [String: String]

    var hasExplicitAttribution: Bool {
        !linkedTaskIDs.isEmpty
            || !relatedChangeIDs.isEmpty
            || !requiredTestIDs.isEmpty
            || !formalSQLPaths.isEmpty
            || !rollbackSQLPaths.isEmpty
            || !documentationPaths.isEmpty
    }
}

struct FeatureCompletionEvaluation: Hashable, Sendable {
    let featureID: String
    let decision: FeatureCompletionDecision
    let reasons: [String]
}

enum FeatureCompletionEvaluator {
    static func evaluate(
        feature: WorkspaceFeature,
        evidence: FeatureEvidence
    ) -> FeatureCompletionEvaluation {
        guard feature.id == evidence.featureID else {
            return result(feature, .keepVerifying, ["Evidence belongs to another feature."])
        }
        if feature.status == .cancelled {
            return result(feature, .noChange, ["Feature is cancelled."])
        }
        if feature.status == .done {
            return doneEvaluation(feature: feature, evidence: evidence)
        }
        if feature.verification == .manual {
            return result(feature, .requiresManualCompletion, ["Manual verification requires user confirmation."])
        }
        if !evidence.readErrors.isEmpty {
            return result(feature, .keepVerifying, evidence.readErrors.map { "Read error: \($0)" })
        }
        if !evidence.blockers.isEmpty {
            return result(feature, .keepVerifying, evidence.blockers.map { "Blocker: \($0)" })
        }
        if !evidence.incompleteTaskIDs.isEmpty {
            return result(
                feature,
                .keepVerifying,
                ["Incomplete tasks: \(evidence.incompleteTaskIDs.sorted().joined(separator: ", "))"]
            )
        }
        guard evidence.hasExplicitAttribution else {
            return result(feature, .noChange, ["No explicitly attributed evidence."])
        }

        let readiness = readiness(feature: feature, evidence: evidence)
        guard readiness.isReady else {
            return result(feature, .keepVerifying, readiness.reasons)
        }
        guard feature.autoComplete else {
            let decision: FeatureCompletionDecision = [.draft, .todo].contains(feature.status)
                ? .startProgress
                : .keepVerifying
            return result(feature, decision, ["Evidence is ready; automatic completion is not authorized."])
        }
        return result(feature, .autoComplete, readiness.reasons)
    }

    private static func readiness(
        feature: WorkspaceFeature,
        evidence: FeatureEvidence
    ) -> (isReady: Bool, reasons: [String]) {
        var missing: [String] = []
        switch feature.verification {
        case .code:
            if evidence.relatedChangeIDs.isEmpty { missing.append("No attributed code change.") }
            if evidence.requiredTestIDs.isEmpty { missing.append("No required test evidence.") }
            if !evidence.failedOrMissingTestIDs.isEmpty {
                missing.append("Failed or missing tests: \(evidence.failedOrMissingTestIDs.sorted().joined(separator: ", "))")
            }
            if let changeAt = evidence.latestRelatedChangeAt {
                guard let testAt = evidence.latestTestAt, testAt >= changeAt else {
                    missing.append("Tests are older than the latest related change.")
                    return (false, missing)
                }
            } else if !evidence.relatedChangeIDs.isEmpty {
                missing.append("Related change time is unavailable.")
            }
        case .sql:
            if evidence.formalSQLPaths.isEmpty { missing.append("Formal SQL is missing.") }
            if evidence.rollbackSQLPaths.isEmpty { missing.append("Rollback SQL is missing.") }
            if evidence.relatedChangeIDs.isEmpty { missing.append("No attributed SQL change.") }
            if evidence.requiredTestIDs.isEmpty { missing.append("SQL validation evidence is missing.") }
            appendTestFailures(evidence, to: &missing)
        case .documentation:
            if evidence.documentationPaths.isEmpty { missing.append("Documentation evidence is missing.") }
            if evidence.relatedChangeIDs.isEmpty { missing.append("No attributed document change.") }
            if evidence.requiredTestIDs.isEmpty { missing.append("Document check evidence is missing.") }
            appendTestFailures(evidence, to: &missing)
        case .manual:
            return (false, ["Manual verification requires user confirmation."])
        }
        return missing.isEmpty
            ? (true, ["All explicit \(feature.verification.rawValue) evidence is current."])
            : (false, missing)
    }

    private static func appendTestFailures(_ evidence: FeatureEvidence, to missing: inout [String]) {
        if !evidence.failedOrMissingTestIDs.isEmpty {
            missing.append("Failed or missing tests: \(evidence.failedOrMissingTestIDs.sorted().joined(separator: ", "))")
        }
        if !evidence.requiredTestIDs.isEmpty,
           let changeAt = evidence.latestRelatedChangeAt,
           evidence.latestTestAt.map({ $0 < changeAt }) ?? true {
            missing.append("Tests are older than the latest related change.")
        }
    }

    private static func doneEvaluation(
        feature: WorkspaceFeature,
        evidence: FeatureEvidence
    ) -> FeatureCompletionEvaluation {
        var staleReasons = evidence.readErrors.map { "Read error: \($0)" }
        staleReasons += evidence.blockers.map { "Blocker: \($0)" }
        if !evidence.incompleteTaskIDs.isEmpty {
            staleReasons.append("Incomplete tasks: \(evidence.incompleteTaskIDs.sorted().joined(separator: ", "))")
        }
        if !evidence.failedOrMissingTestIDs.isEmpty {
            staleReasons.append("Failed or missing tests: \(evidence.failedOrMissingTestIDs.sorted().joined(separator: ", "))")
        }
        if let changeAt = evidence.latestRelatedChangeAt {
            let completedAt = feature.completedAt.flatMap(ISO8601DateFormatter().date(from:))
            let proofAt = [completedAt, evidence.latestTestAt].compactMap { $0 }.max()
            if proofAt.map({ changeAt > $0 }) ?? true {
                staleReasons.append("A related change is newer than completion evidence.")
            }
        }
        guard !staleReasons.isEmpty else {
            return result(feature, .noChange, ["Completion evidence remains current."])
        }
        return feature.evidenceStale
            ? result(feature, .noChange, staleReasons)
            : result(feature, .markEvidenceStale, staleReasons)
    }

    private static func result(
        _ feature: WorkspaceFeature,
        _ decision: FeatureCompletionDecision,
        _ reasons: [String]
    ) -> FeatureCompletionEvaluation {
        FeatureCompletionEvaluation(featureID: feature.id, decision: decision, reasons: reasons)
    }
}
