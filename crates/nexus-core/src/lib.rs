mod agent;
mod audit;
mod automation;
mod demand;
mod documents;
mod git;
mod index;
mod settings;
mod widget;
mod workspace;

pub use agent::{
    agent_event_handoff_prompt, agent_event_task_draft, agent_events_path, append_agent_event,
    append_agent_event_from_root, read_agent_events, read_agent_events_from_root, AgentEvent,
    AgentEventHandoffPromptResponse, AgentEventInput, AgentEventTaskDraftResponse,
    AgentEventTaskTarget, AppendAgentEventResponse, AGENT_EVENTS_FILE,
};
pub use audit::{
    append_audit_event, append_audit_event_from_root, audit_log_path, read_audit_events,
    read_audit_events_from_root, AppendAuditEventResponse, AuditEvent, AuditEventInput,
    AUDIT_LOG_FILE,
};
pub use automation::{
    local_automation_check, LocalAutomationCheckRequest, LocalAutomationCheckResponse,
    LocalAutomationSignal,
};
pub use demand::{
    initialize_demand_intake, read_demand_intake_status, DemandIntakeFileStatus,
    DemandIntakeStatus, InitializeDemandIntakeRequest, InitializeDemandIntakeResponse,
};
pub use documents::{
    create_workspace_document, read_document, CreateWorkspaceDocumentRequest,
    CreateWorkspaceDocumentResponse, DocumentSnapshot,
};
pub use git::{
    expand_user_path, git_status, normalize_git_branch, scan_source_repos, target_branch_confirmed,
    target_branch_exists, GitStatus, SourceRepo,
};
pub use index::{
    rebuild_search_index, search_index, RebuildSearchIndexResponse, SearchResult,
    DEFAULT_INDEX_FILE,
};
pub use settings::{
    export_settings_profile, ExportSettingsProfileResponse, SettingsProfile,
    SettingsProfileSettings,
};
pub use widget::{widget_snapshot_from_dashboard, WidgetSnapshot};
pub use workspace::{
    append_agent_task_draft, create_workspace, scan_workspaces, scan_workspaces_with_audit,
    setup_worktrees, update_workspace_lifecycle, update_workspace_task,
    workspace_task_handoff_prompt, worktree_commands, AppendAgentTaskDraftRequest,
    AppendAgentTaskDraftResponse, CreateWorkspaceRequest, CreateWorkspaceResponse, DashboardData,
    GitRow, SetupWorktreesRequest, SetupWorktreesResponse, TaskCounts,
    UpdateWorkspaceLifecycleRequest, UpdateWorkspaceLifecycleResponse, UpdateWorkspaceTaskRequest,
    UpdateWorkspaceTaskResponse, WorkspaceActivity, WorkspaceData, WorkspaceHealthCheck,
    WorkspaceLifecycle, WorkspaceSessionAction, WorkspaceTask, WorkspaceTaskHandoffPromptRequest,
    WorkspaceTaskHandoffPromptResponse, WorktreeSetupResult,
};
