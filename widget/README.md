# Nexus WidgetKit Legacy Mirror

The canonical Native WidgetKit target now lives in `native/NexusWidget`.

This directory remains as a legacy mirror for the early preview app and historical packaging notes.

## What Is Implemented

- `../native/NexusWidget/Sources/NexusWidget/NexusWidget.swift` defines the canonical native SwiftUI WidgetKit widget.
- `NexusWidget/NexusWidget.swift` mirrors the same source for compatibility with earlier docs and preview tooling.
- The widget reads `widget-snapshot.json`.
- The main Tauri app writes the snapshot through the native `write_widget_snapshot` command.
- The native SwiftUI shell writes the snapshot to Application Support and mirrors it to the `group.com.ks.nexus` App Group container when the signed app has that entitlement.
- The widget uses `nexus://workspace/<workspace-folder>` as its click target.

## Snapshot Contract

The main app writes:

```json
{
  "generatedAt": "2026-05-26T12:00:00.000Z",
  "workspacesRoot": "/Users/example/ks_project/workspaces",
  "activeWorkspace": "Sample Workspace",
  "activeWorkspaceFolder": "2026-01-01-sample-workspace",
  "workspaceCount": 2,
  "riskCount": 4,
  "dirtyServiceCount": 0,
  "missingWorktreeCount": 3,
  "topRisks": [],
  "mainStage": "交付检查 / Delivery",
  "mainStageStatus": "阻塞 / block",
  "mainStageBlockerSummary": "阻塞：SQL rollback evidence is missing.",
  "mainStageNextAction": "查看 SQL",
  "mainStageEvidence": "sql/release.sql",
  "deepLink": "nexus://workspace/2026-01-01-sample-workspace"
}
```

## Distribution Notes

WidgetKit extensions require a real Xcode app target and signing setup. For a distributable build:

1. Install full Xcode, not only Command Line Tools.
2. Create a macOS Widget Extension target named `NexusWidget`.
3. Use `native/NexusWidget/Sources/NexusWidget/NexusWidget.swift` as the extension source.
4. Configure App Group `group.com.ks.nexus` for both the app and widget target.
5. Package the `.appex` into `Nexus.app/Contents/PlugIns`.
6. Sign and notarize the final app bundle.

The current machine only has Command Line Tools, so this repository can provide the widget source and main-app snapshot contract, but cannot compile the WidgetKit extension here.

During unsigned local development, the widget source falls back to `~/Library/Application Support/com.ks.nexus/widget-snapshot.json`. In a signed build with App Group entitlements, the same file should also exist in the shared group container so WidgetKit can read it without relying on the app sandbox.

The Swift source can still be type-checked without generating an extension bundle:

```bash
npm run widget:typecheck
```
