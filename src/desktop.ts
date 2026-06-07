import type { NexusSettingsProfile, WorkspaceSearchResult } from "./workspace-model";
import type { CodexSessionLink, WorkspaceTask } from "./types";

async function tauriInvoke<T>(command: string, args?: Record<string, unknown>) {
  if (typeof window === "undefined" || !("__TAURI_INTERNALS__" in window)) {
    return null;
  }

  const { invoke } = await import("@tauri-apps/api/core");
  return invoke<T>(command, args);
}

export type CreateWorkspacePayload = {
  name: string;
  folder: string;
  workspacesRoot: string;
  sourceReposRoot: string;
  services: string[];
  targetBranch: string;
  confirmed: boolean;
};

export type SetupWorktreesPayload = {
  workspacePath: string;
  sourceReposRoot: string;
  services: string[];
  targetBranch: string;
  confirmed: boolean;
};

export type WorktreeSetupResult = {
  service: string;
  sourcePath: string;
  worktreePath: string;
  status: string;
  detail: string;
};

export type SetupWorktreesResponse = {
  workspacePath: string;
  targetBranch: string;
  command: string;
  created: WorktreeSetupResult[];
  skipped: WorktreeSetupResult[];
  failed: WorktreeSetupResult[];
};

export type UpdateWorkspaceTaskPayload = {
  workspacePath: string;
  taskId: string;
  status: string;
  detail?: string;
  confirmed: boolean;
};

export type UpdateWorkspaceTaskResponse = {
  path: string;
  task: WorkspaceTask;
  previousStatus: string;
  updated: boolean;
};

export type CodexSessionStoreResponse = {
  path: string;
  sessions: CodexSessionLink[];
};

export type BindCodexSessionPayload = {
  workspacePath: string;
  title: string;
  url: string;
  notes?: string;
  confirmed: boolean;
};

export type CodexSessionActionPayload = {
  workspacePath: string;
  sessionId: string;
  confirmed: boolean;
};

export type CodexSessionMutationResponse = {
  path: string;
  sessions: CodexSessionLink[];
  link?: CodexSessionLink;
  updated: boolean;
};

export type AuditEventPayload = {
  actor?: string;
  action: string;
  target: string;
  summary: string;
  metadata?: Record<string, string>;
};

export type AuditEventResponse = {
  path: string;
  event: {
    id: string;
    timestamp: string;
    actor: string;
    action: string;
    target: string;
    summary: string;
    metadata: Record<string, string>;
  };
};

export type WidgetSnapshotPayload = {
  generatedAt: string;
  workspacesRoot: string;
  activeWorkspace?: string;
  activeWorkspaceFolder?: string;
  workspaceCount: number;
  riskCount: number;
  dirtyServiceCount: number;
  missingWorktreeCount: number;
  topRisks: string[];
  deepLink: string;
};

export type ScanWorkspacesPayload = {
  workspacesRoot: string;
  sourceReposRoot: string;
  docsRoot: string;
};

export type SourceRepo = {
  name: string;
  path: string;
  isGit: boolean;
  branch: string;
  dirty: boolean;
  summary: string;
};

export type ScanSourceReposPayload = {
  sourceReposRoot: string;
};

export type PathCheck = {
  key: string;
  label: string;
  path: string;
  exists: boolean;
  isDir: boolean;
  writable: boolean;
  summary: string;
};

export type ToolCheck = {
  key: string;
  label: string;
  available: boolean;
  summary: string;
};

export type EnvironmentHealth = {
  generatedAt: string;
  ready: boolean;
  pathChecks: PathCheck[];
  toolChecks: ToolCheck[];
  workspaceCount: number;
  sourceRepoCount: number;
  blockers: string[];
  warnings: string[];
};

export type EnvironmentHealthPayload = {
  workspacesRoot: string;
  sourceReposRoot: string;
  docsRoot: string;
};

export type RebuildSearchIndexPayload = {
  workspacesRoot: string;
  sourceReposRoot: string;
  docsRoot: string;
};

export type RebuildSearchIndexResponse = {
  path: string;
  workspaceCount: number;
  documentCount: number;
};

export type SearchIndexPayload = {
  query: string;
  limit?: number;
};

export type SearchResult = WorkspaceSearchResult;

export function isDesktopApp() {
  return typeof window !== "undefined" && "__TAURI_INTERNALS__" in window;
}

export async function openExternalUrl(url: string) {
  if (isDesktopApp()) {
    await tauriInvoke<void>("open_url", { url });
    return;
  }

  window.location.href = url;
}

export async function openPath(path: string) {
  if (isDesktopApp()) {
    await tauriInvoke<void>("open_path", { path });
    return;
  }

  window.open(`file://${path}`, "_blank");
}

export async function openTerminal(path: string) {
  if (isDesktopApp()) await tauriInvoke<void>("open_terminal", { path });
}

export async function openIdea(path: string) {
  if (isDesktopApp()) await tauriInvoke<void>("open_idea", { path });
}

export async function openCodex() {
  await openExternalUrl("codex://");
}

export async function readTextFile(path: string) {
  if (!isDesktopApp()) {
    const response = await fetch(`file://${path}`);
    if (!response.ok) {
      throw new Error(`file://${path} returned ${response.status}`);
    }
    return response.text();
  }
  return (await tauriInvoke<string>("read_text_file", { path })) ?? "";
}

export async function scanWorkspaces(payload: ScanWorkspacesPayload) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<unknown>("scan_workspaces", {
    request: {
      workspacesRoot: payload.workspacesRoot,
      sourceReposRoot: payload.sourceReposRoot,
      docsRoot: payload.docsRoot
    }
  });
}

export async function scanSourceRepos(payload: ScanSourceReposPayload) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<SourceRepo[]>("scan_source_repos", {
    request: {
      sourceReposRoot: payload.sourceReposRoot
    }
  });
}

export async function checkEnvironment(payload: EnvironmentHealthPayload) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<EnvironmentHealth>("check_environment", {
    request: {
      workspacesRoot: payload.workspacesRoot,
      sourceReposRoot: payload.sourceReposRoot,
      docsRoot: payload.docsRoot
    }
  });
}

export async function rebuildSearchIndex(payload: RebuildSearchIndexPayload) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<RebuildSearchIndexResponse>("rebuild_search_index", {
    request: {
      workspacesRoot: payload.workspacesRoot,
      sourceReposRoot: payload.sourceReposRoot,
      docsRoot: payload.docsRoot
    }
  });
}

export async function searchIndex(payload: SearchIndexPayload) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<SearchResult[]>("search_index", {
    request: {
      query: payload.query,
      limit: payload.limit
    }
  });
}

export async function createWorkspace(payload: CreateWorkspacePayload) {
  if (!isDesktopApp()) {
    throw new Error("新建工作区需要在 Nexus Mac App 中使用");
  }
  return tauriInvoke<{ path: string; folder: string }>("create_workspace", {
    request: {
      name: payload.name,
      folder: payload.folder,
      workspaces_root: payload.workspacesRoot,
      source_repos_root: payload.sourceReposRoot,
      services: payload.services,
      target_branch: payload.targetBranch,
      confirmed: payload.confirmed
    }
  });
}

export async function setupWorktrees(payload: SetupWorktreesPayload) {
  if (!isDesktopApp()) {
    throw new Error("创建 worktree 需要在 Nexus Mac App 中使用");
  }
  return tauriInvoke<SetupWorktreesResponse>("setup_worktrees", {
    request: {
      workspacePath: payload.workspacePath,
      sourceReposRoot: payload.sourceReposRoot,
      services: payload.services,
      targetBranch: payload.targetBranch,
      confirmed: payload.confirmed
    }
  });
}

export async function updateWorkspaceTask(payload: UpdateWorkspaceTaskPayload) {
  if (!isDesktopApp()) {
    throw new Error("更新任务需要在 Nexus Mac App 中使用");
  }
  return tauriInvoke<UpdateWorkspaceTaskResponse>("update_workspace_task", {
    request: {
      workspacePath: payload.workspacePath,
      taskId: payload.taskId,
      status: payload.status,
      detail: payload.detail,
      confirmed: payload.confirmed
    }
  });
}

export async function readCodexSessions(workspacePath: string) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<CodexSessionStoreResponse>("read_codex_sessions", {
    request: { workspacePath }
  });
}

export async function bindCodexSession(payload: BindCodexSessionPayload) {
  if (!isDesktopApp()) {
    throw new Error("绑定 Codex 会话需要在 Nexus Mac App 中使用");
  }
  return tauriInvoke<CodexSessionMutationResponse>("bind_codex_session", {
    request: {
      workspacePath: payload.workspacePath,
      title: payload.title,
      url: payload.url,
      notes: payload.notes ?? "",
      confirmed: payload.confirmed
    }
  });
}

export async function openCodexSession(payload: CodexSessionActionPayload) {
  if (!isDesktopApp()) {
    throw new Error("打开 Codex 会话需要在 Nexus Mac App 中使用");
  }
  return tauriInvoke<CodexSessionMutationResponse>("open_codex_session", {
    request: {
      workspacePath: payload.workspacePath,
      sessionId: payload.sessionId,
      confirmed: payload.confirmed
    }
  });
}

export async function deleteCodexSession(payload: CodexSessionActionPayload) {
  if (!isDesktopApp()) {
    throw new Error("删除 Codex 会话需要在 Nexus Mac App 中使用");
  }
  return tauriInvoke<CodexSessionMutationResponse>("delete_codex_session", {
    request: {
      workspacePath: payload.workspacePath,
      sessionId: payload.sessionId,
      confirmed: payload.confirmed
    }
  });
}

export async function writeWidgetSnapshot(snapshot: WidgetSnapshotPayload) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<{ path: string }>("write_widget_snapshot", { snapshot });
}

export async function exportSettingsProfile(profile: NexusSettingsProfile) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<{ path: string }>("export_settings_profile", { profile });
}

export async function appendAuditEvent(payload: AuditEventPayload) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<AuditEventResponse>("append_audit_event", {
    request: {
      actor: payload.actor,
      action: payload.action,
      target: payload.target,
      summary: payload.summary,
      metadata: payload.metadata ?? {}
    }
  });
}
