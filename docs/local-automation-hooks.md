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

The native Settings panel can also enable scheduled checks while Nexus is running. The schedule is a local `UserDefaults` preference with supported intervals of 5, 15, 30, and 60 minutes. It is not a LaunchAgent, daemon, or system notification channel; closing Nexus stops the loop.

Optional macOS notifications can be enabled from Settings or the menu bar. Nexus asks for local notification authorization only when the user turns this on. Notifications are sent only when the automation result matches the selected minimum status. Clean checks stay quiet.

Notification preferences are local `UserDefaults` values:

- minimum status: `Review+` or `Attention`
- cooldown: 15, 30, 60, or 180 minutes
- signal filters: risk, delivery, task, and worktree

The cooldown is global for automation notifications so repeated checks do not spam the user with the same local state.

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
- It can run periodically only while the native app process is alive.
- It can send local macOS notifications only after explicit user authorization.
- It throttles notifications through local cooldown and signal preferences.
- It does not run generated worktree scripts.
- It does not change task status or delivery documents.
- It does not execute command metadata from agents.

Future automation hooks should keep this boundary unless the UI and bridge request both carry explicit confirmation.

## Future Hooks

Next automation slices can build on the same contract:

- per-workspace notification preferences
- scheduled risk scans
- delivery-record reminders after code or SQL changes
- validation-run and PR handoff audit events
- menu bar notifications for high-priority local tasks
