/**
 * Ports for the voice module: text to speech and speech to text.
 * Adapters: openai-speech.ts (OpenAI). Without a key both refuse and the voice page falls back to the
 * browser's own voice and speech recognition.
 */

/** How answers sound. One definition, used for every answer and the "Got it" clip. */
export interface VoiceProfile {
  readonly model: string;
  readonly voice: string;
  readonly instructions: string;
}

export interface SpeechSynthesizer {
  readonly name: string;
  /** mp3 bytes, or an error message. */
  synth(
    text: string,
    profile: VoiceProfile,
  ): Promise<{ ok: true; mp3: Uint8Array } | { ok: false; reason: string }>;
}

export interface SpeechRecognizer {
  readonly name: string;
  transcribe(
    audio: Blob,
    ext: string,
  ): Promise<{ ok: true; text: string; model: string } | { ok: false; reason: string }>;
}

/** Where the speech key came from. The environment wins over the file and can't be changed from a page. */
export type SpeechKeySource = "env" | "file" | "none";

export interface SpeechKeyStatus {
  readonly configured: boolean;
  readonly source: SpeechKeySource;
  /** The key's last four characters, never more. */
  readonly hint: string | null;
  /** The file a saved key goes to. */
  readonly file: string;
  /** False when the environment sets the key: the page can't replace or remove it. */
  readonly editable: boolean;
}

export type SpeechKeyResult = { ok: true; status: SpeechKeyStatus } | { ok: false; reason: string };

/**
 * The speech provider's API key, read on every use: a key saved or removed takes effect on the next request, with
 * no restart. The adapters get `current` and nothing else.
 */
export interface SpeechKeyStore {
  current(): string;
  status(): SpeechKeyStatus;
  /** Checks the key with the provider, then writes it (0600). */
  save(key: string): Promise<SpeechKeyResult>;
  clear(): SpeechKeyResult;
}
