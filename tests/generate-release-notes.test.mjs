import assert from "node:assert/strict";
import test from "node:test";
import { parseChangelogSections, releaseNotesFromChangelog } from "../scripts/generate-release-notes.mjs";

const changelog = `# Changelog

## [Unreleased]

### Added

- New bridge flow.

### Fixed

- Safer local validation.

## [0.1.0-alpha] - 2026-05-26

### Added

- Initial preview.
`;

test("parseChangelogSections reads version labels and release dates", () => {
  const sections = parseChangelogSections(changelog);

  assert.equal(sections.get("unreleased").label, "Unreleased");
  assert.equal(sections.get("0.1.0-alpha").releasedAt, "2026-05-26");
});

test("releaseNotesFromChangelog emits the Unreleased section by default", () => {
  const notes = releaseNotesFromChangelog(changelog);

  assert.match(notes, /^# Nexus Unreleased/);
  assert.match(notes, /New bridge flow/);
  assert.match(notes, /Safer local validation/);
  assert.doesNotMatch(notes, /Initial preview/);
});

test("releaseNotesFromChangelog accepts v-prefixed release tags", () => {
  const notes = releaseNotesFromChangelog(changelog, "v0.1.0-alpha");

  assert.match(notes, /^# Nexus 0\.1\.0-alpha/);
  assert.match(notes, /Release date: 2026-05-26/);
  assert.match(notes, /Initial preview/);
  assert.doesNotMatch(notes, /New bridge flow/);
});

test("releaseNotesFromChangelog reports available sections for missing versions", () => {
  assert.throws(
    () => releaseNotesFromChangelog(changelog, "v9.9.9"),
    /Available sections: Unreleased, 0\.1\.0-alpha/
  );
});
