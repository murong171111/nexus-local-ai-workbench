import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { checkDashboardSample } from "../scripts/check-dashboard-samples.mjs";

function sampleDashboard(overrides = {}) {
  return {
    generatedAt: "sample",
    workspacesRoot: "~/ks_project/workspaces",
    sourceReposRoot: "~/ks_project/source-repos",
    docsRoot: "~/ks_project/docs",
    workspaces: [
      {
        name: "Sample Workspace",
        folder: "2026-01-01-sample-workspace",
        path: "~/ks_project/workspaces/2026-01-01-sample-workspace",
        state: "analyzing",
        targetBranch: "chen/sample-branch",
        sourceRoot: "~/ks_project/source-repos",
        confirmedServices: ["order"],
        candidateServices: [],
        taskCounts: { done: 0, doing: 0, todo: 1, blocked: 0, deferred: 0 },
        decisionCount: 0,
        gitRows: [
          {
            service: "order",
            worktreePath: "~/ks_project/workspaces/2026-01-01-sample-workspace/repos/order",
            sourcePath: "~/ks_project/source-repos/order",
            worktree: { exists: true, branch: "chen/sample-branch", dirty: false, summary: "clean" },
            source: { exists: true, branch: "main", dirty: false, summary: "clean" }
          }
        ],
        risks: ["交付记录待补充"],
        riskCount: 1,
        updated: "2026-01-01",
        links: {
          folder: "~/ks_project/workspaces/2026-01-01-sample-workspace",
          workspace: "~/ks_project/workspaces/2026-01-01-sample-workspace/workspace.md",
          status: "~/ks_project/workspaces/2026-01-01-sample-workspace/STATUS.md",
          services: "~/ks_project/workspaces/2026-01-01-sample-workspace/services.md",
          branches: "~/ks_project/workspaces/2026-01-01-sample-workspace/branches.md",
          requirements: "~/ks_project/workspaces/2026-01-01-sample-workspace/requirements.md",
          acceptance: "~/ks_project/workspaces/2026-01-01-sample-workspace/acceptance.md",
          changes: "~/ks_project/workspaces/2026-01-01-sample-workspace/changes.md",
          tasks: "~/ks_project/workspaces/2026-01-01-sample-workspace/tasks.md",
          delivery: "~/ks_project/workspaces/2026-01-01-sample-workspace/交付记录.md",
          handoff: "~/ks_project/workspaces/2026-01-01-sample-workspace/handoff.md"
        },
        worktreeCommand: "git worktree add ...",
        ...overrides.workspace
      }
    ],
    ...overrides.dashboard
  };
}

function writeSample(data) {
  const root = mkdtempSync(path.join(tmpdir(), "nexus-dashboard-sample-"));
  const filePath = path.join(root, "workspaces.json");
  writeFileSync(filePath, JSON.stringify(data, null, 2));
  return filePath;
}

test("checkDashboardSample accepts publishable sample dashboard data", () => {
  assert.deepEqual(checkDashboardSample(writeSample(sampleDashboard())), []);
});

test("checkDashboardSample reports private paths and mismatched counts", () => {
  const privateRoot = "/Users/" + "alice/project";
  const findings = checkDashboardSample(
    writeSample(
      sampleDashboard({
        dashboard: { workspacesRoot: privateRoot },
        workspace: {
          path: privateRoot + "/workspace",
          risks: ["risk one", "risk two"],
          riskCount: 1
        }
      })
    )
  );

  assert.deepEqual(
    findings.map((item) => item.path),
    ["workspacesRoot", "workspaces[0].path", "workspaces[0].riskCount"]
  );
});

test("checkDashboardSample requires standard document links", () => {
  const links = { ...sampleDashboard().workspaces[0].links };
  delete links.tasks;

  const findings = checkDashboardSample(writeSample(sampleDashboard({ workspace: { links } })));

  assert.deepEqual(findings.map((item) => item.path), ["workspaces[0].links.tasks"]);
});
