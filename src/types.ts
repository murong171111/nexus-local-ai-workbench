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
  };
  decisionCount: number;
  gitRows: GitRow[];
  risks: string[];
  riskCount: number;
  updated: string;
  links: Record<string, string>;
  worktreeCommand: string;
  activities?: WorkspaceActivity[];
};

export type DashboardData = {
  generatedAt: string;
  workspacesRoot: string;
  sourceReposRoot?: string;
  docsRoot?: string;
  workspaces: Workspace[];
};
