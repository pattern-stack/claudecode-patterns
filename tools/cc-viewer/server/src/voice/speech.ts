/**
 * Ports for the voice module: text to speech and speech to text.
 * Adapters: openai-speech.ts (OpenAI). Without a key both are absent and the voice page falls back to the
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
