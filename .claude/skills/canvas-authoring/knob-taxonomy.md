# Knob taxonomy — the canonical vocabulary

Every canvas's `instructions.yaml` draws from this taxonomy. The same eight categories work for specs, plans, daily briefs, post-call summaries, email templates, validator reports — any structured document. Portability is the point: a canvas-authoring system that thinks in this vocabulary can serve far more than one domain.

## The eight categories

| # | Category | Controls | Producer impact | Consumer impact |
|---|---|---|---|---|
| 1 | **Structure** | Sections, ordering, frontmatter shape | High (the skeleton) | High (parsing, required-section halts) |
| 2 | **Verbosity** | Per-section depth and form | High (output length, tone) | Low (mostly invisible) |
| 3 | **Visualization** | Diagrams, code blocks, formatting | Medium (rendering choices) | Low (passes through) |
| 4 | **Provenance** | Citations, source links, line numbers | Medium (footnoting effort) | High (traceability) |
| 5 | **Length budget** | Total / per-section caps | High (truncation logic) | Low (parsing remains the same) |
| 6 | **Tone & style** | Voice, signature, formality | High (writing style) | None (cosmetic) |
| 7 | **Metadata** | Frontmatter fields, status semantics | Medium (state propagation) | Medium (status routing) |
| 8 | **Distribution** | Cross-posting (tracker, slack, email) | High (multi-target rendering) | Low (tracker UI) |

Each category has a small set of canonical knob shapes. Below: the names and value spaces.

---

## 1. Structure

Defines the artifact's skeleton. Without these, there's no canvas.

```yaml
sections:
  order:
    - "<section name>"
    - "<another>"
  required:
    - "<sections that must be non-empty>"
  optional:
    - "<sections that can be omitted>"

frontmatter:
  shape: yaml | toml | none
  fields:
    <field-name>:
      type: string | array | enum | date
      required: true | false
      enum: ["v1", "v2", …]   # if type is enum
```

**Constraints:**
- `order` defines what sections exist; everything else (verbosity, required, etc.) keys off these names.
- A section name in `required` or `verbosity` that's not in `order` is a schema error.
- Renaming a section requires updating `template.md` `## <name>` heading AND every reference in `instructions.yaml`.

## 2. Verbosity

Per-section depth and form. The single highest-leverage tuning surface.

```yaml
sections:
  verbosity:
    "<section name>": short | medium | long | code-only | bulleted | one-liner
```

**Value semantics:**

| Value | Approximate length | Form | Use when |
|---|---|---|---|
| `one-liner` | 1 sentence | prose | Header / summary fields |
| `short` | 1-2 sentences or 2-3 bullets | prose or bulleted | Obvious sections, tight artifacts |
| `medium` | 1-2 paragraphs or 4-8 bullets | prose preferred | Default for most sections |
| `long` | 3+ paragraphs | prose | When evidence / reasoning needs space |
| `bulleted` | 3-10 bullets | bulleted only | Open-questions, checklist sections |
| `code-only` | (code block) | fenced code | Interfaces, schemas, queries |

Producers should never exceed `long` without explicit per-canvas authorization. If you find yourself wanting "very long," split the artifact instead.

## 3. Visualization

Diagrams and inline code conventions.

```yaml
diagrams:
  tool: mermaid | excalidraw | none
  in_sections: ["<section name>", …]   # which sections may contain diagrams
  required_in: []                       # sections where a diagram is mandatory (rare)

code_blocks:
  default_language: typescript | python | bash | …
  syntax_highlighting: true | false
```

**Notes:**
- `tool: none` means the producer must not emit diagrams. Useful for plain-text artifacts (email templates, minutes).
- `excalidraw` requires the consumer to render `.excalidraw` files; not all surfaces support it. If `excalidraw` and `tracker_comment.include_sections` overlap, surface this conflict (Linear comments don't render Excalidraw).
- `code_blocks.default_language` only governs unfenced code in templates; explicit fences override.

## 4. Provenance

Citations, source links, line numbers.

```yaml
citations:
  file_paths: required | optional | none
  line_numbers: true | false
  url_format: short | inline | footnoted
  attribution: per-claim | per-section | end-of-doc | none
```

**Notes:**
- `required` means the producer must cite a path for any claim about existing code. Half-cited drafts get sent back.
- `line_numbers: true` is incompatible with `diagrams.tool: excalidraw` for the same content (excalidraw drawings have no line numbers).
- `attribution` controls how citations are surfaced in prose ("As shown in `src/foo.ts:42` …" vs end-of-doc references).

## 5. Length budget

Caps on total and per-section length.

```yaml
length:
  total_chars: <int>          # whole-artifact cap (0 = unlimited)
  total_lines: <int>           # alternate cap form
  per_section_chars:
    "<name>": <int>
  truncate: warn | hard | reflow
```

**Notes:**
- `truncate: warn` lets the producer overrun and emits a warning. `hard` truncates at the cap. `reflow` asks the producer to fit by tightening — most useful but slowest.
- For small artifacts (specs, daily briefs), per-section caps matter more than total.
- For tracker comments: `tracker_comment.max_chars` is a separate length budget specific to that distribution target.

## 6. Tone & style

How the artifact reads.

```yaml
tone:
  voice: neutral | first-person | imperative | conversational
  formality: casual | standard | formal
  perspective: producer | consumer | system

signature:
  text: "<string or empty>"
  position: end | frontmatter | omit
```

**Notes:**
- `voice` affects opening sentences ("This spec covers…" vs "I propose…" vs "Add the following…").
- `signature` is most relevant when the artifact is cross-posted (tracker comments, emails). For internal docs, omit.

## 7. Metadata

Frontmatter fields and status semantics.

```yaml
metadata:
  status_field:
    name: status
    enum: ["draft", "research", "ready", "approved", "shipped"]
    default: "draft"
  related:
    field: related
    type: array
    item_type: artifact-key | url | string
  frontmatter_extras:
    - { name: "issue", type: "string", required: true }
    - { name: "date", type: "string", required: false }
```

**Notes:**
- Status fields drift if not coupled to a real workflow (Linear labels, PR state). If the canvas's status is purely cosmetic, document it as such.
- `related` arrays support cross-document linking. Keep the link format consistent with how consumers parse it.

## 8. Distribution

Cross-posting rules for artifacts that exist in multiple surfaces.

```yaml
tracker_comment:
  enabled: true | false
  max_chars: <int>
  include_sections: ["<name>", …]
  files_list_inline: true | false
  signature: "<string>"

email:
  enabled: true | false
  subject_template: "<string with {{tokens}}>"
  body_format: plaintext | markdown | html

slack:
  enabled: true | false
  channel: "<channel name or null>"
  format: blocks | text
  thread_root: true | false
```

**Notes:**
- The producer renders the artifact ONCE in canonical form, then transforms per distribution target's caps and format.
- A distribution channel that isn't `enabled: true` is silently skipped — no failure.
- Conflicts (e.g. `tracker_comment.include_sections` references a section that contains an excalidraw diagram, which Linear can't render) get surfaced as anti-patterns at canvas-authoring time.

---

## Reusing the taxonomy across domains

The Software Sellers use case (daily briefs, post-call summaries, email templates) maps to the same eight categories:

| Domain | Structure | Verbosity | Visualization | Provenance | Length | Tone | Metadata | Distribution |
|---|---|---|---|---|---|---|---|---|
| **Spec (here)** | sections list | per-section | mermaid | file:line | per-section | neutral | status, issue | tracker comment |
| **Daily brief** | morning sections | bulleted | none | meeting refs | total cap | imperative | date, recipient | email |
| **Post-call summary** | call sections | medium | none | call timestamp | total cap | first-person | call_id, attendees | tracker, email, slack |
| **Email template** | greeting/body/sign | one-liner per | none | none | strict | conversational | recipient_role | email only |

Same vocabulary, different emphases. A canvas-authoring agent that knows this taxonomy can serve every domain.

---

## Adding a new knob category

If you find yourself wanting a knob that doesn't fit any of these eight categories, that's signal. Either:

1. The need is specific enough that it should live as a custom knob inside one canvas (just add it to that canvas's `instructions.yaml` and schema). Don't promote.
2. The need is general — multiple canvases would benefit. Promote to a ninth category and update this file.

Don't pre-promote. Categories #1-#8 are the result of triangulation; ninth+ should pay for itself before joining them.
