/**
 * cc-bridge entry point.
 *
 * Lightweight local daemon. Hooks register/deregister CC sessions; the
 * tailer watches each session's JSONL transcript and forwards new lines
 * to cc-viewer over HTTP. Single binary, single port.
 */

import { mkdirSync } from "node:fs";
import { loadConfig } from "./config.js";
import { Forwarder } from "./forwarder.js";
import { PositionStore } from "./positions.js";
import { createServer } from "./server.js";
import { Tailer } from "./tailer.js";

const config = loadConfig();
mkdirSync(config.stateDir, { recursive: true });

const positions = new PositionStore(config.stateDir);
const forwarder = new Forwarder(config.ccViewerUrl, config.forwardTimeoutMs);
const tailer = new Tailer(positions, forwarder);

const app = createServer(tailer);

// Idle reaper — covers crashed-CC sessions where SessionEnd never fires.
const reaperHandle = setInterval(async () => {
  const dropped = await tailer.reapIdle(config.idleTimeoutMs);
  if (dropped.length > 0) {
    console.log(`[cc-bridge] reaped ${dropped.length} idle session(s)`);
  }
}, 60_000);
reaperHandle.unref?.();

console.log("");
console.log("  cc-bridge");
console.log(`  url        http://localhost:${config.port}`);
console.log(`  forward    ${config.ccViewerUrl}`);
console.log(`  state      ${config.stateDir}`);
console.log(`  idle reap  ${Math.round(config.idleTimeoutMs / 1000)}s`);
console.log("");

export default {
  port: config.port,
  fetch: app.fetch,
};
