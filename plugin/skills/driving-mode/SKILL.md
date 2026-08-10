---
name: driving-mode
description: "Hands-free voice mode — speak a short spoken-word summary of each turn aloud via TTS, one message at a time, so a user who cannot look at the screen still hears the work happen. Use when the user says \"driving mode\", \"tts on\", \"I'm driving\", \"walking\", \"read it to me\", \"hands-free\" — and stay in it every turn until \"tts off\" or \"I'm parked\"."
when_to_use: User says "driving mode", "tts on", "I'm driving", "I'm walking", "read it to me", "read that out loud", "hands-free", "speak it"; exits on "tts off", "stop tts", "I'm parked".
allowed-tools: Bash
user-invocable: true

# === Project SDLC overlay ===
status: beta
topology: [universal]
consumes: [turn-summary]
produces: [audio]
gates:
  enforces: []
  sets: []
---

# Driving Mode

## Purpose

The user is driving, walking, or otherwise away from the screen, running Claude Code by voice from a phone. **They genuinely cannot read anything for hours at a time.** This skill turns on a per-turn spoken-summary protocol: every turn opens by speaking a two-or-three sentence summary aloud, and the written response becomes an archive nobody reads until later.

Two things make this work in practice rather than in theory. Both were learned the hard way in a live multi-hour session on 2026-08-10, and both are easy to break by "simplifying". They are the first two sections below.

## Rule 1 — one message at a time

**Playback is serialized by a mutex inside the script. Do not remove it, and do not go back to firing raw `afplay`/`say` yourself.**

The original guidance was "background it with `&`, never block." That is correct for one message per turn. Across rapid consecutive turns it produced **three voice messages playing simultaneously** — the listener heard a wall of overlapping speech and understood none of it. Audio has no scrollback: a message lost to overlap is lost for good.

The fix is not "stop backgrounding it". Blocking on playback would stall the turn for the length of the audio. Instead the script separates the two halves of the job:

- **Synthesis stays parallel** — it is the slow part (a network round-trip), and there is no reason two messages can't be synthesized at once.
- **Playback serializes** — messages queue and play back-to-back, no overlap and no dead air. Three simultaneous fires took 10s instead of ~4s: queued, not stalled.

The lock is an atomic `mkdir` in the temp dir, with three safety properties worth keeping:

| Property | Why it's there |
|---|---|
| Stale-lock reclaim (5 min) | a killed process can't strand the queue forever |
| Hard wait ceiling (10 min) | the queue can never deadlock; it gives up and plays |
| `SIGINT`/`SIGTERM`/`SIGHUP` handlers | Ctrl-C releases the lock instead of orphaning it |

Escape hatches, for the rare case:

- `TTS_NO_QUEUE=1` — skip the queue entirely.
- `TTS_INTERRUPT=1` — kill what's playing and jump the queue. **Genuine interrupts only** ("stop, wrong branch"), never routine output. It kills every `afplay`/`say` on the machine, including ones this session didn't start.

## Rule 2 — announce, then wait

**Do not launch straight into a long report.** The user is usually listening to music; audio that starts unannounced is half-missed before they realize it's for them.

When you have something substantial to deliver — a review result, a plan, a multi-part status — speak a **short ping** and then **stop and wait**:

> "I've got the review results ready — say when you're ready to hear them."

Then end the turn. Deliver the full thing on the next turn, once they say they're ready. Their words for it: *"don't just start reading it. Send me a message first to say that you have something."*

What does **not** need the handshake:

- Short acknowledgements — "on it", "starting the build".
- Status lines — "tests are green", "PR is open".
- Anything under ~2 sentences that carries no detail they need to retain.

The handshake costs one extra round-trip. Missing the first half of a report costs the whole report.

## Activation

- **Enter** on: "driving mode", "tts on", "I'm driving", "walking", "read it to me", "read that out loud", "hands-free", or anything equivalent.
- **Stay in mode for every subsequent turn** — this is a persistent mode, not a one-shot. It does not lapse because a turn was short or technical.
- **Exit** on: "tts off", "stop tts", "I'm parked".
- **Confirm activation by speaking it**, not by printing it. A printed "driving mode on" is invisible to someone who just told you they can't see the screen.

## The protocol, every turn while active

1. **Speak first.** Fire the TTS command as the **first tool call of the turn**, before writing visible prose and before other tools. Generating text first just delays the audio.
2. **Lead the written response with the same takeaway**, so the spoken and written versions agree when they read it back later.
3. **Ask every question aloud.** Written prose is invisible while this mode is active — a question that only exists on screen will never be answered. Text is archival.
4. **Clarify misspoken dictation semantically.** Voice input arrives garbled, especially late at night. Answer what they clearly meant, and say plainly when you think a word came through wrong — don't silently act on a literal misreading.

### Summary rules (the spoken text)

- **≤ 75 words**, roughly 25 seconds, 2–3 natural conversational sentences.
- **Lead with the single most important takeaway** or action item.
- **No code, file paths, URLs, or markdown.** Say them in plain words or leave them out — a spoken slash is noise.
- **Phrase decisions as spoken questions**, so a yes/no answer is possible without looking anything up.
- **Prefix errors with "Heads up:"** so attention is flagged before the detail arrives.
- Escape embedded double quotes.

### Do NOT spawn an agent for this

Invoke the script **directly from the lead via Bash**. Do not spawn a speaker subagent or a persistent teammate per utterance — measured at **~6–7s of wake cost per message for no benefit**. Direct Bash starts audio sub-second, and the whole point of this mode is that the audio arrives while the work is happening.

## Running it

```bash
node ~/.claude/plugins/cache/claudecode-patterns/sdlc/0.2.25/scripts/driving-mode.mjs "Build is green. Three tests added, none failing." &
```

Always background it with `&` — the queue inside the script is what prevents overlap, so backgrounding costs nothing and blocking gains nothing.

**Resolve the versioned path once, at activation, then reuse the literal string every turn.** Several plugin versions can sit in the cache at the same time, so a bare `*` glob is ambiguous — it can pick a stale version, and any extra matches would be read aloud as text. Resolve it with:

```bash
ls -d ~/.claude/plugins/cache/claudecode-patterns/sdlc/*/scripts/driving-mode.mjs | sort -V | tail -1
```

In the plugin dev repo: `node plugin/scripts/driving-mode.mjs "…" &`. A `driving-mode` bash shim sits next to the script for projects that vendor or symlink it locally; it prefers `bun` and falls back to `node`.

There is also a Justfile recipe where the sdlc module is wired — convenient, but it adds `just`'s startup to every utterance, so prefer the direct call in this mode:

```bash
just sdlc::say "Build is green."
```

### Options

| Env var | Default | Meaning |
|---|---|---|
| `OPENAI_API_KEY` | — | API key; highest precedence |
| `TTS_KEY_FILE` | `~/.config/claude-tts/key` | file containing the key |
| `TTS_MODEL` | `tts-1` | OpenAI speech model |
| `TTS_VOICE` | `nova` | OpenAI voice |
| `TTS_NO_QUEUE` | unset | `1` skips the playback queue |
| `TTS_INTERRUPT` | unset | `1` kills current playback and jumps the queue |

## How a voice is resolved

1. **Key**: `OPENAI_API_KEY`, else the file at `TTS_KEY_FILE`, else `~/.config/claude-tts/key`.
2. **With a key** → OpenAI `/v1/audio/speech` (`tts-1`, `nova`) → mp3 in the temp dir → `afplay` → file deleted.
3. **Without a key, or if the OpenAI call fails** → macOS `say -v Samantha -r 195`. Degraded but still hands-free.

Nothing in the resolution chain is project-specific — no repo path and no product name — so the same key serves every project on the machine.

A successful OpenAI run exits 0 and prints nothing. An `openai tts …` or `tts error: …` line on stderr means it fell back to the system voice; the user still heard something, but check the key.

### Setting up the key

```bash
mkdir -p ~/.config/claude-tts
printf '%s' 'sk-…' > ~/.config/claude-tts/key
chmod 600 ~/.config/claude-tts/key
```

**Migrating from a project-local TTS setup.** Earlier versions of this capability lived inside a single project and read a key from a project-named path such as `~/.config/dealbrain-tts/key`. Either copy it to the neutral location above, or point at it without moving anything:

```bash
export TTS_KEY_FILE=~/.config/dealbrain-tts/key
```

Once this skill is in use, **delete the project-local copy of the old script.** Two copies use two different lock files, so they do not queue against each other — which is exactly the overlap bug Rule 1 exists to prevent.

## Known limits

Honest inventory. This is a v1 proven across one long live session, not a finished product.

- **macOS only.** Playback is `afplay` and the fallback voice is `say`. On Linux or Windows the script will fail to play anything; there is no `mpg123`/`ffplay`/PowerShell path yet.
- **The mutex is per-machine, per-script-copy.** It's a temp-dir lock keyed by name, so it serializes every caller of *this* script on *this* machine — but a second, differently-named copy of the script has its own lock and will happily talk over this one.
- **`TTS_INTERRUPT=1` is a blunt instrument** — `pkill` against `afplay` and `say` process-wide. It will stop unrelated audio played by those tools.
- **The stale-lock reclaim is time-based, not PID-based.** A synthesis that legitimately takes over 5 minutes could have its lock reclaimed by a waiter. In practice `tts-1` returns in a second or two.
- **No text sanitation.** Whatever you pass is what gets spoken — markdown, backticks and URLs included. Keeping them out is the model's job, enforced by the summary rules above, not the script's.
- **Fixed voice parameters.** Model and voice are overridable; rate, pitch and the fallback voice are not.
- **Every utterance is a network call** to OpenAI, billed per character, and it needs connectivity — a dead zone falls back to the system voice mid-drive, which sounds different but keeps working.
- **No transcript.** Spoken text is not recorded anywhere except the written response you produce alongside it.
- **Nothing enforces the mode.** Staying in driving mode is a discipline the model holds across turns; there is no hook that fails a turn which forgot to speak.

## Related

- [`handoff` skill](../handoff/SKILL.md) — end-of-session ceremony; a spoken handoff summary pairs well with this mode
- [`guided-tour` skill](../guided-tour/SKILL.md) — the sibling "one artifact, two modes" capability, and the house pattern this skill's script layout follows
