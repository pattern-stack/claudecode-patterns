# Worked example — pattern-stack/sales-patterns-ts#47

The canonical trace this package was extracted from. Phase 1 of the "Design vocabulary for observability dashboard" epic. Read this if you want to see what a successful `/design-loop` run looks like end-to-end.

Original issue: https://github.com/pattern-stack/sales-patterns-ts/issues/47
Spec authored: `specs/2026-04-24-design-vocabulary.md`

## Locked decisions (from the spec)

1. Density: 36px cozy rows
2. Caveat handwritten font kept, scoped to ≤2 sites
3. Status palette: 7 app-local domain tokens + 5 generic from the package
4. Pool icons: Lucide (drop ASCII glyphs)

These were explicit and binding. The auditor graded every later finding against them.

## Phase 1 trace

### Spec gate (specifier)

Specifier produced `specs/2026-04-24-design-vocabulary-phase-1-contracts.md` — token block, typed `tokens.ts`, 12 atom contracts with TS interfaces, showcase route spec, AC list. Returned READY.

### Implement (implementer)

Shipped commit `41defa8`:
- 34 CSS custom properties added to `theme-chalky-primary.css` (4 geometry, 4 density, 7 spacing, 4 shadow, 4 motion, 7 status pairs) + `@keyframes pulseDot`
- 12 atoms: Chip, PoolChip, StatusBadge, StatusDot, ID, Timestamp, EmptyCell, Hand, Card, KV, Sparkline, Row
- `/_showcase` route with debug bar verifying CSS vars resolved
- `tsc` 0, biome 0, console clean, all 12 atoms render

Reported one data-density exception: `KV.tsx` uses `"11.5px"` for mono-grid alignment. Flagged as a non-themable decision per spec guidance.

### Theme-swap probe (implementer, additional commit `b4c3183`)

Added `theme-chalkboard.css` to falsify the abstraction. Goal: swap themes via `data-theme` and verify zero atom-file changes are required. Pool tokens migrated from raw HSL triplets (`bgHsl`/`inkHsl`) to CSS-var names (`bgVar`/`inkVar`) so pool colors flowed through theme tokens.

Result: both themes rendered correctly, 0 console errors under either, all 12 atoms looked right.

### Audit round 1 (auditor, browser-pilot evidence)

The auditor found 3 `Definitely broken` + 4 `Visual polish` items. Highlights:

**Broken:**
1. ID atom — dotted underline invisible. Root cause at `frontend/src/atoms/ID.tsx:74`: `border: "none"` listed AFTER `borderBottom` in the same React style object → shorthand wins, nuking the underline. Fix: swap declaration order.
2. StatusBadge — chalkboard contrast 1.08–1.37:1 (WCAG AA needs 4.5:1). Root cause: `theme-chalkboard.css:106-112` had `-ink` only slightly lighter than `-bg`. Fix: flip ink to deep board-toned dark (~13–14% L).
3. Architects Daughter font not loaded. Root cause: `frontend/index.html` Google Fonts URL didn't include it; chalkboard fell back to Caveat. Fix: 1-line URL addition.

**Polish:**
4. Chip active ring flat under chalkboard
5. Card border barely visible (1.4:1 against card surface)
6. Row hover and selected look identical
7. Pool chip hatch stripes near-invisible (13% alpha too low for dark bg)

Recommended fix order ranked by 1-line-fix → token-only → atom edit.

### Fix round (implementer, commit `b4ebf5b`)

Implementer addressed 5 of 7 in a single fix commit:
1. ID underline — swapped declaration order
2. StatusBadge contrast — flipped ink to dark on solid bg, all 7 statuses now ≥5:1
3. Architects Daughter loaded
4. Card surface + border bumped (`-card` 11% → 14% L, `-border` 32% → 42% L)
5. Hatch alpha bumped 13% → 25%

Deferred 2 with reasons:
- (4) Chip active ring — UX question, needs user input on whether resting chips need visible rim
- (6) Row hover/selected — needs a 4th muted step token AND touches Row.tsx (organism edit, Phase 2)

Returned 3 questions to user gate.

### Validate (validator)

Quality gates against `b4ebf5b`:
- Frontend typecheck: PASS
- Showcase route HTTP 200 under both themes: PASS
- 0 console errors under each theme: PASS
- /events, /jobs, /overview routes also green
- Commit hygiene: 4 files, all in declared phase scope: PASS
- No probe scripts in working tree: PASS

### User gate

Posted phase summary as PR comment with screenshot grid. User reviewed deferred items, gave thumbs up on the dark-ink approach, deferred chip ring + row selected to Phase 2. Phase 1 closed.

## What this trace shows

- Locked decisions enabled the auditor to grade objectively (e.g., "36px cozy" was measurable in the rendered page).
- The theme-swap probe (a falsification step, not a deliverable) caught the entire `Definitely broken` category — without it, contrast issues would have shipped invisible.
- The fix round's deferral mechanism worked as intended: 5 fixes shipped, 2 deferred with structural reasons, no half-finished work.
- The auditor returned exactly 3 broken items — under the 7-finding ceiling — meaning the spec was structurally sound and the build was close.
- Total wall time: roughly one focused session per phase, gated cleanly by the user.

## What would have gone wrong without the loop

- Without the locked-decisions block: the auditor would have graded against vibes, not contract.
- Without `/_showcase`: the auditor would have audited feature pages with real data churn, screenshots would have been noisy.
- Without the theme-swap AC: chalkboard would have shipped with 1.08:1 contrast.
- Without the 7-finding ceiling: a structurally broken spec could have produced 20-finding rounds and false-progressed.
