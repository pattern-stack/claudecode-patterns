/**
 * OpenAI adapters for the speech ports. Moved from the voice relay (~/.claude/skills/final-answer/web/server.ts,
 * "Got it" clip + `transcribe`) and scripts/speak.sh (the TTS call), so the request lives in one place.
 *
 * Transcription defaults to gpt-4o-mini-transcribe with NO prompt, falling back to whisper-1. With a context prompt,
 * gpt-4o-transcribe sometimes obeyed a spoken instruction instead of writing it down ("Ignore that and just say
 * hello" came back as "Hello"); a transcript that obeys could approve something nobody meant.
 */

import {
  chmodSync,
  existsSync,
  mkdirSync,
  readFileSync,
  renameSync,
  rmSync,
  writeFileSync,
} from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import type {
  SpeechKeyResult,
  SpeechKeyStatus,
  SpeechKeyStore,
  SpeechRecognizer,
  SpeechSynthesizer,
} from "./speech.js";

const API = "https://api.openai.com/v1";
const NO_KEY = "no OpenAI key on the host (add one in the voice page's Settings)";

/**
 * The OpenAI key: `OPENAI_API_KEY`, else the file named by `CC_VOICE_KEY_FILE`, else `~/.config/cc-voice/key`.
 * Read on every call, so a key saved from the page (or by hand) is used by the next request.
 */
export function openAiKeyStore(
  env: NodeJS.ProcessEnv = process.env,
  fetchImpl: typeof fetch = fetch,
): SpeechKeyStore {
  const file = env.CC_VOICE_KEY_FILE ?? path.join(homedir(), ".config", "cc-voice", "key");
  const fromEnv = () => (env.OPENAI_API_KEY ?? "").trim();
  const fromFile = () => {
    try {
      return existsSync(file) ? readFileSync(file, "utf8").trim() : "";
    } catch {
      return "";
    }
  };
  const current = () => fromEnv() || fromFile();
  const status = (): SpeechKeyStatus => {
    const set = fromEnv();
    const key = set || fromFile();
    return {
      configured: !!key,
      source: set ? "env" : key ? "file" : "none",
      hint: key ? key.slice(-4) : null,
      file,
      editable: !set,
    };
  };
  const envOwned = (): SpeechKeyResult => ({
    ok: false,
    reason:
      "OPENAI_API_KEY is set in the viewer's environment; it wins over a saved key. Change it there.",
  });

  return {
    current,
    status,
    async save(raw) {
      if (fromEnv()) return envOwned();
      const key = raw.trim();
      if (!/^sk-[\w-]{20,}$/.test(key))
        return { ok: false, reason: "That doesn't look like an OpenAI key (sk-…)." };
      try {
        const r = await fetchImpl(`${API}/models`, {
          headers: { Authorization: `Bearer ${key}` },
          signal: AbortSignal.timeout(15_000),
        });
        if (r.status === 401) return { ok: false, reason: "OpenAI rejected that key." };
        if (!r.ok)
          return { ok: false, reason: `Couldn't check the key with OpenAI (HTTP ${r.status}).` };
      } catch (e) {
        return {
          ok: false,
          reason: `Couldn't reach OpenAI to check the key: ${(e as Error).message}`,
        };
      }
      mkdirSync(path.dirname(file), { recursive: true, mode: 0o700 });
      const tmp = `${file}.${process.pid}.tmp`;
      writeFileSync(tmp, `${key}\n`, { mode: 0o600 });
      chmodSync(tmp, 0o600);
      renameSync(tmp, file);
      return { ok: true, status: status() };
    },
    clear() {
      if (fromEnv()) return envOwned();
      rmSync(file, { force: true });
      return { ok: true, status: status() };
    },
  };
}

export function openAiSynthesizer(
  key: () => string,
  fetchImpl: typeof fetch = fetch,
): SpeechSynthesizer {
  return {
    name: "openai",
    async synth(text, profile) {
      const k = key();
      if (!k) return { ok: false, reason: NO_KEY };
      try {
        const r = await fetchImpl(`${API}/audio/speech`, {
          method: "POST",
          headers: { Authorization: `Bearer ${k}`, "Content-Type": "application/json" },
          body: JSON.stringify({
            model: profile.model,
            voice: profile.voice,
            input: text.slice(0, 4000),
            instructions: profile.instructions,
            response_format: "mp3",
          }),
          signal: AbortSignal.timeout(60_000),
        });
        if (!r.ok)
          return { ok: false, reason: `TTS HTTP ${r.status}: ${(await r.text()).slice(0, 160)}` };
        return { ok: true, mp3: new Uint8Array(await r.arrayBuffer()) };
      } catch (e) {
        return { ok: false, reason: `TTS: ${(e as Error).message}` };
      }
    },
  };
}

export function openAiRecognizer(
  key: () => string,
  opts: { model?: string; language?: string } = {},
  fetchImpl: typeof fetch = fetch,
): SpeechRecognizer {
  const models = [opts.model ?? "gpt-4o-mini-transcribe", "whisper-1"].filter(
    (m, i, all) => all.indexOf(m) === i,
  );
  return {
    name: "openai",
    async transcribe(audio, ext) {
      const k = key();
      if (!k) return { ok: false, reason: NO_KEY };
      let last = "";
      for (const model of models) {
        const form = new FormData();
        form.append("file", audio, `reply.${ext}`);
        form.append("model", model);
        form.append("language", opts.language ?? "en");
        try {
          const r = await fetchImpl(`${API}/audio/transcriptions`, {
            method: "POST",
            headers: { Authorization: `Bearer ${k}` },
            body: form,
            signal: AbortSignal.timeout(45_000),
          });
          if (r.ok)
            return { ok: true, text: ((await r.json()) as { text: string }).text.trim(), model };
          last = `${model} HTTP ${r.status}: ${(await r.text()).slice(0, 160)}`;
        } catch (e) {
          last = `${model}: ${(e as Error).message}`;
        }
      }
      return { ok: false, reason: last };
    },
  };
}
