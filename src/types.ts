export type GitStatus = {
  exists: boolean;
  branch: string;
  dirty: boolean;
  summary: string;
};

export type GitRow = {
  service: string;
  worktreePath: string;
  sourcePath: string;
  worktree: GitStatus;
  source: GitStatus;
};

export type WorkspaceActivity = {
  time: string;
  title: string;
  detail: string;
};

export type WorkspaceHealthCheck = {
  id: string;
  label: string;
  detail: string;
  status: "pass" | "warning" | "fail" | string;
  action: string;
};

export type WorkspaceSessionAction = {
  id: string;
  label: string;
  detail: string;
  priority: "high" | "medium" | "low" | string;
  status: "blocked" | "recommended" | "optional" | string;
  instructionType: "continue" | "git" | "delivery" | "risk" | "worktree" | string;
  documentKey: string;
};

export type WorkspaceLifecycle = {
  stage: string;
  label: string;
  detail: string;
  progress: number;
  nextAction: string;
  documentKey: string;
};

export type WorkspaceSqlFile = {
  relativePath: string;
  path: string;
  kind: "formal" | "rollback" | string;
};

export type WorkspaceSqlDocument = {
  relativePath: string;
  path: string;
  kind: "markdown" | string;
};

export type Workspace = {
  name: string;
  folder: string;
  path: string;
  state: string;
  targetBranch: string;
  sourceRoot: string;
  confirmedServices: string[];
  candidateServices: string[];
  taskCounts: {
    done: number;
    doing: number;
    todo: number;
    blocked: number;
    deferred?: number;
  };
  decisionCount: number;
  gitRows: GitRow[];
  risks: string[];
  riskCount: number;
  lifecycle?: WorkspaceLifecycle;
  updated: string;
  links: Record<string, string>;
  sqlFiles?: WorkspaceSqlFile[];
  sqlDocuments?: WorkspaceSqlDocument[];
  worktreeCommand: string;
  activities?: WorkspaceActivity[];
  healthChecks?: WorkspaceHealthCheck[];
  sessionActions?: WorkspaceSessionAction[];
};

export type DashboardData = {
  generatedAt: string;
  workspacesRoot: string;
  sourceReposRoot?: string;
  docsRoot?: string;
  workspaces: Workspace[];
};
