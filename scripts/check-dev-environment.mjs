import { existsSync } from "node:fs";
import path from "node:path";
import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(fileURLToPath(new URL("..", import.meta.url)));

const requiredTools = [
  {
    name: "Node.js",
    command: process.execPath,
    args: ["--version"],
    recover: "Install Node.js 22+ and rerun npm ci.",
    validate: (output) => Number(output.replace(/^v/, "").split(".")[0]) >= 22,
    invalid: "Node.js 22+ is required."
  },
  {
    name: "Git",
    command: "git",
    args: ["--version"],
    recover: "Install Git or Xcode Command Line Tools."
  },
  {
    name: "Cargo",
    command: "cargo",
    args: ["--version"],
    recover: "Install the Rust toolchain from https://rustup.rs/ before running npm run rust:test or npm run ffi:build."
  },
  {
    name: "Swift compiler",
    command: "swiftc",
    args: ["--version"],
    recover: "Install Xcode Command Line Tools, then confirm xcode-select points at a compatible toolchain."
  },
  {
    name: "SwiftPM",
    command: "swift",
    args: ["--version"],
    recover: "Install Xcode Command Line Tools or full Xcode before running npm run native:build."
  }
];

export function checkDevEnvironment(options = {}) {
  const cwd = options.cwd ?? root;
  const run = options.run ?? runCommand;
  const results = [];

  for (const tool of requiredTools) {
    const result = run(tool.command, tool.args, cwd);
    const output = `${result.stdout ?? ""}${result.stderr ?? ""}`.trim();
    const available = result.status === 0 && (!tool.validate || tool.validate(output));
    results.push({
      name: tool.name,
      available,
      detail: available ? firstLine(output) : output || tool.invalid || `${tool.command} was not found.`,
      recover: available ? "" : tool.recover
    });
  }

  const dependencyPath = path.join(cwd, "node_modules", ".bin", process.platform === "win32" ? "tsc.cmd" : "tsc");
  const tauriCliPath = path.join(cwd, "node_modules", ".bin", process.platform === "win32" ? "tauri.cmd" : "tauri");
  results.push({
    name: "Node dependencies",
    available: existsSync(dependencyPath),
    detail: existsSync(dependencyPath) ? "node_modules is installed." : "node_modules is missing or incomplete.",
    recover: existsSync(dependencyPath) ? "" : "Run npm ci from the repository root."
  });
  results.push({
    name: "Tauri CLI",
    available: existsSync(tauriCliPath),
    detail: existsSync(tauriCliPath) ? "Project-local Tauri CLI is installed." : "Project-local Tauri CLI is missing.",
    recover: existsSync(tauriCliPath) ? "" : "Run npm ci so @tauri-apps/cli is available before npm run tauri:build."
  });

  return {
    ready: results.every((result) => result.available),
    results
  };
}

function runCommand(command, args, cwd) {
  return spawnSync(command, args, { cwd, encoding: "utf8" });
}

function firstLine(value) {
  return value.split(/\r?\n/u).find(Boolean) ?? "";
}

function main() {
  const report = checkDevEnvironment();

  for (const result of report.results) {
    const mark = result.available ? "OK" : "MISSING";
    console.log(`[${mark}] ${result.name}: ${result.detail}`);
    if (!result.available) console.log(`       ${result.recover}`);
  }

  if (!report.ready) {
    console.error("Development environment check failed. Fix the missing tools above before running the full verification suite.");
    process.exit(1);
  }

  console.log("Development environment check passed.");
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  main();
}
