/**
 * Composition: the voice module from the environment.
 *
 *   CC_VIEWER_VOICE=0        turn the voice page off
 *   OPENAI_API_KEY / CC_VOICE_KEY_FILE (default ~/.config/cc-voice/key)   without a key the page uses browser speech
 *   CC_VOICE_TTS_MODEL (gpt-4o-mini-tts-2025-03-20) · CC_VOICE_VOICE (marin) · CC_VOICE_INSTRUCTIONS
 *   CC_VOICE_STT_MODEL (gpt-4o-mini-transcribe, then whisper-1) · CC_VOICE_LANGUAGE (en)
 *   CC_VOICE_PREFIX ("[voice] ", never empty) · CC_VOICE_MAX_CHARS (1200, how much of an answer is said aloud)
 */

import type { SessionInput } from "../input/index.js";
import { openAiKey, openAiRecognizer, openAiSynthesizer } from "./openai-speech.js";
import { type SessionDirectory, VoiceService } from "./voice-service.js";

export { VoiceService } from "./voice-service.js";

export function voiceFromEnv(opts: {
  stateDir: string;
  input: SessionInput;
  sessions?: SessionDirectory;
  env?: NodeJS.ProcessEnv;
  log?: (...a: unknown[]) => void;
}): VoiceService | undefined {
  const env = opts.env ?? process.env;
  if (env.CC_VIEWER_VOICE === "0") return undefined;
  const key = openAiKey(env);
  const maxChars = Number.parseInt(env.CC_VOICE_MAX_CHARS ?? "", 10);
  return new VoiceService({
    stateDir: opts.stateDir,
    input: opts.input,
    sessions: opts.sessions,
    synth: key ? openAiSynthesizer(key) : undefined,
    recognizer: key
      ? openAiRecognizer(key, { model: env.CC_VOICE_STT_MODEL, language: env.CC_VOICE_LANGUAGE })
      : undefined,
    profile: {
      // Pinned: the bare gpt-4o-mini-tts alias resolves to a newer snapshot that sounds different.
      model: env.CC_VOICE_TTS_MODEL ?? "gpt-4o-mini-tts-2025-03-20",
      voice: env.CC_VOICE_VOICE ?? "marin",
      instructions:
        env.CC_VOICE_INSTRUCTIONS ??
        "Warm, clear, conversational; a colleague giving a spoken update. Natural pace.",
    },
    replyPrefix: env.CC_VOICE_PREFIX,
    maxSpeechChars: Number.isFinite(maxChars) && maxChars > 0 ? maxChars : undefined,
    log: opts.log,
  });
}
