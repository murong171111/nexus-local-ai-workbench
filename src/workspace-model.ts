import type { DashboardData, Workspace } from "./types";

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

export function workspaceFolderFromName(name: string, date = new Date()) {
  return `${todayString(date)}-${slugify(name) || "workspace"}`;
}

export function normalizeServiceList(values: string[]) {
  return Array.from(new Set(values.map((value) => value.trim()).filter(Boolean))).sort((left, right) =>
    left.localeCompare(right)
  );
}

export function workspaceScore(workspace: Workspace) {
  return workspace.riskCount * 10 + workspace.gitRows.filter((row) => row.worktree.dirty).length * 3;
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
