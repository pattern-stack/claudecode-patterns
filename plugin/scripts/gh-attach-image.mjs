#!/usr/bin/env node
// Upload image(s) to GitHub's user-attachments CDN + optionally post them as
// an issue/PR comment. Works on PRIVATE repos — the asset URLs GitHub
// produces (`github.com/user-attachments/assets/<uuid>`) are auth-gated:
// anonymous requests get 404, authed users with repo access get a 302 to a
// short-lived presigned S3 URL. So you get embedding that respects repo
// perms, with no anonymous leakage.
//
// Approach: drive GitHub's native React composer via headless Playwright.
// The old "scrape CSRF + POST directly to /upload/policies/assets" flow
// worked pre-2024 but the current UI no longer exposes the CSRF token for
// that path; letting GitHub's own composer do the upload is reliable.
//
// One-time setup (saves session cookies ~/.config/gh-attach/session.json):
//   node scripts/gh-attach-image.mjs --auth
//
// Upload + comment on an issue:
//   node scripts/gh-attach-image.mjs --issue 45 --image path/to.png --body "caption"
//
// Upload + comment on a PR (same script, just --pr):
//   node scripts/gh-attach-image.mjs --pr 123 --image a.png --image b.png --body "..."
//
// Multiple images with placement control: put `<!-- gh-attach:IMAGE -->` in
// --body, one per --image, in order.
//
// Upload only (prints asset URL to stdout, no comment):
//   node scripts/gh-attach-image.mjs --upload-only --issue 45 --image path/to.png
//   (we still need --issue or --pr to have a composer to upload through)

import { chromium } from "playwright";
import { execSync } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { basename, dirname, resolve } from "node:path";
import { homedir } from "node:os";

const SESSION_PATH =
  process.env.GH_ATTACH_SESSION ||
  `${process.env.XDG_CONFIG_HOME || `${homedir()}/.config`}/gh-attach/session.json`;

function parseArgs(argv) {
  const args = { images: [], body: "", issue: null, pr: null, auth: false, repo: null, uploadOnly: false };
  for (let i = 2; i < argv.length; i++) {
    const a = argv[i];
    if (a === "--auth") args.auth = true;
    else if (a === "--image") args.images.push(argv[++i]);
    else if (a === "--body") args.body = argv[++i];
    else if (a === "--issue") args.issue = argv[++i];
    else if (a === "--pr") args.pr = argv[++i];
    else if (a === "--repo") args.repo = argv[++i];
    else if (a === "--upload-only") args.uploadOnly = true;
    else if (a === "--help" || a === "-h") args.help = true;
  }
  return args;
}

async function saveSession() {
  mkdirSync(dirname(SESSION_PATH), { recursive: true });
  console.log("Launching headed browser. Log into GitHub, then close the window.");
  const browser = await chromium.launch({ headless: false });
  const ctx = await browser.newContext();
  const page = await ctx.newPage();
  await page.goto("https://github.com/login");
  console.log("Waiting for login to complete (detecting user_session cookie)…");
  const deadline = Date.now() + 10 * 60 * 1000;
  while (Date.now() < deadline) {
    const cookies = await ctx.cookies();
    const hasSess = cookies.some((c) => c.name === "user_session" && c.domain.endsWith("github.com"));
    const loggedIn = cookies.some((c) => c.name === "logged_in" && c.value === "yes");
    if (hasSess && loggedIn) break;
    await page.waitForTimeout(1000);
  }
  await ctx.storageState({ path: SESSION_PATH });
  await browser.close();
  console.log(`Session saved → ${SESSION_PATH}`);
}

function repoNameWithOwner(override) {
  if (override) return override;
  return execSync("gh repo view --json nameWithOwner -q .nameWithOwner", { encoding: "utf8" }).trim();
}

// Match either the new HTML embed GitHub writes (`<img src="...user-attachments/assets/..."`)
// or the legacy markdown form (`![alt](...user-attachments/assets/...)`).
const ASSET_URL_RE = /https:\/\/github\.com\/user-attachments\/assets\/[0-9a-f-]+/g;

async function uploadViaComposer({ page, repo, issue, pr, imagePaths }) {
  const path = pr ? `/pull/${pr}` : `/issues/${issue}`;
  await page.goto(`https://github.com/${repo}${path}`);
  await page.waitForLoadState("domcontentloaded");
  await page.waitForTimeout(2500);
  await page.evaluate(() => window.scrollTo(0, document.body.scrollHeight));
  await page.waitForTimeout(1500);

  const textarea = page.locator('textarea[placeholder*="Markdown"]').last();
  await textarea.scrollIntoViewIfNeeded();
  await textarea.click();
  await page.waitForTimeout(1000);

  const urls = [];
  for (const img of imagePaths) {
    const absolute = resolve(img);
    if (!existsSync(absolute)) throw new Error(`Image not found: ${absolute}`);

    const prev = await textarea.inputValue();
    const fileChooserPromise = page.waitForEvent("filechooser", { timeout: 15000 });
    await page.getByRole("button", { name: /Add Files/i }).first().click();
    const chooser = await fileChooserPromise;
    await chooser.setFiles(absolute);

    // Wait for the textarea to gain a new asset URL (or timeout)
    const deadline = Date.now() + 90000;
    let matched = null;
    while (Date.now() < deadline) {
      const v = await textarea.inputValue();
      const found = [...v.matchAll(ASSET_URL_RE)].map((m) => m[0]);
      const newUrl = found.find((u) => !urls.includes(u));
      if (newUrl && v !== prev && !/Uploading/.test(v)) {
        matched = newUrl;
        break;
      }
      await page.waitForTimeout(750);
    }
    if (!matched) throw new Error(`Upload timed out for ${basename(absolute)}`);
    urls.push(matched);
    process.stderr.write(`uploaded ${basename(absolute)} → ${matched}\n`);
  }

  return urls;
}

function substituteBody(body, urls, names) {
  if (!urls.length) return body;
  let out = body;
  let idx = 0;

  // Form 1 (preferred): inline HTML comment placeholder. Most resilient — no
  // visible text in the rendered comment if substitution somehow fails.
  out = out.replace(/<!--\s*gh-attach:IMAGE\s*-->/g, () => {
    const i = idx++;
    return `![${names[i] || "image"}](${urls[i]})`;
  });

  // Form 2: numbered placeholders inside markdown image src — `![alt](PLACEHOLDER_N)`
  // or `![alt](PLACEHOLDER_NN)` (1- or 2-digit). Useful when the body contains
  // table cells with explicit image refs and you want positional control beyond
  // simple ordering. N is 1-indexed and matches the 1-based --image position.
  out = out.replace(/!\[([^\]]*)\]\(PLACEHOLDER_0?([0-9]+)\)/g, (_m, alt, n) => {
    const i = parseInt(n, 10) - 1;
    if (i < 0 || i >= urls.length) return _m; // out of range — leave as-is
    return `![${alt || names[i] || "image"}](${urls[i]})`;
  });

  // If neither form was present, append all images at the bottom.
  if (idx === 0 && !/PLACEHOLDER_0?[0-9]+/.test(body)) {
    out += (out ? "\n\n" : "") + urls.map((u, i) => `![${names[i] || "image"}](${u})`).join("\n\n");
  }

  // Hard fail-fast: if any PLACEHOLDER_NN remains, we'd ship broken images.
  // Better to error than to post a comment with literal `PLACEHOLDER_03` URLs.
  const leftover = out.match(/PLACEHOLDER_0?[0-9]+/);
  if (leftover) {
    throw new Error(
      `Body still contains unresolved placeholder ${leftover[0]} after substitution. ` +
        `Check that --image count (${urls.length}) matches placeholder indices in the body.`,
    );
  }

  return out;
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(
      "Usage: node scripts/gh-attach-image.mjs [--auth] [--issue N|--pr N] --image path [--image path...] [--body text] [--repo owner/name] [--upload-only]",
    );
    process.exit(0);
  }
  if (args.auth) return saveSession();
  if (!args.images.length) { console.error("--image is required"); process.exit(2); }
  if (!args.issue && !args.pr) { console.error("--issue or --pr is required (we drive the composer UI)"); process.exit(2); }
  if (!existsSync(SESSION_PATH)) { console.error(`No session at ${SESSION_PATH}. Run: node scripts/gh-attach-image.mjs --auth`); process.exit(2); }

  const repo = repoNameWithOwner(args.repo);
  const browser = await chromium.launch({ headless: true });
  const ctx = await browser.newContext({ storageState: SESSION_PATH });
  const page = await ctx.newPage();

  let urls;
  try {
    urls = await uploadViaComposer({ page, repo, issue: args.issue, pr: args.pr, imagePaths: args.images });
  } finally {
    await browser.close();
  }

  if (args.uploadOnly) {
    for (const u of urls) console.log(u);
    return;
  }

  const names = args.images.map((p) => basename(p));
  const body = substituteBody(args.body, urls, names);
  const target = args.pr ? "pr" : "issue";
  const num = args.pr || args.issue;
  const out = execSync(`gh ${target} comment ${num} --repo ${repo} --body-file -`, {
    input: body,
    encoding: "utf8",
  });
  console.log(out.trim());
}

main().catch((e) => {
  console.error(e.stack || e.message);
  process.exit(1);
});
