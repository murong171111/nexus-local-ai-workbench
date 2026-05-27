use crate::{
    expand_user_path, git_status, normalize_git_branch, target_branch_confirmed, GitStatus,
};
use serde::Serialize;
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
pub struct GitRow {
    pub service: String,
    pub worktree_path: String,
    pub source_path: String,
    pub worktree: GitStatus,
    pub source: GitStatus,
}

pub fn scan_workspaces(
    workspaces_root: &str,
    source_repos_root: &str,
    docs_root: &str,
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

    let mut workspaces = Vec::new();
    let entries = fs::read_dir(&root).map_err(|error| error.to_string())?;
    for entry in entries {
        let entry = entry.map_err(|error| error.to_string())?;
        let path = entry.path();
        let name = entry.file_name().to_string_lossy().to_string();
        if !path.is_dir() || name == "dashboard" || name.starts_with('.') {
            continue;
        }
        workspaces.push(collect_workspace(&path, source_repos_root));
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

fn collect_workspace(path: &Path, default_source_root: &str) -> WorkspaceData {
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
}
