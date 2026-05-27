mod audit;
mod documents;
mod git;
mod index;
mod settings;
mod widget;
mod workspace;

pub use audit::{
    append_audit_event, append_audit_event_from_root, audit_log_path, read_audit_events,
    read_audit_events_from_root, AppendAuditEventResponse, AuditEvent, AuditEventInput,
    AUDIT_LOG_FILE,
};
pub use documents::{read_document, DocumentSnapshot};
pub use git::{
    expand_user_path, git_status, normalize_git_branch, scan_source_repos, target_branch_confirmed,
    GitStatus, SourceRepo,
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
    create_workspace, scan_workspaces, scan_workspaces_with_audit, setup_worktrees,
    worktree_commands, CreateWorkspaceRequest, CreateWorkspaceResponse, DashboardData, GitRow,
    SetupWorktreesRequest, SetupWorktreesResponse, TaskCounts, WorkspaceActivity, WorkspaceData,
    WorkspaceHealthCheck, WorkspaceSessionAction, WorktreeSetupResult,
};
