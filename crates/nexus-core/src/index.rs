use crate::{expand_user_path, scan_workspaces, WorkspaceData};
use rusqlite::{params, Connection};
use serde::Serialize;
use std::fs;
use std::path::{Path, PathBuf};

pub const DEFAULT_INDEX_FILE: &str = "nexus-index.sqlite3";

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct RebuildSearchIndexResponse {
    pub path: String,
    pub workspace_count: usize,
    pub document_count: usize,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SearchResult {
    pub workspace_folder: String,
    pub workspace_name: String,
    pub document_key: String,
    pub document_name: String,
    pub document_path: String,
    pub kind: String,
    pub snippet: String,
}

#[derive(Clone, Debug)]
struct WorkspaceDocument {
    key: String,
    name: String,
    path: PathBuf,
    kind: String,
    content: String,
}

pub fn rebuild_search_index(
    index_path: &str,
    workspaces_root: &str,
    source_repos_root: &str,
    docs_root: &str,
) -> Result<RebuildSearchIndexResponse, String> {
    let index_path = expand_user_path(index_path);
    if let Some(parent) = index_path.parent() {
        fs::create_dir_all(parent).map_err(|error| error.to_string())?;
    }

    let mut connection = Connection::open(&index_path).map_err(|error| error.to_string())?;
    setup_schema(&connection)?;
    let dashboard = scan_workspaces(workspaces_root, source_repos_root, docs_root)?;
    let workspace_count = dashboard.workspaces.len();
    let mut document_count = 0;

    let transaction = connection
        .transaction()
        .map_err(|error| error.to_string())?;
    transaction
        .execute("DELETE FROM workspace_index", [])
        .map_err(|error| error.to_string())?;
    transaction
        .execute("DELETE FROM document_index", [])
        .map_err(|error| error.to_string())?;
    transaction
        .execute("DELETE FROM document_fts", [])
        .map_err(|error| error.to_string())?;

    for workspace in &dashboard.workspaces {
        transaction
            .execute(
                "INSERT INTO workspace_index (
                    folder, name, state, target_branch, source_root, path, updated,
                    risk_count, task_done, task_doing, task_todo, task_blocked
                 ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12)",
                params![
                    workspace.folder,
                    workspace.name,
                    workspace.state,
                    workspace.target_branch,
                    workspace.source_root,
                    workspace.path,
                    workspace.updated,
                    workspace.risk_count as i64,
                    workspace.task_counts.done as i64,
                    workspace.task_counts.doing as i64,
                    workspace.task_counts.todo as i64,
                    workspace.task_counts.blocked as i64,
                ],
            )
            .map_err(|error| error.to_string())?;

        for document in workspace_documents(workspace)? {
            transaction
                .execute(
                    "INSERT INTO document_index (
                        workspace_folder, workspace_name, document_key, document_name,
                        document_path, kind, content
                     ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                    params![
                        workspace.folder,
                        workspace.name,
                        document.key,
                        document.name,
                        document.path.to_string_lossy().to_string(),
                        document.kind,
                        document.content,
                    ],
                )
                .map_err(|error| error.to_string())?;
            transaction
                .execute(
                    "INSERT INTO document_fts (
                        workspace_folder, workspace_name, document_key, document_name,
                        kind, content, document_path
                     ) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
                    params![
                        workspace.folder,
                        workspace.name,
                        document.key,
                        document.name,
                        document.kind,
                        document.content,
                        document.path.to_string_lossy().to_string(),
                    ],
                )
                .map_err(|error| error.to_string())?;
            document_count += 1;
        }
    }

    transaction.commit().map_err(|error| error.to_string())?;

    Ok(RebuildSearchIndexResponse {
        path: index_path.to_string_lossy().to_string(),
        workspace_count,
        document_count,
    })
}

pub fn search_index(
    index_path: &str,
    query: &str,
    limit: usize,
) -> Result<Vec<SearchResult>, String> {
    let index_path = expand_user_path(index_path);
    if !index_path.exists() {
        return Ok(Vec::new());
    }

    let trimmed = query.trim();
    if trimmed.is_empty() {
        return Ok(Vec::new());
    }

    let connection = Connection::open(index_path).map_err(|error| error.to_string())?;
    let limit = limit.clamp(1, 100) as i64;
    let fts_query = fts_match_query(trimmed);
    match search_fts(&connection, &fts_query, limit) {
        Ok(results) if !results.is_empty() => Ok(results),
        _ => search_like(&connection, trimmed, limit),
    }
}

fn setup_schema(connection: &Connection) -> Result<(), String> {
    connection
        .execute_batch(
            "
            PRAGMA journal_mode = WAL;
            PRAGMA synchronous = NORMAL;

            CREATE TABLE IF NOT EXISTS workspace_index (
                folder TEXT PRIMARY KEY,
                name TEXT NOT NULL,
                state TEXT NOT NULL,
                target_branch TEXT NOT NULL,
                source_root TEXT NOT NULL,
                path TEXT NOT NULL,
                updated TEXT NOT NULL,
                risk_count INTEGER NOT NULL,
                task_done INTEGER NOT NULL,
                task_doing INTEGER NOT NULL,
                task_todo INTEGER NOT NULL,
                task_blocked INTEGER NOT NULL
            );

            CREATE TABLE IF NOT EXISTS document_index (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                workspace_folder TEXT NOT NULL,
                workspace_name TEXT NOT NULL,
                document_key TEXT NOT NULL,
                document_name TEXT NOT NULL,
                document_path TEXT NOT NULL,
                kind TEXT NOT NULL,
                content TEXT NOT NULL
            );

            CREATE INDEX IF NOT EXISTS idx_document_workspace
                ON document_index(workspace_folder);

            CREATE VIRTUAL TABLE IF NOT EXISTS document_fts USING fts5(
                workspace_folder UNINDEXED,
                workspace_name,
                document_key UNINDEXED,
                document_name,
                kind,
                content,
                document_path UNINDEXED
            );
            ",
        )
        .map_err(|error| error.to_string())
}

fn workspace_documents(workspace: &WorkspaceData) -> Result<Vec<WorkspaceDocument>, String> {
    let root = PathBuf::from(&workspace.path);
    let mut documents = Vec::new();
    for (key, kind, name) in [
        ("agents", "guide", "AGENTS.md"),
        ("workspace", "workspace", "workspace.md"),
        ("status", "status", "STATUS.md"),
        ("services", "services", "services.md"),
        ("branches", "branches", "branches.md"),
        ("requirements", "requirements", "requirements.md"),
        ("acceptance", "acceptance", "acceptance.md"),
        ("changes", "changes", "changes.md"),
        ("plan", "plan", "plan.md"),
        ("tasks", "tasks", "tasks.md"),
        ("decisions", "decisions", "decisions.md"),
        ("handoff", "handoff", "handoff.md"),
        ("delivery", "delivery", "delivery.md"),
        ("delivery-cn", "delivery", "交付记录.md"),
        ("bootstrap", "bootstrap", "bootstrap-report.md"),
    ] {
        push_document_if_readable(&mut documents, &root, key, kind, name)?;
    }
    push_directory_documents(&mut documents, &root.join("sql"), "sql", "sql")?;
    Ok(documents)
}

fn push_document_if_readable(
    documents: &mut Vec<WorkspaceDocument>,
    root: &Path,
    key: &str,
    kind: &str,
    name: &str,
) -> Result<(), String> {
    let path = root.join(name);
    if !path.is_file() {
        return Ok(());
    }
    documents.push(WorkspaceDocument {
        key: key.to_string(),
        name: name.to_string(),
        path: path.clone(),
        kind: kind.to_string(),
        content: fs::read_to_string(&path).map_err(|error| error.to_string())?,
    });
    Ok(())
}

fn push_directory_documents(
    documents: &mut Vec<WorkspaceDocument>,
    root: &Path,
    key_prefix: &str,
    kind: &str,
) -> Result<(), String> {
    let entries = match fs::read_dir(root) {
        Ok(entries) => entries,
        Err(_) => return Ok(()),
    };
    for entry in entries {
        let entry = entry.map_err(|error| error.to_string())?;
        let path = entry.path();
        if !path.is_file() || !is_indexable_file(&path) {
            continue;
        }
        let name = entry.file_name().to_string_lossy().to_string();
        documents.push(WorkspaceDocument {
            key: format!("{key_prefix}/{name}"),
            name,
            path: path.clone(),
            kind: kind.to_string(),
            content: fs::read_to_string(&path).map_err(|error| error.to_string())?,
        });
    }
    Ok(())
}

fn is_indexable_file(path: &Path) -> bool {
    matches!(
        path.extension()
            .map(|extension| extension.to_string_lossy().to_ascii_lowercase())
            .as_deref(),
        Some("md" | "markdown" | "mdown" | "mkdn" | "sql" | "txt")
    )
}

fn search_fts(
    connection: &Connection,
    query: &str,
    limit: i64,
) -> Result<Vec<SearchResult>, String> {
    let mut statement = connection
        .prepare(
            "
            SELECT
                workspace_folder,
                workspace_name,
                document_key,
                document_name,
                document_path,
                kind,
                snippet(document_fts, 5, '', '', '...', 24) AS snippet
            FROM document_fts
            WHERE document_fts MATCH ?1
            ORDER BY rank
            LIMIT ?2
            ",
        )
        .map_err(|error| error.to_string())?;
    let rows = statement
        .query_map(params![query, limit], search_result_from_row)
        .map_err(|error| error.to_string())?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|error| error.to_string())
}

fn search_like(
    connection: &Connection,
    query: &str,
    limit: i64,
) -> Result<Vec<SearchResult>, String> {
    let pattern = like_pattern(query);
    let mut statement = connection
        .prepare(
            "
            SELECT
                workspace_folder,
                workspace_name,
                document_key,
                document_name,
                document_path,
                kind,
                substr(content, 1, 220) AS snippet
            FROM document_index
            WHERE workspace_name LIKE ?1 ESCAPE '\\'
                OR document_name LIKE ?1 ESCAPE '\\'
                OR kind LIKE ?1 ESCAPE '\\'
                OR content LIKE ?1 ESCAPE '\\'
            ORDER BY workspace_name, document_name
            LIMIT ?2
            ",
        )
        .map_err(|error| error.to_string())?;
    let rows = statement
        .query_map(params![pattern, limit], search_result_from_row)
        .map_err(|error| error.to_string())?;
    rows.collect::<rusqlite::Result<Vec<_>>>()
        .map_err(|error| error.to_string())
}

fn search_result_from_row(row: &rusqlite::Row<'_>) -> rusqlite::Result<SearchResult> {
    Ok(SearchResult {
        workspace_folder: row.get(0)?,
        workspace_name: row.get(1)?,
        document_key: row.get(2)?,
        document_name: row.get(3)?,
        document_path: row.get(4)?,
        kind: row.get(5)?,
        snippet: row.get(6)?,
    })
}

fn fts_match_query(query: &str) -> String {
    let terms = query
        .split_whitespace()
        .map(str::trim)
        .filter(|term| !term.is_empty())
        .map(quote_fts_term)
        .collect::<Vec<_>>();

    if terms.is_empty() {
        quote_fts_term(query)
    } else {
        terms.join(" AND ")
    }
}

fn quote_fts_term(term: &str) -> String {
    format!("\"{}\"", term.replace('"', "\"\""))
}

fn like_pattern(query: &str) -> String {
    let escaped = query
        .replace('\\', "\\\\")
        .replace('%', "\\%")
        .replace('_', "\\_");
    format!("%{escaped}%")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rebuild_search_index_indexes_workspace_documents_and_sql_notes() {
        let root = std::env::temp_dir().join(format!("nexus-core-index-{}", std::process::id()));
        let workspace = root.join("2026-05-27-pay-log");
        let index_path = root.join(DEFAULT_INDEX_FILE);
        let _ = fs::remove_dir_all(&root);
        fs::create_dir_all(workspace.join("sql")).unwrap();
        fs::write(
            workspace.join("workspace.md"),
            "# Pay Log\n\n- 需求名称: 易宝对账补充 pay_log\n- 当前状态: developing\n- 目标分支: chen/pay-log\n- 源仓库集合: ~/source-repos\n",
        )
        .unwrap();
        fs::write(
            workspace.join("services.md"),
            "# Services\n\n## 已确认相关\n\n| 服务 | 源仓库 | 说明 |\n| --- | --- | --- |\n| order | ~/source-repos/order | pay_log producer |\n",
        )
        .unwrap();
        fs::write(
            workspace.join("tasks.md"),
            "# Tasks\n\n| 任务 | 状态 | 说明 |\n| --- | --- | --- |\n| 补充 pay_log | 进行中 | 对账链路 |\n",
        )
        .unwrap();
        fs::write(
            workspace.join("decisions.md"),
            "# Decisions\n\n| 时间 | 决策 | 原因 | 影响 |\n| --- | --- | --- | --- |\n| today | 记录 pay_log | 易宝对账需要 | order |\n",
        )
        .unwrap();
        fs::write(
            workspace.join("交付记录.md"),
            "# 交付记录\n\n对账补充待验证。\n",
        )
        .unwrap();
        fs::write(
            workspace.join("sql").join("pay_log.sql"),
            "ALTER TABLE pay_log ADD COLUMN reconcile_no varchar(64);",
        )
        .unwrap();

        let rebuilt = rebuild_search_index(
            &index_path.to_string_lossy(),
            &root.to_string_lossy(),
            "~/source-repos",
            "~/docs",
        )
        .unwrap();
        assert_eq!(rebuilt.workspace_count, 1);
        assert!(rebuilt.document_count >= 5);
        assert!(Path::new(&rebuilt.path).exists());

        let pay_log_results = search_index(&index_path.to_string_lossy(), "pay_log", 10).unwrap();
        assert!(pay_log_results
            .iter()
            .any(|result| result.workspace_name == "易宝对账补充 pay_log"));

        let sql_results = search_index(&index_path.to_string_lossy(), "ALTER TABLE", 10).unwrap();
        assert!(sql_results
            .iter()
            .any(|result| result.kind == "sql" && result.document_name == "pay_log.sql"));

        let chinese_results = search_index(&index_path.to_string_lossy(), "对账", 10).unwrap();
        assert!(!chinese_results.is_empty());

        fs::remove_dir_all(root).unwrap();
    }

    #[test]
    fn search_index_returns_empty_results_when_database_is_missing() {
        let missing = std::env::temp_dir().join(format!(
            "nexus-core-missing-index-{}.sqlite3",
            std::process::id()
        ));
        let results = search_index(&missing.to_string_lossy(), "anything", 10).unwrap();
        assert!(results.is_empty());
    }
}
