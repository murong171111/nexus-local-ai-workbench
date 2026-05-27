use nexus_core::{
    append_audit_event, create_workspace as create_workspace_core, expand_user_path,
    export_settings_profile as export_settings_profile_core,
    rebuild_search_index as rebuild_search_index_core, scan_source_repos as scan_source_repos_core,
    scan_workspaces_with_audit as scan_workspaces_core, search_index as search_index_core,
    AuditEventInput, CreateWorkspaceRequest, CreateWorkspaceResponse, DashboardData,
    ExportSettingsProfileResponse, RebuildSearchIndexResponse, SearchResult, SettingsProfile,
    SourceRepo, WidgetSnapshot, DEFAULT_INDEX_FILE,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use tauri::Manager;

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
    fs::read_to_string(expand_user_path(&path)).map_err(|error| error.to_string())
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

fn open_with_system(target: &str) -> Result<(), String> {
    Command::new("open")
        .arg(target)
        .status()
        .map_err(|error| error.to_string())
        .and_then(status_to_result)
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
        let _ = append_audit_event(root, input);
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
            scan_workspaces,
            scan_source_repos,
            check_environment,
            rebuild_search_index,
            search_index,
            write_widget_snapshot,
            export_settings_profile,
            create_workspace
        ])
        .run(tauri::generate_context!())
        .expect("error while running Nexus");
}
