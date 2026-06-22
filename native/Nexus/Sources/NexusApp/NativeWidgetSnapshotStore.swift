import Foundation
import NexusBridge

enum NativeWidgetSnapshotStore {
    static func write(
        snapshot: WidgetSnapshot,
        applicationSupportRoot: String,
        appGroupURL: URL?,
        fileName: String,
        fileManager: FileManager = .default
    ) throws -> [String] {
        let payload = try encoder.encode(snapshot)
        var writtenPaths: [String] = []

        let appSupportURL = URL(fileURLWithPath: applicationSupportRoot, isDirectory: true)
        let appSupportSnapshotURL = try write(
            payload: payload,
            to: appSupportURL,
            fileName: fileName,
            fileManager: fileManager
        )
        writtenPaths.append(appSupportSnapshotURL.path)

        if let appGroupURL {
            let appGroupSnapshotURL = try write(
                payload: payload,
                to: appGroupURL,
                fileName: fileName,
                fileManager: fileManager
            )
            writtenPaths.append(appGroupSnapshotURL.path)
        }

        return writtenPaths
    }

    private static func write(
        payload: Data,
        to directoryURL: URL,
        fileName: String,
        fileManager: FileManager
    ) throws -> URL {
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)
        let snapshotURL = directoryURL.appendingPathComponent(fileName)
        try payload.write(to: snapshotURL, options: .atomic)
        return snapshotURL
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
