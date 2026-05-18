---
name: browser-driver
description: Drive a real browser against a URL — capture full-page screenshots, inspect computed styles / ARIA / cursor / overflow per selector, and exercise interactions (open menus, hover for tooltips). Wraps `${CLAUDE_PLUGIN_DIR}/scripts/capture-surface.mjs` and `${CLAUDE_PLUGIN_DIR}/scripts/inspect-surface.mjs`. Uses headless Playwright with saved auth state by default; supports the user's running Chrome via opt-in.
argument-hint: "<op=capture|inspect|verify> <url> [<args>]"
arguments: [op, url, args]
allowed-tools: Bash(bun ${CLAUDE_PLUGIN_DIR}/scripts/design.ts *) Bash(node scripts/*) Bash(curl *) Read Write Glob Grep

# === Project SDLC overlay ===
status: beta
topology: [universal]
consumes: [url, selectors-json]
produces: [screenshot, inspection-json]
gates:
  enforces: []
  sets: []
---

# Browser Driver

Universal browser interaction layer. **Default = headless Playwright with saved auth state.** Replaces the historical `browser-pilot` subagent + Playwright MCP path because both had reliability gaps (cert handling, subagent registration, MCP knob exposure).

## When to use

- Capturing a screenshot of a live surface (any URL)
- Inspecting cursor/ARIA/role/overflow/computed-style state of rendered elements
- Driving an interaction (open a menu, hover for tooltip, click and see result)
- `/design-loop` invokes this for evidence capture + interactive grading
- `/design-audit` invokes this for one-shot audits
- Ad-hoc: "is the cursor right on this button", "does the menu open"

## Operations

### `capture` — full-page screenshot
```
bun ${CLAUDE_PLUGIN_DIR}/scripts/design.ts capture <url> <outPath>
```
Returns JSON: `{ url, finalUrl, title, navStatus, usedStorage, screenshot, consoleSample }`.

Env vars: `VIEWPORT_W` (default 1512), `VIEWPORT_H` (default 982).

### `inspect` — structural + interactive probe
```
bun ${CLAUDE_PLUGIN_DIR}/scripts/design.ts inspect <url> [<selectors.json>] [<out.json>]
```
With no selectors JSON: minimal probe (nav status, title, auth-stale flag).
With selectors JSON: per-probe `{ cursor, role, ariaLabel, ariaPressed, ariaExpanded, ariaDisabled, tabindex, disabled, display, box*, overflowing, textPreview }`. Plus optional interactions (`openMenu`, `hoverForTooltip`).

#### Selectors JSON shape
```json
{
  "probes": {
    "scopeChip":    { "by": "text", "tag": "button", "selector": "All Opportunities", "ariaName": "Opportunity scope" },
    "formatChip":   { "by": "text", "tag": "button", "selector": "Plain Text", "ariaName": "Change output format" },
    "cursorHint":   { "by": "deepest-text", "selector": "Type \"/\" to write AI instructions", "maxLen": 200 }
  },
  "interactions": [
    { "kind": "openMenu", "trigger": "formatChip", "captureKey": "formatMenu" },
    { "kind": "hoverForTooltip", "trigger": "scopeChip", "captureKey": "scopeTooltip" }
  ]
}
```

### `verify` — single-shot pre-flight check
```
bun ${CLAUDE_PLUGIN_DIR}/scripts/design.ts verify <url>
```
Runs `inspect` with no selectors and checks:
- `navStatus` is `http 200`
- `authStale` is `false`
- `pageTitle` is non-empty and not `"Loading..."`

Exit code 0 on pass, 1 on fail. Stdout is `{ ok, reasons?, hint? }` JSON.

Used by `/design-loop` at start.

## Auth

- Reads `.playwright/auth.json` (Playwright storageState) by default
- If absent or stale → `authStale: true` in the inspect output → call `/auth-recover`

## Cert handling

`--ignore-certificate-errors` is baked into the Chromium launch + `ignoreHTTPSErrors: true` on the context. Works against locally-issued Caddy certs without trust-store changes.

## When NOT to use this skill

- You need to see what the user is *actively browsing* (their cookies, their navigation state) — use `chrome-devtools` MCP via a subagent instead
- You need to do something interactive that the script doesn't support (e.g., drag-and-drop) — write a one-off Node script

## Mode: user-browser (chrome-devtools)

Not yet wrapped by this skill. If needed: spawn a subagent that has the `chrome-devtools` MCP server in its frontmatter (e.g., `browser-pilot`). The user must have Chrome running with `--remote-debugging-port=9222`.

## Constraints

- Always uses headless mode by default — never pops a window unprompted
- Never writes anywhere outside `screenshots/`, `.ai-docs/`, or the explicit `outPath` arg
- Auth helper (`scripts/playwright-auth.mjs`) is the ONLY thing that opens a headed browser; only invoked via `/auth-recover`

## Related

- [`/auth-recover`](../auth-recover/SKILL.md) — refreshes `.playwright/auth.json` when stale
- [`/design-loop`](../design-loop/SKILL.md) — primary consumer
- [`/figma-snapshot`](../figma-snapshot/SKILL.md) — sibling, snapshots the reference
- `${CLAUDE_PLUGIN_DIR}/scripts/capture-surface.mjs` — implementation
- `${CLAUDE_PLUGIN_DIR}/scripts/inspect-surface.mjs` — implementation
