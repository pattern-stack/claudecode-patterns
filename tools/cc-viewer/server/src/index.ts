/**
 * cc-viewer entry point.
 *
 * - Resolves a SQLite path under XDG_STATE_HOME / ~/.local/state/cc-viewer/
 * - Builds the Hono app, mounts the built viewer SPA from ../viewer/dist
 * - Serves on PORT (default 3993) via Bun.serve
 */

import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { createServer } from "./app.js";
import { EventStore } from "./event-store.js";
import { SSEBroadcaster } from "./sse-broadcaster.js";

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

function resolveStaticDir(): string | undefined {
  const dir = path.resolve(import.meta.dir, "../../viewer/dist");
  return existsSync(dir) ? dir : undefined;
}

const persistence = resolveEventStore();
const broadcaster = new SSEBroadcaster();
const staticDir = resolveStaticDir();

const app = createServer({
  eventStore: persistence.store,
  broadcaster,
  staticDir,
});

console.log("");
console.log("  cc-viewer");
console.log(`  url      http://localhost:${PORT}`);
console.log(`  storage  ${persistence.banner}`);
console.log(`  spa      ${staticDir ?? "not built — run `bun run build` from repo root"}`);
console.log("");

export default {
  port: PORT,
  fetch: app.fetch,
};
