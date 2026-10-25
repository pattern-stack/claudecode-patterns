import type { EventStore } from "./event-store.js";
import type { SessionInput } from "./input/index.js";
import type { Pairing } from "./pairing.js";
import type { SSEBroadcaster } from "./sse-broadcaster.js";
import type { VoiceService } from "./voice/index.js";

export interface CORSConfig {
  readonly origin?: string | string[];
  readonly allowMethods?: string[];
  readonly allowHeaders?: string[];
  readonly maxAge?: number;
  readonly credentials?: boolean;
  readonly exposeHeaders?: string[];
}

export interface ServerConfig {
  readonly eventStore?: EventStore;
  readonly broadcaster: SSEBroadcaster;
  readonly cors?: CORSConfig;
  /** Device pairing. When absent (tests, dev) every request is allowed. */
  readonly pairing?: Pairing;
  /** How /admin/input/send reaches a live terminal (input/index.ts). */
  readonly input: SessionInput;
  /** The voice page and its routes. Absent = off. */
  readonly voice?: VoiceService;
}
