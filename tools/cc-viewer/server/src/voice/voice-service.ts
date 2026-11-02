/**
 * The voice module: speaks the linked session's answers and types spoken replies back into it.
 *
 * It owns no transport of its own. Both directions run on the viewer's existing interfaces:
 *   - out: the viewer's event stream (SSEBroadcaster.subscribe). A `Stop` hook for the linked session carries the
 *     turn's final message (`last_assistant_message`); that text is the answer.
 *   - in:  the SessionInput port (input/), the same one POST /admin/input/send projects. Herdr finds the pane by
 *     session id.
 * Speech is behind its own two ports (speech.ts). State (link, settings, history, clips) lives in `stateDir`.
 *
 * Moved from the voice relay (~/.claude/skills/final-answer/web/server.ts): history + clip pruning, the one-active-
 * page rule, idempotent replies, the reply prefix. Dropped: the relay's own token, TLS, pane id and herdr calls.
 */

import { createHash, randomBytes } from "node:crypto";
import { existsSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import path from "node:path";
import type { SessionInput } from "../input/index.js";
import { speakable } from "./speakable.js";
import type {
  SpeechKeyStatus,
  SpeechKeyStore,
  SpeechRecognizer,
  SpeechSynthesizer,
  VoiceProfile,
} from "./speech.js";

/** The one Claude Code session the voice page talks to. Chosen from sessions the viewer already knows. */
export interface VoiceLink {
  readonly sessionId: string;
  readonly cwd: string | null;
  readonly label: string;
  readonly linkedAt: number;
}

export interface VoiceEntry {
  readonly id: number;
  readonly ts: number;
  readonly kind: "answer" | "reply";
  readonly sessionId: string;
  /** What Claude wrote, or what was transcribed and sent. */
  readonly text: string;
  /** What is said out loud for an answer (speakable(text)). */
  readonly speech?: string;
  /** An answer whose audio can be fetched (a synthesizer is configured). */
  readonly audio?: boolean;
  readonly replyId?: string;
}

/** Per listening device and room. The page edits only these. */
export interface VoiceSettings {
  readonly silenceMs: number;
  readonly countdownMs: number;
  readonly listenWindowMs: number;
  readonly sensitivity: number;
  readonly liveCaptions: boolean;
}

/** What the page needs to know about host speech, before anyone talks. Never carries the key. */
export interface SpeechView {
  /** Answers are spoken by the host's voice (else the browser's). */
  readonly tts: boolean;
  /** Replies are written down by the host (else only by the browser's recognition, where it has one). */
  readonly stt: boolean;
  readonly key: SpeechKeyStatus | null;
}

export type LinkStatus = "idle" | "working" | "waiting" | "ended" | "unknown";

/** The viewer's session registry (EventStore.sessions). */
export interface SessionDirectory {
  sessions(limit: number): { sessionId: string; cwd: string | null; lastSeen: string }[];
}

export interface VoiceDeps {
  readonly stateDir: string;
  readonly input: SessionInput;
  readonly sessions?: SessionDirectory;
  readonly synth?: SpeechSynthesizer;
  readonly recognizer?: SpeechRecognizer;
  /** The key both adapters use. When given, they count as available only while it holds a key. */
  readonly speechKey?: SpeechKeyStore;
  readonly profile: VoiceProfile;
  /** Put in front of every reply so Claude reads it as a transcript. Never empty. */
  readonly replyPrefix?: string;
  readonly maxSpeechChars?: number;
  readonly log?: (...a: unknown[]) => void;
}

export type ReplyResult =
  | { ok: true; entry?: VoiceEntry; duplicate?: boolean; adapter?: string }
  | { ok: false; reason: string; status?: number };

export const DEFAULT_SETTINGS: VoiceSettings = {
  silenceMs: 1700,
  countdownMs: 0, // Doug, 2026-10-25: a reply goes as soon as it is transcribed
  listenWindowMs: 90_000,
  sensitivity: 2.5,
  liveCaptions: true,
};
const SETTING_KEYS = Object.keys(DEFAULT_SETTINGS) as (keyof VoiceSettings)[];
const KEEP = 30; // answers + replies kept (and answer clips)
const MAX_REPLY = 4000;
const DEFAULT_PREFIX = "[voice] ";

const HOOK_STATUS: Record<string, LinkStatus> = {
  SessionStart: "idle",
  UserPromptSubmit: "working",
  PreToolUse: "working",
  PostToolUse: "working",
  SubagentStart: "working",
  PermissionRequest: "waiting",
  Elicitation: "waiting",
  Stop: "idle",
  StopFailure: "idle",
  SessionEnd: "ended",
};

interface HookEventShape {
  hookName?: string;
  sessionId?: string;
  cwd?: string;
  payload?: Record<string, unknown>;
}

type Client = { id: string; since: number; send: (event: string, data: unknown) => void };

const labelFor = (sessionId: string, cwd: string | null) =>
  `${cwd ? path.basename(cwd) : "session"} · ${sessionId.slice(0, 8)}`;

export class VoiceService {
  private readonly dir: string;
  private readonly audioDir: string;
  private readonly prefix: string;
  private readonly maxSpeech: number;
  private readonly log: (...a: unknown[]) => void;
  private link: VoiceLink | null;
  private status: LinkStatus = "unknown";
  private settings: VoiceSettings;
  private history: VoiceEntry[];
  private seq: number;
  private readonly clips = new Map<number, Promise<Uint8Array | null>>();
  private ackClip: Promise<Uint8Array | null> | null = null;
  private readonly sending = new Set<string>();
  private readonly clients = new Map<string, Client>();
  private claimed = "";

  constructor(private readonly deps: VoiceDeps) {
    this.dir = deps.stateDir;
    this.audioDir = path.join(this.dir, "audio");
    mkdirSync(this.audioDir, { recursive: true, mode: 0o700 });
    this.prefix = deps.replyPrefix?.trim() ? deps.replyPrefix : DEFAULT_PREFIX;
    this.maxSpeech = deps.maxSpeechChars ?? 1200;
    this.log = deps.log ?? (() => {});
    this.link = this.read<VoiceLink | null>("link.json", null);
    this.settings = {
      ...DEFAULT_SETTINGS,
      ...this.read<Partial<VoiceSettings>>("settings.json", {}),
    };
    this.history = this.read<VoiceEntry[]>("history.json", []);
    this.seq = this.history.reduce((m, e) => Math.max(m, e.id), 0);
  }

  // ---- out: answers from the viewer's event stream ------------------------------------------------------------
  /** Wire to SSEBroadcaster.subscribe. Ignores everything but hooks of the linked session. */
  onViewerEvent = (name: string, data: unknown): void => {
    if (name !== "claude_code.hook" || !this.link) return;
    const e = data as HookEventShape;
    if (e.sessionId !== this.link.sessionId || !e.hookName) return;
    const next = HOOK_STATUS[e.hookName];
    if (next && next !== this.status) {
      this.status = next;
      this.broadcast("status", this.linkView());
    }
    if (e.hookName === "Stop") {
      const text = e.payload?.last_assistant_message;
      if (typeof text === "string" && text.trim()) this.announce(text.trim());
      else this.log("voice: Stop without last_assistant_message; nothing to say");
    }
  };

  /** Record an answer for the linked session and push it to the pages. Audio is made on first request. */
  announce(text: string): VoiceEntry | null {
    if (!this.link) return null;
    const entry = this.record({
      kind: "answer",
      sessionId: this.link.sessionId,
      text,
      speech: speakable(text, this.maxSpeech),
      audio: this.canSpeak(),
    });
    this.broadcast("answer", { ...entry, primary: this.primary() });
    if (entry.audio && this.clients.size) void this.audio(entry.id); // start synthesis before the page asks
    this.log(`voice: answer #${entry.id} (${text.length} chars) -> ${this.clients.size} page(s)`);
    return entry;
  }

  /** The answer's mp3: from disk, or synthesized once (concurrent requests share one call). */
  audio(id: number): Promise<Uint8Array | null> {
    const file = path.join(this.audioDir, `${id}.mp3`);
    if (existsSync(file)) return Promise.resolve(new Uint8Array(readFileSync(file)));
    const entry = this.history.find((h) => h.id === id && h.kind === "answer");
    const synth = this.deps.synth;
    if (!entry || !synth || !this.canSpeak()) return Promise.resolve(null);
    let p = this.clips.get(id);
    if (!p) {
      p = synth.synth(entry.speech ?? entry.text, this.deps.profile).then((r) => {
        this.clips.delete(id);
        if (!r.ok) {
          this.log(`voice: synthesis failed for #${id}: ${r.reason}`);
          return null;
        }
        if (this.history.some((h) => h.id === id)) writeFileSync(file, r.mp3);
        return r.mp3;
      });
      this.clips.set(id, p);
    }
    return p;
  }

  /** "Got it." in the answer voice, made once per voice profile. */
  ack(): Promise<Uint8Array | null> {
    const synth = this.deps.synth;
    if (!synth || !this.canSpeak()) return Promise.resolve(null);
    const key = createHash("sha256")
      .update(JSON.stringify(this.deps.profile))
      .digest("hex")
      .slice(0, 12);
    const file = path.join(this.dir, `ack-${key}.mp3`);
    if (existsSync(file)) return Promise.resolve(new Uint8Array(readFileSync(file)));
    this.ackClip ??= synth.synth("Got it.", this.deps.profile).then((r) => {
      this.ackClip = null;
      if (!r.ok) return null;
      writeFileSync(file, r.mp3);
      return r.mp3;
    });
    return this.ackClip;
  }

  transcribe(audio: Blob, ext: string) {
    if (!this.deps.recognizer || !this.canHear())
      return Promise.resolve({
        ok: false as const,
        reason: "no OpenAI key on the host, so it can't write replies down (add one in Settings)",
      });
    return this.deps.recognizer.transcribe(audio, ext);
  }

  // ---- host speech: the key ----------------------------------------------------------------------------------
  speechView(): SpeechView {
    return {
      tts: this.canSpeak(),
      stt: this.canHear(),
      key: this.deps.speechKey?.status() ?? null,
    };
  }

  async saveKey(
    key: string,
  ): Promise<{ ok: true; speech: SpeechView } | { ok: false; reason: string }> {
    const store = this.deps.speechKey;
    if (!store) return { ok: false, reason: "This viewer has no key store." };
    const r = await store.save(key);
    if (!r.ok) return r;
    this.log(`voice: OpenAI key saved (…${r.status.hint})`);
    return this.speechChanged();
  }

  clearKey(): { ok: true; speech: SpeechView } | { ok: false; reason: string } {
    const store = this.deps.speechKey;
    if (!store) return { ok: false, reason: "This viewer has no key store." };
    const r = store.clear();
    if (!r.ok) return r;
    this.log("voice: OpenAI key removed");
    return this.speechChanged();
  }

  private speechChanged() {
    this.ackClip = null;
    const speech = this.speechView();
    this.broadcast("speech", speech);
    return { ok: true as const, speech };
  }

  private keyHeld(): boolean {
    return this.deps.speechKey ? this.deps.speechKey.status().configured : true;
  }

  private canSpeak(): boolean {
    return !!this.deps.synth && this.keyHeld();
  }

  private canHear(): boolean {
    return !!this.deps.recognizer && this.keyHeld();
  }

  // ---- in: replies through the input port --------------------------------------------------------------------
  async takeReply(raw: string, replyId: string): Promise<ReplyResult> {
    const link = this.link;
    if (!link) return { ok: false, reason: "No session is linked. Pick one in Settings." };
    // biome-ignore lint/suspicious/noControlCharactersInRegex: removing control characters is the point
    const clean = raw
      .replace(/[\u0000-\u001f\u007f-\u009f]+/g, " ")
      .replace(/\s+/g, " ")
      .trim();
    if (!clean) return { ok: false, reason: "Nothing to send." };
    if (this.sending.has(replyId) || this.history.some((h) => h.replyId === replyId))
      return { ok: true, duplicate: true };
    this.sending.add(replyId);
    try {
      const text = (this.prefix + clean).slice(0, MAX_REPLY);
      const r = await this.deps.input.deliver(
        { sessionId: link.sessionId, cwd: link.cwd ?? undefined },
        text,
        true,
      );
      if (!r.ok) return { ok: false, reason: r.error, status: r.status };
      const entry = this.record({ kind: "reply", sessionId: link.sessionId, text: clean, replyId });
      this.broadcast("reply", entry);
      return { ok: true, entry, adapter: r.adapter };
    } finally {
      this.sending.delete(replyId);
    }
  }

  // ---- the link ------------------------------------------------------------------------------------------------
  /** Sessions the viewer knows, newest first: the only targets a page can pick. */
  sessionChoices(limit = 25) {
    return (this.deps.sessions?.sessions(limit) ?? []).map((s) => ({
      sessionId: s.sessionId,
      cwd: s.cwd,
      label: labelFor(s.sessionId, s.cwd),
      lastSeen: s.lastSeen,
      linked: s.sessionId === this.link?.sessionId,
    }));
  }

  setLink(sessionId: string): { ok: true; link: VoiceLink } | { ok: false; reason: string } {
    const known = this.deps.sessions?.sessions(500).find((s) => s.sessionId === sessionId);
    if (!known) return { ok: false, reason: "The dashboard doesn't know that session." };
    this.link = {
      sessionId,
      cwd: known.cwd,
      label: labelFor(sessionId, known.cwd),
      linkedAt: Date.now(),
    };
    this.status = "unknown";
    this.write("link.json", this.link);
    this.broadcast("link", this.linkView());
    this.broadcast("history", this.linkHistory());
    this.log(`voice: linked to ${this.link.label}`);
    return { ok: true, link: this.link };
  }

  linkView() {
    return { link: this.link, status: this.link ? this.status : "unknown" };
  }

  // ---- settings ------------------------------------------------------------------------------------------------
  getSettings(): VoiceSettings {
    return this.settings;
  }

  updateSettings(
    body: Record<string, unknown>,
  ): { ok: true; settings: VoiceSettings } | { ok: false; reason: string } {
    const next: Record<string, number | boolean> = { ...this.settings };
    for (const k of SETTING_KEYS) {
      if (!(k in body)) continue;
      if (typeof DEFAULT_SETTINGS[k] === "boolean") next[k] = Boolean(body[k]);
      else {
        const n = Number(body[k]);
        if (!Number.isFinite(n) || n < 0)
          return { ok: false, reason: `${k} must be a number of zero or more` };
        next[k] = n;
      }
    }
    this.settings = next as unknown as VoiceSettings;
    this.write("settings.json", this.settings);
    this.broadcast("settings", this.settings);
    return { ok: true, settings: this.settings };
  }

  // ---- pages (one active at a time) ------------------------------------------------------------------------------
  /** An SSE stream for one page. The page that last pressed Start plays and listens; the others show text. */
  connect(clientId?: string): {
    id: string;
    stream: ReadableStream<Uint8Array>;
    close: () => void;
  } {
    const id = clientId || randomBytes(6).toString("hex");
    const enc = new TextEncoder();
    let timer: ReturnType<typeof setInterval> | undefined;
    const close = () => {
      if (timer) clearInterval(timer);
      if (this.clients.delete(id)) this.announcePrimary();
    };
    const stream = new ReadableStream<Uint8Array>({
      start: (ctrl) => {
        const send = (event: string, data: unknown) => {
          try {
            ctrl.enqueue(enc.encode(`event: ${event}\ndata: ${JSON.stringify(data)}\n\n`));
          } catch {
            // closed
          }
        };
        this.clients.set(id, { id, since: Date.now(), send });
        send("hello", {
          client: id,
          settings: this.settings,
          history: this.linkHistory(),
          speech: this.speechView(),
          ...this.linkView(),
          now: Date.now(),
        });
        this.announcePrimary();
        timer = setInterval(() => send("ping", Date.now()), 15_000);
      },
      cancel: close,
    });
    return { id, stream, close };
  }

  claim(clientId: string): string {
    if (this.clients.has(clientId)) {
      this.claimed = clientId;
      this.announcePrimary();
    }
    return this.primary();
  }

  /** Ask every open page to reload (after the page changed). Started pages start again on their own. */
  reloadPages(): number {
    this.broadcast("reload", {});
    return this.clients.size;
  }

  get pageCount(): number {
    return this.clients.size;
  }

  private primary(): string {
    if (this.clients.has(this.claimed)) return this.claimed;
    return [...this.clients.values()].sort((a, b) => b.since - a.since)[0]?.id ?? "";
  }

  private announcePrimary() {
    this.broadcast("primary", { primary: this.primary() });
  }

  private broadcast(event: string, data: unknown) {
    for (const c of this.clients.values()) c.send(event, data);
  }

  // ---- history + files -------------------------------------------------------------------------------------------
  private linkHistory(): VoiceEntry[] {
    return this.link ? this.history.filter((h) => h.sessionId === this.link?.sessionId) : [];
  }

  private record(e: Omit<VoiceEntry, "id" | "ts">): VoiceEntry {
    const entry: VoiceEntry = { id: ++this.seq, ts: Date.now(), ...e };
    this.history = [...this.history, entry].slice(-KEEP);
    this.write("history.json", this.history);
    const keep = new Set(this.history.filter((h) => h.kind === "answer").map((h) => `${h.id}.mp3`));
    for (const f of readdirSync(this.audioDir))
      if (!keep.has(f)) rmSync(path.join(this.audioDir, f), { force: true });
    return entry;
  }

  private read<T>(file: string, fallback: T): T {
    try {
      return JSON.parse(readFileSync(path.join(this.dir, file), "utf8")) as T;
    } catch {
      return fallback;
    }
  }

  private write(file: string, data: unknown) {
    writeFileSync(path.join(this.dir, file), `${JSON.stringify(data, null, 2)}\n`, { mode: 0o600 });
  }
}
