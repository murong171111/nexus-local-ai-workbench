#!/usr/bin/env node

import { existsSync, mkdirSync, unlinkSync } from "node:fs";
import net from "node:net";
import os from "node:os";
import path from "node:path";
import { pathToFileURL } from "node:url";
import {
  appendAgentEvent,
  defaultAgentEventsRoot,
  helpText as helperHelpText
} from "./nexus-agent-event.mjs";

export function defaultAgentBridgeSocketPath(env = process.env) {
  if (env.NEXUS_AGENT_BRIDGE_SOCKET?.trim()) {
    return expandHome(env.NEXUS_AGENT_BRIDGE_SOCKET.trim());
  }
  return path.join(defaultAgentEventsRoot(env), "agent-bridge.sock");
}

export function parseAgentBridgeArgs(argv, env = process.env) {
  const options = {
    eventsRoot: defaultAgentEventsRoot(env),
    socketPath: defaultAgentBridgeSocketPath(env),
    help: false
  };

  for (let index = 0; index < argv.length; index += 1) {
    const arg = argv[index];
    const nextValue = () => {
      index += 1;
      if (index >= argv.length) throw new Error(`${arg} requires a value`);
      return argv[index];
    };

    switch (arg) {
      case "--events-root":
        options.eventsRoot = expandHome(nextValue());
        break;
      case "--socket":
        options.socketPath = expandHome(nextValue());
        break;
      case "--help":
      case "-h":
        options.help = true;
        break;
      default:
        throw new Error(`Unknown argument: ${arg}`);
    }
  }

  return options;
}

export function startAgentBridgeServer(options = {}) {
  const eventsRoot = options.eventsRoot ?? defaultAgentEventsRoot();
  const socketPath = options.socketPath ?? defaultAgentBridgeSocketPath();
  const append = options.append ?? appendAgentEvent;
  const onEvent = options.onEvent ?? (() => {});
  const onError = options.onError ?? (() => {});
  const handleLine = createAgentBridgeLineHandler({ eventsRoot, append, onEvent, onError });
  const server = net.createServer((connection) => {
    connection.setEncoding("utf8");
    let buffer = "";

    connection.on("data", (chunk) => {
      buffer += chunk;
      const lines = buffer.split(/\r?\n/u);
      buffer = lines.pop() ?? "";

      for (const line of lines) {
        if (!line.trim()) continue;
        connection.write(`${JSON.stringify(handleLine(line))}\n`);
      }
    });
  });

  mkdirSync(path.dirname(socketPath), { recursive: true });
  if (process.platform !== "win32" && existsSync(socketPath)) {
    unlinkSync(socketPath);
  }

  server.listen(socketPath);
  return { server, socketPath, eventsRoot };
}

export function createAgentBridgeLineHandler(options = {}) {
  const eventsRoot = options.eventsRoot ?? defaultAgentEventsRoot();
  const append = options.append ?? appendAgentEvent;
  const onEvent = options.onEvent ?? (() => {});
  const onError = options.onError ?? (() => {});

  return (line) => {
    try {
      const response = append(eventsRoot, JSON.parse(line));
      onEvent(response.event);
      return { ok: true, event: response.event };
    } catch (error) {
      const message = error instanceof Error ? error.message : String(error);
      onError(error);
      return { ok: false, error: message };
    }
  };
}

export function helpText() {
  return `Usage: nexus-agent-bridge-server [options]

Starts a local Unix socket bridge that accepts one JSON event per line and
appends each event to the same Nexus agent event JSONL store used by the hook helper.

Options:
  --events-root <path>  Override agent event storage root.
  --socket <path>       Unix socket path. Defaults beside agent-events.jsonl.
  --help                Show this message.

Accepted event fields match the hook helper:

${helperHelpText()}`;
}

export function runAgentBridgeCli(argv = process.argv.slice(2), env = process.env) {
  try {
    const options = parseAgentBridgeArgs(argv, env);
    if (options.help) {
      process.stdout.write(helpText());
      return 0;
    }
    const { server, socketPath } = startAgentBridgeServer(options);
    process.stdout.write(`Nexus agent bridge listening on ${socketPath}\n`);
    process.on("SIGTERM", () => server.close(() => process.exit(0)));
    process.on("SIGINT", () => server.close(() => process.exit(0)));
    return undefined;
  } catch (error) {
    process.stderr.write(`Nexus agent bridge failed: ${error instanceof Error ? error.message : String(error)}\n`);
    return 1;
  }
}

function expandHome(value) {
  if (value === "~") return os.homedir();
  if (value.startsWith("~/")) return path.join(os.homedir(), value.slice(2));
  return value;
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  const code = runAgentBridgeCli();
  if (typeof code === "number") process.exitCode = code;
}
