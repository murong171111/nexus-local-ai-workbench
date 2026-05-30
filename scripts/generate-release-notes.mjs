import { readFileSync, writeFileSync } from "node:fs";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const root = path.resolve(fileURLToPath(new URL("..", import.meta.url)));

export function parseChangelogSections(content) {
  const headingPattern = /^## \[([^\]]+)\](?:\s+-\s+([^\n]+))?\s*$/gm;
  const matches = [...content.matchAll(headingPattern)];
  const sections = new Map();

  for (let index = 0; index < matches.length; index += 1) {
    const match = matches[index];
    const next = matches[index + 1];
    const label = match[1].trim();
    const releasedAt = match[2]?.trim() ?? "";
    const bodyStart = (match.index ?? 0) + match[0].length;
    const bodyEnd = next?.index ?? content.length;
    const body = content.slice(bodyStart, bodyEnd).trim();
    sections.set(normalizeVersion(label), { label, releasedAt, body });
  }

  return sections;
}

export function releaseNotesFromChangelog(content, version = "Unreleased") {
  const normalized = normalizeVersion(version);
  const sections = parseChangelogSections(content);
  const section = sections.get(normalized);

  if (!section) {
    const available = [...sections.values()].map((item) => item.label).join(", ") || "none";
    throw new Error(`CHANGELOG.md does not contain a section for ${version}. Available sections: ${available}`);
  }

  if (!section.body) {
    throw new Error(`CHANGELOG.md section ${section.label} is empty.`);
  }

  return formatReleaseNotes(section);
}

function formatReleaseNotes(section) {
  const title = section.label === "Unreleased" ? "Nexus Unreleased" : `Nexus ${section.label}`;
  const date = section.releasedAt ? `\n\nRelease date: ${section.releasedAt}` : "";
  return `# ${title}${date}\n\n${section.body}\n`;
}

function normalizeVersion(value) {
  const trimmed = String(value).trim();
  return trimmed.toLowerCase() === "unreleased" ? "unreleased" : trimmed.replace(/^v/i, "");
}

function parseArgs(argv) {
  const options = {
    changelog: path.join(root, "CHANGELOG.md"),
    output: "",
    version: "Unreleased"
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const next = argv[index + 1];
    if ((arg === "--version" || arg === "-v") && next) {
      options.version = next;
      index += 1;
    } else if (arg === "--changelog" && next) {
      options.changelog = path.resolve(next);
      index += 1;
    } else if ((arg === "--output" || arg === "-o") && next) {
      options.output = path.resolve(next);
      index += 1;
    } else if (arg === "--help" || arg === "-h") {
      options.help = true;
    } else {
      throw new Error(`Unknown or incomplete argument: ${arg}`);
    }
  }

  return options;
}

function usage() {
  return [
    "Usage: npm run release:notes -- [--version <version>] [--output <file>]",
    "",
    "Examples:",
    "  npm run release:notes",
    "  npm run release:notes -- --version v0.1.0-alpha",
    "  npm run release:notes -- --version Unreleased --output release-notes.md"
  ].join("\n");
}

function main() {
  const options = parseArgs(process.argv.slice(2));
  if (options.help) {
    console.log(usage());
    return;
  }

  const content = readFileSync(options.changelog, "utf8");
  const notes = releaseNotesFromChangelog(content, options.version);

  if (options.output) {
    writeFileSync(options.output, notes);
    console.log(`Release notes written to ${options.output}`);
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
