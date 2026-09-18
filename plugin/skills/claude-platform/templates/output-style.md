# Output style template

Copy into `.claude/output-styles/<name>.md` (project) or `~/.claude/output-styles/<name>.md` (user).

```markdown
---
name: My Style                              # default: filename
description: Shown in /config picker
keep-coding-instructions: false             # true → keep Claude Code's coding-specific system prompt; false → drop it
force-for-plugin: false                     # plugin only: auto-apply when plugin is enabled
---

# Custom Style Instructions

You are an interactive CLI tool that helps users with software engineering tasks.

[Your role / tone / format directives here.]

## Specific behaviors

- {behavior 1}
- {behavior 2}
- {behavior 3}
```

Activate via:
1. `/config` → Output style → pick from list, or
2. `.claude/settings.local.json`:
   ```json
   { "outputStyle": "My Style" }
   ```

Since v2.1.251 a changed style applies from the next message, mid-session; before that it needed `/clear` or a new session. `/output-style <name>` (v2.1.269+) also switches it. From the mobile app or web via Remote Control, only the built-in styles can be listed and selected. Style files are read at startup: restart after creating or editing one. A plugin's style is named `<plugin>:<name>` (for example `sdlc:Driving`), and that full string is the `outputStyle` value; a bare name matches nothing and leaves the default in place. Editing `outputStyle` in `settings.local.json` directly also switches the style from the next message, in both directions (measured on 2.1.277).
