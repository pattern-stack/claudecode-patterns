#!/usr/bin/env node
/**
 * guided-tour — human-watchable UI walkthroughs that double as verification.
 *
 * One tour definition, two modes:
 *   narrate  — drives the user's REAL browser (Arc/Chrome) over raw CDP, with a
 *              visible cursor, element highlights, click ripples and captions.
 *   verify   — same steps, no theatre; captures screenshots + console/network
 *              health and evaluates assertions. Exits non-zero on failure.
 *
 * Why raw CDP and not Playwright's connectOverCDP: Arc accepts the websocket
 * then hangs the connectOverCDP handshake — the socket opens, the handshake
 * never completes, 30s timeout (verified 2026-08-10, Arc on Chrome/149.0.7827.156).
 * Raw CDP against the exact same endpoint works fine. See the `browser` skill,
 * "Arc specifics (hard-won)".
 *
 * ZERO npm dependencies — Node 22+ ships a global `WebSocket`. Keep it that way:
 * nothing here may import outside `node:` builtins.
 *
 * CLI:
 *   node guided-tour.mjs <tour-file.mjs> [--verify] [--base-url URL]
 *                        [--out DIR] [--speed N] [--cdp URL] [--close-tab]
 *
 * Library:
 *   import { runTour } from '.../guided-tour.mjs';
 *   const report = await runTour(tour, { mode: 'verify' });
 */
import { mkdirSync, writeFileSync } from 'node:fs';
import { pathToFileURL } from 'node:url';
import { resolve as resolvePath } from 'node:path';

const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
const easeInOut = (t) => (t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2);

export async function runTour(tour, opts = {}) {
  const mode = opts.mode ?? 'narrate';
  const cdpUrl = opts.cdpUrl ?? 'http://127.0.0.1:9222';
  const outDir = opts.outDir ?? './tour-out';
  const speed = opts.speed ?? 1;
  const baseUrl = opts.baseUrl ?? tour.baseUrl ?? '';
  mkdirSync(outDir, { recursive: true });

  if (typeof WebSocket === 'undefined') {
    throw new Error('guided-tour needs Node 22+ (global WebSocket). Current: ' + process.version);
  }

  const report = {
    tour: tour.name,
    mode,
    steps: [],
    consoleErrors: [],
    failedRequests: [],
    assertions: [],
  };

  let v;
  try {
    v = await (await fetch(`${cdpUrl}/json/version`)).json();
  } catch (err) {
    throw new Error(
      `no CDP endpoint at ${cdpUrl} (${err.message}). Launch a Chromium-based browser with ` +
        '--remote-debugging-port=9222 — see the `browser` skill for per-browser commands.',
    );
  }

  const ws = new WebSocket(v.webSocketDebuggerUrl);
  let msgId = 0;
  const pending = new Map();

  const send = (method, params = {}, sessionId) =>
    new Promise((resolve, reject) => {
      const id = ++msgId;
      pending.set(id, { resolve, reject });
      ws.send(JSON.stringify({ id, method, params, ...(sessionId ? { sessionId } : {}) }));
      setTimeout(() => {
        if (pending.has(id)) {
          pending.delete(id);
          reject(new Error(`CDP timeout: ${method}`));
        }
      }, 30000);
    });

  ws.onmessage = (e) => {
    const d = JSON.parse(e.data);
    if (d.id && pending.has(d.id)) {
      const p = pending.get(d.id);
      pending.delete(d.id);
      return d.error ? p.reject(new Error(d.error.message)) : p.resolve(d.result);
    }
    if (d.method === 'Runtime.consoleAPICalled' && d.params?.type === 'error') {
      report.consoleErrors.push(
        (d.params.args || [])
          .map((a) => a.value ?? a.description ?? '')
          .join(' ')
          .slice(0, 200),
      );
    }
    if (d.method === 'Log.entryAdded' && d.params?.entry?.level === 'error') {
      report.consoleErrors.push(String(d.params.entry.text).slice(0, 200));
    }
    if (d.method === 'Network.loadingFailed' && !/favicon/.test(d.params?.request?.url ?? '')) {
      report.failedRequests.push(`FAILED ${d.params.errorText}`);
    }
    if (d.method === 'Network.responseReceived' && d.params.response.status >= 400) {
      report.failedRequests.push(
        `HTTP ${d.params.response.status} ${d.params.response.url.slice(0, 110)}`,
      );
    }
  };

  // v1 awaited `ws.onopen` alone, which hangs forever if the socket errors out.
  await new Promise((res, rej) => {
    const t = setTimeout(() => rej(new Error(`CDP websocket did not open within 15s: ${cdpUrl}`)), 15000);
    ws.onopen = () => { clearTimeout(t); res(); };
    ws.onerror = () => { clearTimeout(t); rej(new Error(`CDP websocket error against ${cdpUrl}`)); };
  });

  const { targetId } = await send('Target.createTarget', { url: 'about:blank' });
  const { sessionId } = await send('Target.attachToTarget', { targetId, flatten: true });
  for (const d of ['Page', 'Runtime', 'Network', 'Log'])
    await send(`${d}.enable`, {}, sessionId).catch(() => {});
  await send('Page.bringToFront', {}, sessionId).catch(() => {});

  const evalJs = async (expression, awaitPromise = false) => {
    const r = await send('Runtime.evaluate', { expression, returnByValue: true, awaitPromise }, sessionId);
    if (r.exceptionDetails) throw new Error(r.exceptionDetails.text);
    return r.result?.value;
  };
  const show = mode === 'narrate';
  const beat = (ms) => sleep(show ? ms / speed : 0);

  // ---- overlay (cursor, banner, caption, highlight, ripple) ----------------
  const OVERLAY = `(() => {
  if (window.__gt) return true;
  const mk = (id, css) => { const e = document.createElement('div'); e.id = id; e.style.cssText = css; document.documentElement.appendChild(e); return e; };
  const z = 2147483647;
  const cursor = mk('__gt_cursor', 'position:fixed;z-index:'+z+';left:0;top:0;width:26px;height:26px;pointer-events:none;transition:transform .45s cubic-bezier(.4,0,.2,1);will-change:transform;opacity:0');
  cursor.innerHTML = '<svg width="26" height="26" viewBox="0 0 24 24"><path d="M5 2l14 8.5-6 1.4-2.6 6.2z" fill="#fff" stroke="#111" stroke-width="1.4" stroke-linejoin="round"/></svg>';
  const ring = mk('__gt_ring', 'position:fixed;z-index:'+(z-2)+';border:2.5px solid #38bdf8;border-radius:8px;box-shadow:0 0 0 4px rgba(56,189,248,.22),0 0 22px rgba(56,189,248,.5);pointer-events:none;transition:all .35s cubic-bezier(.4,0,.2,1);opacity:0');
  const cap = mk('__gt_cap', 'position:fixed;z-index:'+z+';background:#111827;color:#f9fafb;font:600 12.5px/1.35 ui-sans-serif,system-ui;padding:6px 11px;border-radius:7px;box-shadow:0 4px 16px rgba(0,0,0,.5);pointer-events:none;transition:transform .45s cubic-bezier(.4,0,.2,1),opacity .25s;opacity:0;white-space:nowrap');
  const ban = mk('__gt_ban', 'position:fixed;z-index:'+z+';top:16px;left:50%;transform:translateX(-50%);background:#0b6bcb;color:#fff;font:600 15px/1.4 ui-sans-serif,system-ui;padding:10px 20px;border-radius:10px;box-shadow:0 8px 28px rgba(0,0,0,.5);pointer-events:none;max-width:82vw;text-align:center;opacity:0;transition:opacity .3s');
  window.__gt = {
    move(x, y) { cursor.style.opacity = 1; cursor.style.transform = 'translate(' + x + 'px,' + y + 'px)';
      cap.style.transform = 'translate(' + (x + 22) + 'px,' + (y + 16) + 'px)'; },
    say(t) { cap.textContent = t || ''; cap.style.opacity = t ? 1 : 0; },
    banner(t) { ban.textContent = t || ''; ban.style.opacity = t ? 1 : 0; },
    ring(r) { if (!r) { ring.style.opacity = 0; return; }
      ring.style.opacity = 1; ring.style.left = (r.x - 5) + 'px'; ring.style.top = (r.y - 5) + 'px';
      ring.style.width = (r.w + 10) + 'px'; ring.style.height = (r.h + 10) + 'px'; },
    ripple(x, y) { const d = document.createElement('div');
      d.style.cssText = 'position:fixed;z-index:'+(z-1)+';left:' + (x - 9) + 'px;top:' + (y - 9) + 'px;width:18px;height:18px;border-radius:50%;background:rgba(56,189,248,.55);border:2px solid #38bdf8;pointer-events:none;transition:transform .5s ease-out,opacity .5s ease-out';
      document.documentElement.appendChild(d);
      requestAnimationFrame(() => { d.style.transform = 'scale(3.6)'; d.style.opacity = '0'; });
      setTimeout(() => d.remove(), 600); },
    clear() { [cursor, ring, cap, ban].forEach(e => e.remove()); delete window.__gt; }
  };
  return true;
})()`;

  const overlay = async (fn) => {
    if (show) await evalJs(`(window.__gt&&${fn})||true`).catch(() => {});
  };
  const banner = (t) => overlay(`window.__gt.banner(${JSON.stringify(t)})`);
  const say = (t) => overlay(`window.__gt.say(${JSON.stringify(t)})`);

  let cx = 120,
    cy = 120;
  async function glideTo(x, y) {
    if (show) {
      const steps = 14,
        sx = cx,
        sy = cy;
      await evalJs(`window.__gt&&window.__gt.move(${x},${y})`).catch(() => {});
      for (let i = 1; i <= steps; i++) {
        const t = easeInOut(i / steps);
        await send(
          'Input.dispatchMouseEvent',
          {
            type: 'mouseMoved',
            x: Math.round(sx + (x - sx) * t),
            y: Math.round(sy + (y - sy) * t),
            buttons: 0,
          },
          sessionId,
        ).catch(() => {});
        await sleep(32 / speed);
      }
    }
    cx = x;
    cy = y;
  }

  async function rectOf(selector) {
    return evalJs(`(() => {
      ${RESOLVER}
      const el = __resolve(${JSON.stringify(selector)});
      if (!el) return null;
      el.scrollIntoView({ block: 'center', behavior: 'instant' });
      const r = el.getBoundingClientRect();
      return { x: r.x, y: r.y, w: r.width, h: r.height, text: (el.innerText||el.value||'').trim().slice(0,80) };
    })()`);
  }

  async function goto(url) {
    await send('Page.navigate', { url }, sessionId);
    for (let i = 0; i < 75; i++) {
      await sleep(300);
      if ((await evalJs('document.readyState').catch(() => null)) === 'complete') break;
    }
    await sleep(1500 / speed);
    if (show) await evalJs(OVERLAY).catch(() => {});
  }

  async function clickSel(selector, label) {
    const r = await rectOf(selector);
    if (!r) return false;
    const x = Math.round(r.x + r.w / 2),
      y = Math.round(r.y + r.h / 2);
    if (show) {
      await overlay(`window.__gt.ring(${JSON.stringify(r)})`);
      await say(label || `click: ${r.text || selector}`);
      await glideTo(x, y);
      await beat(500);
      await overlay(`window.__gt.ripple(${x},${y})`);
    }
    for (const type of ['mousePressed', 'mouseReleased']) {
      await send(
        'Input.dispatchMouseEvent',
        { type, x, y, button: 'left', clickCount: 1, buttons: type === 'mousePressed' ? 1 : 0 },
        sessionId,
      ).catch(() => {});
      await sleep(60);
    }
    await beat(400);
    await overlay('window.__gt.ring(null)');
    await say('');
    return true;
  }

  async function fillSel(selector, value, label) {
    const r = await rectOf(selector);
    if (!r) return false;
    const x = Math.round(r.x + r.w / 2),
      y = Math.round(r.y + r.h / 2);
    if (show) {
      await overlay(`window.__gt.ring(${JSON.stringify(r)})`);
      await say(
        label ||
          `type: ${value.replace(/./g, (c, i) => (i > 2 && /\w/.test(c) && /pass/i.test(selector) ? '•' : c))}`,
      );
      await glideTo(x, y);
    }
    for (const type of ['mousePressed', 'mouseReleased']) {
      await send(
        'Input.dispatchMouseEvent',
        { type, x, y, button: 'left', clickCount: 1, buttons: type === 'mousePressed' ? 1 : 0 },
        sessionId,
      ).catch(() => {});
    }
    await evalJs(`(() => {
      ${RESOLVER}
      const el = __resolve(${JSON.stringify(selector)});
      const set = Object.getOwnPropertyDescriptor(window.HTMLInputElement.prototype,'value').set;
      set.call(el, ${JSON.stringify(value)});
      el.dispatchEvent(new Event('input',{bubbles:true}));
      el.dispatchEvent(new Event('change',{bubbles:true}));
      return true;
    })()`);
    await beat(500);
    await overlay('window.__gt.ring(null)');
    await say('');
    return true;
  }

  const shot = async (name) => {
    const { data } = await send('Page.captureScreenshot', { format: 'png' }, sessionId);
    writeFileSync(`${outDir}/${name}.png`, Buffer.from(data, 'base64'));
  };

  // ---- run the steps ------------------------------------------------------
  let n = 0;
  const total = tour.steps.length;
  for (const step of tour.steps) {
    n++;
    const rec = {
      n,
      step: step.say ?? step.goto ?? step.click ?? step.expect ?? 'step',
      ok: true,
      notes: [],
    };
    try {
      if (step.goto) await goto(step.goto.startsWith('http') ? step.goto : baseUrl + step.goto);
      if (show && step.say) await banner(`${n}/${total} · ${step.say}`);
      if (step.waitFor) {
        let seen = false;
        for (let i = 0; i < 30; i++) {
          if (await rectOf(step.waitFor)) {
            seen = true;
            break;
          }
          await sleep(500);
        }
        if (!seen) {
          rec.ok = false;
          rec.notes.push(`waitFor never appeared: ${step.waitFor}`);
        }
      }
      if (step.fill) {
        const ok = await fillSel(step.fill.selector, step.fill.value, step.fill.label);
        if (!ok && !step.optional) {
          rec.ok = false;
          rec.notes.push(`fill target not found: ${step.fill.selector}`);
        }
        if (!ok && step.optional) {
          rec.skipped = true;
          rec.notes.push('optional — target absent, skipped');
        }
      }
      if (step.click) {
        const ok = await clickSel(step.click, step.label);
        if (!ok && !step.optional) {
          rec.ok = false;
          rec.notes.push(`click target not found: ${step.click}`);
        }
        if (!ok && step.optional) {
          rec.skipped = true;
          rec.notes.push('optional — target absent, skipped');
        }
      }
      if (step.expect) {
        const body = (await evalJs('document.body.innerText')) || '';
        for (const pat of [].concat(step.expect)) {
          const re = new RegExp(pat, 'i');
          const hit = re.test(body);
          report.assertions.push({ step: n, expect: String(pat), pass: hit });
          if (!hit) {
            rec.ok = false;
            rec.notes.push(`expected text not found: ${pat}`);
          }
        }
      }
      if (step.shot) await shot(step.shot);
      await beat(step.dwell ?? 3500);
    } catch (err) {
      rec.ok = false;
      rec.notes.push(String(err.message));
    }
    report.steps.push(rec);
    const mark = rec.skipped ? '·' : rec.ok ? '✓' : '✗';
    console.log(
      `${mark} ${n}/${total} ${rec.step}${rec.notes.length ? ' — ' + rec.notes.join('; ') : ''}`,
    );
  }

  if (show) {
    await banner('Tour complete');
    await beat(2200);
    await evalJs('window.__gt&&window.__gt.clear()').catch(() => {});
  }
  if (opts.closeTab) await send('Target.closeTarget', { targetId }).catch(() => {});
  ws.close();

  report.consoleErrors = [...new Set(report.consoleErrors)];
  report.failedRequests = [...new Set(report.failedRequests)];
  report.pass = report.steps.every((s) => s.ok) && report.assertions.every((a) => a.pass);
  writeFileSync(`${outDir}/report.json`, JSON.stringify(report, null, 2));
  return report;
}

// selector resolver injected into the page: supports `text=`, `css=`, raw CSS
const RESOLVER = `
const __resolve = (sel) => {
  if (sel.startsWith('text=')) {
    const needle = sel.slice(5).toLowerCase();
    const els = [...document.querySelectorAll('a,button,td,th,li,span,div,h1,h2,h3,p,input,label')];
    return els.filter(e => (e.innerText||'').toLowerCase().trim().includes(needle) && e.children.length <= 3)
              .sort((a,b) => (a.innerText||'').length - (b.innerText||'').length)[0] || null;
  }
  return document.querySelector(sel.startsWith('css=') ? sel.slice(4) : sel);
};`;

// ---- CLI ------------------------------------------------------------------
// Tours are plain data modules: `export default { name, baseUrl, steps }`.
// The runner lives here so tour files stay declarative and reviewable.

const USAGE = `Usage: guided-tour.mjs <tour-file.mjs> [options]

  --verify            verification mode (no theatre, exit non-zero on failure)
  --narrate           narration mode against the user's browser (default)
  --base-url <url>    override the tour's baseUrl (resolve this from sdlc.yml)
  --out <dir>         output dir for screenshots + report.json (default ./tour-out)
  --speed <n>         narration speed multiplier, >1 is faster (default 1)
  --cdp <url>         CDP endpoint (default http://127.0.0.1:9222)
  --close-tab         close the tour tab when finished`;

function parseArgs(argv) {
  const out = { flags: {} };
  const rest = [];
  for (let i = 0; i < argv.length; i++) {
    const a = argv[i];
    if (a === '--verify') out.flags.mode = 'verify';
    else if (a === '--narrate') out.flags.mode = 'narrate';
    else if (a === '--close-tab') out.flags.closeTab = true;
    else if (a === '--base-url') out.flags.baseUrl = argv[++i];
    else if (a === '--out') out.flags.outDir = argv[++i];
    else if (a === '--speed') out.flags.speed = Number(argv[++i]);
    else if (a === '--cdp') out.flags.cdpUrl = argv[++i];
    else if (a === '--help' || a === '-h') out.flags.help = true;
    else rest.push(a);
  }
  out.tourFile = rest[0];
  return out;
}

async function main(argv) {
  const { tourFile, flags } = parseArgs(argv);
  if (flags.help || !tourFile) {
    console.log(USAGE);
    process.exit(flags.help ? 0 : 2);
  }

  const mod = await import(pathToFileURL(resolvePath(tourFile)).href);
  const tour = mod.default ?? mod.tour;
  if (!tour?.steps?.length) {
    console.error(`✗ ${tourFile} has no default export with a non-empty \`steps\` array`);
    process.exit(2);
  }

  const opts = {
    mode: flags.mode ?? 'narrate',
    outDir: flags.outDir ?? './tour-out',
    ...(flags.baseUrl ? { baseUrl: flags.baseUrl } : {}),
    ...(flags.speed ? { speed: flags.speed } : {}),
    ...(flags.cdpUrl ? { cdpUrl: flags.cdpUrl } : {}),
    ...(flags.closeTab ? { closeTab: true } : {}),
  };

  const report = await runTour(tour, opts);

  console.log('\n===== REPORT =====');
  console.log('tour:', report.tour, `(${report.mode})`);
  console.log('pass:', report.pass);
  if (report.assertions.length)
    console.log('assertions:', report.assertions.map((a) => `${a.pass ? '✓' : '✗'} ${a.expect}`).join('  '));
  console.log('console errors:', report.consoleErrors.length);
  report.consoleErrors.slice(0, 8).forEach((e) => console.log('  ERR:', e));
  console.log('failed/4xx+ requests:', report.failedRequests.length);
  report.failedRequests.slice(0, 10).forEach((e) => console.log('  REQ:', e));
  console.log('report:', `${opts.outDir}/report.json`);

  process.exit(report.pass ? 0 : 1);
}

// Only run the CLI when executed directly, never when imported as a library.
if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) {
  main(process.argv.slice(2)).catch((err) => {
    console.error('✗ guided-tour failed:', err.message);
    process.exit(2);
  });
}
