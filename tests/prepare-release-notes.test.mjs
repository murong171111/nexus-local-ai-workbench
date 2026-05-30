import assert from "node:assert/strict";
import test from "node:test";
import { extractReleaseNotes } from "../scripts/prepare-release-notes.mjs";

test("extractReleaseNotes returns only the requested changelog section", () => {
  const notes = extractReleaseNotes(`# Changelog

## [Unreleased]

### Added

- New release helper.

### Fixed

- Preview packaging note.

## [0.1.0-alpha] - 2026-05-26

### Added

- Initial release.
`);

  assert.match(notes, /^# Nexus Unreleased Release Notes/u);
  assert.match(notes, /New release helper/u);
  assert.match(notes, /Preview packaging note/u);
  assert.doesNotMatch(notes, /Initial release/u);
});

test("extractReleaseNotes can target a dated version section", () => {
  const notes = extractReleaseNotes(`# Changelog

## [Unreleased]

### Added

- Work in progress.

## [0.1.1-alpha] - 2026-05-30

### Added

- Tagged release note.
`, { section: "0.1.1-alpha" });

  assert.match(notes, /Tagged release note/u);
  assert.doesNotMatch(notes, /Work in progress/u);
});

test("extractReleaseNotes rejects empty release-note sections", () => {
  assert.throws(
    () => extractReleaseNotes("# Changelog\n\n## [Unreleased]\n\n### Added\n\n## [0.1.0-alpha]\n\n- Initial.\n"),
    /does not contain release-note bullets/u
  );
});
