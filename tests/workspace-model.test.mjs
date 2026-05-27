import assert from "node:assert/strict";
import test from "node:test";
import {
  buildWorktreeCommand,
  branchAlignmentRows,
  compactSearchSnippet,
  createSettingsProfile,
  fallbackSearchResults,
  groupSearchResults,
  hasConfirmedTargetBranch,
  normalizeServiceList,
  normalizeGitBranch,
  orderedSearchResults,
  parseServiceInput,
  parseSettingsProfile,
  serializeSettingsProfile,
  settingsProfileFilename,
  slugify,
  todayString,
  widgetSnapshotFromDashboard,
  workspaceFolderFromName,
  workspaceScore,
  workspaceSessionActions
} from "../.tmp-tests/workspace-model.js";

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
    sessionActions: [],
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

test("parseServiceInput accepts common Chinese and English separators", () => {
  assert.deepEqual(parseServiceInput("order、store-cashier commodity\nmanager；coupon,kspay"), [
    "order",
    "store-cashier",
    "commodity",
    "manager",
    "coupon",
    "kspay"
  ]);
});

test("normalizeServiceList parses compound manual service input", () => {
  assert.deepEqual(normalizeServiceList(["order、store-cashier、commodity", "order"]), ["commodity", "order", "store-cashier"]);
});

test("buildWorktreeCommand creates reviewable git worktree commands", () => {
  const command = buildWorktreeCommand("/workspace/demo", "/source", ["order"], "chen/demo");
  assert.match(command, /git -C '\/source\/order' fetch origin/);
  assert.match(command, /git -C '\/source\/order' worktree add '\/workspace\/demo\/repos\/order' 'chen\/demo'/);
});

test("todayString returns an ISO date", () => {
  assert.equal(todayString(new Date("2026-05-26T23:59:00.000Z")), "2026-05-26");
});

test("workspaceScore prioritizes risks and dirty worktrees", () => {
  const scored = workspace({
    riskCount: 2,
    gitRows: [gitRow("order", { worktree: { dirty: true } }), gitRow("store", { worktree: { branch: "chen/other" } })]
  });
  assert.equal(workspaceScore(scored), 28);
});

test("workspaceSessionActions builds a startup flow from workspace state", () => {
  const actions = workspaceSessionActions(
    workspace({
      targetBranch: "待确认",
      risks: ["目标分支未确认", "worktree 未创建: order", "交付记录待补充"],
      riskCount: 3,
      gitRows: [
        gitRow("order", { worktree: { exists: false, branch: "未创建" } }),
        gitRow("store", { worktree: { dirty: true } })
      ],
      taskCounts: { done: 1, doing: 1, todo: 2, blocked: 1 }
    })
  );

  assert.deepEqual(
    actions.map((action) => action.id),
    [
      "confirm-target-branch",
      "create-worktrees",
      "review-dirty-worktrees",
      "update-delivery-record",
      "resolve-blocked-tasks",
      "start-codex-session"
    ]
  );
  assert.equal(actions[0].status, "blocked");
  assert.equal(actions.at(-1).instructionType, "continue");
});

test("workspaceSessionActions returns core-provided session actions when present", () => {
  const coreAction = {
    id: "core-action",
    label: "Core action",
    detail: "Use Rust Core result",
    priority: "high",
    status: "recommended",
    instructionType: "continue",
    documentKey: "handoff"
  };

  assert.deepEqual(workspaceSessionActions(workspace({ sessionActions: [coreAction] })), [coreAction]);
});

test("normalizeGitBranch strips git status tracking suffixes", () => {
  assert.equal(normalizeGitBranch("chen/demo...origin/chen/demo [ahead 1]"), "chen/demo");
  assert.equal(normalizeGitBranch("## main"), "main");
});

test("hasConfirmedTargetBranch ignores pending branch placeholders", () => {
  assert.equal(hasConfirmedTargetBranch("chen/demo"), true);
  assert.equal(hasConfirmedTargetBranch("待确认"), false);
  assert.equal(hasConfirmedTargetBranch("<target-branch>"), false);
});

test("branchAlignmentRows returns worktrees that are not on the target branch", () => {
  const rows = branchAlignmentRows(
    workspace({
      targetBranch: "chen/demo",
      gitRows: [
        gitRow("order", { worktree: { branch: "chen/demo...origin/chen/demo" }, source: { branch: "main" } }),
        gitRow("store", { worktree: { branch: "chen/other" }, source: { branch: "master" } }),
        gitRow("message", { worktree: { exists: false, branch: "未创建" }, source: { branch: "main" } })
      ]
    })
  );

  assert.deepEqual(rows, [
    {
      service: "store",
      expectedBranch: "chen/demo",
      actualBranch: "chen/other",
      sourceBranch: "master"
    }
  ]);
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

test("fallbackSearchResults mirrors indexed search result shape for browser preview", () => {
  const dashboard = {
    generatedAt: "2026-01-01T00:00:00.000Z",
    workspacesRoot: "/workspace",
    sourceReposRoot: "/source",
    docsRoot: "/docs",
    workspaces: [
      workspace({
        name: "Pay Log Workspace",
        folder: "2026-01-01-pay-log",
        targetBranch: "chen/pay-log",
        confirmedServices: ["order", "store-cashier"],
        risks: ["交付记录待补充"],
        links: { folder: "/workspace/2026-01-01-pay-log" }
      })
    ]
  };

  const results = fallbackSearchResults(dashboard, "store-cashier", 5);

  assert.equal(results.length, 1);
  assert.equal(results[0].workspaceName, "Pay Log Workspace");
  assert.equal(results[0].kind, "workspace");
  assert.equal(results[0].documentPath, "/workspace/2026-01-01-pay-log");
  assert.match(results[0].snippet, /store-cashier/);
});

test("compactSearchSnippet keeps nearby context around a query", () => {
  const snippet = compactSearchSnippet("alpha beta gamma pay_log delta epsilon", "pay_log", 6);
  assert.equal(snippet, "...gamma pay_log delta...");
});

test("groupSearchResults gives the global search popover stable sections", () => {
  const results = [
    {
      workspaceFolder: "a",
      workspaceName: "A",
      documentKey: "workspace",
      documentName: "Workspace metadata",
      documentPath: "/a",
      kind: "workspace",
      snippet: "branch"
    },
    {
      workspaceFolder: "a",
      workspaceName: "A",
      documentKey: "sql",
      documentName: "SQL",
      documentPath: "/a/sql",
      kind: "sql",
      snippet: "alter table"
    },
    {
      workspaceFolder: "a",
      workspaceName: "A",
      documentKey: "tasks",
      documentName: "Tasks",
      documentPath: "/a/tasks.md",
      kind: "tasks",
      snippet: "todo"
    },
    {
      workspaceFolder: "a",
      workspaceName: "A",
      documentKey: "delivery",
      documentName: "Delivery",
      documentPath: "/a/delivery.md",
      kind: "delivery",
      snippet: "ship"
    }
  ];

  const groups = groupSearchResults(results);

  assert.deepEqual(
    groups.map((group) => [group.id, group.label, group.results.length]),
    [
      ["workspace", "工作区 / Workspace", 1],
      ["sql", "SQL 与数据变更 / SQL", 1],
      ["workflow", "任务与交付 / Workflow", 2]
    ]
  );
  assert.deepEqual(
    orderedSearchResults(results).map((result) => result.documentKey),
    ["workspace", "sql", "tasks", "delivery"]
  );
});

test("createSettingsProfile serializes shareable Nexus path settings", () => {
  const settings = {
    workspacesRoot: " ~/ks_project/workspaces ",
    sourceReposRoot: "~/ks_project/source-repos",
    docsRoot: "~/ks_project/docs",
    codexUrl: "",
    refreshIntervalSeconds: 1
  };
  const date = new Date("2026-05-26T08:30:00.000Z");

  const profile = createSettingsProfile(settings, date);

  assert.equal(profile.app, "Nexus");
  assert.equal(profile.schemaVersion, 1);
  assert.equal(profile.exportedAt, "2026-05-26T08:30:00.000Z");
  assert.equal(profile.settings.workspacesRoot, "~/ks_project/workspaces");
  assert.equal(profile.settings.codexUrl, "codex://");
  assert.equal(profile.settings.refreshIntervalSeconds, 3);
});

test("parseSettingsProfile validates and normalizes imported settings", () => {
  const serialized = serializeSettingsProfile(
    {
      workspacesRoot: "~/team/workspaces",
      sourceReposRoot: "~/team/source-repos",
      docsRoot: "~/team/docs",
      codexUrl: "codex://",
      refreshIntervalSeconds: 15
    },
    new Date("2026-05-26T08:30:00.000Z")
  );

  assert.deepEqual(parseSettingsProfile(serialized), {
    workspacesRoot: "~/team/workspaces",
    sourceReposRoot: "~/team/source-repos",
    docsRoot: "~/team/docs",
    codexUrl: "codex://",
    refreshIntervalSeconds: 15
  });
});

test("parseSettingsProfile rejects unrelated JSON files", () => {
  assert.throws(() => parseSettingsProfile(JSON.stringify({ app: "Other", schemaVersion: 1, settings: {} })), /不是 Nexus Profile/);
});

test("settingsProfileFilename uses the export date", () => {
  assert.equal(settingsProfileFilename("2026-05-26T08:30:00.000Z"), "nexus-settings-profile-2026-05-26.json");
});
