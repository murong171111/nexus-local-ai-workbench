import Foundation

struct DemandInputDraft: Hashable, Sendable {
    var requirement: String
    var links: [String]
    var attachments: [String]

    static let empty = DemandInputDraft(requirement: "", links: [], attachments: [])
}

enum DemandInputRevision: Hashable, Sendable {
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

struct DemandInputSnapshot: Hashable, Sendable {
    let draft: DemandInputDraft
    let revision: DemandInputRevision
    let path: String
}

struct DemandInputSaveResponse: Hashable, Sendable {
    let path: String
    let revision: DemandInputRevision
    let auditEventID: String?
    let auditEventPath: String?
    let auditError: String?
}

enum DemandInputSaveResult: Hashable, Sendable {
    case saved(DemandInputSnapshot)
    case failed(message: String)

    var succeeded: Bool {
        if case .saved = self { return true }
        return false
    }

    var message: String? {
        if case .failed(let message) = self { return message }
        return nil
    }
}

enum DemandInputSaveStatus: Hashable, Sendable {
    case idle
    case saving
    case saved
    case failed(String)
}

struct DemandAttachmentPlan: Hashable, Sendable {
    let workspacePath: String
    let expectedDraftRevision: DemandInputRevision
    let items: [DemandAttachmentPlanItem]
}

struct DemandAttachmentPlanItem: Hashable, Sendable {
    let sourceURL: URL
    let destinationURL: URL
    let expectedSizeBytes: Int
    let expectedSHA256: String
}

struct DemandAttachmentCopyError: Hashable, Sendable {
    let sourcePath: String
    let message: String
}

struct DemandAttachmentCopyResponse: Hashable, Sendable {
    let copiedPaths: [String]
    let copiedRelativePaths: [String]
    let errors: [DemandAttachmentCopyError]
    let auditEventID: String?
    let auditEventPath: String?
    let auditError: String?
}
