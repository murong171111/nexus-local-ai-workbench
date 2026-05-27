# Agent Interaction Bridge

Nexus is starting to support local AI agent event ingestion without requiring cloud services.

This first slice is intentionally small: it defines a durable local event format and bridge surface that future hook helpers can write to.

## Current Scope

- Rust Core stores agent events as append-only JSONL.
- The default event file name is `agent-events.jsonl`.
- The Swift/Rust bridge can append agent events and read the newest events.
- The native SwiftUI shell reads recent events from Application Support and shows them in the sidebar.
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
