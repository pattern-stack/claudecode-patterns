# Watchers and loops a person can read

A watcher is a background program an agent starts to wake it on a change (`role=watch`: it exits on the first event
and its owner re-arms it). A loop runs for a window and keeps going (`role=loop`). Under `hc`, each one shows in the
herdr sidebar under the agent that started it, and people open them. Write them so the pane explains itself.

The helper is `plugin/lib/watch.sh` (pure bash, sourced). Its tests are `plugin/lib/watch.test.sh`.

## Naming

- **The name says what it watches**: verb and object, lowercase, at most 32 characters.
  `watch-board-and-leads`, `deploy-main-loop`, `refresh-lead-context`. Not `loop-watch`.
- **Labels**: `role=watch` or `role=loop`, and `owner=<the owner's display name>`.

```sh
hc run --bg --name watch-board-and-leads --label role=watch --label owner=hq-5 \
  env WATCH_OWNER=hq-5 bash scripts/ops/watch-board-and-leads.sh 60
```

## Writing one

```bash
. "$PLUGIN/lib/watch.sh"
watch_header "watching board presses, blocked leads, validated PRs" "20 s" "$(watch_hhmm "$deadline")" "${WATCH_OWNER:-hq}"
while :; do
  # … check …
  watch_beat "check $tick · blocked 0 · validated PRs 2 ($(watch_age "$prs_at"))"
  [ -n "$blocked" ] && {
    watch_event wait "$(date +%H:%M) EVENT blocked: $blocked" "$blocked is blocked on a permission prompt."
    watch_end "event fired after $tick checks"; exit 0; }
  sleep 20
done
```

| Call | Prints | When |
|---|---|---|
| `watch_header <what> <every> <until> <wakes>` | `● <what> · every … · until … · wakes …` | always (coloured on a TTY) |
| `watch_beat <text>` | `· HH:MM:SS  <text>`, one dim line rewritten in place | TTY only |
| `watch_line <text>` | the text as is (step lines) | always |
| `watch_event <ok\|wait\|fail> <machine> <human>` | the machine line as is, then `✓`/`◐`/`✗ HH:MM  <human>` | machine line always; human line on a TTY, or when there is no machine line |
| `watch_end [--fail] <why>` | `■ stopped: <why>` | always; the EXIT trap writes one if you don't |
| `watch_hhmm <epoch>`, `watch_age <epoch>` | `23:50`, `3 min ago` | helpers for the header and the beat |

## Rules

1. **Header on start**: what it watches, how often, when it gives up, who it wakes.
2. **A heartbeat after every check**, with the counts it saw. A count refreshed less often shows its age. The pane is
   never blank and never floods.
3. **The machine line comes first and never changes.** Parents match it by content (`EVENT`, `TIMEOUT`, `FAIL`), so
   the helper never colours or rewrites it. The human sentence is extra: plain words, one sentence, what happened and
   who acts. Green `ok` for done, yellow `wait` for waiting on someone, red `fail` for failures.
4. **A clear end**: `watch_end` before every exit, saying why. `exit` without it still gets a line from the trap
   (`finished`, `exited with code N`, `interrupted`, `terminated`) and keeps the exit code.
5. **Plain when piped**: the heartbeat and the human sentences need stdout to be a TTY; colour also needs `NO_COLOR`
   unset. `WATCH_PLAIN=1` forces plain output. `hc read` and parent notes do not strip ANSI or collapse `\r`, and a
   pane under `hc` *is* a TTY, so a parent reading the pane sees the escapes. Match by content, never by position or
   by whole-line equality.
6. **Typed input is ignored**: `watch_header` turns terminal echo off and points stdin at `/dev/null`, so Escape and
   stray keys don't print `^[`. Echo comes back on exit. Don't read stdin in a watcher.
7. **The helper owns the EXIT, INT and TERM traps.** If you need your own exit cleanup, call `_watch_on_exit $?` at
   the end of your trap.
