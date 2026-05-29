# Agent Interaction Bridge

Nexus is starting to support local AI agent event ingestion without requiring cloud services.

This first slice is intentionally small: it defines a durable local event format and bridge surface that future hook helpers can write to.

## Current Scope

- Rust Core stores agent events as append-only JSONL.
- The default event file name is `agent-events.jsonl`.
- The Swift/Rust bridge can append agent events and read the newest events.
- Rust Core exposes a shared Codex handoff prompt for agent events through the FFI and Swift bridge.
- Rust Core also derives structured task drafts from agent events so shells can show a consistent next-work item.
- Rust Core scans workspace `tasks.md` rows into structured local tasks so task writebacks appear in the native Task Center.
- The native SwiftUI shell reads recent events from Application Support and shows them in the sidebar.
- Sidebar events can be opened to inspect full event context, metadata, and copy the raw JSON payload.
- Event details expose safe local actions for matching workspaces, local file paths, web links, Codex context copy, and copy-and-open Codex handoff.
- Workspace details can bind multiple Codex session deep links, storing them in workspace-local `codex-sessions.json`.
- Workspace details suggest Codex session bindings from recent matching Agent Events when metadata carries Codex deep-link fields.
- `scripts/nexus-agent-event.mjs` lets local agent hooks append events before the local socket bridge exists.
- Preview mode shows a sample event when `NEXUS_CORE_LIBRARY` is not configured.

## Event Shape

Each event has:

- `source`: agent or helper name, such as `codex`, `claude-code`, or `opencode`.
- `sessionId`: the originating agent session or thread.
- `workspaceFolder`: optional Nexus workspace folder.
- `kind`: event type, such as `prompt`, `question`, `permission`, `tool_use`, or `status`.
- `title`: short display title.
- `summary`: human-readable detail.
- `severity`: `info`, `warning`, or `error`.
- `metadata`: string map for command, file, tool, URL, or agent-specific context.

## Action Metadata

The native shell treats metadata as data, not as executable instructions. It may surface safe next-step actions when these keys or value shapes are present:

- `workspaceFolder`, `folder`, `workspace`, `workspacePath`, or `path`: match and select a workspace when the value matches a known workspace folder or path.
- Keys containing `path`, `file`, `folder`, or `directory`: open the value as a local `file://`, `/absolute/path`, or `~/path` target when it exists.
- Any metadata value beginning with `http://` or `https://`: open as a normal web link.
- Codex session links can be suggested when the event matches a workspace and metadata contains a URL-like value under keys such as `codexUrl`, `codexSessionUrl`, `sessionUrl`, `threadUrl`, `conversationUrl`, or `deepLink`. Values using a `codex` URL scheme are treated as Codex candidates even when the key is generic.

Commands are copied or shown as text only. Nexus does not execute command metadata from agent events.

## Codex Handoff Prompt

Nexus generates a shared handoff prompt from the event payload so every shell can copy the same continuation context. The prompt includes:

- Event identity: title, kind, severity, source, session, workspace, event ID, and timestamp.
- The human-readable event summary.
- Sorted metadata lines.
- A safety instruction that metadata is context only and command metadata must not be executed without an explicit user request.

SwiftUI uses this bridge-backed prompt when Rust Core is loaded, and falls back to the same local format in preview mode.

The native event detail sheet keeps two Codex paths separate:

- `Copy Codex context` copies the shared event prompt and records `codex_agent_event.copied`.
- `Open in Codex` copies the same prompt, opens the configured Codex URL, shows handoff feedback, and records `codex_agent_event.opened`.

If the event matches a known workspace, the audit metadata includes workspace identifiers so the workspace timeline can show the event handoff. If no workspace matches, the audit event still records the agent event ID, source, session, kind, severity, and title.

## Task Draft

Nexus can derive a structured task draft from the same event. The native shell can show it as a reviewable draft and, after confirmation, persist it into the related workspace `tasks.md`.

The draft contains:

- `title`: action-oriented text such as `Review permission request: ...`.
- `category`: `approval`, `answer`, `tool-review`, `incident`, `risk-review`, `handoff`, or `follow-up`.
- `priority`: `high`, `medium`, or `normal`, derived from severity and event kind.
- `status`: currently always `draft`.
- `summary`: the event summary.
- `prompt`: the shared Codex handoff prompt.
- `workspaceFolder`: the related workspace folder when known.
- `relatedTargets`: workspace, local path, web URL, or command references extracted from metadata.

Command targets remain non-executable context. They are useful for review, copying, or future explicit approvals only.

## Task Writeback

The native shell can append a task draft to a workspace `tasks.md` file after explicit confirmation.

Writeback rules:

- The user must check the confirmation control before Nexus writes.
- Rust Core rejects writeback requests with `confirmed=false`.
- The task is appended under an `Agent Task Drafts` section as a normal Markdown task table row.
- The source agent event ID is embedded in the row detail so repeated writes of the same event become no-ops.
- Command targets remain text in the row detail. Nexus still does not execute them.
- When the FFI bridge receives an audit root, successful writes append an `agent_task_draft.appended` audit event.

## Local Task Center

Workspace task rows are now scanned as structured task snapshots:

- The first table column becomes the task title.
- The second table column becomes the task status.
- The third table column remains the task detail.
- The Markdown table row line number is exposed as `sourceLine` so native task surfaces can return to the exact `tasks.md` source context.
- `priority=high|medium|normal|low` in the detail column controls priority when present.
- `event=<agent-event-id>` marks the task as agent-sourced and lets Nexus deduplicate writebacks.

The native SwiftUI sidebar shows open tasks across all workspaces in a local Task Center. Selecting a task moves focus to the owning workspace, and each task row can locate the owning `tasks.md` row for source review by opening the document, copying a task-source locator, and showing the focused line context in Documents Hub. The workspace detail panel shows task rows alongside readiness, session actions, risk, activity, and documents, with the same direct path back to `tasks.md`.

Task Center filters are local UI state. The native shell can persistently focus all open tasks, high-priority tasks, agent-sourced tasks, or deferred tasks without changing `tasks.md`.

## Task Status Updates

The native shell can update a scanned workspace task after explicit confirmation:

- `完成` changes the matching table row status to `已完成`.
- `延期` changes the matching table row status to `延期`.
- Rust Core matches tasks by the stable task ID emitted during scanning.
- Normal workspace tasks use `<workspace-folder>:task-<index>`.
- Agent-sourced tasks use `<workspace-folder>:<event-id>` when the row detail contains `event=<agent-event-id>`.
- Successful FFI writes append a `workspace_task.updated` audit event when an audit root is provided.

Status updates only rewrite the matched Markdown table row in `tasks.md`. Nexus does not modify unrelated task rows or execute any command metadata.

## Task Codex Handoff

Workspace tasks can also produce a copyable Codex handoff prompt through Rust Core, FFI, and the Swift bridge. The prompt includes:

- Workspace name, folder, path, target branch, source repository root, and `tasks.md` path.
- Task ID, title, status, priority, source, and source event ID when present.
- Task source line when available.
- The task detail text.
- A workflow reminder to read workspace documents, inspect `repos/<service>` worktrees, keep SQL and delivery docs aligned, and report touched services, branches, verification, and risks.

The native Task Center and workspace task rows expose this as a `Codex` action. The action copies the generated prompt to the pasteboard, opens the configured Codex URL, shows task-specific handoff feedback, and appends a `codex_task_handoff.opened` audit event. It does not execute task detail text by itself.

## Codex Session Links

Workspace-level Codex session links are the first explicit "return to this agent conversation" surface in Nexus. The native workspace detail view can:

- bind a Codex deep link or web URL with a short title and optional note;
- list multiple sessions for the same workspace;
- open a saved link through macOS;
- copy the link back to the clipboard;
- delete a local binding after confirmation.

The first native implementation stores these records in:

```text
<workspace>/codex-sessions.json
```

The file uses a small JSON envelope with `schemaVersion` and `sessions`. Deleting a record only removes the Nexus binding; it does not delete or mutate the Codex conversation. Bind, update, open, copy, and delete actions append local audit events when the bridge is available.

Native Command Center now treats these links as part of the workspace session path instead of a separate utility only. The detail overview shows the saved session count, the session path includes a `会话 / Sessions` step, and when no other blocker is present the primary path can resume the latest saved Codex session. If no session is saved, the session path routes to the bind flow while the handoff path still copies a fresh workspace context pack.

## Storage Boundary

Agent events are not workspace source-of-truth records. They are local operational telemetry used for:

- Recent agent activity.
- Future reply and approval surfaces.
- Deep links back to active sessions.
- Audit-oriented investigation of local agent workflows.

Workspace Markdown files remain the source of truth for requirements, tasks, decisions, and delivery records.

## Safety Boundary

This slice does not execute commands, approve permissions, or start a local server.

Future hook helpers and local bridge servers must stay fail-open: if Nexus is closed or unreachable, the agent should continue normally unless the user explicitly configures stricter behavior.

## Hook Helper

The hook helper writes the same JSONL shape as Rust Core and is designed for early local integrations.

```bash
npm run agent:event -- \
  --source codex \
  --session-id "$CODEX_SESSION_ID" \
  --workspace-folder "2026-05-27-demo" \
  --kind permission \
  --title "Permission requested" \
  --summary "Codex requested git push" \
  --severity warning \
  --metadata command="git push"
```

By default the helper writes to:

```text
~/Library/Application Support/com.ks.nexus/agent-events/agent-events.jsonl
```

Set `NEXUS_AGENT_EVENTS_ROOT` or pass `--events-root` to override the storage root.

The helper is fail-open by default. It logs a warning and exits `0` if it cannot write an event. Pass `--strict` only for tests or workflows that should fail when event capture fails.
