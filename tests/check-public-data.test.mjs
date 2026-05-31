import assert from "node:assert/strict";
import { mkdtempSync, mkdirSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import test from "node:test";
import { scanPublicData } from "../scripts/check-public-data.mjs";

test("scanPublicData allows documented sample paths", () => {
  const root = mkdtempSync(path.join(tmpdir(), "nexus-public-data-"));
  writeFileSync(path.join(root, "README.md"), "Use /Users/example/ks_project/workspaces or ~/ks_project/workspaces.");

  assert.deepEqual(scanPublicData(root), []);
});

test("scanPublicData reports private paths with file and line context", () => {
  const root = mkdtempSync(path.join(tmpdir(), "nexus-public-data-"));
  const privateRoot = "/Users/" + "alice/";
  writeFileSync(path.join(root, "sample.json"), `{\n  "path": "${"/Users/" + "alice/private/workspace"}"\n}\n`);

  assert.deepEqual(scanPublicData(root), [
    {
      file: "sample.json",
      line: 2,
      name: "private macOS home path",
      value: privateRoot
    }
  ]);
});

test("scanPublicData skips generated and dependency directories", () => {
  const root = mkdtempSync(path.join(tmpdir(), "nexus-public-data-"));
  mkdirSync(path.join(root, ".build"));
  mkdirSync(path.join(root, "native"));
  mkdirSync(path.join(root, "native", "Nexus"));
  mkdirSync(path.join(root, "native", "Nexus", ".build"));
  mkdirSync(path.join(root, ".cache"));
  mkdirSync(path.join(root, ".swiftpm"));
  mkdirSync(path.join(root, "node_modules"));
  mkdirSync(path.join(root, "dist"));
  writeFileSync(path.join(root, ".build", "private.md"), "/Users/" + "alice/private");
  writeFileSync(path.join(root, "native", "Nexus", ".build", "description.json"), "/Users/" + "alice/private");
  writeFileSync(path.join(root, ".cache", "vite.json"), "/Users/" + "alice/private");
  writeFileSync(path.join(root, ".swiftpm", "configuration"), "/Users/" + "alice/private");
  writeFileSync(path.join(root, "node_modules", "private.md"), "/Users/" + "alice/private");
  writeFileSync(path.join(root, "dist", "private.md"), "TOKEN" + "=abc123");

  assert.deepEqual(scanPublicData(root), []);
});
