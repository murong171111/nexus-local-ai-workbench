# Local Audit Log

Nexus keeps a small append-only JSONL audit log for user-visible local writes. The log is designed to be readable, easy to back up, and indexable by the future SQLite/FTS store.

## Location

```text
~/Library/Application Support/com.ks.nexus/audit/audit-log.jsonl
```

The Rust Core accepts a custom audit root for native shell and test scenarios, but the packaged Mac app should use the Application Support location above.

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
- `nexus_append_audit_event_json`: available through the Swift/Rust bridge for future native shell actions.

## Not Audited Yet

- Widget snapshot refreshes, because they are high-frequency cache writes.
- Generated worktree shell scripts being executed, because Nexus only generates commands and does not run them.
- Markdown document edits, because in-app document editing is not implemented yet.
- Git operations such as reset, clean, branch deletion, or worktree removal, because these are intentionally outside the early write surface.

## Migration Path

Markdown workspace files remain the human-readable source of truth. The audit JSONL file is the durable write trail. Future SQLite tables should index this file instead of replacing it as the only copy.
