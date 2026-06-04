#!/usr/bin/env node
/**
 * Headed-once auth bootstrap: open a VISIBLE browser at a login URL, let the
 * user authenticate by hand, then save Playwright storage state so headless
 * runs (the plugin's playwright MCP server, browser-driver's design.ts) are
 * authenticated thereafter.
 *
 * Deliberately generic — no IdP/provider/credential assumptions. Projects
 * with their own credential plumbing (env, sops, password-manager CLIs)
 * should point `sdlc.yml → browser.auth_script` at their own script instead;
 * this is the universal fallback.
 *
 * Usage:
 *   node auth-capture.mjs <login-url> [--out .playwright/auth.json] [--done <url-substring>] [--timeout-min 10]
 *
 *   --out          Where to write storage state (default .playwright/auth.json,
 *                  matching browser-driver's AUTH_FILE).
 *   --done         Optional URL substring that signals login completed; when
 *                  set, state saves automatically as soon as the page URL
 *                  contains it. Without it, press Enter in this terminal when
 *                  you're logged in.
 *   --timeout-min  Give up after N minutes (default 10).
 *
 * Requires `playwright` resolvable from the consuming project (same
 * expectation as capture-surface.mjs).
 */
import { mkdirSync } from 'fs';
import { dirname, resolve } from 'path';
import { createInterface } from 'readline';
import { chromium } from 'playwright';

function arg(flag, fallback) {
  const i = process.argv.indexOf(flag);
  return i !== -1 && process.argv[i + 1] ? process.argv[i + 1] : fallback;
}

const loginUrl = process.argv[2];
if (!loginUrl || loginUrl.startsWith('--')) {
  console.error('Usage: node auth-capture.mjs <login-url> [--out path] [--done url-substring] [--timeout-min 10]');
  process.exit(1);
}
const outPath = resolve(arg('--out', '.playwright/auth.json'));
const doneSubstring = arg('--done', null);
const timeoutMin = Number(arg('--timeout-min', '10'));

const browser = await chromium.launch({
  headless: false,
  args: ['--ignore-certificate-errors'],
});
const context = await browser.newContext({ ignoreHTTPSErrors: true });
const page = await context.newPage();
await page.goto(loginUrl);

console.log(`\n🔑 Log in via the browser window (${loginUrl}).`);

const saveState = async () => {
  mkdirSync(dirname(outPath), { recursive: true });
  await context.storageState({ path: outPath });
  console.log(`✅ Storage state saved → ${outPath}`);
  await browser.close();
  process.exit(0);
};

const deadline = setTimeout(async () => {
  console.error(`⏱️  Timed out after ${timeoutMin} minutes without completing login.`);
  await browser.close();
  process.exit(1);
}, timeoutMin * 60_000);
deadline.unref?.();

if (doneSubstring) {
  console.log(`   Waiting for the URL to contain "${doneSubstring}"…`);
  await page.waitForURL((url) => url.toString().includes(doneSubstring), {
    timeout: timeoutMin * 60_000,
  });
  await saveState();
} else {
  console.log('   Press Enter here once you are logged in.');
  createInterface({ input: process.stdin }).once('line', saveState);
}
