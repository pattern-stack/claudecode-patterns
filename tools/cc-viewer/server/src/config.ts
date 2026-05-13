import type { EventStore } from "./event-store.js";
import type { SSEBroadcaster } from "./sse-broadcaster.js";

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
}
