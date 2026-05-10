# claudecode-patterns

**Run Claude Code as a team.** Plan-first, gate-disciplined, customizable to your stack — without forking anyone's prompts.

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

This works because every domain capability is modeled as a **primitive**: a small file declaring how that thing works for one specific vendor. Linear, GitHub Issues, Jira are interchangeable behind the same domain interface. When you need a task management tool we don't ship, drop a new file in `primitives/task-management/` — that's it.

The same pattern extends to language conventions, quality profiles, commit styles. Want strict TypeScript with typecheck-on-save in one project and forgiving Python in another? Two values in `sdlc.yml`. Same agents work both.

### 2. Customize without touching agents

`sdlc.yml` is the dial. You change behavior by editing config, not by editing agent prompts.

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

Want to pin a different commit style for one project? Change one line. Add a custom validator step? Drop a primitive. The agents read the config; you don't have to fork the agents to change how they behave.

This makes onboarding a team trivial. Clone the repo. Adjust two values for your stack. Your AI behaves consistently for everyone.

### 3. Build your own templates without writing prompts

The shape of every artifact your AI produces — specs, plans, session logs, validator reports — is governed by a **canvas**: a template + tunable knobs that you can adjust through dialog, not by editing agent code.

```bash
just canvas-dev      # walks you through the developer-voice authoring flow
just canvas-seller   # outcome-framed flow, hides system mechanics
```

Want your specs shorter? Tune one knob. Want validator reports posted differently to GitHub? Tune another. Want a new canvas for daily standups, post-mortems, or PR summaries? The `canvas-author` agent reverse-engineers a canvas from an example you paste in.

This is the difference between "AI tooling that has prompts" and "AI tooling that has a configurable artifact contract." The second one survives team disagreements about format.

---

## How it actually works

### The two-gate workflow

```mermaid
flowchart LR
    R[Request] --> P["/plan<br>(Gate 0 — chat)"]
    P --> S["/sync-issues<br>→ task management"]
    S --> D["/design ISSUE<br>(Gate 1 — label)"]
    D -->|state:strategy-approved| I["/develop or /orchestrate"]
    I --> V[Validator report on PR]
    V --> M["Gate 2 — PR Review<br>→ Merge"]

    style P fill:#fef3c7,stroke:#d97706
    style D fill:#fef3c7,stroke:#d97706
    style M fill:#fef3c7,stroke:#d97706
```

Three gates, two synchronous, one asynchronous:

| Gate | Where | What you do |
|---|---|---|
| **0 — Plan** | In chat (5 min) | Iterate the YAML plan; approve before anything reaches your task management tool |
| **1 — Strategy** | On your task management tool (5 min per issue) | Review the implementation strategy before any code is written |
| **2 — PR review** | GitHub | Validator pre-checks; you confirm and merge |

The implementer agent **refuses** to start without `state:strategy-approved` on the issue. It's not a convention — it's a hard refusal. This is what kills decision drift: the agreed approach is on the issue, the implementer reads it, anyone reviewing can compare what was agreed against what got built.

You're approving plans (cheap) and reviewing code-against-plan (fast). Not reading 800-line PRs from cold context.

### AFK throughput via parallel orchestration

Two execution paths once strategies are approved:

**`/develop ISSUE-KEY`** — flat team, one issue at a time. Implementer writes code, validator checks, you stay in the loop. Best for the issues you want to think hard about.

**`/orchestrate state:strategy-approved`** — parallel batch. Spawns one coordinator per approved issue, each running its own implementer + validator in worktree isolation. You queue 5 approved issues at 6pm; you wake up to 5 PRs, each pre-validated, ready to review.

The orchestrator is the feature. It's how a team of two ships work that used to require a team of five — without sacrificing the gates that keep AI from running into walls.

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

## Quick start

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
just verify          # invariants pass — config is valid

# 4. Run the loop
/plan "Add Redis caching to the user service"
# (iterate, approve)
/sync-issues
/design ACME-101    # review in your task management tool, label state:strategy-approved
/develop ACME-101   # or /orchestrate state:strategy-approved
```

That's the whole flow. The hard part is the first 10 minutes deciding what your `sdlc.yml` should say. After that, the system runs.

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
