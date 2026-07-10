import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const packageJson = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"));
const ciWorkflow = readFileSync(new URL("../.github/workflows/ci.yml", import.meta.url), "utf8");

test("standard verification and CI run the Native Swift test suite", () => {
  assert.equal(packageJson.scripts["native:test"], "swift test --disable-sandbox --package-path native/Nexus");
  assert.equal(packageJson.scripts["native:build"], "swift build --disable-sandbox --package-path native/Nexus");
  assert.match(packageJson.scripts.verify, /npm run native:test/u);
  assert.match(ciWorkflow, /run: npm run native:test/u);
});
