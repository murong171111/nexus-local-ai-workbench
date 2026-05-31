import type { DashboardData, GitRow, Workspace, WorkspaceSessionAction } from "./types";

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

export type WorktreeStatusKind = "missing" | "branch-mismatch" | "dirty" | "source-dirty" | "clean";

export type WorktreeStatusSignal = {
  service: string;
  kind: WorktreeStatusKind;
  priority: "high" | "medium" | "low";
  label: string;
  detail: string;
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

export type WorkspaceFilterId = "all" | "risk" | "branch" | "dirty" | "missing" | "archived" | string;

export type WorkspaceFilterOptions = {
  query?: string;
  filter?: WorkspaceFilterId;
};

export type WorkspaceCreatePreflightIssue = {
  code: string;
  severity: "blocker" | "warning";
  message: string;
};

export type WorkspaceCreatePreflightInput = {
  name: string;
  folder: string;
  workspacesRoot: string;
  sourceReposRoot: string;
  services: string[];
  targetBranch: string;
  existingFolders?: string[];
  knownSourceRepos?: string[];
  environmentReady?: boolean;
};

export type WorkspaceCreatePreflightReport = {
  canCreate: boolean;
  issues: WorkspaceCreatePreflightIssue[];
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

export function workspaceFolderFromName(name: string, date = new Date()) {
  return `${todayString(date)}-${slugify(name) || "workspace"}`;
}

export function workspaceCreatePreflight(input: WorkspaceCreatePreflightInput): WorkspaceCreatePreflightReport {
  const issues: WorkspaceCreatePreflightIssue[] = [];
  const folder = input.folder.trim();
  const workspacesRoot = input.workspacesRoot.trim();
  const sourceReposRoot = input.sourceReposRoot.trim();
  const services = normalizeServiceList(input.services);
  const existingFolders = new Set(input.existingFolders ?? []);
  const knownSourceRepos = new Set((input.knownSourceRepos ?? []).map((service) => service.trim()).filter(Boolean));

  if (!input.name.trim()) {
    issues.push(preflightIssue("name-missing", "blocker", "需求名称不能为空 / Workspace name is required."));
  }
  if (!workspacesRoot) {
    issues.push(preflightIssue("workspaces-root-missing", "blocker", "创建本地文件前需要配置工作区根目录 / Workspaces root is required."));
  }
  if (!sourceReposRoot) {
    issues.push(preflightIssue("source-root-missing", "warning", "源仓库根目录未配置，后续 worktree 命令可能需要手动调整 / Source repositories root is missing."));
  }
  if (!folder || folder === `${todayString()}-workspace`) {
    issues.push(preflightIssue("folder-generic", "warning", "目录名较通用，建议使用更明确的需求名称 / Workspace folder is generic."));
  }
  if (folder.includes("..") || folder.includes("/") || folder.includes("\\")) {
    issues.push(preflightIssue("folder-invalid", "blocker", "工作区目录名必须是单个安全目录名 / Folder must be a single safe directory name."));
  }
  if (existingFolders.has(folder)) {
    issues.push(preflightIssue("folder-exists", "blocker", `工作区目录已存在 / Workspace folder already exists: ${folder}.`));
  }
  if (!hasConfirmedTargetBranch(input.targetBranch)) {
    issues.push(preflightIssue("target-branch-pending", "warning", "目标分支未确认，可以先建工作区，但 worktree 创建应稍后执行 / Target branch is pending."));
  }
  if (!services.length) {
    issues.push(preflightIssue("services-pending", "warning", "尚未确认服务范围，早期梳理阶段可以先保持待确认 / Service scope can stay pending."));
  }
  for (const service of services) {
    if (knownSourceRepos.size > 0 && !knownSourceRepos.has(service)) {
      issues.push(preflightIssue("service-source-missing", "warning", `最新源仓库扫描中没有该服务 / Service is not in the latest source repo scan: ${service}.`));
    }
  }
  if (input.environmentReady === false) {
    issues.push(preflightIssue("environment-not-ready", "warning", "环境检查仍有阻塞项，请复核路径和工具后再依赖后续动作 / Environment check has blockers."));
  }

  return {
    canCreate: issues.every((issue) => issue.severity !== "blocker"),
    issues
  };
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

export function worktreeStatusSignal(row: GitRow, targetBranch: string): WorktreeStatusSignal {
  const expectedBranch = normalizeGitBranch(targetBranch);
  const actualBranch = normalizeGitBranch(row.worktree.branch);
  const sourceBranch = normalizeGitBranch(row.source.branch);

  if (!row.worktree.exists) {
    return {
      service: row.service,
      kind: "missing",
      priority: "high",
      label: "缺失 worktree / Missing",
      detail: `${row.service} has no workspace worktree at ${row.worktreePath}.`
    };
  }

  if (hasConfirmedTargetBranch(targetBranch) && actualBranch && actualBranch !== expectedBranch) {
    return {
      service: row.service,
      kind: "branch-mismatch",
      priority: "high",
      label: "分支不一致 / Branch mismatch",
      detail: `${row.service} worktree is on ${actualBranch}; expected ${expectedBranch}.`
    };
  }

  if (row.worktree.dirty) {
    return {
      service: row.service,
      kind: "dirty",
      priority: "medium",
      label: "未提交改动 / Dirty worktree",
      detail: `${row.service} worktree has uncommitted changes: ${row.worktree.summary || "dirty"}.`
    };
  }

  if (row.source.exists && row.source.dirty) {
    return {
      service: row.service,
      kind: "source-dirty",
      priority: "low",
      label: "源仓库有改动 / Source dirty",
      detail: `${row.service} source repo has uncommitted changes: ${row.source.summary || "dirty"}.`
    };
  }

  return {
    service: row.service,
    kind: "clean",
    priority: "low",
    label: "就绪 / Clean",
    detail: `${row.service} worktree is ready on ${actualBranch || "unknown branch"}; source branch is ${sourceBranch || "unknown"}.`
  };
}

export function workspaceWorktreeSignals(workspace: Workspace) {
  return workspace.gitRows.map((row) => worktreeStatusSignal(row, workspace.targetBranch));
}

export function workspaceIsArchived(workspace: Workspace) {
  const normalized = `${workspace.state} ${workspace.lifecycle?.stage ?? ""}`.toLowerCase();
  return normalized.includes("archived") || normalized.includes("archive") || normalized.includes("归档");
}

export function workspaceSearchHaystack(workspace: Workspace) {
  return [
    workspace.name,
    workspace.folder,
    workspace.state,
    workspace.lifecycle?.stage ?? "",
    workspace.lifecycle?.label ?? "",
    workspace.targetBranch,
    workspace.sourceRoot,
    ...workspace.confirmedServices,
    ...workspace.candidateServices,
    ...workspace.risks
  ]
    .join(" ")
    .toLowerCase();
}

export function workspaceMatchesQuery(workspace: Workspace, query = "") {
  const normalizedQuery = query.trim().toLowerCase();
  return !normalizedQuery || workspaceSearchHaystack(workspace).includes(normalizedQuery);
}

export function workspaceMatchesFilter(workspace: Workspace, filter: WorkspaceFilterId = "all") {
  const archived = workspaceIsArchived(workspace);
  if (filter === "all") return true;
  if (filter === "archived") return archived;
  if (archived) return false;
  if (filter === "risk") return workspace.riskCount > 0;
  if (filter === "branch") return branchAlignmentRows(workspace).length > 0;
  if (filter === "dirty") return workspace.gitRows.some((row) => row.worktree.dirty);
  if (filter === "missing") return workspace.gitRows.some((row) => !row.worktree.exists);
  return true;
}

export function filterWorkspaces(workspaces: Workspace[], options: WorkspaceFilterOptions = {}) {
  return workspaces.filter((workspace) =>
    workspaceMatchesQuery(workspace, options.query) && workspaceMatchesFilter(workspace, options.filter)
  );
}

export function workspaceScore(workspace: Workspace) {
  const signals = workspaceWorktreeSignals(workspace);
  const missing = signals.filter((signal) => signal.kind === "missing").length;
  const mismatches = signals.filter((signal) => signal.kind === "branch-mismatch").length;
  const dirty = signals.filter((signal) => signal.kind === "dirty").length;
  return workspace.riskCount * 10 + missing * 6 + mismatches * 5 + dirty * 3;
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

export function isArchivedWorkspace(workspace: Workspace) {
  return workspaceIsArchived(workspace);
}

export function activeAttentionWorkspaces(workspaces: Workspace[]) {
  return workspaces.filter((workspace) => !isArchivedWorkspace(workspace));
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

function preflightIssue(code: string, severity: "blocker" | "warning", message: string): WorkspaceCreatePreflightIssue {
  return { code, severity, message };
}

export function widgetSnapshotFromDashboard(dashboard: DashboardData, activeFolder: string) {
  const attentionWorkspaces = activeAttentionWorkspaces(dashboard.workspaces);
  const activeWorkspace = dashboard.workspaces.find((workspace) => workspace.folder === activeFolder) ?? attentionWorkspaces[0] ?? dashboard.workspaces[0];
  const attentionGitRows = attentionWorkspaces.flatMap((workspace) => workspace.gitRows);
  return {
    generatedAt: new Date().toISOString(),
    workspacesRoot: dashboard.workspacesRoot,
    activeWorkspace: activeWorkspace?.name,
    activeWorkspaceFolder: activeWorkspace?.folder,
    workspaceCount: attentionWorkspaces.length,
    riskCount: attentionWorkspaces.reduce((sum, workspace) => sum + workspace.riskCount, 0),
    dirtyServiceCount: attentionGitRows.filter((row) => row.worktree.dirty).length,
    missingWorktreeCount: attentionGitRows.filter((row) => !row.worktree.exists).length,
    topRisks: attentionWorkspaces.flatMap((workspace) => workspace.risks.map((risk) => `${workspace.name}: ${risk}`)).slice(0, 3),
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
