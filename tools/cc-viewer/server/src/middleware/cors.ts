/**
 * CORS middleware for dashboard dev.
 */

import { cors } from "hono/cors";
import type { CORSConfig } from "../config.js";

/**
 * Build the Hono cors middleware for this server.
 *
 * By default only pages served from this machine (localhost / 127.0.0.1 / [::1], any port) may read responses, so
 * an arbitrary website open in the browser cannot read session transcripts through this server. The SPA is
 * same-origin and Vite dev proxies, so neither needs CORS. Pin a different policy via `ServerConfig.cors`.
 */
const LOCAL_ORIGIN = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/;

export function corsMiddleware(config?: CORSConfig) {
  return cors({
    origin: config?.origin ?? ((origin) => (LOCAL_ORIGIN.test(origin) ? origin : null)),
    allowMethods: config?.allowMethods ?? ["GET", "POST", "OPTIONS"],
    allowHeaders: config?.allowHeaders ?? ["Content-Type"],
    ...(config?.maxAge !== undefined ? { maxAge: config.maxAge } : {}),
    ...(config?.credentials !== undefined ? { credentials: config.credentials } : {}),
    ...(config?.exposeHeaders !== undefined ? { exposeHeaders: config.exposeHeaders } : {}),
  });
}
