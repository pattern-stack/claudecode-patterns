---
name: browser
description: Browser interaction via the plugin-shipped MCP servers — see and drive the user's own browser over CDP, run independent headless checks via Playwright, and audit with Lighthouse. Auto-invoked when the conversation mentions browser verification, console errors, screenshots, lighthouse audits, visual QA, tapping into the user's browser, or checking the app in a browser. Exposes /browse and /verify.
allowed-tools: Bash, Read, Glob, Grep

# === Project SDLC overlay ===
status: active
topology: [universal]
consumes: [url]
produces: [screenshots, console, network, audit-scores]
gates:
  enforces: []
  sets: []
---

# Browser

## Purpose

Unified browser interaction for development: see what the user sees (their session, their cookies), interact with pages, run visual QA, and audit performance. The plugin ships the three MCP servers this skill drives, so any project with the plugin has them on the session — no per-project `.mcp.json` setup.

## Two modes, two skills

| Need | Use |
|------|-----|
| The **user's** browser — their auth/session, "what's on my screen", interactive prod debugging | **this skill** (chrome-devtools over CDP) |
| Independent headless check without disturbing the user | **this skill** (playwright server) |
| Scripted evidence capture for design loops — screenshots, selector probes, saved-auth headless runs | [`browser-driver`](../browser-driver/SKILL.md) (`design.ts capture/inspect/verify`) |

## The three MCP servers (plugin-shipped)

Declared in `plugin.json → components.mcpServers`; they register on every session of every consuming project. Tool names are **plugin-namespaced** (`mcp__plugin_sdlc_<server>__…`) — when in doubt, discover them with ToolSearch (`"chrome-devtools list pages"`, `"browser navigate"`, `"lighthouse audit"`).

| Server | Purpose | When to use |
|--------|---------|-------------|
| `chrome-devtools` | The user's running browser via CDP :9222 | Use their session/cookies, see their page, interact alongside them |
| `playwright` | Headless, isolated browser | Independent verification; authenticated runs via saved storage state |
| `lighthouse` | Auditing | Performance, accessibility, SEO, best-practices gates |

**Note for plugin-shipped subagents:** agent-frontmatter `mcpServers:` is silently ignored for plugin agents (platform security rule). Browser-capable agents (e.g. `browser-pilot`) rely on these session-level servers instead — which also means their `tools:` must be the **denylist** form, since an allowlist without MCP entries blocks MCP tools.

## Connecting to the user's browser (CDP)

Works with **any Chromium-based browser** exposing CDP on port 9222. Not Firefox/Safari.

| Browser | macOS launch command |
|---------|---------------------|
| Arc | `open -a "Arc" --args --remote-debugging-port=9222` |
| Chrome | `open -a "Google Chrome" --args --remote-debugging-port=9222` |
| Chromium | `open -a "Chromium" --args --remote-debugging-port=9222` |
| Brave | `open -a "Brave Browser" --args --remote-debugging-port=9222` |
| Edge | `open -a "Microsoft Edge" --args --remote-debugging-port=9222` |
| Vivaldi | `open -a "Vivaldi" --args --remote-debugging-port=9222` |
| Opera | `open -a "Opera" --args --remote-debugging-port=9222` |

> The flag only applies to a fresh launch — quit the browser fully first.

### Arc specifics (hard-won)

Arc **loses the flag on every Cmd-Q**, and lingering helper processes can keep a flagless instance alive. The reliable relaunch one-liner:

```bash
osascript -e 'quit app "Arc"' ; sleep 2 ; pkill -9 -f "/Applications/Arc.app/" 2>/dev/null ; sleep 1 ; open -a "Arc" --args --remote-debugging-port=9222 && sleep 3 && curl -sS http://localhost:9222/json/version | head -3
```

If Arc still ignores the flag, make it sticky, then relaunch:

```bash
defaults write company.thebrowser.Browser EnableRemoteDebugging -bool true
```

### Per-dev browser preference

Stored as an env var in `.claude/settings.local.json` (gitignored, never committed):

```json
{ "env": { "BROWSER_PREFERENCE": "arc" } }
```

Valid values: `arc`, `chrome`, `chromium`, `brave`, `edge`, `vivaldi`, `opera`.

Setting a preference also opts you into the `check-cdp` SessionStart nudge: when :9222 is dark at session start, you get your browser's relaunch command up front instead of discovering it mid-task.

### CDP connection check (run before any user-browser interaction)

1. Call the chrome-devtools `list_pages` tool.
2. **Works** → proceed.
3. **Fails**:
   - `curl -sS -m 2 http://localhost:9222/json/version` to confirm it's the browser, not the server.
   - Read `BROWSER_PREFERENCE` from `.claude/settings.local.json`; if unset, ask which browser they use and write it for them.
   - Show the launch command for *their* browser (Arc → the one-liner above).
   - Stop and wait — do not proceed until CDP connects.

## Project URLs

Do **not** hardcode URLs in this skill (historically, copies of this skill carried another project's ports for months). Resolve targets in this order:

1. `.claude/sdlc.yml` → `browser:` block, when the project defines one:
   ```yaml
   browser:
     frontend_url: https://localhost:3001
     api_url: http://localhost:3000
     prod_url: https://example.com/app
   ```
2. An explicit URL in the user's request.
3. Otherwise: ask once, and offer to persist the answer into `sdlc.yml`.

## Auth for headless runs

The playwright server runs `--headless --isolated` — it has no session. The ladder, most-portable first:

1. **Saved storage state** — `.playwright/auth.json` (shared with `browser-driver`). If present and fresh, headless runs are already authenticated.
2. **Headed-once bootstrap** — `node ${CLAUDE_PLUGIN_ROOT}/scripts/auth-capture.mjs <login-url>` opens a *visible* browser, the user logs in by hand, the script saves storage state, headless thereafter. Generic: no provider/IdP assumptions.
3. **Project-supplied auth script** — when a project has its own credential plumbing (env, sops, password-manager CLI), point `sdlc.yml → browser.auth_script` at it; prefer it over the generic bootstrap.
4. **The user's browser** — when storage state can't capture it (device-bound SSO), fall back to chrome-devtools and work inside their session.

## Tool preferences

- **PREFER** accessibility snapshots (`take_snapshot` / `browser_snapshot`) over screenshots — structured, token-efficient.
- **USE** element uids from the snapshot for clicks/fills — never guess coordinates.
- **USE** `evaluate_script` / `browser_evaluate` for batch work against an authenticated app (e.g. many API calls) instead of clicking through UI.
- **USE** lighthouse for quality gates, chrome-devtools performance tracing for deep dives.

## Commands

- **`/verify [url] [--perf]`** — visual QA pass (snapshot, console, network, screenshot, optional perf). See `commands/verify.md`.
- **`/browse [instruction]`** — open-ended browser interaction. See `commands/browse.md`.

## Delegating: the browser-pilot teammate

For sustained browser work inside dev loops, spawn the plugin's `browser-pilot` agent — it uses the same session-level servers and this skill as its knowledge base.

## Reporting format

```
**Page:** {url}
**Status:** {pass | issues found}

**Console:** {N errors, M warnings} or "clean"
**Network:** {N failed requests} or "all OK"
**Visual:** {brief description of what's on screen}

{Details of any issues found}
```
