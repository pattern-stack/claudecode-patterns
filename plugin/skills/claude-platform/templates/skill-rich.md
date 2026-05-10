# Rich skill template

Copy this into `.claude/skills/<your-skill>/SKILL.md` and trim to fit. Only `description` is recommended; everything else is optional.

```markdown
---
# === Identity ===
name: my-skill                              # default: directory name
description: One-sentence "what + when". Drives auto-invocation. Put the key use case first.
when_to_use: Trigger phrases or example user requests. Combined with description, capped at 1,536 chars in skill listing.

# === Invocation control ===
disable-model-invocation: false             # true → only user can /invoke
user-invocable: true                        # false → hide from / menu (Claude can still invoke)

# === Arguments ===
argument-hint: <branch> [scope]             # autocomplete display
arguments: [branch, scope]                  # named positional ($branch, $scope) — or use $0/$1

# === Tool pre-approval ===
allowed-tools: Read Grep Glob Bash(git *)   # pre-approved while skill is active

# === Model + effort ===
model: inherit                              # sonnet | opus | haiku | <full id> | inherit
effort: inherit                             # low | medium | high | xhigh | max | inherit

# === Forking (run in subagent context) ===
context: fork                               # set to fork to spawn a subagent
agent: Explore                              # built-in (Explore/Plan/general-purpose) or custom name

# === Path gating (auto-invocation only fires for matching files) ===
paths:
  - "**/*.tsx"
  - "src/**/*.ts"

# === Lifecycle hooks scoped to this skill ===
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "${CLAUDE_SKILL_DIR}/scripts/validate.sh"

# === Shell for !`...` injection ===
shell: bash                                 # bash | powershell
---

# {Title}

## Purpose
{One paragraph. The body lives in context for the rest of the session once invoked — every line is recurring tokens.}

## Dynamic context
- Diff: !`git diff $branch`
- Status: !`git status --short`

## Instructions
1. {standing instruction}
2. {standing instruction}
3. {standing instruction}

## Bundled resources
- Reference: ${CLAUDE_SKILL_DIR}/reference.md
- Helper script: ${CLAUDE_SKILL_DIR}/scripts/helper.py
```

## Bundled file layout

```
my-skill/
├── SKILL.md
├── reference.md           # detail Claude reads on demand
├── examples/
│   └── sample.md
└── scripts/
    └── helper.py          # executed via Bash, not loaded into context
```

Reference bundled files from SKILL.md so Claude knows what they contain. Use `${CLAUDE_SKILL_DIR}` in `!`...`` so script paths survive any cwd.

Keep SKILL.md under ~500 lines. Push detail into separate files.
