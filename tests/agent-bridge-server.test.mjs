import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  createAgentBridgeLineHandler,
  defaultAgentBridgeSocketPath,
  parseAgentBridgeArgs
} from "../scripts/nexus-agent-bridge-server.mjs";

test("parseAgentBridgeArgs resolves socket and events root overrides", () => {
  const options = parseAgentBridgeArgs(
    ["--events-root", "~/nexus-events", "--socket", "~/nexus.sock"],
    { NEXUS_AGENT_BRIDGE_SOCKET: "/tmp/from-env.sock" }
  );

  assert.match(options.eventsRoot, /nexus-events$/);
  assert.match(options.socketPath, /nexus\.sock$/);
});

test("defaultAgentBridgeSocketPath can be configured from env", () => {
  assert.equal(defaultAgentBridgeSocketPath({ NEXUS_AGENT_BRIDGE_SOCKET: "/tmp/nexus.sock" }), "/tmp/nexus.sock");
});

test("agent bridge handler appends newline-delimited events", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "nexus-agent-bridge-"));
  const handleLine = createAgentBridgeLineHandler({ eventsRoot: root });

  try {
    const response = handleLine(JSON.stringify({
      source: "codex",
      sessionId: "thread-1",
      kind: "status",
      title: "Status",
      summary: "Bridge received an event",
      metadata: { tool: "socket" }
    }));

    assert.equal(response.ok, true);
    assert.equal(response.event.source, "codex");
    assert.equal(response.event.metadata.tool, "socket");

    const events = readFileSync(path.join(root, "agent-events.jsonl"), "utf8")
      .trim()
      .split("\n")
      .map((line) => JSON.parse(line));
    assert.equal(events.length, 1);
    assert.equal(events[0].summary, "Bridge received an event");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("agent bridge handler returns an error response for malformed JSON", () => {
  const errors = [];
  const handleLine = createAgentBridgeLineHandler({
    onError: (error) => errors.push(error)
  });

  const response = handleLine("{not-json");

  assert.equal(response.ok, false);
  assert.match(response.error, /Expected property name|JSON/u);
  assert.equal(errors.length, 1);
});
