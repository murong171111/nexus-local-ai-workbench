import {
  Activity,
  AlertTriangle,
  BookOpen,
  Boxes,
  Braces,
  Check,
  Clipboard,
  CheckCircle2,
  ChevronDown,
  CircleDot,
  Command,
  Database,
  Download,
  ExternalLink,
  FileText,
  FolderOpen,
  GitBranch,
  GitCommit,
  ListChecks,
  Plus,
  RefreshCw,
  Search,
  Settings,
  Sparkles,
  Terminal,
  Upload,
  Workflow,
  X,
  type LucideIcon
} from "lucide-react";
import { useCallback, useEffect, useMemo, useRef, useState, type KeyboardEvent as ReactKeyboardEvent } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import rawData from "./data/workspaces.json";
import { Badge } from "./components/ui/badge";
import { Button } from "./components/ui/button";
import { Card } from "./components/ui/card";
import { Input } from "./components/ui/input";
import { appendAuditEvent, checkEnvironment, createWorkspace, exportSettingsProfile, openExternalUrl, openPath as openPathInDesktop, readTextFile, rebuildSearchIndex, scanSourceRepos, scanWorkspaces, searchIndex, writeWidgetSnapshot, type EnvironmentHealth, type RebuildSearchIndexResponse, type SearchResult, type SourceRepo } from "./desktop";
import { cn, riskTone } from "./lib";
import { branchAlignmentRows, buildWorktreeCommand, createSettingsProfile, fallbackSearchResults, groupSearchResults, normalizeServiceList, orderedSearchResults, parseServiceInput, parseSettingsProfile, settingsProfileFilename, todayString, widgetSnapshotFromDashboard, workspaceFolderFromName, workspaceScore, type NexusSettingsProfile } from "./workspace-model";
import type { DashboardData, Workspace } from "./types";

const initialData = rawData as DashboardData;

const stateLabels: Record<string, string> = {
  analyzing: "分析中 / Analyzing",
  developing: "开发中 / Developing",
  testing: "验证中 / Verifying",
  delivered: "已交付 / Delivered",
  archived: "已归档 / Archived",
  unknown: "未知 / Unknown"
};

const filterLabels: Record<string, { title: string; desc: string }> = {
  all: { title: "全部", desc: "All" },
  risk: { title: "有风险", desc: "Risk" },
  branch: { title: "分支不一致", desc: "Branch" },
  dirty: { title: "有改动", desc: "Dirty" },
  missing: { title: "缺 worktree", desc: "Missing" }
};

const statLabels: Record<string, { title: string; desc: string }> = {
  workspaces: { title: "工作区", desc: "Workspaces" },
  services: { title: "服务", desc: "Services" },
  risks: { title: "风险项", desc: "Risks" },
  branch: { title: "分支不一致", desc: "Branch mismatch" },
  missing: { title: "缺失 Worktree", desc: "Missing worktree" }
};

const auditActionLabels: Record<string, string> = {
  "codex.opened": "Codex 已打开 / Codex opened",
  "codex_instruction.copied": "Codex 指令已复制 / Instruction copied",
  "codex_handoff.opened": "Codex 交接已打开 / Codex handoff",
  "document.opened": "文档已打开 / Document opened",
  "risk_instruction.copied": "风险指令已复制 / Risk instruction",
  "workspace.created": "工作区已创建 / Workspace created",
  "worktree.command.copied": "Worktree 命令已复制 / Worktree command"
};

function auditActivityTitle(action: string) {
  return auditActionLabels[action] ?? action.replace(/[_.]/g, " ");
}

function activityTimestamp() {
  return new Date().toISOString().slice(0, 16).replace("T", " ");
}

type NexusSettings = {
  workspacesRoot: string;
  sourceReposRoot: string;
  docsRoot: string;
  codexUrl: string;
  refreshIntervalSeconds: number;
};

type SearchIndexState = {
  state: "idle" | "building" | "ready" | "preview" | "error";
  message: string;
  path?: string;
  workspaceCount?: number;
  documentCount?: number;
};

const settingsStorageKey = "nexus-settings";
const onboardingStorageKey = "nexus-onboarding-complete";

function settingsFromDashboard(dashboard: DashboardData): NexusSettings {
  return {
    workspacesRoot: dashboard.workspacesRoot,
    sourceReposRoot: dashboard.sourceReposRoot ?? "~/ks_project/source-repos",
    docsRoot: dashboard.docsRoot ?? "~/ks_project/docs",
    codexUrl: "codex://",
    refreshIntervalSeconds: 10
  };
}

function loadSettings(dashboard: DashboardData) {
  const defaults = settingsFromDashboard(dashboard);
  try {
    const stored = window.localStorage.getItem(settingsStorageKey);
    if (!stored) return defaults;
    const parsed = JSON.parse(stored) as Partial<NexusSettings>;
    return {
      ...defaults,
      ...parsed,
      refreshIntervalSeconds: Number(parsed.refreshIntervalSeconds || defaults.refreshIntervalSeconds)
    };
  } catch {
    return defaults;
  }
}

function shouldShowOnboarding() {
  try {
    return !window.localStorage.getItem(settingsStorageKey) && !window.localStorage.getItem(onboardingStorageKey);
  } catch {
    return false;
  }
}

function browserEnvironmentFallback(settings: NexusSettings, dashboard: DashboardData, sourceRepos: SourceRepo[]): EnvironmentHealth {
  const checks = [
    { key: "workspacesRoot", label: "工作区目录", path: settings.workspacesRoot },
    { key: "sourceReposRoot", label: "源仓库目录", path: settings.sourceReposRoot },
    { key: "docsRoot", label: "交付文档目录", path: settings.docsRoot }
  ];
  return {
    generatedAt: new Date().toISOString(),
    ready: true,
    pathChecks: checks.map((check) => ({
      ...check,
      exists: true,
      isDir: true,
      writable: true,
      summary: "浏览器预览模式下未检查本机目录"
    })),
    toolChecks: [{ key: "git", label: "Git", available: true, summary: "浏览器预览模式" }],
    workspaceCount: dashboard.workspaces.length,
    sourceRepoCount: sourceRepos.length,
    blockers: [],
    warnings: ["浏览器预览模式不会读取真实本机目录，打包应用内会执行原生检查。"]
  };
}

function downloadSettingsProfile(profile: NexusSettingsProfile) {
  const blob = new Blob([JSON.stringify(profile, null, 2)], { type: "application/json" });
  const url = window.URL.createObjectURL(blob);
  const link = window.document.createElement("a");
  link.href = url;
  link.download = settingsProfileFilename(profile.exportedAt);
  window.document.body.appendChild(link);
  link.click();
  link.remove();
  window.URL.revokeObjectURL(url);
}

function toneForRisk(count: number) {
  const tone = riskTone(count);
  if (tone === "high") return "red";
  if (tone === "medium") return "amber";
  if (tone === "low") return "blue";
  return "green";
}

function codexInstruction(workspace: Workspace, action: "continue" | "git" | "delivery" | "risk" | "worktree") {
  if (action === "continue") {
    return `继续工作区：${workspace.folder}\n需求：${workspace.name}\n请先读取该工作区的 AGENTS.md、STATUS.md、services.md、branches.md、tasks.md 和交付记录.md，然后总结当前状态、风险和下一步建议。`;
  }
  if (action === "git") {
    return `检查工作区 ${workspace.folder} 的所有相关服务 git 状态。\n请重点检查 workspaces/${workspace.folder}/repos 下的 worktree 是否存在、分支是否匹配、是否有未提交改动，并给出处理建议。`;
  }
  if (action === "delivery") {
    return `更新工作区 ${workspace.folder} 的交付记录。\n请根据本次代码/SQL/逻辑变更，补充交付记录.md，包含涉及服务、分支、变更点、SQL、验证结果和遗留风险。`;
  }
  if (action === "worktree") {
    return workspace.worktreeCommand;
  }
  return `分析工作区 ${workspace.folder} 的风险项。\n当前风险：\n${workspace.risks.map((risk) => `- ${risk}`).join("\n") || "- 暂无"}\n请逐项解释原因、影响范围和建议处理动作。`;
}

function riskInstruction(workspace: Workspace, risk: string) {
  if (risk.includes("分支不一致")) {
    return `工作区 ${workspace.folder} 存在风险：${risk}\n请读取 branches.md 并检查每个 repos/<service> worktree 的实际分支是否等于目标分支 ${workspace.targetBranch}。请列出不一致服务、当前分支、建议切换或重建 worktree 的命令，并提醒不要直接切换源仓库分支。`;
  }
  if (risk.includes("目标分支")) {
    return `工作区 ${workspace.folder} 存在风险：${risk}\n请读取 branches.md 和 workspace.md，确认目标分支命名，并给出是否需要创建 worktree 的建议。`;
  }
  if (risk.includes("worktree")) {
    return `工作区 ${workspace.folder} 存在风险：${risk}\n请基于 services.md 中已确认服务，检查 repos/<service> 是否存在，并给出创建 worktree 的命令。`;
  }
  if (risk.includes("服务范围")) {
    return `工作区 ${workspace.folder} 存在风险：${risk}\n请读取需求文档和 services.md，梳理已确认服务、候选服务和仍需验证的调用链。`;
  }
  if (risk.includes("交付")) {
    return `工作区 ${workspace.folder} 存在风险：${risk}\n请检查交付记录.md 是否存在并补齐交付记录结构。`;
  }
  return `工作区 ${workspace.folder} 存在风险：${risk}\n请分析该风险的原因、影响和建议处理动作。`;
}

function Stat({ label, value, icon: Icon }: { label: { title: string; desc: string }; value: string | number; icon: LucideIcon }) {
  return (
    <div className="rounded-lg border border-neutral-200 bg-white px-3 py-3">
      <div className="flex items-center justify-between text-neutral-500">
        <span className="text-xs">{label.title}</span>
        <Icon className="h-3.5 w-3.5" />
      </div>
      <div className="mono mt-1 text-[10px] uppercase tracking-wide text-neutral-400">{label.desc}</div>
      <div className="mono mt-2 text-xl text-neutral-950">{value}</div>
    </div>
  );
}

function Sidebar({
  workspaces,
  active,
  setActive,
  filter,
  setFilter,
  onOpenCreate,
  onOpenSettings
}: {
  workspaces: Workspace[];
  active: string;
  setActive: (folder: string) => void;
  filter: string;
  setFilter: (filter: string) => void;
  onOpenCreate: () => void;
  onOpenSettings: () => void;
}) {
  const filters = ["all", "risk", "branch", "dirty", "missing"];

  return (
    <aside className="flex max-h-[42vh] flex-col border-b border-neutral-200 bg-neutral-50 px-3 py-4 lg:sticky lg:top-0 lg:h-screen lg:max-h-none lg:border-b-0 lg:border-r">
      <div className="px-2">
        <div className="flex items-center gap-2">
          <div className="flex h-8 w-8 items-center justify-center rounded-md bg-blue-500/15 text-blue-600">
            <Terminal className="h-4 w-4" />
          </div>
          <div>
            <div className="text-sm font-medium text-neutral-950">Nexus</div>
            <div className="mono text-[11px] text-neutral-500">Local AI Workbench</div>
          </div>
        </div>
      </div>

      <div className="mt-4 rounded-lg border border-neutral-200 bg-white p-3 lg:mt-6">
        <div className="flex items-center justify-between">
          <span className="text-xs text-neutral-500">Agent 状态</span>
          <Badge tone="blue">就绪 / Ready</Badge>
        </div>
        <div className="mt-3 flex items-center gap-2 text-sm text-neutral-900">
          <CircleDot className="h-3.5 w-3.5 text-emerald-600" />
          扫描 Markdown 与 Git
        </div>
        <div className="mt-1 text-xs text-neutral-500">用于同步工作区文档、服务状态和本地 worktree。</div>
      </div>

      <div className="mt-4 lg:mt-5">
        <div className="px-2 text-xs uppercase tracking-[0.14em] text-neutral-400">快速筛选 / Filters</div>
        <div className="mt-2 grid grid-cols-2 gap-1 lg:grid-cols-1">
          {filters.map((id) => (
            <button
              key={id}
              onClick={() => setFilter(id)}
              className={cn(
                "flex h-10 items-center justify-between rounded-md px-2 text-left text-sm text-neutral-600 transition-colors",
                filter === id && "bg-neutral-100 text-neutral-950"
              )}
            >
              <span>
                <span className="block leading-4">{filterLabels[id].title}</span>
                <span className="mono block text-[10px] text-neutral-400">{filterLabels[id].desc}</span>
              </span>
              {id === "risk" && <span className="mono text-[11px]">{workspaces.filter((w) => w.riskCount).length}</span>}
              {id === "branch" && <span className="mono text-[11px]">{workspaces.filter((w) => branchAlignmentRows(w).length).length}</span>}
            </button>
          ))}
        </div>
      </div>

      <div className="mt-4 min-h-0 flex-1 overflow-auto lg:mt-5">
        <div className="px-2 text-xs uppercase tracking-[0.14em] text-neutral-400">工作区 / Workspaces</div>
        <div className="mt-2 grid gap-1">
          {workspaces.map((workspace) => (
            <button
              key={workspace.folder}
              onClick={() => setActive(workspace.folder)}
              className={cn(
                "rounded-md px-2 py-2 text-left transition-colors hover:bg-neutral-50",
                active === workspace.folder && "bg-neutral-100"
              )}
            >
              <div className="flex items-center justify-between gap-2">
                <span className="truncate text-sm text-neutral-900">{workspace.name}</span>
                {workspace.riskCount > 0 && <span className="h-1.5 w-1.5 shrink-0 rounded-full bg-amber-400" />}
              </div>
              <div className="mono mt-1 truncate text-[11px] text-neutral-400">{workspace.folder}</div>
            </button>
          ))}
        </div>
      </div>

      <div className="mt-4 grid gap-2 border-t border-neutral-200 pt-3">
        <Button className="w-full justify-start" onClick={onOpenCreate}>
          <Plus className="h-4 w-4" />
          新建工作区
        </Button>
        <Button variant="ghost" className="w-full justify-start text-neutral-600" onClick={onOpenSettings}>
          <Settings className="h-4 w-4" />
          设置
        </Button>
      </div>
    </aside>
  );
}

function TopBar({
  query,
  setQuery,
  current,
  dashboard,
  refreshEnabled,
  searchResults,
  searchSearching,
  searchIndexState,
  selectedSearchIndex,
  onToggleRefresh,
  onRefresh,
  onCommand,
  onOpenCodex,
  onOpenSearchResult,
  onOpenSelectedSearchResult,
  onMoveSearchSelection,
  onRebuildSearchIndex
}: {
  query: string;
  setQuery: (query: string) => void;
  current?: Workspace;
  dashboard: DashboardData;
  refreshEnabled: boolean;
  searchResults: SearchResult[];
  searchSearching: boolean;
  searchIndexState: SearchIndexState;
  selectedSearchIndex: number;
  onToggleRefresh: () => void;
  onRefresh: () => void;
  onCommand: () => void;
  onOpenCodex: () => void;
  onOpenSearchResult: (result: SearchResult) => void;
  onOpenSelectedSearchResult: () => void;
  onMoveSearchSelection: (direction: 1 | -1) => void;
  onRebuildSearchIndex: () => void;
}) {
  const dirty = dashboard.workspaces.flatMap((workspace) => workspace.gitRows).filter((row) => row.worktree.dirty).length;
  const branchMismatches = dashboard.workspaces.reduce((sum, workspace) => sum + branchAlignmentRows(workspace).length, 0);
  const trimmedQuery = query.trim();
  const activeSearchId = trimmedQuery && searchResults.length ? `search-result-${selectedSearchIndex}` : undefined;

  const handleSearchKeyDown = (event: ReactKeyboardEvent<HTMLInputElement>) => {
    if (!trimmedQuery) return;

    if (event.key === "ArrowDown") {
      event.preventDefault();
      onMoveSearchSelection(1);
      return;
    }
    if (event.key === "ArrowUp") {
      event.preventDefault();
      onMoveSearchSelection(-1);
      return;
    }
    if (event.key === "Enter" && !event.nativeEvent.isComposing) {
      event.preventDefault();
      onOpenSelectedSearchResult();
      return;
    }
    if (event.key === "Escape") {
      event.preventDefault();
      setQuery("");
    }
  };

  return (
    <header className="sticky top-0 z-20 border-b border-neutral-200 bg-white px-4 py-3 xl:px-5">
      <div className="flex flex-wrap items-center gap-2 xl:gap-3">
        <div className="relative min-w-[260px] flex-1 xl:max-w-xl">
          <Search className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-neutral-400" />
          <Input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            onKeyDown={handleSearchKeyDown}
            placeholder="搜索工作区、文档、SQL、任务..."
            className="pl-9"
            role="combobox"
            aria-expanded={Boolean(trimmedQuery)}
            aria-controls="global-search-results"
            aria-activedescendant={activeSearchId}
          />
          <SearchResultsPopover
            query={query}
            results={searchResults}
            searching={searchSearching}
            indexState={searchIndexState}
            selectedIndex={selectedSearchIndex}
            onOpenResult={onOpenSearchResult}
            onRebuild={onRebuildSearchIndex}
          />
        </div>
        <Button variant="outline" className="mono" onClick={onCommand}>
          <Command className="h-4 w-4" />
          K
        </Button>
        <Button variant="outline" className="mono" onClick={onOpenCodex} title="打开 Codex / Open Codex">
          <Sparkles className="h-4 w-4" />
          Codex
        </Button>
        <Button variant="ghost" className="mono" onClick={onRefresh} title="刷新数据 / Refresh data">
          <RefreshCw className="h-4 w-4" />
        </Button>
        <button
          onClick={onToggleRefresh}
          className={cn(
            "mono inline-flex h-9 items-center rounded-md border px-2 text-xs transition-colors",
            refreshEnabled
              ? "border-blue-400/25 bg-blue-500/10 text-blue-700"
              : "border-neutral-200 bg-white text-neutral-500"
          )}
        >
          实时 {refreshEnabled ? "开" : "关"}
        </button>
        <Badge tone={dirty ? "amber" : "green"}>
          <GitCommit className="h-3 w-3" />
          {dirty ? `${dirty} dirty` : "git clean"}
        </Badge>
        <Badge tone={branchMismatches ? "amber" : "green"}>
          <GitBranch className="h-3 w-3" />
          {branchMismatches ? `${branchMismatches} branch` : "branch aligned"}
        </Badge>
        <Badge tone="blue" className="max-w-full truncate xl:max-w-[320px]">
          <Workflow className="h-3 w-3" />
          {current?.name ?? "No workspace"}
        </Badge>
      </div>
    </header>
  );
}

function SearchResultsPopover({
  query,
  results,
  searching,
  indexState,
  selectedIndex,
  onOpenResult,
  onRebuild
}: {
  query: string;
  results: SearchResult[];
  searching: boolean;
  indexState: SearchIndexState;
  selectedIndex: number;
  onOpenResult: (result: SearchResult) => void;
  onRebuild: () => void;
}) {
  const trimmedQuery = query.trim();
  if (!trimmedQuery) return null;

  const stateTone = indexState.state === "ready" ? "green" : indexState.state === "error" ? "amber" : "muted";
  const groupedResults = groupSearchResults(results);
  let resultIndex = 0;

  return (
    <div id="global-search-results" className="absolute left-0 right-0 top-full z-40 mt-2 overflow-hidden rounded-lg border border-neutral-200 bg-white shadow-[0_18px_48px_rgba(15,23,42,0.14)]">
      <div className="flex items-center justify-between gap-3 border-b border-neutral-100 px-3 py-2">
        <div className="flex min-w-0 items-center gap-2">
          <Database className="h-3.5 w-3.5 text-blue-600" />
          <span className="truncate text-xs font-medium text-neutral-700">本地索引搜索 / Local index</span>
          <Badge tone={stateTone}>{indexState.message}</Badge>
        </div>
        <button className="shrink-0 rounded border border-neutral-200 px-2 py-1 text-[11px] text-neutral-600 hover:bg-neutral-50" onClick={onRebuild}>
          重建索引
        </button>
      </div>
      <div className="max-h-[420px] overflow-auto p-2">
        {searching ? (
          <div className="flex items-center gap-2 rounded-md px-3 py-4 text-sm text-neutral-500">
            <RefreshCw className="h-4 w-4 animate-spin" />
            正在搜索本地索引...
          </div>
        ) : results.length ? (
          <div className="grid gap-2">
            {groupedResults.map((group) => (
              <div key={group.id}>
                <div className="mono px-2 pb-1 pt-2 text-[10px] uppercase tracking-wide text-neutral-400">{group.label}</div>
                <div className="grid gap-1">
                  {group.results.map((result) => {
                    const currentIndex = resultIndex;
                    resultIndex += 1;
                    const active = currentIndex === selectedIndex;
                    return (
                      <button
                        id={`search-result-${currentIndex}`}
                        key={`${result.workspaceFolder}-${result.documentKey}-${result.documentPath}`}
                        onClick={() => onOpenResult(result)}
                        className={cn(
                          "grid w-full gap-1 rounded-md px-3 py-2.5 text-left transition-colors",
                          active ? "bg-blue-50 text-blue-950 ring-1 ring-blue-200" : "hover:bg-neutral-100"
                        )}
                        aria-selected={active}
                      >
                        <div className="flex min-w-0 items-center gap-2">
                          <Badge tone={result.kind === "sql" ? "amber" : result.kind === "workspace" ? "blue" : "muted"}>{searchKindLabel(result.kind)}</Badge>
                          <span className="min-w-0 truncate text-sm font-medium text-neutral-950">{result.workspaceName}</span>
                          <span className="mono shrink-0 text-[11px] text-neutral-400">{result.documentName}</span>
                        </div>
                        <div className="max-h-10 overflow-hidden text-xs leading-5 text-neutral-500">{result.snippet || result.documentPath}</div>
                      </button>
                    );
                  })}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <div className="rounded-md px-3 py-4 text-sm text-neutral-500">
            没有命中文档索引。卡片列表仍会按工作区元数据过滤。
          </div>
        )}
      </div>
      <div className="mono flex items-center justify-between gap-3 border-t border-neutral-100 px-3 py-2 text-[11px] text-neutral-400">
        <span>{indexState.documentCount !== undefined ? `${indexState.workspaceCount ?? 0} workspaces / ${indexState.documentCount} docs` : "preview fallback"}</span>
        <span>↑↓ 选择 · Enter 打开 · Esc 清空</span>
      </div>
    </div>
  );
}

function searchKindLabel(kind: string) {
  const labels: Record<string, string> = {
    workspace: "workspace",
    services: "services",
    tasks: "tasks",
    decisions: "decisions",
    delivery: "delivery",
    sql: "sql",
    status: "status",
    branches: "branch"
  };
  return labels[kind] ?? kind;
}

function searchIndexReadyState(rebuilt: RebuildSearchIndexResponse): SearchIndexState {
  return {
    state: "ready",
    message: "ready",
    path: rebuilt.path,
    workspaceCount: rebuilt.workspaceCount,
    documentCount: rebuilt.documentCount
  };
}

function WorkspaceCard({
  workspace,
  active,
  expanded,
  onFocus,
  onToggleDetails,
  onCopyCommand,
  onCopyInstruction,
  onCopyRiskInstruction,
  onCopyAndOpenCodex,
  onOpenDocument,
  onOpenDrawer
}: {
  workspace: Workspace;
  active: boolean;
  expanded: boolean;
  onFocus: () => void;
  onToggleDetails: () => void;
  onCopyCommand: () => void;
  onCopyInstruction: (action: "continue" | "git" | "delivery" | "risk" | "worktree") => void;
  onCopyRiskInstruction: (risk: string) => void;
  onCopyAndOpenCodex: (action: "continue" | "git" | "delivery" | "risk") => void;
  onOpenDocument: (title: string, path: string) => void;
  onOpenDrawer: () => void;
}) {
  const missing = workspace.gitRows.filter((row) => !row.worktree.exists).length;
  const dirty = workspace.gitRows.filter((row) => row.worktree.dirty).length;
  const branchMismatches = branchAlignmentRows(workspace);
  const serviceStatus = workspace.confirmedServices.length ? `${workspace.confirmedServices.length} 个已确认` : "待确认";
  const latestActivity = workspace.activities?.[0];

  return (
    <Card className={cn("overflow-hidden transition-colors hover:border-neutral-300", active && "border-blue-300")}>
      <div className="border-b border-neutral-200 p-4">
        <div className="flex items-start justify-between gap-4">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <h2 className="truncate text-base font-medium text-neutral-950">{workspace.name}</h2>
              <Badge tone={toneForRisk(workspace.riskCount)}>{workspace.riskCount ? `${workspace.riskCount} 风险` : "稳定 / Stable"}</Badge>
            </div>
            <div className="mono mt-1 truncate text-xs text-neutral-400">{workspace.folder}</div>
          </div>
          <Badge tone="muted">{stateLabels[workspace.state] ?? workspace.state}</Badge>
        </div>
      </div>

      <div className="grid gap-4 p-4">
        <div className="grid grid-cols-2 gap-2 xl:grid-cols-4">
          <StatusCell
            label="分支"
            subLabel="Branch"
            value={branchMismatches.length ? `${branchMismatches.length} 个不一致` : workspace.targetBranch}
            icon={GitBranch}
            tone={branchMismatches.length ? "warning" : "ok"}
          />
          <StatusCell label="服务" subLabel="Services" value={serviceStatus} icon={Boxes} />
          <StatusCell label="Worktree" subLabel="本地分支目录" value={missing ? `${missing} 个缺失` : "已就绪"} icon={Terminal} tone={missing ? "warning" : "ok"} />
          <StatusCell label="改动" subLabel="Changes" value={dirty ? `${dirty} 个未提交` : "干净"} icon={CheckCircle2} tone={dirty ? "warning" : "ok"} />
        </div>

        {branchMismatches.length > 0 && (
          <div className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2">
            <div className="flex items-center gap-2 text-xs font-medium text-amber-900">
              <GitBranch className="h-3.5 w-3.5" />
              分支一致性 / Branch alignment
            </div>
            <div className="mt-2 grid gap-1">
              {branchMismatches.slice(0, 3).map((row) => (
                <div key={row.service} className="mono flex min-w-0 items-center justify-between gap-2 text-[11px] text-amber-800">
                  <span className="truncate">{row.service}</span>
                  <span className="truncate">{`${row.actualBranch} -> ${row.expectedBranch}`}</span>
                </div>
              ))}
            </div>
          </div>
        )}

        <div className="flex flex-wrap gap-1.5">
          {workspace.confirmedServices.length ? (
            workspace.confirmedServices.map((service) => <Badge key={service}>{service}</Badge>)
          ) : (
            <Badge tone="amber">服务待确认 / Services pending</Badge>
          )}
          {workspace.candidateServices.slice(0, 3).map((service) => (
            <Badge key={service} tone="muted">
              {service}
            </Badge>
          ))}
        </div>

        <div className="grid gap-3 xl:grid-cols-[1fr_auto] xl:items-end">
          <div>
            <div className="mb-2 text-xs text-neutral-400">最近活动 / Recent activity</div>
            <div className="rounded-md bg-neutral-50 px-2 py-2 text-xs text-neutral-600">
              {latestActivity ? (
                <div className="grid gap-1">
                  <div className="mono truncate text-neutral-500">{latestActivity.time}</div>
                  <div className="truncate font-medium text-neutral-700">{latestActivity.title}</div>
                  <div className="truncate text-neutral-500">{latestActivity.detail}</div>
                </div>
              ) : (
                <div className="mono truncate">
                  更新 {workspace.updated} / 决策 {workspace.decisionCount} / 待办 {workspace.taskCounts.todo}
                </div>
              )}
            </div>
          </div>
          <div className="flex gap-2 xl:justify-end">
            <button className="text-xs text-blue-600 hover:text-blue-700" onClick={() => openPathInDesktop(workspace.links.folder)}>
              目录
            </button>
            <button className="text-xs text-blue-600 hover:text-blue-700" onClick={() => onOpenDocument("交付记录.md", workspace.links.delivery)}>
              交付
            </button>
          </div>
        </div>

        {workspace.risks.length > 0 && (
          <div className="grid gap-1">
            {workspace.risks.slice(0, 3).map((risk) => (
              <div key={risk} className="grid gap-2 rounded-md bg-amber-50 px-2 py-1.5 text-xs text-amber-800 md:grid-cols-[1fr_auto] md:items-center">
                <div className="flex min-w-0 items-center gap-2">
                  <AlertTriangle className="h-3.5 w-3.5 shrink-0" />
                  <span className="truncate">{risk}</span>
                </div>
                <div className="flex gap-1">
                  <button className="rounded border border-amber-200 bg-white px-2 py-1 text-[11px] text-amber-800 hover:bg-amber-100" onClick={() => onCopyRiskInstruction(risk)}>
                    复制处理指令
                  </button>
                  {risk.includes("服务范围") && (
                    <button className="rounded border border-amber-200 bg-white px-2 py-1 text-[11px] text-amber-800 hover:bg-amber-100" onClick={() => onOpenDocument("services.md", workspace.links.services)}>
                      服务文档
                    </button>
                  )}
                  {risk.includes("目标分支") && (
                    <button className="rounded border border-amber-200 bg-white px-2 py-1 text-[11px] text-amber-800 hover:bg-amber-100" onClick={() => onOpenDocument("branches.md", workspace.links.branches)}>
                      分支文档
                    </button>
                  )}
                  {risk.includes("分支不一致") && (
                    <button className="rounded border border-amber-200 bg-white px-2 py-1 text-[11px] text-amber-800 hover:bg-amber-100" onClick={() => onOpenDocument("branches.md", workspace.links.branches)}>
                      分支文档
                    </button>
                  )}
                  {risk.includes("worktree") && workspace.links.worktreeScript && (
                    <button className="rounded border border-amber-200 bg-white px-2 py-1 text-[11px] text-amber-800 hover:bg-amber-100" onClick={() => onOpenDocument("worktree-commands.sh", workspace.links.worktreeScript)}>
                      worktree 脚本
                    </button>
                  )}
                </div>
              </div>
            ))}
          </div>
        )}

        <div className="flex flex-wrap items-center gap-2 border-t border-neutral-100 pt-3">
          <button className="rounded-md border border-neutral-200 px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50" onClick={onOpenDrawer}>
            打开详情抽屉
          </button>
          <button className="rounded-md border border-neutral-200 px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50" onClick={onFocus}>
            设为焦点 / Focus
          </button>
          <button className="rounded-md border border-neutral-200 px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50" onClick={onToggleDetails}>
            <span className="inline-flex items-center gap-1">
              {expanded ? "收起详情" : "展开详情"} / Details
              <ChevronDown className={cn("h-3.5 w-3.5 transition-transform", expanded && "rotate-180")} />
            </span>
          </button>
          <button className="rounded-md border border-neutral-200 px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50" onClick={onCopyCommand}>
            复制 worktree 命令
          </button>
          {workspace.links.worktreeScript && (
            <button className="rounded-md border border-neutral-200 px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50" onClick={() => onOpenDocument("worktree-commands.sh", workspace.links.worktreeScript)}>
              worktree 脚本
            </button>
          )}
          {workspace.links.bootstrap && (
            <button className="rounded-md border border-neutral-200 px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50" onClick={() => onOpenDocument("bootstrap-report.md", workspace.links.bootstrap)}>
              状态报告
            </button>
          )}
          <button className="rounded-md border border-neutral-200 px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50" onClick={() => onCopyInstruction("continue")}>
            复制续做指令
          </button>
          <button className="rounded-md border border-neutral-200 px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50" onClick={() => onCopyInstruction("risk")}>
            复制风险分析指令
          </button>
          <button className="rounded-md border border-blue-200 bg-blue-50 px-2.5 py-1.5 text-xs text-blue-700 hover:bg-blue-100" onClick={() => onCopyAndOpenCodex("continue")}>
            复制续做并打开 Codex
          </button>
          <button className="rounded-md border border-neutral-200 px-2.5 py-1.5 text-xs text-neutral-700 hover:bg-neutral-50" onClick={() => onOpenDocument("tasks.md", workspace.links.tasks)}>
            任务文档
          </button>
        </div>

        {expanded && (
          <div className="rounded-lg border border-neutral-200 bg-neutral-50 p-3">
            <div className="mb-2 text-xs font-medium text-neutral-800">服务与 Git 状态 / Service git status</div>
            {workspace.gitRows.length ? (
              <div className="grid gap-2">
                {workspace.gitRows.map((row) => (
                  <div key={row.service} className="grid gap-2 rounded-md bg-white p-2 text-xs md:grid-cols-[120px_1fr_1fr]">
                    <div className="font-medium text-neutral-900">
                      {row.service}
                      {branchMismatches.some((item) => item.service === row.service) && (
                        <Badge tone="amber" className="mt-1">branch</Badge>
                      )}
                    </div>
                    <div>
                      <div className="text-neutral-400">工作区 worktree</div>
                      <div className="mono mt-1 text-neutral-700">{row.worktree.branch}</div>
                      <div className="mt-1 text-neutral-500">{row.worktree.summary}</div>
                    </div>
                    <div>
                      <div className="text-neutral-400">源仓库 source</div>
                      <div className="mono mt-1 text-neutral-700">{row.source.branch}</div>
                      <div className="mt-1 text-neutral-500">{row.source.summary}</div>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="rounded-md bg-white p-2 text-xs text-neutral-500">还没有确认服务范围，确认后这里会展示每个服务的 worktree 与源仓库状态。</div>
            )}
            <div className="mono mt-3 rounded-md bg-white p-2 text-[11px] text-neutral-500">{workspace.worktreeCommand}</div>
          </div>
        )}
      </div>
    </Card>
  );
}

function StatusCell({
  label,
  subLabel,
  value,
  icon: Icon,
  tone = "default"
}: {
  label: string;
  subLabel: string;
  value: string;
  icon: LucideIcon;
  tone?: "default" | "ok" | "warning";
}) {
  return (
    <div className="rounded-md border border-neutral-200 bg-white p-2">
      <div className="flex items-center justify-between text-neutral-400">
        <span className="text-[11px]">{label}</span>
        <Icon className={cn("h-3.5 w-3.5", tone === "ok" && "text-emerald-600", tone === "warning" && "text-amber-600")} />
      </div>
      <div className="mono mt-1 text-[10px] uppercase tracking-wide text-neutral-400">{subLabel}</div>
      <div className="mono mt-2 truncate text-xs text-neutral-700">{value}</div>
    </div>
  );
}

type CommandAction = {
  id: string;
  label: string;
  hint: string;
  icon: LucideIcon;
  run: () => void;
};

function CommandPalette({
  open,
  onOpenChange,
  current,
  setFilter,
  refreshData,
  rebuildSearchIndex,
  onOpenCodex
}: {
  open: boolean;
  onOpenChange: (open: boolean) => void;
  current?: Workspace;
  setFilter: (filter: string) => void;
  refreshData: () => void;
  rebuildSearchIndex: () => void;
  onOpenCodex: () => void;
}) {
  const [commandQuery, setCommandQuery] = useState("");

  useEffect(() => {
    if (!open) return;
    const onKeyDown = (event: KeyboardEvent) => {
      if (event.key === "Escape") onOpenChange(false);
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, [onOpenChange, open]);

  if (!open) return null;

  const openPath = (path?: string) => {
    if (!path) return;
    void openPathInDesktop(path);
    onOpenChange(false);
  };
  const copy = async (text?: string) => {
    if (!text) return;
    await navigator.clipboard.writeText(text);
    onOpenChange(false);
  };

  const actions: CommandAction[] = [
    {
      id: "refresh",
      label: "刷新工作区数据",
      hint: "Refresh workspace JSON",
      icon: RefreshCw,
      run: () => {
        refreshData();
        onOpenChange(false);
      }
    },
    {
      id: "rebuild-index",
      label: "重建本地搜索索引",
      hint: "Rebuild SQLite + FTS",
      icon: Database,
      run: () => {
        rebuildSearchIndex();
        onOpenChange(false);
      }
    },
    {
      id: "risk",
      label: "只看有风险工作区",
      hint: "Show risk workspaces",
      icon: AlertTriangle,
      run: () => {
        setFilter("risk");
        onOpenChange(false);
      }
    },
    {
      id: "dirty",
      label: "只看有未提交改动",
      hint: "Show dirty worktrees",
      icon: GitCommit,
      run: () => {
        setFilter("dirty");
        onOpenChange(false);
      }
    },
    {
      id: "branch",
      label: "只看分支不一致",
      hint: "Show branch mismatches",
      icon: GitBranch,
      run: () => {
        setFilter("branch");
        onOpenChange(false);
      }
    },
    {
      id: "folder",
      label: "打开当前工作区目录",
      hint: current?.folder ?? "No workspace selected",
      icon: ExternalLink,
      run: () => openPath(current?.links.folder)
    },
    {
      id: "delivery",
      label: "打开交付记录",
      hint: "交付记录.md",
      icon: FileText,
      run: () => openPath(current?.links.delivery)
    },
    {
      id: "copy-worktree",
      label: "复制 worktree 创建命令",
      hint: "Create workspace-local repos",
      icon: Clipboard,
      run: () => copy(current?.worktreeCommand)
    },
    {
      id: "open-codex",
      label: "打开 Codex",
      hint: "Open Codex app",
      icon: Sparkles,
      run: () => {
        onOpenCodex();
        onOpenChange(false);
      }
    }
  ];
  const visible = actions.filter((action) => {
    const haystack = `${action.label} ${action.hint}`.toLowerCase();
    return haystack.includes(commandQuery.trim().toLowerCase());
  });

  return (
    <div className="fixed inset-0 z-50 bg-neutral-950/15 p-[12vh_24px]" onMouseDown={() => onOpenChange(false)}>
      <div className="mx-auto max-w-2xl overflow-hidden rounded-lg border border-neutral-200 bg-white shadow-[0_18px_48px_rgba(15,23,42,0.14)]" onMouseDown={(event) => event.stopPropagation()}>
        <div className="flex items-center gap-2 border-b border-neutral-200 px-3 py-3">
          <Command className="h-4 w-4 text-blue-600" />
          <input
            autoFocus
            value={commandQuery}
            onChange={(event) => setCommandQuery(event.target.value)}
            placeholder="输入命令 / Run command..."
            className="h-8 flex-1 bg-transparent text-sm text-neutral-950 outline-none placeholder:text-neutral-400"
          />
          <Badge tone="muted">esc</Badge>
        </div>
        <div className="max-h-[420px] overflow-auto p-2">
          {visible.map((action) => (
            <button
              key={action.id}
              onClick={action.run}
              className="flex w-full items-center gap-3 rounded-md px-3 py-2.5 text-left transition-colors hover:bg-neutral-100"
            >
              <span className="flex h-8 w-8 items-center justify-center rounded-md bg-neutral-100 text-neutral-600">
                <action.icon className="h-4 w-4" />
              </span>
              <span className="min-w-0 flex-1">
                <span className="block text-sm text-neutral-950">{action.label}</span>
                <span className="mono block truncate text-[11px] text-neutral-400">{action.hint}</span>
              </span>
            </button>
          ))}
        </div>
      </div>
    </div>
  );
}

function RightRail({ current, visible }: { current?: Workspace; visible: Workspace[] }) {
  const alerts = visible.flatMap((workspace) => workspace.risks.map((risk) => ({ workspace: workspace.name, risk }))).slice(0, 8);
  const branchMismatches = current ? branchAlignmentRows(current).length : 0;
  const events = visible.slice(0, 6).map((workspace) => ({
    label: workspace.name,
    detail: workspace.riskCount ? `发现 ${workspace.riskCount} 个风险 / risks` : "扫描正常 / Clean"
  }));

  return (
    <aside className="hidden h-screen border-l border-neutral-200 bg-neutral-50 p-4 2xl:block">
      <section>
        <div className="mb-3 flex items-center gap-2 text-sm text-neutral-900">
          <Activity className="h-4 w-4 text-blue-600" />
          实时日志 / Live log
        </div>
        <div className="grid gap-2">
          {events.map((event) => (
            <div key={event.label} className="rounded-md bg-white px-3 py-2">
              <div className="truncate text-xs text-neutral-700">{event.label}</div>
              <div className="mono mt-1 text-[11px] text-neutral-400">{event.detail}</div>
            </div>
          ))}
        </div>
      </section>

      <section className="mt-6">
        <div className="mb-3 flex items-center gap-2 text-sm text-neutral-900">
          <Sparkles className="h-4 w-4 text-blue-600" />
          AI 判断 / Reasoning
        </div>
        <div className="rounded-lg border border-neutral-200 bg-white p-3 text-sm leading-6 text-neutral-600">
          {current ? (
            <>
              当前焦点是 <span className="text-neutral-950">{current.name}</span>。
              {branchMismatches ? `有 ${branchMismatches} 个服务 worktree 分支与目标分支不一致，应先校准分支。` : "优先处理分支确认、worktree 缺失和交付文档完整性。"}
            </>
          ) : (
            "选择一个 workspace 查看分析上下文。"
          )}
        </div>
      </section>

      <section className="mt-6">
        <div className="mb-3 flex items-center gap-2 text-sm text-neutral-900">
          <AlertTriangle className="h-4 w-4 text-amber-300" />
          风险告警 / Risk alerts
        </div>
        <div className="grid gap-2">
          {alerts.length ? (
            alerts.map((alert) => (
              <div key={`${alert.workspace}-${alert.risk}`} className="rounded-md border border-amber-200 bg-amber-50 px-3 py-2">
                <div className="truncate text-xs text-amber-800">{alert.risk}</div>
                <div className="mono mt-1 truncate text-[11px] text-amber-600">{alert.workspace}</div>
              </div>
            ))
          ) : (
            <div className="rounded-md bg-white px-3 py-2 text-xs text-neutral-500">暂无风险 / No active alerts</div>
          )}
        </div>
      </section>
    </aside>
  );
}

function WorkspaceDrawer({
  workspace,
  onClose,
  onCopyInstruction,
  onCopyRiskInstruction,
  onCopyAndOpenCodex,
  onOpenDocument
}: {
  workspace?: Workspace;
  onClose: () => void;
  onCopyInstruction: (workspace: Workspace, action: "continue" | "git" | "delivery" | "risk" | "worktree") => void;
  onCopyRiskInstruction: (workspace: Workspace, risk: string) => void;
  onCopyAndOpenCodex: (workspace: Workspace, action: "continue" | "git" | "delivery" | "risk") => void;
  onOpenDocument: (title: string, path: string) => void;
}) {
  if (!workspace) return null;

  const missing = workspace.gitRows.filter((row) => !row.worktree.exists).length;
  const dirty = workspace.gitRows.filter((row) => row.worktree.dirty).length;
  const branchMismatches = branchAlignmentRows(workspace);

  return (
    <div className="fixed inset-0 bg-neutral-950/10" style={{ zIndex: 1000 }} onMouseDown={onClose}>
      <aside
        className="fixed right-0 top-0 h-full w-full max-w-xl overflow-auto border-l border-neutral-200 bg-white shadow-[0_18px_48px_rgba(15,23,42,0.12)]"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="sticky top-0 z-10 border-b border-neutral-200 bg-white px-5 py-4">
          <div className="flex items-start justify-between gap-4">
            <div className="min-w-0">
              <div className="text-xs text-neutral-500">工作区详情 / Workspace detail</div>
              <h2 className="mt-1 truncate text-lg font-semibold text-neutral-950">{workspace.name}</h2>
              <div className="mono mt-1 truncate text-xs text-neutral-400">{workspace.folder}</div>
            </div>
            <button className="rounded-md border border-neutral-200 p-1.5 text-neutral-500 hover:bg-neutral-50" onClick={onClose}>
              <X className="h-4 w-4" />
            </button>
          </div>
        </div>

        <div className="grid gap-5 p-5">
          <section className="grid grid-cols-2 gap-3">
            <Stat label={{ title: "风险项", desc: "Risks" }} value={workspace.riskCount} icon={AlertTriangle} />
            <Stat label={{ title: "确认服务", desc: "Services" }} value={workspace.confirmedServices.length} icon={Boxes} />
            <Stat label={{ title: "缺 worktree", desc: "Missing" }} value={missing} icon={Terminal} />
            <Stat label={{ title: "未提交改动", desc: "Dirty" }} value={dirty} icon={GitCommit} />
            <Stat label={{ title: "分支不一致", desc: "Branch" }} value={branchMismatches.length} icon={GitBranch} />
          </section>

          {branchMismatches.length > 0 && (
            <section className="rounded-lg border border-amber-200 bg-amber-50 p-3">
              <div className="mb-2 flex items-center gap-2 text-sm font-medium text-amber-900">
                <GitBranch className="h-4 w-4" />
                分支一致性 / Branch alignment
              </div>
              <div className="grid gap-2">
                {branchMismatches.map((row) => (
                  <div key={row.service} className="rounded-md bg-white px-3 py-2 text-xs">
                    <div className="font-medium text-neutral-950">{row.service}</div>
                    <div className="mono mt-1 text-amber-800">worktree: {row.actualBranch}</div>
                    <div className="mono mt-1 text-neutral-500">target: {row.expectedBranch} / source: {row.sourceBranch || "unknown"}</div>
                  </div>
                ))}
              </div>
            </section>
          )}

          <section className="rounded-lg border border-neutral-200 bg-neutral-50 p-3">
            <div className="mb-3 flex items-center gap-2 text-sm font-medium text-neutral-900">
              <ListChecks className="h-4 w-4 text-blue-600" />
              下一步操作 / Next actions
            </div>
            <div className="grid gap-2">
              <button className="rounded-md border border-neutral-200 bg-white px-3 py-2 text-left text-sm text-neutral-700 hover:bg-neutral-50" onClick={() => onCopyInstruction(workspace, "continue")}>
                复制“继续这个工作区”指令
              </button>
              <button className="rounded-md border border-blue-200 bg-blue-50 px-3 py-2 text-left text-sm text-blue-700 hover:bg-blue-100" onClick={() => onCopyAndOpenCodex(workspace, "continue")}>
                复制“继续工作区”并打开 Codex
              </button>
              <button className="rounded-md border border-neutral-200 bg-white px-3 py-2 text-left text-sm text-neutral-700 hover:bg-neutral-50" onClick={() => onCopyInstruction(workspace, "git")}>
                复制“检查服务 Git 状态”指令
              </button>
              <button className="rounded-md border border-neutral-200 bg-white px-3 py-2 text-left text-sm text-neutral-700 hover:bg-neutral-50" onClick={() => onCopyInstruction(workspace, "delivery")}>
                复制“更新交付记录”指令
              </button>
              <button className="rounded-md border border-neutral-200 bg-white px-3 py-2 text-left text-sm text-neutral-700 hover:bg-neutral-50" onClick={() => onCopyInstruction(workspace, "worktree")}>
                复制 worktree 创建命令
              </button>
            </div>
          </section>

          <section>
            <div className="mb-2 text-sm font-medium text-neutral-900">文档入口 / Documents</div>
            <div className="grid grid-cols-2 gap-2 text-sm">
              {[
                ["状态", workspace.links.status],
                ["服务", workspace.links.services],
                ["分支", workspace.links.branches],
                ["任务", workspace.links.tasks],
                ["交付", workspace.links.delivery],
                ["报告", workspace.links.bootstrap],
                ["Worktree", workspace.links.worktreeScript],
                ["SQL", workspace.links.sql]
              ].filter(([, href]) => Boolean(href)).map(([label, href]) => (
                <button key={label} className="rounded-md border border-neutral-200 px-3 py-2 text-left text-neutral-700 hover:bg-neutral-50" onClick={() => onOpenDocument(`${label}.md`, href)}>
                  {label}
                </button>
              ))}
            </div>
          </section>

          <section>
            <div className="mb-2 text-sm font-medium text-neutral-900">风险动作 / Risk actions</div>
            {workspace.risks.length ? (
              <div className="grid gap-2">
                {workspace.risks.map((risk) => (
                  <div key={risk} className="rounded-md border border-amber-200 bg-amber-50 p-3">
                    <div className="text-sm text-amber-900">{risk}</div>
                    <div className="mt-2 flex flex-wrap gap-2">
                      <button className="rounded-md border border-amber-200 bg-white px-2 py-1 text-xs text-amber-800 hover:bg-amber-100" onClick={() => onCopyRiskInstruction(workspace, risk)}>
                        复制处理指令
                      </button>
                      {risk.includes("目标分支") && (
                        <button className="rounded-md border border-amber-200 bg-white px-2 py-1 text-xs text-amber-800 hover:bg-amber-100" onClick={() => onOpenDocument("branches.md", workspace.links.branches)}>
                          打开分支文档
                        </button>
                      )}
                      {risk.includes("分支不一致") && (
                        <button className="rounded-md border border-amber-200 bg-white px-2 py-1 text-xs text-amber-800 hover:bg-amber-100" onClick={() => onOpenDocument("branches.md", workspace.links.branches)}>
                          打开分支文档
                        </button>
                      )}
                      {risk.includes("服务范围") && (
                        <button className="rounded-md border border-amber-200 bg-white px-2 py-1 text-xs text-amber-800 hover:bg-amber-100" onClick={() => onOpenDocument("services.md", workspace.links.services)}>
                          打开服务文档
                        </button>
                      )}
                      {risk.includes("交付") && (
                        <button className="rounded-md border border-amber-200 bg-white px-2 py-1 text-xs text-amber-800 hover:bg-amber-100" onClick={() => onOpenDocument("交付记录.md", workspace.links.delivery)}>
                          打开交付记录
                        </button>
                      )}
                      {risk.includes("worktree") && workspace.links.worktreeScript && (
                        <button className="rounded-md border border-amber-200 bg-white px-2 py-1 text-xs text-amber-800 hover:bg-amber-100" onClick={() => onOpenDocument("worktree-commands.sh", workspace.links.worktreeScript)}>
                          打开 worktree 脚本
                        </button>
                      )}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="rounded-md border border-neutral-200 bg-neutral-50 p-3 text-sm text-neutral-500">暂无风险。</div>
            )}
          </section>

          <section>
            <div className="mb-2 text-sm font-medium text-neutral-900">服务 Git 状态 / Service git status</div>
            {workspace.gitRows.length ? (
              <div className="grid gap-2">
                {workspace.gitRows.map((row) => (
                  <div key={row.service} className="rounded-md border border-neutral-200 p-3 text-sm">
                    <div className="flex items-center gap-2 font-medium text-neutral-950">
                      {row.service}
                      {branchMismatches.some((item) => item.service === row.service) && <Badge tone="amber">branch mismatch</Badge>}
                    </div>
                    <div className="mt-2 grid gap-2 text-xs text-neutral-600">
                      <div>
                        <span className="text-neutral-400">worktree</span>
                        <div className="mono mt-1">{row.worktree.branch} / {row.worktree.summary}</div>
                      </div>
                      <div>
                        <span className="text-neutral-400">source</span>
                        <div className="mono mt-1">{row.source.branch} / {row.source.summary}</div>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="rounded-md border border-neutral-200 bg-neutral-50 p-3 text-sm text-neutral-500">尚未确认服务范围。</div>
            )}
          </section>
        </div>
      </aside>
    </div>
  );
}

function EnvironmentHealthPanel({
  health,
  compact = false,
  onRefresh
}: {
  health?: EnvironmentHealth;
  compact?: boolean;
  onRefresh: () => void;
}) {
  const ready = health?.ready ?? false;
  const blockers = health?.blockers.length ?? 0;
  const warnings = health?.warnings.length ?? 0;

  return (
    <Card className={cn("p-4", compact && "p-3")}>
      <div className="flex items-start justify-between gap-4">
        <div>
          <div className="flex items-center gap-2">
            {ready ? <CheckCircle2 className="h-4 w-4 text-emerald-600" /> : <AlertTriangle className="h-4 w-4 text-amber-600" />}
            <div className="text-sm font-medium text-neutral-950">环境健康检查 / Environment</div>
          </div>
          <p className="mt-1 text-sm leading-6 text-neutral-500">
            {ready ? "本机路径和基础工具可用，可以继续创建或推进工作区。" : "存在需要处理的路径或工具问题，建议先修复再创建工作区。"}
          </p>
        </div>
        <Button variant="outline" onClick={onRefresh}>
          <RefreshCw className="h-4 w-4" />
          检查
        </Button>
      </div>

      <div className={cn("mt-3 grid gap-2", compact ? "grid-cols-1" : "md:grid-cols-3")}>
        {(health?.pathChecks ?? []).map((check) => (
          <div key={check.key} className="rounded-md bg-neutral-50 px-3 py-2 ring-1 ring-neutral-200">
            <div className="flex items-center justify-between gap-2">
              <div className="text-xs font-medium text-neutral-700">{check.label}</div>
              <Badge tone={!check.exists || !check.isDir ? "red" : check.writable ? "green" : "amber"}>
                {!check.exists ? "missing" : check.writable ? "ok" : "check"}
              </Badge>
            </div>
            <div className="mono mt-1 truncate text-[11px] text-neutral-500">{check.path}</div>
            <div className="mt-1 text-xs text-neutral-500">{check.summary}</div>
          </div>
        ))}
      </div>

      <div className={cn("mt-3 grid gap-2", compact ? "grid-cols-2" : "sm:grid-cols-4")}>
        <div className="rounded-md bg-white px-3 py-2 ring-1 ring-neutral-200">
          <div className="text-xs text-neutral-400">工作区</div>
          <div className="mono mt-1 text-lg text-neutral-950">{health?.workspaceCount ?? 0}</div>
        </div>
        <div className="rounded-md bg-white px-3 py-2 ring-1 ring-neutral-200">
          <div className="text-xs text-neutral-400">服务仓库</div>
          <div className="mono mt-1 text-lg text-neutral-950">{health?.sourceRepoCount ?? 0}</div>
        </div>
        <div className="rounded-md bg-white px-3 py-2 ring-1 ring-neutral-200">
          <div className="text-xs text-neutral-400">阻塞</div>
          <div className="mono mt-1 text-lg text-neutral-950">{blockers}</div>
        </div>
        <div className="rounded-md bg-white px-3 py-2 ring-1 ring-neutral-200">
          <div className="text-xs text-neutral-400">提示</div>
          <div className="mono mt-1 text-lg text-neutral-950">{warnings}</div>
        </div>
      </div>

      {(health?.blockers.length || health?.warnings.length) ? (
        <div className="mt-3 grid gap-1 text-xs">
          {health.blockers.map((item) => (
            <div key={item} className="rounded-md bg-red-50 px-2 py-1.5 text-red-700">{item}</div>
          ))}
          {health.warnings.map((item) => (
            <div key={item} className="rounded-md bg-amber-50 px-2 py-1.5 text-amber-700">{item}</div>
          ))}
        </div>
      ) : null}
    </Card>
  );
}

function SettingsPanel({
  open,
  settings,
  sourceRepos,
  environmentHealth,
  sourceScanning,
  onChange,
  onClose,
  onSave,
  onExportSettings,
  onImportSettings,
  onOpenPath,
  onScanSourceRepos,
  onCheckEnvironment
}: {
  open: boolean;
  settings: NexusSettings;
  sourceRepos: SourceRepo[];
  environmentHealth?: EnvironmentHealth;
  sourceScanning: boolean;
  onChange: (settings: NexusSettings) => void;
  onClose: () => void;
  onSave: () => void;
  onExportSettings: () => void;
  onImportSettings: (content: string) => void;
  onOpenPath: (path: string) => void;
  onScanSourceRepos: () => void;
  onCheckEnvironment: () => void;
}) {
  const importInputRef = useRef<HTMLInputElement>(null);

  if (!open) return null;

  const update = (key: keyof NexusSettings, value: string) => {
    onChange({
      ...settings,
      [key]: key === "refreshIntervalSeconds" ? Math.max(3, Number(value) || 10) : value
    });
  };

  const importFile = async (file?: File) => {
    if (!file) return;
    onImportSettings(await file.text());
    if (importInputRef.current) importInputRef.current.value = "";
  };

  return (
    <div className="fixed inset-0 z-50 bg-neutral-950/12 backdrop-blur-[2px]">
      <aside className="ml-auto flex h-full w-full max-w-[560px] flex-col border-l border-neutral-200 bg-white shadow-[0_24px_80px_rgba(15,23,42,0.16)]">
        <div className="flex items-start justify-between gap-4 border-b border-neutral-200 px-5 py-4">
          <div>
            <div className="flex items-center gap-2">
              <Settings className="h-4 w-4 text-blue-600" />
              <h2 className="text-lg font-semibold text-neutral-950">Nexus 设置</h2>
            </div>
            <p className="mt-1 text-sm leading-6 text-neutral-500">
              配置本机路径后，分享给其他人也可以用同一个应用读取自己的工作区、源仓库和交付文档目录。
            </p>
          </div>
          <Button variant="ghost" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>

        <div className="flex-1 overflow-y-auto px-5 py-5">
          <div className="grid gap-4">
            <Card className="p-4">
              <div className="text-sm font-medium text-neutral-950">路径 / Paths</div>
              <div className="mt-4 grid gap-4">
                <PathSetting
                  label="工作区目录"
                  desc="存放每个需求 workspace 的目录。"
                  value={settings.workspacesRoot}
                  onChange={(value) => update("workspacesRoot", value)}
                  onOpen={() => onOpenPath(settings.workspacesRoot)}
                />
                <PathSetting
                  label="源仓库目录"
                  desc="每个服务原始仓库所在目录，用于对比 source git 状态。"
                  value={settings.sourceReposRoot}
                  onChange={(value) => update("sourceReposRoot", value)}
                  onOpen={() => onOpenPath(settings.sourceReposRoot)}
                />
                <PathSetting
                  label="交付文档目录"
                  desc="跨需求归档文档目录；工作区内的交付记录仍跟随 workspace。"
                  value={settings.docsRoot}
                  onChange={(value) => update("docsRoot", value)}
                  onOpen={() => onOpenPath(settings.docsRoot)}
                />
              </div>
            </Card>

            <EnvironmentHealthPanel health={environmentHealth} onRefresh={onCheckEnvironment} />

            <Card className="p-4">
              <div className="text-sm font-medium text-neutral-950">应用行为 / Behavior</div>
              <div className="mt-4 grid gap-4">
                <label className="grid gap-2">
                  <span className="text-xs font-medium text-neutral-500">Codex URL Scheme</span>
                  <Input value={settings.codexUrl} onChange={(event) => update("codexUrl", event.target.value)} />
                </label>
                <label className="grid gap-2">
                  <span className="text-xs font-medium text-neutral-500">实时刷新间隔，秒</span>
                  <Input
                    type="number"
                    min={3}
                    value={settings.refreshIntervalSeconds}
                    onChange={(event) => update("refreshIntervalSeconds", event.target.value)}
                  />
                </label>
              </div>
            </Card>

            <Card className="p-4">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="text-sm font-medium text-neutral-950">团队配置 / Team profile</div>
                  <p className="mt-2 text-sm leading-6 text-neutral-500">
                    导出一份不包含工作区内容的 JSON 配置，只保存路径约定、Codex URL 和刷新间隔；导入后会保存为本机配置。
                  </p>
                </div>
              </div>
              <div className="mt-3 grid gap-2 sm:grid-cols-2">
                <Button variant="outline" onClick={onExportSettings}>
                  <Download className="h-4 w-4" />
                  导出配置
                </Button>
                <Button variant="outline" onClick={() => importInputRef.current?.click()}>
                  <Upload className="h-4 w-4" />
                  导入配置
                </Button>
                <input
                  ref={importInputRef}
                  type="file"
                  accept="application/json,.json"
                  className="hidden"
                  onChange={(event) => void importFile(event.currentTarget.files?.[0])}
                />
              </div>
              <div className="mt-3 rounded-md bg-neutral-50 px-3 py-2 text-xs leading-5 text-neutral-500">
                分享给别人前建议把路径改成团队约定写法，例如 `~/ks_project/workspaces`，对方导入后仍可按自己的机器目录再调整。
              </div>
            </Card>

            <Card className="p-4">
              <div className="text-sm font-medium text-neutral-950">数据刷新 / Data refresh</div>
              <p className="mt-2 text-sm leading-6 text-neutral-500">
                Nexus 会在应用内直接扫描上述路径，不需要终端脚本。保存后点击顶部刷新按钮即可重新读取工作区。
              </p>
              <div className="mt-3 flex flex-wrap gap-2">
                <Button onClick={onSave}>保存本机配置</Button>
                <Button variant="outline" onClick={onScanSourceRepos} disabled={sourceScanning}>
                  <FolderOpen className="h-4 w-4" />
                  {sourceScanning ? "扫描中" : "扫描源仓库"}
                </Button>
              </div>
              <div className="mt-3 grid gap-2 text-xs text-neutral-500">
                <div className="flex items-center justify-between rounded-md bg-neutral-50 px-3 py-2">
                  <span>已识别服务仓库</span>
                  <span className="mono text-neutral-700">{sourceRepos.length}</span>
                </div>
                {sourceRepos.slice(0, 4).map((repo) => (
                  <div key={repo.path} className="flex min-w-0 items-center justify-between gap-3 rounded-md bg-white px-3 py-2 ring-1 ring-neutral-200">
                    <span className="truncate text-neutral-700">{repo.name}</span>
                    <span className={cn("mono shrink-0", repo.dirty ? "text-amber-600" : "text-neutral-400")}>{repo.branch}</span>
                  </div>
                ))}
              </div>
            </Card>
          </div>
        </div>
      </aside>
    </div>
  );
}

function OnboardingPanel({
  open,
  settings,
  sourceRepos,
  environmentHealth,
  sourceScanning,
  onChange,
  onClose,
  onSave,
  onSkip,
  onOpenPath,
  onScanSourceRepos,
  onCheckEnvironment
}: {
  open: boolean;
  settings: NexusSettings;
  sourceRepos: SourceRepo[];
  environmentHealth?: EnvironmentHealth;
  sourceScanning: boolean;
  onChange: (settings: NexusSettings) => void;
  onClose: () => void;
  onSave: () => void;
  onSkip: () => void;
  onOpenPath: (path: string) => void;
  onScanSourceRepos: () => void;
  onCheckEnvironment: () => void;
}) {
  if (!open) return null;

  const update = (key: keyof NexusSettings, value: string) => {
    onChange({
      ...settings,
      [key]: key === "refreshIntervalSeconds" ? Math.max(3, Number(value) || 10) : value
    });
  };

  const steps = [
    { label: "配置路径", done: Boolean(settings.workspacesRoot && settings.sourceReposRoot && settings.docsRoot) },
    { label: "扫描服务", done: sourceRepos.length > 0 },
    { label: "创建工作区", done: false }
  ];

  return (
    <div className="fixed inset-0 z-[1200] flex items-center justify-center overflow-hidden overscroll-contain bg-neutral-950/16 px-4 backdrop-blur-[2px]">
      <section className="relative grid max-h-[92vh] w-full max-w-5xl grid-cols-1 overflow-hidden overscroll-contain rounded-xl border border-neutral-200 bg-white shadow-[0_24px_80px_rgba(15,23,42,0.16)] lg:grid-cols-[320px_minmax(0,1fr)]">
        <button
          className="absolute right-3 top-3 z-10 rounded-md border border-neutral-200 bg-white p-1.5 text-neutral-500 hover:bg-neutral-50"
          onClick={onClose}
          title="关闭初始化 / Close onboarding"
        >
          <X className="h-4 w-4" />
        </button>
        <div className="border-b border-neutral-200 bg-neutral-50 px-5 py-5 lg:border-b-0 lg:border-r">
          <div className="flex items-center gap-2">
            <Command className="h-4 w-4 text-blue-600" />
            <div className="text-sm font-semibold text-neutral-950">Nexus 初始化</div>
          </div>
          <h2 className="mt-5 text-2xl font-semibold tracking-tight text-neutral-950">连接你的本地开发目录</h2>
          <p className="mt-3 text-sm leading-6 text-neutral-500">
            首次启动只需要确认三个路径。保存后，Nexus 会用这些路径扫描工作区、识别服务仓库，并在新建需求时提供服务选择。
          </p>
          <div className="mt-6 grid gap-2">
            {steps.map((step, index) => (
              <div key={step.label} className="flex items-center gap-3 rounded-md bg-white px-3 py-2 ring-1 ring-neutral-200">
                <span className={cn("flex h-6 w-6 items-center justify-center rounded-md text-xs", step.done ? "bg-emerald-50 text-emerald-700" : "bg-neutral-100 text-neutral-500")}>
                  {step.done ? <Check className="h-3.5 w-3.5" /> : index + 1}
                </span>
                <span className="text-sm text-neutral-700">{step.label}</span>
              </div>
            ))}
          </div>
        </div>

        <div className="overflow-y-auto overscroll-contain px-5 py-5">
          <div className="grid gap-4">
            <Card className="p-4">
              <div className="text-sm font-medium text-neutral-950">本地路径</div>
              <div className="mt-4 grid gap-4">
                <PathSetting
                  label="工作区目录"
                  desc="每个需求 workspace 的根目录。"
                  value={settings.workspacesRoot}
                  onChange={(value) => update("workspacesRoot", value)}
                  onOpen={() => onOpenPath(settings.workspacesRoot)}
                />
                <PathSetting
                  label="源仓库目录"
                  desc="用于扫描服务列表和读取 source git 状态。"
                  value={settings.sourceReposRoot}
                  onChange={(value) => update("sourceReposRoot", value)}
                  onOpen={() => onOpenPath(settings.sourceReposRoot)}
                />
                <PathSetting
                  label="交付文档目录"
                  desc="跨需求交付资料归档目录。"
                  value={settings.docsRoot}
                  onChange={(value) => update("docsRoot", value)}
                  onOpen={() => onOpenPath(settings.docsRoot)}
                />
              </div>
            </Card>

            <EnvironmentHealthPanel health={environmentHealth} compact onRefresh={onCheckEnvironment} />

            <Card className="p-4">
              <div className="flex items-start justify-between gap-4">
                <div>
                  <div className="text-sm font-medium text-neutral-950">服务仓库扫描</div>
                  <p className="mt-1 text-sm leading-6 text-neutral-500">扫描结果会出现在新建工作区面板中，可以直接勾选涉及服务。</p>
                </div>
                <Button variant="outline" onClick={onScanSourceRepos} disabled={sourceScanning}>
                  <FolderOpen className="h-4 w-4" />
                  {sourceScanning ? "扫描中" : "扫描"}
                </Button>
              </div>
              <div className="mt-3 grid grid-cols-1 gap-2 sm:grid-cols-2">
                <div className="rounded-md bg-neutral-50 px-3 py-2">
                  <div className="text-xs text-neutral-400">识别数量</div>
                  <div className="mono mt-1 text-lg text-neutral-950">{sourceRepos.length}</div>
                </div>
                <div className="rounded-md bg-neutral-50 px-3 py-2">
                  <div className="text-xs text-neutral-400">源仓库目录</div>
                  <div className="mono mt-1 truncate text-xs text-neutral-700">{settings.sourceReposRoot}</div>
                </div>
              </div>
            </Card>
          </div>

          <div className="mt-5 flex flex-wrap justify-end gap-2 border-t border-neutral-200 pt-4">
            <Button variant="ghost" onClick={onSkip}>稍后设置</Button>
            <Button variant="outline" onClick={onScanSourceRepos} disabled={sourceScanning}>先扫描服务</Button>
            <Button onClick={onSave}>保存并开始</Button>
          </div>
        </div>
      </section>
    </div>
  );
}

function PathSetting({
  label,
  desc,
  value,
  onChange,
  onOpen
}: {
  label: string;
  desc: string;
  value: string;
  onChange: (value: string) => void;
  onOpen: () => void;
}) {
  return (
    <label className="grid gap-2">
      <span className="flex items-center justify-between gap-3">
        <span>
          <span className="block text-xs font-medium text-neutral-500">{label}</span>
          <span className="mt-1 block text-xs text-neutral-400">{desc}</span>
        </span>
        <Button type="button" variant="ghost" className="shrink-0" onClick={onOpen}>
          打开
          <ExternalLink className="h-3.5 w-3.5" />
        </Button>
      </span>
      <Input value={value} onChange={(event) => onChange(event.target.value)} />
    </label>
  );
}

function isMarkdownDocument(path: string) {
  return /\.(md|markdown|mdown|mkdn)$/i.test(path.trim());
}

function MarkdownDocument({ content }: { content: string }) {
  if (!content.trim()) {
    return <div className="rounded-lg border border-dashed border-neutral-200 bg-white p-6 text-sm text-neutral-500">文档为空。</div>;
  }

  return (
    <div className="rounded-lg border border-neutral-200 bg-white px-6 py-5 text-[15px] leading-7 text-neutral-800">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          h1: (props) => <h1 className="mb-4 border-b border-neutral-200 pb-3 text-2xl font-semibold leading-tight text-neutral-950" {...props} />,
          h2: (props) => <h2 className="mb-3 mt-7 text-xl font-semibold leading-tight text-neutral-950 first:mt-0" {...props} />,
          h3: (props) => <h3 className="mb-2 mt-5 text-base font-semibold leading-tight text-neutral-950" {...props} />,
          h4: (props) => <h4 className="mb-2 mt-4 text-sm font-semibold leading-tight text-neutral-900" {...props} />,
          p: (props) => <p className="my-3 text-neutral-700" {...props} />,
          ul: (props) => <ul className="my-3 list-disc space-y-1 pl-5" {...props} />,
          ol: (props) => <ol className="my-3 list-decimal space-y-1 pl-5" {...props} />,
          li: (props) => <li className="pl-1 marker:text-neutral-400" {...props} />,
          blockquote: (props) => <blockquote className="my-4 border-l-2 border-blue-300 bg-blue-50/60 px-4 py-2 text-neutral-700" {...props} />,
          hr: (props) => <hr className="my-6 border-neutral-200" {...props} />,
          a: (props) => <a className="font-medium text-blue-700 underline decoration-blue-200 underline-offset-4 hover:text-blue-800" target="_blank" rel="noreferrer" {...props} />,
          strong: (props) => <strong className="font-semibold text-neutral-950" {...props} />,
          code: ({ children, className, ...props }) => {
            const text = String(children);
            const isBlock = text.includes("\n") || className;
            if (!isBlock) {
              return <code className="mono rounded bg-neutral-100 px-1.5 py-0.5 text-[0.92em] text-neutral-900" {...props}>{children}</code>;
            }
            return <code className={cn("mono text-[13px] leading-6 text-neutral-800", className)} {...props}>{children}</code>;
          },
          pre: (props) => <pre className="mono my-4 overflow-x-auto rounded-lg border border-neutral-200 bg-neutral-50 p-4 text-[13px] leading-6 text-neutral-800" {...props} />,
          table: (props) => (
            <div className="my-4 overflow-x-auto rounded-lg border border-neutral-200">
              <table className="w-full border-collapse bg-white text-sm" {...props} />
            </div>
          ),
          th: (props) => <th className="border-b border-neutral-200 bg-neutral-50 px-3 py-2 text-left font-semibold text-neutral-900" {...props} />,
          td: (props) => <td className="border-b border-neutral-100 px-3 py-2 align-top text-neutral-700 last:border-b-0" {...props} />,
          input: (props) => <input className="mr-2 align-middle accent-blue-600" disabled {...props} />
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  );
}

function DocumentViewer({
  document,
  onClose,
  onOpenExternal
}: {
  document?: { title: string; path: string; content: string };
  onClose: () => void;
  onOpenExternal: (path: string) => void;
}) {
  const markdown = Boolean(document && isMarkdownDocument(document.path));
  const [mode, setMode] = useState<"preview" | "source">("preview");

  useEffect(() => {
    if (!document) return;
    setMode(isMarkdownDocument(document.path) ? "preview" : "source");
  }, [document?.path]);

  if (!document) return null;

  return (
    <div className="fixed inset-0 bg-neutral-950/18 backdrop-blur-[3px]" style={{ zIndex: 1300 }} onMouseDown={onClose}>
      <aside
        className="ml-auto flex h-full w-full max-w-4xl flex-col border-l border-neutral-200 bg-white shadow-[0_24px_80px_rgba(15,23,42,0.18)]"
        onMouseDown={(event) => event.stopPropagation()}
      >
        <div className="flex items-start justify-between gap-4 border-b border-neutral-200 px-5 py-4">
          <div className="min-w-0">
            <div className="flex items-center gap-2">
              <FileText className="h-4 w-4 text-blue-600" />
              <h2 className="truncate text-lg font-semibold text-neutral-950">{document.title}</h2>
            </div>
            <div className="mono mt-1 truncate text-xs text-neutral-400">{document.path}</div>
          </div>
          <div className="flex shrink-0 gap-2">
            {markdown && (
              <div className="flex rounded-md border border-neutral-200 bg-neutral-50 p-0.5">
                <button
                  className={cn("inline-flex h-8 items-center gap-1.5 rounded px-2.5 text-xs transition-colors", mode === "preview" ? "bg-white text-neutral-950 shadow-sm" : "text-neutral-500 hover:text-neutral-900")}
                  onClick={() => setMode("preview")}
                >
                  <BookOpen className="h-3.5 w-3.5" />
                  预览
                </button>
                <button
                  className={cn("inline-flex h-8 items-center gap-1.5 rounded px-2.5 text-xs transition-colors", mode === "source" ? "bg-white text-neutral-950 shadow-sm" : "text-neutral-500 hover:text-neutral-900")}
                  onClick={() => setMode("source")}
                >
                  <Braces className="h-3.5 w-3.5" />
                  原文
                </button>
              </div>
            )}
            <Button variant="outline" onClick={() => onOpenExternal(document.path)}>
              <ExternalLink className="h-4 w-4" />
              系统打开
            </Button>
            <Button variant="ghost" onClick={onClose}>
              <X className="h-4 w-4" />
            </Button>
          </div>
        </div>
        <div className="flex-1 overflow-auto overscroll-contain bg-neutral-50 p-5">
          {markdown && mode === "preview" ? (
            <MarkdownDocument content={document.content} />
          ) : (
            <pre className="mono min-h-full whitespace-pre-wrap break-words rounded-lg border border-neutral-200 bg-white p-4 text-sm leading-6 text-neutral-800">
              {document.content || "文档为空。"}
            </pre>
          )}
        </div>
      </aside>
    </div>
  );
}

function CreateWorkspacePanel({
  open,
  settings,
  sourceRepos,
  sourceScanning,
  onClose,
  onCreate,
  onScanSourceRepos
}: {
  open: boolean;
  settings: NexusSettings;
  sourceRepos: SourceRepo[];
  sourceScanning: boolean;
  onClose: () => void;
  onCreate: (input: { name: string; folder: string; services: string[]; targetBranch: string; confirmed: boolean }) => void;
  onScanSourceRepos: () => void;
}) {
  const [name, setName] = useState("");
  const [servicesText, setServicesText] = useState("");
  const [serviceQuery, setServiceQuery] = useState("");
  const [selectedServices, setSelectedServices] = useState<string[]>([]);
  const [targetBranch, setTargetBranch] = useState("");
  const [confirmed, setConfirmed] = useState(false);
  const folder = workspaceFolderFromName(name);
  if (!open) return null;

  const manualServices = parseServiceInput(servicesText);
  const services = normalizeServiceList([...selectedServices, ...manualServices]);
  const serviceMatches = sourceRepos
    .filter((repo) => repo.name.toLowerCase().includes(serviceQuery.trim().toLowerCase()))
    .slice(0, 16);
  const toggleService = (service: string) => {
    setSelectedServices((current) => {
      if (current.includes(service)) return current.filter((item) => item !== service);
      return normalizeServiceList([...current, service]);
    });
  };

  return (
    <div className="fixed inset-0 z-50 bg-neutral-950/12 backdrop-blur-[2px]">
      <aside className="ml-auto flex h-full w-full max-w-[560px] flex-col border-l border-neutral-200 bg-white shadow-[0_24px_80px_rgba(15,23,42,0.16)]">
        <div className="flex items-start justify-between gap-4 border-b border-neutral-200 px-5 py-4">
          <div>
            <div className="flex items-center gap-2">
              <Plus className="h-4 w-4 text-blue-600" />
              <h2 className="text-lg font-semibold text-neutral-950">新建工作区</h2>
            </div>
            <p className="mt-1 text-sm leading-6 text-neutral-500">
              按 `ks-project-demand-workspace` skill 的标准结构创建需求目录、交付记录、任务、分支和服务文档。
            </p>
          </div>
          <Button variant="ghost" onClick={onClose}>
            <X className="h-4 w-4" />
          </Button>
        </div>
        <div className="flex-1 overflow-y-auto px-5 py-5">
          <div className="grid gap-4">
            <Card className="p-4">
              <div className="grid gap-4">
                <label className="grid gap-2">
                  <span className="text-xs font-medium text-neutral-500">需求名称</span>
                  <Input value={name} onChange={(event) => setName(event.target.value)} placeholder="例如：支付对账补充 pay_log" />
                </label>
                <label className="grid gap-2">
                  <span className="text-xs font-medium text-neutral-500">工作区目录名</span>
                  <Input value={folder} readOnly />
                </label>
                <div className="grid gap-3">
                  <div className="flex items-center justify-between gap-3">
                    <div>
                      <div className="text-xs font-medium text-neutral-500">涉及服务，可选</div>
                      <div className="mt-1 text-xs text-neutral-400">从源仓库扫描结果勾选，也可以手动补充。</div>
                    </div>
                    <Button type="button" variant="outline" onClick={onScanSourceRepos} disabled={sourceScanning}>
                      <Search className="h-4 w-4" />
                      {sourceScanning ? "扫描中" : "扫描"}
                    </Button>
                  </div>
                  <Input value={serviceQuery} onChange={(event) => setServiceQuery(event.target.value)} placeholder="搜索服务仓库" />
                  <div className="max-h-48 overflow-auto rounded-md border border-neutral-200 bg-neutral-50 p-1">
                    {serviceMatches.length ? (
                      serviceMatches.map((repo) => {
                        const selected = selectedServices.includes(repo.name);
                        return (
                          <button
                            key={repo.path}
                            type="button"
                            className={cn(
                              "flex w-full items-center justify-between gap-3 rounded px-2 py-2 text-left text-sm transition-colors",
                              selected ? "bg-blue-50 text-blue-700" : "text-neutral-700 hover:bg-white"
                            )}
                            onClick={() => toggleService(repo.name)}
                          >
                            <span className="flex min-w-0 items-center gap-2">
                              <span className={cn("flex h-5 w-5 shrink-0 items-center justify-center rounded border", selected ? "border-blue-300 bg-blue-600 text-white" : "border-neutral-300 bg-white text-transparent")}>
                                <Check className="h-3.5 w-3.5" />
                              </span>
                              <span className="min-w-0">
                                <span className="block truncate font-medium">{repo.name}</span>
                                <span className="mono block truncate text-[11px] text-neutral-400">{repo.branch}</span>
                              </span>
                            </span>
                            <span className={cn("mono shrink-0 text-[11px]", repo.dirty ? "text-amber-600" : repo.isGit ? "text-emerald-600" : "text-neutral-400")}>
                              {repo.isGit ? (repo.dirty ? "dirty" : "clean") : "non-git"}
                            </span>
                          </button>
                        );
                      })
                    ) : (
                      <div className="grid place-items-center gap-2 px-3 py-6 text-center text-sm text-neutral-500">
                        <FolderOpen className="h-5 w-5 text-neutral-300" />
                        <div>{sourceRepos.length ? "没有匹配的服务" : "还没有扫描到源仓库服务"}</div>
                      </div>
                    )}
                  </div>
                  <Input value={servicesText} onChange={(event) => setServicesText(event.target.value)} placeholder="手动补充：order、store-cashier commodity" />
                  {services.length > 0 && (
                    <div className="flex flex-wrap gap-2">
                      {services.map((service) => (
                        <Badge key={service} tone="blue">{service}</Badge>
                      ))}
                    </div>
                  )}
                </div>
                <label className="grid gap-2">
                  <span className="text-xs font-medium text-neutral-500">目标分支，可选</span>
                  <Input value={targetBranch} onChange={(event) => setTargetBranch(event.target.value)} placeholder="chen/feature-name，留空则待确认" />
                </label>
              </div>
            </Card>
            <Card className="p-4 text-sm leading-6 text-neutral-600">
              <div className="font-medium text-neutral-950">创建位置</div>
              <div className="mono mt-2 break-all text-xs text-neutral-500">{settings.workspacesRoot}</div>
              <div className="mt-3 text-neutral-500">创建后不会自动创建 worktree；目标分支确认后再按工作区里的命令创建。</div>
            </Card>
            <label className="flex items-start gap-3 rounded-md border border-neutral-200 bg-white p-4 text-sm text-neutral-600">
              <input
                type="checkbox"
                checked={confirmed}
                onChange={(event) => setConfirmed(event.target.checked)}
                className="mt-1 h-4 w-4 rounded border-neutral-300 text-blue-600"
              />
              <span>
                <span className="block font-medium text-neutral-950">确认创建本地文件 / Confirm local write</span>
                <span className="mt-1 block leading-6">
                  Nexus 将在工作区目录下写入标准 Markdown、脚本、SQL 和日志目录，并记录一条本地审计日志。
                </span>
              </span>
            </label>
          </div>
        </div>
        <div className="flex justify-end gap-2 border-t border-neutral-200 px-5 py-4">
          <Button variant="ghost" onClick={onClose}>取消</Button>
          <Button disabled={!name.trim() || !confirmed} onClick={() => onCreate({ name: name.trim(), folder, services, targetBranch, confirmed })}>
            创建工作区
          </Button>
        </div>
      </aside>
    </div>
  );
}

export function App() {
  const [dashboard, setDashboard] = useState<DashboardData>(initialData);
  const [settings, setSettings] = useState<NexusSettings>(() => loadSettings(initialData));
  const [query, setQuery] = useState("");
  const [filter, setFilter] = useState("all");
  const [active, setActive] = useState(initialData.workspaces[0]?.folder ?? "");
  const [commandOpen, setCommandOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [onboardingRequested, setOnboardingRequested] = useState(() => shouldShowOnboarding());
  const [onboardingOpen, setOnboardingOpen] = useState(false);
  const [createOpen, setCreateOpen] = useState(false);
  const [refreshEnabled, setRefreshEnabled] = useState(true);
  const [expanded, setExpanded] = useState<Set<string>>(new Set());
  const [drawerFolder, setDrawerFolder] = useState("");
  const [document, setDocument] = useState<{ title: string; path: string; content: string }>();
  const [toast, setToast] = useState("");
  const [sourceRepos, setSourceRepos] = useState<SourceRepo[]>([]);
  const [sourceScanning, setSourceScanning] = useState(false);
  const [environmentHealth, setEnvironmentHealth] = useState<EnvironmentHealth>(() => browserEnvironmentFallback(settings, initialData, []));
  const [environmentChecking, setEnvironmentChecking] = useState(false);
  const [environmentChecked, setEnvironmentChecked] = useState(false);
  const [searchResults, setSearchResults] = useState<SearchResult[]>([]);
  const [searchSearching, setSearchSearching] = useState(false);
  const [selectedSearchIndex, setSelectedSearchIndex] = useState(0);
  const [searchIndexState, setSearchIndexState] = useState<SearchIndexState>({
    state: "idle",
    message: "not built"
  });
  const searchRequestRef = useRef(0);

  const showToast = useCallback((message: string) => {
    setToast(message);
    window.setTimeout(() => setToast(""), 1800);
  }, []);

  const refreshData = useCallback(async () => {
    const scanned = await scanWorkspaces({
      workspacesRoot: settings.workspacesRoot,
      sourceReposRoot: settings.sourceReposRoot,
      docsRoot: settings.docsRoot
    });
    if (scanned) {
      setDashboard(scanned as DashboardData);
      return;
    }

    const response = await fetch(`/data/workspaces.json?t=${Date.now()}`, { cache: "no-store" });
    if (!response.ok) return;
    setDashboard((await response.json()) as DashboardData);
  }, [settings.docsRoot, settings.sourceReposRoot, settings.workspacesRoot]);

  const refreshSourceRepos = useCallback(async () => {
    setSourceScanning(true);
    try {
      const scanned = await scanSourceRepos({ sourceReposRoot: settings.sourceReposRoot });
      if (scanned) {
        setSourceRepos(scanned);
        return scanned;
      }

      const fallbackServices = normalizeServiceList(dashboard.workspaces.flatMap((workspace) => workspace.confirmedServices));
      const fallbackRepos = fallbackServices.map((service) => ({
        name: service,
        path: `${settings.sourceReposRoot}/${service}`,
        isGit: false,
        branch: "browser preview",
        dirty: false,
        summary: "浏览器预览模式"
      }));
      setSourceRepos(fallbackRepos);
      return fallbackRepos;
    } finally {
      setSourceScanning(false);
    }
  }, [dashboard.workspaces, settings.sourceReposRoot]);

  const refreshEnvironmentHealth = useCallback(async () => {
    setEnvironmentChecking(true);
    try {
      const checked = await checkEnvironment({
        workspacesRoot: settings.workspacesRoot,
        sourceReposRoot: settings.sourceReposRoot,
        docsRoot: settings.docsRoot
      });
      if (checked) {
        setEnvironmentHealth(checked);
        return checked;
      }
      const fallback = browserEnvironmentFallback(settings, dashboard, sourceRepos);
      setEnvironmentHealth(fallback);
      return fallback;
    } finally {
      setEnvironmentChecked(true);
      setEnvironmentChecking(false);
    }
  }, [dashboard, settings, sourceRepos]);

  const refreshSearchIndex = useCallback(async (options: { showToast?: boolean } = {}) => {
    setSearchIndexState((currentState) => ({
      ...currentState,
      state: "building",
      message: "building"
    }));
    try {
      const rebuilt = await rebuildSearchIndex({
        workspacesRoot: settings.workspacesRoot,
        sourceReposRoot: settings.sourceReposRoot,
        docsRoot: settings.docsRoot
      });
      if (!rebuilt) {
        setSearchIndexState({
          state: "preview",
          message: "preview"
        });
        return null;
      }
      setSearchIndexState(searchIndexReadyState(rebuilt));
      if (options.showToast) showToast(`已重建索引：${rebuilt.documentCount} 份文档`);
      return rebuilt;
    } catch (error) {
      setSearchIndexState({
        state: "error",
        message: "index error"
      });
      if (options.showToast) showToast(error instanceof Error ? error.message : "索引重建失败");
      return null;
    }
  }, [settings.docsRoot, settings.sourceReposRoot, settings.workspacesRoot, showToast]);

  useEffect(() => {
    const hasModal = commandOpen || settingsOpen || onboardingOpen || createOpen || Boolean(drawerFolder) || Boolean(document);
    if (!hasModal) return;

    const previousBodyOverflow = window.document.body.style.overflow;
    const previousHtmlOverscroll = window.document.documentElement.style.overscrollBehavior;
    window.document.body.style.overflow = "hidden";
    window.document.documentElement.style.overscrollBehavior = "none";

    return () => {
      window.document.body.style.overflow = previousBodyOverflow;
      window.document.documentElement.style.overscrollBehavior = previousHtmlOverscroll;
    };
  }, [commandOpen, createOpen, document, drawerFolder, onboardingOpen, settingsOpen]);

  useEffect(() => {
    if (!onboardingRequested || !environmentChecked || environmentChecking) return;

    if (environmentHealth.ready) {
      window.localStorage.setItem(onboardingStorageKey, "true");
      setOnboardingRequested(false);
      setOnboardingOpen(false);
      return;
    }

    setOnboardingOpen(true);
  }, [environmentChecked, environmentChecking, environmentHealth.ready, onboardingRequested]);

  useEffect(() => {
    const onKeyDown = (event: KeyboardEvent) => {
      if ((event.metaKey || event.ctrlKey) && event.key.toLowerCase() === "k") {
        event.preventDefault();
        setCommandOpen(true);
      }
    };
    window.addEventListener("keydown", onKeyDown);
    return () => window.removeEventListener("keydown", onKeyDown);
  }, []);

  useEffect(() => {
    void refreshData();
  }, [refreshData]);

  useEffect(() => {
    void refreshSourceRepos();
  }, [settings.sourceReposRoot]);

  useEffect(() => {
    void refreshEnvironmentHealth();
  }, [settings.workspacesRoot, settings.sourceReposRoot, settings.docsRoot]);

  useEffect(() => {
    void refreshSearchIndex();
  }, [refreshSearchIndex]);

  useEffect(() => {
    const trimmed = query.trim();
    const requestId = searchRequestRef.current + 1;
    searchRequestRef.current = requestId;

    if (!trimmed) {
      setSearchResults([]);
      setSearchSearching(false);
      return;
    }

    setSearchSearching(true);
    const timer = window.setTimeout(async () => {
      try {
        const indexed = await searchIndex({ query: trimmed, limit: 8 });
        const results = indexed ?? fallbackSearchResults(dashboard, trimmed, 8);
        if (searchRequestRef.current === requestId) setSearchResults(results);
      } catch {
        if (searchRequestRef.current === requestId) {
          setSearchResults(fallbackSearchResults(dashboard, trimmed, 8));
        }
      } finally {
        if (searchRequestRef.current === requestId) setSearchSearching(false);
      }
    }, 180);

    return () => window.clearTimeout(timer);
  }, [dashboard, query]);

  useEffect(() => {
    setSelectedSearchIndex(0);
  }, [query, searchResults]);

  useEffect(() => {
    if (!refreshEnabled) return;
    const timer = window.setInterval(refreshData, settings.refreshIntervalSeconds * 1000);
    return () => window.clearInterval(timer);
  }, [refreshData, refreshEnabled, settings.refreshIntervalSeconds]);

  useEffect(() => {
    void writeWidgetSnapshot(widgetSnapshotFromDashboard(dashboard, active));
  }, [dashboard, active]);

  const sorted = useMemo(() => [...dashboard.workspaces].sort((a, b) => workspaceScore(b) - workspaceScore(a)), [dashboard.workspaces]);
  const visible = useMemo(() => {
    const lower = query.trim().toLowerCase();
    return sorted.filter((workspace) => {
      const haystack = [
        workspace.name,
        workspace.folder,
        workspace.targetBranch,
        workspace.sourceRoot,
        ...workspace.confirmedServices,
        ...workspace.candidateServices,
        ...workspace.risks
      ]
        .join(" ")
        .toLowerCase();
      const matchesQuery = !lower || haystack.includes(lower);
      const matchesFilter =
        filter === "all" ||
        (filter === "risk" && workspace.riskCount > 0) ||
        (filter === "branch" && branchAlignmentRows(workspace).length > 0) ||
        (filter === "dirty" && workspace.gitRows.some((row) => row.worktree.dirty)) ||
        (filter === "missing" && workspace.gitRows.some((row) => !row.worktree.exists));
      return matchesQuery && matchesFilter;
    });
  }, [filter, query, sorted]);

  const current = visible.find((workspace) => workspace.folder === active) ?? visible[0];
  const drawerWorkspace = dashboard.workspaces.find((workspace) => workspace.folder === drawerFolder);
  const services = new Set(dashboard.workspaces.flatMap((workspace) => workspace.confirmedServices)).size;
  const risks = dashboard.workspaces.reduce((sum, workspace) => sum + workspace.riskCount, 0);
  const branchMismatches = dashboard.workspaces.reduce((sum, workspace) => sum + branchAlignmentRows(workspace).length, 0);
  const missing = dashboard.workspaces.filter((workspace) => workspace.gitRows.some((row) => !row.worktree.exists)).length;
  const keyboardSearchResults = useMemo(() => orderedSearchResults(searchResults), [searchResults]);

  const workspaceForTarget = useCallback((target: string) => {
    return dashboard.workspaces.find((workspace) => {
      return target === workspace.folder || target.includes(workspace.path) || target.includes(workspace.folder);
    });
  }, [dashboard.workspaces]);

  const prependWorkspaceActivity = useCallback((workspace: Workspace, action: string, summary: string) => {
    const activity = {
      time: activityTimestamp(),
      title: auditActivityTitle(action),
      detail: `Nexus App · ${summary}`
    };
    setDashboard((currentData) => ({
      ...currentData,
      workspaces: currentData.workspaces.map((item) => {
        if (item.folder !== workspace.folder) return item;
        return {
          ...item,
          updated: activity.time,
          activities: [activity, ...(item.activities ?? [])].slice(0, 6)
        };
      })
    }));
  }, []);

  const recordWorkspaceAction = useCallback(async (
    workspace: Workspace,
    action: string,
    summary: string,
    options: { target?: string; metadata?: Record<string, string> } = {}
  ) => {
    const target = options.target ?? workspace.path;
    prependWorkspaceActivity(workspace, action, summary);
    try {
      await appendAuditEvent({
        actor: "Nexus App",
        action,
        target,
        summary,
        metadata: {
          folder: workspace.folder,
          workspaceFolder: workspace.folder,
          name: workspace.name,
          path: workspace.path,
          ...options.metadata
        }
      });
    } catch {
      // Browser preview and unavailable desktop bridges should not block the user action.
    }
  }, [prependWorkspaceActivity]);

  const toggleDetails = (folder: string) => {
    setExpanded((currentSet) => {
      const next = new Set(currentSet);
      if (next.has(folder)) next.delete(folder);
      else next.add(folder);
      return next;
    });
  };

  const handleOpenCodex = async () => {
    await openExternalUrl(settings.codexUrl || "codex://");
    if (current) {
      void recordWorkspaceAction(current, "codex.opened", `Opened Codex for ${current.name}`, {
        metadata: { codexUrl: settings.codexUrl || "codex://" }
      });
    }
    showToast("已打开 Codex");
  };

  const copyCommand = async (workspace: Workspace) => {
    await navigator.clipboard.writeText(workspace.worktreeCommand);
    void recordWorkspaceAction(workspace, "worktree.command.copied", `Copied worktree command for ${workspace.name}`);
    showToast(`已复制 ${workspace.name} 的 worktree 命令`);
  };

  const copyInstruction = async (workspace: Workspace, action: "continue" | "git" | "delivery" | "risk" | "worktree") => {
    await navigator.clipboard.writeText(codexInstruction(workspace, action));
    void recordWorkspaceAction(workspace, "codex_instruction.copied", `Copied ${action} Codex instruction for ${workspace.name}`, {
      metadata: { instructionType: action }
    });
    showToast(`已复制 ${workspace.name} 的 Codex 指令`);
  };

  const copyAndOpenCodex = async (workspace: Workspace, action: "continue" | "git" | "delivery" | "risk") => {
    await navigator.clipboard.writeText(codexInstruction(workspace, action));
    await openExternalUrl(settings.codexUrl || "codex://");
    void recordWorkspaceAction(workspace, "codex_handoff.opened", `Copied ${action} instruction and opened Codex for ${workspace.name}`, {
      metadata: { instructionType: action, codexUrl: settings.codexUrl || "codex://" }
    });
    showToast(`已复制 ${workspace.name} 的指令并打开 Codex`);
  };

  const saveSettings = () => {
    window.localStorage.setItem(settingsStorageKey, JSON.stringify(settings, null, 2));
    window.localStorage.setItem(onboardingStorageKey, "true");
    setOnboardingRequested(false);
    setOnboardingOpen(false);
    showToast("已保存 Nexus 本机配置");
    void refreshData();
    void refreshSourceRepos();
    void refreshEnvironmentHealth();
    void refreshSearchIndex();
  };

  const handleExportSettings = async () => {
    const profile = createSettingsProfile(settings);
    try {
      const exported = await exportSettingsProfile(profile);
      if (exported?.path) {
        showToast(`已导出配置：${exported.path}`);
        return;
      }
      downloadSettingsProfile(profile);
      showToast("已下载 Nexus 配置文件");
    } catch (error) {
      showToast(error instanceof Error ? error.message : "导出配置失败");
    }
  };

  const handleImportSettings = (content: string) => {
    try {
      const imported = parseSettingsProfile(content);
      setSettings(imported);
      window.localStorage.setItem(settingsStorageKey, JSON.stringify(imported, null, 2));
      window.localStorage.setItem(onboardingStorageKey, "true");
      setOnboardingRequested(false);
      setOnboardingOpen(false);
      showToast("已导入并保存团队配置");
    } catch (error) {
      showToast(error instanceof Error ? error.message : "导入配置失败");
    }
  };

  const dismissOnboarding = () => {
    window.localStorage.setItem(onboardingStorageKey, "true");
    setOnboardingRequested(false);
    setOnboardingOpen(false);
  };

  const openConfiguredPath = async (path: string) => {
    await openPathInDesktop(path);
  };

  const handleScanSourceRepos = async () => {
    const repos = await refreshSourceRepos();
    showToast(`已识别 ${repos.length} 个源仓库服务`);
  };

  const handleCheckEnvironment = async () => {
    const health = await refreshEnvironmentHealth();
    showToast(health.ready ? "环境检查通过" : `环境检查发现 ${health.blockers.length} 个阻塞项`);
  };

  const openDocument = async (title: string, path: string) => {
    try {
      const content = await readTextFile(path);
      setDocument({ title, path, content });
      const workspace = workspaceForTarget(path);
      if (workspace) {
        void recordWorkspaceAction(workspace, "document.opened", `Opened ${title}`, {
          target: path,
          metadata: { documentTitle: title, documentPath: path }
        });
      }
    } catch (error) {
      showToast(error instanceof Error ? error.message : "文档读取失败");
    }
  };

  const handleRefreshAll = () => {
    void refreshData();
    void refreshSearchIndex({ showToast: true });
  };

  const handleOpenSearchResult = (result: SearchResult) => {
    setActive(result.workspaceFolder);
    setQuery("");
    if (result.kind === "workspace") {
      setDrawerFolder(result.workspaceFolder);
      return;
    }
    void openDocument(`${result.workspaceName} / ${result.documentName}`, result.documentPath);
  };

  const moveSearchSelection = (direction: 1 | -1) => {
    const count = keyboardSearchResults.length;
    if (!count) return;
    setSelectedSearchIndex((currentIndex) => (currentIndex + direction + count) % count);
  };

  const handleOpenSelectedSearchResult = () => {
    const result = keyboardSearchResults[Math.min(selectedSearchIndex, keyboardSearchResults.length - 1)];
    if (result) handleOpenSearchResult(result);
  };

  const handleCreateWorkspace = async (input: { name: string; folder: string; services: string[]; targetBranch: string; confirmed: boolean }) => {
    try {
      const result = await createWorkspace({
        name: input.name,
        folder: input.folder,
        workspacesRoot: settings.workspacesRoot,
        sourceReposRoot: settings.sourceReposRoot,
        services: input.services,
        targetBranch: input.targetBranch,
        confirmed: input.confirmed
      });
      const path = result?.path ?? `${settings.workspacesRoot}/${input.folder}`;
      const targetBranch = input.targetBranch.trim() || "待确认";
      const links = {
        folder: path,
        workspace: `${path}/workspace.md`,
        status: `${path}/STATUS.md`,
        services: `${path}/services.md`,
        branches: `${path}/branches.md`,
        tasks: `${path}/tasks.md`,
        delivery: `${path}/交付记录.md`,
        handoff: `${path}/handoff.md`,
        bootstrap: `${path}/bootstrap-report.md`,
        worktreeScript: `${path}/scripts/worktree-commands.sh`,
        sql: `${path}/sql`
      };
      const workspaceRisks = [
        ...(targetBranch === "待确认" ? ["目标分支未确认"] : []),
        ...(input.services.length ? [`worktree 未创建: ${input.services.join(", ")}`] : ["服务范围未确认"]),
        "交付记录待补充"
      ];
      const workspace: Workspace = {
        name: input.name,
        folder: input.folder,
        path,
        state: "analyzing",
        targetBranch,
        sourceRoot: settings.sourceReposRoot,
        confirmedServices: input.services,
        candidateServices: [],
        taskCounts: { done: 0, doing: 0, todo: 5, blocked: 0 },
        decisionCount: 0,
        gitRows: input.services.map((service) => ({
          service,
          worktreePath: `${path}/repos/${service}`,
          sourcePath: `${settings.sourceReposRoot}/${service}`,
          worktree: { exists: false, branch: "未创建", dirty: false, summary: "未创建" },
          source: { exists: true, branch: "未检查", dirty: false, summary: "待刷新" }
        })),
        risks: workspaceRisks,
        riskCount: workspaceRisks.length,
        updated: todayString(),
        links,
        worktreeCommand: buildWorktreeCommand(path, settings.sourceReposRoot, input.services, targetBranch),
        activities: [
          {
            time: activityTimestamp(),
            title: auditActivityTitle("workspace.created"),
            detail: `Nexus App · Created workspace ${input.name}`
          }
        ]
      };
      setDashboard((currentData) => ({ ...currentData, workspaces: [workspace, ...currentData.workspaces] }));
      setActive(input.folder);
      setCreateOpen(false);
      void refreshSearchIndex();
      showToast(`已创建工作区 ${input.name}`);
    } catch (error) {
      showToast(error instanceof Error ? error.message : "创建工作区失败");
    }
  };

  const copyRiskInstruction = async (workspace: Workspace, risk: string) => {
    await navigator.clipboard.writeText(riskInstruction(workspace, risk));
    void recordWorkspaceAction(workspace, "risk_instruction.copied", `Copied risk instruction for ${risk}`, {
      metadata: { risk }
    });
    showToast("已复制风险处理指令");
  };

  return (
    <div className="grid min-h-screen grid-cols-1 lg:grid-cols-[248px_minmax(0,1fr)] 2xl:grid-cols-[268px_minmax(0,1fr)_330px]">
      <Sidebar
        workspaces={sorted}
        active={current?.folder ?? active}
        setActive={setActive}
        filter={filter}
        setFilter={setFilter}
        onOpenCreate={() => setCreateOpen(true)}
        onOpenSettings={() => setSettingsOpen(true)}
      />
      <main className="min-w-0">
        <TopBar
          query={query}
          setQuery={setQuery}
          current={current}
          dashboard={dashboard}
          refreshEnabled={refreshEnabled}
          searchResults={searchResults}
          searchSearching={searchSearching}
          searchIndexState={searchIndexState}
          selectedSearchIndex={Math.min(selectedSearchIndex, Math.max(keyboardSearchResults.length - 1, 0))}
          onToggleRefresh={() => setRefreshEnabled((value) => !value)}
          onRefresh={handleRefreshAll}
          onCommand={() => setCommandOpen(true)}
          onOpenCodex={handleOpenCodex}
          onOpenSearchResult={handleOpenSearchResult}
          onOpenSelectedSearchResult={handleOpenSelectedSearchResult}
          onMoveSearchSelection={moveSearchSelection}
          onRebuildSearchIndex={() => void refreshSearchIndex({ showToast: true })}
        />
        <div className="px-4 py-4 xl:px-5 xl:py-5">
          <div className="mb-5 grid gap-3 xl:flex xl:items-end xl:justify-between">
            <div className="min-w-0">
              <div className="mono mb-2 flex min-w-0 items-center gap-2 truncate text-xs text-neutral-400">
                <Braces className="h-3.5 w-3.5" />
                <span className="truncate">{dashboard.workspacesRoot}</span>
              </div>
              <h1 className="text-2xl font-semibold tracking-tight text-neutral-950">本地 AI 开发工作台</h1>
              <p className="mt-2 max-w-2xl text-sm leading-6 text-neutral-500">
                用于统一查看需求工作区、服务范围、分支/worktree 状态、风险告警和交付资料完整性。每张卡片代表一个可推进的本地任务流。
              </p>
            </div>
            <div className="mono text-xs text-neutral-400">generated {dashboard.generatedAt}</div>
          </div>

          <div className="mb-5 rounded-lg border border-neutral-200 bg-white p-3 text-sm text-neutral-600">
            <div className="mb-3 flex flex-wrap items-center justify-between gap-2 border-b border-neutral-100 pb-3">
              <div className="flex items-center gap-2">
                {environmentHealth.ready ? <CheckCircle2 className="h-4 w-4 text-emerald-600" /> : <AlertTriangle className="h-4 w-4 text-amber-600" />}
                <span className="font-medium text-neutral-900">环境状态 / Environment</span>
                <Badge tone={environmentHealth.ready ? "green" : "amber"}>{environmentHealth.ready ? "ready" : "attention"}</Badge>
              </div>
              <button className="rounded-md border border-neutral-200 px-2 py-1 text-xs text-neutral-700 hover:bg-neutral-50" onClick={handleCheckEnvironment}>
                {environmentChecking ? "检查中" : "重新检查"}
              </button>
            </div>
            <div className="font-medium text-neutral-900">如何阅读 / How to read</div>
            <div className="mt-2 grid gap-2 md:grid-cols-3">
              <div>风险项提示当前需要优先确认的阻塞点。</div>
              <div>Worktree 表示工作区内独立分支目录，避免多个需求互相切分支。</div>
              <div>展开详情可查看每个服务的 worktree 与源仓库 Git 状态。</div>
            </div>
          </div>

          <div className="mb-5 grid grid-cols-2 gap-3 xl:grid-cols-5">
            <Stat label={statLabels.workspaces} value={dashboard.workspaces.length} icon={Workflow} />
            <Stat label={statLabels.services} value={services} icon={Boxes} />
            <Stat label={statLabels.risks} value={risks} icon={AlertTriangle} />
            <Stat label={statLabels.branch} value={branchMismatches} icon={GitBranch} />
            <Stat label={statLabels.missing} value={missing} icon={Terminal} />
          </div>

          <section className="grid grid-cols-1 gap-3 2xl:grid-cols-2">
            {visible.map((workspace) => (
              <WorkspaceCard
                key={workspace.folder}
                workspace={workspace}
                active={workspace.folder === current?.folder}
                expanded={expanded.has(workspace.folder)}
                onFocus={() => setActive(workspace.folder)}
                onToggleDetails={() => toggleDetails(workspace.folder)}
                onCopyCommand={() => copyCommand(workspace)}
                onCopyInstruction={(action) => copyInstruction(workspace, action)}
                onCopyRiskInstruction={(risk) => copyRiskInstruction(workspace, risk)}
                onCopyAndOpenCodex={(action) => copyAndOpenCodex(workspace, action)}
                onOpenDocument={openDocument}
                onOpenDrawer={() => {
                  setActive(workspace.folder);
                  setDrawerFolder(workspace.folder);
                }}
              />
            ))}
          </section>
        </div>
      </main>
      <RightRail current={current} visible={visible} />
      <CommandPalette
        open={commandOpen}
        onOpenChange={setCommandOpen}
        current={current}
        setFilter={setFilter}
        refreshData={handleRefreshAll}
        rebuildSearchIndex={() => void refreshSearchIndex({ showToast: true })}
        onOpenCodex={handleOpenCodex}
      />
      <CreateWorkspacePanel
        open={createOpen}
        settings={settings}
        sourceRepos={sourceRepos}
        sourceScanning={sourceScanning}
        onClose={() => setCreateOpen(false)}
        onCreate={handleCreateWorkspace}
        onScanSourceRepos={handleScanSourceRepos}
      />
      <SettingsPanel
        open={settingsOpen}
        settings={settings}
        sourceRepos={sourceRepos}
        environmentHealth={environmentHealth}
        sourceScanning={sourceScanning}
        onChange={setSettings}
        onClose={() => setSettingsOpen(false)}
        onSave={saveSettings}
        onExportSettings={handleExportSettings}
        onImportSettings={handleImportSettings}
        onOpenPath={openConfiguredPath}
        onScanSourceRepos={handleScanSourceRepos}
        onCheckEnvironment={handleCheckEnvironment}
      />
      <OnboardingPanel
        open={onboardingOpen}
        settings={settings}
        sourceRepos={sourceRepos}
        environmentHealth={environmentHealth}
        sourceScanning={sourceScanning}
        onChange={setSettings}
        onClose={dismissOnboarding}
        onSave={saveSettings}
        onSkip={dismissOnboarding}
        onOpenPath={openConfiguredPath}
        onScanSourceRepos={handleScanSourceRepos}
        onCheckEnvironment={handleCheckEnvironment}
      />
      <WorkspaceDrawer
        workspace={drawerWorkspace}
        onClose={() => setDrawerFolder("")}
        onCopyInstruction={copyInstruction}
        onCopyRiskInstruction={copyRiskInstruction}
        onCopyAndOpenCodex={copyAndOpenCodex}
        onOpenDocument={openDocument}
      />
      <DocumentViewer document={document} onClose={() => setDocument(undefined)} onOpenExternal={openConfiguredPath} />
      {toast && <div className="fixed bottom-4 left-1/2 -translate-x-1/2 rounded-md border border-neutral-200 bg-white px-3 py-2 text-sm text-neutral-700 shadow-[0_8px_24px_rgba(15,23,42,0.12)]" style={{ zIndex: 1100 }}>{toast}</div>}
    </div>
  );
}
