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

### 1. Pick the mode

- Instruction concerns *the user's* page/session ("my screen", "I'm logged in", prod debugging) → **chrome-devtools**.
- Independent check that shouldn't disturb the user → **playwright** (headless; see the skill's auth ladder if the target needs login).
- Audit request → **lighthouse**.

### 2. Check the connection (chrome-devtools mode)

Call the chrome-devtools `list_pages` tool (plugin-namespaced — discover via ToolSearch if needed).

**If it fails**: follow the CDP Connection Check in the `browser` skill — `BROWSER_PREFERENCE` from `.claude/settings.local.json`, browser-specific launch command (Arc has a dedicated relaunch recipe). Stop until connected.

### 3. Resolve URLs

Per the skill's Project URLs section: `sdlc.yml → browser:` block → explicit URL in the instruction → ask.

### 4. Interpret and execute

Full toolkit (short tool names; all plugin-namespaced):

**Navigation & interaction** (chrome-devtools): `navigate_page`, `click`, `fill`, `fill_form`, `hover`, `type_text`, `press_key`, `drag`, `upload_file`

**Inspection** (chrome-devtools): `take_snapshot` (preferred), `take_screenshot`, `list_console_messages`, `list_network_requests`, `evaluate_script`, `get_console_message`, `get_network_request`

**Performance** (chrome-devtools): `performance_start_trace` / `performance_stop_trace`, `performance_analyze_insight`

**Headless** (playwright): `browser_navigate`, `browser_click`, `browser_snapshot`, `browser_take_screenshot`, `browser_evaluate`, `browser_console_messages`, `browser_network_requests`

**Auditing** (lighthouse): `run_audit`, `get_performance_score`, `get_accessibility_score`, `get_seo_analysis`, `get_core_web_vitals`, `get_lcp_opportunities`, `compare_mobile_desktop`, `find_unused_javascript`

### 5. Report back

- Describe what happened; show screenshots when visual output was requested or relevant.
- Report errors encountered; suggest follow-ups when appropriate.

## Approach

- **Always snapshot first** to understand page structure before interacting.
- **Use element uids** from the snapshot — never guess coordinates.
- **Chain actions naturally** — "click X then fill Y" is one flow.
- **Be conversational** — interactive, not a formal report.
- **Ask if unclear** before acting.
