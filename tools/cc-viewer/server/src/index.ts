/**
 * cc-viewer entry point.
 *
 * - Resolves a SQLite path under XDG_STATE_HOME / ~/.local/state/cc-viewer/
 * - Builds the Hono app — SPA assets are embedded at compile time via
 *   `scripts/codegen-static.ts` + `bun build --compile`.
 * - Serves on CC_VIEWER_PORT (else PORT, default 3993) via Bun.serve, and on CC_VIEWER_TLS_PORT (default 3443) over
 *   https when a certificate exists (`cc-viewer tls` makes one; CC_VIEWER_TLS_CERT / CC_VIEWER_TLS_KEY override).
 * - `cc-viewer pair` / `cc-viewer tls` run a command instead (cli.ts).
 */

import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { createServer } from "./app.js";
import { runCli } from "./cli.js";
import { Pairing } from "./pairing.js";
import { watchCommandSources } from "./command-watcher.js";
import { EventStore } from "./event-store.js";
import { sessionInputFromEnv } from "./input/index.js";
import { SSEBroadcaster } from "./sse-broadcaster.js";
import { STATIC_BUNDLE } from "./static-bundle.js";
import { voiceFromEnv } from "./voice/index.js";

const PORT = Number.parseInt(process.env.CC_VIEWER_PORT ?? process.env.PORT ?? "3993", 10);
// On the network by default; every request that isn't from this machine needs a paired device (pairing.ts).
// CC_VIEWER_HOST=127.0.0.1 keeps it on this machine only.
const HOST = process.env.CC_VIEWER_HOST ?? "0.0.0.0";
const STATE_DIR = path.join(process.env.XDG_STATE_HOME ?? path.join(homedir(), ".local", "state"), "cc-viewer");
const TLS_PORT = Number.parseInt(process.env.CC_VIEWER_TLS_PORT ?? "3443", 10);
const TLS_CERT = process.env.CC_VIEWER_TLS_CERT ?? path.join(STATE_DIR, "tls", "cert.pem");
const TLS_KEY = process.env.CC_VIEWER_TLS_KEY ?? path.join(STATE_DIR, "tls", "key.pem");

// A command for the host's terminal, not the server.
const args = Bun.argv.slice(2);
if (args.length) process.exit(await runCli(args, { port: PORT, tlsCert: TLS_CERT, tlsKey: TLS_KEY, tlsPort: TLS_PORT }));

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

// Live-update the slash-command palette when plugin config changes on disk.
watchCommandSources(broadcaster);

const pairing = new Pairing(STATE_DIR);
// Adapters are bound here, once: how replies reach a terminal, and the voice module that speaks answers.
const input = sessionInputFromEnv();
const voice = voiceFromEnv({
  stateDir: path.join(STATE_DIR, "voice"),
  input,
  sessions: persistence.store,
  log: (...a: unknown[]) => console.log(new Date().toLocaleTimeString(), ...a),
});
if (voice) broadcaster.subscribe(voice.onViewerEvent);
const app = createServer({
  eventStore: persistence.store,
  broadcaster,
  pairing,
  input,
  voice,
  port: PORT,
});

// https for other devices: browsers give the microphone only to secure pages, and the pairing key and cookie stop
// crossing the network in clear text. Same app, same device check; only the transport differs.
let tlsBanner = "off (no certificate; `cc-viewer tls` makes one)";
if (TLS_PORT > 0 && existsSync(TLS_CERT) && existsSync(TLS_KEY)) {
  try {
    Bun.serve({
      hostname: HOST,
      port: TLS_PORT,
      tls: { cert: Bun.file(TLS_CERT), key: Bun.file(TLS_KEY) },
      fetch: app.fetch,
      idleTimeout: 0,
    });
    tlsBanner = `https://<this machine>:${TLS_PORT} (cert ${TLS_CERT})`;
  } catch (err) {
    tlsBanner = `failed: ${(err as Error).message}`;
  }
} else if (TLS_PORT <= 0) tlsBanner = "off (CC_VIEWER_TLS_PORT=0)";

const spaAssetCount = Object.keys(STATIC_BUNDLE).length;

console.log("");
console.log("  cc-viewer");
console.log(`  url      http://localhost:${PORT} (bound to ${HOST})`);
console.log(`  https    ${tlsBanner}`);
console.log(`  pairing  off-host devices pair at /pair (key in ${path.join(STATE_DIR, "viewer-key")})`);
console.log(`  storage  ${persistence.banner}`);
console.log(`  input    ${input.name}`);
console.log(`  voice    ${voice ? `http://localhost:${PORT}/voice` : "off (CC_VIEWER_VOICE=0)"}`);
console.log(
  `  spa      ${spaAssetCount > 0 ? `${spaAssetCount} embedded asset(s)` : "not bundled — run vite dev separately"}`,
);
console.log("");

export default {
  hostname: HOST,
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
