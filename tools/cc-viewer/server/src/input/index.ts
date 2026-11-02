/**
 * Composition: which SessionInput adapters this viewer uses, in order, from `CC_VIEWER_INPUT`
 * (comma-separated; default `herdr,ghostty`). The first adapter that finds the session decides.
 * An unknown name is a startup error, never a silent default.
 */

import { ghosttyBridgeInput } from "./ghostty-bridge.js";
import { herdrInput } from "./herdr.js";
import { firstMatch, type SessionInput } from "./session-input.js";

export type { DeliverResult, InputTarget, SessionInput } from "./session-input.js";

const ADAPTERS: Record<string, (env: NodeJS.ProcessEnv) => SessionInput> = {
  herdr: () => herdrInput(),
  ghostty: (env) => ghosttyBridgeInput(env.GHOSTTY_BRIDGE_URL),
};

export function sessionInputFromEnv(env: NodeJS.ProcessEnv = process.env): SessionInput {
  const names = (env.CC_VIEWER_INPUT ?? "herdr,ghostty")
    .split(",")
    .map((s) => s.trim())
    .filter(Boolean);
  const adapters = names.map((name) => {
    const make = ADAPTERS[name];
    if (!make)
      throw new Error(
        `CC_VIEWER_INPUT: unknown adapter "${name}" (known: ${Object.keys(ADAPTERS).join(", ")})`,
      );
    return make(env);
  });
  if (adapters.length === 0) throw new Error("CC_VIEWER_INPUT names no adapter");
  return adapters.length === 1 ? (adapters[0] as SessionInput) : firstMatch(adapters);
}
