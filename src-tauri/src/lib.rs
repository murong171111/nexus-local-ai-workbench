use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;
use tauri::Manager;

#[derive(Deserialize)]
struct CreateWorkspaceRequest {
    name: String,
    folder: String,
    workspaces_root: String,
    source_repos_root: String,
    services: Vec<String>,
    target_branch: String,
}

#[derive(Serialize)]
struct CreateWorkspaceResponse {
    path: String,
    folder: String,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScanWorkspacesRequest {
    workspaces_root: String,
    source_repos_root: String,
    docs_root: String,
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

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct DashboardData {
    generated_at: String,
    workspaces_root: String,
    source_repos_root: String,
    docs_root: String,
    workspaces: Vec<WorkspaceData>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceData {
    name: String,
    folder: String,
    path: String,
    state: String,
    target_branch: String,
    source_root: String,
    confirmed_services: Vec<String>,
    candidate_services: Vec<String>,
    task_counts: TaskCounts,
    decision_count: usize,
    git_rows: Vec<GitRow>,
    risks: Vec<String>,
    risk_count: usize,
    updated: String,
    links: std::collections::BTreeMap<String, String>,
    worktree_command: String,
}

#[derive(Default, Serialize)]
struct TaskCounts {
    done: usize,
    doing: usize,
    todo: usize,
    blocked: usize,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct GitRow {
    service: String,
    worktree_path: String,
    source_path: String,
    worktree: GitStatus,
    source: GitStatus,
}

#[derive(Serialize)]
struct GitStatus {
    exists: bool,
    branch: String,
    dirty: bool,
    summary: String,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
struct SourceRepo {
    name: String,
    path: String,
    is_git: bool,
    branch: String,
    dirty: bool,
    summary: String,
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

#[derive(Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
struct WidgetSnapshot {
    generated_at: String,
    workspaces_root: String,
    active_workspace: Option<String>,
    active_workspace_folder: Option<String>,
    workspace_count: usize,
    risk_count: usize,
    dirty_service_count: usize,
    missing_worktree_count: usize,
    top_risks: Vec<String>,
    deep_link: String,
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
fn scan_workspaces(request: ScanWorkspacesRequest) -> Result<DashboardData, String> {
    let root = expand_user_path(&request.workspaces_root);
    if !root.exists() {
        return Ok(DashboardData {
            generated_at: generated_at(),
            workspaces_root: request.workspaces_root,
            source_repos_root: request.source_repos_root,
            docs_root: request.docs_root,
            workspaces: Vec::new(),
        });
    }

    let mut workspaces = Vec::new();
    let entries = fs::read_dir(&root).map_err(|error| error.to_string())?;
    for entry in entries {
        let entry = entry.map_err(|error| error.to_string())?;
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        if !path.is_dir() || name == "dashboard" || name.starts_with('.') {
            continue;
        }
        workspaces.push(collect_workspace(&path, &request.source_repos_root));
    }
    workspaces.sort_by(|left, right| right.risk_count.cmp(&left.risk_count).then(left.folder.cmp(&right.folder)));

    Ok(DashboardData {
        generated_at: generated_at(),
        workspaces_root: request.workspaces_root,
        source_repos_root: request.source_repos_root,
        docs_root: request.docs_root,
        workspaces,
    })
}

#[tauri::command]
fn scan_source_repos(request: ScanSourceReposRequest) -> Result<Vec<SourceRepo>, String> {
    let root = expand_user_path(&request.source_repos_root);
    if !root.exists() {
        return Ok(Vec::new());
    }

    let mut repos = Vec::new();
    let entries = fs::read_dir(&root).map_err(|error| error.to_string())?;
    for entry in entries {
        let entry = entry.map_err(|error| error.to_string())?;
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        if !path.is_dir() || name.starts_with('.') || matches!(name.as_str(), "node_modules" | "target" | "dist") {
            continue;
        }
        let status = git_status(&path);
        let is_git = path.join(".git").exists();
        repos.push(SourceRepo {
            name,
            path: path.to_string_lossy().to_string(),
            is_git,
            branch: status.branch,
            dirty: status.dirty,
            summary: status.summary,
        });
    }
    repos.sort_by(|left, right| left.name.cmp(&right.name));
    Ok(repos)
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
fn write_widget_snapshot(app: tauri::AppHandle, snapshot: WidgetSnapshot) -> Result<WidgetSnapshotResponse, String> {
    let app_data_dir = app.path().app_data_dir().map_err(|error| error.to_string())?;
    fs::create_dir_all(&app_data_dir).map_err(|error| error.to_string())?;
    let snapshot_path = app_data_dir.join("widget-snapshot.json");
    let payload = serde_json::to_string_pretty(&snapshot).map_err(|error| error.to_string())?;
    fs::write(&snapshot_path, payload).map_err(|error| error.to_string())?;
    Ok(WidgetSnapshotResponse {
        path: snapshot_path.to_string_lossy().to_string(),
    })
}

#[tauri::command]
fn create_workspace(request: CreateWorkspaceRequest) -> Result<CreateWorkspaceResponse, String> {
    let root = expand_user_path(&request.workspaces_root);
    let workspace = root.join(&request.folder);
    if workspace.exists() {
        return Err(format!("workspace already exists: {}", workspace.display()));
    }

    fs::create_dir_all(workspace.join("logs")).map_err(|error| error.to_string())?;
    fs::create_dir_all(workspace.join("sql")).map_err(|error| error.to_string())?;
    fs::create_dir_all(workspace.join("repos")).map_err(|error| error.to_string())?;
    fs::create_dir_all(workspace.join("scripts")).map_err(|error| error.to_string())?;

    let services = normalized_services(&request.services);
    let target_branch = if request.target_branch.trim().is_empty() {
        "待确认"
    } else {
        request.target_branch.trim()
    };
    let today = request.folder.split('-').take(3).collect::<Vec<_>>().join("-");

    write_file(
        &workspace.join("AGENTS.md"),
        &format!(
            "# Workspace Agent Guide\n\n- 需求名称: {}\n- 工作区: {}\n- 开发目录: `repos/<service>`\n- 源仓库目录: `{}`\n\n## Rules\n\n- 代码改动优先发生在 `repos/<service>` worktree 中。\n- 每次代码、SQL、业务逻辑、接口、DTO、配置或验证变化后，检查并更新 `交付记录.md`。\n- 不直接切换源仓库分支，源仓库只作为 worktree 来源。\n",
            request.name,
            workspace.display(),
            request.source_repos_root
        ),
    )?;

    write_file(
        &workspace.join("workspace.md"),
        &format!(
            "# {}\n\n- 需求名称: {}\n- 创建日期: {}\n- 当前状态: analyzing\n- 目标分支: {}\n- 源仓库集合: {}\n\n## 需求描述\n\n待补充。\n\n## 当前结论\n\n- 工作区已由 Nexus 创建。\n- 服务范围和目标分支可继续确认。\n",
            request.name, request.name, today, target_branch, request.source_repos_root
        ),
    )?;

    write_file(
        &workspace.join("STATUS.md"),
        &format!(
            "# STATUS\n\n- 状态: analyzing\n- 当前焦点: 需求范围确认\n- 下一步: 确认服务范围、目标分支、是否创建 worktree\n- 更新时间: {}\n\n## Bootstrap Summary\n\n- 服务数量: {}\n- 目标分支: {}\n- 源仓库目录: `{}`\n- Worktree 命令: `scripts/worktree-commands.sh`\n- 创建报告: `bootstrap-report.md`\n\n## Blockers\n\n{}\n",
            today,
            services.len(),
            target_branch,
            request.source_repos_root,
            if target_branch == "待确认" {
                "- 目标分支待确认时，不自动创建 worktree。\n"
            } else {
                "- worktree 尚未创建，需要人工确认后执行命令。\n"
            }
        ),
    )?;

    write_file(&workspace.join("services.md"), &services_markdown(&services, &request.source_repos_root))?;
    write_file(&workspace.join("branches.md"), &branches_markdown(&services, target_branch, &request.source_repos_root))?;
    write_file(
        &workspace.join("plan.md"),
        "# Plan\n\n## 分析步骤\n\n- [ ] 确认需求范围\n- [ ] 确认涉及服务\n- [ ] 确认目标分支\n- [ ] 创建 worktree\n- [ ] 编码与验证\n- [ ] 更新交付记录\n",
    )?;
    write_file(
        &workspace.join("tasks.md"),
        "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| 确认需求范围 | 待办 | 补充业务目标、入口、影响范围 |\n| 确认服务范围 | 待办 | 标记涉及服务和待验证服务 |\n| 确认目标分支 | 待办 | 多服务优先统一分支 |\n| 创建 worktree | 待办 | 分支确认后再执行 |\n| 更新交付记录 | 待办 | 代码/SQL/逻辑变更后必须更新 |\n",
    )?;
    write_file(
        &workspace.join("decisions.md"),
        "# Decisions\n\n| 时间 | 决策 | 原因 | 影响 |\n| --- | --- | --- | --- |\n",
    )?;
    write_file(
        &workspace.join("handoff.md"),
        "# Handoff\n\n## 当前状态\n\n待补充。\n\n## 后续继续方式\n\n请先读取 `AGENTS.md`、`STATUS.md`、`services.md`、`branches.md`、`tasks.md` 和 `交付记录.md`。\n",
    )?;
    write_file(
        &workspace.join("delivery.md"),
        "# Delivery Notes\n\n## 变更记录\n\n| 时间 | 类型 | 服务 | 内容 | 验证 |\n| --- | --- | --- | --- | --- |\n",
    )?;
    write_file(
        &workspace.join("交付记录.md"),
        &format!(
            "# 交付记录\n\n## 需求信息\n\n- 需求名称: {}\n- 工作区: {}\n- 分支: {}\n\n## 涉及服务\n\n{}\n\n## 代码变更\n\n暂无。\n\n## SQL 变更\n\n暂无。\n\n## 新增逻辑\n\n暂无。\n\n## 验证结果\n\n暂无。\n\n## 遗留风险\n\n- 创建后需要确认服务范围、分支和 worktree 状态。\n",
            request.name,
            request.folder,
            target_branch,
            if services.is_empty() { "待确认。".to_string() } else { services.iter().map(|service| format!("- {}", service)).collect::<Vec<_>>().join("\n") }
        ),
    )?;
    write_file(
        &workspace.join("bootstrap-report.md"),
        &bootstrap_report(&request.name, &request.folder, &workspace, &services, target_branch, &request.source_repos_root, today.as_str()),
    )?;
    write_file(
        &workspace.join("scripts").join("worktree-commands.sh"),
        &worktree_commands(&workspace, &services, target_branch, &request.source_repos_root),
    )?;
    update_index(&root, &request.name, &request.folder, target_branch, &services)?;

    Ok(CreateWorkspaceResponse {
        path: workspace.to_string_lossy().to_string(),
        folder: request.folder,
    })
}

fn open_with_system(target: &str) -> Result<(), String> {
    Command::new("open")
        .arg(target)
        .status()
        .map_err(|error| error.to_string())
        .and_then(status_to_result)
}

fn expand_user_path(value: &str) -> PathBuf {
    if value == "~" {
        return std::env::var_os("HOME").map(PathBuf::from).unwrap_or_else(|| PathBuf::from(value));
    }
    if let Some(rest) = value.strip_prefix("~/") {
        if let Some(home) = std::env::var_os("HOME") {
            return PathBuf::from(home).join(rest);
        }
    }
    PathBuf::from(value)
}

fn collect_workspace(path: &Path, default_source_root: &str) -> WorkspaceData {
    let workspace_md = read_text_lossy(&path.join("workspace.md"));
    let services_md = read_text_lossy(&path.join("services.md"));
    let branches_md = read_text_lossy(&path.join("branches.md"));
    let tasks_md = read_text_lossy(&path.join("tasks.md"));
    let decisions_md = read_text_lossy(&path.join("decisions.md"));

    let name = extract_bullet_value(&workspace_md, "需求名称").unwrap_or_else(|| {
        path.file_name().unwrap_or_default().to_string_lossy().to_string()
    });
    let state = extract_bullet_value(&workspace_md, "当前状态").unwrap_or_else(|| "unknown".to_string());
    let target_branch = extract_bullet_value(&workspace_md, "目标分支")
        .or_else(|| extract_bullet_value(&workspace_md, "建议目标分支"))
        .unwrap_or_else(|| {
            extract_bullet_value(&branches_md, "目标分支").unwrap_or_else(|| "待确认".to_string())
        });
    let source_root = extract_bullet_value(&workspace_md, "源仓库集合").unwrap_or_else(|| default_source_root.to_string());

    let confirmed_rows = table_rows(&section(&services_md, "已确认相关"));
    let fallback_rows = table_rows(&section(&services_md, "初步服务范围"));
    let candidate_rows = table_rows(&section(&services_md, "待验证范围"));
    let confirmed_services = service_names_from(if confirmed_rows.is_empty() { &fallback_rows } else { &confirmed_rows });
    let candidate_services = service_names_from(&candidate_rows)
        .into_iter()
        .filter(|service| !confirmed_services.contains(service))
        .collect::<Vec<_>>();

    let task_rows = table_rows(&tasks_md);
    let decision_rows = table_rows(&decisions_md);
    let task_counts = count_tasks(&task_rows);

    let mut git_rows = Vec::new();
    for service in &confirmed_services {
        let worktree_path = path.join("repos").join(service);
        let source_path = expand_user_path(&source_root).join(service);
        git_rows.push(GitRow {
            service: service.clone(),
            worktree_path: worktree_path.to_string_lossy().to_string(),
            source_path: source_path.to_string_lossy().to_string(),
            worktree: git_status(&worktree_path),
            source: git_status(&source_path),
        });
    }

    let mut risks = Vec::new();
    if target_branch.contains("待确认") {
        risks.push("目标分支未确认".to_string());
    }
    if confirmed_services.is_empty() {
        risks.push("服务范围未确认".to_string());
    }
    let missing_worktrees = git_rows
        .iter()
        .filter(|row| !row.worktree.exists)
        .map(|row| row.service.clone())
        .collect::<Vec<_>>();
    if !missing_worktrees.is_empty() {
        risks.push(format!("worktree 未创建: {}", missing_worktrees.join(", ")));
    }
    let dirty_worktrees = git_rows
        .iter()
        .filter(|row| row.worktree.dirty)
        .map(|row| row.service.clone())
        .collect::<Vec<_>>();
    if !dirty_worktrees.is_empty() {
        risks.push(format!("worktree 有未提交改动: {}", dirty_worktrees.join(", ")));
    }
    if !path.join("交付记录.md").exists() {
        risks.push("缺少交付记录".to_string());
    } else if delivery_needs_update(&read_text_lossy(&path.join("交付记录.md"))) {
        risks.push("交付记录待补充".to_string());
    }
    if !path.join("sql").exists() {
        risks.push("缺少 SQL 目录".to_string());
    }

    let mut links = std::collections::BTreeMap::new();
    links.insert("folder".to_string(), path.to_string_lossy().to_string());
    links.insert("workspace".to_string(), path.join("workspace.md").to_string_lossy().to_string());
    links.insert("status".to_string(), path.join("STATUS.md").to_string_lossy().to_string());
    links.insert("services".to_string(), path.join("services.md").to_string_lossy().to_string());
    links.insert("branches".to_string(), path.join("branches.md").to_string_lossy().to_string());
    links.insert("tasks".to_string(), path.join("tasks.md").to_string_lossy().to_string());
    links.insert("delivery".to_string(), path.join("交付记录.md").to_string_lossy().to_string());
    links.insert("handoff".to_string(), path.join("handoff.md").to_string_lossy().to_string());
    links.insert("bootstrap".to_string(), path.join("bootstrap-report.md").to_string_lossy().to_string());
    links.insert("worktreeScript".to_string(), path.join("scripts").join("worktree-commands.sh").to_string_lossy().to_string());
    links.insert("sql".to_string(), path.join("sql").to_string_lossy().to_string());

    let risk_count = risks.len();
    let folder = path.file_name().unwrap_or_default().to_string_lossy().to_string();
    let worktree_command = worktree_commands(path, &missing_worktrees, &target_branch, &source_root);
    WorkspaceData {
        name,
        folder,
        path: path.to_string_lossy().to_string(),
        state,
        target_branch,
        source_root,
        confirmed_services,
        candidate_services,
        task_counts,
        decision_count: decision_rows.len(),
        git_rows,
        risks,
        risk_count,
        updated: generated_date(),
        links,
        worktree_command,
    }
}

fn read_text_lossy(path: &Path) -> String {
    fs::read_to_string(path).unwrap_or_default()
}

fn extract_bullet_value(text: &str, label: &str) -> Option<String> {
    for line in text.lines() {
        let trimmed = line.trim();
        let prefixes = [format!("- {}:", label), format!("- {}：", label)];
        for prefix in prefixes {
            if trimmed.starts_with(&prefix) {
                return Some(trimmed[prefix.len()..].trim().replace('`', ""));
            }
        }
    }
    None
}

fn section(text: &str, heading: &str) -> String {
    let marker = format!("## {}", heading);
    let Some(start) = text.find(&marker) else {
        return String::new();
    };
    let body_start = start + marker.len();
    let rest = &text[body_start..];
    let end = rest.find("\n## ").unwrap_or(rest.len());
    rest[..end].to_string()
}

fn table_rows(text: &str) -> Vec<Vec<String>> {
    text.lines()
        .map(str::trim)
        .filter(|line| line.starts_with('|') && !line.contains("---"))
        .map(|line| {
            line.trim_matches('|')
                .split('|')
                .map(|cell| cell.trim().replace('`', ""))
                .collect::<Vec<_>>()
        })
        .filter(|row| {
            !row.is_empty()
                && !matches!(
                    row[0].as_str(),
                    "服务" | "任务" | "需求" | "场景" | "时间" | "工作区"
                )
        })
        .collect()
}

fn service_names_from(rows: &[Vec<String>]) -> Vec<String> {
    rows.iter()
        .filter_map(|row| row.first())
        .filter(|name| !matches!(name.as_str(), "待确认" | "待补充" | ""))
        .cloned()
        .collect()
}

fn count_tasks(rows: &[Vec<String>]) -> TaskCounts {
    let mut counts = TaskCounts::default();
    for row in rows {
        let joined = row.join(" ").to_lowercase();
        if joined.contains("阻塞") || joined.contains("blocked") {
            counts.blocked += 1;
        } else if ["已完成", "已确认", "已创建", "完成"].iter().any(|word| joined.contains(word)) {
            counts.done += 1;
        } else if ["持续进行", "进行中", "doing"].iter().any(|word| joined.contains(word)) {
            counts.doing += 1;
        } else {
            counts.todo += 1;
        }
    }
    counts
}

fn delivery_needs_update(text: &str) -> bool {
    let normalized = text.replace(' ', "");
    normalized.contains("待补充")
        || normalized.contains("待确认")
        || normalized.contains("暂无")
        || normalized.contains("创建后需要确认")
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

fn git_status(path: &Path) -> GitStatus {
    if !path.exists() {
        return GitStatus {
            exists: false,
            branch: "未创建".to_string(),
            dirty: false,
            summary: "未创建".to_string(),
        };
    }
    if !path.join(".git").exists() {
        return GitStatus {
            exists: true,
            branch: "非 git worktree".to_string(),
            dirty: true,
            summary: "目录存在但不是 git worktree".to_string(),
        };
    }
    let output = Command::new("git")
        .args(["-C", &path.to_string_lossy(), "status", "--short", "--branch"])
        .output();
    match output {
        Ok(output) if output.status.success() => {
            let stdout = String::from_utf8_lossy(&output.stdout);
            let lines = stdout.lines().map(str::trim).filter(|line| !line.is_empty()).collect::<Vec<_>>();
            let branch = lines.first().map(|line| line.replace("## ", "")).unwrap_or_else(|| "未知".to_string());
            let dirty = lines.len() > 1;
            GitStatus {
                exists: true,
                branch,
                dirty,
                summary: if dirty { "有未提交改动" } else { "干净" }.to_string(),
            }
        }
        Ok(output) => GitStatus {
            exists: true,
            branch: "检查失败".to_string(),
            dirty: true,
            summary: String::from_utf8_lossy(&output.stderr).trim().to_string(),
        },
        Err(error) => GitStatus {
            exists: true,
            branch: "检查失败".to_string(),
            dirty: true,
            summary: error.to_string(),
        },
    }
}

fn generated_at() -> String {
    chrono_like_now(true)
}

fn generated_date() -> String {
    chrono_like_now(false)
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

fn normalized_services(services: &[String]) -> Vec<String> {
    services
        .iter()
        .map(|service| service.trim().to_string())
        .filter(|service| !service.is_empty())
        .collect()
}

fn write_file(path: &Path, content: &str) -> Result<(), String> {
    fs::write(path, content).map_err(|error| error.to_string())
}

fn services_markdown(services: &[String], source_root: &str) -> String {
    let rows = if services.is_empty() {
        "| 待确认 | 待确认 | 待补充 |\n".to_string()
    } else {
        services
            .iter()
            .map(|service| format!("| {} | `{}/{}` | 初始确认 |\n", service, source_root, service))
            .collect::<String>()
    };
    format!(
        "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n{}\n## 待验证范围\n\n| 服务 | 线索 | 说明 |\n| --- | --- | --- |\n",
        rows
    )
}

fn branches_markdown(services: &[String], target_branch: &str, source_root: &str) -> String {
    let rows = if services.is_empty() {
        "| 待确认 | 待确认 | 待确认 | 待创建 |\n".to_string()
    } else {
        services
            .iter()
            .map(|service| {
                format!(
                    "| {} | `{}/{}` | {} | 待创建 |\n",
                    service, source_root, service, target_branch
                )
            })
            .collect::<String>()
    };
    format!(
        "# Branches\n\n- 目标分支: {}\n\n| 服务 | 源仓库 | 目标分支 | Worktree |\n| --- | --- | --- | --- |\n{}",
        target_branch, rows
    )
}

fn bootstrap_report(name: &str, folder: &str, workspace: &Path, services: &[String], target_branch: &str, source_root: &str, today: &str) -> String {
    let service_lines = if services.is_empty() {
        "- 服务范围待确认".to_string()
    } else {
        services
            .iter()
            .map(|service| format!("- {}: `{}/{}` -> `repos/{}`", service, source_root, service, service))
            .collect::<Vec<_>>()
            .join("\n")
    };
    format!(
        "# Bootstrap Report\n\n- 需求名称: {}\n- 工作区: {}\n- 创建日期: {}\n- 目标分支: {}\n- 工作区路径: `{}`\n- 源仓库目录: `{}`\n\n## 服务范围\n\n{}\n\n## 初始风险\n\n{}\n\n## 下一步\n\n- [ ] 补充需求描述和影响范围。\n- [ ] 确认目标分支。\n- [ ] 复核 `scripts/worktree-commands.sh` 后创建 worktree。\n- [ ] 编码或 SQL 变更后更新 `交付记录.md`。\n",
        name,
        folder,
        today,
        target_branch,
        workspace.to_string_lossy(),
        source_root,
        service_lines,
        if target_branch == "待确认" {
            "- 目标分支未确认\n- worktree 尚未创建"
        } else {
            "- worktree 尚未创建"
        }
    )
}

fn worktree_commands(workspace: &Path, services: &[String], target_branch: &str, source_root: &str) -> String {
    let branch = if target_branch.trim().is_empty() || target_branch.contains("待确认") {
        "<target-branch>"
    } else {
        target_branch
    };
    let mut content = "#!/usr/bin/env bash\nset -euo pipefail\n\n# Review these commands before running. Nexus does not execute them automatically.\n".to_string();
    if services.is_empty() {
        content.push_str("# No services are confirmed yet.\n");
        content.push_str("# Add services in services.md, then regenerate or edit this file.\n");
        return content;
    }
    for service in services {
        let source = expand_user_path(source_root).join(service);
        let target = workspace.join("repos").join(service);
        content.push_str(&format!(
            "\n# {}\ngit -C {} fetch origin\ngit -C {} worktree add {} {}\n",
            service,
            shell_quote(&source.to_string_lossy()),
            shell_quote(&source.to_string_lossy()),
            shell_quote(&target.to_string_lossy()),
            shell_quote(branch)
        ));
    }
    content
}

fn shell_quote(value: &str) -> String {
    format!("'{}'", value.replace('\'', "'\\''"))
}

fn update_index(root: &Path, name: &str, folder: &str, target_branch: &str, services: &[String]) -> Result<(), String> {
    let index = root.join("INDEX.md");
    let mut content = fs::read_to_string(&index).unwrap_or_else(|_| {
        "# Workspace Index\n\n| 工作区 | 状态 | 目标分支 | 服务 | 路径 |\n| --- | --- | --- | --- | --- |\n".to_string()
    });
    content.push_str(&format!(
        "| {} | analyzing | {} | {} | `{}` |\n",
        name,
        target_branch,
        if services.is_empty() { "待确认".to_string() } else { services.join(", ") },
        folder
    ));
    fs::write(index, content).map_err(|error| error.to_string())
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
            write_widget_snapshot,
            create_workspace
        ])
        .run(tauri::generate_context!())
        .expect("error while running Nexus");
}
