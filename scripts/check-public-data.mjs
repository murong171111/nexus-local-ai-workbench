import { readFileSync, readdirSync, statSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(fileURLToPath(new URL("..", import.meta.url)));

const ignoredDirectories = new Set([
  ".git",
  ".build",
  ".npm-cache",
  ".swift-module-cache",
  ".tmp-tests",
  "dist",
  "node_modules",
  "target"
]);

const ignoredFiles = new Set([
  "package-lock.json",
  "Cargo.lock"
]);

const textExtensions = new Set([
  ".json",
  ".md",
  ".mjs",
  ".rs",
  ".swift",
  ".toml",
  ".ts",
  ".tsx",
  ".yml",
  ".yaml"
]);

const allowedPathExamples = [
  "/Users/example/",
  "/home/example/",
  "/Users/runner/",
  "~/ks_project/"
];

const checks = [
  {
    name: "private macOS home path",
    pattern: /\/Users\/[A-Za-z0-9._-]+\//g,
    allow: (match) => allowedPathExamples.some((prefix) => match.startsWith(prefix))
  },
  {
    name: "private Linux home path",
    pattern: /\/home\/[A-Za-z0-9._-]+\//g,
    allow: (match) => allowedPathExamples.some((prefix) => match.startsWith(prefix))
  },
  {
    name: "secret-like assignment",
    pattern: /\b(?:TOKEN|SECRET|PASSWORD|PRIVATE_KEY)\s*[:=]\s*['"]?[^'"\s]+/gi,
    allow: () => false
  }
];

export function scanPublicData(scanRoot = root) {
  const findings = [];
  walk(scanRoot, scanRoot, findings);
  return findings;
}

function walk(directory, scanRoot, findings) {
  for (const entry of readdirSync(directory)) {
    if (ignoredDirectories.has(entry)) continue;

    const absolute = path.join(directory, entry);
    const relative = path.relative(scanRoot, absolute);
    const stats = statSync(absolute);

    if (stats.isDirectory()) {
      walk(absolute, scanRoot, findings);
      continue;
    }

    if (ignoredFiles.has(entry) || !textExtensions.has(path.extname(entry))) continue;
    scanFile(relative, absolute, findings);
  }
}

function scanFile(relative, absolute, findings) {
  const content = readFileSync(absolute, "utf8");
  for (const check of checks) {
    for (const match of content.matchAll(check.pattern)) {
      const value = match[0];
      if (check.allow(value, relative)) continue;
      findings.push({
        file: relative,
        line: lineForIndex(content, match.index ?? 0),
        name: check.name,
        value
      });
    }
  }
}

function lineForIndex(content, index) {
  return content.slice(0, index).split("\n").length;
}

function formatFindings(findings) {
  return findings.map((finding) => `- ${finding.file}:${finding.line} ${finding.name}: ${finding.value}`);
}

function main() {
  const findings = scanPublicData(root);

  if (findings.length) {
    console.error("Public data check failed. Remove private paths or secret-like values before publishing:");
    for (const line of formatFindings(findings)) {
      console.error(line);
    }
    process.exit(1);
  }

  console.log("Public data check passed.");
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
