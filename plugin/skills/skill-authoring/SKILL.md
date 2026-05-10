---
name: skill-authoring
description: Create skills, commands, and agents for THIS project — applying the SDLC architecture (primitives, sdlc.yml, artifact_paths, mission format, topology metadata) on top of the canonical Claude Code platform reference. Use when authoring a new component for this repo.
allowed-tools: Read, Write, Glob, Grep
user-invocable: true
---

# Skill Authoring (project SDLC layer)

This skill is the **project-specific overlay** on `claude-platform`. Use them together:

| Layer | Skill | Scope |
|---|---|---|
| **Platform reference** | `claude-platform` | Every Claude Code field, every SDK primitive, every variance — agnostic to this project |
| **Project SDLC overlay** | `skill-authoring` (this) | The conventions THIS repo layers on: primitives, sdlc.yml, mission format, topology metadata, artifact paths |

When authoring a component for this project: start with `claude-platform/templates/{skill-rich,subagent-rich,output-style}.md` for the platform-correct frontmatter, then layer the project conventions below on top.

## Three component types (this project's stance)

| Type | Location | Invocation | When |
|---|---|---|---|
| **Skill** | `.claude/skills/<name>/SKILL.md` | `/<name>` or auto | Single thematic capability; reusable across workflows |
| **Command** | `.claude/commands/<name>.md` | `/<name>` | Workflow orchestration with explicit human gates |
| **Agent** | `.claude/agents/<name>.md` | Claude delegates / `@`-mention | Isolated specialist with restricted tools |

Note: Anthropic's stance is "commands and skills are the same mechanism; new workflows should use skills." See `claude-platform/reference/plugins.md` for the verbatim quote. This project keeps `commands/` for the existing SDLC entrypoints because they orchestrate via the **mission format** (below) — but new workflows should land as skills with bundled supporting files.

## Project conventions layered on top of `claude-platform`

### 1. Custom frontmatter for SDLC metadata

This project's components carry extra frontmatter fields **that Claude Code ignores at runtime** but a human reader (and tooling) treat as documentation:

```yaml
---
# Standard Claude Code fields (consumed by runtime)
name: ...
description: ...
disallowedTools: ...

# === Project SDLC metadata (NOT consumed by Claude Code runtime) ===
status: active            # active | skeleton | deferred
topology: [A, B]          # which orchestration topologies use this component
consumes: [issue, spec]   # artifact types this reads
produces: [pr, comment]   # artifact types this writes
gates:
  enforces: [strategy-approved]   # gate labels this halts on
  sets: [awaiting-strategy-review] # gate labels this sets
---
```

Convention: keep these fields. They make the SDLC roster grep-able and self-documenting. They have no effect on the Claude Code runtime — that's fine.

### 2. Primitives system

Components declare which **primitives** they consume; values resolve from `.claude/sdlc.yml`. See `.claude/primitives/README.md` for the full taxonomy.

```yaml
primitives:
  required:
    - language          # typescript | python | go
    - quality_profile   # strict | fast
  optional:
    - commit_style      # conventional | freeform
```

Resolution order (per primitives/README.md):
1. Explicit argument or issue label (e.g. `stack:backend` → `language: backend`)
2. `.claude/sdlc.yml` project default
3. Hardcoded fallback in the primitive's own README

The primitive file at `.claude/primitives/<category>/<value>.md` is the contract. Agents reference it by `{value}` interpolation; the filename **is** the API. Don't hardcode primitive specifics in agent prompts.

### 3. Tool boundaries — canonical groups in `sdlc.yml`

Claude Code's runtime does not substitute named tool groups (the `tools:` field takes literal tool names). This project defines canonical groups in `sdlc.yml` `tool_groups:` and uses a `# tool_group: <name>` comment in each agent's frontmatter to declare which group the enumerated list expands.

**For SDLC agents that need tracker-MCP access, prefer the DENYLIST form** — otherwise you weld the agent to one tracker (e.g. Linear), and swapping to GitHub Issues requires editing every agent file.

```yaml
# ❌ Welded to Linear (allowlist enumerating Linear MCP)
tools: Read, Write, Edit, Bash, Glob, Grep, mcp__plugin_linear_linear__get_issue

# ✅ Tracker-agnostic — inherits whichever MCP is configured
# tool_group: code_writer_mcp (denylist; inherits all configured MCP)
disallowedTools: WebFetch, WebSearch, Agent
```

The agent body refers to "the configured task-management MCP" or to the primitive (`task-management/{value}.md`); Claude resolves the right tool at runtime.

#### Available tool groups (see `sdlc.yml` for the canonical list)

**Allowlists** — copy into `tools:` to restrict to exactly these (no MCP):
- `read_only` — Read, Glob, Grep
- `research` — `read_only` + WebFetch, WebSearch
- `research_writer` — `research` + Write
- `spec_writer` — Read, Write, Edit, Glob, Grep
- `code_writer` — `spec_writer` + Bash
- `validator` — Read, Bash, Glob, Grep

**Denylists** — copy into `disallowedTools:` to inherit-all-minus (keeps MCP):
- `no_egress` — WebFetch, WebSearch
- `no_recursion` — Agent
- `spec_writer_mcp` — `spec_writer` + all configured MCP
- `code_writer_mcp` — `code_writer` + all configured MCP
- `validator_mcp` — `validator` + all configured MCP

#### Agent → group mapping (current roster)

| Agent | Group | Form |
|---|---|---|
| `planner` | `spec_writer` | allowlist |
| `understander` | `research_writer` | allowlist |
| `specifier` | `spec_writer_mcp` | denylist |
| `implementer` | `code_writer_mcp` | denylist |
| `validator` | `validator_mcp` | denylist |
| `coordinator` | custom | allowlist (Agent scoped + repo-only; no MCP — defers tracker to implementer) |
| `claude-platform-drift-check` | `research` | allowlist |

Use the allowlist form (`tools: ...`) only when scoping is the point: `coordinator.md` uses `tools: ..., Agent(implementer, validator)` because *which subagents can be spawned* is a load-bearing topology constraint.

### 4. `artifact_paths` from `sdlc.yml`

Every multi-issue plan defines a **stack**. Artifacts produced during that plan are co-located under `.ai-docs/stacks/<slug>/`. Cross-cutting artifacts go to `.ai-docs/research/<topic>.md`. Source of truth: `.claude/sdlc.yml` `artifact_paths`. Agents MUST read from there — never hardcode.

### 4b. `artifacts:` registry from `sdlc.yml` (canvases)

Each artifact (spec, plan, understanding, validator-report, pr-body, …) is a **canvas** — a `template.md` + `instructions.yaml` + `instructions.schema.json` + `README.md` quartet at `.claude/canvases/<name>/`. Source of truth: `.claude/sdlc.yml` `artifacts:` registry. Producer and consumer agents read from the resolved path; no inline templates in agent prompts. See [`artifacts/README.md`](../../artifacts/README.md) and the [`canvas-authoring`](../canvas-authoring/SKILL.md) skill.

When authoring a canvas (or tuning one), use `/canvas <mode> [name]` rather than editing the four files by hand. The canvas-author agent applies a probing dialog with full schema awareness and never writes without confirmation.

### 5. Artifact templates and instructions

Documents agents produce (specs, plans, validator reports, etc.) follow a **template + instructions** pattern. Each artifact lives at `.claude/canvases/<name>/`:

| File | Purpose |
|---|---|
| `template.md` | Structural skeleton with `{{token}}` placeholders |
| `instructions.yaml` | Typed knobs (section order, verbosity, diagram tool, citations, downstream-comment shape) |
| `instructions.schema.json` | JSON Schema validating `instructions.yaml` |
| `README.md` | Producer, consumers, override semantics |

**Why split structure from behavior:** section ordering changes rarely; verbosity / diagram tool / citation strictness changes often. Splitting lets you tune one without churning the other.

**How agents use them:**

- **Producer** reads both files at start, validates `instructions.yaml` against the schema, renders the template per the knobs, writes the populated document.
- **Consumers** read the same files to know which sections are required and how to interpret them. The `sections.required` list in `instructions.yaml` is the single source of truth — consumers do not hardcode section names.

**Override semantics:** edit the files in place. When this project ships as a plugin, plugin defaults are overridden by project-local `.claude/canvases/<name>/` files via Claude Code's standard plugin overlay. No special mechanism.

**Source of truth for paths:** `.claude/sdlc.yml` `artifacts:` block. Agents resolve paths from there — never hardcode the directory.

**Currently shipped:**
- `.claude/canvases/spec/` — per-issue implementation strategy (specifier produces; implementer / coordinator / validator consume)

**Still embedded in producer agents** (migrate opportunistically when an artifact's structure or behavior next needs to change): `plan`, `understanding`, `validator-report`, `pr-body`, `coordinator-status`. The migration order is "the next time you'd be editing the inline `## Output Format` block, lift it to `.claude/canvases/<name>/` first, then make your change in one place."

**Validation:** `scripts/verify-canvases.sh` (when implemented) validates each `instructions.yaml` against its schema. CI / pre-commit hook candidate; mirrors `verify-tool-groups.sh`.

### 6. Mission format for command steps

Commands orchestrate via prose using a **Mission** block per step. This makes extracting a step into a dedicated agent later mechanical:

```markdown
### Step 2: Strategize

**Delegate to**: `specifier` agent

**Mission**:
- **Objective**: Produce per-issue implementation strategy and post for human review
- **Input**: `$1` (issue key) + any existing research artifact
- **Context**: `.claude/sdlc.yml` + `.claude/primitives/{language,task-management}/...`
- **Constraints**: No code; no implementation; sets `state:awaiting-strategy-review` and halts
- **Output**: spec at the resolved path + Linear comment + label set
```

Don't write step-by-step recipes inside command bodies — that belongs in the agent's own `## Instructions`. The command coordinates; the agent executes.

### 7. Pre-render with `!`...`` where it pays

Slash commands and skills can pre-render shell output before Claude reads the body. Use it for working-tree state, recent commits, or any cheap context the workflow always needs:

```markdown
## Working tree state
Branch: !`git branch --show-current`
Status: !`git status --short`
Recent: !`git log --oneline -5`
```

Skip pre-rendering when the value is session-state-dependent (`$CLAUDE_SESSION_ID` semantics) or when the cost of running unconditionally exceeds the value.

### 8. Topology A vs B (project-specific)

| Topology | Command | Pattern |
|---|---|---|
| A | `/develop <issue>` | Flat team via `TeamCreate` — implementer + validator + needs-driven extras as split-pane peers |
| B | `/orchestrate <filter>` | One `coordinator` teammate per issue; each coordinator spawns implementer/validator as **subagents** (Agent tool), not further teammates |

The topology constraint is load-bearing: subagents cannot spawn further subagents, so coordinator's spawning happens via Agent tool inside its own context. See `.claude/agents/coordinator.md` and `claude-platform/cookbooks/multiagent-coordination.md`.

## Templates

These templates show only the **project overlay**. For complete platform frontmatter, copy from `claude-platform/templates/` first:

- **Skill** — `claude-platform/templates/skill-rich.md` + this project's `templates/skill.md` overlay
- **Command** — this project's `templates/command.md` (mission format is a project convention)
- **Agent** — `claude-platform/templates/subagent-rich.md` + this project's `templates/agent.md` overlay

## Naming

- Lowercase + hyphens: `task-management`, `quality-gates`
- Skills: noun or noun-phrase (what it is) — `prime`, `quality-gates`
- Commands: verb or verb-phrase (what user wants to do) — `design`, `develop`, `orchestrate`
- Agents: role name (who it is) — `planner`, `specifier`, `implementer`, `validator`

## Authoring checklist

When creating a new component, verify:

- [ ] Started from the matching `claude-platform/templates/` file
- [ ] Frontmatter is correct per `claude-platform/reference/{skills,subagents}.md`
- [ ] Tool boundaries use `disallowedTools` if tracker-agnostic; allowlist only if scoping is the point
- [ ] Project SDLC metadata block present (`status`, `topology`, `consumes`, `produces`, `gates`)
- [ ] Primitives consumed are declared and read from `sdlc.yml`
- [ ] Artifact paths read from `sdlc.yml` `artifact_paths`, never hardcoded
- [ ] Description includes trigger words (drives auto-invocation)
- [ ] No leaked vendor-specific MCP names in `tools:` for SDLC roster agents
- [ ] If a command, uses Mission format for steps; does not embed agent recipes
- [ ] Pre-render with `!`...`` if working-tree or git context is always needed

## Key principles (this project)

1. **Primitives are the contract.** Agents reference primitives, never hardcode tracker/language/quality specifics.
2. **Commands delegate via Mission format.** Don't bake agent logic into commands.
3. **Tool boundaries via denylist** for tracker-agnostic SDLC roles; allowlist only for scoping.
4. **Stack co-location for artifacts.** Plans define stacks; artifacts live under `.ai-docs/stacks/<slug>/`.
5. **Project metadata fields are documentation, not runtime config.** Keep them; they're useful for grepping the roster.
6. **`claude-platform` is the platform truth.** When a Claude Code feature changes, update `claude-platform/reference/*.md` first; this skill stays focused on project overlays.
