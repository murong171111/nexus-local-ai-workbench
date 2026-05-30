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

test("scanPublicData checks publishable web and macOS metadata assets", () => {
  const root = mkdtempSync(path.join(tmpdir(), "nexus-public-data-"));
  writeFileSync(path.join(root, "index.html"), "<!-- /Users/" + "alice/private -->");
  writeFileSync(path.join(root, "styles.css"), "/* TOKEN" + "=abc123 */");
  writeFileSync(path.join(root, "Info.plist"), "<string>/home/" + "alice/private</string>");

  assert.deepEqual(scanPublicData(root), [
    {
      file: "Info.plist",
      line: 1,
      name: "private Linux home path",
      value: "/home/" + "alice/"
    },
    {
      file: "index.html",
      line: 1,
      name: "private macOS home path",
      value: "/Users/" + "alice/"
    },
    {
      file: "styles.css",
      line: 1,
      name: "secret-like assignment",
      value: "TOKEN" + "=abc123"
    }
  ]);
});

test("scanPublicData skips generated and dependency directories", () => {
  const root = mkdtempSync(path.join(tmpdir(), "nexus-public-data-"));
  mkdirSync(path.join(root, ".build"));
  mkdirSync(path.join(root, ".cache"));
  mkdirSync(path.join(root, ".swiftpm"));
  mkdirSync(path.join(root, ".vite"));
  mkdirSync(path.join(root, "node_modules"));
  mkdirSync(path.join(root, "dist"));
  mkdirSync(path.join(root, "native", "Nexus", ".build"), { recursive: true });
  writeFileSync(path.join(root, ".build", "private.md"), "/Users/" + "alice/private");
  writeFileSync(path.join(root, ".cache", "private.md"), "/Users/" + "alice/private");
  writeFileSync(path.join(root, ".swiftpm", "private.md"), "/Users/" + "alice/private");
  writeFileSync(path.join(root, ".vite", "private.md"), "/Users/" + "alice/private");
  writeFileSync(path.join(root, "node_modules", "private.md"), "/Users/" + "alice/private");
  writeFileSync(path.join(root, "dist", "private.md"), "TOKEN" + "=abc123");
  writeFileSync(path.join(root, "native", "Nexus", ".build", "debug.yaml"), "/Users/" + "alice/private");

  assert.deepEqual(scanPublicData(root), []);
});
