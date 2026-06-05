---
name: project-documentation
description: Create and manage durable project documentation — ADRs, specs, RFCs, and architecture docs. Use when the user wants to record an architecture decision, write an ADR or RFC, draft a spec, update a spec after implementation, or discuss where documentation should live.
when_to_use: User says "write an ADR", "record this decision", "draft a spec", "mark the spec shipped", "update the spec to match what we built", "where should this doc go", or asks about documentation structure and conventions.
allowed-tools: Read, Write, Edit, Glob, Grep
user-invocable: true

# === Project SDLC overlay ===
status: active
topology: none
---

# Project Documentation

Discipline for **durable** project documentation: Architecture Decision Records (ADRs), implementation specs, and RFCs. Durable docs outlive the work that produced them — every future agent and human reads them, so convention fidelity matters more than speed.

## The two documentation planes

| Plane | Lives at | Governed by | This skill? |
|---|---|---|---|
| **Durable docs** — ADRs, RFCs, specs-as-record, guides | `docs/` | This skill + the consumer repo's own conventions | yes |
| **SDLC working artifacts** — plans, stack research, per-issue specs, validator reports, handoffs | `.ai-docs/` | `sdlc.yml` `artifact_paths` + the canvas registry | no — never hardcode these paths; read `artifact_paths` |

If the artifact is produced by a phase agent inside the SDLC loop, it belongs to the working plane — route via `sdlc.yml` `artifact_paths` and canvases, not this skill. A per-issue spec that turns out to capture a durable decision gets **promoted**: distill it into an ADR. Don't move the file.

## Detect conventions before creating anything

Documentation conventions are repo-local facts. **Never assume — detect:**

1. `Glob` the target directory (`docs/adrs/*`, `docs/specs/*`, `docs/rfcs/*`) — learn the **naming scheme** from the filenames themselves (`NNN-title.md`? `ADR-NNN-title.md`? 3- or 4-digit? dotted sub-numbers like `033.1`?).
2. Read the 2–3 most recent files — learn the **header style** (YAML frontmatter vs bold-field header block), the **status vocabulary** actually in use, and the section shape.
3. Check for a project-local documentation skill or a CLAUDE.md documentation section — the consumer repo may carry an overlay with its own facts. **The repo's own conventions always win over this skill's defaults.**

Match what exists. Only when the directory is empty (greenfield) fall back to the bundled templates:

- `${CLAUDE_SKILL_DIR}/templates/adr.md`
- `${CLAUDE_SKILL_DIR}/templates/spec.md`

## Creating an ADR

1. Detect conventions (above).
2. Find the next number from the existing files — and **check for collisions**: duplicate numbers happen when two branches race. Never mint a number that already exists, and don't mistake a dotted sub-ADR (`033.1` amends `033`) for a free slot.
3. Create the file following the detected naming. Include: today's date, status (`Draft`, or `Accepted` if the decision is final), Context, Decision, Options Considered, Consequences.
4. ADRs capture **why**, not how. Keep them short; link to specs/RFCs for the how.

## Creating a spec

1. Detect conventions. If the project names specs by tracker/epic key (e.g. `JOB-1.md`), follow that; otherwise date-prefix (`YYYY-MM-DD-kebab-title.md`).
2. Status starts at `Draft`. Include: Goal, Architecture, Files, Implementation Steps, Open Questions.
3. The bar: an implementer can code from it without guessing.

## Specs are post-implementation truth

When implementation lands, **update the spec in the same PR**: close the open questions you resolved, correct details that turned out wrong, add constraints discovered while building. The spec becomes the record of what was built, not just the plan for building it.

## Status lifecycle — in place, never moved

Status lives in the document's header. **Files never move** — other docs, skills, and tracker comments link to them by path; an archive folder breaks every link for zero gain.

- **ADRs:** `Draft → Accepted → Superseded by <ADR or RFC ref>` — append-only, never deleted. A superseded ADR keeps its body; only the status line changes.
- **Specs:** `Draft → Implemented | Superseded` (canonical default — adopt the repo's richer vocabulary if one exists).

## Key rules

- Status lives in the document header — not folder structure, not filename.
- ADRs are numbered and append-only. Collisions checked, supersession linked.
- Don't over-document. If it's in the code or git history, don't repeat it in docs.
- Bulk or context-isolated authorship → delegate to the [`sdlc-author`](../../agents/sdlc-author.md) agent (it honors canvases and these conventions).
