#!/usr/bin/env node

import { Buffer } from "node:buffer";
import { spawnSync } from "node:child_process";
import { existsSync, readFileSync } from "node:fs";
import { request as httpRequest } from "node:http";
import { homedir, hostname } from "node:os";
import { join } from "node:path";
import process from "node:process";
import { setTimeout as sleep } from "node:timers/promises";
import { parseArgs } from "node:util";

async function readCodexActivity(socketPath, linkedSessions) {
  const socket = new WebSocket("ws://localhost/", {
    dispatcher: {
      dispatch(options, handler) {
        const request = httpRequest({
          socketPath,
          path: options.path,
          method: options.method,
          headers: {
            ...options.headers,
            Connection: "Upgrade",
            Upgrade: options.upgrade,
          },
        });
        request.once("upgrade", (response, connection, head) => {
          if (head.length) connection.unshift(head);
          handler.onUpgrade(
            response.statusCode,
            response.rawHeaders.map((value) => Buffer.from(value)),
            connection,
          );
        });
        request.once("response", (response) => {
          response.resume();
          handler.onError(
            new Error(`Codex socket returned HTTP ${response.statusCode}`),
          );
        });
        request.once("error", (error) => handler.onError(error));
        request.setTimeout(5_000, () =>
          request.destroy(new Error("Codex socket timed out")),
        );
        request.end();
        return true;
      },
    },
  });

  let nextId = 0;
  const pending = new Map();
  const send = (value) => socket.send(JSON.stringify(value));
  const rpc = (method, params) =>
    new Promise((resolve, reject) => {
      const id = ++nextId;
      pending.set(id, { resolve, reject });
      send({ id, method, params });
    });
  socket.addEventListener("message", ({ data }) => {
    const message = JSON.parse(data);
    const request = pending.get(message.id);
    if (!request) return;
    pending.delete(message.id);
    if (message.error)
      request.reject(new Error(`Codex rejected request ${message.id}`));
    else request.resolve(message.result);
  });
  const read = new Promise((resolve, reject) => {
    socket.addEventListener("open", () => resolve(), { once: true });
    socket.addEventListener(
      "error",
      () => reject(new Error("Cannot connect to the Codex app server")),
      { once: true },
    );
  }).then(async () => {
    await rpc("initialize", {
      clientInfo: {
        name: "workline_activity",
        title: "Workline activity",
        version: "1",
      },
    });
    send({ method: "initialized" });
    const { data: ids } = await rpc("thread/loaded/list", {});
    const threads = await Promise.all(
      ids.map(async (threadId) => {
        const { thread } = await rpc("thread/read", {
          threadId,
          includeTurns: false,
        });
        return thread;
      }),
    );
    const working = threads
      .filter(
        ({ status }) => status.type === "active" && !status.activeFlags?.length,
      )
      .map(({ id }) => id)
      .sort();
    const known = new Set(ids);
    const unknown = [...new Set(linkedSessions.map(({ id }) => id))].filter((id) => !known.has(id));
    await Promise.all(unknown.map(async (id) => {
      const result = await rpc("thread/read", { threadId: id, includeTurns: false }).catch(() => null);
      if (result?.thread?.id === id) known.add(id);
    }));
    const hostIds = new Set(linkedSessions.filter(({ id }) => known.has(id)).map(({ hostId }) => hostId));
    return { working, hostId: hostIds.size === 1 ? [...hostIds][0] : undefined };
  });
  let timer;
  try {
    return await Promise.race([
      read,
      new Promise((_, reject) => {
        timer = setTimeout(
          () => reject(new Error("Codex activity read timed out")),
          10_000,
        );
      }),
    ]);
  } finally {
    clearTimeout(timer);
    socket.close();
  }
}

function workline(helper, path, payload) {
  const transport = `
import json, sys
from uuid import uuid4
sys.path.insert(0, sys.argv[1])
from api import request
try:
    path = sys.argv[2]
    result = request(path, None if path == '/api/work' else str(uuid4()))
    if path == '/api/work':
        result = [dict(id=s['id'], hostId=s['hostId']) for item in result['work']
                  if item['stage'] == 'Building' for s in item['sessions']]
    print(json.dumps(result))
except Exception:
    sys.exit(1)
`;
  const result = spawnSync("python3", ["-B", "-c", transport, helper, path], {
    input: payload === undefined ? undefined : JSON.stringify(payload),
    encoding: "utf8",
    timeout: 45_000,
  });
  if (result.status !== 0) {
    throw new Error(
      "Workline activity request failed. Check the host's Workline access.",
    );
  }
  return JSON.parse(result.stdout);
}

const codexHome = process.env.CODEX_HOME ?? join(homedir(), ".codex");
const { values } = parseArgs({
  options: {
    socket: {
      type: "string",
      default: join(
        codexHome,
        "app-server-control",
        "app-server-control.sock",
      ),
    },
    source: { type: "string", default: hostname() },
    "host-id": { type: "string", default: process.env.WORKLINE_CODEX_HOST_ID },
    helper: {
      type: "string",
      default: join(homedir(), ".agents", "skills", "workline", "scripts"),
    },
    once: { type: "boolean" },
    "dry-run": { type: "boolean" },
  },
});

let lastWorking;
let lastReport = 0;
let discoverAfter = 0;
let previousError;
let hostId = values["host-id"];
while (true) {
  try {
    if (!existsSync(values.socket) && !values.once && !values["dry-run"]) {
      await sleep(15_000);
      continue;
    }
    let linked = [];
    if (!hostId && !values["dry-run"] && Date.now() >= discoverAfter) {
      discoverAfter = Date.now() + 60_000;
      const organizer = join(codexHome, "chat-organizer", "remote-config.json");
      if (existsSync(organizer))
        hostId = JSON.parse(readFileSync(organizer, "utf8")).hostId;
      if (!hostId) linked = workline(values.helper, "/api/work");
    }
    const activity = await readCodexActivity(values.socket, linked);
    const { working } = activity;
    hostId ??= activity.hostId;
    const observed_at = Date.now();
    if (values["dry-run"]) {
      console.log(
        JSON.stringify({
          working: working.length,
          currentSessionWorking: working.includes(process.env.CODEX_THREAD_ID),
        }),
      );
      break;
    }
    const list = JSON.stringify({ working, hostId });
    if (
      list !== lastWorking ||
      ((hostId || working.length > 0) &&
        observed_at - lastReport >= 30_000)
    ) {
      const result = workline(values.helper, "/api/session-activity", {
        source: values.source,
        host_id: hostId,
        observed_at,
        working,
      });
      if (result.accepted !== true) throw new Error("Workline rejected the activity timestamp");
      lastWorking = list;
      lastReport = observed_at;
    }
    previousError = undefined;
    if (values.once) break;
    await sleep(5_000);
  } catch (error) {
    if (previousError !== error.message) console.error(error.message);
    previousError = error.message;
    if (values.once || values["dry-run"]) {
      process.exitCode = 1;
      break;
    }
    await sleep(15_000);
  }
}
