/**
 * Runtime configuration — environment-driven, no flags. Mirrors cc-viewer's
 * config conventions so users have one consistent set of env vars across
 * both binaries.
 */

import { homedir } from "node:os";
import path from "node:path";

export interface BridgeConfig {
  readonly port: number;
  readonly ccViewerUrl: string;
  readonly stateDir: string;
  readonly idleTimeoutMs: number;
  readonly forwardTimeoutMs: number;
}

export function loadConfig(): BridgeConfig {
  const port = Number.parseInt(process.env.CC_BRIDGE_PORT ?? "3994", 10);
  const ccViewerUrl =
    process.env.CC_VIEWER_URL ??
    (process.env.CC_VIEWER_PORT
      ? `http://localhost:${process.env.CC_VIEWER_PORT}`
      : "http://localhost:3993");
  const stateRoot = process.env.XDG_STATE_HOME ?? path.join(homedir(), ".local", "state");
  const stateDir = path.join(stateRoot, "cc-bridge");
  const idleTimeoutMs = Number.parseInt(process.env.CC_BRIDGE_IDLE_TIMEOUT_MS ?? "600000", 10);
  const forwardTimeoutMs = Number.parseInt(process.env.CC_BRIDGE_FORWARD_TIMEOUT_MS ?? "2000", 10);

  return { port, ccViewerUrl, stateDir, idleTimeoutMs, forwardTimeoutMs };
}
