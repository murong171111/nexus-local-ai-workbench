#!/usr/bin/env node

import { appendFileSync, mkdirSync, readFileSync } from "node:fs";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";

const EVENT_FILE = "agent-events.jsonl";

export function defaultAgentEventsRoot(env = process.env, platform = process.platform) {
  if (env.NEXUS_AGENT_EVENTS_ROOT?.trim()) {
    return expandHome(env.NEXUS_AGENT_EVENTS_ROOT.trim());
  }

  if (platform === "darwin") {
    return path.join(os.homedir(), "Library", "Application Support", "com.ks.nexus", "agent-events");
  }

  return path.join(os.homedir(), ".nexus", "agent-events");
}

export function parseAgentEventArgs(argv, env = process.env) {
  const options = {
    eventsRoot: defaultAgentEventsRoot(env),
    strict: false,
    help: false
  };
  const event = {
    source: "",
    sessionId: "",
    workspaceFolder: undefined,
    kind: "",
    title: "",
    summary: "",
    severity: "",
    metadata: {}
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const nextValue = () => {
      index += 1;
      if (index >= argv.length) {
        throw new Error(`${arg} requires a value`);
      }
      return argv[index];
    };

    switch (arg) {
      case "--events-root":
        options.eventsRoot = expandHome(nextValue());
        break;
      case "--source":
        event.source = nextValue();
        break;
      case "--session-id":
        event.sessionId = nextValue();
        break;
      case "--workspace-folder":
        event.workspaceFolder = nextValue();
        break;
      case "--kind":
        event.kind = nextValue();
        break;
      case "--title":
        event.title = nextValue();
        break;
      case "--summary":
        event.summary = nextValue();
        break;
      case "--severity":
        event.severity = nextValue();
        break;
      case "--metadata":
        Object.assign(event.metadata, parseMetadataPair(nextValue()));
        break;
      case "--metadata-json":
        Object.assign(event.metadata, parseMetadataJson(nextValue()));
        break;
      case "--input-json":
        mergeEvent(event, JSON.parse(nextValue()));
        break;
      case "--stdin":
        mergeEvent(event, JSON.parse(readFileSync(0, "utf8")));
        break;
      case "--strict":
        options.strict = true;
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return { event, options };
}

export function buildAgentEvent(input, now = new Date()) {
  const source = nonEmpty(input.source, "agent");
  const sessionId = nonEmpty(input.sessionId ?? input.session_id, "unknown-session");
  const kind = nonEmpty(input.kind, "event");
  const timestamp = now.toISOString();

  return {
    id: agentEventId(source, sessionId, kind, now),
    timestamp,
    source,
    sessionId,
    workspaceFolder: normalizeOptional(input.workspaceFolder ?? input.workspace_folder),
    kind,
    title: nonEmpty(input.title, "Agent event"),
    summary: nonEmpty(input.summary, "No summary provided"),
    severity: nonEmpty(input.severity, "info"),
    metadata: normalizeMetadata(input.metadata)
  };
}

export function appendAgentEvent(eventsRoot, input, now = new Date()) {
  const event = buildAgentEvent(input, now);
  mkdirSync(eventsRoot, { recursive: true });
  const filePath = path.join(eventsRoot, EVENT_FILE);
  appendFileSync(filePath, `${JSON.stringify(event)}\n`, "utf8");
  return { path: filePath, event };
}

export function helpText() {
  return `Usage: nexus-agent-event [options]

Options:
  --events-root <path>       Override agent event storage root.
  --source <name>            Agent source, for example codex.
  --session-id <id>          Agent session or thread id.
  --workspace-folder <name>  Optional Nexus workspace folder.
  --kind <kind>              Event kind: prompt, question, permission, tool_use, status.
  --title <text>             Short event title.
  --summary <text>           Human-readable event summary.
  --severity <level>         info, warning, or error.
  --metadata <key=value>     Add metadata. Can be repeated.
  --metadata-json <json>     Add metadata object.
  --input-json <json>        Merge event fields from JSON.
  --stdin                    Read event JSON from stdin.
  --strict                   Exit non-zero on failure. Default is fail-open.
  --help                     Show this message.
`;
}

export function runAgentEventCli(argv = process.argv.slice(2), env = process.env) {
  try {
    const { event, options } = parseAgentEventArgs(argv, env);
    if (options.help) {
      process.stdout.write(helpText());
      return 0;
    }
    const response = appendAgentEvent(options.eventsRoot, event);
    process.stdout.write(`${JSON.stringify(response)}\n`);
    return 0;
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    process.stderr.write(`Nexus agent event helper skipped: ${message}\n`);
    return argv.includes("--strict") ? 1 : 0;
  }
}

function expandHome(value) {
  if (value === "~") {
    return os.homedir();
  }
  if (value.startsWith("~/")) {
    return path.join(os.homedir(), value.slice(2));
  }
  return value;
}

function parseMetadataPair(value) {
  const separator = value.indexOf("=");
  if (separator <= 0) {
    throw new Error("--metadata expects key=value");
  }
  return { [value.slice(0, separator)]: value.slice(separator + 1) };
}

function parseMetadataJson(value) {
  const parsed = JSON.parse(value);
  if (!parsed || Array.isArray(parsed) || typeof parsed !== "object") {
    throw new Error("--metadata-json expects an object");
  }
  return normalizeMetadata(parsed);
}

function mergeEvent(target, input) {
  if (!input || Array.isArray(input) || typeof input !== "object") {
    throw new Error("input event JSON must be an object");
  }

  const normalized = {
    source: input.source,
    sessionId: input.sessionId ?? input.session_id,
    workspaceFolder: input.workspaceFolder ?? input.workspace_folder,
    kind: input.kind,
    title: input.title,
    summary: input.summary,
    severity: input.severity
  };

  for (const [key, value] of Object.entries(normalized)) {
    if (value !== undefined) {
      target[key] = value;
    }
  }
  if (input.metadata !== undefined) {
    target.metadata = { ...target.metadata, ...normalizeMetadata(input.metadata) };
  }
}

function normalizeMetadata(metadata) {
  if (!metadata || Array.isArray(metadata) || typeof metadata !== "object") {
    return {};
  }
  return Object.fromEntries(
    Object.entries(metadata).map(([key, value]) => [String(key), value == null ? "" : String(value)])
  );
}

function nonEmpty(value, fallback) {
  const trimmed = String(value ?? "").trim();
  return trimmed === "" ? fallback : trimmed;
}

function normalizeOptional(value) {
  const trimmed = String(value ?? "").trim();
  return trimmed === "" ? undefined : trimmed;
}

function agentEventId(source, sessionId, kind, now) {
  return [
    "agent",
    sanitizeIdSegment(source),
    sanitizeIdSegment(sessionId),
    sanitizeIdSegment(kind),
    now.getTime()
  ].join("-");
}

function sanitizeIdSegment(value) {
  const sanitized = String(value)
    .split("")
    .map((character) => (/^[a-zA-Z0-9_-]$/.test(character) ? character : "-"))
    .join("")
    .replace(/^-+|-+$/g, "");
  return sanitized || "event";
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  process.exitCode = runAgentEventCli();
}
