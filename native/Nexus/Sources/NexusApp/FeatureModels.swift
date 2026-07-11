import Foundation

enum FeatureStatus: String, CaseIterable, Hashable, Sendable {
    case draft
    case todo
    case inProgress = "in_progress"
    case verifying
    case done
    case blocked
    case cancelled
}

enum FeatureVerificationPolicy: String, CaseIterable, Hashable, Sendable {
    case code
    case sql
    case documentation
    case manual
}

struct WorkspaceFeature: Identifiable, Hashable, Sendable {
    let id: String
    var title: String
    var status: FeatureStatus
    var verification: FeatureVerificationPolicy
    var autoComplete: Bool
    var sources: [String]
    var services: [String]
    var taskIDs: [String]
    var evidenceIDs: [String]
    var description: String
    var completedAt: String?
    var completedBy: String?
    var completionNote: String?
    var evidenceStale: Bool
    var preservedLines: [String]
}

struct FeatureDocument: Hashable, Sendable {
    var preamble: [String]
    var features: [WorkspaceFeature]

    static let empty = FeatureDocument(preamble: ["# Features", ""], features: [])
}

enum FeatureDocumentRevision: Hashable, Sendable {
    case missing
    case regularUTF8(sha256: String, byteCount: Int)
    case invalid(reason: String)

    var label: String {
        switch self {
        case .missing:
            return "missing"
        case .regularUTF8(let sha256, let byteCount):
            return "regular UTF-8 \(byteCount) bytes sha256=\(sha256)"
        case .invalid(let reason):
            return "invalid: \(reason)"
        }
    }
}

struct FeatureDocumentSnapshot: Hashable, Sendable {
    let document: FeatureDocument
    let revision: FeatureDocumentRevision
    let path: String
}

enum FeatureMutation: Hashable, Sendable {
    case add(WorkspaceFeature)
    case update(expected: WorkspaceFeature, replacement: WorkspaceFeature)
    case setStatus(id: String, status: FeatureStatus, completionNote: String?)
    case cancel(id: String, reason: String)
}

struct FeatureWritePlan: Hashable, Sendable {
    let workspacePath: String
    let path: String
    let revision: FeatureDocumentRevision
    let document: FeatureDocument
    let expectedFeature: WorkspaceFeature?
    let mutation: FeatureMutation
}

struct FeatureWriteResponse: Hashable, Sendable {
    let path: String
    let revision: FeatureDocumentRevision
    let document: FeatureDocument
    let auditEventID: String?
    let auditEventPath: String?
    let auditError: String?
}
