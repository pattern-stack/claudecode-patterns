# Reverse engineering — extracting a canvas from an example artifact

`reverse` mode is the strategically critical pattern: a user provides one (or two) example documents that look right, and the canvas-author extracts the canonical knob settings that would reproduce them.

This is not pattern matching. It's structured inference: read the example, decompose it against the eight-category taxonomy, propose values, surface uncertainty.

## When to use reverse mode

- Migration: "Here's how we did specs at the last company — make our canvas like that."
- Standardization: "Several teams write daily briefs differently. Here's the version we like — extract it."
- Fast bootstrap: "I don't want to enumerate every knob from scratch. Here's an example. Get me 80% there."

For all three, reverse mode is faster and grounded in concrete reality. It avoids the abstract-question trap of `new` mode.

## The extraction process

### Phase 1: Read structurally

Walk the example artifact top-to-bottom. Catalog:

- **Frontmatter:** present? what fields? what types/values?
- **Headings:** every H1 / H2 / H3, in order. Names are verbatim.
- **Section content shape:** prose / bullets / code / mixed.
- **Embedded artifacts:** code blocks (language?), diagrams (tool?), tables, lists.
- **Total length:** chars and lines, plus distribution by section.
- **Citations:** any file paths, URLs, line numbers? format?
- **Tone signal:** voice ("I propose" / "We recommend" / imperative), formality.
- **Signatures or attributions:** end-of-doc, footer, omitted?

This gives the structural fingerprint.

### Phase 2: Map to taxonomy

For each of the eight knob categories ([knob-taxonomy.md](knob-taxonomy.md)), propose a value:

#### Structure
- `sections.order` ← verbatim H2 list
- `sections.required` ← sections that have non-stub content (deferred until phase 3 — confirmed with user)
- `frontmatter.fields` ← any frontmatter found

#### Verbosity
- For each section, classify by length and form:

| Observed | Inferred verbosity |
|---|---|
| 1 sentence | `one-liner` |
| 1-2 sentences or 2-3 bullets | `short` |
| 1-2 paragraphs or 4-8 bullets | `medium` |
| 3+ paragraphs | `long` |
| Only bullets, no prose | `bulleted` |
| Only code/yaml | `code-only` |

#### Visualization
- `diagrams.tool` ← detected from embedded blocks (mermaid, excalidraw refs, ascii art)
- `diagrams.in_sections` ← which H2s contain diagrams

#### Provenance
- `citations.file_paths` ← `required` if every claim has a citation, `optional` if some do, `none` if absent
- `citations.line_numbers` ← detect `:NN` suffixes on file paths
- `citations.attribution` ← end-of-doc references list vs. inline

#### Length budget
- `length.total_chars` ← actual char count, rounded up to a sensible cap (next 100 / 500 / 1000)
- `length.per_section_chars` ← per-section char count, capped similarly
- `length.truncate` ← can't infer from one example; default to `reflow`

#### Tone & style
- `tone.voice` ← detect "I" / "we" / imperative / passive
- `tone.formality` ← contractions, slang, formal register markers
- `signature.text` ← end-of-doc string if present

#### Metadata
- `metadata.status_field` ← from frontmatter; record enum values seen
- `metadata.related` ← any "see also" sections or related-link arrays

#### Distribution
- Can't infer from one example; ask the user "is this artifact also posted to a tracker / email / slack?"

### Phase 3: Confidence levels

For every inferred value, attach a confidence:

| Confidence | Means |
|---|---|
| **high** | The example unambiguously demonstrates this value (e.g. heading list is what it is) |
| **medium** | The example is consistent with the value but other values are also plausible (e.g. medium verbosity vs. short) |
| **low** | Multiple values could produce what's seen (e.g. `citations.line_numbers: true` could mean "required" or "this example happened to have them"; `truncate: hard` vs. `reflow` is invisible from output) |

High-confidence inferences are proposed without ceremony. Medium and low get explicit confirmation:

> I see file paths but no line numbers. Could be `line_numbers: false` (intentional convention)
> or it could just be that this example didn't need them. Which?

### Phase 4: Triangulate (optional but recommended)

If the user has a second example, request it. Triangulating across two examples:

- **Stable across both** = the canvas pattern. Promote.
- **Differs between them** = a tunable knob (or noise). Flag for user choice.
- **Only in one** = probably noise. Default to omitting.

Two examples cuts inference confidence to high or low — far less ambiguous than the single-example case. Request two whenever possible.

### Phase 5: Draft and confirm

Produce the four canvas files (`template.md`, `instructions.yaml`, `instructions.schema.json`, `README.md`) in draft form. Display the proposed `instructions.yaml` first — it's where the inference work is most visible.

Apply only on confirmation. The user can request adjustments inline; the agent loops back through Phase 5 until aligned.

## Inference tables

### Verbosity heuristics

```
Section text length (chars) → inferred verbosity

  0-80          → one-liner
  80-300        → short
  300-1500      → medium
  1500+         → long

Adjustments:
  - All bullets, no prose          → bulleted (regardless of length)
  - Only fenced code               → code-only
  - Mostly tables                  → bulleted (tables behave like structured bullets)
```

### Citation inference

```
Per-paragraph (or per-bullet) citation rate:
  > 80%  → citations.file_paths: required
  20-80% → citations.file_paths: optional
  < 20%  → citations.file_paths: none

Path format:
  "src/foo.ts:42"   → line_numbers: true
  "src/foo.ts"      → line_numbers: false
  External URLs     → url_format: inline | footnoted (per visible position)
```

### Tone inference

```
Voice markers:
  "I propose / I think / I'll"           → first-person
  "We / our / let's"                     → first-person (collective)
  "Add the / Run the / Update"           → imperative
  Passive constructions ("is added")     → neutral

Formality markers:
  Contractions, "you" addressing reader  → casual
  No contractions, abstract nouns        → formal
  Mix                                    → standard (the most common default)
```

## Example: extracting a spec canvas from a sample

Given an example like:

```markdown
---
issue: APP-42
status: ready
---

# Add OAuth2 to the API

## Goal
Wire third-party OAuth2 alongside our existing token auth.

## Approach
We'll add an OAuth2 middleware that runs before the existing token middleware
in src/api/middleware.ts:42-58. The middleware checks for a Bearer token in
the standard format, falls back to existing token logic if absent.

## File-level plan
### Create
- `src/auth/oauth2.ts` — middleware impl
- `src/auth/oauth2.test.ts`

### Modify
- `src/api/middleware.ts` — register the new middleware

## Tests
Cover: token-present (success), token-malformed (401), token-absent (passes through).

## Open questions
- Should we cache token validation results?
```

The agent would propose:

```yaml
# Confidence levels in comments
sections:
  order: ["Goal", "Approach", "File-level plan", "Tests", "Open questions"]    # high
  required: ["Goal", "Approach", "File-level plan", "Tests"]                    # medium — Open questions empty in this example
  verbosity:
    Goal: short                    # high (1 sentence)
    Approach: medium                # high (1 paragraph)
    File-level plan: medium         # high (4 bullets, two subsections)
    Tests: short                    # high (1 sentence with comma list)
    Open questions: bulleted        # medium — only 1 bullet shown
diagrams:
  tool: none                        # high (no diagrams present)
  in_sections: []
citations:
  file_paths: required              # medium (1 path with line range, but only 1 path)
  line_numbers: true                # medium (line range present)
metadata:
  frontmatter_extras:
    - { name: issue, type: string, required: true }     # high
    - { name: status, type: string, required: true }    # high
```

And ask:
> Two confirmations needed:
> 1. **Open questions required?** This example has it but with only 1 bullet. Required = halts on empty; optional = section can be omitted. Your call.
> 2. **`citations.file_paths: required`?** Only one path appears. Did the author cite where they could, or is one path the typical density?

## Constraints

- **Don't over-fit.** A single example always shows ONE point in the value space; the canvas should generalize. Prefer `medium` over `long` when ambiguous; prefer `optional` over `required` when only one example.
- **Surface inference work.** The user should see what was inferred and from what, not just the final values. Confidence levels do this.
- **Never write without confirmation.** Reverse mode is exploratory; the user must approve the draft before any file is written.
- **Document the canvas's lineage.** Note in the canvas's `README.md` that it was reverse-engineered from `<source>` on `<date>`. This helps when later tuning ("we got this from a 2023-era spec; might want to revisit").

## When reverse mode falls over

- The example is malformed (no clear sections, mixed conventions). Switch to `new` mode and use the example as inspiration only.
- The example is highly stylized in ways that don't generalize (heavy emoji, inside jokes, custom layout). Extract the structural shape, drop the styling, ask the user how style should be handled.
- The user has fundamentally different needs than the example demonstrates ("I like the look but the content is wrong for our domain"). The canvas can capture style but not domain — surface this clearly and ask whether style or domain is the priority.
