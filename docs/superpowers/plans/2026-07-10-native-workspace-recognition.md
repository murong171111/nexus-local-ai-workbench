# Native Workspace Recognition Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make Native dashboard scanning and environment diagnostics recognize the same identity-backed workspace directories.

**Architecture:** `NativeWorkspaceScanner` owns one direct-child recognition rule based on `workspace.md` or `STATUS.md`. Dashboard scanning consumes the recognized URLs, while `AppState` asks the scanner for the same count instead of independently counting child directories.

**Tech Stack:** Swift 5.9, SwiftUI, Foundation, XCTest, Swift Package Manager

## Global Constraints

- New product behavior remains Swift Native-only.
- `INDEX.md` remains diagnostic evidence and is not authoritative.
- Either `workspace.md` or `STATUS.md` is sufficient for recoverable workspace identity.
- No new dependency, registry, or persistence layer.
- Production code follows a failing-test-first cycle.

---

### Task 1: Shared File-Backed Workspace Recognition

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift:30-66`
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift:4624-4641,4761-4775`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift:2134`
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: configured `workspacesRoot`, `FileManager`, and the existing Native environment check.
- Produces: `NativeWorkspaceScanner.workspaceDirectoryCount(workspacesRoot:fileManager:) -> Int` and dashboard snapshots built from the same recognized directory list.

- [ ] **Step 1: Write the failing integration test**

Add this test next to the existing Native workspace scanner tests:

```swift
@MainActor
func testNativeWorkspaceRecognitionAlignsDashboardAndEnvironmentCounts() async throws {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("nexus-native-workspace-identity-\(UUID().uuidString)")
    let workspacesRoot = root.appendingPathComponent("workspaces")
    let sourceRoot = root.appendingPathComponent("source-repos")
    let docsRoot = root.appendingPathComponent("docs")
    let workspaceRecord = workspacesRoot.appendingPathComponent("2026-07-10-workspace-record")
    let statusRecord = workspacesRoot.appendingPathComponent("2026-07-10-status-record")
    let scratch = workspacesRoot.appendingPathComponent("scratch")
    let dashboardDirectory = workspacesRoot.appendingPathComponent("dashboard")
    let defaultsSuite = "NexusAppTests-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: defaultsSuite)!
    defer {
        try? FileManager.default.removeItem(at: root)
        defaults.removePersistentDomain(forName: defaultsSuite)
    }

    for directory in [workspaceRecord, statusRecord, scratch, dashboardDirectory, sourceRoot, docsRoot] {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }
    try "# Workspace\n".write(
        to: workspaceRecord.appendingPathComponent("workspace.md"),
        atomically: true,
        encoding: .utf8
    )
    try "# Status\n\n- 当前状态: created\n".write(
        to: statusRecord.appendingPathComponent("STATUS.md"),
        atomically: true,
        encoding: .utf8
    )
    try "notes\n".write(
        to: scratch.appendingPathComponent("notes.md"),
        atomically: true,
        encoding: .utf8
    )
    try "# Dashboard\n".write(
        to: dashboardDirectory.appendingPathComponent("workspace.md"),
        atomically: true,
        encoding: .utf8
    )

    let dashboard = try NativeWorkspaceScanner.scan(
        workspacesRoot: workspacesRoot.path,
        sourceReposRoot: sourceRoot.path,
        docsRoot: docsRoot.path
    )
    let appState = AppState(
        workspaces: [],
        agentStatus: AgentStatus(title: "Loading", detail: "Tests", connectedTools: []),
        bridge: PreviewNexusBridge(),
        workspaceRoot: workspacesRoot.path,
        sourceReposRoot: sourceRoot.path,
        docsRoot: docsRoot.path,
        defaults: defaults
    )

    await appState.checkNativeEnvironment()

    XCTAssertEqual(
        dashboard.workspaces.map(\.folder),
        ["2026-07-10-status-record", "2026-07-10-workspace-record"]
    )
    XCTAssertEqual(appState.nativeEnvironmentHealth?.workspaceCount, dashboard.workspaces.count)
}
```

- [ ] **Step 2: Run the test and verify RED**

Run:

```bash
swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testNativeWorkspaceRecognitionAlignsDashboardAndEnvironmentCounts
```

Expected: FAIL because `scratch` and `dashboard` are scanned or counted, and the dashboard/environment counts do not both equal two.

- [ ] **Step 3: Implement one scanner-owned recognition rule**

In `NativeWorkspaceScanner`, add the shared constants and count API, then make `scan` consume `workspaceDirectories`:

```swift
private static let ignoredWorkspaceDirectoryNames: Set<String> = [
    "dashboard", "node_modules", "target", "dist", "build", ".build"
]
private static let workspaceIdentityFileNames = ["workspace.md", "STATUS.md"]

static func workspaceDirectoryCount(
    workspacesRoot: String,
    fileManager: FileManager = .default
) -> Int {
    let root = URL(fileURLWithPath: (workspacesRoot as NSString).expandingTildeInPath)
    return (try? workspaceDirectories(at: root, fileManager: fileManager).count) ?? 0
}

private static func workspaceDirectories(
    at root: URL,
    fileManager: FileManager
) throws -> [URL] {
    try fileManager.contentsOfDirectory(
        at: root,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
    )
    .filter { isWorkspaceDirectory($0, fileManager: fileManager) }
    .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
}

private static func isWorkspaceDirectory(_ url: URL, fileManager: FileManager) -> Bool {
    guard (try? url.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true,
          !ignoredWorkspaceDirectoryNames.contains(url.lastPathComponent) else {
        return false
    }

    return workspaceIdentityFileNames.contains { filename in
        var isDirectory: ObjCBool = false
        let path = url.appendingPathComponent(filename, isDirectory: false).path
        return fileManager.fileExists(atPath: path, isDirectory: &isDirectory) && !isDirectory.boolValue
    }
}
```

Keep the existing missing-root empty dashboard guard. Replace the scan's direct `contentsOfDirectory` pipeline with `try workspaceDirectories(at:fileManager:)`.

- [ ] **Step 4: Reuse the scanner count in environment health**

Replace the generic child-directory count in `buildNativeEnvironmentHealth` with:

```swift
let workspaceCount = NativeWorkspaceScanner.workspaceDirectoryCount(
    workspacesRoot: workspacesRoot
)
```

Delete `countChildDirectories(at:ignoredName:)`; it has no remaining caller.

- [ ] **Step 5: Run the targeted test and verify GREEN**

Run:

```bash
swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testNativeWorkspaceRecognitionAlignsDashboardAndEnvironmentCounts
```

Expected: PASS with one scanner test executed and zero failures.

- [ ] **Step 6: Record and verify the slice**

Add this Unreleased changelog entry:

```markdown
- Native workspace scanning and status diagnostics now share one file-backed workspace identity rule, excluding unrelated child directories from real workspace counts.
```

Run:

```bash
git diff --check
swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testNativeWorkspace
swift test --disable-sandbox --package-path native/Nexus
```

Expected: all commands pass and the full Swift suite reports zero failures.

- [ ] **Step 7: Commit the implementation slice**

```bash
git add CHANGELOG.md native/Nexus/Sources/NexusApp/NativeWorkspaceScanner.swift native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift docs/superpowers/plans/2026-07-10-native-workspace-recognition.md
git commit -m "Unify Native workspace recognition"
```
