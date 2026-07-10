import Foundation

struct DemandInputDraft: Hashable {
    var requirement: String
    var links: [String]
    var attachments: [String]

    static let empty = DemandInputDraft(requirement: "", links: [], attachments: [])
}

enum DemandInputRevision: Hashable {
    case missing
    case regularUTF8(sha256: String, byteCount: Int)
    case invalid(reason: String)

    var label: String {
        switch self {
        case .missing:
            "missing"
        case .regularUTF8(let sha256, let byteCount):
            "regular UTF-8 \(byteCount) bytes sha256=\(sha256)"
        case .invalid(let reason):
            "invalid: \(reason)"
        }
    }
}

struct DemandInputSnapshot: Hashable {
    let draft: DemandInputDraft
    let revision: DemandInputRevision
    let path: String
}

struct DemandInputSaveResponse: Hashable {
    let path: String
    let revision: DemandInputRevision
    let auditEventID: String?
    let auditEventPath: String?
    let auditError: String?
}

struct DemandAttachmentPlan: Hashable {
    let workspacePath: String
    let expectedDraftRevision: DemandInputRevision
    let items: [DemandAttachmentPlanItem]
}

struct DemandAttachmentPlanItem: Hashable {
    let sourceURL: URL
    let destinationURL: URL
    let expectedSizeBytes: Int
    let expectedSHA256: String
}

struct DemandAttachmentCopyError: Hashable {
    let sourcePath: String
    let message: String
}

struct DemandAttachmentCopyResponse: Hashable {
    let copiedPaths: [String]
    let errors: [DemandAttachmentCopyError]
    let auditEventID: String?
    let auditEventPath: String?
    let auditError: String?
}
