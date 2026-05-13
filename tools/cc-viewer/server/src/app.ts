import { Hono } from "hono";
import type { ServerConfig } from "./config.js";
import { corsMiddleware } from "./middleware/cors.js";
import { errorHandler } from "./middleware/error-handler.js";
import { eventRoutes } from "./routes/events.js";
import { healthRoutes } from "./routes/health.js";
import { hookRoutes } from "./routes/hooks.js";
import { SPA_FALLBACK, STATIC_BUNDLE } from "./static-bundle.js";

export function createServer(config: ServerConfig): Hono {
  const app = new Hono();

  app.use("*", corsMiddleware(config.cors));
  app.onError(errorHandler);

  // API first (so they beat the SPA fallback)
  app.route("/", healthRoutes());
  app.route("/", hookRoutes(config.broadcaster, config.eventStore));
  app.route("/", eventRoutes(config.eventStore, config.broadcaster));

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
