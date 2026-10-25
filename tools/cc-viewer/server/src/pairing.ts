/**
 * Device pairing for the dashboard (the same model as the maplelog board).
 *
 * One secret key, made on first start and kept in `<state>/viewer-key` (0600). A device is paired when it holds the
 * key: a browser as an HttpOnly cookie, anything else as the `X-Viewer-Key` header. The host (this machine) or an
 * already paired device mints a one-time code — 6 digits, 10 minutes, one use, void after 5 wrong guesses — and the
 * new device trades it for the key once. Only one code is live at a time.
 */

import { randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { chmodSync, existsSync, mkdirSync, readFileSync, writeFileSync } from "node:fs";
import path from "node:path";

export const CODE_TTL_MS = 10 * 60_000;
export const CODE_TRIES = 5;

const safeEqual = (a: string, b: string): boolean => {
  const x = Buffer.from(a);
  const y = Buffer.from(b);
  return x.length === y.length && timingSafeEqual(x, y);
};

export class Pairing {
  readonly key: string;
  private code: { value: string; until: number; tries: number } | null = null;

  constructor(stateDir: string) {
    mkdirSync(stateDir, { recursive: true });
    const file = path.join(stateDir, "viewer-key");
    let key = existsSync(file) ? readFileSync(file, "utf8").trim() : "";
    if (!key) {
      key = randomBytes(24).toString("base64url");
      writeFileSync(file, `${key}\n`, { mode: 0o600 });
    }
    chmodSync(file, 0o600);
    this.key = key;
  }

  /** True when `candidate` is the key (constant time). */
  matches(candidate: string | undefined): boolean {
    return !!candidate && safeEqual(candidate, this.key);
  }

  /** Mint a fresh one-time code, replacing any live one. */
  newCode(now = Date.now()): { code: string; minutes: number } {
    const value = String(randomInt(0, 1_000_000)).padStart(6, "0");
    this.code = { value, until: now + CODE_TTL_MS, tries: 0 };
    return { code: value, minutes: CODE_TTL_MS / 60_000 };
  }

  /** Trade a code for the key: true once on a match, then the code is gone. Wrong guesses count toward the limit. */
  claim(candidate: string, now = Date.now()): boolean {
    const live = this.code && now < this.code.until ? this.code : null;
    if (!live) {
      this.code = null;
      return false;
    }
    if (safeEqual(candidate.trim(), live.value)) {
      this.code = null;
      return true;
    }
    live.tries += 1;
    if (live.tries >= CODE_TRIES) this.code = null;
    return false;
  }
}
