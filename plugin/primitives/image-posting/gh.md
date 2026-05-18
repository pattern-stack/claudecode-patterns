---
type: primitive-adapter
category: image-posting
value: gh
status: beta
description: GitHub adapter for the image-posting port. Maps port operations to `plugin/scripts/gh-attach-image.mjs` (Playwright-driven uploads via GitHub's native composer; works on private repos via session cookies). See README.md for the abstract contract.
port: README.md
---

# GitHub Adapter (image-posting)

Concrete binding of the [image-posting port](./README.md) to `plugin/scripts/gh-attach-image.mjs`. The port contract (operation list, conventions) lives in `README.md` — this file is operations → commands only.

## Why a script instead of pure `gh` CLI

GitHub's REST API does not expose a public endpoint for the `user-attachments` CDN — that asset path is auth-gated and works on private repos (anonymous gets 404, authed users get a 302 to a short-lived presigned S3 URL). The official path to upload into it is the issue/PR composer's drag-and-drop, which is a React surface, not a REST call.

The vendored `gh-attach-image.mjs` script drives that composer headlessly via Playwright with saved session cookies. The pre-2024 "scrape CSRF + POST to `/upload/policies/assets`" path no longer works — the current UI doesn't expose the CSRF token for it. So we let GitHub's own composer do the upload.

## Configuration

Read from `.claude/sdlc.yml`:

```yaml
image_posting: gh
# Optional overrides:
# image_posting_config:
#   gh:
#     session_path: ~/.config/gh-attach/session.json   # default
#     repo: <owner>/<repo>                              # default: `gh repo view -q .nameWithOwner`
```

## One-time setup

Session cookies must exist at `session_path` (default `~/.config/gh-attach/session.json`). One-time interactive auth:

```bash
node ${CLAUDE_PLUGIN_DIR}/scripts/gh-attach-image.mjs --auth
```

Opens a headed browser; log in to GitHub; close the window once `user_session` + `logged_in=yes` cookies are set. Cookies are reused across runs until they expire (GitHub session is long-lived; in practice months).

## Operation bindings

| Port operation | Implementation |
|---|---|
| `verify-prereqs()` | Check `gh auth status` exits 0; check `session_path` exists and is readable; check `playwright` resolvable (`node -e "require('playwright')"` exits 0). Return `{ ok: false, missing: [...] }` listing failures. |
| `attach-image({image_path, context})` | Invoke the script with `--upload-only --issue <n>` (or `--pr <n>`) `--image <path>`. The script needs an issue/PR to use as a composer host even for upload-only. Capture the asset URL from stdout. Return `{ asset_ref: <url> }`. |
| `post-comment-with-images({target, body_markdown, image_paths})` | Invoke the script with `--issue <n>` (or `--pr <n>`), one `--image <path>` per image (in order), and `--body <heredoc>`. Body MAY contain `<!-- gh-attach:IMAGE -->` placeholders for inline placement; otherwise images append to the end. Capture the comment URL from stdout. Return `{ comment_url }`. |

### Script invocation patterns

The script is invoked via Bash. The plugin's path resolution exposes it as `${CLAUDE_PLUGIN_DIR}/scripts/gh-attach-image.mjs`.

**Upload only (returns asset URL):**

```bash
node ${CLAUDE_PLUGIN_DIR}/scripts/gh-attach-image.mjs \
  --upload-only \
  --pr 123 \
  --image /tmp/audit/01-overview.png
```

stdout: a single URL like `https://github.com/user-attachments/assets/abc-def-123-...`.

**Post comment with images:**

```bash
node ${CLAUDE_PLUGIN_DIR}/scripts/gh-attach-image.mjs \
  --pr 123 \
  --image /tmp/audit/01-overview.png \
  --image /tmp/audit/02-detail.png \
  --body "$(cat <<'EOF'
## Design audit — head <sha>

### Both-themes overview

<!-- gh-attach:IMAGE -->
<!-- gh-attach:IMAGE -->

### Findings
...
EOF
)"
```

stdout: the comment URL.

**Target a different repo:**

```bash
node ${CLAUDE_PLUGIN_DIR}/scripts/gh-attach-image.mjs \
  --repo owner/repo \
  --issue 45 \
  --image foo.png \
  --body "..."
```

## Error handling

- **Session expired** (`Sign in to GitHub` page detected): script exits non-zero with `SESSION_EXPIRED`. Adapter MAY surface this with the hint to run `--auth`.
- **Composer not found** (issue/PR doesn't exist or perms missing): script exits non-zero with `COMPOSER_404`. Adapter surfaces and stops.
- **Upload timeout** (CDN slow): script retries 3× internally then exits with `UPLOAD_TIMEOUT`.

## Limitations

- Requires a headed-or-headless Chromium per invocation. Cold-start ~2–3s; not suitable for high-frequency posting.
- Session cookie lifetime is GitHub-controlled. Adapter cannot pre-emptively refresh.
- One script invocation per comment. Multiple comments require multiple invocations.

## Related

- [`task-management/github`](../task-management/github.md) — sibling primitive for the same surface, different concern.
- [`design-auditor`](../../agents/design-auditor.md) — primary consumer (when shipped).
- `plugin/scripts/gh-attach-image.mjs` — the vendored implementation.
