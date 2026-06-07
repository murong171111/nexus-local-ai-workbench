use crate::expand_user_path;
use serde::{Deserialize, Serialize};
use std::fs;
use std::path::{Component, Path, PathBuf};

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct DocumentSnapshot {
    pub path: String,
    pub name: String,
    pub extension: String,
    pub is_markdown: bool,
    pub content: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateWorkspaceDocumentRequest {
    pub workspace_path: String,
    pub document_key: String,
    pub relative_path: String,
    pub confirmed: bool,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CreateWorkspaceDocumentResponse {
    pub path: String,
    pub document_key: String,
    pub relative_path: String,
    pub created: bool,
    pub already_exists: bool,
}

pub fn read_document(path: &str) -> Result<DocumentSnapshot, String> {
    let resolved = expand_user_path(path);
    if !resolved.exists() {
        return Err(format!("document does not exist: {}", resolved.display()));
    }
    if !resolved.is_file() {
        return Err(format!(
            "document path is not a file: {}",
            resolved.display()
        ));
    }

    let content = fs::read_to_string(&resolved).map_err(|error| error.to_string())?;
    let extension = resolved
        .extension()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_default();
    let name = resolved
        .file_name()
        .map(|value| value.to_string_lossy().to_string())
        .unwrap_or_else(|| resolved.to_string_lossy().to_string());

    Ok(DocumentSnapshot {
        path: resolved.to_string_lossy().to_string(),
        name,
        is_markdown: is_markdown_extension(&extension),
        extension,
        content,
    })
}

pub fn create_workspace_document(
    request: CreateWorkspaceDocumentRequest,
) -> Result<CreateWorkspaceDocumentResponse, String> {
    if !request.confirmed {
        return Err("workspace document creation requires explicit confirmation".to_string());
    }

    let workspace = expand_user_path(&request.workspace_path);
    if !workspace.exists() {
        return Err(format!("workspace does not exist: {}", workspace.display()));
    }
    if !workspace.is_dir() {
        return Err(format!(
            "workspace is not a directory: {}",
            workspace.display()
        ));
    }

    let relative_path =
        safe_standard_document_relative_path(&request.document_key, &request.relative_path)?;
    let document_path = workspace.join(&relative_path);
    if document_path.exists() {
        if !document_path.is_file() {
            return Err(format!(
                "document path exists but is not a file: {}",
                document_path.display()
            ));
        }
        return Ok(CreateWorkspaceDocumentResponse {
            path: document_path.to_string_lossy().to_string(),
            document_key: request.document_key,
            relative_path: relative_path.to_string_lossy().to_string(),
            created: false,
            already_exists: true,
        });
    }

    if let Some(parent) = document_path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }
    fs::write(
        &document_path,
        standard_document_template(&request.document_key),
    )
    .map_err(|error| error.to_string())?;

    Ok(CreateWorkspaceDocumentResponse {
        path: document_path.to_string_lossy().to_string(),
        document_key: request.document_key,
        relative_path: relative_path.to_string_lossy().to_string(),
        created: true,
        already_exists: false,
    })
}

fn is_markdown_extension(extension: &str) -> bool {
    matches!(
        extension.to_ascii_lowercase().as_str(),
        "md" | "markdown" | "mdown" | "mkdn"
    )
}

fn safe_standard_document_relative_path(
    document_key: &str,
    relative_path: &str,
) -> Result<PathBuf, String> {
    let expected = expected_standard_document_relative_path(document_key)
        .ok_or_else(|| format!("unsupported workspace document key: {document_key}"))?;
    let trimmed = relative_path.trim();
    if trimmed.is_empty() {
        return Err("workspace document relative path is required".to_string());
    }

    let path = Path::new(trimmed);
    if path.is_absolute() {
        return Err("workspace document path must be relative".to_string());
    }
    for component in path.components() {
        match component {
            Component::Normal(_) | Component::CurDir => {}
            _ => {
                return Err("workspace document path cannot contain parent directories".to_string())
            }
        }
    }

    let normalized = path
        .components()
        .filter_map(|component| match component {
            Component::Normal(value) => Some(value.to_string_lossy().to_string()),
            Component::CurDir => None,
            _ => None,
        })
        .collect::<Vec<_>>()
        .join("/");

    if normalized != expected {
        return Err(format!(
            "workspace document key {document_key} must use relative path {expected}"
        ));
    }

    Ok(PathBuf::from(expected))
}

fn expected_standard_document_relative_path(document_key: &str) -> Option<&'static str> {
    match document_key {
        "workspace" => Some("workspace.md"),
        "status" => Some("STATUS.md"),
        "services" => Some("services.md"),
        "branches" => Some("branches.md"),
        "requirements" => Some("requirements.md"),
        "acceptance" => Some("acceptance.md"),
        "changes" => Some("changes.md"),
        "tasks" => Some("tasks.md"),
        "delivery" => Some("交付记录.md"),
        "handoff" => Some("handoff.md"),
        "bootstrap" => Some("bootstrap-report.md"),
        "worktreeScript" => Some("scripts/worktree-commands.sh"),
        _ => None,
    }
}

fn standard_document_template(document_key: &str) -> &'static str {
    match document_key {
        "workspace" => {
            "# Workspace\n\n- 需求名称: 待补充\n- 当前状态: analyzing\n- 目标分支: 待确认\n- 源仓库集合: 待确认\n\n## 需求范围\n\n待补充。\n"
        }
        "status" => {
            "# Status\n\n- 当前状态: analyzing\n- 下一步: 补齐工作区文档\n- 更新时间: 待补充\n\n## Blockers\n\n- 文档由 Nexus 恢复流程创建，请补充真实状态。\n"
        }
        "services" => {
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n"
        }
        "branches" => {
            "# Branches\n\n| 服务 | 目标分支 | 当前分支 | 说明 |\n| --- | --- | --- | --- |\n"
        }
        "requirements" => {
            "# Requirements\n\n## 需求概览\n\n- 需求名称: 待补充\n- 目标分支: 待确认\n- 涉及服务: 待确认\n\n## 业务规则\n\n| 编号 | 规则 | 来源 | 状态 |\n| --- | --- | --- | --- |\n| R1 | 待补充 | 待补充 | 待确认 |\n\n## 边界与不做范围\n\n| 编号 | 说明 | 原因 | 状态 |\n| --- | --- | --- | --- |\n\n## 兼容规则\n\n| 编号 | 兼容场景 | 处理方式 | 验收方式 |\n| --- | --- | --- | --- |\n\n## 待确认问题\n\n| 编号 | 问题 | 影响 | 结论 |\n| --- | --- | --- | --- |\n"
        }
        "acceptance" => {
            "# Acceptance\n\n## 验收目标\n\n- 验收状态: 待补充\n\n## 验收清单\n\n| 编号 | 对应规则 | 验收方式 | 证据位置 | 状态 |\n| --- | --- | --- | --- | --- |\n| A1 | R1 | 待补充 | 待补充 | 待验证 |\n\n## 回归范围\n\n| 场景 | 服务 | 验证方式 | 状态 |\n| --- | --- | --- | --- |\n\n## 验收结论\n\n待补充。\n"
        }
        "changes" => {
            "# Changes\n\n## 变更日志\n\n| 时间 | 类型 | 服务 | 文件/模块 | 说明 | 影响交付 |\n| --- | --- | --- | --- | --- | --- |\n| 待补充 | 待补充 | 待补充 | 待补充 | 待补充 | 待确认 |\n"
        }
        "tasks" => "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n",
        "delivery" => {
            "# 交付记录\n\n## 需求要点\n\n待补充。\n\n## 涉及服务\n\n待补充。\n\n## SQL / 配置\n\n- 是否有 SQL 变动：无\n- 正式 SQL 文件：无\n- 回滚 SQL 文件：无\n- 文件规则：如本文档任意位置记录 SQL 变更，或本段落记录 `变更类型：DDL/DML`、影响表、新增字段、回填脚本、数据修复等变更元数据，必须同步 `sql/` 下正式 SQL 与回滚 SQL 文件。\n\n## 验证记录\n\n待补充。\n\n## 风险与后续\n\n待补充。\n"
        }
        "handoff" => {
            "# Handoff\n\n## Codex 上下文\n\n待补充。\n\n## 下一步\n\n- 读取 requirements.md、acceptance.md、changes.md、workspace.md、STATUS.md、services.md、branches.md、tasks.md 和交付记录。\n"
        }
        "bootstrap" => {
            "# Bootstrap Report\n\n- 状态: 待复核\n- 说明: 该文件由 Nexus 文档恢复流程创建，请补充真实初始化记录。\n"
        }
        "worktreeScript" => {
            "#!/usr/bin/env bash\nset -euo pipefail\n\n# TODO: Regenerate worktree commands from Nexus after services and target branch are confirmed.\n"
        }
        _ => "# Document\n\n待补充。\n",
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn read_document_returns_markdown_snapshot() {
        let root = std::env::temp_dir().join(format!("nexus-core-document-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();
        let document = root.join("交付记录.md");
        fs::write(&document, "# 交付记录\n\n暂无。\n").unwrap();

        let snapshot = read_document(&document.to_string_lossy()).unwrap();
        assert_eq!(snapshot.name, "交付记录.md");
        assert_eq!(snapshot.extension, "md");
        assert!(snapshot.is_markdown);
        assert!(snapshot.content.contains("交付记录"));

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn read_document_rejects_missing_files() {
        let missing = std::env::temp_dir().join(format!(
            "nexus-core-missing-document-{}.md",
            std::process::id()
        ));
        let error = read_document(&missing.to_string_lossy()).unwrap_err();
        assert!(error.contains("document does not exist"));
    }

    #[test]
    fn create_workspace_document_writes_standard_missing_file() {
        let root =
            std::env::temp_dir().join(format!("nexus-core-create-document-{}", std::process::id()));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();

        let response = create_workspace_document(CreateWorkspaceDocumentRequest {
            workspace_path: root.to_string_lossy().to_string(),
            document_key: "delivery".to_string(),
            relative_path: "交付记录.md".to_string(),
            confirmed: true,
        })
        .unwrap();

        assert!(response.created);
        assert!(!response.already_exists);
        assert!(fs::read_to_string(root.join("交付记录.md"))
            .unwrap()
            .contains("## 验证记录"));

        let existing = create_workspace_document(CreateWorkspaceDocumentRequest {
            workspace_path: root.to_string_lossy().to_string(),
            document_key: "delivery".to_string(),
            relative_path: "交付记录.md".to_string(),
            confirmed: true,
        })
        .unwrap();

        assert!(!existing.created);
        assert!(existing.already_exists);

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn create_workspace_document_requires_confirmation_and_standard_path() {
        let root = std::env::temp_dir().join(format!(
            "nexus-core-create-document-reject-{}",
            std::process::id()
        ));
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(&root).unwrap();

        let unconfirmed = create_workspace_document(CreateWorkspaceDocumentRequest {
            workspace_path: root.to_string_lossy().to_string(),
            document_key: "tasks".to_string(),
            relative_path: "tasks.md".to_string(),
            confirmed: false,
        })
        .unwrap_err();
        assert!(unconfirmed.contains("explicit confirmation"));

        let traversal = create_workspace_document(CreateWorkspaceDocumentRequest {
            workspace_path: root.to_string_lossy().to_string(),
            document_key: "tasks".to_string(),
            relative_path: "../tasks.md".to_string(),
            confirmed: true,
        })
        .unwrap_err();
        assert!(traversal.contains("parent directories"));

        let wrong_path = create_workspace_document(CreateWorkspaceDocumentRequest {
            workspace_path: root.to_string_lossy().to_string(),
            document_key: "tasks".to_string(),
            relative_path: "notes.md".to_string(),
            confirmed: true,
        })
        .unwrap_err();
        assert!(wrong_path.contains("relative path tasks.md"));

        fs::remove_dir_all(root).unwrap();
    }
}
