/**
 * Local image file streamer.
 *
 * Transcript file-delivery tools (SendUserFile) reference images by absolute
 * path, not bytes. The chat surface renders them via `/admin/file?path=…`,
 * which streams the file from disk.
 *
 * Scope guard: only image extensions are served (this is a read-only local
 * viewer of the user's own machine, bound to 127.0.0.1; restricting to images
 * keeps it from becoming a general file-disclosure endpoint).
 */

import { existsSync, statSync } from "node:fs";
import path from "node:path";
import { Hono } from "hono";

const IMAGE_MIME: Record<string, string> = {
  ".png": "image/png",
  ".jpg": "image/jpeg",
  ".jpeg": "image/jpeg",
  ".gif": "image/gif",
  ".webp": "image/webp",
  ".svg": "image/svg+xml",
  ".bmp": "image/bmp",
  ".avif": "image/avif",
};

const MAX_BYTES = 25 * 1024 * 1024;

export function fileRoutes(): Hono {
  const app = new Hono();

  app.get("/admin/file", (c) => {
    const p = c.req.query("path");
    if (!p || !path.isAbsolute(p)) {
      return c.json({ error: "an absolute file path is required" }, 400);
    }
    const mime = IMAGE_MIME[path.extname(p).toLowerCase()];
    if (!mime) {
      return c.json({ error: "only image files are served" }, 400);
    }
    if (!existsSync(p)) {
      return c.json({ error: "file not found" }, 404);
    }
    let st: ReturnType<typeof statSync>;
    try {
      st = statSync(p);
    } catch {
      return c.json({ error: "file not found" }, 404);
    }
    if (!st.isFile()) return c.json({ error: "not a regular file" }, 400);
    if (st.size > MAX_BYTES) return c.json({ error: "file too large" }, 413);

    return new Response(Bun.file(p), {
      headers: { "content-type": mime, "cache-control": "private, max-age=300" },
    });
  });

  return app;
}
