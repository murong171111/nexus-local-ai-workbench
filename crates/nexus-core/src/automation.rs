use crate::{
    append_audit_event_from_root, scan_workspaces_with_audit, AuditEventInput, WorkspaceData,
    WorkspaceTask,
};
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Clone, Debug, PartialEq, Eq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalAutomationCheckRequest {
    pub workspaces_root: String,
    pub source_repos_root: String,
    pub docs_root: String,
    pub audit_root: Option<String>,
    pub actor: Option<String>,
    pub generated_at: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalAutomationCheckResponse {
    pub generated_at: String,
    pub status: String,
    pub summary: String,
    pub workspace_count: usize,
    pub archived_workspace_count: usize,
    pub risk_count: usize,
    pub delivery_issue_count: usize,
    pub branch_mismatch_count: usize,
    pub open_task_count: usize,
    pub high_priority_task_count: usize,
    pub missing_worktree_count: usize,
    pub dirty_service_count: usize,
    pub signals: Vec<LocalAutomationSignal>,
    pub audit_event_id: Option<String>,
    pub audit_error: Option<String>,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct LocalAutomationSignal {
    pub id: String,
    pub kind: String,
    pub severity: String,
    pub title: String,
    pub detail: String,
    pub count: usize,
    pub action: String,
}

pub fn local_automation_check(
    request: LocalAutomationCheckRequest,
) -> Result<LocalAutomationCheckResponse, String> {
    let dashboard = scan_workspaces_with_audit(
        &request.workspaces_root,
        &request.source_repos_root,
        &request.docs_root,
        request.audit_root.as_deref(),
    )?;

    let mut response =
        automation_response_from_workspaces(&dashboard.workspaces, &request.generated_at);

    if let Some(audit_root) = request.audit_root.as_deref() {
        let audit_result = append_audit_event_from_root(
            audit_root,
            AuditEventInput {
                actor: request
                    .actor
                    .unwrap_or_else(|| "Nexus Automation".to_string()),
                action: "automation.check.completed".to_string(),
                target: request.workspaces_root,
                summary: response.summary.clone(),
                metadata: automation_metadata(&response),
            },
        );
        match audit_result {
            Ok(audit_response) => {
                response.audit_event_id = Some(audit_response.event.id);
            }
            Err(error) => {
                response.audit_error = Some(error);
            }
        }
    }

    Ok(response)
}

fn automation_response_from_workspaces(
    workspaces: &[WorkspaceData],
    generated_at: &str,
) -> LocalAutomationCheckResponse {
    let workspace_count = workspaces.len();
    let active_workspaces = workspaces
        .iter()
        .filter(|workspace| !workspace_is_archived(workspace))
        .collect::<Vec<_>>();
    let archived_workspace_count = workspace_count.saturating_sub(active_workspaces.len());
    let active_workspace_count = active_workspaces.len();
    let risk_count = active_workspaces
        .iter()
        .map(|workspace| workspace.risk_count)
        .sum();
    let delivery_issue_count = active_workspaces
        .iter()
        .filter(|workspace| workspace_has_delivery_issue(workspace))
        .count();
    let branch_mismatch_count = active_workspaces
        .iter()
        .filter(|workspace| workspace_has_branch_issue(workspace))
        .count();
    let open_task_count = active_workspaces
        .iter()
        .flat_map(|workspace| workspace.tasks.iter())
        .filter(|task| !task_is_done(task))
        .count();
    let high_priority_task_count = active_workspaces
        .iter()
        .flat_map(|workspace| workspace.tasks.iter())
        .filter(|task| !task_is_done(task) && task_is_high_priority(task))
        .count();
    let missing_worktree_count = active_workspaces
        .iter()
        .flat_map(|workspace| workspace.git_rows.iter())
        .filter(|row| !row.worktree.exists)
        .count();
    let dirty_service_count = active_workspaces
        .iter()
        .flat_map(|workspace| workspace.git_rows.iter())
        .filter(|row| row.worktree.dirty || row.source.dirty)
        .count();

    let mut signals = vec![LocalAutomationSignal {
        id: "refresh.completed".to_string(),
        kind: "refresh".to_string(),
        severity: "info".to_string(),
        title: "刷新完成 / Refresh completed".to_string(),
        detail: format!(
            "Scanned {workspace_count} workspaces ({archived_workspace_count} archived)."
        ),
        count: workspace_count,
        action: "refresh".to_string(),
    }];

    if risk_count > 0 {
        signals.push(LocalAutomationSignal {
            id: "risk.scan".to_string(),
            kind: "risk".to_string(),
            severity: if risk_count >= 3 { "error" } else { "warning" }.to_string(),
            title: "风险扫描 / Risk scan".to_string(),
            detail: format!("{risk_count} risk signals need review across active workspaces."),
            count: risk_count,
            action: "review-risk".to_string(),
        });
    }

    if delivery_issue_count > 0 {
        signals.push(LocalAutomationSignal {
            id: "delivery.check".to_string(),
            kind: "delivery".to_string(),
            severity: "warning".to_string(),
            title: "交付检查 / Delivery check".to_string(),
            detail: format!("{delivery_issue_count} workspaces need delivery-record attention."),
            count: delivery_issue_count,
            action: "update-delivery".to_string(),
        });
    }

    if branch_mismatch_count > 0 {
        signals.push(LocalAutomationSignal {
            id: "branch.check".to_string(),
            kind: "branch".to_string(),
            severity: "warning".to_string(),
            title: "分支检查 / Branch check".to_string(),
            detail: format!(
                "{branch_mismatch_count} workspaces have branch alignment issues."
            ),
            count: branch_mismatch_count,
            action: "review-branches".to_string(),
        });
    }

    if missing_worktree_count > 0 || dirty_service_count > 0 {
        signals.push(LocalAutomationSignal {
            id: "worktree.check".to_string(),
            kind: "worktree".to_string(),
            severity: "warning".to_string(),
            title: "Worktree 检查 / Worktree check".to_string(),
            detail: format!(
                "{missing_worktree_count} missing worktrees, {dirty_service_count} dirty services."
            ),
            count: missing_worktree_count + dirty_service_count,
            action: "review-worktrees".to_string(),
        });
    }

    if open_task_count > 0 {
        signals.push(LocalAutomationSignal {
            id: "task.check".to_string(),
            kind: "task".to_string(),
            severity: if high_priority_task_count > 0 {
                "warning"
            } else {
                "info"
            }
            .to_string(),
            title: "任务检查 / Task check".to_string(),
            detail: format!(
                "{open_task_count} open tasks, {high_priority_task_count} high priority."
            ),
            count: open_task_count,
            action: "review-tasks".to_string(),
        });
    }

    if signals.len() == 1 {
        signals.push(LocalAutomationSignal {
            id: "workspace.clean".to_string(),
            kind: "workspace".to_string(),
            severity: "info".to_string(),
            title: "状态清洁 / Clean state".to_string(),
            detail: "No active risk, delivery, worktree, or task attention signals.".to_string(),
            count: active_workspace_count,
            action: "none".to_string(),
        });
    }

    let status = if signals.iter().any(|signal| signal.severity == "error") {
        "attention"
    } else if signals.iter().any(|signal| signal.severity == "warning") {
        "review"
    } else {
        "clean"
    }
    .to_string();

    let summary = match status.as_str() {
        "attention" => format!(
            "Automation check found {risk_count} risks and {high_priority_task_count} high-priority tasks."
        ),
        "review" => format!(
            "Automation check found {risk_count} risks, {delivery_issue_count} delivery issues, {branch_mismatch_count} branch issues, and {open_task_count} open tasks."
        ),
        _ => format!("Automation check passed for {active_workspace_count} active workspaces."),
    };

    LocalAutomationCheckResponse {
        generated_at: generated_at.to_string(),
        status,
        summary,
        workspace_count,
        archived_workspace_count,
        risk_count,
        delivery_issue_count,
        branch_mismatch_count,
        open_task_count,
        high_priority_task_count,
        missing_worktree_count,
        dirty_service_count,
        signals,
        audit_event_id: None,
        audit_error: None,
    }
}

fn automation_metadata(response: &LocalAutomationCheckResponse) -> BTreeMap<String, String> {
    [
        ("generatedAt".to_string(), response.generated_at.clone()),
        ("status".to_string(), response.status.clone()),
        (
            "workspaceCount".to_string(),
            response.workspace_count.to_string(),
        ),
        (
            "archivedWorkspaceCount".to_string(),
            response.archived_workspace_count.to_string(),
        ),
        ("riskCount".to_string(), response.risk_count.to_string()),
        (
            "deliveryIssueCount".to_string(),
            response.delivery_issue_count.to_string(),
        ),
        (
            "branchMismatchCount".to_string(),
            response.branch_mismatch_count.to_string(),
        ),
        (
            "openTaskCount".to_string(),
            response.open_task_count.to_string(),
        ),
        (
            "highPriorityTaskCount".to_string(),
            response.high_priority_task_count.to_string(),
        ),
        (
            "missingWorktreeCount".to_string(),
            response.missing_worktree_count.to_string(),
        ),
        (
            "dirtyServiceCount".to_string(),
            response.dirty_service_count.to_string(),
        ),
        (
            "signals".to_string(),
            response
                .signals
                .iter()
                .map(|signal| signal.id.as_str())
                .collect::<Vec<_>>()
                .join(","),
        ),
    ]
    .into_iter()
    .collect()
}

fn workspace_is_archived(workspace: &WorkspaceData) -> bool {
    let normalized = format!("{} {}", workspace.state, workspace.lifecycle.stage).to_lowercase();
    normalized.contains("archived")
        || normalized.contains("archive")
        || normalized.contains("归档")
        || normalized.contains("已归档")
}

fn workspace_has_delivery_issue(workspace: &WorkspaceData) -> bool {
    workspace.risks.iter().any(|risk| {
        let normalized = risk.to_lowercase();
        risk.contains("交付记录")
            || risk.contains("SQL 变更")
            || normalized.contains("delivery")
            || normalized.contains("sql")
    }) || workspace.health_checks.iter().any(|check| {
        matches!(check.id.as_str(), "delivery-record" | "sql-directory")
            && !matches!(check.status.as_str(), "pass" | "ok")
    })
}

fn workspace_has_branch_issue(workspace: &WorkspaceData) -> bool {
    workspace.risks.iter().any(|risk| {
        let normalized = risk.to_lowercase();
        risk.contains("分支不一致") || normalized.contains("branch mismatch")
    }) || workspace.health_checks.iter().any(|check| {
        check.id == "branch-alignment" && !matches!(check.status.as_str(), "pass" | "ok")
    })
}

fn task_is_done(task: &WorkspaceTask) -> bool {
    let normalized = task.status.to_lowercase();
    normalized.contains("完成")
        || normalized.contains("done")
        || normalized.contains("closed")
        || normalized.contains("resolved")
}

fn task_is_high_priority(task: &WorkspaceTask) -> bool {
    let normalized = format!("{} {} {}", task.status, task.priority, task.detail).to_lowercase();
    normalized.contains("priority=high")
        || normalized.contains("priority=critical")
        || normalized.contains("high")
        || normalized.contains("critical")
        || normalized.contains("阻塞")
        || normalized.contains("blocked")
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::fs;
    use std::process::Command;

    #[test]
    fn local_automation_check_reports_risk_delivery_tasks_and_audit_event() {
        let root =
            std::env::temp_dir().join(format!("nexus-core-automation-{}", std::process::id()));
        let audit_root = root.join("audit");
        let workspace = root.join("2026-05-28-automation-demo");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(workspace.join("sql")).unwrap();
        fs::create_dir_all(&audit_root).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Automation Demo\n\n- 需求名称: Automation Demo\n- 当前状态: developing\n- 目标分支: chen/automation\n- 源仓库集合: ~/source-repos\n",
        )
        .unwrap();
        fs::write(
            workspace.join("services.md"),
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n| order | ~/source-repos/order | core |\n",
        )
        .unwrap();
        fs::write(
            workspace.join("tasks.md"),
            "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| 修复风险 | 待办 | priority=high |\n| 已完成任务 | 已完成 | ok |\n",
        )
        .unwrap();
        fs::write(workspace.join("decisions.md"), "# Decisions\n").unwrap();
        fs::write(workspace.join("交付记录.md"), "# 交付记录\n\n暂无。\n").unwrap();

        let response = local_automation_check(LocalAutomationCheckRequest {
            workspaces_root: root.to_string_lossy().to_string(),
            source_repos_root: "~/source-repos".to_string(),
            docs_root: "~/docs".to_string(),
            audit_root: Some(audit_root.to_string_lossy().to_string()),
            actor: Some("Nexus Test".to_string()),
            generated_at: "2026-05-28T10:00:00Z".to_string(),
        })
        .unwrap();

        assert_eq!(response.workspace_count, 1);
        assert_eq!(response.archived_workspace_count, 0);
        assert!(response.risk_count > 0);
        assert_eq!(response.delivery_issue_count, 1);
        assert_eq!(response.branch_mismatch_count, 0);
        assert_eq!(response.open_task_count, 1);
        assert_eq!(response.high_priority_task_count, 1);
        assert_eq!(response.missing_worktree_count, 1);
        assert_eq!(response.status, "review");
        assert!(response.audit_event_id.is_some());
        assert!(response.audit_error.is_none());
        assert!(response
            .signals
            .iter()
            .any(|signal| signal.id == "risk.scan"));
        assert!(response
            .signals
            .iter()
            .any(|signal| signal.id == "delivery.check"));
        assert!(response
            .signals
            .iter()
            .any(|signal| signal.id == "task.check" && signal.severity == "warning"));

        let audit_log = fs::read_to_string(audit_root.join("audit-log.jsonl")).unwrap();
        assert!(audit_log.contains("automation.check.completed"));
        assert!(audit_log.contains("Nexus Test"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn local_automation_check_reports_branch_alignment_signal() {
        let root = std::env::temp_dir().join(format!(
            "nexus-core-automation-branch-{}",
            std::process::id()
        ));
        let workspace = root.join("2026-05-31-branch-demo");
        let worktree = workspace.join("repos").join("order");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(workspace.join("sql")).unwrap();
        fs::create_dir_all(&worktree).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Branch Demo\n\n- 需求名称: Branch Demo\n- 当前状态: developing\n- 目标分支: chen/target-branch\n- 源仓库集合: ~/source-repos\n",
        )
        .unwrap();
        fs::write(
            workspace.join("services.md"),
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n| order | ~/source-repos/order | core |\n",
        )
        .unwrap();
        fs::write(workspace.join("tasks.md"), "# Tasks\n").unwrap();
        fs::write(
            workspace.join("交付记录.md"),
            "# 交付记录\n\n## SQL 变更\n\n- 是否有 SQL 变更：否\n",
        )
        .unwrap();
        let init_status = Command::new("git")
            .args(["init", "-b", "chen/old-branch"])
            .current_dir(&worktree)
            .status()
            .unwrap();
        assert!(init_status.success());

        let response = local_automation_check(LocalAutomationCheckRequest {
            workspaces_root: root.to_string_lossy().to_string(),
            source_repos_root: "~/source-repos".to_string(),
            docs_root: "~/docs".to_string(),
            audit_root: None,
            actor: None,
            generated_at: "2026-05-31T10:00:00Z".to_string(),
        })
        .unwrap();

        assert_eq!(response.branch_mismatch_count, 1);
        assert!(response.signals.iter().any(|signal| {
            signal.id == "branch.check"
                && signal.action == "review-branches"
                && signal.count == 1
        }));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn local_automation_check_excludes_archived_workspaces_from_attention_signals() {
        let root = std::env::temp_dir().join(format!(
            "nexus-core-automation-archived-{}",
            std::process::id()
        ));
        let workspace = root.join("2026-05-28-archived-demo");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&workspace).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Archived Demo\n\n- 需求名称: Archived Demo\n- 当前状态: archived\n- 目标分支: chen/archived-demo\n- 源仓库集合: ~/source-repos\n",
        )
        .unwrap();
        fs::write(
            workspace.join("STATUS.md"),
            "# STATUS\n\n- 状态: archived\n",
        )
        .unwrap();
        fs::write(
            workspace.join("services.md"),
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n| order | ~/source-repos/order | archived |\n",
        )
        .unwrap();
        fs::write(
            workspace.join("tasks.md"),
            "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| 历史高优先任务 | 待办 | priority=high |\n",
        )
        .unwrap();
        fs::write(workspace.join("交付记录.md"), "# 交付记录\n\n暂无。\n").unwrap();

        let response = local_automation_check(LocalAutomationCheckRequest {
            workspaces_root: root.to_string_lossy().to_string(),
            source_repos_root: "~/source-repos".to_string(),
            docs_root: "~/docs".to_string(),
            audit_root: None,
            actor: Some("Nexus Test".to_string()),
            generated_at: "2026-05-28T10:00:00Z".to_string(),
        })
        .unwrap();

        assert_eq!(response.workspace_count, 1);
        assert_eq!(response.archived_workspace_count, 1);
        assert_eq!(response.risk_count, 0);
        assert_eq!(response.delivery_issue_count, 0);
        assert_eq!(response.open_task_count, 0);
        assert_eq!(response.high_priority_task_count, 0);
        assert_eq!(response.missing_worktree_count, 0);
        assert_eq!(response.dirty_service_count, 0);
        assert_eq!(response.status, "clean");
        assert!(!response.signals.iter().any(|signal| matches!(
            signal.id.as_str(),
            "risk.scan" | "delivery.check" | "task.check" | "worktree.check"
        )));

        fs::remove_dir_all(root).unwrap();
    }
}
