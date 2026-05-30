import assert from "node:assert/strict";
import { execFileSync, spawnSync } from "node:child_process";
import { mkdtempSync, readFileSync, rmSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import {
  agentEventDefaultsFromEnv,
  appendAgentEvent,
  buildAgentEvent,
  parseAgentEventArgs
} from "../scripts/nexus-agent-event.mjs";

const scriptPath = path.resolve("scripts/nexus-agent-event.mjs");

test("buildAgentEvent normalizes defaults and metadata values", () => {
  const now = new Date("2026-05-27T09:30:00.000Z");
  const event = buildAgentEvent(
    {
      source: " codex ",
      sessionId: " thread-1 ",
      workspaceFolder: " 2026-05-27-demo ",
      kind: " permission ",
      title: "",
      summary: " Needs approval ",
      severity: "",
      metadata: { command: "git push", count: 2, empty: null }
    },
    now
  );

  assert.equal(event.id, `agent-codex-thread-1-permission-${now.getTime()}`);
  assert.equal(event.title, "Agent event");
  assert.equal(event.severity, "info");
  assert.equal(event.workspaceFolder, "2026-05-27-demo");
  assert.deepEqual(event.metadata, { command: "git push", count: "2", empty: "" });
});

test("parseAgentEventArgs merges direct flags, metadata, and JSON input", () => {
  const { event, options } = parseAgentEventArgs(
    [
      "--events-root",
      "/tmp/nexus-events",
      "--source",
      "codex",
      "--metadata",
      "tool=shell",
      "--metadata-json",
      "{\"command\":\"git status\"}",
      "--input-json",
      "{\"sessionId\":\"s1\",\"kind\":\"tool_use\",\"summary\":\"Ran status\"}",
      "--strict"
    ],
    {}
  );

  assert.equal(options.eventsRoot, "/tmp/nexus-events");
  assert.equal(options.strict, true);
  assert.equal(event.source, "codex");
  assert.equal(event.sessionId, "s1");
  assert.equal(event.kind, "tool_use");
  assert.deepEqual(event.metadata, { tool: "shell", command: "git status" });
});

test("agentEventDefaultsFromEnv infers common local agent session context", () => {
  assert.deepEqual(agentEventDefaultsFromEnv({
    CODEX_SESSION_ID: "codex-thread",
    NEXUS_WORKSPACE_FOLDER: "2026-05-30-demo"
  }), {
    source: "codex",
    sessionId: "codex-thread",
    workspaceFolder: "2026-05-30-demo"
  });

  assert.deepEqual(agentEventDefaultsFromEnv({
    CLAUDE_CODE_SESSION_ID: "claude-thread"
  }), {
    source: "claude-code",
    sessionId: "claude-thread",
    workspaceFolder: undefined
  });

  assert.deepEqual(agentEventDefaultsFromEnv({
    NEXUS_AGENT_SOURCE: "custom-agent",
    NEXUS_AGENT_SESSION_ID: "custom-session",
    OPENCODE_SESSION_ID: "ignored"
  }), {
    source: "custom-agent",
    sessionId: "custom-session",
    workspaceFolder: undefined
  });
});

test("parseAgentEventArgs uses environment defaults unless flags override them", () => {
  const { event } = parseAgentEventArgs(
    ["--session-id", "manual-session", "--kind", "status"],
    {
      CODEX_SESSION_ID: "codex-thread",
      NEXUS_WORKSPACE_FOLDER: "2026-05-30-demo"
    }
  );

  assert.equal(event.source, "codex");
  assert.equal(event.sessionId, "manual-session");
  assert.equal(event.workspaceFolder, "2026-05-30-demo");
  assert.equal(event.kind, "status");
});

test("appendAgentEvent writes one JSONL event", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "nexus-agent-helper-"));
  try {
    const response = appendAgentEvent(
      root,
      {
        source: "codex",
        sessionId: "s1",
        kind: "question",
        title: "Question",
        summary: "Need user input",
        severity: "warning"
      },
      new Date("2026-05-27T10:00:00.000Z")
    );

    const lines = readFileSync(response.path, "utf8").trim().split("\n");
    assert.equal(lines.length, 1);
    const event = JSON.parse(lines[0]);
    assert.equal(event.kind, "question");
    assert.equal(event.severity, "warning");
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});

test("CLI writes events and remains fail-open by default", () => {
  const root = mkdtempSync(path.join(os.tmpdir(), "nexus-agent-cli-"));
  try {
    const output = execFileSync(
      process.execPath,
      [
        scriptPath,
        "--events-root",
        root,
        "--source",
        "codex",
        "--session-id",
        "s2",
        "--kind",
        "tool_use",
        "--title",
        "Tool use",
        "--summary",
        "Ran tests",
        "--metadata",
        "tool=npm"
      ],
      { encoding: "utf8" }
    );
    const response = JSON.parse(output);
    assert.equal(response.event.metadata.tool, "npm");

    const failed = spawnSync(process.execPath, [scriptPath, "--metadata", "broken"], {
      encoding: "utf8"
    });
    assert.equal(failed.status, 0);
    assert.match(failed.stderr, /helper skipped/);
  } finally {
    rmSync(root, { recursive: true, force: true });
  }
});
