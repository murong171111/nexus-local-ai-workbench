# Native Truthful Fallback Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Prevent default Native startup and unavailable bridge fallbacks from presenting sample data as real local state.

**Architecture:** Keep existing preview fixtures for direct test use, but remove them from runtime construction and compatibility fallback reads. Reuse current `NexusBridgeError.coreError` handling so authoritative failures become visible through existing AppState error paths.

**Tech Stack:** Swift 5.9, SwiftUI, Foundation, XCTest, Swift Package Manager

## Global Constraints

- New product behavior remains Swift Native-only.
- No new dependency or abstraction.
- Preview fixtures remain available for explicit tests.
- Authoritative local reads never fabricate data.
- Production code follows a failing-test-first cycle.

---

### Task 1: Truthful Startup State

**Files:**
- Modify: `native/Nexus/Sources/NexusApp/AppState.swift:4138`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: `AppState.preview() -> AppState`
- Produces: An AppState with `workspaces.isEmpty == true` and `agentStatus.title == "Loading"` before refresh.

- [ ] **Step 1: Write the failing test**

```swift
@MainActor
func testDefaultAppStateStartsWithoutSampleWorkspaces() {
    let appState = AppState.preview()

    XCTAssertTrue(appState.workspaces.isEmpty)
    XCTAssertEqual(appState.agentStatus.title, "Loading")
}
```

- [ ] **Step 2: Run the test to verify it fails**

Run:

```bash
swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testDefaultAppStateStartsWithoutSampleWorkspaces
```

Expected: FAIL because startup currently contains `WorkspaceSummary.previewData` and reports `Ready`.

- [ ] **Step 3: Implement the minimal startup change**

```swift
static func preview() -> AppState {
    AppState(
        workspaces: [],
        agentStatus: AgentStatus(
            title: "Loading",
            detail: "Reading local workspace state",
            connectedTools: []
        ),
        bridge: NexusBridgeFactory.makeDefault()
    )
}
```

- [ ] **Step 4: Run the targeted test**

Expected: PASS.

### Task 2: Truthful Preview Bridge Reads

**Files:**
- Modify: `native/Nexus/Sources/NexusBridge/NexusBridge.swift:44`
- Test: `native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift`

**Interfaces:**
- Consumes: Existing `NexusBridge` protocol methods.
- Produces: Empty optional feeds and explicit errors for authoritative local reads.

- [ ] **Step 1: Write failing tests**

```swift
func testPreviewBridgeOptionalFeedsAreEmpty() async throws {
    let bridge = PreviewNexusBridge()

    let events = try await bridge.readAgentEvents(
        request: ReadAgentEventsRequest(eventsRoot: "/tmp/events", limit: 8)
    )
    let results = try await bridge.searchIndex(
        request: SearchIndexRequest(indexPath: "/tmp/index", query: "demo")
    )

    XCTAssertTrue(events.isEmpty)
    XCTAssertTrue(results.isEmpty)
}

func testPreviewBridgeRejectsAuthoritativeLocalReads() async {
    let bridge = PreviewNexusBridge()

    await assertThrowsUnavailable {
        _ = try await bridge.readDocument(request: ReadDocumentRequest(path: "/missing/tasks.md"))
    }
}
```

Use a local async assertion helper in the same test file:

```swift
private func assertThrowsUnavailable(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected async expression to throw", file: file, line: line)
    } catch {
        XCTAssertTrue(error.localizedDescription.contains("unavailable"), file: file, line: line)
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run:

```bash
swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testPreviewBridge
```

Expected: FAIL because the bridge currently returns a sample Agent event and a fake Preview document.

- [ ] **Step 3: Implement the minimal bridge behavior**

Add one private helper:

```swift
private func unavailable(_ operation: String) -> NexusBridgeError {
    .coreError("\(operation) is unavailable because no Nexus Core bridge is loaded")
}
```

Return empty arrays for optional feeds and throw `unavailable(...)` from workspace, repository, document, demand-intake, widget, and automation reads.

- [ ] **Step 4: Run the targeted tests**

Expected: PASS.

### Task 3: Verification And Release Note

**Files:**
- Modify: `CHANGELOG.md`

**Interfaces:**
- Consumes: Completed startup and bridge behavior.
- Produces: Regression evidence and a user-visible change record.

- [ ] **Step 1: Add the changelog entry**

Add under the current unreleased section:

```markdown
- Native startup and unavailable bridge fallbacks no longer present preview workspaces, documents, Agent events, or automation findings as real local state.
```

- [ ] **Step 2: Run focused and full verification**

```bash
git diff --check
swift test --disable-sandbox --package-path native/Nexus --filter ModelBehaviorTests/testPreviewBridge
swift test --disable-sandbox --package-path native/Nexus
```

Expected: all commands pass and the full Swift suite reports zero failures.

- [ ] **Step 3: Commit the slice**

```bash
git add docs/superpowers/specs/2026-07-10-native-truthful-fallback-design.md docs/superpowers/plans/2026-07-10-native-truthful-fallback.md native/Nexus/Sources/NexusApp/AppState.swift native/Nexus/Sources/NexusBridge/NexusBridge.swift native/Nexus/Tests/NexusAppTests/ModelBehaviorTests.swift CHANGELOG.md
git commit -m "Make Native fallback state truthful"
```
