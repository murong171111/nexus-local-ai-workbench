use nexus_core::{
    append_audit_event as append_audit_event_core, create_workspace as create_workspace_core,
    expand_user_path, export_settings_profile as export_settings_profile_core,
    rebuild_search_index as rebuild_search_index_core, scan_source_repos as scan_source_repos_core,
    scan_workspaces_with_audit as scan_workspaces_core, search_index as search_index_core,
    setup_worktrees as setup_worktrees_core, update_workspace_task as update_workspace_task_core,
    AuditEventInput, CreateWorkspaceRequest, CreateWorkspaceResponse, DashboardData,
    ExportSettingsProfileResponse, RebuildSearchIndexResponse, SearchResult, SettingsProfile,
    SetupWorktreesRequest, SetupWorktreesResponse, SourceRepo, UpdateWorkspaceTaskRequest,
    UpdateWorkspaceTaskResponse, WidgetSnapshot, DEFAULT_INDEX_FILE,
};
use serde::{Deserialize, Serialize};
use std::collections::{hash_map::DefaultHasher, BTreeMap};
use std::fs;
use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};
use std::process::Command;
use tauri::Manager;

const CODEX_SESSIONS_FILE: &str = "codex-sessions.json";

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScanWorkspacesRequest {
    workspaces_root: String,
    source_repos_root: String,
    docs_root: String,
    audit_root: Option<String>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScanSourceReposRequest {
    source_repos_root: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct EnvironmentHealthRequest {
    workspaces_root: String,
    source_repos_root: String,
    docs_root: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct RebuildSearchIndexRequest {
    workspaces_root: String,
    source_repos_root: String,
    docs_root: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct SearchIndexRequest {
    query: String,
    limit: Option<usize>,
}

#[derive(Clone, Deserialize)]
struct CreateWorkspaceCommandRequest {
    pub name: String,
    pub folder: String,
    #[serde(alias = "workspacesRoot")]
    pub workspaces_root: String,
    #[serde(alias = "sourceReposRoot")]
    pub source_repos_root: String,
    pub services: Vec<String>,
    #[serde(alias = "targetBranch")]
    pub target_branch: String,
    #[serde(default)]
    pub confirmed: bool,
}

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SetupWorktreesCommandRequest {
    pub workspace_path: String,
    pub source_repos_root: String,
    pub services: Vec<String>,
    pub target_branch: String,
    #[serde(default)]
    pub confirmed: bool,
}

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct DemandIntakeStatusRequest {
    pub workspace_path: String,
}

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct InitializeDemandIntakeRequest {
    pub workspace_path: String,
    #[serde(default)]
    pub demand_name: String,
    #[serde(default)]
    pub lanhu_link: String,
    #[serde(default)]
    pub notes: String,
    #[serde(default)]
    pub confirmed: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct CodexSessionsReadRequest {
    workspace_path: String,
}

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct BindCodexSessionRequest {
    workspace_path: String,
    title: String,
    url: String,
    notes: String,
    confirmed: bool,
}

#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CodexSessionActionRequest {
    workspace_path: String,
    session_id: String,
    confirmed: bool,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct CodexSessionLink {
    id: String,
    title: String,
    url: String,
    notes: String,
    created_at: String,
    last_opened_at: Option<String>,
}

#[derive(Clone, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct CodexSessionLinkStore {
    schema_version: u8,
    sessions: Vec<CodexSessionLink>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CodexSessionStoreResponse {
    path: String,
    sessions: Vec<CodexSessionLink>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct CodexSessionMutationResponse {
    path: String,
    sessions: Vec<CodexSessionLink>,
    link: Option<CodexSessionLink>,
    updated: bool,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppendAuditEventCommandRequest {
    actor: Option<String>,
    action: String,
    target: String,
    summary: String,
    #[serde(default)]
    metadata: BTreeMap<String, String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct PathCheck {
    key: String,
    label: String,
    path: String,
    exists: bool,
    is_dir: bool,
    writable: bool,
    summary: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct ToolCheck {
    key: String,
    label: String,
    available: bool,
    summary: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct EnvironmentHealth {
    generated_at: String,
    ready: bool,
    path_checks: Vec<PathCheck>,
    tool_checks: Vec<ToolCheck>,
    workspace_count: usize,
    source_repo_count: usize,
    blockers: Vec<String>,
    warnings: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct WidgetSnapshotResponse {
    path: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DemandIntakeFileStatus {
    key: String,
    label: String,
    filename: String,
    path: String,
    exists: bool,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DemandIntakeStatus {
    directory_path: String,
    exists: bool,
    ready: bool,
    missing_count: usize,
    files: Vec<DemandIntakeFileStatus>,
}

const DEMAND_INTAKE_DIR: &str = "需求";
const DEMAND_INTAKE_FILES: [(&str, &str, &str); 5] = [
    ("requirement", "需求确认卡", "requirement.md"),
    ("questions", "待确认问题", "questions.md"),
    ("scope", "开发范围", "scope.md"),
    ("tasks", "需求列表", "tasks.md"),
    ("delivery", "需求交付", "delivery.md"),
];

#[tauri::command]
fn open_url(url: String) -> Result<(), String> {
    open_with_system(&url)
}

#[tauri::command]
fn open_path(path: String) -> Result<(), String> {
    open_with_system(&expand_user_path(&path).to_string_lossy())
}

#[tauri::command]
fn open_terminal(path: String) -> Result<(), String> {
    let path = expand_user_path(&path);
    Command::new("open")
        .arg("-a")
        .arg("Terminal")
        .arg(path)
        .status()
        .map_err(|error| error.to_string())
        .and_then(status_to_result)
}

#[tauri::command]
fn open_idea(path: String) -> Result<(), String> {
    let path = expand_user_path(&path);
    Command::new("open")
        .arg("-a")
        .arg("IntelliJ IDEA")
        .arg(path)
        .status()
        .map_err(|error| error.to_string())
        .and_then(status_to_result)
}

#[tauri::command]
fn read_text_file(path: String) -> Result<String, String> {
    let path = expand_user_path(&path);
    if !path.exists() {
        return Err(format!("file does not exist: {}", path.display()));
    }
    if !path.is_file() {
        return Err(format!("path is not a text file: {}", path.display()));
    }
    fs::read_to_string(path).map_err(|error| error.to_string())
}

#[tauri::command]
fn read_demand_intake_status(
    request: DemandIntakeStatusRequest,
) -> Result<DemandIntakeStatus, String> {
    let workspace = checked_workspace_path(&request.workspace_path)?;
    Ok(demand_intake_status_for_workspace(&workspace))
}

#[tauri::command]
fn scan_workspaces(
    app: tauri::AppHandle,
    request: ScanWorkspacesRequest,
) -> Result<DashboardData, String> {
    let app_audit_root = app_audit_root(&app)
        .ok()
        .map(|path| path.to_string_lossy().to_string());
    let audit_root = request.audit_root.as_deref().or(app_audit_root.as_deref());
    scan_workspaces_core(
        &request.workspaces_root,
        &request.source_repos_root,
        &request.docs_root,
        audit_root,
    )
}

#[tauri::command]
fn scan_source_repos(request: ScanSourceReposRequest) -> Result<Vec<SourceRepo>, String> {
    scan_source_repos_core(&request.source_repos_root)
}

#[tauri::command]
fn check_environment(request: EnvironmentHealthRequest) -> Result<EnvironmentHealth, String> {
    let workspace_root = expand_user_path(&request.workspaces_root);
    let source_root = expand_user_path(&request.source_repos_root);
    let path_checks = vec![
        path_check("workspacesRoot", "工作区目录", &request.workspaces_root),
        path_check("sourceReposRoot", "源仓库目录", &request.source_repos_root),
        path_check("docsRoot", "交付文档目录", &request.docs_root),
    ];
    let tool_checks = vec![tool_check("git", "Git", "git", &["--version"])];
    let workspace_count = count_child_dirs(&workspace_root, Some("dashboard"));
    let source_repo_count = count_git_like_dirs(&source_root);

    let mut blockers = Vec::new();
    let mut warnings = Vec::new();
    for check in &path_checks {
        if !check.exists {
            blockers.push(format!("{}不存在: {}", check.label, check.path));
        } else if !check.is_dir {
            blockers.push(format!("{}不是目录: {}", check.label, check.path));
        } else if !check.writable {
            warnings.push(format!("{}可能不可写: {}", check.label, check.path));
        }
    }
    for check in &tool_checks {
        if !check.available {
            blockers.push(format!("{}不可用: {}", check.label, check.summary));
        }
    }
    if source_repo_count == 0 {
        warnings.push("源仓库目录下暂未识别到 git 服务仓库".to_string());
    }

    Ok(EnvironmentHealth {
        generated_at: generated_at(),
        ready: blockers.is_empty(),
        path_checks,
        tool_checks,
        workspace_count,
        source_repo_count,
        blockers,
        warnings,
    })
}

#[tauri::command]
fn rebuild_search_index(
    app: tauri::AppHandle,
    request: RebuildSearchIndexRequest,
) -> Result<RebuildSearchIndexResponse, String> {
    let index_path = app_index_path(&app)?;
    rebuild_search_index_core(
        &index_path.to_string_lossy(),
        &request.workspaces_root,
        &request.source_repos_root,
        &request.docs_root,
    )
}

#[tauri::command]
fn search_index(
    app: tauri::AppHandle,
    request: SearchIndexRequest,
) -> Result<Vec<SearchResult>, String> {
    let index_path = app_index_path(&app)?;
    search_index_core(
        &index_path.to_string_lossy(),
        &request.query,
        request.limit.unwrap_or(20),
    )
}

#[tauri::command]
fn write_widget_snapshot(
    app: tauri::AppHandle,
    snapshot: WidgetSnapshot,
) -> Result<WidgetSnapshotResponse, String> {
    let app_data_dir = app
        .path()
        .app_data_dir()
        .map_err(|error| error.to_string())?;
    fs::create_dir_all(&app_data_dir).map_err(|error| error.to_string())?;
    let snapshot_path = app_data_dir.join("widget-snapshot.json");
    let payload = serde_json::to_string_pretty(&snapshot).map_err(|error| error.to_string())?;
    fs::write(&snapshot_path, payload).map_err(|error| error.to_string())?;
    Ok(WidgetSnapshotResponse {
        path: snapshot_path.to_string_lossy().to_string(),
    })
}

#[tauri::command]
fn export_settings_profile(
    app: tauri::AppHandle,
    profile: SettingsProfile,
) -> Result<ExportSettingsProfileResponse, String> {
    let app_data_dir = app
        .path()
        .app_data_dir()
        .map_err(|error| error.to_string())?;
    let profile_dir = app_data_dir.join("profiles");
    let response = export_settings_profile_core(&profile_dir, &profile)?;
    record_audit_event(
        &app,
        AuditEventInput {
            actor: "Nexus App".to_string(),
            action: "settings_profile.exported".to_string(),
            target: response.path.clone(),
            summary: "Exported a shareable Nexus settings profile".to_string(),
            metadata: audit_metadata(&[
                ("path", response.path.clone()),
                ("workspacesRoot", profile.settings.workspaces_root),
                ("sourceReposRoot", profile.settings.source_repos_root),
                ("docsRoot", profile.settings.docs_root),
            ]),
        },
    );
    Ok(response)
}

#[tauri::command]
fn append_audit_event(
    app: tauri::AppHandle,
    request: AppendAuditEventCommandRequest,
) -> Result<nexus_core::AppendAuditEventResponse, String> {
    let root = app_audit_root(&app)?;
    append_audit_event_core(
        root,
        AuditEventInput {
            actor: request.actor.unwrap_or_else(|| "Nexus App".to_string()),
            action: request.action,
            target: request.target,
            summary: request.summary,
            metadata: request.metadata,
        },
    )
}

#[tauri::command]
fn create_workspace(
    app: tauri::AppHandle,
    request: CreateWorkspaceCommandRequest,
) -> Result<CreateWorkspaceResponse, String> {
    if !request.confirmed {
        return Err("workspace creation requires explicit confirmation".to_string());
    }

    let core_request = CreateWorkspaceRequest {
        name: request.name.clone(),
        folder: request.folder.clone(),
        workspaces_root: request.workspaces_root.clone(),
        source_repos_root: request.source_repos_root.clone(),
        services: request.services.clone(),
        target_branch: request.target_branch.clone(),
    };
    let response = create_workspace_core(core_request)?;
    record_audit_event(
        &app,
        AuditEventInput {
            actor: "Nexus App".to_string(),
            action: "workspace.created".to_string(),
            target: response.path.clone(),
            summary: format!("Created workspace {}", request.name),
            metadata: audit_metadata(&[
                ("name", request.name),
                ("folder", request.folder),
                ("services", request.services.join(",")),
                ("targetBranch", request.target_branch),
                ("workspacesRoot", request.workspaces_root),
                ("sourceReposRoot", request.source_repos_root),
            ]),
        },
    );
    Ok(response)
}

#[tauri::command]
fn setup_worktrees(
    app: tauri::AppHandle,
    request: SetupWorktreesCommandRequest,
) -> Result<SetupWorktreesResponse, String> {
    if !request.confirmed {
        return Err("worktree setup requires explicit confirmation".to_string());
    }

    let response = setup_worktrees_core(SetupWorktreesRequest {
        workspace_path: request.workspace_path.clone(),
        source_repos_root: request.source_repos_root.clone(),
        services: request.services.clone(),
        target_branch: request.target_branch.clone(),
        confirmed: request.confirmed,
    })?;
    record_audit_event(
        &app,
        AuditEventInput {
            actor: "Nexus App".to_string(),
            action: "worktree.setup.executed".to_string(),
            target: response.workspace_path.clone(),
            summary: format!(
                "Created {} worktrees, skipped {}, failed {}",
                response.created.len(),
                response.skipped.len(),
                response.failed.len()
            ),
            metadata: audit_metadata(&[
                ("workspace", response.workspace_path.clone()),
                ("services", request.services.join(",")),
                ("targetBranch", response.target_branch.clone()),
                ("created", response.created.len().to_string()),
                ("skipped", response.skipped.len().to_string()),
                ("failed", response.failed.len().to_string()),
            ]),
        },
    );
    Ok(response)
}

#[tauri::command]
fn initialize_demand_intake(
    app: tauri::AppHandle,
    request: InitializeDemandIntakeRequest,
) -> Result<DemandIntakeStatus, String> {
    if !request.confirmed {
        return Err("demand intake initialization requires explicit confirmation".to_string());
    }

    let workspace = checked_workspace_path(&request.workspace_path)?;
    let demand_dir = workspace.join(DEMAND_INTAKE_DIR);
    if demand_dir.exists() && !demand_dir.is_dir() {
        return Err(format!(
            "demand intake path exists but is not a directory: {}",
            demand_dir.display()
        ));
    }

    fs::create_dir_all(&demand_dir).map_err(|error| error.to_string())?;
    let demand_name = non_empty_or(&request.demand_name, "待补充");
    let lanhu_link = non_empty_or(&request.lanhu_link, "待补充");
    let notes = non_empty_or(&request.notes, "待补充");
    let mut created_files = Vec::new();

    for (key, _label, filename) in DEMAND_INTAKE_FILES {
        let file_path = demand_dir.join(filename);
        if file_path.exists() {
            if !file_path.is_file() {
                return Err(format!(
                    "demand intake file path exists but is not a file: {}",
                    file_path.display()
                ));
            }
            continue;
        }

        fs::write(
            &file_path,
            demand_intake_template(key, &demand_name, &lanhu_link, &notes),
        )
        .map_err(|error| error.to_string())?;
        created_files.push(filename.to_string());
    }

    let status = demand_intake_status_for_workspace(&workspace);
    record_audit_event(
        &app,
        AuditEventInput {
            actor: "Nexus App".to_string(),
            action: "demand_intake.initialized".to_string(),
            target: status.directory_path.clone(),
            summary: format!("Initialized demand intake files for {}", demand_name),
            metadata: audit_metadata(&[
                ("workspacePath", workspace.to_string_lossy().to_string()),
                ("demandName", demand_name),
                ("lanhuLink", lanhu_link),
                ("createdFiles", created_files.join(",")),
                ("missingCount", status.missing_count.to_string()),
            ]),
        },
    );
    Ok(status)
}

fn checked_workspace_path(workspace_path: &str) -> Result<PathBuf, String> {
    let workspace = expand_user_path(workspace_path);
    if !workspace.exists() {
        return Err(format!("workspace does not exist: {}", workspace.display()));
    }
    if !workspace.is_dir() {
        return Err(format!(
            "workspace path is not a directory: {}",
            workspace.display()
        ));
    }
    Ok(workspace)
}

fn demand_intake_status_for_workspace(workspace: &Path) -> DemandIntakeStatus {
    let demand_dir = workspace.join(DEMAND_INTAKE_DIR);
    let exists = demand_dir.is_dir();
    let files = DEMAND_INTAKE_FILES
        .iter()
        .map(|(key, label, filename)| {
            let path = demand_dir.join(filename);
            DemandIntakeFileStatus {
                key: (*key).to_string(),
                label: (*label).to_string(),
                filename: (*filename).to_string(),
                path: path.to_string_lossy().to_string(),
                exists: path.is_file(),
            }
        })
        .collect::<Vec<_>>();
    let missing_count = files.iter().filter(|file| !file.exists).count();
    DemandIntakeStatus {
        directory_path: demand_dir.to_string_lossy().to_string(),
        exists,
        ready: exists && missing_count == 0,
        missing_count,
        files,
    }
}

fn demand_intake_template(key: &str, demand_name: &str, lanhu_link: &str, notes: &str) -> String {
    match key {
        "requirement" => format!(
            "# 需求确认卡：{}\n\n## 1. 需求目标\n\n- 待整理。\n\n## 2. 页面和入口\n\n- 页面：待确认\n- 入口：待确认\n- 角色/权限：待确认\n\n## 3. 用户流程\n\n1. 待整理。\n\n## 4. UI 与交互规则\n\n- 字段：待确认\n- 按钮：待确认\n- 状态：待确认\n- 校验：待确认\n- 空状态/异常：待确认\n\n## 5. 已确认需求点\n\n- 待整理。\n\n## 6. 推断内容\n\n- 暂无。\n\n## 7. 待确认问题\n\n- P0: 待整理\n- P1: 待整理\n- P2: 待整理\n\n## 8. 建议开发范围\n\n- 本次建议实现：待确认\n- 暂不实现：待确认\n\n## 9. 验收标准\n\n- 待整理。\n\n## 输入材料\n\n- 蓝湖链接：{}\n\n### 补充说明\n\n{}\n",
            demand_name, lanhu_link, notes
        ),
        "questions" => format!(
            "# 待确认问题：{}\n\n## P0 阻塞开发\n\n- [ ] 待整理。\n\n## P1 可先做主流程但影响边界\n\n- [ ] 待整理。\n\n## P2 不阻塞开发的细节\n\n- [ ] 待整理。\n\n## 结论\n\n- P0 清零前不要进入编码。\n",
            demand_name
        ),
        "scope" => format!(
            "# 本次开发范围：{}\n\n## 已确认并实现\n\n- 待确认。\n\n## 暂不实现\n\n- 待确认。\n\n## 仍待确认\n\n- 待确认。\n\n## 进入开发条件\n\n- [ ] requirement.md 已整理。\n- [ ] questions.md 中 P0 已清零或有明确处理结论。\n- [ ] 本文件已冻结本次开发范围。\n",
            demand_name
        ),
        "tasks" => format!(
            "# 需求列表：{}\n\n> 由需求预检阶段维护。后续开发按未完成需求顺序推进，完成后回写状态。\n\n| 需求点 | 状态 | 优先级 | 来源 | 说明 |\n| --- | --- | --- | --- | --- |\n| 整理 requirement.md | 待办 | P0 | 需求预检 | 从蓝湖材料和补充说明提炼需求确认卡 |\n| 整理 questions.md | 待办 | P0 | 需求预检 | 按 P0/P1/P2 分级缺口 |\n| 冻结 scope.md | 待办 | P0 | 产品确认 | P0 清零后确认开发范围 |\n\n## 开发顺序规则\n\n- 优先处理状态为 `进行中` 或 `待办` 的 P0/P1 需求点。\n- 开发前先确认 `scope.md` 已冻结。\n- 完成需求点后，将状态更新为 `已完成`，并在 delivery.md 或 交付记录.md 补充结果。\n",
            demand_name
        ),
        "delivery" => format!(
            "# 需求交付记录：{}\n\n## 预检结论\n\n- 待整理。\n\n## 范围确认\n\n- 待整理。\n\n## 开发与验证记录\n\n- 暂无。\n\n## 遗留问题\n\n- 暂无。\n",
            demand_name
        ),
        _ => "# Document\n\n待补充。\n".to_string(),
    }
}

fn non_empty_or(value: &str, fallback: &str) -> String {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        fallback.to_string()
    } else {
        trimmed.to_string()
    }
}

#[tauri::command]
fn update_workspace_task(
    app: tauri::AppHandle,
    request: UpdateWorkspaceTaskRequest,
) -> Result<UpdateWorkspaceTaskResponse, String> {
    if !request.confirmed {
        return Err("workspace task update requires explicit confirmation".to_string());
    }

    let response = update_workspace_task_core(request.clone())?;
    record_audit_event(
        &app,
        AuditEventInput {
            actor: "Nexus App".to_string(),
            action: "workspace.task.updated".to_string(),
            target: response.path.clone(),
            summary: format!(
                "Updated task {} from {} to {}",
                response.task.title, response.previous_status, response.task.status
            ),
            metadata: audit_metadata(&[
                ("workspace", request.workspace_path),
                ("taskId", request.task_id),
                ("previousStatus", response.previous_status.clone()),
                ("status", response.task.status.clone()),
                ("updated", response.updated.to_string()),
            ]),
        },
    );
    Ok(response)
}

#[tauri::command]
fn read_codex_sessions(
    request: CodexSessionsReadRequest,
) -> Result<CodexSessionStoreResponse, String> {
    let sessions_path = codex_sessions_path(&request.workspace_path)?;
    let sessions = read_codex_session_links(&sessions_path)?;
    Ok(CodexSessionStoreResponse {
        path: sessions_path.to_string_lossy().to_string(),
        sessions,
    })
}

#[tauri::command]
fn bind_codex_session(
    app: tauri::AppHandle,
    request: BindCodexSessionRequest,
) -> Result<CodexSessionMutationResponse, String> {
    if !request.confirmed {
        return Err("codex session binding requires explicit confirmation".to_string());
    }

    let sessions_path = codex_sessions_path(&request.workspace_path)?;
    let mut sessions = read_codex_session_links(&sessions_path)?;
    let url = normalized_session_url(&request.url)?;
    let title = clean_session_title(&request.title, sessions.len() + 1);
    let notes = request.notes.trim().to_string();
    let mut updated = false;
    let link = if let Some(existing_index) = sessions.iter().position(|link| link.url == url) {
        sessions[existing_index].title = title.clone();
        sessions[existing_index].notes = notes.clone();
        updated = true;
        sessions[existing_index].clone()
    } else {
        let created_at = generated_at();
        let id = codex_session_id(&url, &created_at);
        let link = CodexSessionLink {
            id,
            title: title.clone(),
            url: url.clone(),
            notes,
            created_at,
            last_opened_at: None,
        };
        sessions.insert(0, link.clone());
        link
    };

    write_codex_session_links(&sessions_path, &sessions)?;
    record_audit_event(
        &app,
        AuditEventInput {
            actor: "Nexus App".to_string(),
            action: if updated {
                "codex_session_link.updated".to_string()
            } else {
                "codex_session_link.bound".to_string()
            },
            target: sessions_path.to_string_lossy().to_string(),
            summary: if updated {
                "Updated Codex session link".to_string()
            } else {
                "Bound Codex session link".to_string()
            },
            metadata: audit_metadata(&[
                ("workspace", request.workspace_path),
                ("sessionId", link.id.clone()),
                ("sessionTitle", link.title.clone()),
                ("sessionUrl", link.url.clone()),
                ("sessionCount", sessions.len().to_string()),
            ]),
        },
    );

    Ok(CodexSessionMutationResponse {
        path: sessions_path.to_string_lossy().to_string(),
        sessions,
        link: Some(link),
        updated,
    })
}

#[tauri::command]
fn open_codex_session(
    app: tauri::AppHandle,
    request: CodexSessionActionRequest,
) -> Result<CodexSessionMutationResponse, String> {
    if !request.confirmed {
        return Err("codex session opening requires explicit confirmation".to_string());
    }

    let sessions_path = codex_sessions_path(&request.workspace_path)?;
    let mut sessions = read_codex_session_links(&sessions_path)?;
    let Some(index) = sessions
        .iter()
        .position(|link| link.id == request.session_id)
    else {
        return Err(format!(
            "codex session link not found: {}",
            request.session_id
        ));
    };
    let mut link = sessions[index].clone();
    open_with_system(&link.url)?;
    link.last_opened_at = Some(generated_at());
    sessions[index] = link.clone();
    write_codex_session_links(&sessions_path, &sessions)?;
    record_audit_event(
        &app,
        AuditEventInput {
            actor: "Nexus App".to_string(),
            action: "codex_session_link.opened".to_string(),
            target: link.url.clone(),
            summary: "Opened Codex session link".to_string(),
            metadata: audit_metadata(&[
                ("workspace", request.workspace_path),
                ("sessionId", link.id.clone()),
                ("sessionTitle", link.title.clone()),
                ("sessionUrl", link.url.clone()),
            ]),
        },
    );

    Ok(CodexSessionMutationResponse {
        path: sessions_path.to_string_lossy().to_string(),
        sessions,
        link: Some(link),
        updated: true,
    })
}

#[tauri::command]
fn delete_codex_session(
    app: tauri::AppHandle,
    request: CodexSessionActionRequest,
) -> Result<CodexSessionMutationResponse, String> {
    if !request.confirmed {
        return Err("codex session deletion requires explicit confirmation".to_string());
    }

    let sessions_path = codex_sessions_path(&request.workspace_path)?;
    let mut sessions = read_codex_session_links(&sessions_path)?;
    let Some(index) = sessions
        .iter()
        .position(|link| link.id == request.session_id)
    else {
        return Err(format!(
            "codex session link not found: {}",
            request.session_id
        ));
    };
    let link = sessions.remove(index);
    write_codex_session_links(&sessions_path, &sessions)?;
    record_audit_event(
        &app,
        AuditEventInput {
            actor: "Nexus App".to_string(),
            action: "codex_session_link.deleted".to_string(),
            target: sessions_path.to_string_lossy().to_string(),
            summary: "Deleted Codex session link".to_string(),
            metadata: audit_metadata(&[
                ("workspace", request.workspace_path),
                ("sessionId", link.id.clone()),
                ("sessionTitle", link.title.clone()),
                ("sessionUrl", link.url.clone()),
                ("sessionCount", sessions.len().to_string()),
            ]),
        },
    );

    Ok(CodexSessionMutationResponse {
        path: sessions_path.to_string_lossy().to_string(),
        sessions,
        link: Some(link),
        updated: true,
    })
}

fn open_with_system(target: &str) -> Result<(), String> {
    Command::new("open")
        .arg(target)
        .status()
        .map_err(|error| error.to_string())
        .and_then(status_to_result)
}

fn codex_sessions_path(workspace_path: &str) -> Result<PathBuf, String> {
    let workspace = expand_user_path(workspace_path);
    if !workspace.exists() {
        return Err(format!("workspace does not exist: {}", workspace.display()));
    }
    if !workspace.is_dir() {
        return Err(format!(
            "workspace is not a directory: {}",
            workspace.display()
        ));
    }
    Ok(workspace.join(CODEX_SESSIONS_FILE))
}

fn read_codex_session_links(path: &Path) -> Result<Vec<CodexSessionLink>, String> {
    if !path.exists() {
        return Ok(Vec::new());
    }
    let content = fs::read_to_string(path).map_err(|error| error.to_string())?;
    if content.trim().is_empty() {
        return Ok(Vec::new());
    }
    if let Ok(store) = serde_json::from_str::<CodexSessionLinkStore>(&content) {
        return Ok(store.sessions);
    }
    if let Ok(sessions) = serde_json::from_str::<Vec<CodexSessionLink>>(&content) {
        return Ok(sessions);
    }
    Err(format!("invalid codex sessions file: {}", path.display()))
}

fn write_codex_session_links(path: &Path, sessions: &[CodexSessionLink]) -> Result<(), String> {
    let store = CodexSessionLinkStore {
        schema_version: 1,
        sessions: sessions.to_vec(),
    };
    let payload = serde_json::to_string_pretty(&store).map_err(|error| error.to_string())?;
    fs::write(path, payload).map_err(|error| error.to_string())
}

fn normalized_session_url(url: &str) -> Result<String, String> {
    let trimmed = url.trim();
    let Some((scheme, _rest)) = trimmed.split_once(':') else {
        return Err(
            "Codex session URL requires a valid scheme, for example codex:// or https://."
                .to_string(),
        );
    };
    if scheme.is_empty()
        || !scheme.chars().all(|character| {
            character.is_ascii_alphanumeric() || matches!(character, '+' | '-' | '.')
        })
    {
        return Err("Codex session URL scheme is invalid.".to_string());
    }
    Ok(trimmed.to_string())
}

fn clean_session_title(title: &str, index: usize) -> String {
    let clean = title.trim();
    if clean.is_empty() {
        format!("Codex session {index}")
    } else {
        clean.to_string()
    }
}

fn codex_session_id(url: &str, timestamp: &str) -> String {
    let mut hasher = DefaultHasher::new();
    url.hash(&mut hasher);
    timestamp.hash(&mut hasher);
    format!("session-{:x}", hasher.finish())
}

fn path_check(key: &str, label: &str, value: &str) -> PathCheck {
    let path = expand_user_path(value);
    let exists = path.exists();
    let is_dir = path.is_dir();
    let writable = is_dir && can_write_marker(&path);
    let summary = if !exists {
        "目录不存在".to_string()
    } else if !is_dir {
        "路径存在但不是目录".to_string()
    } else if writable {
        "目录可用".to_string()
    } else {
        "目录存在但写入检查未通过".to_string()
    };
    PathCheck {
        key: key.to_string(),
        label: label.to_string(),
        path: value.to_string(),
        exists,
        is_dir,
        writable,
        summary,
    }
}

fn can_write_marker(path: &Path) -> bool {
    let marker = path.join(".nexus-write-check");
    match fs::write(&marker, "ok") {
        Ok(_) => {
            let _ = fs::remove_file(marker);
            true
        }
        Err(_) => false,
    }
}

fn tool_check(key: &str, label: &str, command: &str, args: &[&str]) -> ToolCheck {
    let output = Command::new(command).args(args).output();
    match output {
        Ok(output) if output.status.success() => ToolCheck {
            key: key.to_string(),
            label: label.to_string(),
            available: true,
            summary: String::from_utf8_lossy(&output.stdout).trim().to_string(),
        },
        Ok(output) => ToolCheck {
            key: key.to_string(),
            label: label.to_string(),
            available: false,
            summary: String::from_utf8_lossy(&output.stderr).trim().to_string(),
        },
        Err(error) => ToolCheck {
            key: key.to_string(),
            label: label.to_string(),
            available: false,
            summary: error.to_string(),
        },
    }
}

fn count_child_dirs(root: &Path, ignored: Option<&str>) -> usize {
    fs::read_dir(root)
        .ok()
        .into_iter()
        .flat_map(|entries| entries.filter_map(Result::ok))
        .filter(|entry| {
            let name = entry.file_name().to_string_lossy().to_string();
            entry.path().is_dir() && !name.starts_with('.') && ignored != Some(name.as_str())
        })
        .count()
}

fn count_git_like_dirs(root: &Path) -> usize {
    fs::read_dir(root)
        .ok()
        .into_iter()
        .flat_map(|entries| entries.filter_map(Result::ok))
        .filter(|entry| entry.path().is_dir() && entry.path().join(".git").exists())
        .count()
}

fn record_audit_event(app: &tauri::AppHandle, input: AuditEventInput) {
    if let Ok(root) = app_audit_root(app) {
        let _ = append_audit_event_core(root, input);
    }
}

fn app_audit_root(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    app.path()
        .app_data_dir()
        .map(|path| path.join("audit"))
        .map_err(|error| error.to_string())
}

fn app_index_path(app: &tauri::AppHandle) -> Result<PathBuf, String> {
    app.path()
        .app_data_dir()
        .map(|path| path.join(DEFAULT_INDEX_FILE))
        .map_err(|error| error.to_string())
}

fn audit_metadata(pairs: &[(&str, String)]) -> BTreeMap<String, String> {
    pairs
        .iter()
        .map(|(key, value)| ((*key).to_string(), value.clone()))
        .collect()
}

fn generated_at() -> String {
    chrono_like_now(true)
}

fn chrono_like_now(include_time: bool) -> String {
    let output = if include_time {
        Command::new("date").args(["+%Y-%m-%dT%H:%M:%S"]).output()
    } else {
        Command::new("date").args(["+%Y-%m-%d"]).output()
    };
    output
        .ok()
        .and_then(|output| String::from_utf8(output.stdout).ok())
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
        .unwrap_or_else(|| "unknown".to_string())
}

fn status_to_result(status: std::process::ExitStatus) -> Result<(), String> {
    if status.success() {
        Ok(())
    } else {
        Err(format!("open command failed with status: {status}"))
    }
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    tauri::Builder::default()
        .plugin(tauri_plugin_opener::init())
        .invoke_handler(tauri::generate_handler![
            open_url,
            open_path,
            open_terminal,
            open_idea,
            read_text_file,
            read_demand_intake_status,
            scan_workspaces,
            scan_source_repos,
            check_environment,
            rebuild_search_index,
            search_index,
            write_widget_snapshot,
            export_settings_profile,
            append_audit_event,
            create_workspace,
            setup_worktrees,
            initialize_demand_intake,
            update_workspace_task,
            read_codex_sessions,
            bind_codex_session,
            open_codex_session,
            delete_codex_session
        ])
        .run(tauri::generate_context!())
        .expect("error while running Nexus");
}
