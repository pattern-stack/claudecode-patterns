---
type: primitive
category: quality
value: strict
status: active
description: Default quality profile — all configured gates blocking before merge. Deferred gates (lint/test) listed as such; agents skip them until activated.
---

# Strict Quality Profile

All configured gates must pass before a PR is considered ready. Gates that aren't yet wired are listed as deferred — agents should not run them until they exist.

## Gates

| Gate | Command | Blocking | Status |
|---|---|---|---|
| Typecheck | `bunx tsc --noEmit` | Yes | Active |
| Build (per-package, when shipped) | `bun run build` (in package) | Yes | Active per-package |
| Lint + Format | — | Yes | Deferred until biome lands |
| Tests | — | Yes | Deferred until test runner lands |

## Testing requirements (when active)

- Unit tests for new exports in `packages/*`.
- Integration tests for adapters that touch external systems (Linear, GitHub, etc.) — gate behind sandbox env, never live writes in CI.
- Edge cases and error paths covered.

## Strategy implications

When planning work under `strict`:
- Budget for typecheck pass on every changed package.
- Run `bunx tsc --noEmit` in each affected package before declaring done.
- If a gate is deferred and the change touches code that gate would cover, call it out in the spec — defer doesn't mean ignore.
- Any new package must add its own `typecheck` script in `package.json`.

## When to use

- Default for all PRs in this repo.
- Override to `fast` only for prototypes, spikes, or doc-only changes.
