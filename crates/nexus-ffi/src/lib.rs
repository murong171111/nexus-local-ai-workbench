use nexus_core::{
    agent_event_handoff_prompt, agent_event_task_draft, append_agent_event_from_root,
    append_agent_task_draft, append_audit_event_from_root, create_workspace,
    create_workspace_document, local_automation_check, read_agent_events_from_root, read_document,
    rebuild_search_index, scan_source_repos, scan_workspaces, scan_workspaces_with_audit,
    search_index, setup_worktrees, update_workspace_lifecycle, update_workspace_task,
    widget_snapshot_from_dashboard, workspace_task_handoff_prompt, AgentEvent, AgentEventInput,
    AgentEventTaskDraftResponse, AppendAgentTaskDraftRequest as CoreAppendAgentTaskDraftRequest,
    AuditEventInput, CreateWorkspaceDocumentRequest as CoreCreateWorkspaceDocumentRequest,
    CreateWorkspaceRequest as CoreCreateWorkspaceRequest,
    LocalAutomationCheckRequest as CoreLocalAutomationCheckRequest,
    SetupWorktreesRequest as CoreSetupWorktreesRequest,
    UpdateWorkspaceLifecycleRequest as CoreUpdateWorkspaceLifecycleRequest,
    UpdateWorkspaceTaskRequest as CoreUpdateWorkspaceTaskRequest, WorkspaceTask,
    WorkspaceTaskHandoffPromptRequest,
};
use serde::{de::DeserializeOwned, Deserialize, Serialize};
use std::ffi::{CStr, CString};
use std::os::raw::c_char;

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScanWorkspacesRequest {
    workspaces_root: String,
    source_repos_root: String,
    docs_root: String,
    audit_root: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ScanSourceReposRequest {
    source_repos_root: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReadDocumentRequest {
    path: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateWorkspaceDocumentBridgeRequest {
    workspace_path: String,
    document_key: String,
    relative_path: String,
    confirmed: bool,
    audit_root: Option<String>,
    actor: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WidgetSnapshotRequest {
    workspaces_root: String,
    source_repos_root: String,
    docs_root: String,
    active_folder: String,
    generated_at: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct CreateWorkspaceBridgeRequest {
    name: String,
    folder: String,
    workspaces_root: String,
    source_repos_root: String,
    services: Vec<String>,
    target_branch: String,
    confirmed: bool,
    audit_root: Option<String>,
    actor: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SetupWorktreesBridgeRequest {
    workspace_path: String,
    source_repos_root: String,
    services: Vec<String>,
    target_branch: String,
    confirmed: bool,
    audit_root: Option<String>,
    actor: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppendAuditEventBridgeRequest {
    audit_root: String,
    event: AuditEventInput,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppendAgentEventBridgeRequest {
    events_root: String,
    event: AgentEventInput,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct ReadAgentEventsBridgeRequest {
    events_root: String,
    limit: Option<usize>,
    workspace_folder: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AgentEventHandoffPromptBridgeRequest {
    event: AgentEvent,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AgentEventTaskDraftBridgeRequest {
    event: AgentEvent,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct AppendAgentTaskDraftBridgeRequest {
    workspace_path: String,
    draft: AgentEventTaskDraftResponse,
    confirmed: bool,
    audit_root: Option<String>,
    actor: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpdateWorkspaceTaskBridgeRequest {
    workspace_path: String,
    task_id: String,
    status: String,
    detail: Option<String>,
    confirmed: bool,
    audit_root: Option<String>,
    actor: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct UpdateWorkspaceLifecycleBridgeRequest {
    workspace_path: String,
    state: String,
    focus: Option<String>,
    next_action: Option<String>,
    confirmed: bool,
    audit_root: Option<String>,
    actor: Option<String>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct WorkspaceTaskHandoffPromptBridgeRequest {
    workspace_name: String,
    workspace_folder: String,
    workspace_path: String,
    target_branch: String,
    source_root: String,
    task: WorkspaceTask,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct RebuildSearchIndexBridgeRequest {
    index_path: String,
    workspaces_root: String,
    source_repos_root: String,
    docs_root: String,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct SearchIndexBridgeRequest {
    index_path: String,
    query: String,
    limit: Option<usize>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "camelCase")]
struct LocalAutomationCheckBridgeRequest {
    workspaces_root: String,
    source_repos_root: String,
    docs_root: String,
    audit_root: Option<String>,
    actor: Option<String>,
    generated_at: String,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
struct BridgeResponse<T: Serialize> {
    ok: bool,
    data: Option<T>,
    error: Option<String>,
}

#[no_mangle]
pub unsafe extern "C" fn nexus_scan_workspaces_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: ScanWorkspacesRequest| {
        scan_workspaces_with_audit(
            &request.workspaces_root,
            &request.source_repos_root,
            &request.docs_root,
            request.audit_root.as_deref(),
        )
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_scan_source_repos_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: ScanSourceReposRequest| {
        scan_source_repos(&request.source_repos_root)
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_read_document_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: ReadDocumentRequest| {
        read_document(&request.path)
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_create_workspace_document_json(
    input_json: *const c_char,
) -> *mut c_char {
    bridge_call(
        input_json,
        |request: CreateWorkspaceDocumentBridgeRequest| {
            let response = create_workspace_document(CoreCreateWorkspaceDocumentRequest {
                workspace_path: request.workspace_path.clone(),
                document_key: request.document_key.clone(),
                relative_path: request.relative_path.clone(),
                confirmed: request.confirmed,
            })?;

            if response.created {
                if let Some(audit_root) = request.audit_root.as_deref() {
                    let _ = append_audit_event_from_root(
                        audit_root,
                        AuditEventInput {
                            actor: request.actor.unwrap_or_else(|| "Nexus Native".to_string()),
                            action: "document.created".to_string(),
                            target: response.path.clone(),
                            summary: format!(
                                "Created workspace document {}",
                                response.relative_path
                            ),
                            metadata: [
                                ("workspace".to_string(), request.workspace_path),
                                ("documentKey".to_string(), response.document_key.clone()),
                                ("relativePath".to_string(), response.relative_path.clone()),
                                ("documentPath".to_string(), response.path.clone()),
                            ]
                            .into_iter()
                            .collect(),
                        },
                    );
                }
            }

            Ok(response)
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn nexus_widget_snapshot_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: WidgetSnapshotRequest| {
        scan_workspaces(
            &request.workspaces_root,
            &request.source_repos_root,
            &request.docs_root,
        )
        .map(|dashboard| {
            widget_snapshot_from_dashboard(
                &dashboard,
                &request.active_folder,
                &request.generated_at,
            )
        })
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_append_audit_event_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: AppendAuditEventBridgeRequest| {
        append_audit_event_from_root(&request.audit_root, request.event)
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_append_agent_event_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: AppendAgentEventBridgeRequest| {
        append_agent_event_from_root(&request.events_root, request.event)
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_read_agent_events_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: ReadAgentEventsBridgeRequest| {
        read_agent_events_from_root(
            &request.events_root,
            request.limit.unwrap_or(20),
            request.workspace_folder.as_deref(),
        )
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_agent_event_handoff_prompt_json(
    input_json: *const c_char,
) -> *mut c_char {
    bridge_call(
        input_json,
        |request: AgentEventHandoffPromptBridgeRequest| {
            Ok(agent_event_handoff_prompt(&request.event))
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn nexus_agent_event_task_draft_json(
    input_json: *const c_char,
) -> *mut c_char {
    bridge_call(input_json, |request: AgentEventTaskDraftBridgeRequest| {
        Ok(agent_event_task_draft(&request.event))
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_append_agent_task_draft_json(
    input_json: *const c_char,
) -> *mut c_char {
    bridge_call(input_json, |request: AppendAgentTaskDraftBridgeRequest| {
        let response = append_agent_task_draft(CoreAppendAgentTaskDraftRequest {
            workspace_path: request.workspace_path.clone(),
            draft: request.draft.clone(),
            confirmed: request.confirmed,
        })?;

        if response.appended {
            if let Some(audit_root) = request.audit_root.as_deref() {
                let _ = append_audit_event_from_root(
                    audit_root,
                    AuditEventInput {
                        actor: request.actor.unwrap_or_else(|| "Nexus Native".to_string()),
                        action: "agent_task_draft.appended".to_string(),
                        target: response.path.clone(),
                        summary: format!("Added task draft {}", response.title),
                        metadata: [
                            ("workspace".to_string(), request.workspace_path),
                            (
                                "sourceEventId".to_string(),
                                response.source_event_id.clone(),
                            ),
                            ("taskTitle".to_string(), response.title.clone()),
                            ("category".to_string(), request.draft.category),
                            ("priority".to_string(), request.draft.priority),
                        ]
                        .into_iter()
                        .collect(),
                    },
                );
            }
        }

        Ok(response)
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_update_workspace_task_json(
    input_json: *const c_char,
) -> *mut c_char {
    bridge_call(input_json, |request: UpdateWorkspaceTaskBridgeRequest| {
        let response = update_workspace_task(CoreUpdateWorkspaceTaskRequest {
            workspace_path: request.workspace_path.clone(),
            task_id: request.task_id.clone(),
            status: request.status.clone(),
            detail: request.detail.clone(),
            confirmed: request.confirmed,
        })?;

        if response.updated {
            if let Some(audit_root) = request.audit_root.as_deref() {
                let _ = append_audit_event_from_root(
                    audit_root,
                    AuditEventInput {
                        actor: request.actor.unwrap_or_else(|| "Nexus Native".to_string()),
                        action: "workspace_task.updated".to_string(),
                        target: response.path.clone(),
                        summary: format!(
                            "Updated task {} from {} to {}",
                            response.task.title, response.previous_status, response.task.status
                        ),
                        metadata: [
                            ("workspace".to_string(), request.workspace_path),
                            ("taskId".to_string(), request.task_id),
                            ("taskTitle".to_string(), response.task.title.clone()),
                            (
                                "previousStatus".to_string(),
                                response.previous_status.clone(),
                            ),
                            ("status".to_string(), response.task.status.clone()),
                        ]
                        .into_iter()
                        .collect(),
                    },
                );
            }
        }

        Ok(response)
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_update_workspace_lifecycle_json(
    input_json: *const c_char,
) -> *mut c_char {
    bridge_call(
        input_json,
        |request: UpdateWorkspaceLifecycleBridgeRequest| {
            let response = update_workspace_lifecycle(CoreUpdateWorkspaceLifecycleRequest {
                workspace_path: request.workspace_path.clone(),
                state: request.state.clone(),
                focus: request.focus.clone(),
                next_action: request.next_action.clone(),
                confirmed: request.confirmed,
            })?;

            if response.updated {
                if let Some(audit_root) = request.audit_root.as_deref() {
                    let _ = append_audit_event_from_root(
                        audit_root,
                        AuditEventInput {
                            actor: request.actor.unwrap_or_else(|| "Nexus Native".to_string()),
                            action: "workspace_lifecycle.updated".to_string(),
                            target: response.workspace_path.clone(),
                            summary: format!(
                                "Updated lifecycle from {} to {}",
                                response.previous_state, response.state
                            ),
                            metadata: [
                                ("workspace".to_string(), request.workspace_path),
                                ("previousState".to_string(), response.previous_state.clone()),
                                ("state".to_string(), response.state.clone()),
                                ("focus".to_string(), response.focus.clone()),
                                ("nextAction".to_string(), response.next_action.clone()),
                            ]
                            .into_iter()
                            .collect(),
                        },
                    );
                }
            }

            Ok(response)
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn nexus_workspace_task_handoff_prompt_json(
    input_json: *const c_char,
) -> *mut c_char {
    bridge_call(
        input_json,
        |request: WorkspaceTaskHandoffPromptBridgeRequest| {
            Ok(workspace_task_handoff_prompt(
                &WorkspaceTaskHandoffPromptRequest {
                    workspace_name: request.workspace_name,
                    workspace_folder: request.workspace_folder,
                    workspace_path: request.workspace_path,
                    target_branch: request.target_branch,
                    source_root: request.source_root,
                    task: request.task,
                },
            ))
        },
    )
}

#[no_mangle]
pub unsafe extern "C" fn nexus_rebuild_search_index_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: RebuildSearchIndexBridgeRequest| {
        rebuild_search_index(
            &request.index_path,
            &request.workspaces_root,
            &request.source_repos_root,
            &request.docs_root,
        )
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_search_index_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: SearchIndexBridgeRequest| {
        search_index(
            &request.index_path,
            &request.query,
            request.limit.unwrap_or(20),
        )
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_local_automation_check_json(
    input_json: *const c_char,
) -> *mut c_char {
    bridge_call(input_json, |request: LocalAutomationCheckBridgeRequest| {
        local_automation_check(CoreLocalAutomationCheckRequest {
            workspaces_root: request.workspaces_root,
            source_repos_root: request.source_repos_root,
            docs_root: request.docs_root,
            audit_root: request.audit_root,
            actor: request.actor,
            generated_at: request.generated_at,
        })
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_create_workspace_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: CreateWorkspaceBridgeRequest| {
        if !request.confirmed {
            return Err("workspace creation requires explicit confirmation".to_string());
        }

        let response = create_workspace(CoreCreateWorkspaceRequest {
            name: request.name.clone(),
            folder: request.folder.clone(),
            workspaces_root: request.workspaces_root.clone(),
            source_repos_root: request.source_repos_root.clone(),
            services: request.services.clone(),
            target_branch: request.target_branch.clone(),
        })?;

        if let Some(audit_root) = request.audit_root.as_deref() {
            let _ = append_audit_event_from_root(
                audit_root,
                AuditEventInput {
                    actor: request.actor.unwrap_or_else(|| "Nexus Native".to_string()),
                    action: "workspace.created".to_string(),
                    target: response.path.clone(),
                    summary: format!("Created workspace {}", request.name),
                    metadata: [
                        ("name".to_string(), request.name),
                        ("folder".to_string(), request.folder),
                        ("services".to_string(), request.services.join(",")),
                        ("targetBranch".to_string(), request.target_branch),
                        ("workspacesRoot".to_string(), request.workspaces_root),
                        ("sourceReposRoot".to_string(), request.source_repos_root),
                    ]
                    .into_iter()
                    .collect(),
                },
            );
        }

        Ok(response)
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_setup_worktrees_json(input_json: *const c_char) -> *mut c_char {
    bridge_call(input_json, |request: SetupWorktreesBridgeRequest| {
        if !request.confirmed {
            return Err("worktree setup requires explicit confirmation".to_string());
        }

        let response = setup_worktrees(CoreSetupWorktreesRequest {
            workspace_path: request.workspace_path.clone(),
            source_repos_root: request.source_repos_root.clone(),
            services: request.services.clone(),
            target_branch: request.target_branch.clone(),
            confirmed: request.confirmed,
        })?;

        if let Some(audit_root) = request.audit_root.as_deref() {
            let _ = append_audit_event_from_root(
                audit_root,
                AuditEventInput {
                    actor: request.actor.unwrap_or_else(|| "Nexus Native".to_string()),
                    action: "worktree.setup.executed".to_string(),
                    target: response.workspace_path.clone(),
                    summary: format!(
                        "Created {} worktrees, skipped {}, failed {}",
                        response.created.len(),
                        response.skipped.len(),
                        response.failed.len()
                    ),
                    metadata: [
                        ("workspace".to_string(), response.workspace_path.clone()),
                        ("services".to_string(), request.services.join(",")),
                        ("targetBranch".to_string(), response.target_branch.clone()),
                        ("created".to_string(), response.created.len().to_string()),
                        ("skipped".to_string(), response.skipped.len().to_string()),
                        ("failed".to_string(), response.failed.len().to_string()),
                    ]
                    .into_iter()
                    .collect(),
                },
            );
        }

        Ok(response)
    })
}

#[no_mangle]
pub unsafe extern "C" fn nexus_string_free(value: *mut c_char) {
    if !value.is_null() {
        let _ = CString::from_raw(value);
    }
}

unsafe fn bridge_call<Request, Response, Handler>(
    input_json: *const c_char,
    handler: Handler,
) -> *mut c_char
where
    Request: DeserializeOwned,
    Response: Serialize,
    Handler: FnOnce(Request) -> Result<Response, String>,
{
    if input_json.is_null() {
        return into_c_string(error_response::<Response>("input json pointer is null"));
    }

    let input = match CStr::from_ptr(input_json).to_str() {
        Ok(value) => value,
        Err(error) => {
            return into_c_string(error_response::<Response>(&format!(
                "input json is not valid utf-8: {error}"
            )))
        }
    };

    let request = match serde_json::from_str::<Request>(input) {
        Ok(request) => request,
        Err(error) => {
            return into_c_string(error_response::<Response>(&format!(
                "input json could not be decoded: {error}"
            )))
        }
    };

    match handler(request) {
        Ok(data) => into_c_string(BridgeResponse {
            ok: true,
            data: Some(data),
            error: None,
        }),
        Err(error) => into_c_string(error_response::<Response>(&error)),
    }
}

fn error_response<T: Serialize>(error: &str) -> BridgeResponse<T> {
    BridgeResponse {
        ok: false,
        data: None,
        error: Some(error.to_string()),
    }
}

fn into_c_string<T: Serialize>(value: T) -> *mut c_char {
    let payload = serde_json::to_string(&value)
        .unwrap_or_else(|error| format!(r#"{{"ok":false,"data":null,"error":"{error}"}}"#))
        .replace('\0', "\\u0000");
    CString::new(payload)
        .expect("nul bytes are escaped before CString creation")
        .into_raw()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::Value;
    use std::fs;

    #[test]
    fn scan_workspaces_bridge_returns_dashboard_json() {
        let root =
            std::env::temp_dir().join(format!("nexus-ffi-workspaces-{}", std::process::id()));
        let audit_root = root.join("audit");
        let workspace = root.join("2026-05-27-bridge-demo");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(workspace.join("sql")).unwrap();
        fs::create_dir_all(&audit_root).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Bridge Demo\n\n- 需求名称: Bridge Demo\n- 当前状态: developing\n- 目标分支: chen/bridge\n- 源仓库集合: ~/source-repos\n",
        )
        .unwrap();
        fs::write(
            workspace.join("services.md"),
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n| order | ~/source-repos/order | core |\n",
        )
        .unwrap();
        fs::write(
            workspace.join("tasks.md"),
            "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| 核对任务中心 | 进行中 | priority=high event=bridge-task |\n",
        )
        .unwrap();
        fs::write(workspace.join("decisions.md"), "# Decisions\n").unwrap();
        fs::write(workspace.join("交付记录.md"), "# 交付记录\n\n暂无。\n").unwrap();
        fs::write(
            audit_root.join("audit-log.jsonl"),
            r#"{"id":"bridge-create","timestamp":"2026-05-27T09:30:00Z","actor":"Nexus Test","action":"workspace.created","target":"/tmp/2026-05-27-bridge-demo","summary":"Created Bridge Demo","metadata":{"folder":"2026-05-27-bridge-demo"}}
"#,
        )
        .unwrap();

        let request = format!(
            r#"{{"workspacesRoot":"{}","sourceReposRoot":"~/source-repos","docsRoot":"~/docs","auditRoot":"{}"}}"#,
            root.to_string_lossy(),
            audit_root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_scan_workspaces_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["workspaces"][0]["name"], "Bridge Demo");
        assert_eq!(
            value["data"]["workspaces"][0]["targetBranch"],
            "chen/bridge"
        );
        assert_eq!(
            value["data"]["workspaces"][0]["activities"][0]["title"],
            "工作区已创建 / Workspace created"
        );
        assert_eq!(
            value["data"]["workspaces"][0]["healthChecks"][0]["id"],
            "service-scope"
        );
        assert_eq!(
            value["data"]["workspaces"][0]["sessionActions"][0]["id"],
            "create-worktrees"
        );
        assert_eq!(
            value["data"]["workspaces"][0]["tasks"][0]["title"],
            "核对任务中心"
        );
        assert_eq!(
            value["data"]["workspaces"][0]["tasks"][0]["priority"],
            "high"
        );
        assert_eq!(
            value["data"]["workspaces"][0]["tasks"][0]["sourceEventId"],
            "bridge-task"
        );
        assert_eq!(value["data"]["workspaces"][0]["tasks"][0]["sourceLine"], 5);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn bridge_returns_json_error_for_invalid_input() {
        let input = CString::new("{not-json").unwrap();
        let output = unsafe { nexus_scan_source_repos_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], false);
        assert!(value["error"]
            .as_str()
            .unwrap()
            .contains("input json could not be decoded"));
    }

    #[test]
    fn read_document_bridge_returns_document_snapshot() {
        let root = std::env::temp_dir().join(format!("nexus-ffi-document-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        let document = root.join("handoff.md");
        fs::write(&document, "# Handoff\n\nReady.\n").unwrap();

        let request = format!(r#"{{"path":"{}"}}"#, document.to_string_lossy());
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_read_document_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["name"], "handoff.md");
        assert_eq!(value["data"]["isMarkdown"], true);
        assert!(value["data"]["content"].as_str().unwrap().contains("Ready"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn create_workspace_document_bridge_writes_file_and_audit() {
        let root =
            std::env::temp_dir().join(format!("nexus-ffi-create-document-{}", std::process::id()));
        let workspace = root.join("2026-05-29-document-demo");
        let audit_root = root.join("audit");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&workspace).unwrap();
        fs::create_dir_all(&audit_root).unwrap();

        let request = format!(
            r#"{{"workspacePath":"{}","documentKey":"tasks","relativePath":"tasks.md","confirmed":true,"auditRoot":"{}","actor":"Nexus FFI Test"}}"#,
            workspace.to_string_lossy(),
            audit_root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_create_workspace_document_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["created"], true);
        assert_eq!(value["data"]["relativePath"], "tasks.md");
        assert!(fs::read_to_string(workspace.join("tasks.md"))
            .unwrap()
            .contains("| 任务 | 状态 | 说明 |"));

        let audit_log = fs::read_to_string(audit_root.join("audit-log.jsonl")).unwrap();
        assert!(audit_log.contains("document.created"));
        assert!(audit_log.contains("tasks.md"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn widget_snapshot_bridge_returns_compact_status_payload() {
        let root = std::env::temp_dir().join(format!("nexus-ffi-widget-{}", std::process::id()));
        let workspace = root.join("2026-05-27-widget-demo");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(workspace.join("sql")).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Widget Demo\n\n- 需求名称: Widget Demo\n- 当前状态: developing\n- 目标分支: chen/widget\n- 源仓库集合: ~/source-repos\n",
        )
        .unwrap();
        fs::write(
            workspace.join("services.md"),
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n| order | ~/source-repos/order | core |\n",
        )
        .unwrap();
        fs::write(workspace.join("tasks.md"), "# Tasks\n").unwrap();
        fs::write(workspace.join("decisions.md"), "# Decisions\n").unwrap();
        fs::write(workspace.join("交付记录.md"), "# 交付记录\n\n暂无。\n").unwrap();

        let request = format!(
            r#"{{"workspacesRoot":"{}","sourceReposRoot":"~/source-repos","docsRoot":"~/docs","activeFolder":"2026-05-27-widget-demo","generatedAt":"2026-05-27T12:30:00"}}"#,
            root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_widget_snapshot_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["activeWorkspace"], "Widget Demo");
        assert_eq!(value["data"]["workspaceCount"], 1);
        assert_eq!(value["data"]["generatedAt"], "2026-05-27T12:30:00");
        assert_eq!(
            value["data"]["deepLink"],
            "nexus://workspace/2026-05-27-widget-demo"
        );

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn local_automation_check_bridge_returns_signals_and_audit() {
        let root =
            std::env::temp_dir().join(format!("nexus-ffi-automation-{}", std::process::id()));
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
            "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| 核对风险 | 待办 | priority=high |\n",
        )
        .unwrap();
        fs::write(workspace.join("decisions.md"), "# Decisions\n").unwrap();
        fs::write(workspace.join("交付记录.md"), "# 交付记录\n\n暂无。\n").unwrap();

        let request = format!(
            r#"{{"workspacesRoot":"{}","sourceReposRoot":"~/source-repos","docsRoot":"~/docs","auditRoot":"{}","actor":"Nexus FFI Test","generatedAt":"2026-05-28T10:30:00Z"}}"#,
            root.to_string_lossy(),
            audit_root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_local_automation_check_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["workspaceCount"], 1);
        assert_eq!(value["data"]["deliveryIssueCount"], 1);
        assert_eq!(value["data"]["openTaskCount"], 1);
        assert_eq!(value["data"]["signals"][0]["id"], "refresh.completed");
        assert_eq!(value["data"]["auditError"], Value::Null);
        assert!(value["data"]["auditEventId"].as_str().is_some());

        let audit_log = fs::read_to_string(audit_root.join("audit-log.jsonl")).unwrap();
        assert!(audit_log.contains("automation.check.completed"));
        assert!(audit_log.contains("Nexus FFI Test"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn append_audit_event_bridge_writes_jsonl() {
        let root = std::env::temp_dir().join(format!("nexus-ffi-audit-{}", std::process::id()));
        let audit_root = root.join("audit");
        let _ = fs::remove_dir_all(&root);
        let request = format!(
            r#"{{"auditRoot":"{}","event":{{"actor":"Nexus Test","action":"workspace.created","target":"/tmp/demo","summary":"Created demo workspace","metadata":{{"folder":"2026-05-27-demo"}}}}}}"#,
            audit_root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_append_audit_event_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["event"]["action"], "workspace.created");
        let path = value["data"]["path"].as_str().unwrap();
        assert!(path.ends_with("audit-log.jsonl"));
        let lines = fs::read_to_string(path).unwrap();
        assert_eq!(lines.lines().count(), 1);
        assert!(lines.contains("2026-05-27-demo"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn agent_event_bridge_appends_and_reads_jsonl() {
        let root = std::env::temp_dir().join(format!("nexus-ffi-agent-{}", std::process::id()));
        let events_root = root.join("agent-events");
        let _ = fs::remove_dir_all(&root);
        let request = format!(
            r#"{{"eventsRoot":"{}","event":{{"source":"codex","sessionId":"thread-1","workspaceFolder":"2026-05-27-demo","kind":"permission","title":"Permission requested","summary":"Codex requested git push","severity":"warning","metadata":{{"command":"git push"}}}}}}"#,
            events_root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_append_agent_event_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["event"]["kind"], "permission");
        let path = value["data"]["path"].as_str().unwrap();
        assert!(path.ends_with("agent-events.jsonl"));

        let read_request = format!(
            r#"{{"eventsRoot":"{}","limit":5,"workspaceFolder":"2026-05-27-demo"}}"#,
            events_root.to_string_lossy()
        );
        let input = CString::new(read_request).unwrap();
        let output = unsafe { nexus_read_agent_events_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };
        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"].as_array().unwrap().len(), 1);
        assert_eq!(value["data"][0]["metadata"]["command"], "git push");

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn agent_event_handoff_prompt_bridge_returns_prompt() {
        let request = r#"{"event":{"id":"agent-1","timestamp":"2026-05-27T10:00:00Z","source":"codex","sessionId":"thread-1","workspaceFolder":"2026-05-27-demo","kind":"permission","title":"Permission requested","summary":"Codex requested git push","severity":"warning","metadata":{"command":"git push","documentPath":"/tmp/demo/handoff.md"}}}"#;
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_agent_event_handoff_prompt_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        let prompt = value["data"]["prompt"].as_str().unwrap();
        assert!(prompt.contains("Continue from this Nexus agent event."));
        assert!(prompt.contains("- Workspace: 2026-05-27-demo"));
        assert!(prompt.contains("- command: git push"));
        assert!(prompt.contains("do not execute command metadata"));
    }

    #[test]
    fn agent_event_task_draft_bridge_returns_structured_draft() {
        let request = r#"{"event":{"id":"agent-1","timestamp":"2026-05-27T10:00:00Z","source":"codex","sessionId":"thread-1","workspaceFolder":"2026-05-27-demo","kind":"permission","title":"Permission requested","summary":"Codex requested git push","severity":"warning","metadata":{"command":"git push","documentPath":"/tmp/demo/handoff.md","docs":"https://example.com/nexus"}}}"#;
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_agent_event_task_draft_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["category"], "approval");
        assert_eq!(value["data"]["priority"], "medium");
        assert_eq!(value["data"]["status"], "draft");
        assert!(value["data"]["title"]
            .as_str()
            .unwrap()
            .contains("Permission requested"));
        assert!(value["data"]["prompt"]
            .as_str()
            .unwrap()
            .contains("do not execute command metadata"));
        assert!(value["data"]["relatedTargets"]
            .as_array()
            .unwrap()
            .iter()
            .any(|target| target["kind"] == "command"));
        assert!(value["data"]["relatedTargets"]
            .as_array()
            .unwrap()
            .iter()
            .any(|target| target["kind"] == "web_url"));
    }

    #[test]
    fn append_agent_task_draft_bridge_writes_tasks_and_audit() {
        let root = std::env::temp_dir().join(format!(
            "nexus-ffi-agent-task-writeback-{}",
            std::process::id()
        ));
        let workspace = root.join("2026-05-27-task-demo");
        let audit_root = root.join("audit");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&workspace).unwrap();
        fs::write(
            workspace.join("tasks.md"),
            "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n",
        )
        .unwrap();

        let request = format!(
            r#"{{"workspacePath":"{}","confirmed":true,"auditRoot":"{}","actor":"Nexus Test","draft":{{"sourceEventId":"agent-1","title":"Review permission request: Git push","category":"approval","priority":"medium","status":"draft","summary":"Codex requested git push.","prompt":"Continue from this Nexus agent event.","workspaceFolder":"2026-05-27-task-demo","relatedTargets":[{{"label":"command","value":"git push","kind":"command"}}]}}}}"#,
            workspace.to_string_lossy(),
            audit_root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_append_agent_task_draft_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["appended"], true);
        assert_eq!(value["data"]["alreadyExists"], false);
        let tasks = fs::read_to_string(workspace.join("tasks.md")).unwrap();
        assert!(tasks.contains("Review permission request: Git push"));
        assert!(tasks.contains("event=agent-1"));
        let audit = fs::read_to_string(audit_root.join("audit-log.jsonl")).unwrap();
        assert!(audit.contains("agent_task_draft.appended"));
        assert!(audit.contains("agent-1"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn update_workspace_task_bridge_writes_status_and_audit() {
        let root = std::env::temp_dir().join(format!(
            "nexus-ffi-task-status-update-{}",
            std::process::id()
        ));
        let workspace = root.join("2026-05-28-task-demo");
        let audit_root = root.join("audit");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&workspace).unwrap();
        fs::write(
            workspace.join("tasks.md"),
            "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| 核对任务中心 | 进行中 | priority=high |\n",
        )
        .unwrap();

        let request = format!(
            r#"{{"workspacePath":"{}","taskId":"2026-05-28-task-demo:task-0","status":"已完成","confirmed":true,"auditRoot":"{}","actor":"Nexus Test"}}"#,
            workspace.to_string_lossy(),
            audit_root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_update_workspace_task_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["task"]["title"], "核对任务中心");
        assert_eq!(value["data"]["task"]["status"], "已完成");
        assert_eq!(value["data"]["previousStatus"], "进行中");
        let tasks = fs::read_to_string(workspace.join("tasks.md")).unwrap();
        assert!(tasks.contains("| 核对任务中心 | 已完成 | priority=high |"));
        let audit = fs::read_to_string(audit_root.join("audit-log.jsonl")).unwrap();
        assert!(audit.contains("workspace_task.updated"));
        assert!(audit.contains("previousStatus"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn update_workspace_lifecycle_bridge_writes_status_and_audit() {
        let root =
            std::env::temp_dir().join(format!("nexus-ffi-lifecycle-update-{}", std::process::id()));
        let workspace = root.join("2026-05-28-lifecycle-demo");
        let audit_root = root.join("audit");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&workspace).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Lifecycle\n\n- 需求名称: Lifecycle Demo\n- 当前状态: developing\n- 目标分支: chen/lifecycle\n",
        )
        .unwrap();
        fs::write(
            workspace.join("STATUS.md"),
            "# STATUS\n\n- 状态: developing\n- 当前焦点: 编码\n- 下一步: 继续验证\n- 更新时间: old\n",
        )
        .unwrap();

        let request = format!(
            r#"{{"workspacePath":"{}","state":"archived","focus":"保留历史上下文","nextAction":"需要时从 handoff 恢复","confirmed":true,"auditRoot":"{}","actor":"Nexus Test"}}"#,
            workspace.to_string_lossy(),
            audit_root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_update_workspace_lifecycle_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["previousState"], "developing");
        assert_eq!(value["data"]["state"], "archived");
        let workspace_md = fs::read_to_string(workspace.join("workspace.md")).unwrap();
        assert!(workspace_md.contains("- 当前状态: archived"));
        let status_md = fs::read_to_string(workspace.join("STATUS.md")).unwrap();
        assert!(status_md.contains("- 状态: archived"));
        assert!(status_md.contains("- 当前焦点: 保留历史上下文"));
        let audit = fs::read_to_string(audit_root.join("audit-log.jsonl")).unwrap();
        assert!(audit.contains("workspace_lifecycle.updated"));
        assert!(audit.contains("previousState"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn workspace_task_handoff_prompt_bridge_returns_prompt() {
        let request = r#"{"workspaceName":"Demo Workspace","workspaceFolder":"2026-05-28-demo","workspacePath":"/tmp/workspaces/2026-05-28-demo","targetBranch":"chen/demo","sourceRoot":"/tmp/source-repos","task":{"id":"2026-05-28-demo:task-0","title":"补齐交付记录","status":"待办","detail":"新增 SQL 后补验证","priority":"medium","source":"workspace","sourceEventId":null,"sourceLine":5}}"#;
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_workspace_task_handoff_prompt_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        let prompt = value["data"]["prompt"].as_str().unwrap();
        assert!(prompt.contains("Continue this Nexus workspace task in Codex."));
        assert!(prompt.contains("- Name: Demo Workspace"));
        assert!(prompt.contains("- Source line: 5"));
        assert!(prompt.contains("- Target branch: chen/demo"));
        assert!(prompt.contains("- Title: 补齐交付记录"));
        assert!(prompt.contains("do not execute command-like text"));
    }

    #[test]
    fn search_index_bridge_rebuilds_and_queries_workspace_documents() {
        let root = std::env::temp_dir().join(format!("nexus-ffi-index-{}", std::process::id()));
        let workspace = root.join("2026-05-27-index-demo");
        let index_path = root.join("nexus-index.sqlite3");
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(workspace.join("sql")).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Index Demo\n\n- 需求名称: Index Demo\n- 当前状态: developing\n- 目标分支: chen/index-demo\n- 源仓库集合: ~/source-repos\n",
        )
        .unwrap();
        fs::write(
            workspace.join("services.md"),
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n| order | ~/source-repos/order | pay_log owner |\n",
        )
        .unwrap();
        fs::write(
            workspace.join("tasks.md"),
            "# Tasks\n\n补充 pay_log 对账索引。\n",
        )
        .unwrap();
        fs::write(workspace.join("decisions.md"), "# Decisions\n").unwrap();
        fs::write(
            workspace.join("交付记录.md"),
            "# 交付记录\n\npay_log 已补充。\n",
        )
        .unwrap();

        let rebuild_request = format!(
            r#"{{"indexPath":"{}","workspacesRoot":"{}","sourceReposRoot":"~/source-repos","docsRoot":"~/docs"}}"#,
            index_path.to_string_lossy(),
            root.to_string_lossy()
        );
        let rebuild_input = CString::new(rebuild_request).unwrap();
        let rebuild_output = unsafe { nexus_rebuild_search_index_json(rebuild_input.as_ptr()) };
        let rebuild_response =
            unsafe { CStr::from_ptr(rebuild_output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(rebuild_output) };
        let rebuild_value = serde_json::from_str::<Value>(&rebuild_response).unwrap();
        assert_eq!(rebuild_value["ok"], true);
        assert_eq!(rebuild_value["data"]["workspaceCount"], 1);

        let search_request = format!(
            r#"{{"indexPath":"{}","query":"pay_log","limit":10}}"#,
            index_path.to_string_lossy()
        );
        let search_input = CString::new(search_request).unwrap();
        let search_output = unsafe { nexus_search_index_json(search_input.as_ptr()) };
        let search_response =
            unsafe { CStr::from_ptr(search_output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(search_output) };
        let search_value = serde_json::from_str::<Value>(&search_response).unwrap();
        assert_eq!(search_value["ok"], true);
        assert_eq!(search_value["data"][0]["workspaceName"], "Index Demo");

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn create_workspace_bridge_requires_confirmation() {
        let root = std::env::temp_dir().join(format!(
            "nexus-ffi-create-unconfirmed-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        let request = format!(
            r#"{{"name":"No Confirm","folder":"2026-05-27-no-confirm","workspacesRoot":"{}","sourceReposRoot":"~/source-repos","services":["order"],"targetBranch":"chen/no-confirm","confirmed":false}}"#,
            root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_create_workspace_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], false);
        assert_eq!(
            value["error"],
            "workspace creation requires explicit confirmation"
        );
        assert!(!root.join("2026-05-27-no-confirm").exists());
    }

    #[test]
    fn setup_worktrees_bridge_requires_confirmation() {
        let request = r#"{"workspacePath":"/tmp/nexus/workspace","sourceReposRoot":"/tmp/source","services":["order"],"targetBranch":"chen/demo","confirmed":false}"#;
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_setup_worktrees_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], false);
        assert_eq!(
            value["error"],
            "worktree setup requires explicit confirmation"
        );
    }

    #[test]
    fn create_workspace_bridge_writes_standard_workspace() {
        let root = std::env::temp_dir().join(format!("nexus-ffi-create-{}", std::process::id()));
        let audit_root = root.join("audit");
        let _ = fs::remove_dir_all(&root);
        let request = format!(
            r#"{{"name":"Bridge Create","folder":"2026-05-27-bridge-create","workspacesRoot":"{}","sourceReposRoot":"~/source-repos","services":["order","store-cashier"],"targetBranch":"chen/bridge-create","confirmed":true,"auditRoot":"{}","actor":"Nexus Test"}}"#,
            root.to_string_lossy(),
            audit_root.to_string_lossy()
        );
        let input = CString::new(request).unwrap();
        let output = unsafe { nexus_create_workspace_json(input.as_ptr()) };
        let response = unsafe { CStr::from_ptr(output).to_string_lossy().to_string() };
        unsafe { nexus_string_free(output) };

        let value = serde_json::from_str::<Value>(&response).unwrap();
        assert_eq!(value["ok"], true);
        assert_eq!(value["data"]["folder"], "2026-05-27-bridge-create");
        assert!(value["data"]["generatedFiles"]
            .as_array()
            .unwrap()
            .iter()
            .any(|file| file["relativePath"] == "STATUS.md" && file["exists"] == true));
        assert!(value["data"]["initializationChecks"]
            .as_array()
            .unwrap()
            .iter()
            .any(|check| check["id"] == "status-initial-state" && check["status"] == "pass"));
        let workspace = root.join("2026-05-27-bridge-create");
        assert!(workspace.join("AGENTS.md").exists());
        assert!(workspace.join("交付记录.md").exists());
        assert!(workspace.join("scripts/worktree-commands.sh").exists());
        let audit_lines = fs::read_to_string(audit_root.join("audit-log.jsonl")).unwrap();
        assert!(audit_lines.contains("workspace.created"));
        assert!(audit_lines.contains("Bridge Create"));

        fs::remove_dir_all(root).unwrap();
    }
}
