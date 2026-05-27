import Darwin
import Foundation

public protocol NexusBridge {
    var modeDescription: String { get }

    func scanWorkspaces(request: ScanWorkspacesRequest) async throws -> DashboardSnapshot
    func scanSourceRepos(request: ScanSourceReposRequest) async throws -> [SourceRepositorySnapshot]
    func readDocument(request: ReadDocumentRequest) async throws -> DocumentSnapshot
    func widgetSnapshot(request: WidgetSnapshotRequest) async throws -> WidgetSnapshot
    func createWorkspace(request: CreateWorkspaceRequest) async throws -> CreateWorkspaceResponse
}

public enum NexusBridgeFactory {
    public static func makeDefault(environment: [String: String] = ProcessInfo.processInfo.environment) -> NexusBridge {
        guard let libraryPath = environment["NEXUS_CORE_LIBRARY"], !libraryPath.isEmpty else {
            return PreviewNexusBridge()
        }

        do {
            return try DynamicLibraryNexusBridge(libraryPath: libraryPath)
        } catch {
            return PreviewNexusBridge(modeDetail: "Preview fallback: \(error.localizedDescription)")
        }
    }
}

public final class PreviewNexusBridge: NexusBridge {
    public let modeDescription: String

    public init(modeDetail: String = "Preview bridge: set NEXUS_CORE_LIBRARY to load Rust Core") {
        self.modeDescription = modeDetail
    }

    public func scanWorkspaces(request: ScanWorkspacesRequest) async throws -> DashboardSnapshot {
        DashboardSnapshot.preview(
            workspacesRoot: request.workspacesRoot,
            sourceReposRoot: request.sourceReposRoot,
            docsRoot: request.docsRoot
        )
    }

    public func scanSourceRepos(request: ScanSourceReposRequest) async throws -> [SourceRepositorySnapshot] {
        [
            SourceRepositorySnapshot(
                name: "order",
                path: "\(request.sourceReposRoot)/order",
                isGit: true,
                branch: "feature/yibao-pay-log",
                dirty: false,
                summary: "clean"
            ),
            SourceRepositorySnapshot(
                name: "store-cashier",
                path: "\(request.sourceReposRoot)/store-cashier",
                isGit: true,
                branch: "feature/yibao-pay-log",
                dirty: true,
                summary: "dirty"
            )
        ]
    }

    public func readDocument(request: ReadDocumentRequest) async throws -> DocumentSnapshot {
        DocumentSnapshot(
            path: request.path,
            name: URL(fileURLWithPath: request.path).lastPathComponent,
            extension: URL(fileURLWithPath: request.path).pathExtension,
            isMarkdown: true,
            content: "# Preview Document\n\nSet NEXUS_CORE_LIBRARY to read real workspace documents through Rust Core."
        )
    }

    public func widgetSnapshot(request: WidgetSnapshotRequest) async throws -> WidgetSnapshot {
        let dashboard = DashboardSnapshot.preview(
            workspacesRoot: request.workspacesRoot,
            sourceReposRoot: request.sourceReposRoot,
            docsRoot: request.docsRoot
        )
        return WidgetSnapshot.preview(
            dashboard: dashboard,
            activeFolder: request.activeFolder,
            generatedAt: request.generatedAt
        )
    }

    public func createWorkspace(request: CreateWorkspaceRequest) async throws -> CreateWorkspaceResponse {
        guard request.confirmed else {
            throw NexusBridgeError.coreError("workspace creation requires explicit confirmation")
        }
        throw NexusBridgeError.coreError("Create workspace requires Rust Core bridge. Set NEXUS_CORE_LIBRARY to a local libnexus_ffi.dylib.")
    }
}

public final class DynamicLibraryNexusBridge: NexusBridge {
    private typealias BridgeCall = @convention(c) (UnsafePointer<CChar>?) -> UnsafeMutablePointer<CChar>?
    private typealias BridgeFree = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    private let handle: UnsafeMutableRawPointer
    private let scanWorkspacesFunction: BridgeCall
    private let scanSourceReposFunction: BridgeCall
    private let readDocumentFunction: BridgeCall
    private let widgetSnapshotFunction: BridgeCall
    private let createWorkspaceFunction: BridgeCall
    private let freeFunction: BridgeFree
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    public let modeDescription: String

    public init(libraryPath: String) throws {
        guard let handle = dlopen(libraryPath, RTLD_NOW | RTLD_LOCAL) else {
            throw NexusBridgeError.loadFailed(String(cString: dlerror()))
        }

        do {
            self.handle = handle
            self.scanWorkspacesFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_scan_workspaces_json"
            )
            self.scanSourceReposFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_scan_source_repos_json"
            )
            self.readDocumentFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_read_document_json"
            )
            self.widgetSnapshotFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_widget_snapshot_json"
            )
            self.createWorkspaceFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_create_workspace_json"
            )
            self.freeFunction = try Self.loadSymbol(handle: handle, name: "nexus_string_free")
            self.modeDescription = "Rust Core bridge: \(libraryPath)"
        } catch {
            dlclose(handle)
            throw error
        }
    }

    deinit {
        dlclose(handle)
    }

    public func scanWorkspaces(request: ScanWorkspacesRequest) async throws -> DashboardSnapshot {
        try call(scanWorkspacesFunction, request: request)
    }

    public func scanSourceRepos(request: ScanSourceReposRequest) async throws -> [SourceRepositorySnapshot] {
        try call(scanSourceReposFunction, request: request)
    }

    public func readDocument(request: ReadDocumentRequest) async throws -> DocumentSnapshot {
        try call(readDocumentFunction, request: request)
    }

    public func widgetSnapshot(request: WidgetSnapshotRequest) async throws -> WidgetSnapshot {
        try call(widgetSnapshotFunction, request: request)
    }

    public func createWorkspace(request: CreateWorkspaceRequest) async throws -> CreateWorkspaceResponse {
        try call(createWorkspaceFunction, request: request)
    }

    private static func loadSymbol<T>(handle: UnsafeMutableRawPointer, name: String) throws -> T {
        guard let symbol = dlsym(handle, name) else {
            throw NexusBridgeError.missingSymbol(name)
        }
        return unsafeBitCast(symbol, to: T.self)
    }

    private func call<Request: Encodable, Response: Decodable>(
        _ function: BridgeCall,
        request: Request
    ) throws -> Response {
        let requestData = try encoder.encode(request)
        guard let requestJSON = String(data: requestData, encoding: .utf8) else {
            throw NexusBridgeError.encodingFailed
        }

        let responsePointer = requestJSON.withCString { pointer in
            function(pointer)
        }

        guard let responsePointer else {
            throw NexusBridgeError.nullResponse
        }
        defer {
            freeFunction(responsePointer)
        }

        let responseJSON = String(cString: responsePointer)
        let responseData = Data(responseJSON.utf8)
        let envelope = try decoder.decode(BridgeEnvelope<Response>.self, from: responseData)
        if envelope.ok, let data = envelope.data {
            return data
        }

        throw NexusBridgeError.coreError(envelope.error ?? "unknown Nexus Core bridge error")
    }
}

private struct BridgeEnvelope<T: Decodable>: Decodable {
    let ok: Bool
    let data: T?
    let error: String?
}

public enum NexusBridgeError: LocalizedError, Equatable {
    case loadFailed(String)
    case missingSymbol(String)
    case encodingFailed
    case nullResponse
    case coreError(String)

    public var errorDescription: String? {
        switch self {
        case let .loadFailed(message):
            "Could not load Nexus Core library: \(message)"
        case let .missingSymbol(name):
            "Nexus Core library is missing symbol: \(name)"
        case .encodingFailed:
            "Could not encode bridge request"
        case .nullResponse:
            "Nexus Core bridge returned a null response"
        case let .coreError(message):
            message
        }
    }
}
