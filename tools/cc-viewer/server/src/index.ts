/**
 * cc-viewer entry point.
 *
 * - Resolves a SQLite path under XDG_STATE_HOME / ~/.local/state/cc-viewer/
 * - Builds the Hono app — SPA assets are embedded at compile time via
 *   `scripts/codegen-static.ts` + `bun build --compile`.
 * - Serves on PORT (default 3993) via Bun.serve.
 */

import { mkdirSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { createServer } from "./app.js";
import { EventStore } from "./event-store.js";
import { SSEBroadcaster } from "./sse-broadcaster.js";
import { STATIC_BUNDLE } from "./static-bundle.js";

const PORT = Number.parseInt(process.env.PORT ?? "3993", 10);

function resolveEventStore(): { store?: EventStore; banner: string } {
  if (process.env.CC_VIEWER_PERSISTENCE === "0") {
    return { banner: "disabled (CC_VIEWER_PERSISTENCE=0)" };
  }

  const dbPath = resolveDbPath();
  mkdirSync(path.dirname(dbPath), { recursive: true });

  try {
    const store = new EventStore({ path: dbPath });
    return { store, banner: `${dbPath} (${store.count()} events)` };
  } catch (err) {
    return { banner: `disabled (EventStore init failed: ${(err as Error).message})` };
  }
}

function resolveDbPath(): string {
  const override = process.env.CC_VIEWER_DB;
  if (override) return path.resolve(override);
  const stateHome = process.env.XDG_STATE_HOME ?? path.join(homedir(), ".local", "state");
  return path.join(stateHome, "cc-viewer", "events.db");
}

const persistence = resolveEventStore();
const broadcaster = new SSEBroadcaster();

const app = createServer({
  eventStore: persistence.store,
  broadcaster,
});

const spaAssetCount = Object.keys(STATIC_BUNDLE).length;

console.log("");
console.log("  cc-viewer");
console.log(`  url      http://localhost:${PORT}`);
console.log(`  storage  ${persistence.banner}`);
console.log(
  `  spa      ${spaAssetCount > 0 ? `${spaAssetCount} embedded asset(s)` : "not bundled — run vite dev separately"}`,
);
console.log("");

export default {
  port: PORT,
  fetch: app.fetch,
  // SSE streams hold connections open indefinitely with bursty (or zero)
  // traffic. Bun's default 10s idle close would terminate them mid-flight
  // and trigger client reconnect storms (the dashboard "reconnecting…"
  // badge perpetually flashing). 0 disables idle reaping; the broadcaster
  // additionally emits keepalive pings every 15s so any intermediary
  // (proxy, browser) that has its own idle policy stays happy.
  idleTimeout: 0,
};
