use crate::DashboardData;
use serde::{Deserialize, Serialize};

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct WidgetSnapshot {
    pub generated_at: String,
    pub workspaces_root: String,
    pub active_workspace: Option<String>,
    pub active_workspace_folder: Option<String>,
    pub workspace_count: usize,
    pub risk_count: usize,
    pub dirty_service_count: usize,
    pub missing_worktree_count: usize,
    pub top_risks: Vec<String>,
    pub deep_link: String,
}

pub fn widget_snapshot_from_dashboard(
    dashboard: &DashboardData,
    active_folder: &str,
    generated_at: &str,
) -> WidgetSnapshot {
    let active_workspace = dashboard
        .workspaces
        .iter()
        .find(|workspace| workspace.folder == active_folder)
        .or_else(|| dashboard.workspaces.first());

    let all_git_rows = dashboard
        .workspaces
        .iter()
        .flat_map(|workspace| workspace.git_rows.iter())
        .collect::<Vec<_>>();

    WidgetSnapshot {
        generated_at: generated_at.to_string(),
        workspaces_root: dashboard.workspaces_root.clone(),
        active_workspace: active_workspace.map(|workspace| workspace.name.clone()),
        active_workspace_folder: active_workspace.map(|workspace| workspace.folder.clone()),
        workspace_count: dashboard.workspaces.len(),
        risk_count: dashboard
            .workspaces
            .iter()
            .map(|workspace| workspace.risk_count)
            .sum(),
        dirty_service_count: all_git_rows
            .iter()
            .filter(|row| row.worktree.dirty || row.source.dirty)
            .count(),
        missing_worktree_count: all_git_rows
            .iter()
            .filter(|row| !row.worktree.exists)
            .count(),
        top_risks: dashboard
            .workspaces
            .iter()
            .flat_map(|workspace| {
                workspace
                    .risks
                    .iter()
                    .map(|risk| format!("{}: {}", workspace.name, risk))
            })
            .take(3)
            .collect(),
        deep_link: active_workspace
            .map(|workspace| format!("nexus://workspace/{}", encode_component(&workspace.folder)))
            .unwrap_or_else(|| "nexus://".to_string()),
    }
}

fn encode_component(value: &str) -> String {
    let mut encoded = String::new();
    for byte in value.as_bytes() {
        if matches!(
            byte,
            b'A'..=b'Z'
                | b'a'..=b'z'
                | b'0'..=b'9'
                | b'-'
                | b'_'
                | b'.'
                | b'!'
                | b'~'
                | b'*'
                | b'\''
                | b'('
                | b')'
        ) {
            encoded.push(*byte as char);
        } else {
            encoded.push_str(&format!("%{:02X}", byte));
        }
    }
    encoded
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{GitRow, GitStatus, TaskCounts, WorkspaceData};
    use std::collections::BTreeMap;

    #[test]
    fn widget_snapshot_summarizes_dashboard_state() {
        let dashboard = DashboardData {
            generated_at: "2026-05-27T12:00:00".to_string(),
            workspaces_root: "~/ks_project/workspaces".to_string(),
            source_repos_root: "~/ks_project/source-repos".to_string(),
            docs_root: "~/ks_project/docs".to_string(),
            workspaces: vec![
                workspace(
                    "多价格开发",
                    "2026-05-25-多价格开发",
                    2,
                    vec!["交付记录待补充".to_string(), "目标分支未确认".to_string()],
                    vec![git_row("order", true, false), git_row("store", true, true)],
                ),
                workspace(
                    "易宝对账补充 pay_log",
                    "2026-05-25-yibao-pay-log",
                    1,
                    vec!["worktree 未创建: commodity".to_string()],
                    vec![git_row("commodity", false, false)],
                ),
            ],
        };

        let snapshot = widget_snapshot_from_dashboard(
            &dashboard,
            "2026-05-25-多价格开发",
            "2026-05-27T12:10:00",
        );

        assert_eq!(snapshot.generated_at, "2026-05-27T12:10:00");
        assert_eq!(snapshot.active_workspace, Some("多价格开发".to_string()));
        assert_eq!(
            snapshot.active_workspace_folder,
            Some("2026-05-25-多价格开发".to_string())
        );
        assert_eq!(snapshot.workspace_count, 2);
        assert_eq!(snapshot.risk_count, 3);
        assert_eq!(snapshot.dirty_service_count, 1);
        assert_eq!(snapshot.missing_worktree_count, 1);
        assert_eq!(snapshot.top_risks.len(), 3);
        assert_eq!(
            snapshot.deep_link,
            "nexus://workspace/2026-05-25-%E5%A4%9A%E4%BB%B7%E6%A0%BC%E5%BC%80%E5%8F%91"
        );
    }

    #[test]
    fn widget_snapshot_handles_empty_dashboards() {
        let dashboard = DashboardData {
            generated_at: "2026-05-27T12:00:00".to_string(),
            workspaces_root: "~/ks_project/workspaces".to_string(),
            source_repos_root: "~/ks_project/source-repos".to_string(),
            docs_root: "~/ks_project/docs".to_string(),
            workspaces: Vec::new(),
        };

        let snapshot = widget_snapshot_from_dashboard(&dashboard, "missing", "now");
        assert_eq!(snapshot.workspace_count, 0);
        assert_eq!(snapshot.active_workspace, None);
        assert_eq!(snapshot.deep_link, "nexus://");
    }

    fn workspace(
        name: &str,
        folder: &str,
        risk_count: usize,
        risks: Vec<String>,
        git_rows: Vec<GitRow>,
    ) -> WorkspaceData {
        WorkspaceData {
            name: name.to_string(),
            folder: folder.to_string(),
            path: format!("/workspaces/{folder}"),
            state: "developing".to_string(),
            target_branch: "chen/demo".to_string(),
            source_root: "/source".to_string(),
            confirmed_services: git_rows
                .iter()
                .map(|row| row.service.clone())
                .collect::<Vec<_>>(),
            candidate_services: Vec::new(),
            task_counts: TaskCounts::default(),
            decision_count: 0,
            git_rows,
            risks,
            risk_count,
            lifecycle: crate::WorkspaceLifecycle {
                stage: "developing".to_string(),
                label: "开发中 / Developing".to_string(),
                detail: "Widget test fixture".to_string(),
                progress: 60,
                next_action: "Continue development".to_string(),
                document_key: "handoff".to_string(),
            },
            updated: "2026-05-27".to_string(),
            links: BTreeMap::new(),
            sql_files: Vec::new(),
            worktree_command: String::new(),
            tasks: Vec::new(),
            activities: Vec::new(),
            health_checks: Vec::new(),
            session_actions: Vec::new(),
        }
    }

    fn git_row(service: &str, exists: bool, dirty: bool) -> GitRow {
        GitRow {
            service: service.to_string(),
            worktree_path: format!("/worktree/{service}"),
            source_path: format!("/source/{service}"),
            worktree: GitStatus {
                exists,
                branch: if exists { "chen/demo" } else { "未创建" }.to_string(),
                dirty,
                summary: if dirty {
                    "有未提交改动"
                } else {
                    "干净"
                }
                .to_string(),
            },
            source: GitStatus {
                exists: true,
                branch: "main".to_string(),
                dirty: false,
                summary: "干净".to_string(),
            },
        }
    }
}
