# claudecode-patterns

**Run Claude Code as a team.** Plan-first, gate-disciplined, customizable to your stack — without forking anyone's prompts.

---

## TL;DR

A team-grade Claude Code distribution. Configure via [`sdlc.yml`](.claude/sdlc.yml) instead of forking prompts.

<h3 align="center">
  <a href=".claude/agents/planner.md">Plan</a>&nbsp;&nbsp;→&nbsp;&nbsp;
  <a href=".claude/agents/specifier.md">Strategy</a>&nbsp;&nbsp;→&nbsp;&nbsp;
  <a href=".claude/agents/implementer.md">Code</a>&nbsp;&nbsp;→&nbsp;&nbsp;
  <a href=".claude/agents/validator.md">Review</a>
</h3>

<p align="center"><em>Hard gates between each. The implementer agent <b>refuses</b> to start without strategy approval.</em></p>

- **`/orchestrate` runs whole epics in parallel** — queue approved issues, wake up to validated PRs. Each issue runs through its own gates independently.
- **Swap task management tools** (Linear ↔ GitHub Issues ↔ Jira) by changing one config value. Same agents, same commands.
- **Tune artifact shapes** (specs, plans, session logs, anything you author) through dialog with the [canvas-author agent](.claude/agents/canvas-author.md). Schema-validated, versioned, no prompt edits.

## Quickstart

```bash
# 1. Clone and copy the .claude/ layer to your project
git clone https://github.com/pattern-stack/claudecode-patterns
cp -r claudecode-patterns/.claude  your-project/
cp    claudecode-patterns/Justfile your-project/
cp -r claudecode-patterns/scripts  your-project/

# 2. Adjust the dial (one file)
$EDITOR your-project/.claude/sdlc.yml
#   language: typescript
#   quality_profile: strict
#   task_management: linear     ← or github
#   team_key: ACME              ← your team's prefix in the task management tool

# 3. Verify the config
cd your-project
just verify                     # invariants pass — config is valid

# 4. Run the loop
/plan "Add Redis caching to the user service"
# (iterate, approve)
/sync-issues
/design ACME-101                # review in your task management tool, label state:strategy-approved
/develop ACME-101               # or /orchestrate state:strategy-approved
```

That's the whole flow. The hard part is the first 10 minutes deciding what your `sdlc.yml` should say. After that, the system runs.

A native Claude Code plugin distribution is in flight; when it lands, the install collapses to a single-line command with `extends:` overrides for project-specific tweaks.

---

## The problem

If you've put Claude Code in front of a team, you've seen this:

- **Review is the bottleneck.** Devs spend more time reviewing AI-generated code than writing it (11.4 vs 9.8 hrs/week, [Datadog 2026](https://www.datadoghq.com/state-of-ai-engineering/)).
- **Plans shift after you've started.** You realize issue #3 should land before #2, scope leaks from one issue into another, or you drop one entirely. By the time you reorder, the agent's halfway through downstream work against the old plan. The morning evaporates into rebase triage.
- **The bottom of the stack absorbs everything.** Without enforced scope boundaries, the agent top-loads — early PRs balloon, late PRs are thin or duplicate. Splitting them post-hoc is harder than starting clean.
- **One change cascades.** A reviewer suggests an architectural rethink in PR #1. Fixing it cascades the same conflict across PRs #2–#5. Each follow-up in #1 cascades again. The cost of changing your mind grows linearly with stack depth.
- **Each session starts from zero.** The agent rediscovers questions you already answered, suggests approaches you already rejected. Multi-session continuity is where most teams give up.
- **Customization means forking prompts.** Different rules for one project? Edit six agent files. Swap Linear for GitHub? Edit them again. Now your team has six branches of the same prompts and nobody knows whose is canonical.

Most "AI for teams" tooling addresses pieces of this. None addresses all of it without locking you into one task management tool, one workflow, and one prompt style.

## What this distribution gives you

Three load-bearing features:

### 1. Plug-and-play task management

Your task management tool is a configuration value, not a hardcoded dependency.

```yaml
# .claude/sdlc.yml
task_management: linear   # or github, or jira
```

The agents don't change. The commands don't change. The same `/plan`, `/design`, `/develop`, `/orchestrate` workflow works against whichever task management tool you use today — or the one you migrate to next quarter.

This works because every domain capability is modeled as a **primitive**: a small file declaring how one specific vendor maps to the same domain shape the agents already expect. Linear, GitHub Issues, Jira sit behind the same interface — `find issue by key`, `post comment`, `apply label`, `list children`. When you need a task management tool we don't ship, you author one new primitive: a single file that maps that vendor's API to the domain shape. The agents and commands don't change. The work is bounded — adapter logic lives in the primitive; nothing else needs to know about it.

The same pattern extends to [language conventions](.claude/primitives/language/typescript.md), [quality profiles](.claude/primitives/quality/strict.md), [commit styles](.claude/primitives/commit/conventional.md), and [task management adapters](.claude/primitives/task-management/linear.md). Want strict TypeScript with typecheck-on-save in one project and forgiving Python in another? Two values in `sdlc.yml`. Same agents work both.

### 2. Customize without editing fifteen markdown files

`sdlc.yml` is the dial. You change behavior by editing one YAML, not by hunting through agent / skill / command files.

```yaml
language: typescript           # primitives/language/typescript.md gets loaded
quality_profile: strict        # primitives/quality/strict.md
commit_style: conventional     # primitives/commit/conventional.md
team_key: ACME                 # team key
develop_team:                  # who shows up for /develop
  - implementer
  - validator
orchestrate_concurrency: 3     # how many issues run in parallel
```

Want to pin a different commit style for one project? Change one line. Add a custom validator step? Drop a primitive. The agents read the config — you don't have to fork prompt files to change behavior.

This is what makes onboarding a team trivial — clone the repo, adjust two values, your AI behaves consistently for everyone. No "whose `~/.claude/` setup is the source of truth" debate.

> Today the install is `cp -r .claude/` into your project. A native Claude Code plugin distribution is in flight; when it lands, the same behavior moves to a single-line install with `extends:` overrides for project-specific tweaks.

### 3. Versioned, tunable contracts for every artifact your AI produces

Most tooling treats AI output as the side effect of a prompt. Want a different shape? Edit the prompt. Want a new kind of artifact? Write another prompt. Six PRs later, your team's "agreed format" has drifted into six variants and nobody knows whose is canonical.

The canvas system inverts that. Every artifact your AI produces — [specs](.claude/canvases/spec/README.md), [plans](.claude/canvases/plan/README.md), [session logs](.claude/canvases/session/README.md), the [per-turn envelope every phase agent emits](.claude/canvases/envelope/README.md), the next thing you haven't built yet — is governed by a **canvas**: a typed contract with tunable knobs, schema-validated, versioned, and read by every consumer downstream (agents, validators, analytics, future render targets).

```bash
just canvas-dev      # knob-level dialog with the canvas-author agent (developer voice)
just canvas-seller   # outcome-framed dialog — hides system mechanics, works from samples
```

What this unlocks:

- **Tune via knobs, not prompts.** Want shorter specs? Adjust verbosity. Want validator reports on a different surface? Tune distribution rules. The producing agent reads the canvas at runtime — no prompt edit required, no fork.
- **Reverse-engineer from examples.** Hand the [`canvas-author` agent](.claude/agents/canvas-author.md) a daily brief, post-mortem, or PR summary you like. It extracts the structural shape, infers knob values with confidence ratings, and emits a reusable canvas you can tune from there. The "what does good look like" conversation becomes a contract.
- **Two voices, one agent.** [Developer voice](.claude/output-styles/canvas-flow-developer.md) speaks knobs and schemas. [Seller voice](.claude/output-styles/canvas-flow-seller.md) speaks outcomes and samples — hides system mechanics entirely, lets non-technical users iterate via "shorter, drop the diagrams, add a TLDR." Same agent, different surface, one flag to swap.
- **Progressive disclosure as a discipline.** Both voices default to terse headlines and ratchet up detail only when the user pulls. Replaces the "wall of options" that kills configurability for anyone who doesn't already know the system.
- **Schema-enforced.** Each canvas validates against a JSON Schema in CI. No silent drift between what the agent produces and what downstream consumers expect.
- **Open-ended.** Daily standups, RFC drafts, post-call summaries, weekly reports, runbooks — same system. The four-file canvas pattern (template + instructions + schema + README) carries any artifact type your team produces.

This is structured artifact engineering, not prompt engineering. The difference shows up the third time you change the format — when "edit fifteen prompts and hope" becomes "tune two knobs and ship."

---

## How it actually works

### The two-gate workflow

Three gates: two synchronous (chat, label), one async (PR review).

1. `/plan "<request>"` — **Gate 0 (chat, ~5 min)**: iterate YAML, approve before anything reaches your task management tool.
2. `/sync-issues` — epic + leaf issues + dependency labels created.
3. `/design ISSUE` — **Gate 1 (label, ~5 min per issue)**: specifier posts strategy on the issue, you review and apply `state:strategy-approved`.
4. `/develop ISSUE` or `/orchestrate FILTER` — implementer writes code and opens a PR, validator runs the quality profile and posts a report.
5. **Gate 2 (PR review)** — confirm and merge.

The implementer agent **refuses** to start without `state:strategy-approved` on the issue. Not a convention — a hard refusal. That's what kills decision drift: the agreed approach lives on the issue, the implementer reads it, reviewers can compare what was agreed against what got built.

You're approving plans (cheap) and reviewing code-against-plan (fast). Not reading 800-line PRs from cold context.

### AFK throughput via parallel orchestration

Two execution paths once strategies are approved:

**`/develop ISSUE-KEY`** — flat team, one issue at a time. Implementer writes code, validator checks, you stay in the loop. Best for the issues you want to think hard about.

**`/orchestrate <FILTER>`** — parallel batch. The filter scales with the level of work you want to throw at it:

- **One issue at a time:** `/orchestrate ABC-101`
- **Several explicit issues:** `/orchestrate ABC-101 ABC-102 ABC-103`
- **Everything matching a label:** `/orchestrate state:strategy-approved`
- **A plan file:** `/orchestrate plans/redis-caching.yaml`
- **An entire epic or project:** `/orchestrate ABC-100` — every approved leaf issue under that parent gets picked up

Whatever the input, **each leaf issue runs through the same gates independently**. One coordinator per issue. Their own implementer and validator. Worktree isolation so parallel work doesn't collide. Concurrency bounded by `sdlc.yml.orchestrate_concurrency` (default 3); the rest queue. Issues that aren't `state:strategy-approved` get dropped with a clear log entry — Gate 1 enforcement doesn't bend just because you're moving fast.

This is the feature: queue an entire approved epic at 6pm, wake up to a stack of pre-validated PRs ready for Gate 2 review. A team of two ships work that used to take five — without sacrificing the gates that keep AI from running into walls.

### Audit trail by default

Every workflow execution writes a session directory:

```
agent-logs/<session-id>/
├── session.json     # structured state — status, artifacts produced, errors
├── execution.log    # JSONL — every phase agent's full envelope per turn
├── summary.md       # human-readable closing report
└── input.json       # original request
```

Two-tone observability: machine-indexable for analytics, human-skimmable for forensics, replayable for debugging. When code review surfaces a question — "why did the agent do X here?" — you have the trace.

---

## What's in `.claude/`

```
.claude/
├── sdlc.yml                      # the dial — primitives + topology + verifier config
├── primitives/                   # vendor-specific implementations of each domain
│   ├── language/                 #   typescript, python, ...
│   ├── quality/                  #   strict, fast, ...
│   ├── commit/                   #   conventional, ...
│   └── task-management/          #   linear, github, ...
├── agents/                       # 6 SDLC phase agents + canvas-author + drift-check
├── commands/                     # /plan /design /develop /orchestrate /sync-issues /canvas
├── skills/                       # workflow knowledge (when to use what; how to recover)
├── output-styles/                # canvas-flow voices (developer, seller)
├── canvases/                     # spec, envelope, plan, session — artifact contracts
└── hooks/                        # lifecycle event fan-out for observability
```

Each file is small. Each file is replaceable. Nothing is implicit.

---

## What changed from v1

A near-total architectural rewrite. The skeleton — decompose, spec, implement, validate — is the same. Almost everything underneath is different:

| Concept | v1 | v2 |
|---|---|---|
| **Decomposition** | 3-step `commands/plan/{1,2,3}-*.md` | `/plan` skill → `planner` agent → YAML |
| **Spec** | `commands/spec-generation/feature.md` | `specifier` agent + spec canvas + task management tool comment |
| **Implementation** | `commands/implement.md` | `/develop` (flat) / `/orchestrate` (parallel) |
| **Validation** | `commands/test.md` | `validator` agent + report |
| **Task management** | Linear-specific scripts | Primitives (Linear, GitHub, swap one value) |
| **Worktree** | `worktree-manager-skill` | `sdlc.yml.worktree:` config |
| **Quality** | `quality-gates` skill | `validator` + `tool_groups` invariant verifier |
| **Canvases** | (none) | Active registry — spec, envelope, plan, session |
| **Output styles** | (none) | Dual-voice canvas-flow (developer, seller) |
| **Verifiers** | (none) | `verify-canvases.sh`, `verify-tool-groups.sh` |
| **CI** | (none) | GitHub Actions — invariants on every PR |

v1's `BOOTSTRAP-PLAN.md` is preserved at [`.claude/docs/archive/v1-bootstrap-plan.md`](.claude/docs/archive/v1-bootstrap-plan.md) for historical reference.

---

## Verifying your setup

Three commands. Each catches a specific class of drift:

```bash
just verify-tool-groups    # agent frontmatter matches sdlc.yml.tool_groups
just verify-canvases       # every canvas's instructions.yaml validates against its schema
just canvases              # canvases on disk are registered in sdlc.yml.canvases
```

These run in CI on every PR. If a contributor edits an agent and forgets to update its tool group declaration, the build fails. If someone adds a canvas without registering it, the build fails. The conventions are checked.

---

## Where to read next

| If you want to | Go to |
|---|---|
| Operate the loop on a real issue | [`.claude/skills/sdlc-loop/SKILL.md`](.claude/skills/sdlc-loop/SKILL.md) |
| Understand the human-side workflow | [`WORKFLOW.md`](WORKFLOW.md) |
| Author a new skill, agent, or output-style | [`.claude/skills/skill-authoring/SKILL.md`](.claude/skills/skill-authoring/SKILL.md) |
| Tune or build a canvas | `just canvas-dev` (knobs) or `just canvas-seller` (outcomes) |
| Configure your project | [`.claude/sdlc.yml`](.claude/sdlc.yml) + [`.claude/primitives/README.md`](.claude/primitives/README.md) |
| Understand Claude Code itself | [`.claude/skills/claude-platform/SKILL.md`](.claude/skills/claude-platform/SKILL.md) |

## License

MIT.
