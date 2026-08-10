#!/usr/bin/env node
/**
 * driving-mode — speak a line of text aloud, one message at a time.
 *
 * Synthesizes with OpenAI TTS when a key resolves, falls back to the macOS
 * `say` voice when it doesn't. Callers background it with `&` and never wait,
 * so the ONE thing this script must guarantee is that two messages fired close
 * together do not play on top of each other. See the playback mutex below.
 *
 *   node driving-mode.mjs "Build is green, three tests added." &
 *
 * Zero npm dependencies — nothing outside `node:` builtins. Keep it that way.
 *
 * Environment:
 *   OPENAI_API_KEY   api key (highest precedence)
 *   TTS_KEY_FILE     path to a file containing the key
 *   TTS_MODEL        default `tts-1`
 *   TTS_VOICE        default `nova`
 *   TTS_NO_QUEUE=1   skip the playback queue entirely
 *   TTS_INTERRUPT=1  stop what's playing and jump the queue
 */
import { spawnSync } from "node:child_process";
import { mkdirSync, readFileSync, rmSync, statSync, unlinkSync, writeFileSync } from "node:fs";
import { homedir, tmpdir } from "node:os";
import { join } from "node:path";

const text = process.argv.slice(2).join(" ").trim();
if (!text || text === "--help" || text === "-h") {
  console.error('usage: driving-mode.mjs "<text to speak>"');
  process.exit(text ? 0 : 1);
}

// ---------------------------------------------------------------------------
// Playback mutex. DO NOT REMOVE.
//
// The original guidance was "background it with `&`, never block" — right for
// one message per turn, wrong across rapid consecutive turns. On 2026-08-10,
// with a driving user, THREE voice messages played SIMULTANEOUSLY and he
// understood none of them. Audio has no scrollback; a lost message is lost.
//
// Only PLAYBACK is serialized. Synthesis (the slow network call) still runs in
// parallel, so queued messages play back-to-back with no dead air — measured at
// 10s for three simultaneous fires vs ~4s for one, i.e. queued, not stalled.
//
// The lock is an atomic `mkdir`, with a stale-lock reclaim (a killed process
// can't strand the queue), a hard wait ceiling (it can never deadlock), and
// signal handlers that release on the way out.
// ---------------------------------------------------------------------------
const LOCK = join(tmpdir(), "claude-driving-mode.lock");
const STALE_MS = 5 * 60 * 1000;
const MAX_WAIT_MS = 10 * 60 * 1000;

let held = false;

const releaseLock = () => {
  held = false;
  try {
    rmSync(LOCK, { recursive: true, force: true });
  } catch {}
};

async function acquireLock() {
  if (held) return; // reentrant: the fallback path may ask twice
  if (process.env.TTS_NO_QUEUE === "1") return;
  if (process.env.TTS_INTERRUPT === "1") {
    spawnSync("pkill", ["-f", "afplay"]);
    spawnSync("pkill", ["-x", "say"]);
    releaseLock();
  }
  const start = Date.now();
  for (;;) {
    try {
      mkdirSync(LOCK); // atomic — succeeds for exactly one process
      held = true;
      return;
    } catch {}
    try {
      // Reclaim a lock orphaned by a killed process.
      if (Date.now() - statSync(LOCK).mtimeMs > STALE_MS) {
        releaseLock();
        continue;
      }
    } catch {}
    if (Date.now() - start > MAX_WAIT_MS) {
      releaseLock(); // never deadlock the queue
      return;
    }
    await new Promise((r) => setTimeout(r, 150));
  }
}

for (const sig of ["SIGINT", "SIGTERM", "SIGHUP"]) {
  process.on(sig, () => {
    releaseLock();
    process.exit(130);
  });
}

const finish = (code) => {
  releaseLock();
  process.exit(code ?? 0);
};

const sayFallback = async () => {
  await acquireLock();
  const r = spawnSync("say", ["-v", "Samantha", "-r", "195", text], { stdio: "inherit" });
  finish(r.status ?? 0);
};

// ---------------------------------------------------------------------------
// Key resolution. Nothing here is project-specific — no repo path, no product
// name. Env first, then an explicit file, then a neutral shared default.
// The key file lives outside every repo and is never committed.
// ---------------------------------------------------------------------------
const keyFile = process.env.TTS_KEY_FILE || join(homedir(), ".config", "claude-tts", "key");
let apiKey = process.env.OPENAI_API_KEY;
if (!apiKey) {
  try {
    apiKey = readFileSync(keyFile, "utf8").trim();
  } catch {}
}
if (!apiKey) {
  await sayFallback();
}

const model = process.env.TTS_MODEL ?? "tts-1";
const voice = process.env.TTS_VOICE ?? "nova";

try {
  // Synthesize BEFORE taking the lock — holding it across the network call
  // would stall the queue for no reason.
  const res = await fetch("https://api.openai.com/v1/audio/speech", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({ model, voice, input: text, response_format: "mp3" }),
  });
  if (!res.ok) {
    console.error(`openai tts ${res.status}: ${await res.text()}`);
    await sayFallback();
  }
  const buf = Buffer.from(await res.arrayBuffer());
  const path = join(tmpdir(), `tts-${Date.now()}-${process.pid}.mp3`);
  writeFileSync(path, buf);

  await acquireLock();
  const r = spawnSync("afplay", [path], { stdio: "inherit" });
  try {
    unlinkSync(path);
  } catch {}
  finish(r.status ?? 0);
} catch (err) {
  console.error(`tts error: ${err?.message ?? err}`);
  await sayFallback();
}
