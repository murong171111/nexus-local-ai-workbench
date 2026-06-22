import Foundation
import NexusBridge

enum NativeDocumentStore {
    private static let markdownExtensions: Set<String> = ["md", "markdown"]

    static func read(path: String, fileManager: FileManager = .default) throws -> DocumentSnapshot {
        let url = expandedURL(for: path)
        let content = try String(contentsOf: url, encoding: .utf8)
        let ext = url.pathExtension.lowercased()
        return DocumentSnapshot(
            path: url.path,
            name: url.lastPathComponent,
            extension: ext,
            isMarkdown: markdownExtensions.contains(ext),
            content: content
        )
    }

    private static func expandedURL(for path: String) -> URL {
        let expandedPath = (path as NSString).expandingTildeInPath
        return URL(fileURLWithPath: expandedPath)
    }
}
