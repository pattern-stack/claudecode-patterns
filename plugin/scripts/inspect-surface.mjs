#!/usr/bin/env node
/**
 * Interactive surface inspection — drives a real browser against a URL and
 * probes per-selector computed styles, ARIA, cursor, and overflow. Plus
 * optional interaction passes (open a menu, hover for tooltip).
 *
 * Built for design-loop grading (catches what static screenshots can't),
 * but generic — works against any URL with a JSON selector spec.
 *
 * Usage:
 *   node scripts/inspect-surface.mjs <url> [<selectors.json>] [<out.json>]
 *
 * - <selectors.json> is optional. If omitted, the script runs a minimal probe
 *   (page title, hydration check, auth-stale check).
 * - <out.json> is optional. If omitted, prints JSON to stdout.
 *
 * Env vars:
 *   VIEWPORT_W      default 1512
 *   VIEWPORT_H      default 982
 *   WAIT_AFTER_NAV  default 1500 ms
 *
 * Selectors JSON shape:
 *   {
 *     "probes": {
 *       "<key>": {
 *         "by": "text" | "css" | "role" | "deepest-text",
 *         "tag": "button",                // for by:text
 *         "selector": "All Opportunities",
 *         "role": "button",               // for by:role
 *         "ariaName": "Change scope",     // override for interactions
 *         "maxLen": 400                   // for by:deepest-text
 *       }
 *     },
 *     "interactions": [
 *       { "kind": "openMenu", "trigger": "<probe-key>", "captureKey": "formatMenu" },
 *       { "kind": "hoverForTooltip", "trigger": "<probe-key>", "captureKey": "scopeTooltip" }
 *     ]
 *   }
 */
import { chromium } from 'playwright';
import { existsSync, readFileSync, writeFileSync } from 'fs';

const [, , url, selectorsPath, outPath] = process.argv;
if (!url) {
	console.error('Usage: inspect-surface.mjs <url> [<selectors.json>] [<out.json>]');
	process.exit(2);
}

const AUTH_FILE = '.playwright/auth.json';
const useStorage = existsSync(AUTH_FILE);
const viewportW = Number(process.env.VIEWPORT_W ?? 1512);
const viewportH = Number(process.env.VIEWPORT_H ?? 982);
const waitAfterNav = Number(process.env.WAIT_AFTER_NAV ?? 1500);

const selectorsSpec = selectorsPath
	? JSON.parse(readFileSync(selectorsPath, 'utf-8'))
	: { probes: {}, interactions: [] };

const browser = await chromium.launch({
	headless: true,
	args: ['--ignore-certificate-errors'],
});
const context = await browser.newContext({
	ignoreHTTPSErrors: true,
	viewport: { width: viewportW, height: viewportH },
	...(useStorage ? { storageState: AUTH_FILE } : {}),
});
const page = await context.newPage();

let navStatus = 'ok';
let finalUrl = url;
let pageTitle = '';
let authStale = false;
try {
	const resp = await page.goto(url, { waitUntil: 'domcontentloaded', timeout: 30_000 });
	navStatus = `http ${resp?.status() ?? '?'}`;
	await page
		.waitForFunction(
			() => !document.body.textContent?.trim().startsWith('Loading'),
			null,
			{ timeout: 15_000 },
		)
		.catch(() => {});
	await page.waitForTimeout(waitAfterNav);
	finalUrl = page.url();
	pageTitle = await page.title().catch(() => '');
	authStale = /\/(login|start|auth)(\?|$)/.test(new URL(finalUrl).pathname);
} catch (e) {
	navStatus = `nav-fail: ${e.message?.slice(0, 200) ?? 'unknown'}`;
}

const describeFn = `
  function describe(el) {
    if (!el) return null;
    const r = el.getBoundingClientRect();
    const cs = getComputedStyle(el);
    return {
      tag: el.tagName.toLowerCase(),
      role: el.getAttribute('role') || el.getAttribute('aria-role'),
      ariaLabel: el.getAttribute('aria-label'),
      ariaPressed: el.getAttribute('aria-pressed'),
      ariaExpanded: el.getAttribute('aria-expanded'),
      ariaDisabled: el.getAttribute('aria-disabled'),
      tabindex: el.getAttribute('tabindex'),
      disabled: el.hasAttribute('disabled'),
      cursor: cs.cursor,
      display: cs.display,
      boxX: Math.round(r.x),
      boxY: Math.round(r.y),
      boxW: Math.round(r.width),
      boxH: Math.round(r.height),
      scrollW: el.scrollWidth,
      clientW: el.clientWidth,
      overflowing: el.scrollWidth > el.clientWidth,
      textPreview: (el.textContent || '').trim().slice(0, 80),
    };
  }
  function findByText(tag, text) {
    return Array.from(document.querySelectorAll(tag)).find(
      (el) => (el.textContent || '').trim() === text,
    );
  }
  function findDeepestContaining(predicate) {
    const all = Array.from(document.querySelectorAll('*'));
    return all
      .filter((el) => {
        if (!predicate(el)) return false;
        return !Array.from(el.children).some((c) => predicate(c));
      })
      .pop();
  }
`;

const passive = await page.evaluate(
	({ describeFnSrc, probes }) => {
		// biome-ignore lint: probes loaded via eval intentionally
		eval(describeFnSrc);
		const out = {};
		for (const [key, spec] of Object.entries(probes ?? {})) {
			let el = null;
			if (spec.by === 'text') {
				const tag = spec.tag ?? 'button';
				// biome-ignore lint: defined via eval
				el = findByText(tag, spec.selector);
			} else if (spec.by === 'css') {
				el = document.querySelector(spec.selector);
			} else if (spec.by === 'role') {
				el = Array.from(document.querySelectorAll(`[role="${spec.role}"], ${spec.role}`)).find(
					(e) => !spec.selector || (e.textContent || '').includes(spec.selector),
				);
			} else if (spec.by === 'deepest-text') {
				// biome-ignore lint: defined via eval
				el = findDeepestContaining(
					(e) =>
						(e.textContent || '').includes(spec.selector) &&
						(e.textContent || '').length < (spec.maxLen ?? 400),
				);
			}
			// biome-ignore lint: defined via eval
			out[key] = describe(el);
		}
		return out;
	},
	{ describeFnSrc: describeFn, probes: selectorsSpec.probes },
);

const interactive = {};
for (const interaction of selectorsSpec.interactions ?? []) {
	try {
		if (interaction.kind === 'openMenu') {
			const probe = selectorsSpec.probes[interaction.trigger];
			if (!probe) throw new Error(`trigger probe '${interaction.trigger}' not in probes`);
			const role = probe.role ?? 'button';
			const triggerName = probe.ariaName ?? probe.selector;
			const trigger = page.getByRole(role, { name: new RegExp(triggerName, 'i') });
			await trigger.click({ timeout: 2000 });
			await page.waitForTimeout(400);
			interactive[interaction.captureKey] = await page.evaluate(
				({ describeFnSrc }) => {
					// biome-ignore lint: defined via eval
					eval(describeFnSrc);
					const dialog = document.querySelector(
						'[role="dialog"], [role="menu"], [data-radix-popper-content-wrapper]',
					);
					if (!dialog) return { open: false };
					const items = Array.from(
						dialog.querySelectorAll('[role="menuitem"], [role="option"], button'),
					)
						.filter((el) => (el.textContent || '').trim().length > 0)
						// biome-ignore lint: defined via eval
						.map((el) => ({ text: (el.textContent || '').trim(), ...describe(el) }))
						.slice(0, 15);
					// biome-ignore lint: defined via eval
					return { open: true, dialog: describe(dialog), items };
				},
				{ describeFnSrc: describeFn },
			);
			await page.keyboard.press('Escape').catch(() => {});
			await page.waitForTimeout(200);
		} else if (interaction.kind === 'hoverForTooltip') {
			const probe = selectorsSpec.probes[interaction.trigger];
			const role = probe?.role ?? 'button';
			const triggerName = probe?.ariaName ?? probe?.selector;
			const trigger = page.getByRole(role, { name: new RegExp(triggerName, 'i') });
			await trigger.hover({ timeout: 1500 });
			await page.waitForTimeout(400);
			interactive[interaction.captureKey] = await page.evaluate(() => {
				const t = document.querySelector('[role="tooltip"]');
				return t ? (t.textContent || '').trim() : null;
			});
		}
	} catch (e) {
		interactive[interaction.captureKey ?? interaction.kind] = {
			error: String(e.message || e).slice(0, 200),
		};
	}
}

await browser.close();

const result = {
	url,
	finalUrl,
	pageTitle,
	navStatus,
	authStale,
	viewport: { width: viewportW, height: viewportH },
	passive,
	interactive,
};

const json = JSON.stringify(result, null, 2);
if (outPath) {
	writeFileSync(outPath, json);
	console.log(`wrote ${outPath}`);
} else {
	console.log(json);
}
