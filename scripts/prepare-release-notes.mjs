import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(fileURLToPath(new URL("..", import.meta.url)));

export function extractReleaseNotes(changelogText, options = {}) {
  const section = options.section ?? "Unreleased";
  const lines = changelogText.split(/\r?\n/u);
  const startIndex = lines.findIndex((line) => isVersionHeading(line, section));

  if (startIndex === -1) {
    throw new Error(`CHANGELOG.md does not contain a "${section}" section.`);
  }

  const endIndex = lines.findIndex((line, index) => index > startIndex && /^##\s+/u.test(line));
  const bodyLines = lines.slice(startIndex + 1, endIndex === -1 ? undefined : endIndex);
  const body = bodyLines.join("\n").trim();

  if (!body || !/-\s+\S/u.test(body)) {
    throw new Error(`CHANGELOG.md "${section}" section does not contain release-note bullets.`);
  }

  return `# Nexus ${section} Release Notes\n\n${body}\n`;
}

function isVersionHeading(line, section) {
  const escaped = escapeRegExp(section);
  return new RegExp(`^##\\s+(?:\\[${escaped}\\]|${escaped})(?:\\s+-\\s+.*)?$`, "u").test(line.trim());
}

function escapeRegExp(value) {
  return value.replace(/[.*+?^${}()|[\]\\]/gu, "\\$&");
}

function parseArgs(argv) {
  const options = {
    changelog: path.join(root, "CHANGELOG.md"),
    out: null,
    section: "Unreleased"
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const value = argv[index + 1];
    if (arg === "--changelog" && value) {
      options.changelog = path.resolve(value);
      index += 1;
    } else if (arg === "--out" && value) {
      options.out = path.resolve(value);
      index += 1;
    } else if (arg === "--section" && value) {
      options.section = value;
      index += 1;
    } else {
      throw new Error(`Unknown or incomplete argument: ${arg}`);
    }
  }

  return options;
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  const changelog = readFileSync(options.changelog, "utf8");
  const notes = extractReleaseNotes(changelog, { section: options.section });

  if (options.out) {
    writeFileSync(options.out, notes);
    console.log(`Release notes written to ${path.relative(root, options.out)}`);
    return;
  }

  process.stdout.write(notes);
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
  try {
    main();
  } catch (error) {
    console.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
