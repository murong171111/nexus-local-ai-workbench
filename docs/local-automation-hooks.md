# Local Automation Hooks

Nexus local automation hooks are lightweight checks that run on the user's Mac without a cloud service.

The first native slice is intentionally conservative: it scans local workspace Markdown and git state, creates a structured check summary, and optionally appends an audit-log event. It does not execute shell commands, modify git branches, edit documents, or approve agent actions.

## Current Hook

`local_automation_check` is exposed by Rust Core and the Swift/Rust bridge.

It checks:

- workspace refresh status
- risk signal count
- delivery-record issues
- open and high-priority tasks
- missing worktrees
- dirty source or worktree services

The native Mac menu bar can run this check from `Run Checks`. The result appears in the same menu as a compact automation summary.

## Audit Event

When an audit root is provided, successful checks append:

```text
automation.check.completed
```

The event metadata includes generated time, overall status, workspace count, risk count, delivery issue count, task counts, worktree counts, dirty service count, and emitted signal IDs.

Audit writes are fail-open. If the scan succeeds but audit logging fails, Nexus returns the automation summary with an `auditError` field instead of blocking the local workflow.

## Safety Boundary

The hook is read-mostly:

- It reads workspace Markdown files.
- It inspects git status through the existing Rust Core workspace scan.
- It can append one audit JSONL event.
- It does not run generated worktree scripts.
- It does not change task status or delivery documents.
- It does not execute command metadata from agents.

Future automation hooks should keep this boundary unless the UI and bridge request both carry explicit confirmation.

## Future Hooks

Next automation slices can build on the same contract:

- periodic background refresh from the native shell
- scheduled risk scans
- delivery-record reminders after code or SQL changes
- validation-run and PR handoff audit events
- menu bar notifications for high-priority local tasks
