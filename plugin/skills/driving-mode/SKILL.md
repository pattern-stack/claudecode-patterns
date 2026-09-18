---
name: driving-mode
description: "Hands-free mode — switch this project to the Driving output style, so every reply is written to be heard (the user's phone reads it aloud) and long work runs in Herdr tabs. Use when the user says \"driving mode\", \"I'm driving\", \"walking\", \"hands-free\", \"read it to me\"; leave it on \"I'm parked\", \"back at the keyboard\", \"driving mode off\"."
when_to_use: User says "driving mode", "I'm driving", "I'm walking", "hands-free", "read it to me"; exits on "I'm parked", "back at the keyboard", "driving mode off".
allowed-tools: Bash, Read
user-invocable: true

# === Project SDLC overlay ===
status: beta
topology: [universal]
consumes: [turn-summary]
produces: [spoken-text]
gates:
  enforces: []
  sets: []
---

# Driving Mode

The user is driving or walking and cannot look at the screen. Their phone reads replies aloud. The rules for how a reply must sound live in one place, the **Driving output style** (`output-styles/driving.md` in this plugin). This skill turns that style on and off by voice.

Why a skill at all: the phone can select only Claude Code's built-in output styles, so the user cannot pick Driving from there. They say "I'm driving" and this skill does it for them.

## Entering

1. **Select the style for this project.** It is the same setting `/output-style` writes, in the session's primary working directory (the one named in your environment, not wherever the shell has since `cd`'d):

   ```bash
   f="<primary working directory>/.claude/settings.local.json"
   mkdir -p "$(dirname "$f")"; [ -s "$f" ] || echo '{}' > "$f"
   jq -r '.outputStyle // "none"' "$f"
   jq '.outputStyle = "sdlc:Driving"' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
   ```

   The first `jq` prints the style that was set before. If it is not `none` or `default`, remember it for the exit step. The value must be the full name, plugin prefix included: a bare `Driving` matches no style and silently leaves the default in place.

2. **Read the style and follow it from this reply on.** Its rules are in `${CLAUDE_SKILL_DIR}/../../output-styles/driving.md`; read that file now. Claude Code re-reads the setting and applies the style itself from the next message (measured on 2.1.277: a file edit switches it mid-session both ways, as `/output-style` does), and sessions started later in this project open in it.

3. **Confirm in one spoken sentence**, for example: "Driving mode is on. I'll keep it short and speakable."

## Leaving

On "I'm parked", "back at the keyboard" or "driving mode off", put back the style that was set before. Otherwise remove the setting:

```bash
f="<primary working directory>/.claude/settings.local.json"
jq 'del(.outputStyle)' "$f" > "$f.tmp" && mv "$f.tmp" "$f"
```

To put back an earlier style, write `jq '.outputStyle = "<previous>"'` instead of the `del`. Confirm in one sentence and return to normal formatting.

## History

Until 0.2.29 this skill spoke each turn aloud through OpenAI text-to-speech and `afplay`, with a playback queue so that messages could not overlap. The phone now reads replies itself, so the voice script, its key and the `just sdlc::say` recipe were removed. The two rules that session learned still hold in the style: one idea at a time, and give the headline before a long report.
