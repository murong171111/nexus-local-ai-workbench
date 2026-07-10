import Foundation
import NexusBridge

struct NativeAuditAppendFeedback {
    let response: AppendAuditEventResponse?
    let error: String?
}

enum NativeAuditEventStore {
    static let fileName = "audit-events.jsonl"

    static func append(
        auditRoot: String,
        event input: AuditEventInput,
        fileManager: FileManager = .default,
        now: Date = Date(),
        id: String = UUID().uuidString
    ) throws -> AppendAuditEventResponse {
        let rootURL = URL(fileURLWithPath: auditRoot)
        try fileManager.createDirectory(at: rootURL, withIntermediateDirectories: true)
        let event = AuditEvent(
            id: id,
            timestamp: ISO8601DateFormatter().string(from: now),
            actor: input.actor,
            action: input.action,
            target: input.target,
            summary: input.summary,
            metadata: input.metadata
        )
        let fileURL = rootURL.appendingPathComponent(fileName)
        let line = try encoder.encode(event) + Data([0x0A])
        if fileManager.fileExists(atPath: fileURL.path) {
            let handle = try FileHandle(forWritingTo: fileURL)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: line)
        } else {
            try line.write(to: fileURL, options: .atomic)
        }
        return AppendAuditEventResponse(path: fileURL.path, event: event)
    }

    static func appendFeedback(
        auditRoot: String?,
        event: AuditEventInput
    ) -> NativeAuditAppendFeedback {
        guard let auditRoot = auditRoot?.trimmingCharacters(in: .whitespacesAndNewlines),
              !auditRoot.isEmpty else {
            return NativeAuditAppendFeedback(response: nil, error: nil)
        }
        do {
            return NativeAuditAppendFeedback(
                response: try append(auditRoot: auditRoot, event: event),
                error: nil
            )
        } catch {
            return NativeAuditAppendFeedback(response: nil, error: error.localizedDescription)
        }
    }

    static func loadRecent(
        auditRoot: String,
        limit: Int,
        fileManager: FileManager = .default
    ) throws -> [AuditEvent] {
        guard limit > 0 else { return [] }
        let fileURL = URL(fileURLWithPath: auditRoot).appendingPathComponent(fileName)
        guard fileManager.fileExists(atPath: fileURL.path) else {
            return []
        }

        let payload = try String(contentsOf: fileURL, encoding: .utf8)
        let events = payload
            .split(separator: "\n")
            .compactMap { line in
                try? decoder.decode(AuditEvent.self, from: Data(line.utf8))
            }
        return Array(events.suffix(limit).reversed())
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }
}
