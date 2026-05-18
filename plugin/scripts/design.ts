#!/usr/bin/env bun
/**
 * Single entrypoint for design-loop dogfood scripts.
 *
 * Usage:
 *   bun scripts/design.ts <subcommand> [args...]
 *
 * Subcommands:
 *   capture <url> <outPath>                    # full-page screenshot via Playwright
 *   inspect <url> [selectors.json] [out.json]  # computed-style + ARIA + interaction probe
 *   verify  <url>                              # one-shot pre-flight check (exit 0/1)
 *   auth    [--manual | --account=<op-item>]   # refresh .playwright/auth.json
 *   help                                       # show this
 *
 * Env vars (inherited by subprocesses):
 *   VIEWPORT_W       default 1512
 *   VIEWPORT_H       default 982
 *   WAIT_AFTER_NAV   default 1500
 *
 * Implementation: thin router. Each subcommand spawns the existing standalone
 * script (`scripts/{capture,inspect}-surface.mjs`, `scripts/playwright-auth.mjs`)
 * so they stay individually runnable and this entrypoint just consolidates the
 * invocation surface. Future cleanup may inline the modules.
 */

import { spawn } from 'node:child_process';
import { existsSync, readFileSync } from 'node:fs';
import { resolve } from 'node:path';

// capture-surface.mjs and inspect-surface.mjs live next to this file (they
// ship together as part of the plugin). playwright-auth.mjs is intentionally
// NOT shipped — auth flow is consumer-specific (SSO provider, login URLs,
// etc.) — and resolves against the calling process's CWD.
const SCRIPTS_DIR = import.meta.dirname;
const CONSUMER_CWD = process.cwd();

function help(exit = 0): never {
	const usage = `
usage: bun scripts/design.ts <subcommand> [args...]

subcommands:
  capture <url> <outPath>
      Full-page screenshot. Uses .playwright/auth.json if present.
      Env: VIEWPORT_W (1512), VIEWPORT_H (982).

  inspect <url> [selectors.json] [out.json]
      Interactive probe. With no selectors JSON: minimal nav/auth/title check.
      With selectors JSON: per-probe { cursor, role, aria*, overflowing, ... }
      plus interactions (openMenu, hoverForTooltip).
      Env: VIEWPORT_W, VIEWPORT_H, WAIT_AFTER_NAV.

  verify <url>
      One-shot pre-flight. Exits 0 on (200 + non-stale auth + non-loading
      title), 1 otherwise. Prints { ok, reason?, fix_hint? } JSON.

  auth [--manual | --account=<op-item>]
      Refresh .playwright/auth.json via SSO. --manual = you complete login
      in the popped browser. --account=<op> = 1Password automation (requires
      op CLI + unlocked 1Password).

  help
      Show this message.
`.trim();
	console.log(usage);
	process.exit(exit);
}

function runScript(scriptPath: string, args: string[]): Promise<number> {
	return new Promise((resolveP) => {
		const child = spawn('bun', [scriptPath, ...args], {
			stdio: 'inherit',
			cwd: CONSUMER_CWD,
			env: process.env,
		});
		child.on('exit', (code) => resolveP(code ?? 0));
	});
}

function runScriptCaptureStdout(
	scriptPath: string,
	args: string[],
): Promise<{ code: number; stdout: string }> {
	return new Promise((resolveP) => {
		let stdout = '';
		const child = spawn('bun', [scriptPath, ...args], {
			stdio: ['inherit', 'pipe', 'inherit'],
			cwd: CONSUMER_CWD,
			env: process.env,
		});
		child.stdout.on('data', (chunk) => {
			stdout += chunk.toString();
			process.stdout.write(chunk);
		});
		child.on('exit', (code) => resolveP({ code: code ?? 0, stdout }));
	});
}

function pluginScript(name: string): string {
	return resolve(SCRIPTS_DIR, name);
}

function consumerScript(name: string): string {
	return resolve(CONSUMER_CWD, 'scripts', name);
}

const [, , subcommand, ...rest] = process.argv;

if (!subcommand || subcommand === 'help' || subcommand === '--help' || subcommand === '-h') {
	help(0);
}

switch (subcommand) {
	case 'capture': {
		if (rest.length < 2) {
			console.error('capture: requires <url> <outPath>');
			help(2);
		}
		const code = await runScript(pluginScript('capture-surface.mjs'), rest);
		process.exit(code);
		break;
	}

	case 'inspect': {
		if (rest.length < 1) {
			console.error('inspect: requires <url>');
			help(2);
		}
		const code = await runScript(pluginScript('inspect-surface.mjs'), rest);
		process.exit(code);
		break;
	}

	case 'verify': {
		if (rest.length < 1) {
			console.error('verify: requires <url>');
			help(2);
		}
		const [url] = rest;
		// Run inspect with no selectors → just gives us nav status + auth + title.
		const { stdout } = await runScriptCaptureStdout(pluginScript('inspect-surface.mjs'), [
			url,
		]);
		let parsed: any;
		try {
			parsed = JSON.parse(stdout);
		} catch {
			console.error('verify: inspect did not return JSON');
			process.exit(1);
		}
		const reasons: string[] = [];
		if (!/^http 2\d\d$/.test(parsed.navStatus ?? '')) reasons.push(`navStatus=${parsed.navStatus}`);
		if (parsed.authStale) reasons.push('authStale=true (run: bun scripts/design.ts auth)');
		if (!parsed.pageTitle || /loading/i.test(parsed.pageTitle))
			reasons.push(`pageTitle=${JSON.stringify(parsed.pageTitle ?? '')}`);
		if (reasons.length) {
			console.error(
				JSON.stringify(
					{ ok: false, reasons, hint: 'Fix and re-run `bun scripts/design.ts verify <url>`' },
					null,
					2,
				),
			);
			process.exit(1);
		}
		console.log(JSON.stringify({ ok: true, finalUrl: parsed.finalUrl, title: parsed.pageTitle }, null, 2));
		process.exit(0);
		break;
	}

	case 'auth': {
		// Auth flow is consumer-specific (SSO provider, login URL, TOTP, etc.).
		// Resolve to the calling project's scripts/playwright-auth.mjs. The
		// plugin does not ship a generic auth helper; each project provides
		// its own and exposes a sibling /auth-recover skill.
		const authScript = consumerScript('playwright-auth.mjs');
		if (!existsSync(authScript)) {
			console.error(
				`auth: consumer-side script not found at ${authScript}\n` +
					'  The plugin does not ship a generic auth helper. Create your own at\n' +
					'  scripts/playwright-auth.mjs (Playwright + your SSO flow + save\n' +
					"  storageState to .playwright/auth.json). See your project's\n" +
					'  /auth-recover skill for the contract.',
			);
			process.exit(2);
		}
		const code = await runScript(authScript, rest);
		process.exit(code);
		break;
	}

	default:
		console.error(`unknown subcommand: ${subcommand}`);
		help(2);
}
