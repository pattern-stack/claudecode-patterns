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

System prompt is fixed at session start (for prompt caching). Changes apply on next session.
