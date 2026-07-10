import Foundation
import NexusBridge

struct NativeWorkspaceTaskRow {
    let index: Int
    let sourceLine: Int
    let cells: [String]
    let snapshot: WorkspaceTaskSnapshot
}

enum NativeWorkspaceTaskParser {
    static func rows(from content: String, folder: String) -> [NativeWorkspaceTaskRow] {
        var result: [NativeWorkspaceTaskRow] = []
        var taskIndex = 0

        for (lineIndex, line) in content.components(separatedBy: "\n").enumerated() {
            guard let cells = tableRowCells(line) else { continue }
            let index = taskIndex
            taskIndex += 1
            let sourceLine = lineIndex + 1
            guard let snapshot = snapshot(
                folder: folder,
                index: index,
                sourceLine: sourceLine,
                cells: cells
            ) else {
                continue
            }
            result.append(
                NativeWorkspaceTaskRow(
                    index: index,
                    sourceLine: sourceLine,
                    cells: cells,
                    snapshot: snapshot
                )
            )
        }
        return result
    }

    static func snapshots(from content: String, folder: String) -> [WorkspaceTaskSnapshot] {
        rows(from: content, folder: folder).map(\.snapshot)
    }

    static func snapshot(
        folder: String,
        index: Int,
        sourceLine: Int,
        cells: [String]
    ) -> WorkspaceTaskSnapshot? {
        guard let rawTitle = cells.first else { return nil }
        let title = sanitizedCell(rawTitle)
        guard !title.isEmpty else { return nil }
        let status = cells.indices.contains(1)
            ? sanitizedCell(cells[1])
            : "待办"
        let detail = cells.indices.contains(2)
            ? sanitizedCell(cells[2])
            : ""
        let sourceEventID = markerValue(in: detail, marker: "event=")
        return WorkspaceTaskSnapshot(
            id: sourceEventID.map { "\(folder):\($0)" } ?? "\(folder):task-\(index)",
            title: title,
            status: status,
            detail: detail,
            priority: priority(cells: cells, status: status, detail: detail),
            source: sourceEventID == nil ? "workspace" : "agent",
            sourceEventId: sourceEventID,
            sourceLine: sourceLine
        )
    }

    static func sanitizedCell(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\r", with: " ")
            .replacingOccurrences(of: "|", with: "/")
            .replacingOccurrences(of: "`", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func formattedRow(_ cells: [String]) -> String {
        "| \(cells.map(sanitizedCell).joined(separator: " | ")) |"
    }

    private static func tableRowCells(_ line: String) -> [String]? {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("|"),
              trimmed.contains("|"),
              !isTableDivider(trimmed) else {
            return nil
        }
        let cells = trimmed
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { sanitizedCell(String($0)) }
        guard !cells.isEmpty,
              !["服务", "任务", "需求", "场景", "时间", "工作区"].contains(cells[0]) else {
            return nil
        }
        return cells
    }

    private static func isTableDivider(_ line: String) -> Bool {
        let cells = line
            .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
            .split(separator: "|", omittingEmptySubsequences: false)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return !cells.isEmpty && cells.allSatisfy { cell in
            !cell.isEmpty && cell.allSatisfy { character in
                character == "-" || character == ":" || character == " "
            }
        }
    }

    private static func priority(cells: [String], status: String, detail: String) -> String {
        if cells.indices.contains(3) {
            let explicit = sanitizedCell(cells[3]).lowercased()
            if ["high", "medium", "normal", "low"].contains(explicit) {
                return explicit
            }
        }
        if let marked = markerValue(in: detail, marker: "priority=")?.lowercased(),
           ["high", "medium", "normal", "low"].contains(marked) {
            return marked
        }
        let joined = "\(status) \(detail)".lowercased()
        if joined.contains("阻塞") || joined.contains("blocked") {
            return "high"
        }
        if joined.contains("进行中") || joined.contains("doing") {
            return "medium"
        }
        return "normal"
    }

    private static func markerValue(in text: String, marker: String) -> String? {
        guard let markerRange = text.range(of: marker) else { return nil }
        let rest = text[markerRange.upperBound...]
        let end = rest.firstIndex { character in
            character.isWhitespace || character == "·" || character == ";"
                || character == "," || character == "|"
        } ?? rest.endIndex
        let value = rest[..<end].trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
}
