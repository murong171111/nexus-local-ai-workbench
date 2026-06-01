import { readFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(fileURLToPath(new URL("..", import.meta.url)));
const sampleFiles = ["src/data/workspaces.json"];
const requiredLinks = ["folder", "workspace", "status", "services", "branches", "tasks", "delivery", "handoff"];

export function checkDashboardSample(filePath) {
  const findings = [];
  let parsed;

  try {
    parsed = JSON.parse(readFileSync(filePath, "utf8"));
  } catch (error) {
    findings.push(finding(filePath, "invalid-json", error instanceof Error ? error.message : String(error)));
    return findings;
  }

  if (!isRecord(parsed)) {
    findings.push(finding(filePath, "dashboard-shape", "sample dashboard must be a JSON object"));
    return findings;
  }

  if (parsed.generatedAt !== "sample") {
    findings.push(finding(filePath, "generated-at", "generatedAt must stay the stable sample marker"));
  }

  for (const key of ["workspacesRoot", "sourceReposRoot", "docsRoot"]) {
    if (!samplePath(parsed[key])) {
      findings.push(finding(filePath, key, `${key} must use a publishable ~/ks_project sample path`));
    }
  }

  if (!Array.isArray(parsed.workspaces) || parsed.workspaces.length === 0) {
    findings.push(finding(filePath, "workspaces", "sample dashboard must include at least one workspace"));
    return findings;
  }

  const seenFolders = new Set();
  parsed.workspaces.forEach((workspace, index) => {
    checkWorkspace(filePath, workspace, index, seenFolders, findings);
  });

  return findings;
}

export function checkDashboardSamples(scanRoot = root) {
  return sampleFiles.flatMap((relativePath) => checkDashboardSample(path.join(scanRoot, relativePath)));
}

function checkWorkspace(filePath, workspace, index, seenFolders, findings) {
  const prefix = `workspaces[${index}]`;
  if (!isRecord(workspace)) {
    findings.push(finding(filePath, prefix, "workspace must be an object"));
    return;
  }

  for (const key of ["name", "folder", "path", "state", "targetBranch", "sourceRoot", "updated"]) {
    if (!nonEmptyString(workspace[key])) {
      findings.push(finding(filePath, `${prefix}.${key}`, `${key} is required`));
    }
  }

  if (nonEmptyString(workspace.folder)) {
    if (seenFolders.has(workspace.folder)) {
      findings.push(finding(filePath, `${prefix}.folder`, `duplicate workspace folder ${workspace.folder}`));
    }
    seenFolders.add(workspace.folder);
  }

  if (!samplePath(workspace.path)) {
    findings.push(finding(filePath, `${prefix}.path`, "workspace path must use a publishable sample path"));
  }
  if (!samplePath(workspace.sourceRoot)) {
    findings.push(finding(filePath, `${prefix}.sourceRoot`, "sourceRoot must use a publishable sample path"));
  }

  if (!Array.isArray(workspace.confirmedServices)) {
    findings.push(finding(filePath, `${prefix}.confirmedServices`, "confirmedServices must be an array"));
  }
  if (!Array.isArray(workspace.candidateServices)) {
    findings.push(finding(filePath, `${prefix}.candidateServices`, "candidateServices must be an array"));
  }
  if (!Array.isArray(workspace.gitRows)) {
    findings.push(finding(filePath, `${prefix}.gitRows`, "gitRows must be an array"));
  }
  if (!Array.isArray(workspace.risks)) {
    findings.push(finding(filePath, `${prefix}.risks`, "risks must be an array"));
  }

  if (Array.isArray(workspace.risks) && workspace.riskCount !== workspace.risks.length) {
    findings.push(finding(filePath, `${prefix}.riskCount`, "riskCount must match risks.length in sample data"));
  }

  if (!isRecord(workspace.taskCounts)) {
    findings.push(finding(filePath, `${prefix}.taskCounts`, "taskCounts is required"));
  } else {
    for (const key of ["done", "doing", "todo", "blocked", "deferred"]) {
      if (!nonNegativeInteger(workspace.taskCounts[key])) {
        findings.push(finding(filePath, `${prefix}.taskCounts.${key}`, `${key} must be a non-negative integer`));
      }
    }
  }

  if (!isRecord(workspace.links)) {
    findings.push(finding(filePath, `${prefix}.links`, "links is required"));
  } else {
    for (const key of requiredLinks) {
      if (!samplePath(workspace.links[key])) {
        findings.push(finding(filePath, `${prefix}.links.${key}`, `${key} link must use a publishable sample path`));
      }
    }
  }

  if (Array.isArray(workspace.gitRows)) {
    workspace.gitRows.forEach((row, rowIndex) => {
      checkGitRow(filePath, row, `${prefix}.gitRows[${rowIndex}]`, findings);
    });
  }
}

function checkGitRow(filePath, row, prefix, findings) {
  if (!isRecord(row)) {
    findings.push(finding(filePath, prefix, "git row must be an object"));
    return;
  }

  for (const key of ["service", "worktreePath", "sourcePath"]) {
    if (!nonEmptyString(row[key])) {
      findings.push(finding(filePath, `${prefix}.${key}`, `${key} is required`));
    }
  }
  if (!samplePath(row.worktreePath)) {
    findings.push(finding(filePath, `${prefix}.worktreePath`, "worktreePath must use a publishable sample path"));
  }
  if (!samplePath(row.sourcePath)) {
    findings.push(finding(filePath, `${prefix}.sourcePath`, "sourcePath must use a publishable sample path"));
  }

  for (const key of ["worktree", "source"]) {
    if (!isRecord(row[key])) {
      findings.push(finding(filePath, `${prefix}.${key}`, `${key} status is required`));
      continue;
    }
    if (typeof row[key].exists !== "boolean") {
      findings.push(finding(filePath, `${prefix}.${key}.exists`, "exists must be boolean"));
    }
    if (typeof row[key].dirty !== "boolean") {
      findings.push(finding(filePath, `${prefix}.${key}.dirty`, "dirty must be boolean"));
    }
    for (const statusKey of ["branch", "summary"]) {
      if (!nonEmptyString(row[key][statusKey])) {
        findings.push(finding(filePath, `${prefix}.${key}.${statusKey}`, `${statusKey} is required`));
      }
    }
  }
}

function samplePath(value) {
  return typeof value === "string" && (value.startsWith("~/ks_project/") || value === "~/ks_project");
}

function nonEmptyString(value) {
  return typeof value === "string" && value.trim().length > 0;
}

function nonNegativeInteger(value) {
  return Number.isInteger(value) && value >= 0;
}

function isRecord(value) {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function finding(file, pathLabel, message) {
  return {
    file: path.relative(root, file),
    path: pathLabel,
    message
  };
}

function formatFindings(findings) {
  return findings.map((item) => `- ${item.file} ${item.path}: ${item.message}`);
}

function main() {
  const findings = checkDashboardSamples(root);
  if (findings.length) {
    console.error("Dashboard sample check failed:");
    for (const line of formatFindings(findings)) console.error(line);
    process.exit(1);
  }
  console.log("Dashboard sample check passed.");
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
