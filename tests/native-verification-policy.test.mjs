import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";

const packageJson = JSON.parse(readFileSync(new URL("../package.json", import.meta.url), "utf8"));
const ciWorkflow = readFileSync(new URL("../.github/workflows/ci.yml", import.meta.url), "utf8");
const releaseProcess = readFileSync(new URL("../docs/release-process.md", import.meta.url), "utf8");

test("standard verification and CI run the Native Swift test suite", () => {
  assert.equal(packageJson.scripts["native:test"], "swift test --disable-sandbox --package-path native/Nexus");
  assert.equal(packageJson.scripts["native:build"], "swift build --disable-sandbox --package-path native/Nexus");
  assert.match(packageJson.scripts.verify, /npm run native:test/u);
  assert.match(ciWorkflow, /run: npm run native:test/u);
});

test("Native M1 has a stable real-lifecycle acceptance command", () => {
  assert.match(
    packageJson.scripts["native:m1-acceptance"],
    /testNativeStoresCanProveEndToEndWorkspaceLifecycle/u,
  );
  assert.match(
    packageJson.scripts["native:m1-acceptance"],
    /testMainWorkflowAcceptanceEvidenceRequiresEveryM1Gate/u,
  );
  assert.match(releaseProcess, /npm run native:m1-acceptance/u);
});

test("feature-centered workflow has a stable real-files acceptance command", () => {
  assert.match(
    packageJson.scripts["native:feature-acceptance"],
    /testFeatureCenteredWorkflowPreservesDeliveryAndCrossSessionContext/u,
  );
  assert.match(releaseProcess, /npm run native:feature-acceptance/u);
});
