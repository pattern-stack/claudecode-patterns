---
description: Run visual QA on a URL — screenshot, console, network, performance
argument-hint: [url] [--perf]
---

# /verify — Visual QA

Run a visual QA pass against a URL via the user's browser (CDP). Knowledge base: the [`browser`](../skills/browser/SKILL.md) skill.

## Usage

```
/verify                                  # Verify the project frontend (from sdlc.yml browser.frontend_url)
/verify http://localhost:3000/health     # Verify a specific URL
/verify --perf                           # Include performance trace
/verify https://localhost:3001 --perf    # Both
```

**Arguments**:
- `$ARGUMENTS`: Target URL — defaults to `sdlc.yml → browser.frontend_url`; if neither is present, ask. Append `--perf` for performance metrics.

## Steps

### 1. Check CDP connection

Call the chrome-devtools `list_pages` tool. **If it fails**: follow the CDP Connection Check in the `browser` skill (`BROWSER_PREFERENCE`, browser-specific launch command, Arc relaunch recipe). Stop here until connected.

### 2. Navigate

If the target URL differs from the currently selected page, `navigate_page` to it.

### 3. Visual QA pass

Run in parallel where possible:

1. **Snapshot**: `take_snapshot` — accessibility tree
2. **Console**: `list_console_messages` — errors and warnings
3. **Network**: `list_network_requests` — failed requests (filter non-2xx)
4. **Screenshot**: `take_screenshot` — save to `screenshots/verify-{timestamp}.png`, then read it

### 4. Report

```
**Page:** {url}
**Status:** {pass | issues found}

**Console:** {N errors, M warnings} or "clean"
**Network:** {N failed requests} or "all OK"
**Visual:** {brief description of what's on screen}

{Details of any issues found}
```

### 5. Performance (if `--perf`)

1. `performance_start_trace` with `reload: true`, `autoStop: true`
2. Report:

```
**Performance:**
| Metric | Value |
|--------|-------|
| LCP | {ms} |
| CLS | {score} |
| TTFB | {ms} |
```

3. List available insight names for follow-up (`performance_analyze_insight`).

## Tips

- Check the project's dev server is running before reporting a connection failure as a finding.
- Repeated checks: just re-run `/verify` — the CDP connection is reused.
