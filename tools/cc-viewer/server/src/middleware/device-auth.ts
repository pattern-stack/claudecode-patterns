/**
 * Who may use the dashboard.
 *
 * - **This machine** — a loopback peer that also names a loopback Host (localhost / 127.0.0.1 / [::1]). Hooks, the
 *   bridge and the browser on the host need nothing else. Requiring the loopback Host stops a DNS-rebinding page
 *   (evil.example resolving to 127.0.0.1) from passing as local.
 * - **A paired device** — sends the key as the `ccv_key` cookie (browsers) or the `X-Viewer-Key` header (scripts,
 *   hooks on other machines). See pairing.ts.
 * - Everyone else gets 401 (a page navigation is sent to /pair instead).
 *
 * Writes (anything but GET/HEAD/OPTIONS) are also refused when the browser says they came from another site: an
 * `Origin` that is neither a local origin nor this request's own host. Without that, any website open in a trusted
 * browser could POST here (for example to /admin/input/send, which types into a terminal).
 */

import type { Context, MiddlewareHandler } from "hono";
import { getConnInfo } from "hono/bun";
import { getCookie } from "hono/cookie";
import type { Pairing } from "../pairing.js";

export const KEY_COOKIE = "ccv_key";
export const KEY_HEADER = "x-viewer-key";

const LOOPBACK_HOST = /^(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/i;
const LOCAL_ORIGIN = /^https?:\/\/(localhost|127\.0\.0\.1|\[::1\])(:\d+)?$/i;
const OPEN_PATHS = new Set(["/pair", "/pair/claim", "/health"]);
const SAFE_METHODS = new Set(["GET", "HEAD", "OPTIONS"]);

function peerAddress(c: Context): string {
  try {
    return getConnInfo(c).remote.address ?? "";
  } catch {
    return "";
  }
}

const isLoopbackAddress = (addr: string): boolean =>
  addr === "::1" || addr.startsWith("127.") || addr.startsWith("::ffff:127.");

/** The request comes from this machine and names it as such. */
export function isLocal(c: Context): boolean {
  return isLoopbackAddress(peerAddress(c)) && LOOPBACK_HOST.test(c.req.header("host") ?? "");
}

/** The request carries the device key. */
export function isPaired(c: Context, pairing: Pairing): boolean {
  return pairing.matches(c.req.header(KEY_HEADER) ?? getCookie(c, KEY_COOKIE));
}

function crossSiteWrite(c: Context): boolean {
  if (SAFE_METHODS.has(c.req.method)) return false;
  const origin = c.req.header("origin");
  if (!origin) return false; // curl, hooks, server-to-server
  if (LOCAL_ORIGIN.test(origin)) return false;
  const host = c.req.header("host") ?? "";
  return origin !== `http://${host}` && origin !== `https://${host}`;
}

export function deviceAuth(pairing: Pairing): MiddlewareHandler {
  return async (c, next) => {
    if (crossSiteWrite(c)) return c.json({ error: "cross-site request refused" }, 403);
    const pathname = new URL(c.req.url).pathname;
    if (OPEN_PATHS.has(pathname) || isLocal(c) || isPaired(c, pairing)) return next();
    const wantsPage = c.req.method === "GET" && (c.req.header("accept") ?? "").includes("text/html");
    if (wantsPage) return c.redirect("/pair", 302);
    return c.json({ error: "this device isn't paired", pair: "/pair" }, 401);
  };
}
