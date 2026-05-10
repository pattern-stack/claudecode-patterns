# Cookbook: skills that run in a subagent (`context: fork`)

A skill with `context: fork` becomes the **task** for a subagent rather than running in your main conversation. The skill body is the prompt; the `agent:` field picks the executor.

## Why fork

- Verbose intermediate context (file reads, log greps, doc dumps) stays out of main.
- Specialized agent type (e.g. `Explore` is read-only, optimized for codebase research).
- Skill's tool restrictions and permissions are inherited from the agent type, not from your main session.

## When NOT to fork

- The skill is **reference content** ("our API conventions"). The subagent gets the guidelines but no task and produces nothing useful. Forks need explicit instructions.
- You need to iterate or refine — fork output comes back as a single result.

## Pattern: research skill running in Explore

```yaml
---
name: deep-research
description: Research a topic thoroughly using read-only codebase exploration
context: fork
agent: Explore
allowed-tools: Bash(rg *), Bash(grep *)
---

Research $ARGUMENTS thoroughly.

1. Find relevant files via Glob and Grep
2. Read and analyze the code
3. Summarize findings with specific file:line references
4. Flag uncertainties or gaps explicitly
```

What happens:
1. Each `!`...`` runs at preprocess time (none here).
2. New isolated context spawns with the `Explore` agent type's model + tools + permissions.
3. The skill body becomes that subagent's user-message-prompt.
4. The subagent runs to completion; the result returns to your main conversation.

## Pattern: PR summary with dynamic context

```yaml
---
name: pr-summary
description: Summarize changes in a pull request
context: fork
agent: Explore
allowed-tools: Bash(gh *)
---

## Pull request context
- Diff: !`gh pr diff`
- Comments: !`gh pr view --comments`
- Files: !`gh pr diff --name-only`

## Your task
Summarize this PR in 3 bullets. Flag anything risky.
```

`gh` runs **before** the fork is spawned. The subagent receives the rendered prompt with the PR data inlined.

## Pattern: codified review against a checklist file

Bundle reference docs alongside `SKILL.md`:

```
.claude/skills/security-review/
├── SKILL.md
└── checklist.md
```

```yaml
---
name: security-review
description: Audit code changes for security issues against the bundled checklist
context: fork
agent: general-purpose
allowed-tools: Read, Grep, Glob, Bash(git *)
---

## Diff
!`git diff $ARGUMENTS`

Review against ${CLAUDE_SKILL_DIR}/checklist.md. Report findings with severity and remediation.
```

`${CLAUDE_SKILL_DIR}` resolves at preprocess time to the absolute path of the skill, so the subagent can read the bundled file regardless of cwd.

## Pattern: forked custom subagent (your own role)

`agent:` accepts **any** subagent name from `.claude/agents/`, not just built-ins. Compose a domain agent + a skill:

```yaml
# .claude/agents/security-auditor.md
---
name: security-auditor
description: Senior security auditor; identifies risks and proposes fixes
tools: Read, Grep, Glob, Bash
model: opus
---
You are a senior security engineer specializing in OWASP, AuthN/Z, and supply chain.
```

```yaml
# .claude/skills/audit-pr/SKILL.md
---
description: Run a security audit against the current PR
context: fork
agent: security-auditor
---
!`gh pr diff`

Audit this PR for security risks. Report critical / warning / suggestion.
```

## Pitfalls

- **Forks don't inherit your conversation history.** They get the rendered skill, plus CLAUDE.md and git status. Pass anything you need.
- **Forks are "use once" by design.** No way to follow up — for that, spawn a named subagent instead and use `SendMessage`.
- **`disable-model-invocation`** is recommended for fork skills with side effects, since they can otherwise auto-trigger.
- **Tool permissions** come from the agent type. If the agent is `Explore` (read-only), the skill cannot edit files even if the body says to.
