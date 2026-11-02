/**
 * Commands the viewer binary runs instead of serving, for the host's terminal:
 *
 *   cc-viewer pair          a one-time pairing code for another device (asks the running viewer)
 *   cc-viewer tls [--force] a self-signed certificate for the HTTPS listener (needs openssl)
 *
 * Both talk to the same state the server uses; neither starts a server.
 */

import { existsSync, mkdirSync } from "node:fs";
import { hostname, networkInterfaces } from "node:os";
import path from "node:path";

export interface CliContext {
  readonly port: number;
  readonly tlsCert: string;
  readonly tlsKey: string;
  readonly tlsPort: number;
}

export const CLI_COMMANDS = ["pair", "tls", "help", "--help", "-h"] as const;

export async function runCli(args: string[], ctx: CliContext): Promise<number> {
  const [cmd, ...rest] = args;
  if (cmd === "pair") return pair(ctx);
  if (cmd === "tls") return tls(ctx, rest.includes("--force"));
  console.log(`usage: cc-viewer [pair | tls [--force]]
  (no command)   run the dashboard
  pair           print a one-time code to pair another device (the viewer must be running)
  tls            make a self-signed certificate for https on port ${ctx.tlsPort}; restart the viewer after`);
  return cmd === "help" || cmd === "--help" || cmd === "-h" ? 0 : 2;
}

async function pair(ctx: CliContext): Promise<number> {
  try {
    const r = await fetch(`http://127.0.0.1:${ctx.port}/pair/new`, {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: "{}",
      signal: AbortSignal.timeout(5000),
    });
    const j = (await r.json().catch(() => ({}))) as {
      code?: string;
      minutes?: number;
      error?: string;
    };
    if (!r.ok || !j.code) {
      console.error(`couldn't get a code: ${j.error ?? `HTTP ${r.status}`}`);
      return 1;
    }
    console.log(`${j.code}  (one use, ${j.minutes} min) — type it at /pair on the new device`);
    return 0;
  } catch (e) {
    console.error(`the viewer isn't answering on 127.0.0.1:${ctx.port}: ${(e as Error).message}`);
    return 1;
  }
}

/** This machine's names and non-loopback IPv4 addresses: the ones another device might type. */
export function hostNames(): { dns: string[]; ip: string[] } {
  const ip = new Set(["127.0.0.1"]);
  for (const addrs of Object.values(networkInterfaces()))
    for (const a of addrs ?? []) if (a.family === "IPv4" && !a.internal) ip.add(a.address);
  return { dns: [...new Set(["localhost", hostname()])], ip: [...ip] };
}

function tls(ctx: CliContext, force: boolean): number {
  if (!force && (existsSync(ctx.tlsCert) || existsSync(ctx.tlsKey))) {
    console.error(`a certificate already exists (${ctx.tlsCert}); pass --force to replace it`);
    return 1;
  }
  const { dns, ip } = hostNames();
  const san = [...dns.map((d) => `DNS:${d}`), ...ip.map((a) => `IP:${a}`)].join(",");
  mkdirSync(path.dirname(ctx.tlsCert), { recursive: true, mode: 0o700 });
  mkdirSync(path.dirname(ctx.tlsKey), { recursive: true, mode: 0o700 });
  const r = Bun.spawnSync(
    [
      "openssl",
      "req",
      "-x509",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-days",
      "825",
      "-keyout",
      ctx.tlsKey,
      "-out",
      ctx.tlsCert,
      "-subj",
      `/CN=cc-viewer ${hostname()}`,
      "-addext",
      `subjectAltName=${san}`,
      "-addext",
      "extendedKeyUsage=serverAuth",
    ],
    { stdout: "ignore", stderr: "pipe" },
  );
  if (r.exitCode !== 0) {
    console.error(`openssl failed: ${r.stderr.toString().trim() || `exit ${r.exitCode}`}`);
    return 1;
  }
  Bun.spawnSync(["chmod", "600", ctx.tlsKey]);
  console.log(`certificate  ${ctx.tlsCert}
covers       ${san.replaceAll(",", ", ")}

Restart the viewer, then open https://${ip.find((a) => a !== "127.0.0.1") ?? dns[1]}:${ctx.tlsPort}/voice.
So browsers trust it (and allow the microphone without a warning), on each device:
  macOS   scp <host>:${ctx.tlsCert} ~/cc-viewer.pem
          sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ~/cc-viewer.pem
  iOS     AirDrop or mail the .pem, install the profile, then Settings → General → About →
          Certificate Trust Settings → turn it on`);
  return 0;
}
