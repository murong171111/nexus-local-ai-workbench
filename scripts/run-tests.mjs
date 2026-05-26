import { execFileSync } from "node:child_process";
import { readdirSync, rmSync } from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

const root = path.resolve(fileURLToPath(new URL("..", import.meta.url)));
const tsc = path.join(root, "node_modules", ".bin", process.platform === "win32" ? "tsc.cmd" : "tsc");

rmSync(path.join(root, ".tmp-tests"), { recursive: true, force: true });
execFileSync(tsc, ["-p", "tsconfig.test.json"], { cwd: root, stdio: "inherit" });

const testFiles = readdirSync(path.join(root, "tests"))
  .filter((file) => file.endsWith(".test.mjs"))
  .map((file) => path.join("tests", file));

execFileSync(process.execPath, ["--test", ...testFiles], { cwd: root, stdio: "inherit" });
