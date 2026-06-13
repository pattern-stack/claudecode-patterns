import { Hono } from "hono";
import type { ServerConfig } from "./config.js";
import { corsMiddleware } from "./middleware/cors.js";
import { errorHandler } from "./middleware/error-handler.js";
import { commandRoutes } from "./routes/commands.js";
import { eventRoutes } from "./routes/events.js";
import { fileRoutes } from "./routes/file.js";
import { healthRoutes } from "./routes/health.js";
import { hookRoutes } from "./routes/hooks.js";
import { inputRoutes } from "./routes/input.js";
import { transcriptRoutes } from "./routes/transcripts.js";
import { SPA_FALLBACK, STATIC_BUNDLE } from "./static-bundle.js";

export function createServer(config: ServerConfig): Hono {
  const app = new Hono();

  app.use("*", corsMiddleware(config.cors));
  app.onError(errorHandler);

  // API first (so they beat the SPA fallback).
  // transcriptRoutes registers the static `/hooks/TranscriptDelta` path —
  // mount it BEFORE hookRoutes (which holds the parameterized `/hooks/:eventType`)
  // so the static match wins regardless of router specificity rules.
  app.route("/", healthRoutes());
  app.route("/", transcriptRoutes(config.broadcaster, config.eventStore));
  app.route("/", hookRoutes(config.broadcaster, config.eventStore));
  app.route("/", eventRoutes(config.eventStore, config.broadcaster));
  app.route("/", inputRoutes());
  app.route("/", commandRoutes());
  app.route("/", fileRoutes());

  // SPA fallback. Bundle is populated by scripts/codegen-static.ts at build
  // time. When empty (dev / pre-build), Hono returns 404 on unmatched paths
  // and the user is expected to run vite dev on its own port.
  if (Object.keys(STATIC_BUNDLE).length > 0) {
    app.get("*", (c) => {
      const pathname = new URL(c.req.url).pathname;
      const entry = STATIC_BUNDLE[pathname] ?? SPA_FALLBACK;
      if (!entry) return c.notFound();
      return new Response(Bun.file(entry.path), {
        headers: { "content-type": entry.mime },
      });
    });
  }

  return app;
}
