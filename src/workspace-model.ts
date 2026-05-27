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
  if (parsed.app !== "Nexus") throw new Error("配置文件不是 Nexus Profile");
  if (parsed.schemaVersion !== 1) throw new Error("暂不支持该配置版本");
  if (!isRecord(parsed.settings)) throw new Error("配置文件缺少 settings");

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

  return groups;
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
