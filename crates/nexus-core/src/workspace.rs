use crate::{
    expand_user_path, git_status, normalize_git_branch, read_audit_events,
    target_branch_confirmed, AuditEvent, GitStatus,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;
use std::fs;
use std::path::Path;
use std::process::Command;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DashboardData {
    pub generated_at: String,
    pub workspaces_root: String,
    pub source_repos_root: String,
    pub docs_root: String,
    pub workspaces: Vec<WorkspaceData>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceData {
    pub name: String,
    pub folder: String,
    pub path: String,
    pub state: String,
    pub target_branch: String,
    pub source_root: String,
    pub confirmed_services: Vec<String>,
    pub candidate_services: Vec<String>,
    pub task_counts: TaskCounts,
    pub decision_count: usize,
    pub git_rows: Vec<GitRow>,
    pub risks: Vec<String>,
    pub risk_count: usize,
    pub updated: String,
    pub links: BTreeMap<String, String>,
    pub worktree_command: String,
    pub activities: Vec<WorkspaceActivity>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize)]
pub struct TaskCounts {
    pub done: usize,
    pub doing: usize,
    pub todo: usize,
    pub blocked: usize,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WorkspaceActivity {
    pub time: String,
    pub title: String,
    pub detail: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct GitRow {
    pub service: String,
    pub worktree_path: String,
    pub source_path: String,
    pub worktree: GitStatus,
    pub source: GitStatus,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
pub struct CreateWorkspaceRequest {
    pub name: String,
    pub folder: String,
    pub workspaces_root: String,
    pub source_repos_root: String,
    pub services: Vec<String>,
    pub target_branch: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct CreateWorkspaceResponse {
    pub path: String,
    pub folder: String,
}

pub fn scan_workspaces(
    workspaces_root: &str,
    source_repos_root: &str,
    docs_root: &str,
) -> Result<DashboardData, String> {
    scan_workspaces_with_audit(workspaces_root, source_repos_root, docs_root, None)
}

pub fn scan_workspaces_with_audit(
    workspaces_root: &str,
    source_repos_root: &str,
    docs_root: &str,
    audit_root: Option<&str>,
) -> Result<DashboardData, String> {
    let root = expand_user_path(workspaces_root);
    if !root.exists() {
        return Ok(DashboardData {
            generated_at: generated_at(),
            workspaces_root: workspaces_root.to_string(),
            source_repos_root: source_repos_root.to_string(),
            docs_root: docs_root.to_string(),
            workspaces: Vec::new(),
        });
    }

    let audit_path = audit_root.map(expand_user_path);
    let audit_events = audit_path
        .as_ref()
        .map(|root| read_audit_events(root, 400))
        .transpose()?
        .unwrap_or_default();

    let mut workspaces = Vec::new();
    let entries = fs::read_dir(&root).map_err(|error| error.to_string())?;
    for entry in entries {
        let entry = entry.map_err(|error| error.to_string())?;
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        if !path.is_dir()
            || name == "dashboard"
            || name.starts_with('.')
            || audit_path.as_ref().is_some_and(|audit_path| audit_path == &path)
        {
            continue;
        }
        workspaces.push(collect_workspace(
            &path,
            source_repos_root,
            &audit_events,
        ));
    }
    workspaces.sort_by(|left, right| {
        right
            .risk_count
            .cmp(&left.risk_count)
            .then(left.folder.cmp(&right.folder))
    });

    Ok(DashboardData {
        generated_at: generated_at(),
        workspaces_root: workspaces_root.to_string(),
        source_repos_root: source_repos_root.to_string(),
        docs_root: docs_root.to_string(),
        workspaces,
    })
}

pub fn create_workspace(
    request: CreateWorkspaceRequest,
) -> Result<CreateWorkspaceResponse, String> {
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
    let today = request
        .folder
        .split('-')
        .take(3)
        .collect::<Vec<_>>()
        .join("-");

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

    write_file(
        &workspace.join("services.md"),
        &services_markdown(&services, &request.source_repos_root),
    )?;
    write_file(
        &workspace.join("branches.md"),
        &branches_markdown(&services, target_branch, &request.source_repos_root),
    )?;
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
            if services.is_empty() {
                "待确认。".to_string()
            } else {
                services
                    .iter()
                    .map(|service| format!("- {}", service))
                    .collect::<Vec<_>>()
                    .join("\n")
            }
        ),
    )?;
    write_file(
        &workspace.join("bootstrap-report.md"),
        &bootstrap_report(
            &request.name,
            &request.folder,
            &workspace,
            &services,
            target_branch,
            &request.source_repos_root,
            today.as_str(),
        ),
    )?;
    write_file(
        &workspace.join("scripts").join("worktree-commands.sh"),
        &worktree_commands(
            &workspace,
            &services,
            target_branch,
            &request.source_repos_root,
        ),
    )?;
    update_index(
        &root,
        &request.name,
        &request.folder,
        target_branch,
        &services,
    )?;

    Ok(CreateWorkspaceResponse {
        path: workspace.to_string_lossy().to_string(),
        folder: request.folder,
    })
}

fn collect_workspace(
    path: &Path,
    default_source_root: &str,
    audit_events: &[AuditEvent],
) -> WorkspaceData {
    let workspace_md = read_text_lossy(&path.join("workspace.md"));
    let services_md = read_text_lossy(&path.join("services.md"));
    let branches_md = read_text_lossy(&path.join("branches.md"));
    let tasks_md = read_text_lossy(&path.join("tasks.md"));
    let decisions_md = read_text_lossy(&path.join("decisions.md"));

    let name = extract_bullet_value(&workspace_md, "需求名称").unwrap_or_else(|| {
        path.file_name()
            .unwrap_or_default()
            .to_string_lossy()
            .to_string()
    });
    let state =
        extract_bullet_value(&workspace_md, "当前状态").unwrap_or_else(|| "unknown".to_string());
    let target_branch = extract_bullet_value(&workspace_md, "目标分支")
        .or_else(|| extract_bullet_value(&workspace_md, "建议目标分支"))
        .unwrap_or_else(|| {
            extract_bullet_value(&branches_md, "目标分支").unwrap_or_else(|| "待确认".to_string())
        });
    let source_root = extract_bullet_value(&workspace_md, "源仓库集合")
        .unwrap_or_else(|| default_source_root.to_string());

    let confirmed_rows = table_rows(&section(&services_md, "已确认相关"));
    let fallback_rows = table_rows(&section(&services_md, "初步服务范围"));
    let candidate_rows = table_rows(&section(&services_md, "待验证范围"));
    let confirmed_services = service_names_from(if confirmed_rows.is_empty() {
        &fallback_rows
    } else {
        &confirmed_rows
    });
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
        risks.push(format!(
            "worktree 有未提交改动: {}",
            dirty_worktrees.join(", ")
        ));
    }
    let branch_mismatches = git_rows
        .iter()
        .filter(|row| {
            target_branch_confirmed(&target_branch)
                && row.worktree.exists
                && normalize_git_branch(&row.worktree.branch)
                    != normalize_git_branch(&target_branch)
        })
        .map(|row| {
            format!(
                "{}({})",
                row.service,
                normalize_git_branch(&row.worktree.branch)
            )
        })
        .collect::<Vec<_>>();
    if !branch_mismatches.is_empty() {
        risks.push(format!("分支不一致: {}", branch_mismatches.join(", ")));
    }
    if !path.join("交付记录.md").exists() {
        risks.push("缺少交付记录".to_string());
    } else if delivery_needs_update(&read_text_lossy(&path.join("交付记录.md"))) {
        risks.push("交付记录待补充".to_string());
    }
    if !path.join("sql").exists() {
        risks.push("缺少 SQL 目录".to_string());
    }

    let mut links = BTreeMap::new();
    links.insert("folder".to_string(), path.to_string_lossy().to_string());
    links.insert(
        "workspace".to_string(),
        path.join("workspace.md").to_string_lossy().to_string(),
    );
    links.insert(
        "status".to_string(),
        path.join("STATUS.md").to_string_lossy().to_string(),
    );
    links.insert(
        "services".to_string(),
        path.join("services.md").to_string_lossy().to_string(),
    );
    links.insert(
        "branches".to_string(),
        path.join("branches.md").to_string_lossy().to_string(),
    );
    links.insert(
        "tasks".to_string(),
        path.join("tasks.md").to_string_lossy().to_string(),
    );
    links.insert(
        "delivery".to_string(),
        path.join("交付记录.md").to_string_lossy().to_string(),
    );
    links.insert(
        "handoff".to_string(),
        path.join("handoff.md").to_string_lossy().to_string(),
    );
    links.insert(
        "bootstrap".to_string(),
        path.join("bootstrap-report.md")
            .to_string_lossy()
            .to_string(),
    );
    links.insert(
        "worktreeScript".to_string(),
        path.join("scripts")
            .join("worktree-commands.sh")
            .to_string_lossy()
            .to_string(),
    );
    links.insert(
        "sql".to_string(),
        path.join("sql").to_string_lossy().to_string(),
    );

    let risk_count = risks.len();
    let folder = path
        .file_name()
        .unwrap_or_default()
        .to_string_lossy()
        .to_string();
    let worktree_command =
        worktree_commands(path, &missing_worktrees, &target_branch, &source_root);
    let activities = workspace_activities(
        path,
        &folder,
        &name,
        &risks,
        generated_date().as_str(),
        audit_events,
    );
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
        activities,
    }
}

fn workspace_activities(
    path: &Path,
    folder: &str,
    name: &str,
    risks: &[String],
    updated: &str,
    audit_events: &[AuditEvent],
) -> Vec<WorkspaceActivity> {
    let path_text = path.to_string_lossy().to_string();
    let mut activities = audit_events
        .iter()
        .filter(|event| audit_event_matches_workspace(event, folder, &path_text))
        .take(6)
        .map(audit_event_to_activity)
        .collect::<Vec<_>>();

    if activities.is_empty() {
        let title = risks
            .first()
            .cloned()
            .unwrap_or_else(|| "Workspace scanned".to_string());
        activities.push(WorkspaceActivity {
            time: updated.to_string(),
            title,
            detail: format!("Loaded {} from Nexus Core dashboard scan", name),
        });
    }

    activities
}

fn audit_event_matches_workspace(event: &AuditEvent, folder: &str, path: &str) -> bool {
    event.metadata.get("folder").is_some_and(|value| value == folder)
        || event
            .metadata
            .get("workspace")
            .is_some_and(|value| value == folder)
        || event
            .metadata
            .get("workspaceFolder")
            .is_some_and(|value| value == folder)
        || event.target.contains(path)
        || event.target.contains(folder)
}

fn audit_event_to_activity(event: &AuditEvent) -> WorkspaceActivity {
    WorkspaceActivity {
        time: compact_timestamp(&event.timestamp),
        title: audit_action_label(&event.action),
        detail: if event.actor.trim().is_empty() {
            event.summary.clone()
        } else {
            format!("{} · {}", event.actor, event.summary)
        },
    }
}

fn audit_action_label(action: &str) -> String {
    match action {
        "workspace.created" => "工作区已创建 / Workspace created".to_string(),
        "settings_profile.exported" => "设置已导出 / Settings exported".to_string(),
        "settings_profile.imported" => "设置已导入 / Settings imported".to_string(),
        "codex.opened" => "Codex 已打开 / Codex opened".to_string(),
        "codex_handoff.opened" => "Codex 交接已打开 / Codex handoff".to_string(),
        "codex_instruction.copied" => "Codex 指令已复制 / Instruction copied".to_string(),
        "document.opened" => "文档已打开 / Document opened".to_string(),
        "risk_instruction.copied" => "风险指令已复制 / Risk instruction".to_string(),
        "worktree.command.copied" => "Worktree 命令已复制 / Worktree command".to_string(),
        "worktree.command.generated" => "Worktree 命令已生成 / Worktree command".to_string(),
        value if !value.trim().is_empty() => value.replace('_', " ").replace('.', " "),
        _ => "本地事件 / Local event".to_string(),
    }
}

fn compact_timestamp(value: &str) -> String {
    if value.len() >= 16 && value.as_bytes().get(10) == Some(&b'T') {
        value[..16].replace('T', " ")
    } else {
        value.to_string()
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
        } else if ["已完成", "已确认", "已创建", "完成"]
            .iter()
            .any(|word| joined.contains(word))
        {
            counts.done += 1;
        } else if ["持续进行", "进行中", "doing"]
            .iter()
            .any(|word| joined.contains(word))
        {
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

pub fn worktree_commands(
    workspace: &Path,
    services: &[String],
    target_branch: &str,
    source_root: &str,
) -> String {
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
            .map(|service| {
                format!(
                    "| {} | `{}/{}` | 初始确认 |\n",
                    service, source_root, service
                )
            })
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

fn bootstrap_report(
    name: &str,
    folder: &str,
    workspace: &Path,
    services: &[String],
    target_branch: &str,
    source_root: &str,
    today: &str,
) -> String {
    let service_lines = if services.is_empty() {
        "- 服务范围待确认".to_string()
    } else {
        services
            .iter()
            .map(|service| {
                format!(
                    "- {}: `{}/{}` -> `repos/{}`",
                    service, source_root, service, service
                )
            })
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

fn update_index(
    root: &Path,
    name: &str,
    folder: &str,
    target_branch: &str,
    services: &[String],
) -> Result<(), String> {
    let index = root.join("INDEX.md");
    let mut content = fs::read_to_string(&index).unwrap_or_else(|_| {
        "# Workspace Index\n\n| 工作区 | 状态 | 目标分支 | 服务 | 路径 |\n| --- | --- | --- | --- | --- |\n".to_string()
    });
    content.push_str(&format!(
        "| {} | analyzing | {} | {} | `{}` |\n",
        name,
        target_branch,
        if services.is_empty() {
            "待确认".to_string()
        } else {
            services.join(", ")
        },
        folder
    ));
    fs::write(index, content).map_err(|error| error.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scan_workspaces_extracts_documents_and_risks() {
        let root =
            std::env::temp_dir().join(format!("nexus-core-workspaces-{}", std::process::id()));
        let workspace = root.join("2026-01-01-demo");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(workspace.join("sql")).unwrap();
        fs::create_dir_all(workspace.join("repos")).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Demo\n\n- 需求名称: Demo Workspace\n- 当前状态: developing\n- 目标分支: chen/demo\n- 源仓库集合: ~/source-repos\n",
        )
        .unwrap();
        fs::write(
            workspace.join("services.md"),
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n| order | ~/source-repos/order | core |\n\n## 待验证范围\n\n| 服务 | 线索 | 说明 |\n| --- | --- | --- |\n| coupon | maybe | 待确认 |\n",
        )
        .unwrap();
        fs::write(
            workspace.join("tasks.md"),
            "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| 确认需求范围 | 已完成 | ok |\n| 编码与验证 | 进行中 | active |\n| 更新交付记录 | 待办 | later |\n",
        )
        .unwrap();
        fs::write(workspace.join("decisions.md"), "# Decisions\n").unwrap();
        fs::write(workspace.join("交付记录.md"), "# 交付记录\n\n暂无。\n").unwrap();

        let dashboard =
            scan_workspaces(&root.to_string_lossy(), "~/source-repos", "~/docs").unwrap();
        assert_eq!(dashboard.workspaces.len(), 1);
        let item = &dashboard.workspaces[0];
        assert_eq!(item.name, "Demo Workspace");
        assert_eq!(item.state, "developing");
        assert_eq!(item.confirmed_services, vec!["order"]);
        assert_eq!(item.candidate_services, vec!["coupon"]);
        assert_eq!(item.task_counts.done, 1);
        assert_eq!(item.task_counts.doing, 1);
        assert_eq!(item.task_counts.todo, 1);
        assert!(item
            .risks
            .iter()
            .any(|risk| risk.contains("worktree 未创建")));
        assert!(item.risks.iter().any(|risk| risk == "交付记录待补充"));
        assert!(item.links.contains_key("workspace"));
        assert_eq!(item.activities[0].title, "worktree 未创建: order");

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn scan_workspaces_enriches_activity_from_audit_log() {
        let root = std::env::temp_dir().join(format!(
            "nexus-core-workspaces-audit-{}",
            std::process::id()
        ));
        let audit_root = root.join("audit");
        let workspace = root.join("2026-05-27-audit-demo");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(workspace.join("sql")).unwrap();
        fs::create_dir_all(&audit_root).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Audit Demo\n\n- 需求名称: Audit Demo\n- 当前状态: developing\n- 目标分支: chen/audit\n- 源仓库集合: ~/source-repos\n",
        )
        .unwrap();
        fs::write(
            workspace.join("services.md"),
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n| order | ~/source-repos/order | core |\n",
        )
        .unwrap();
        fs::write(workspace.join("tasks.md"), "# Tasks\n").unwrap();
        fs::write(workspace.join("decisions.md"), "# Decisions\n").unwrap();
        fs::write(workspace.join("交付记录.md"), "# 交付记录\n\n已补充。\n").unwrap();
        fs::write(
            audit_root.join("audit-log.jsonl"),
            r#"{"id":"create","timestamp":"2026-05-27T09:10:00Z","actor":"Nexus Test","action":"workspace.created","target":"/tmp/2026-05-27-audit-demo","summary":"Created Audit Demo","metadata":{"folder":"2026-05-27-audit-demo"}}
{"id":"instruction","timestamp":"2026-05-27T09:30:00Z","actor":"Nexus Test","action":"codex_instruction.copied","target":"/tmp/2026-05-27-audit-demo","summary":"Copied continue instruction","metadata":{"folder":"2026-05-27-audit-demo"}}
{"id":"other","timestamp":"2026-05-27T09:20:00Z","actor":"Nexus Test","action":"workspace.created","target":"/tmp/other","summary":"Created other","metadata":{"folder":"other"}}
"#,
        )
        .unwrap();

        let dashboard = scan_workspaces_with_audit(
            &root.to_string_lossy(),
            "~/source-repos",
            "~/docs",
            Some(&audit_root.to_string_lossy()),
        )
        .unwrap();
        let item = &dashboard.workspaces[0];
        assert_eq!(item.activities.len(), 2);
        assert_eq!(
            item.activities[0].title,
            "Codex 指令已复制 / Instruction copied"
        );
        assert_eq!(item.activities[0].time, "2026-05-27 09:30");
        assert!(item.activities[0].detail.contains("Copied continue instruction"));
        assert_eq!(
            item.activities[1].title,
            "工作区已创建 / Workspace created"
        );
        assert_eq!(item.activities[1].time, "2026-05-27 09:10");
        assert!(item.activities[1].detail.contains("Created Audit Demo"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn worktree_commands_use_reviewable_shell_commands() {
        let commands = worktree_commands(
            Path::new("/workspace/demo"),
            &["order".to_string()],
            "chen/demo",
            "/source",
        );
        assert!(commands.contains("git -C '/source/order' fetch origin"));
        assert!(commands.contains("worktree add '/workspace/demo/repos/order' 'chen/demo'"));
    }

    #[test]
    fn create_workspace_writes_standard_documents_and_index() {
        let root = std::env::temp_dir().join(format!(
            "nexus-core-create-workspace-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        let request = CreateWorkspaceRequest {
            name: "Demo Feature".to_string(),
            folder: "2026-05-27-demo-feature".to_string(),
            workspaces_root: root.to_string_lossy().to_string(),
            source_repos_root: "~/source-repos".to_string(),
            services: vec![
                " order ".to_string(),
                "".to_string(),
                "store-cashier".to_string(),
            ],
            target_branch: "chen/demo-feature".to_string(),
        };

        let created = create_workspace(request).unwrap();
        let workspace = Path::new(&created.path);
        assert_eq!(created.folder, "2026-05-27-demo-feature");
        assert!(workspace.join("AGENTS.md").exists());
        assert!(workspace.join("repos").is_dir());
        assert!(workspace.join("sql").is_dir());
        assert!(workspace.join("scripts/worktree-commands.sh").exists());

        let services_md = fs::read_to_string(workspace.join("services.md")).unwrap();
        assert!(services_md.contains("| order | `~/source-repos/order` | 初始确认 |"));
        assert!(
            services_md.contains("| store-cashier | `~/source-repos/store-cashier` | 初始确认 |")
        );
        let delivery = fs::read_to_string(workspace.join("交付记录.md")).unwrap();
        assert!(delivery.contains("- 分支: chen/demo-feature"));
        assert!(delivery.contains("- order"));
        let script = fs::read_to_string(workspace.join("scripts/worktree-commands.sh")).unwrap();
        assert!(script.contains("worktree add"));
        assert!(script.contains("'chen/demo-feature'"));
        let index = fs::read_to_string(root.join("INDEX.md")).unwrap();
        assert!(index.contains("| Demo Feature | analyzing | chen/demo-feature | order, store-cashier | `2026-05-27-demo-feature` |"));

        fs::remove_dir_all(root).unwrap();
    }
}
