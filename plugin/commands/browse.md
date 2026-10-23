---
description: Interact with the user's browser — navigate, click, type, inspect, or anything else
argument-hint: [instruction...]
---

# /browse — Browser Interaction

Open-ended browser interaction. Tell Claude what to do in a browser and it does it. Knowledge base: the [`browser`](../skills/browser/SKILL.md) skill.

## Usage

```
/browse go to the app and click the settings button
/browse fill out the login form with test@example.com / password123
/browse check if the modal opens when I click "New Item"
/browse take a screenshot of the current page
/browse what's on my screen right now?
/browse run a lighthouse accessibility audit on the frontend
```

**Arguments**:
- `$ARGUMENTS`: Natural-language instruction describing what to do in the browser.

## How It Works

This session has no browser tools of its own. The browser servers belong to the **`browser-pilot`** agent and start only while it runs, so every browser action goes through it. The plugin installs it to `~/.claude/agents/` (`hooks/ensure-browser-agent.sh`); if the Agent tool doesn't list `browser-pilot`, start a new session and try again.

### 1. Pick the mode

- Instruction concerns *the user's* page/session ("my screen", "I'm logged in", prod debugging) → **chrome-devtools**.
- Independent check that shouldn't disturb the user → **playwright** (headless; see the skill's auth ladder if the target needs login).
- Audit request → **chrome-devtools** `lighthouse_audit` (accessibility, SEO, best practices) plus a performance trace for speed. Needs the CDP connection.

### 2. Resolve URLs

Per the skill's Project URLs section: `sdlc.yml → browser:` block → explicit URL in the instruction → ask.

### 3. Hand it to browser-pilot

Spawn the `browser-pilot` agent with the mode, the resolved URL and the user's instruction as one complete task. It checks the CDP connection itself in chrome-devtools mode (the `browser` skill's CDP Connection Check) and reports back in its standard format.

- **Headless (playwright) work must be one complete task.** browser-pilot's servers restart on every run, including a follow-up `SendMessage`, so the headless page, its cookies and its JS state are gone by the next run. Put the whole flow (navigate, act, check, screenshot) in one prompt.
- **chrome-devtools work can continue.** The page lives in the user's browser, so a follow-up `SendMessage` to the same agent picks up where it left off.

### 4. Report back

- Relay what browser-pilot found; show screenshots when visual output was requested or relevant.
- Report errors encountered; suggest follow-ups when appropriate.

## Approach

- **Chain actions naturally** — "click X then fill Y" is one flow, and one browser-pilot task.
- **Be conversational** — interactive, not a formal report.
- **Ask if unclear** before acting.
