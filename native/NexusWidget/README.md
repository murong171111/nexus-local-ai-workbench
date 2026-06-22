# Nexus WidgetKit Target

This directory is the Native WidgetKit target path for Nexus.

## Contents

- `Sources/NexusWidget/NexusWidget.swift`: WidgetKit source that reads the Nexus widget snapshot and opens `nexus://workspace/<folder>` links.
- `Info.plist`: Widget extension bundle metadata with the `com.apple.widgetkit-extension` extension point.
- `NexusWidget.entitlements`: App Group entitlement for `group.com.ks.nexus`.

## Build Status

The source can be type-checked with:

```bash
swiftc -parse-as-library -typecheck native/NexusWidget/Sources/NexusWidget/NexusWidget.swift
```

Producing a signed `.appex` still requires a full Xcode Widget Extension target that embeds this source, plist, and entitlement file into `Nexus.app/Contents/PlugIns`. This directory is the canonical Native target evidence used by M3 distribution readiness while the Xcode project is being completed.
