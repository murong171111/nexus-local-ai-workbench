import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { checkDevEnvironment } from "../scripts/check-dev-environment.mjs";

function fakeRun(missing = new Set()) {
  return (command) => {
    const name = command.includes("node") ? "node" : command;
    if (missing.has(name)) return { status: 127, stdout: "", stderr: "" };
    const versions = {
      node: "v22.0.0",
      git: "git version 2.45.0",
      cargo: "cargo 1.78.0",
      swiftc: "Apple Swift version 5.10",
      swift: "Swift Package Manager - Swift 5.10"
    };
    return { status: 0, stdout: versions[name] ?? "ok", stderr: "" };
  };
}

function tempProject(withDependencies = true) {
  const root = mkdtempSync(path.join(tmpdir(), "nexus-env-check-"));
  if (withDependencies) {
    mkdirSync(path.join(root, "node_modules", ".bin"), { recursive: true });
    writeFileSync(path.join(root, "node_modules", ".bin", process.platform === "win32" ? "tsc.cmd" : "tsc"), "");
    writeFileSync(path.join(root, "node_modules", ".bin", process.platform === "win32" ? "tauri.cmd" : "tauri"), "");
  }
  return root;
}

test("checkDevEnvironment passes when required tools and dependencies are available", () => {
  const report = checkDevEnvironment({ cwd: tempProject(), run: fakeRun() });

  assert.equal(report.ready, true);
  assert.equal(report.results.every((result) => result.available), true);
});

test("checkDevEnvironment reports missing Rust with recovery guidance", () => {
  const report = checkDevEnvironment({ cwd: tempProject(), run: fakeRun(new Set(["cargo"])) });
  const cargo = report.results.find((result) => result.name === "Cargo");

  assert.equal(report.ready, false);
  assert.equal(cargo.available, false);
  assert.match(cargo.recover, /Rust toolchain/);
});

test("checkDevEnvironment reports missing node dependencies before full verify", () => {
  const report = checkDevEnvironment({ cwd: tempProject(false), run: fakeRun() });
  const dependencies = report.results.find((result) => result.name === "Node dependencies");

  assert.equal(report.ready, false);
  assert.equal(dependencies.available, false);
  assert.match(dependencies.recover, /npm ci/);
});

test("checkDevEnvironment reports missing project-local Tauri CLI", () => {
  const root = tempProject();
  const tauriPath = path.join(root, "node_modules", ".bin", process.platform === "win32" ? "tauri.cmd" : "tauri");
  rmSync(tauriPath, { force: true });

  const report = checkDevEnvironment({ cwd: root, run: fakeRun() });
  const tauri = report.results.find((result) => result.name === "Tauri CLI");

  assert.equal(report.ready, false);
  assert.equal(tauri.available, false);
  assert.match(tauri.recover, /@tauri-apps\/cli/);
});
