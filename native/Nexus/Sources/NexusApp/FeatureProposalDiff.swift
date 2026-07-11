import Foundation

enum FeatureProposalKind: String, Hashable, Sendable {
    case add
    case change
    case cancel
    case unchanged
}

struct FeatureProposalItem: Identifiable, Hashable, Sendable {
    let id: String
    let kind: FeatureProposalKind
    let confirmed: WorkspaceFeature?
    let proposed: WorkspaceFeature?
    let assignedFeatureID: String?
}

struct FeatureProposalDiff: Hashable, Sendable {
    let items: [FeatureProposalItem]

    static func resolve(confirmed: FeatureDocument, draft: FeatureDocument) -> FeatureProposalDiff {
        let proposedByID = Dictionary(uniqueKeysWithValues: draft.features.map { ($0.id, $0) })
        var items = confirmed.features.map { feature -> FeatureProposalItem in
            guard let proposed = proposedByID[feature.id] else {
                return FeatureProposalItem(
                    id: feature.id,
                    kind: feature.status == .cancelled ? .unchanged : .cancel,
                    confirmed: feature,
                    proposed: nil,
                    assignedFeatureID: nil
                )
            }
            return FeatureProposalItem(
                id: feature.id,
                kind: proposalComparable(feature) == proposalComparable(proposed) ? .unchanged : .change,
                confirmed: feature,
                proposed: proposed,
                assignedFeatureID: nil
            )
        }

        var nextID = (confirmed.features.compactMap { numericFeatureID($0.id) }.max() ?? 0) + 1
        for feature in draft.features where feature.id.hasPrefix("DRAFT-") {
            items.append(
                FeatureProposalItem(
                    id: feature.id,
                    kind: .add,
                    confirmed: nil,
                    proposed: feature,
                    assignedFeatureID: String(format: "F-%03d", nextID)
                )
            )
            nextID += 1
        }
        return FeatureProposalDiff(items: items)
    }

    var actionableItems: [FeatureProposalItem] {
        items.filter { $0.kind != .unchanged }
    }

    private static func numericFeatureID(_ id: String) -> Int? {
        guard id.hasPrefix("F-") else { return nil }
        return Int(id.dropFirst(2))
    }

    private static func proposalComparable(_ feature: WorkspaceFeature) -> WorkspaceFeature {
        var feature = feature
        feature.status = .todo
        feature.completedAt = nil
        feature.completedBy = nil
        feature.completionNote = nil
        feature.evidenceStale = false
        return feature
    }
}

struct FeatureProposalMergePlan: Hashable, Sendable {
    let workspacePath: String
    let confirmedPath: String
    let draftPath: String
    let confirmedRevision: FeatureDocumentRevision
    let draftRevision: FeatureDocumentRevision
    let confirmedDocument: FeatureDocument
    let draftDocument: FeatureDocument
    let additionalFeatures: [WorkspaceFeature]
    let items: [FeatureProposalItem]
    let selectedItemIDs: Set<String>
    let replacements: [String: WorkspaceFeature]
}

struct FeatureProposalMergeResponse: Hashable, Sendable {
    let path: String
    let revision: FeatureDocumentRevision
    let document: FeatureDocument
    let addCount: Int
    let changeCount: Int
    let cancelCount: Int
    let auditEventID: String?
    let auditEventPath: String?
    let auditError: String?
    let archivePath: String?
    let archiveError: String?
}

struct ConfirmedFeatureProposalMerge: Hashable, Sendable {
    let plan: FeatureProposalMergePlan
    let token: Int
}

struct FeatureProposalReview: Hashable, Sendable {
    let diff: FeatureProposalDiff?
    let confirmedRevision: FeatureDocumentRevision?
    let draftRevision: FeatureDocumentRevision?
    let error: String?

    var canConfirm: Bool { diff != nil && error == nil }
}
