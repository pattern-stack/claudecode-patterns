---
name: figma-snapshot
description: Snapshot a Figma frame's metadata, tokens, design-context, and screenshot to local files under `.ai-docs/figma/<slug>/` so downstream agents (design-builder, design-grader, spec authors) don't re-call the Figma MCP every iteration. Universal — not tied to design-loop; usable for spec writing, design audits, refactor planning.
argument-hint: "<figma-url> [--slug=<name>] [--force]"
arguments: [figma_url, slug, force]
allowed-tools: Bash(git *) Read Write Edit Glob Grep mcp__figma-dev-mode__get_metadata mcp__figma-dev-mode__get_variable_defs mcp__figma-dev-mode__get_design_context mcp__figma-dev-mode__get_screenshot

# === Project SDLC overlay ===
status: beta
topology: [universal]
consumes: [figma-url]
produces: [figma-snapshot]
gates:
  enforces: []
  sets: []
---

# Figma Snapshot

Extract a Figma frame to a structured, locally-cached set of files so downstream consumers don't re-call the Figma MCP each iteration.

## When to use

- Before invoking `/design-loop` against a `figma`-type reference (mandatory)
- Starting work on a UI surface that references a Figma frame
- Re-snapshotting after a Figma update (`--force`)
- Ad-hoc: spec writing, design Q, design audits, refactor planning
- Anywhere you want the tokens / metadata / screenshot in-repo without re-fetching

## Inputs

| Arg | Required | Default | Notes |
|---|---|---|---|
| `figma_url` | yes | — | Figma frame URL (must include `node-id`) |
| `--slug` | no | derived from frame name | Output directory name under `.ai-docs/figma/` |
| `--force` | no | `false` | Re-snapshot even if a fresh one exists |

## Prerequisites

- `figma-dev-mode` MCP server loaded in this session (`mcp__figma-dev-mode__get_metadata` etc. visible)
- If not: `/plugin install figma`, restart session

## Process

1. Parse `figma_url` → extract `fileId` + `nodeId` (node-id in URL uses `-`; MCP uses `:` — convert)
2. Derive slug if not provided: kebab-case of the frame's name (from metadata), or use `frame-{nodeId}`
3. Check idempotency: if `.ai-docs/figma/<slug>/snapshot.yaml` exists, was written < 7 days ago, and `--force` is not set → print existing summary and exit
4. Call MCP tools sequentially:
   - `mcp__figma-dev-mode__get_metadata` → frame tree (XML-ish prose)
   - `mcp__figma-dev-mode__get_variable_defs` → design tokens (prose map)
   - `mcp__figma-dev-mode__get_design_context` → generated React+Tailwind reference
   - `mcp__figma-dev-mode__get_screenshot` → rendered PNG
5. Parse + write outputs (see "Output files" below)
6. Write `summary.md` as the primary downstream-consumable artifact
7. Sanity check: `reference.png` dimensions within 10% of metadata bounding-box
8. Print summary to stdout (caller relays to user)

## Output files

```
.ai-docs/figma/<slug>/
├── snapshot.yaml       # frontmatter — URL, fileId, nodeId, fetched-at, integrity hash
├── metadata.xml        # raw MCP get_metadata output (for diffing)
├── metadata.json       # parsed frame tree (top-level children + bounding boxes)
├── tokens.json         # flat token map: { "color.text.primary": "#191710", "space.m": "16px", ... }
├── design-context.tsx  # raw MCP get_design_context (React stub for reference; do not import)
├── reference.png       # the rendered frame screenshot
└── summary.md          # human/agent-readable composition description (THE consumable artifact)
```

## `snapshot.yaml` shape

```yaml
figma_url: https://www.figma.com/design/<fileId>/<file-name>?node-id=<nodeId>&m=dev
file_id: <fileId>
node_id: <nodeId-colon-form>
frame_name: <name from metadata>
frame_width: <px>
frame_height: <px>
fetched_at: 2026-05-18T17:30:00Z
integrity:
  metadata_sha256: <hash>
  reference_sha256: <hash>
mcp_versions:
  figma-dev-mode: <version-if-known>
```

## `summary.md` shape (the consumable artifact)

```markdown
# {Frame Name}

- **Figma:** {url}
- **Snapshotted:** {date}
- **Frame:** `{nodeId}` — {width}×{height}

## Composition

- 3–5 bullets describing top-level layout, primary sections, key floating elements.

## Tokens used

- **Colors:** N distinct (see `tokens.json` for full map). Highlights: `color.text.primary`, `color.primary`, `color.border.muted`, …
- **Spacing:** `space.2xs` (8), `space.m` (16), `space.l` (24), `space.2xl` (40)
- **Type:** Public Sans Heading/4 (20/bold), Body/1 (14/reg), Support/helper/1 (12/reg)
- **Radii:** `border.radius.small` (2), `border.radius.main` (4)
- **Effects:** `active` = drop-shadow rgba(0,0,0,0.2) 0/4/8/0

## Top-level components (by frame ID)

- `{id}` "Name" — N×N — role (header card / body section / floating toolbar / nav rail / …)
- ...

## Visual notes

- Anything not obvious from metadata: surface color, gradient direction, content density, copy tone, etc.
- States captured: default only (MCP does not surface hover/focus/disabled variants)

## Known gaps

- MCP does not return hover/focus/disabled states; treat those as inferred from atom variants
- MCP does not return motion / animation specs
- Color values may differ slightly from raw Figma due to MCP color-space conversion
```

## Constraints

- Idempotent: same input + same Figma state = same output (modulo timestamps in `snapshot.yaml`)
- Sanity-check: image dimensions ≈ metadata bbox; flag mismatch in `summary.md` "Known gaps"
- Don't overwrite `tokens.json` silently when re-snapshotting — diff and surface changes in the printed summary
- Don't write to a directory with uncommitted changes without `--force`

## Authoring guidance for `summary.md`

The summary is what downstream agents READ INSTEAD OF the Figma MCP. Make it complete:
- A grader should be able to grade a build against `summary.md` + `reference.png` without ever touching the MCP
- A builder should be able to implement against `summary.md` + `tokens.json` + `design-context.tsx`
- A spec author should be able to write a falsifiable checklist from `summary.md`

Err on the side of including more, not less. Re-snapshot is cheap (5 MCP calls); under-documented snapshots cost full rounds.

## Related

- [`/design-loop`](../design-loop/SKILL.md) — primary consumer (figma-type references)
- [`design-reference` canvas](../../canvases/design-reference/README.md) — references this skill in the `figma` type
- Figma Dev Mode MCP server — the data source
