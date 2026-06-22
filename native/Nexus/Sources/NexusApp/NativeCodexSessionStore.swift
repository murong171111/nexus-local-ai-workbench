import Foundation

enum NativeCodexSessionStore {
    static let fileName = "codex-sessions.json"

    static func load(workspacePath: String, fileManager: FileManager = .default) -> [CodexSessionLink] {
        let url = storeURL(workspacePath: workspacePath)
        guard fileManager.fileExists(atPath: url.path),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        if let store = try? decoder.decode(CodexSessionLinkStore.self, from: data) {
            return store.sessions
        }

        if let legacySessions = try? decoder.decode([CodexSessionLink].self, from: data) {
            return legacySessions
        }

        return []
    }

    static func write(
        _ links: [CodexSessionLink],
        workspacePath: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let workspaceURL = localFileURL(for: workspacePath)
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: workspaceURL.path, isDirectory: &isDirectory),
              isDirectory.boolValue else {
            throw NSError(
                domain: "NexusCodexSessionLinks",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Workspace folder does not exist: \(workspaceURL.path)"]
            )
        }

        let store = CodexSessionLinkStore(
            schemaVersion: CodexSessionLinkStore.currentSchemaVersion,
            sessions: links
        )
        let data = try encoder.encode(store)
        let url = storeURL(workspacePath: workspacePath)
        try data.write(to: url, options: .atomic)
        return url
    }

    static func storeURL(workspacePath: String) -> URL {
        localFileURL(for: workspacePath)
            .appendingPathComponent(fileName)
    }

    private static func localFileURL(for rawPath: String) -> URL {
        let trimmed = rawPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let expanded: String
        if trimmed == "~" {
            expanded = FileManager.default.homeDirectoryForCurrentUser.path
        } else if trimmed.hasPrefix("~/") {
            expanded = FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent(String(trimmed.dropFirst(2)))
                .path
        } else {
            expanded = trimmed
        }
        return URL(fileURLWithPath: expanded)
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        JSONDecoder()
    }
}
