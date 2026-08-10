---
name: guided-tour
description: "Run a scripted walkthrough of the app's UI in two modes — narrate (drives the user's real browser with a visible cursor, highlights and captions, for demos and human-watchable walkthroughs) and verify (same steps, no theatre: screenshots, console errors, failed requests, text assertions, report.json, non-zero exit). Use when asked to demo a feature in the browser, walk someone through a flow, prove a UI change end-to-end, or turn a manual click-through into a repeatable check."
allowed-tools: Bash, Read, Write, Glob, Grep

# === Project SDLC overlay ===
status: beta
topology: [universal, design-loop]
consumes: [url, tour-definition]
produces: [screenshots, report-json, console, network]
gates:
  enforces: []
  sets: []
---

# Guided Tour

## Purpose

A tour is one file that describes a path through the UI — go here, click that, expect this text on screen. The same file serves two jobs that are normally written twice:

- **narrate** — a human watches. The tour drives the user's own browser: a cursor glides to each target, a ring highlights it, a click leaves a ripple, a caption trails the pointer, and a banner up top narrates the step. For demos, walkthroughs, and "show me it works."
- **verify** — nobody watches. Same steps, no animation, no dwell time. It captures screenshots, collects console errors and failed/4xx requests, evaluates the `expect` assertions, writes `report.json`, and exits non-zero on failure.

Write the tour once for the demo; keep it as the check.

## Where tours live

The engine ships with the plugin. **Tour definitions live in the consuming project at `.claude/tours/<name>.mjs`** — they describe *that* project's UI, so they belong in *that* project's repo.

Tours are agent-authored and committed. Treat one like any other source file: it goes up in a PR, gets reviewed, and drifts when the UI drifts. A tour nobody reviewed is a tour that will assert on stale copy.

There is no `tours_dir` config key — the path is a fixed convention, and a knob for it would only add a way for the two to disagree.

## Running one

Both modes need a Chromium-based browser exposing CDP on port 9222. See the [`browser` skill](../browser/SKILL.md) for per-browser launch commands and the Arc relaunch one-liner. Not Firefox/Safari.

Prefer the Justfile recipes when the project has the sdlc module wired:

```bash
just sdlc::tour        .claude/tours/checkout.mjs --base-url http://localhost:3000
just sdlc::tour-verify .claude/tours/checkout.mjs --base-url http://localhost:3000 --out .tour-out
```

Otherwise call the installed script directly via the version glob (`${CLAUDE_PLUGIN_ROOT}` is **not** substituted into skill bodies, so don't write it here):

```bash
node ~/.claude/plugins/cache/claudecode-patterns/sdlc/*/scripts/guided-tour.mjs \
  .claude/tours/checkout.mjs --base-url http://localhost:3000 --verify
```

In the plugin dev repo: `node plugin/scripts/guided-tour.mjs <tour> …`.

### Options

| Flag | Meaning |
|------|---------|
| *(default)* | narrate mode |
| `--verify` | verification mode — no theatre, exit non-zero on failure |
| `--base-url <url>` | override the tour's `baseUrl`; relative `goto` paths hang off it |
| `--out <dir>` | screenshots + `report.json` (default `./tour-out`) |
| `--speed <n>` | narration speed multiplier — `2` is twice as fast, verify ignores it |
| `--cdp <url>` | CDP endpoint (default `http://127.0.0.1:9222`) |
| `--close-tab` | close the tour's tab when finished |

It can also be imported: `import { runTour } from '…/guided-tour.mjs'` → `runTour(tour, { mode, baseUrl, outDir, speed, cdpUrl, closeTab })` resolves to the report object.

## Project URLs

Do **not** hardcode URLs or ports in a tour if you can avoid it, and never in this skill (historically, copies of sibling skills carried another project's ports for months). Resolve the base URL in this order and pass it with `--base-url`:

1. `.claude/sdlc.yml` → `browser.frontend_url`, when the project defines one:
   ```yaml
   browser:
     frontend_url: https://localhost:3001
     api_url: http://localhost:3000
   ```
2. An explicit URL in the user's request.
3. The tour's own `baseUrl` field — a per-project default, fine to commit, but `--base-url` beats it.
4. Otherwise: ask once, and offer to persist the answer into `sdlc.yml`.

## Authoring a tour

A tour is a plain ES module exporting a data object. No imports, no runner boilerplate — the engine's CLI supplies both.

```js
export default {
  name: 'checkout',
  baseUrl: 'http://localhost:3000',      // overridden by --base-url
  steps: [
    { goto: '/cart', say: 'Start in the cart', dwell: 2500 },
    { click: 'text=Checkout', say: 'Begin checkout', dwell: 3000 },
    { fill: { selector: 'input[name="email"]', value: 'demo@example.test' }, dwell: 800 },
    { click: 'button[type="submit"]', label: 'place order' },
    { waitFor: 'css=[data-testid="confirmation"]' },
    { say: 'Order confirmed', expect: ['Thank you', 'Order #'], shot: 'confirmation' },
  ],
};
```

A full annotated example ships at [`examples/example-tour.mjs`](./examples/example-tour.mjs). Copy it and rewrite every selector, URL and assertion — it is a shape, not a config.

### Step vocabulary

One step object may carry several keys. They execute in this fixed order: `goto` → `say` (banner) → `waitFor` → `fill` → `click` → `expect` → `shot` → `dwell`.

| Key | Type | What it does |
|-----|------|--------------|
| `goto` | `string` | Navigate. Absolute (`http…`) is used as-is; anything else is appended to the base URL. Waits for `readyState === 'complete'`, then re-injects the overlay. |
| `say` | `string` | Narration for the top banner, rendered as `n/total · text`. **narrate only** — in verify it is just the step's label in the console log. |
| `click` | `string` (selector) | Glide the cursor to the element's centre, ring it, ripple, and dispatch a real CDP mouse press/release. Fails the step if the target isn't found (unless `optional`). |
| `label` | `string` | Caption shown next to the cursor for this step's `click`. Defaults to the element's own text. |
| `fill` | `{ selector, value, label? }` | Click into the field, then set `value` through the native `HTMLInputElement` value setter and dispatch `input` + `change` (React-safe). `label` overrides the caption; a `pass`-matching selector auto-masks the caption. |
| `expect` | `string \| string[]` | Case-insensitive **regex** matched against `document.body.innerText`. Each pattern is recorded as its own assertion in the report. A miss fails the step. |
| `waitFor` | `string` (selector) | Poll for the selector, up to 15s (30 × 500ms). Fails the step if it never appears. |
| `shot` | `string` | Capture a PNG screenshot to `<out>/<name>.png`. Runs in **both** modes. |
| `dwell` | `number` (ms) | How long to hold on this step so a human can read it. Default 3500. **narrate only** — verify skips every dwell, which is most of why it's fast. |
| `optional` | `boolean` | A missing `click`/`fill` target marks the step *skipped* (`·`) instead of failed. This is how login steps no-op against an already-authenticated browser. |

### Selector forms

| Form | Example | Resolution |
|------|---------|------------|
| `text=` | `text=workspace-analyst` | Case-insensitive substring over `a, button, td, th, li, span, div, h1, h2, h3, p, input, label`, keeping only elements with ≤3 children, then the **shortest** match. Approximates "the leaf element that says this". |
| `css=` | `css=[data-testid="row"]` | `document.querySelector` on the remainder. |
| raw CSS | `input[name="email"]` | `document.querySelector` directly — anything not prefixed is treated as CSS. |

`text=` is deliberately loose so tours read well; when a page has several near-identical labels, reach for a `data-testid` instead.

### Authoring guidance

- **Assert on text a human would look for**, not on implementation detail. `expect` reads rendered `innerText`, so it survives refactors that a DOM-structure assertion wouldn't.
- **`say` every step you'd narrate out loud.** It costs nothing in verify and is the whole point in narrate.
- **Mark anything environment-dependent `optional`** — login, cookie banners, first-run modals.
- **Never commit real credentials.** Use a seeded demo account, and prefer `--base-url` + a dev fixture over pointing a tour at production.
- **Screenshot the moments that carry the proof**, not every step. Each `shot` lands in `--out` and is worth attaching to the PR.
- **Keep `dwell` honest**: it is read-time for a human. Tuning it does not change what verify checks.

## The report

`--out/report.json`:

```json
{
  "tour": "checkout", "mode": "verify", "pass": true,
  "steps":          [{ "n": 1, "step": "…", "ok": true, "notes": [] }],
  "assertions":     [{ "step": 6, "expect": "Thank you", "pass": true }],
  "consoleErrors":  ["…"],
  "failedRequests": ["HTTP 404 http://…/api/foo"]
}
```

`pass` is `every step ok && every assertion pass` — and it alone drives the exit code. **`consoleErrors` and `failedRequests` are reported but do not fail the run.** They are usually the most interesting output: the run this capability was built from passed all four assertions *and* surfaced four real 404s the UI was swallowing. Read them every time; decide per project whether to promote them to failures.

## Why raw CDP

The engine speaks the Chrome DevTools Protocol directly over a WebSocket rather than using Playwright, for one specific reason:

> **Playwright's `chromium.connectOverCDP()` hangs against Arc.** The websocket connects, then the handshake never completes and times out after 30s. Verified 2026-08-10 against Arc on Chrome/149.0.7827.156. Raw CDP against the *exact same endpoint* works perfectly — `Target.getTargets`, `Browser.getVersion`, `Target.createTarget` and `Input.dispatchMouseEvent` all respond normally.

A useful side effect: Node 22+ ships a global `WebSocket`, so **the engine has zero npm dependencies** — nothing to install, in any project, in any language. Keep it that way; it must not import outside `node:` builtins.

## Known limits

Honest inventory. This is a proven v1, not a finished product.

- **Both modes need a CDP browser on :9222.** `verify` is not headless and is therefore **not yet a CI gate** — it is a local check today. Making it CI-native means launching a headless Chromium and pointing `--cdp` at it; that path is untested here.
- **`fill` only handles `<input>`.** It goes through `HTMLInputElement.prototype`'s value setter, so `<textarea>`, `<select>` and contenteditable/rich-text editors are unsupported.
- **`expect` only sees `document.body.innerText`.** No attribute, count, style or shadow-DOM assertions. Text inside closed shadow roots is invisible to it.
- **`text=` can match the wrong element** on pages with repeated labels — it picks the shortest match among elements with ≤3 children. Use `css=` with a `data-testid` when precision matters.
- **Timings are fixed**: `waitFor` polls for 15s, navigation waits up to ~22s for `readyState`, every CDP call times out at 30s. None are configurable per step yet.
- **No iframe support** — everything evaluates in the top frame's context.
- **No assertion on console/network health.** They're collected and reported; failing on them is a per-project decision the engine doesn't make.
- **narrate injects an overlay into the page** (`window.__gt`, a few fixed-position divs at max z-index). It's removed at the end of the run, but a page that navigates mid-step gets it re-injected on the next `goto`. Verify mode injects nothing.
- **It opens a new tab in the user's real browser** and drives real mouse events there. Don't run a narrate tour against something destructive, and don't run one while the user is typing.

## Related

- [`browser` skill](../browser/SKILL.md) — CDP connection recipes (incl. the Arc relaunch one-liner), URL resolution from `sdlc.yml`, the headless-auth ladder
- [`browser-driver` skill](../browser-driver/SKILL.md) — headless Playwright evidence capture for design loops (screenshots, selector probes) when you want a check, not a walkthrough
- [`browser-pilot`](../../agents/browser-pilot.md) — the browser teammate; spawn it for exploratory browser work, use a tour when the path is known and worth repeating
