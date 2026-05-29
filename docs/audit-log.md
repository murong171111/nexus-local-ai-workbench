# Local Audit Log

Nexus keeps a small append-only JSONL audit log for user-visible local writes. The log is designed to be readable, easy to back up, and indexable by the future SQLite/FTS store.

## Location

```text
~/Library/Application Support/com.ks.nexus/audit/audit-log.jsonl
```

The Rust Core accepts a custom audit root for native shell and test scenarios, but the packaged Mac app should use the Application Support location above.

The dashboard scan now reads this JSONL file and attaches matching events to each workspace as recent activity. Matching uses the event `metadata.folder`, `metadata.workspace`, `metadata.workspaceFolder`, or a target path that contains the workspace folder/path.

## Event Shape

Each line is a standalone JSON object:

```json
{
  "id": "audit-workspace-created-demo-1770000000000",
  "timestamp": "2026-05-27T12:00:00Z",
  "actor": "Nexus App",
  "action": "workspace.created",
  "target": "/Users/example/ks_project/workspaces/2026-05-27-demo",
  "summary": "Created workspace Demo",
  "metadata": {
    "folder": "2026-05-27-demo",
    "services": "order,store-cashier",
    "targetBranch": "chen/demo"
  }
}
```

## Currently Audited

- `workspace.created`: written after confirmed workspace creation succeeds.
- `settings_profile.exported`: written after a settings profile export succeeds.
- `document.opened`: written when a workspace document is opened inside Nexus.
- `codex.opened`: written when Codex is opened from the active workspace context.
- `codex_instruction.copied`: written when a workspace handoff, Git, delivery, risk, or worktree prompt is copied.
- `codex_task_handoff.copied`: written when a workspace task Codex handoff prompt is copied.
- `codex_task_handoff.opened`: written when Nexus copies a workspace task prompt and opens Codex in one action.
- `codex_worktree_setup.opened`: written when Nexus copies a worktree setup result prompt and opens Codex in one action.
- `codex_session_link.bound`: written when a workspace Codex session deep link is bound locally, including bindings accepted from Agent Event suggestions.
- `codex_session_link.updated`: written when binding the same Codex session URL updates the local title or note.
- `codex_session_link.opened`: written when Nexus opens a saved workspace Codex session link.
- `codex_session_link.copied`: written when a saved workspace Codex session link is copied.
- `codex_session_link.deleted`: written when a saved workspace Codex session binding is deleted locally.
- `workspace.deeplink.copied`: written when Nexus copies a `nexus://workspace/<folder>` link for the selected workspace.
- `workspace.deeplink.opened`: written when a `nexus://workspace/<folder>` deep link focuses a workspace.
- `codex_handoff.opened`: written when Nexus copies a workspace prompt and opens Codex in one action.
- `risk_instruction.copied`: written when a risk-specific handling prompt is copied.
- `worktree.command.copied`: written when a reviewable worktree command is copied.
- `worktree.setup.executed`: written after a confirmed worktree setup run finishes.
- `automation.check.completed`: written after the native local automation check scans refresh, risk, delivery, task, worktree, and dirty-service signals.
- `append_audit_event`: available through the Tauri command layer for preview-app UI actions.
- `nexus_append_audit_event_json`: available through the Swift/Rust bridge for future native shell actions.
- Workspace scans enrich each workspace card/detail timeline with the latest matching audit events, while falling back to the scan summary when no event exists.

## Not Audited Yet

- Widget snapshot refreshes, because they are high-frequency cache writes.
- Generated worktree shell scripts being executed, because Nexus only generates commands and does not run them.
- Markdown document edits, because in-app document editing is not implemented yet.
- Git operations such as reset, clean, branch deletion, or worktree removal, because these are intentionally outside the early write surface.

## Migration Path

Markdown workspace files remain the human-readable source of truth. The audit JSONL file is the durable write trail. SQLite tables should index this file for fast search and richer timelines instead of replacing it as the only copy.
