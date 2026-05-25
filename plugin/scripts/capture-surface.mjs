#!/usr/bin/env node
/**
 * One-shot screenshot capture for design-loop dogfood.
 * Bypasses cert errors and reuses saved auth state.
 *
 * Usage:
 *   node scripts/capture-canvas-screenshot.mjs <url> <outPath>
 */
import { chromium } from 'playwright';
import { existsSync } from 'fs';

const [, , url, outPath] = process.argv;
if (!url || !outPath) {
	console.error('Usage: capture-canvas-screenshot.mjs <url> <outPath>');
	process.exit(2);
}

const AUTH_FILE = '.playwright/auth.json';
const useStorage = existsSync(AUTH_FILE);

const browser = await chromium.launch({
	headless: true,
	args: ['--ignore-certificate-errors'],
});

const viewportW = Number(process.env.VIEWPORT_W ?? 1512);
const viewportH = Number(process.env.VIEWPORT_H ?? 982);
const context = await browser.newContext({
	ignoreHTTPSErrors: true,
	viewport: { width: viewportW, height: viewportH },
	...(useStorage ? { storageState: AUTH_FILE } : {}),
});

const page = await context.newPage();

const consoleMsgs = [];
page.on('console', (msg) => consoleMsgs.push(`[${msg.type()}] ${msg.text()}`));
page.on('pageerror', (err) => consoleMsgs.push(`[pageerror] ${err.message}`));

let navStatus = 'ok';
try {
	const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30_000 });
	navStatus = `http ${resp?.status() ?? '?'}`;
} catch (e) {
	navStatus = `nav-fail: ${e.message}`;
}

// give SPA time to hydrate
await page.waitForTimeout(2500);

const finalUrl = page.url();
const title = await page.title().catch(() => '');

await page.screenshot({ path: outPath, fullPage: true });

await browser.close();

console.log(JSON.stringify({
	url,
	finalUrl,
	title,
	navStatus,
	usedStorage: useStorage,
	screenshot: outPath,
	consoleSample: consoleMsgs.slice(0, 20),
}, null, 2));
