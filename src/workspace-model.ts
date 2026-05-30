import type { DashboardData, Workspace, WorkspaceSessionAction } from "./types";

export type ShareableNexusSettings = {
  workspacesRoot: string;
  sourceReposRoot: string;
  docsRoot: string;
  codexUrl: string;
  refreshIntervalSeconds: number;
};

export type NexusSettingsProfile = {
  schemaVersion: 1;
  app: "Nexus";
  exportedAt: string;
  settings: ShareableNexusSettings;
  notes: string[];
};

export type BranchAlignmentRow = {
  service: string;
  expectedBranch: string;
  actualBranch: string;
  sourceBranch: string;
};

export type WorkspaceSearchResult = {
  workspaceFolder: string;
  workspaceName: string;
  documentKey: string;
  documentName: string;
  documentPath: string;
  kind: string;
  snippet: string;
};

export type WorkspaceSearchResultGroup = {
  id: string;
  label: string;
  results: WorkspaceSearchResult[];
};

export type DashboardDataQualityIssue = {
  code: string;
  message: string;
  workspaceFolder?: string;
};

export type DashboardDataQualityReport = {
  ok: boolean;
  issues: DashboardDataQualityIssue[];
};

export function slugify(value: string) {
  return value
    .trim()
    .toLowerCase()
    .replace(/[^\p{Letter}\p{Number}]+/gu, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 48);
}

export function todayString(date = new Date()) {
  return date.toISOString().slice(0, 10);
}

export function settingsProfileFilename(exportedAt = new Date().toISOString()) {
  return `nexus-settings-profile-${exportedAt.slice(0, 10)}.json`;
}

export function createSettingsProfile(settings: ShareableNexusSettings, date = new Date()): NexusSettingsProfile {
  return {
    schemaVersion: 1,
    app: "Nexus",
    exportedAt: date.toISOString(),
    settings: normalizeSettings(settings),
    notes: [
      "This file stores local Nexus path conventions for team sharing.",
      "Review paths after importing because every machine can use different local roots."
    ]
  };
}

export function serializeSettingsProfile(settings: ShareableNexusSettings, date = new Date()) {
  return JSON.stringify(createSettingsProfile(settings, date), null, 2);
}

export function parseSettingsProfile(content: string): ShareableNexusSettings {
  let parsed: unknown;
  try {
    parsed = JSON.parse(content);
  } catch {
    throw new Error("配置文件不是有效 JSON");
  }

  if (!isRecord(parsed)) throw new Error("配置文件格式不正确");
  if (parsed.app !== "Nexus") throw new Error("配置文件不是 Nexus Profile：app 必须是 Nexus");
  if (parsed.schemaVersion !== 1) throw new Error(`暂不支持该配置版本：${String(parsed.schemaVersion ?? "缺失")}`);
  if (!isRecord(parsed.settings)) throw new Error("配置文件缺少 settings：需要包含 workspacesRoot、sourceReposRoot、docsRoot、codexUrl 和 refreshIntervalSeconds");

  return normalizeSettings({
    workspacesRoot: requiredString(parsed.settings.workspacesRoot, "workspacesRoot"),
    sourceReposRoot: requiredString(parsed.settings.sourceReposRoot, "sourceReposRoot"),
    docsRoot: requiredString(parsed.settings.docsRoot, "docsRoot"),
    codexUrl: requiredString(parsed.settings.codexUrl, "codexUrl"),
    refreshIntervalSeconds: Number(parsed.settings.refreshIntervalSeconds)
  });
}

function normalizeSettings(settings: ShareableNexusSettings): ShareableNexusSettings {
  return {
    workspacesRoot: settings.workspacesRoot.trim(),
    sourceReposRoot: settings.sourceReposRoot.trim(),
    docsRoot: settings.docsRoot.trim(),
    codexUrl: settings.codexUrl.trim() || "codex://",
    refreshIntervalSeconds: Math.max(3, Number(settings.refreshIntervalSeconds) || 10)
  };
}

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === "object" && value !== null;
}

function requiredString(value: unknown, label: string) {
  if (typeof value !== "string" || !value.trim()) {
    throw new Error(`配置文件缺少 ${label}`);
  }
  return value;
}

export function dashboardDataQualityReport(dashboard: DashboardData): DashboardDataQualityReport {
  const issues: DashboardDataQualityIssue[] = [];
  const seenFolders = new Set<string>();

  if (!hasText(dashboard.generatedAt)) {
    issues.push(dataIssue("generated-at-missing", "Dashboard data is missing generatedAt."));
  } else if (Number.isNaN(Date.parse(dashboard.generatedAt))) {
    issues.push(dataIssue("generated-at-invalid", `Dashboard generatedAt is not an ISO-compatible date: ${dashboard.generatedAt}`));
  }
  if (!hasText(dashboard.workspacesRoot)) {
    issues.push(dataIssue("workspaces-root-missing", "Dashboard data is missing workspacesRoot."));
  }

  for (const workspace of dashboard.workspaces) {
    const workspaceFolder = hasText(workspace.folder) ? workspace.folder.trim() : "";
    if (!workspaceFolder) {
      issues.push(dataIssue("workspace-folder-missing", `Workspace "${workspace.name || "unnamed"}" is missing folder.`));
    } else if (seenFolders.has(workspaceFolder)) {
      issues.push(dataIssue("workspace-folder-duplicate", `Workspace folder is duplicated: ${workspaceFolder}`, workspaceFolder));
    } else {
      seenFolders.add(workspaceFolder);
    }

    if (!hasText(workspace.name)) {
      issues.push(dataIssue("workspace-name-missing", "Workspace is missing name.", workspaceFolder));
    }
    if (!pathLooksInsideRoot(workspace.path, dashboard.workspacesRoot, workspace.folder)) {
      issues.push(dataIssue("workspace-path-outside-root", `Workspace path should live under workspacesRoot and end with its folder: ${workspace.path}`, workspaceFolder));
    }
    if (workspace.riskCount !== workspace.risks.length) {
      issues.push(dataIssue("risk-count-mismatch", `riskCount is ${workspace.riskCount} but risks has ${workspace.risks.length} item(s).`, workspaceFolder));
    }
    for (const [key, value] of Object.entries(workspace.taskCounts)) {
      if (!Number.isInteger(value) || value < 0) {
        issues.push(dataIssue("task-count-invalid", `taskCounts.${key} must be a non-negative integer.`, workspaceFolder));
      }
    }
    if (!Number.isInteger(workspace.decisionCount) || workspace.decisionCount < 0) {
      issues.push(dataIssue("decision-count-invalid", "decisionCount must be a non-negative integer.", workspaceFolder));
    }

    const gitServices = new Set(workspace.gitRows.map((row) => row.service));
    for (const service of workspace.confirmedServices) {
      if (!gitServices.has(service)) {
        issues.push(dataIssue("confirmed-service-missing-git-row", `Confirmed service "${service}" has no matching gitRows entry.`, workspaceFolder));
      }
    }
    for (const row of workspace.gitRows) {
      if (!row.service.trim()) {
        issues.push(dataIssue("git-row-service-missing", "A gitRows entry is missing service.", workspaceFolder));
      }
      if (row.service && !row.sourcePath.endsWith(`/${row.service}`)) {
        issues.push(dataIssue("git-source-path-mismatch", `sourcePath for "${row.service}" should end with the service name.`, workspaceFolder));
      }
      if (row.service && !row.worktreePath.endsWith(`/repos/${row.service}`)) {
        issues.push(dataIssue("git-worktree-path-mismatch", `worktreePath for "${row.service}" should end with repos/<service>.`, workspaceFolder));
      }
    }

    if (workspace.links.folder && workspace.links.folder !== workspace.path) {
      issues.push(dataIssue("folder-link-mismatch", "links.folder should match workspace.path.", workspaceFolder));
    }
  }

  return { ok: issues.length === 0, issues };
}

export function workspaceFolderFromName(name: string, date = new Date()) {
  return `${todayString(date)}-${slugify(name) || "workspace"}`;
}

export function parseServiceInput(value: string) {
  return value
    .split(/[,\n，、;；\s]+/u)
    .map((service) => service.trim())
    .filter(Boolean);
}

export function normalizeServiceList(values: string[]) {
  return Array.from(new Set(values.flatMap(parseServiceInput))).sort((left, right) =>
    left.localeCompare(right)
  );
}

export function shellQuote(value: string) {
  return `'${value.replace(/'/g, "'\\''")}'`;
}

export function buildWorktreeCommand(workspacePath: string, sourceRoot: string, services: string[], targetBranch: string) {
  const branch = targetBranch.trim() && !targetBranch.includes("待确认") ? targetBranch.trim() : "<target-branch>";
  const normalized = normalizeServiceList(services);
  if (!normalized.length) {
    return "# No services are confirmed yet. Add services before creating worktrees.";
  }
  return normalized
    .map((service) => {
      const sourcePath = `${sourceRoot}/${service}`;
      const targetPath = `${workspacePath}/repos/${service}`;
      return [`# ${service}`, `git -C ${shellQuote(sourcePath)} fetch origin`, `git -C ${shellQuote(sourcePath)} worktree add ${shellQuote(targetPath)} ${shellQuote(branch)}`].join("\n");
    })
    .join("\n\n");
}

export function normalizeGitBranch(value: string) {
  return value
    .replace(/^##\s*/, "")
    .split("...")[0]
    .split(" ")[0]
    .trim();
}

export function hasConfirmedTargetBranch(value: string) {
  const branch = normalizeGitBranch(value);
  return Boolean(branch) && !branch.includes("待确认") && branch !== "<target-branch>";
}

export function branchAlignmentRows(workspace: Workspace): BranchAlignmentRow[] {
  if (!hasConfirmedTargetBranch(workspace.targetBranch)) return [];

  const expectedBranch = normalizeGitBranch(workspace.targetBranch);
  return workspace.gitRows
    .filter((row) => row.worktree.exists)
    .map((row) => ({
      service: row.service,
      expectedBranch,
      actualBranch: normalizeGitBranch(row.worktree.branch),
      sourceBranch: normalizeGitBranch(row.source.branch)
    }))
    .filter((row) => row.actualBranch && row.actualBranch !== expectedBranch);
}

export function workspaceScore(workspace: Workspace) {
  return workspace.riskCount * 10 + branchAlignmentRows(workspace).length * 5 + workspace.gitRows.filter((row) => row.worktree.dirty).length * 3;
}

export function sortWorkspacesForAttention(workspaces: Workspace[], pinnedFolders: Iterable<string> = []) {
  const pinned = new Set(pinnedFolders);
  return [...workspaces].sort((left, right) => {
    const leftPinned = pinned.has(left.folder);
    const rightPinned = pinned.has(right.folder);
    if (leftPinned !== rightPinned) return leftPinned ? -1 : 1;

    const scoreDelta = workspaceScore(right) - workspaceScore(left);
    if (scoreDelta !== 0) return scoreDelta;

    return left.name.localeCompare(right.name);
  });
}

export function workspaceSessionActions(workspace: Workspace): WorkspaceSessionAction[] {
  if (workspace.sessionActions?.length) return workspace.sessionActions;

  const actions: WorkspaceSessionAction[] = [];
  const missingWorktrees = workspace.gitRows.filter((row) => !row.worktree.exists).map((row) => row.service);
  const dirtyWorktrees = workspace.gitRows.filter((row) => row.worktree.dirty).map((row) => row.service);
  const mismatches = branchAlignmentRows(workspace).map((row) => `${row.service}(${row.actualBranch})`);
  const deliveryRisk = workspace.risks.find((risk) => risk.includes("交付") || risk.toLowerCase().includes("delivery"));

  if (!workspace.confirmedServices.length) {
    actions.push(sessionAction("confirm-services", "确认服务范围 / Confirm services", "先补齐已确认服务，后续 worktree 和风险检查才有可靠目标。", "high", "blocked", "risk", "services"));
  }

  if (!hasConfirmedTargetBranch(workspace.targetBranch)) {
    actions.push(sessionAction("confirm-target-branch", "确认目标分支 / Confirm branch", "目标分支仍是待确认状态，创建 worktree 前需要先定分支。", "high", "blocked", "git", "branches"));
  }

  if (missingWorktrees.length) {
    actions.push(sessionAction("create-worktrees", "创建缺失 worktree / Create worktrees", `缺少 worktree: ${missingWorktrees.join(", ")}`, "high", "recommended", "worktree", "worktreeScript"));
  }

  if (mismatches.length) {
    actions.push(sessionAction("align-branches", "修正分支不一致 / Align branches", `分支不一致: ${mismatches.join(", ")}`, "high", "blocked", "git", "branches"));
  }

  if (dirtyWorktrees.length) {
    actions.push(sessionAction("review-dirty-worktrees", "复核未提交改动 / Review changes", `存在未提交改动: ${dirtyWorktrees.join(", ")}`, "medium", "recommended", "git", "status"));
  }

  if (deliveryRisk) {
    actions.push(sessionAction("update-delivery-record", "更新交付记录 / Update delivery", deliveryRisk, "medium", "recommended", "delivery", "delivery"));
  }

  if (workspace.taskCounts.blocked > 0) {
    actions.push(sessionAction("resolve-blocked-tasks", "处理阻塞任务 / Resolve blockers", `tasks.md 中存在 ${workspace.taskCounts.blocked} 个阻塞任务。`, "medium", "recommended", "risk", "tasks"));
  }

  const readyToStart = actions.length === 0;
  actions.push(sessionAction(
    "start-codex-session",
    "启动 Codex 会话 / Start Codex session",
    readyToStart ? "就绪检查已通过，可以复制完整上下文并进入开发会话。" : "复制当前工作区上下文，带着上方动作进入 Codex 继续处理。",
    readyToStart ? "high" : "low",
    "recommended",
    "continue",
    "handoff"
  ));

  return actions;
}

function sessionAction(
  id: string,
  label: string,
  detail: string,
  priority: string,
  status: string,
  instructionType: string,
  documentKey: string
): WorkspaceSessionAction {
  return { id, label, detail, priority, status, instructionType, documentKey };
}

function dataIssue(code: string, message: string, workspaceFolder?: string): DashboardDataQualityIssue {
  return workspaceFolder ? { code, message, workspaceFolder } : { code, message };
}

function hasText(value: string | undefined) {
  return Boolean(String(value ?? "").trim());
}

function pathLooksInsideRoot(pathValue: string, rootValue: string, folder: string) {
  const normalizedPath = pathValue.replace(/\/+$/g, "");
  const normalizedRoot = rootValue.replace(/\/+$/g, "");
  const normalizedFolder = folder.replace(/^\/+|\/+$/g, "");
  return Boolean(normalizedRoot && normalizedFolder)
    && normalizedPath === `${normalizedRoot}/${normalizedFolder}`;
}

export function widgetSnapshotFromDashboard(dashboard: DashboardData, activeFolder: string) {
  const activeWorkspace = dashboard.workspaces.find((workspace) => workspace.folder === activeFolder) ?? dashboard.workspaces[0];
  const allGitRows = dashboard.workspaces.flatMap((workspace) => workspace.gitRows);
  return {
    generatedAt: new Date().toISOString(),
    workspacesRoot: dashboard.workspacesRoot,
    activeWorkspace: activeWorkspace?.name,
    activeWorkspaceFolder: activeWorkspace?.folder,
    workspaceCount: dashboard.workspaces.length,
    riskCount: dashboard.workspaces.reduce((sum, workspace) => sum + workspace.riskCount, 0),
    dirtyServiceCount: allGitRows.filter((row) => row.worktree.dirty).length,
    missingWorktreeCount: allGitRows.filter((row) => !row.worktree.exists).length,
    topRisks: dashboard.workspaces.flatMap((workspace) => workspace.risks.map((risk) => `${workspace.name}: ${risk}`)).slice(0, 3),
    deepLink: activeWorkspace ? `nexus://workspace/${encodeURIComponent(activeWorkspace.folder)}` : "nexus://"
  };
}

export function fallbackSearchResults(dashboard: DashboardData, query: string, limit = 8): WorkspaceSearchResult[] {
  const normalizedQuery = query.trim().toLowerCase();
  if (!normalizedQuery) return [];

  return dashboard.workspaces
    .map((workspace) => {
      const parts = [
        workspace.name,
        workspace.folder,
        workspace.targetBranch,
        workspace.sourceRoot,
        ...workspace.confirmedServices,
        ...workspace.candidateServices,
        ...workspace.risks,
        workspace.worktreeCommand
      ];
      const haystack = parts.join(" ").toLowerCase();
      if (!haystack.includes(normalizedQuery)) return null;

      return {
        workspaceFolder: workspace.folder,
        workspaceName: workspace.name,
        documentKey: "workspace",
        documentName: "Workspace metadata",
        documentPath: workspace.links.folder || workspace.path,
        kind: "workspace",
        snippet: compactSearchSnippet(
          [
            workspace.targetBranch,
            workspace.confirmedServices.join(", ") || "服务待确认",
            workspace.risks[0] || "暂无风险"
          ].join(" · "),
          query
        )
      };
    })
    .filter((result): result is WorkspaceSearchResult => Boolean(result))
    .sort((left, right) => fallbackSearchRank(left, normalizedQuery) - fallbackSearchRank(right, normalizedQuery))
    .slice(0, Math.max(1, limit));
}

export function groupSearchResults(results: WorkspaceSearchResult[]): WorkspaceSearchResultGroup[] {
  const groups: WorkspaceSearchResultGroup[] = [];
  const groupsById = new Map<string, WorkspaceSearchResultGroup>();

  for (const result of results) {
    const group = searchResultGroupForKind(result.kind);
    let existing = groupsById.get(group.id);
    if (!existing) {
      existing = { ...group, results: [] };
      groupsById.set(group.id, existing);
      groups.push(existing);
    }
    existing.results.push(result);
  }

  return groups.sort((left, right) => searchResultGroupRank(left.id) - searchResultGroupRank(right.id));
}

export function orderedSearchResults(results: WorkspaceSearchResult[]) {
  return groupSearchResults(results).flatMap((group) => group.results);
}

function searchResultGroupForKind(kind: string) {
  if (kind === "workspace") return { id: "workspace", label: "工作区 / Workspace" };
  if (kind === "sql") return { id: "sql", label: "SQL 与数据变更 / SQL" };
  if (kind === "services" || kind === "branches" || kind === "status") {
    return { id: "state", label: "服务与状态 / State" };
  }
  if (kind === "tasks" || kind === "decisions" || kind === "delivery") {
    return { id: "workflow", label: "任务与交付 / Workflow" };
  }
  return { id: "documents", label: "文档 / Documents" };
}

function searchResultGroupRank(groupId: string) {
  const ranks: Record<string, number> = {
    workspace: 0,
    state: 1,
    workflow: 2,
    sql: 3,
    documents: 4
  };
  return ranks[groupId] ?? 99;
}

function fallbackSearchRank(result: WorkspaceSearchResult, query: string) {
  const name = result.workspaceName.toLowerCase();
  const folder = result.workspaceFolder.toLowerCase();
  const snippet = result.snippet.toLowerCase();

  if (name === query || folder === query) return 0;
  if (name.startsWith(query) || folder.startsWith(query)) return 1;
  if (name.includes(query) || folder.includes(query)) return 2;
  if (snippet.includes(query)) return 3;
  return 4;
}

export function compactSearchSnippet(content: string, query: string, radius = 72) {
  const trimmed = content.replace(/\s+/g, " ").trim();
  if (!trimmed) return "";

  const lower = trimmed.toLowerCase();
  const needle = query.trim().toLowerCase();
  const index = needle ? lower.indexOf(needle) : -1;
  if (index < 0) return trimmed.slice(0, radius * 2);

  const start = Math.max(0, index - radius);
  const end = Math.min(trimmed.length, index + needle.length + radius);
  return `${start > 0 ? "..." : ""}${trimmed.slice(start, end)}${end < trimmed.length ? "..." : ""}`;
}
