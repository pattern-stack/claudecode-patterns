import { Hono } from "hono";

export function healthRoutes(): Hono {
  const app = new Hono();
  // `version` is injected by the launcher: ensure-cc-viewer.sh sets
  // CC_VIEWER_VERSION to the installed plugin version, which equals the
  // version-pinned binary it launches. The SessionStart hook reads it back
  // to decide whether a running dashboard is stale and needs restarting.
  // Older binaries predate this field — an absent `version` reads as stale.
  app.get("/health", (c) =>
    c.json({ status: "ok", version: process.env.CC_VIEWER_VERSION ?? "dev" }),
  );
  return app;
}
