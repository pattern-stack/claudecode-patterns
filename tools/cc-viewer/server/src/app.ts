import { Hono } from "hono";
import { serveStatic } from "hono/bun";
import type { ServerConfig } from "./config.js";
import { corsMiddleware } from "./middleware/cors.js";
import { errorHandler } from "./middleware/error-handler.js";
import { eventRoutes } from "./routes/events.js";
import { healthRoutes } from "./routes/health.js";
import { hookRoutes } from "./routes/hooks.js";

export function createServer(config: ServerConfig): Hono {
  const app = new Hono();

  app.use("*", corsMiddleware(config.cors));
  app.onError(errorHandler);

  // API first (so they beat the SPA fallback)
  app.route("/", healthRoutes());
  app.route("/", hookRoutes(config.broadcaster, config.eventStore));
  app.route("/", eventRoutes(config.eventStore, config.broadcaster));

  // SPA static mount last
  if (config.staticDir) {
    app.use("/*", serveStatic({ root: config.staticDir }));
    app.get("*", serveStatic({ path: "index.html", root: config.staticDir }));
  }

  return app;
}
