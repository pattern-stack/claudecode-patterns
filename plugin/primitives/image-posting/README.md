---
type: primitive-port
category: image-posting
status: beta
description: The image-posting port — abstract operations for attaching images to comment surfaces (PR / tracker issue / local folder). Adapters provide concrete CLI/MCP bindings. The active adapter is selected by `image_posting:` in `.claude/sdlc.yml`.
---

# Image Posting Port

The abstract contract for attaching screenshots (and other images) to a comment surface. Consumed primarily by `design-auditor` for posting screenshot grids alongside findings; designed so any future agent (validator with visual regression output, planner with architecture diagrams) can use the same operations.

When you write or edit an agent prompt, **reference operations from this file, never concrete CLI commands**. The adapter file (`{image_posting}.md`) is consulted only at runtime by the agent.

## Relationship to `task-management` and `validator_post_target`

Image-posting is a **separate axis** from where a comment lands:

| Axis | What it picks |
|---|---|
| `task_management: <linear \| github>` | The tracker — issue keys, gate labels, sub-issue topology. |
| `modes.<mode>.validator_post_target: <pr \| tracker>` | Which **surface** validator/post-impl reports land on (PR vs tracker issue). |
| `image_posting: <gh \| local-folder \| ...>` | How **images** get attached to whatever surface was chosen. |

These coexist by design. A project can be on Linear (`task_management: linear`) but use `image_posting: gh` if the code lives on GitHub and PR comments are the post target. Per the design-loop port proposal Open Q #5, they are NOT unified into a single `output_target` primitive in v1. v2 may revisit once a second non-`gh` adapter (e.g. `linear-comment`) exists to pressure the design.

## Operation contract

| Operation | Inputs | Output | Notes |
|---|---|---|---|
| `attach-image` | `{ image_path, context: { repo?, issue?, pr? } }` | `{ asset_ref: string }` | `asset_ref` is a renderable URL or path the consumer can drop into markdown (`![](<asset_ref>)`). For `gh`: GitHub user-attachments CDN URL (auth-gated). For `local-folder`: relative `./images/<file>.png` path. |
| `post-comment-with-images` | `{ target: { repo?, issue?, pr? }, body_markdown, image_paths[] }` | `{ comment_url \| null }` | Atomic: upload images and post the comment in one go. The body may contain `<!-- gh-attach:IMAGE -->` placeholders, one per image in order, for inline placement. Returns `null` if the adapter does not post (e.g. `local-folder` just writes files). |
| `verify-prereqs` | — | `{ ok: bool, missing: string[] }` | Adapter self-check at agent startup. `gh` verifies `gh auth status` + cached session cookies for the headless uploader. |

Operations not in this table belong to the adapter, not the port. Propose adding to the port first.

## Configuration in `sdlc.yml`

```yaml
image_posting: gh           # gh | local-folder | linear-comment (future)

# Optional adapter overrides — most adapters have sensible defaults.
# image_posting_config:
#   gh:
#     session_path: ~/.config/gh-attach/session.json
#   local-folder:
#     output_dir: .ai-docs/audit-images
```

Defaults if `image_posting:` is omitted:

- `task_management: github` → default `image_posting: gh`
- otherwise → default `image_posting: local-folder`

Override always wins.

## Adapter resolution

`plugin/primitives/image-posting/<value>.md`. Project-level override at `.claude/primitives/image-posting/<value>.md`.

## Available adapters (v1)

| Value | Status | Posts to | Image hosting |
|---|---|---|---|
| `gh` | Active | GitHub issue or PR | GitHub user-attachments CDN (auth-gated; works on private repos) |
| `local-folder` | **Deferred (v1.1)** | None — writes the comment as a markdown file in `<output_dir>/` | Files in `<output_dir>/` |
| `linear-comment` | **Deferred (v2)** | Linear issue | Linear's attachment API |

`local-folder` is named as a defer-target so the auditor has a no-network fallback once it lands.

## Prerequisites

Every adapter must implement `verify-prereqs`. Agents call it once at startup; on failure they halt with the adapter's missing-deps list and a setup hint.

For `gh`: `gh` CLI authenticated; Playwright installed (`npm i -g playwright` or vendored chrome binary); `~/.config/gh-attach/session.json` present (one-time interactive auth via the script's `--auth` mode). The adapter MAY auto-run `--auth` on first failure if `permissionMode` allows.

## Authoring rules

- Adapters MUST honor the operation signatures verbatim. If an adapter cannot do `post-comment-with-images` atomically (e.g. a future adapter that only attaches, doesn't post), it falls back to `attach-image` per image and surfaces this in `verify-prereqs.missing`.
- Adapters MUST NOT leak adapter-specific terminology into operation outputs. `asset_ref` is opaque to the consumer.
- Adapters MUST tolerate `image_paths: []` (post a text-only comment).

## Out of scope for v1

- **Image preprocessing** (resize, crop, annotation overlays). The consumer pre-processes if needed.
- **Image diffing** for visual regression. The auditor handles diff logic; the port just attaches.
- **CDN selection** beyond what the adapter chooses. The consumer cannot force a specific host.

## Related

- [`task-management`](../task-management/README.md) — the tracker port; image-posting is orthogonal.
- [`design-auditor`](../../agents/design-auditor.md) — primary consumer (when shipped).
- [Design-loop port proposal](../../../.ai-docs/proposals/design-loop-port.md) Open Q #5 — rationale for keeping this separate from `validator_post_target`.
