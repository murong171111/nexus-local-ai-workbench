import assert from "node:assert/strict";
import test from "node:test";
import { normalizeServiceList, slugify, todayString, widgetSnapshotFromDashboard, workspaceFolderFromName, workspaceScore } from "../.tmp-tests/workspace-model.js";

function gitRow(service, overrides = {}) {
  return {
    service,
    worktreePath: `/workspace/repos/${service}`,
    sourcePath: `/source/${service}`,
    worktree: {
      exists: true,
      branch: "chen/demo",
      dirty: false,
      summary: "clean",
      ...overrides.worktree
    },
    source: {
      exists: true,
      branch: "main",
      dirty: false,
      summary: "clean",
      ...overrides.source
    }
  };
}

function workspace(overrides = {}) {
  return {
    name: "Sample Workspace",
    folder: "2026-01-01-sample-workspace",
    path: "/workspace/2026-01-01-sample-workspace",
    state: "developing",
    targetBranch: "chen/demo",
    sourceRoot: "/source",
    confirmedServices: ["order"],
    candidateServices: [],
    taskCounts: { done: 1, doing: 1, todo: 2, blocked: 0 },
    decisionCount: 2,
    gitRows: [gitRow("order")],
    risks: [],
    riskCount: 0,
    updated: "2026-01-01",
    links: {},
    worktreeCommand: "git worktree add ...",
    ...overrides
  };
}

test("slugify keeps readable Chinese and normalizes separators", () => {
  assert.equal(slugify(" 示例 需求 / V2 "), "示例-需求-v2");
});

test("workspaceFolderFromName prefixes a stable date", () => {
  const date = new Date("2026-05-26T04:00:00.000Z");
  assert.equal(workspaceFolderFromName("示例需求", date), "2026-05-26-示例需求");
});

test("normalizeServiceList trims, deduplicates, and sorts service names", () => {
  assert.deepEqual(normalizeServiceList([" order ", "store", "order", "", "cashier"]), ["cashier", "order", "store"]);
});

test("todayString returns an ISO date", () => {
  assert.equal(todayString(new Date("2026-05-26T23:59:00.000Z")), "2026-05-26");
});

test("workspaceScore prioritizes risks and dirty worktrees", () => {
  const scored = workspace({
    riskCount: 2,
    gitRows: [gitRow("order", { worktree: { dirty: true } }), gitRow("store")]
  });
  assert.equal(workspaceScore(scored), 23);
});

test("widgetSnapshotFromDashboard summarizes active workspace state", () => {
  const dashboard = {
    generatedAt: "2026-01-01T00:00:00.000Z",
    workspacesRoot: "/workspace",
    sourceReposRoot: "/source",
    docsRoot: "/docs",
    workspaces: [
      workspace({
        name: "Risky Workspace",
        folder: "2026-01-01-risky",
        riskCount: 2,
        risks: ["branch mismatch", "missing delivery note"],
        gitRows: [
          gitRow("order", { worktree: { dirty: true } }),
          gitRow("store", { worktree: { exists: false, summary: "missing" } })
        ]
      })
    ]
  };

  const snapshot = widgetSnapshotFromDashboard(dashboard, "2026-01-01-risky");

  assert.equal(snapshot.activeWorkspace, "Risky Workspace");
  assert.equal(snapshot.workspaceCount, 1);
  assert.equal(snapshot.riskCount, 2);
  assert.equal(snapshot.dirtyServiceCount, 1);
  assert.equal(snapshot.missingWorktreeCount, 1);
  assert.deepEqual(snapshot.topRisks, ["Risky Workspace: branch mismatch", "Risky Workspace: missing delivery note"]);
  assert.equal(snapshot.deepLink, "nexus://workspace/2026-01-01-risky");
  assert.match(snapshot.generatedAt, /^\d{4}-\d{2}-\d{2}T/);
});
