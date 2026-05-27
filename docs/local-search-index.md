# Local Search Index

Nexus uses a rebuildable SQLite + FTS index for fast local search across requirement workspaces.

## Location

```text
~/Library/Application Support/com.ks.nexus/nexus-index.sqlite3
```

The index is a cache. Human-readable workspace Markdown files remain the source of truth.

## Indexed Content

The first indexer reads:

- `AGENTS.md`
- `workspace.md`
- `STATUS.md`
- `services.md`
- `branches.md`
- `plan.md`
- `tasks.md`
- `decisions.md`
- `handoff.md`
- `delivery.md`
- `交付记录.md`
- `bootstrap-report.md`
- `sql/*.md`
- `sql/*.sql`
- `sql/*.txt`

This covers workspace metadata, service scope, tasks, decisions, delivery records, and SQL notes.

## Tables

- `workspace_index`: one row per workspace, with state, target branch, source root, risk count, and task counts.
- `document_index`: one row per indexed document, with workspace linkage and raw text content.
- `document_fts`: FTS5 virtual table for search. Search falls back to `LIKE` when FTS syntax cannot handle a short or punctuation-heavy query.

## Bridge Surface

Rust Core:

- `rebuild_search_index(index_path, workspaces_root, source_repos_root, docs_root)`
- `search_index(index_path, query, limit)`

Tauri:

- `rebuild_search_index`
- `search_index`
- The preview app rebuilds the index on startup, settings changes, manual refresh, and workspace creation.
- The top search popover queries the index, groups matched results by workspace/state/workflow/SQL, and opens matched documents in the in-app viewer.
- Keyboard navigation supports arrow-key selection, Enter to open the selected result, and Escape to clear the query.
- Browser preview mode falls back to workspace metadata results when Tauri is not available.

Swift/Rust FFI:

- `nexus_rebuild_search_index_json`
- `nexus_search_index_json`
- The native SwiftUI shell can rebuild the same Application Support index, search it through `NexusBridge`, group results, and open matching workspaces or documents.

## Next UI Work

The Tauri preview app and native SwiftUI shell now both have grouped global search with keyboard navigation. The next product slice should extend result previews with richer workspace activity context and add saved/pinned search scopes.
