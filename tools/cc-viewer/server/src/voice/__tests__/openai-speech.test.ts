import { afterEach, beforeEach, describe, expect, test } from "bun:test";
import { existsSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import path from "node:path";
import { openAiKeyStore, openAiRecognizer, openAiSynthesizer } from "../openai-speech.js";

const KEY = "sk-test-0123456789abcdefghijWXYZ";
let dir: string;
let file: string;
let checks: string[];
const okFetch = (async (_url: string, init?: RequestInit) => {
  checks.push(String((init?.headers as Record<string, string>).Authorization));
  return new Response("{}", { status: 200 });
}) as unknown as typeof fetch;
const rejectFetch = (async () => new Response("no", { status: 401 })) as unknown as typeof fetch;

beforeEach(() => {
  dir = mkdtempSync(path.join(tmpdir(), "voice-key-"));
  file = path.join(dir, "cfg", "key");
  checks = [];
});
afterEach(() => rmSync(dir, { recursive: true, force: true }));

describe("the key store", () => {
  test("no key: nothing configured, the file is where a key would go", () => {
    const s = openAiKeyStore({ CC_VOICE_KEY_FILE: file }, okFetch);
    expect(s.current()).toBe("");
    expect(s.status()).toEqual({
      configured: false,
      source: "none",
      hint: null,
      file,
      editable: true,
    });
  });

  test("save checks the key with OpenAI, writes it 0600, and the next read sees it", async () => {
    const s = openAiKeyStore({ CC_VOICE_KEY_FILE: file }, okFetch);
    const r = await s.save(`  ${KEY}\n`);
    expect(r).toMatchObject({
      ok: true,
      status: { configured: true, source: "file", hint: "WXYZ" },
    });
    expect(checks).toEqual([`Bearer ${KEY}`]);
    expect(readFileSync(file, "utf8").trim()).toBe(KEY);
    expect(statSync(file).mode & 0o777).toBe(0o600);
    expect(s.current()).toBe(KEY);
  });

  test("a key OpenAI rejects, or one that isn't shaped like a key, is not saved", async () => {
    expect(await openAiKeyStore({ CC_VOICE_KEY_FILE: file }, rejectFetch).save(KEY)).toEqual({
      ok: false,
      reason: "OpenAI rejected that key.",
    });
    const r = await openAiKeyStore({ CC_VOICE_KEY_FILE: file }, okFetch).save("hello");
    expect(r.ok).toBe(false);
    expect(checks).toEqual([]);
    expect(existsSync(file)).toBe(false);
  });

  test("a key written by hand is picked up without a restart; clear removes it", () => {
    const s = openAiKeyStore({ CC_VOICE_KEY_FILE: file }, okFetch);
    expect(s.status().configured).toBe(false);
    writeFileSync(path.join(dir, "k2"), KEY);
    const s2 = openAiKeyStore({ CC_VOICE_KEY_FILE: path.join(dir, "k2") }, okFetch);
    expect(s2.current()).toBe(KEY);
    expect(s2.clear()).toMatchObject({ ok: true, status: { configured: false } });
    expect(existsSync(path.join(dir, "k2"))).toBe(false);
  });

  test("OPENAI_API_KEY wins and can't be replaced or removed from a page", async () => {
    const s = openAiKeyStore({ CC_VOICE_KEY_FILE: file, OPENAI_API_KEY: KEY }, okFetch);
    expect(s.status()).toMatchObject({
      configured: true,
      source: "env",
      editable: false,
      hint: "WXYZ",
    });
    expect((await s.save("sk-other-0123456789abcdefghij")).ok).toBe(false);
    expect(s.clear().ok).toBe(false);
    expect(checks).toEqual([]);
  });
});

describe("the adapters read the key on every call", () => {
  test("without a key they refuse instead of calling OpenAI", async () => {
    let called = 0;
    const f = (async () => {
      called++;
      return new Response(new Uint8Array([1]), { status: 200 });
    }) as unknown as typeof fetch;
    let key = "";
    const synth = openAiSynthesizer(() => key, f);
    const rec = openAiRecognizer(() => key, {}, f);
    expect((await synth.synth("hi", { model: "m", voice: "v", instructions: "i" })).ok).toBe(false);
    expect((await rec.transcribe(new Blob([new Uint8Array([1])]), "webm")).ok).toBe(false);
    expect(called).toBe(0);
    key = KEY;
    expect((await synth.synth("hi", { model: "m", voice: "v", instructions: "i" })).ok).toBe(true);
    expect(called).toBe(1);
  });
});
