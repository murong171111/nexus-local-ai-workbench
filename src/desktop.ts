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
    return response.text();
  }
  return (await tauriInvoke<string>("read_text_file", { path })) ?? "";
}

export async function scanWorkspaces(payload: ScanWorkspacesPayload) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<unknown>("scan_workspaces", {
    request: {
      workspaces_root: payload.workspacesRoot,
      source_repos_root: payload.sourceReposRoot,
      docs_root: payload.docsRoot
    }
  });
}

export async function scanSourceRepos(payload: ScanSourceReposPayload) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<SourceRepo[]>("scan_source_repos", {
    request: {
      source_repos_root: payload.sourceReposRoot
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
      target_branch: payload.targetBranch
    }
  });
}

export async function writeWidgetSnapshot(snapshot: WidgetSnapshotPayload) {
  if (!isDesktopApp()) return null;
  return tauriInvoke<{ path: string }>("write_widget_snapshot", { snapshot });
}
