# Gate 0: watch-style — watchers a person can read

Brief: `hq/briefs/sdlc/20261105-watch-style.md` (on hq branch `hq/work-watch-style`).
Status: **Gate 0 approved by Doug (Nov 5), with the defaults below.** HQ: content matching, so the header stays on stdout; `hc read` does not strip ANSI, so the heartbeat is TTY-only. As built, `NO_COLOR` drops only colour; `WATCH_PLAIN=1` drops the heartbeat and sentences too.

## The convention

1. **Name says what it watches.** `hc run --name` is a verb-object phrase, ≤32 chars:
   `watch-board-and-leads` (was `loop-watch`), `deploy-main-loop`, `refresh-lead-context`.
   Labels: `role=watch` (exits on the first event, parent re-arms) or `role=loop` (runs a window, keeps going),
   plus `owner=<display name>` (e.g. `owner=hq-5`).
2. **Header on start.** One line: `● <what> · every <n> · until <HH:MM> · wakes <owner>`.
3. **Heartbeat.** One dim line rewritten in place (`\r` + clear-line) after every check:
   `· 22:14:40 check 37 · 0 blocked · 4 working · 2 PRs open · 0 Gate 1s`. Never scrolls, so the pane is never blank and never floods.
4. **Events.** The machine line the parent parses prints **first and byte-identical to today** (`22:15 EVENT blocked: web`),
   uncoloured. On a TTY a coloured plain-English line follows it:
   green `✓` done/ok · yellow `◐` waiting on someone · red `✗` failure. Time + one sentence.
5. **Clear end.** `■ stopped: <why>` (event fired / window over / failure / interrupted, via an EXIT/INT trap),
   so a finished pane in the sidebar explains itself.
6. **Plain when piped.** Colour, the heartbeat and the `✓`/`■` decorations only when stdout is a TTY and `NO_COLOR` is unset.
   Piped or logged, output is exactly today's lines (plus the header and `stopped:` lines, as plain text).
   `WATCH_PLAIN=1` forces plain for tests.
7. **Typed input.** `watch_header` does `exec </dev/null` and `stty -echo` when stdin is a TTY (restored on exit),
   so Escape and stray keys never print `^[`.

## The helper (after Gate 0)

`plugin/lib/watch.sh`, sourced: `watch_header <what> <every> <until> <wakes>`, `watch_beat <text>`,
`watch_event <ok|wait|fail> <machine-line> <sentence>`, `watch_end <why>`. Pure bash, no deps.
Tests: `plugin/lib/watch.test.sh` (piped output byte-equal to a golden; TTY path under `script -q`; `NO_COLOR`; stdin ignored).
Doc: `plugin/skills/skill-authoring/` gains a short `watchers.md` (naming + writing), linked from `SKILL.md`.
Then an hq PR: the three loops source the helper, get renamed, event lines unchanged.

## Open questions for Doug

- **Machine line first, then the human line** (as the brief says), or one coloured line that *is* the machine line? I propose
  keeping them separate: HQ's parsing never has to change, and the human sentence can say more.
- `deploy-main-loop` prints a line per step today. Keep those step lines (as `◦` progress, dim), or fold them into the heartbeat?
  I propose: keep them, they're the deploy's story.
- Heartbeat counts cost nothing extra in `loop-watch` (it already computes them), but the PR/Gate 1 counts only refresh every
  3rd tick; the beat shows the last known value with its age. OK?
- loop-watch runs as HQ's child, so its exit note (or `hc read`) is what HQ parses. With a header above it, the `EVENT`
  line is no longer the pane's first line. I'll make HQ match on `EVENT`/`TIMEOUT`/`FAIL` rather than position; if HQ
  depends on "first line", the header could go to stderr instead.
- To confirm before building: does `hc read` / the parent note strip ANSI and collapse `\r` rewrites? If not, the helper
  writes the heartbeat only to the TTY and the parent's view stays plain either way.

## Mock panes

Colour key: `[grn]` green, `[yel]` yellow, `[red]` red, `[cyn]` cyan bold, `[dim]` dim/grey, `[/]` reset.
The `·` heartbeat line is the single line that rewrites itself; it's shown at its latest state.

### 1. `watch-board-and-leads` (role=watch, owner=hq-5) — fired on a blocked lead

```
[cyn]● watching board presses, blocked leads, idle leads, validated PRs, Gate 1s, usage[/] [dim]· every 20 s · until 23:50 · wakes hq-5[/]
22:31 EVENT blocked: web
[yel]◐ 22:31  web is blocked on a permission prompt; hq-5 needs to answer it.[/]
[dim]■ stopped: event fired after 41 checks (13 min); hq-5 re-arms[/]
```
While running (before the event), the pane shows just the header and:
```
[dim]· 22:30:40  check 41 · presses 0 · blocked 0 · working 4/7 · validated PRs 2 (1 min ago) · Gate 1s 0[/]
```

### 2. `deploy-main-loop` (role=loop, owner=hq-5) — one deploy, then a red one

```
[cyn]● deploying dugshub/maplelog main when it moves and CI is green[/] [dim]· every 60 min · until 06:00 · wakes hq-5 on failure[/]
22:00 publishing main 4f2c1a9 (last deployed 9be0d33; GitHub CI green)
22:07 publish 18822341 ok; deploying
22:11 deployed 4f2c1a9 (run 18822398); route checks: all ok
[grn]✓ 22:11  main 4f2c1a9 is live on maplelog.lab.dugsapps.dev; every route check passed.[/]
23:11 FAIL: main 7a01e3c is red on GitHub CI: frontend-build; not deployed
[red]✗ 23:11  main 7a01e3c failed frontend-build on GitHub CI, so it wasn't deployed; the old pods keep serving.[/]
[red]■ stopped: a failure (main 7a01e3c red); hq-5 is told[/]
```

### 3. `refresh-lead-context` (role=loop, owner=hq-5) — window ended quietly

```
[cyn]● refreshing idle leads over 200k context[/] [dim]· every 3 min · until 01:00 · wakes nobody (prints a line per refresh)[/]
23:42 api: refreshed at 231k
[grn]✓ 23:42  api wrote its status file, was cleared, and reloaded from its brief (was 231k).[/]
00:15 recorder: no status update, not cleared
[yel]◐ 00:15  recorder didn't update its status file in 10 min, so it wasn't cleared; it's still at 214k.[/]
[dim]■ stopped: window over at 01:00 (2 leads checked over limit, 1 refreshed)[/]
```

Piped (`hc read` with colour stripped, a log, or `NO_COLOR=1`), mock 1 is exactly:
```
● watching board presses, blocked leads, idle leads, validated PRs, Gate 1s, usage · every 20 s · until 23:50 · wakes hq-5
22:31 EVENT blocked: web
■ stopped: event fired after 41 checks (13 min); hq-5 re-arms
```
(Piped: no heartbeat, and the coloured sentence is dropped since the machine line already says it.)
