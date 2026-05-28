import Darwin
import Foundation

public protocol NexusBridge {
    var modeDescription: String { get }

    func scanWorkspaces(request: ScanWorkspacesRequest) async throws -> DashboardSnapshot
    func scanSourceRepos(request: ScanSourceReposRequest) async throws -> [SourceRepositorySnapshot]
    func readDocument(request: ReadDocumentRequest) async throws -> DocumentSnapshot
    func widgetSnapshot(request: WidgetSnapshotRequest) async throws -> WidgetSnapshot
    func appendAuditEvent(request: AppendAuditEventRequest) async throws -> AppendAuditEventResponse
    func appendAgentEvent(request: AppendAgentEventRequest) async throws -> AppendAgentEventResponse
    func readAgentEvents(request: ReadAgentEventsRequest) async throws -> [AgentEvent]
    func agentEventHandoffPrompt(request: AgentEventHandoffPromptRequest) async throws -> AgentEventHandoffPromptResponse
    func agentEventTaskDraft(request: AgentEventTaskDraftRequest) async throws -> AgentEventTaskDraftResponse
    func appendAgentTaskDraft(request: AppendAgentTaskDraftRequest) async throws -> AppendAgentTaskDraftResponse
    func updateWorkspaceTask(request: UpdateWorkspaceTaskRequest) async throws -> UpdateWorkspaceTaskResponse
    func workspaceTaskHandoffPrompt(request: WorkspaceTaskHandoffPromptRequest) async throws -> WorkspaceTaskHandoffPromptResponse
    func rebuildSearchIndex(request: RebuildSearchIndexRequest) async throws -> RebuildSearchIndexResponse
    func searchIndex(request: SearchIndexRequest) async throws -> [SearchResult]
    func createWorkspace(request: CreateWorkspaceRequest) async throws -> CreateWorkspaceResponse
    func setupWorktrees(request: SetupWorktreesRequest) async throws -> SetupWorktreesResponse
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

    public func appendAuditEvent(request: AppendAuditEventRequest) async throws -> AppendAuditEventResponse {
        throw NexusBridgeError.coreError("Audit logging requires Rust Core bridge. Set NEXUS_CORE_LIBRARY to a local libnexus_ffi.dylib.")
    }

    public func appendAgentEvent(request: AppendAgentEventRequest) async throws -> AppendAgentEventResponse {
        throw NexusBridgeError.coreError("Agent event logging requires Rust Core bridge. Set NEXUS_CORE_LIBRARY to a local libnexus_ffi.dylib.")
    }

    public func readAgentEvents(request: ReadAgentEventsRequest) async throws -> [AgentEvent] {
        [
            AgentEvent(
                id: "preview-agent-event",
                timestamp: "preview",
                source: "codex",
                sessionId: "preview-session",
                workspaceFolder: request.workspaceFolder ?? "2026-05-25-yibao-pay-log",
                kind: "permission",
                title: "Agent event preview",
                summary: "Set NEXUS_CORE_LIBRARY to read real local agent hook events.",
                severity: "info",
                metadata: [
                    "workspaceFolder": request.workspaceFolder ?? "2026-05-25-yibao-pay-log",
                    "documentPath": "~/ks_project/workspaces/2026-05-25-yibao-pay-log/handoff.md",
                    "docs": "https://github.com/murong171111/nexus-local-ai-workbench"
                ]
            )
        ]
    }

    public func agentEventHandoffPrompt(request: AgentEventHandoffPromptRequest) async throws -> AgentEventHandoffPromptResponse {
        AgentEventHandoffPromptResponse(prompt: request.event.fallbackHandoffPrompt)
    }

    public func agentEventTaskDraft(request: AgentEventTaskDraftRequest) async throws -> AgentEventTaskDraftResponse {
        request.event.fallbackTaskDraft
    }

    public func appendAgentTaskDraft(request: AppendAgentTaskDraftRequest) async throws -> AppendAgentTaskDraftResponse {
        guard request.confirmed else {
            throw NexusBridgeError.coreError("agent task draft append requires explicit confirmation")
        }
        throw NexusBridgeError.coreError("Agent task writeback requires Rust Core bridge. Set NEXUS_CORE_LIBRARY to a local libnexus_ffi.dylib.")
    }

    public func updateWorkspaceTask(request: UpdateWorkspaceTaskRequest) async throws -> UpdateWorkspaceTaskResponse {
        guard request.confirmed else {
            throw NexusBridgeError.coreError("workspace task update requires explicit confirmation")
        }
        throw NexusBridgeError.coreError("Task status updates require Rust Core bridge. Set NEXUS_CORE_LIBRARY to a local libnexus_ffi.dylib.")
    }

    public func workspaceTaskHandoffPrompt(request: WorkspaceTaskHandoffPromptRequest) async throws -> WorkspaceTaskHandoffPromptResponse {
        WorkspaceTaskHandoffPromptResponse(prompt: request.fallbackPrompt)
    }

    public func rebuildSearchIndex(request: RebuildSearchIndexRequest) async throws -> RebuildSearchIndexResponse {
        RebuildSearchIndexResponse(path: request.indexPath, workspaceCount: 0, documentCount: 0)
    }

    public func searchIndex(request: SearchIndexRequest) async throws -> [SearchResult] {
        []
    }

    public func createWorkspace(request: CreateWorkspaceRequest) async throws -> CreateWorkspaceResponse {
        guard request.confirmed else {
            throw NexusBridgeError.coreError("workspace creation requires explicit confirmation")
        }
        throw NexusBridgeError.coreError("Create workspace requires Rust Core bridge. Set NEXUS_CORE_LIBRARY to a local libnexus_ffi.dylib.")
    }

    public func setupWorktrees(request: SetupWorktreesRequest) async throws -> SetupWorktreesResponse {
        guard request.confirmed else {
            throw NexusBridgeError.coreError("worktree setup requires explicit confirmation")
        }
        throw NexusBridgeError.coreError("Worktree setup requires Rust Core bridge. Set NEXUS_CORE_LIBRARY to a local libnexus_ffi.dylib.")
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
    private let appendAuditEventFunction: BridgeCall
    private let appendAgentEventFunction: BridgeCall
    private let readAgentEventsFunction: BridgeCall
    private let agentEventHandoffPromptFunction: BridgeCall
    private let agentEventTaskDraftFunction: BridgeCall
    private let appendAgentTaskDraftFunction: BridgeCall
    private let updateWorkspaceTaskFunction: BridgeCall
    private let workspaceTaskHandoffPromptFunction: BridgeCall
    private let rebuildSearchIndexFunction: BridgeCall
    private let searchIndexFunction: BridgeCall
    private let createWorkspaceFunction: BridgeCall
    private let setupWorktreesFunction: BridgeCall
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
            self.appendAuditEventFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_append_audit_event_json"
            )
            self.appendAgentEventFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_append_agent_event_json"
            )
            self.readAgentEventsFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_read_agent_events_json"
            )
            self.agentEventHandoffPromptFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_agent_event_handoff_prompt_json"
            )
            self.agentEventTaskDraftFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_agent_event_task_draft_json"
            )
            self.appendAgentTaskDraftFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_append_agent_task_draft_json"
            )
            self.updateWorkspaceTaskFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_update_workspace_task_json"
            )
            self.workspaceTaskHandoffPromptFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_workspace_task_handoff_prompt_json"
            )
            self.rebuildSearchIndexFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_rebuild_search_index_json"
            )
            self.searchIndexFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_search_index_json"
            )
            self.createWorkspaceFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_create_workspace_json"
            )
            self.setupWorktreesFunction = try Self.loadSymbol(
                handle: handle,
                name: "nexus_setup_worktrees_json"
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

    public func appendAuditEvent(request: AppendAuditEventRequest) async throws -> AppendAuditEventResponse {
        try call(appendAuditEventFunction, request: request)
    }

    public func appendAgentEvent(request: AppendAgentEventRequest) async throws -> AppendAgentEventResponse {
        try call(appendAgentEventFunction, request: request)
    }

    public func readAgentEvents(request: ReadAgentEventsRequest) async throws -> [AgentEvent] {
        try call(readAgentEventsFunction, request: request)
    }

    public func agentEventHandoffPrompt(request: AgentEventHandoffPromptRequest) async throws -> AgentEventHandoffPromptResponse {
        try call(agentEventHandoffPromptFunction, request: request)
    }

    public func agentEventTaskDraft(request: AgentEventTaskDraftRequest) async throws -> AgentEventTaskDraftResponse {
        try call(agentEventTaskDraftFunction, request: request)
    }

    public func appendAgentTaskDraft(request: AppendAgentTaskDraftRequest) async throws -> AppendAgentTaskDraftResponse {
        try call(appendAgentTaskDraftFunction, request: request)
    }

    public func updateWorkspaceTask(request: UpdateWorkspaceTaskRequest) async throws -> UpdateWorkspaceTaskResponse {
        try call(updateWorkspaceTaskFunction, request: request)
    }

    public func workspaceTaskHandoffPrompt(request: WorkspaceTaskHandoffPromptRequest) async throws -> WorkspaceTaskHandoffPromptResponse {
        try call(workspaceTaskHandoffPromptFunction, request: request)
    }

    public func rebuildSearchIndex(request: RebuildSearchIndexRequest) async throws -> RebuildSearchIndexResponse {
        try call(rebuildSearchIndexFunction, request: request)
    }

    public func searchIndex(request: SearchIndexRequest) async throws -> [SearchResult] {
        try call(searchIndexFunction, request: request)
    }

    public func createWorkspace(request: CreateWorkspaceRequest) async throws -> CreateWorkspaceResponse {
        try call(createWorkspaceFunction, request: request)
    }

    public func setupWorktrees(request: SetupWorktreesRequest) async throws -> SetupWorktreesResponse {
        try call(setupWorktreesFunction, request: request)
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
