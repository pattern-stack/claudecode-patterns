/**
 * Slash-command catalog.
 *
 * Projects the `/` commands Claude Code reads — so the chat composer can show
 * the same palette. Sources, in the order CC resolves them:
 *   - enabled plugins (settings.json `enabledPlugins`, pinned by
 *     installed_plugins.json): each plugin's `commands/*.md` and
 *     `user-invocable` `skills/*\/SKILL.md`.
 *   - the session project's own `<cwd>/.claude/commands/*.md` (when `?cwd=`).
 *
 * Plugin items are namespaced `<plugin>:<name>` (the canonical invocation);
 * project/user items are bare. Built-in commands (/help, /clear, …) are not
 * file-backed and are intentionally omitted.
 *
 * Read-only over the user's ~/.claude config. Descriptions come straight from
 * each file's frontmatter.
 */

import { existsSync, readdirSync, readFileSync, statSync } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { Hono } from "hono";

export interface CommandEntry {
  /** Invocation token without the leading slash, e.g. "sdlc:design". */
  name: string;
  description: string;
  argumentHint?: string;
  /** Owning plugin key (e.g. "sdlc@claudecode-patterns"), or null for project/builtin. */
  plugin: string | null;
  kind: "command" | "skill" | "project" | "builtin";
}

const HOME = homedir();

/**
 * Claude Code's built-in commands + built-in skills. These ship in the binary
 * (not file-backed), so they can't be enumerated from disk — this is a curated
 * snapshot and may drift slightly across CC versions. Descriptions are kept
 * terse; names are bare (no plugin namespace).
 */
const DEFAULT_COMMANDS: CommandEntry[] = [
  // session / context
  { name: "help", description: "List available commands and usage.", plugin: null, kind: "builtin" },
  { name: "clear", description: "Clear the conversation history and free the context window.", plugin: null, kind: "builtin" },
  { name: "compact", description: "Summarize the conversation to reclaim context (optional focus).", plugin: null, kind: "builtin" },
  { name: "context", description: "Visualize how the context window is being used.", plugin: null, kind: "builtin" },
  { name: "cost", description: "Show token usage and cost for the current session.", plugin: null, kind: "builtin" },
  { name: "resume", description: "Resume a previous conversation.", plugin: null, kind: "builtin" },
  { name: "export", description: "Export the current conversation.", plugin: null, kind: "builtin" },
  // config / model
  { name: "model", description: "Switch the active model.", plugin: null, kind: "builtin" },
  { name: "config", description: "Open settings / configuration.", plugin: null, kind: "builtin" },
  { name: "permissions", description: "View and edit tool permissions.", plugin: null, kind: "builtin" },
  { name: "hooks", description: "Configure lifecycle hooks.", plugin: null, kind: "builtin" },
  { name: "mcp", description: "Manage MCP server connections.", plugin: null, kind: "builtin" },
  { name: "agents", description: "Create and manage subagents.", plugin: null, kind: "builtin" },
  { name: "add-dir", description: "Add another working directory to the session.", plugin: null, kind: "builtin" },
  { name: "vim", description: "Toggle vim-style input editing.", plugin: null, kind: "builtin" },
  { name: "terminal-setup", description: "Install terminal keybindings (e.g. Shift+Enter for newline).", plugin: null, kind: "builtin" },
  { name: "ide", description: "Connect to an IDE integration.", plugin: null, kind: "builtin" },
  // project / repo
  { name: "init", description: "Generate a CLAUDE.md for the current project.", plugin: null, kind: "builtin" },
  { name: "memory", description: "Edit CLAUDE.md memory files.", plugin: null, kind: "builtin" },
  { name: "review", description: "Review a pull request.", plugin: null, kind: "builtin" },
  // health / account
  { name: "doctor", description: "Diagnose installation and config health.", plugin: null, kind: "builtin" },
  { name: "status", description: "Show account and session status.", plugin: null, kind: "builtin" },
  { name: "bug", description: "Report a bug to Anthropic.", plugin: null, kind: "builtin" },
  { name: "login", description: "Authenticate.", plugin: null, kind: "builtin" },
  { name: "logout", description: "Sign out.", plugin: null, kind: "builtin" },
  // built-in skills (user-invocable)
  { name: "code-review", description: "Review the current diff for correctness bugs and reuse/simplification cleanups.", plugin: null, kind: "builtin" },
  { name: "security-review", description: "Security review of the pending changes on the current branch.", plugin: null, kind: "builtin" },
  { name: "simplify", description: "Clean up changed code (reuse / simplification / efficiency) and apply the fixes.", plugin: null, kind: "builtin" },
  { name: "deep-research", description: "Multi-source, adversarially fact-checked research report with citations.", plugin: null, kind: "builtin" },
  { name: "run", description: "Launch and drive the project's app to see a change working.", plugin: null, kind: "builtin" },
  { name: "verify", description: "Run the app and confirm a change behaves as intended.", plugin: null, kind: "builtin" },
  { name: "loop", description: "Run a prompt or slash command on a recurring interval.", plugin: null, kind: "builtin" },
  { name: "schedule", description: "Create / manage scheduled cloud agents (cron routines).", plugin: null, kind: "builtin" },
  { name: "claude-api", description: "Reference for the Claude API / Anthropic SDK (models, pricing, params, tools).", plugin: null, kind: "builtin" },
  { name: "update-config", description: "Configure the Claude Code harness via settings.json.", plugin: null, kind: "builtin" },
  { name: "keybindings-help", description: "Customize keyboard shortcuts / chord bindings.", plugin: null, kind: "builtin" },
  { name: "fewer-permission-prompts", description: "Add an allowlist to reduce permission prompts.", plugin: null, kind: "builtin" },
];

/** Parse a leading `---` frontmatter block into a flat key→value map. */
function parseFrontmatter(text: string): Record<string, string> {
  if (!text.startsWith("---")) return {};
  const end = text.indexOf("\n---", 3);
  if (end === -1) return {};
  const block = text.slice(3, end);
  const out: Record<string, string> = {};
  for (const line of block.split("\n")) {
    const m = line.match(/^([A-Za-z0-9_-]+):\s*(.*)$/);
    const key = m?.[1];
    const raw = m?.[2];
    if (key === undefined || raw === undefined) continue;
    let val = raw.trim();
    if ((val.startsWith('"') && val.endsWith('"')) || (val.startsWith("'") && val.endsWith("'"))) {
      val = val.slice(1, -1);
    }
    out[key] = val;
  }
  return out;
}

function readJsonSafe<T>(file: string): T | null {
  try {
    return JSON.parse(readFileSync(file, "utf8")) as T;
  } catch {
    return null;
  }
}

/** Plugins toggled on across user settings (+ local override). */
function enabledPluginKeys(): Set<string> {
  const enabled = new Set<string>();
  for (const f of ["settings.json", "settings.local.json"]) {
    const cfg = readJsonSafe<{ enabledPlugins?: Record<string, boolean> }>(
      path.join(HOME, ".claude", f),
    );
    if (cfg?.enabledPlugins) {
      for (const [key, on] of Object.entries(cfg.enabledPlugins)) {
        if (on) enabled.add(key);
        else enabled.delete(key);
      }
    }
  }
  return enabled;
}

/** Map "<plugin>@<marketplace>" → installed install path. */
function installPaths(): Record<string, string> {
  const j = readJsonSafe<{ plugins?: Record<string, { installPath?: string }[]> }>(
    path.join(HOME, ".claude", "plugins", "installed_plugins.json"),
  );
  const out: Record<string, string> = {};
  for (const [key, entries] of Object.entries(j?.plugins ?? {})) {
    const p = entries?.[0]?.installPath;
    if (p) out[key] = p;
  }
  return out;
}

/** Recursively collect `*.md` files under `dir`, returning [relPathNoExt, absPath]. */
function collectMarkdown(dir: string): [string, string][] {
  if (!existsSync(dir)) return [];
  const out: [string, string][] = [];
  const walk = (cur: string, rel: string) => {
    let entries: string[];
    try {
      entries = readdirSync(cur);
    } catch {
      return;
    }
    for (const name of entries) {
      const abs = path.join(cur, name);
      let st: ReturnType<typeof statSync>;
      try {
        st = statSync(abs);
      } catch {
        continue;
      }
      if (st.isDirectory()) walk(abs, rel ? `${rel}/${name}` : name);
      else if (name.endsWith(".md")) {
        const stem = name.slice(0, -3);
        out.push([rel ? `${rel}/${stem}` : stem, abs]);
      }
    }
  };
  walk(dir, "");
  return out;
}

function pluginShortName(key: string): string {
  return key.split("@")[0] ?? key;
}

/** Enumerate commands + user-invocable skills for one installed plugin. */
function pluginEntries(pluginKey: string, installPath: string): CommandEntry[] {
  const short = pluginShortName(pluginKey);
  const entries: CommandEntry[] = [];

  // commands/*.md → /<plugin>:<name>
  for (const [rel, abs] of collectMarkdown(path.join(installPath, "commands"))) {
    const fm = parseFrontmatter(readFileSync(abs, "utf8"));
    entries.push({
      name: `${short}:${rel.replace(/\//g, ":")}`,
      description: fm.description ?? "",
      argumentHint: fm["argument-hint"] || undefined,
      plugin: pluginKey,
      kind: "command",
    });
  }

  // skills/*/SKILL.md with user-invocable: true → /<plugin>:<skill name>
  const skillsDir = path.join(installPath, "skills");
  if (existsSync(skillsDir)) {
    for (const entry of readdirSync(skillsDir)) {
      const skillFile = path.join(skillsDir, entry, "SKILL.md");
      if (!existsSync(skillFile)) continue;
      const fm = parseFrontmatter(readFileSync(skillFile, "utf8"));
      if (fm["user-invocable"] !== "true") continue;
      const skillName = fm.name || entry;
      entries.push({
        name: `${short}:${skillName}`,
        description: fm.description ?? "",
        plugin: pluginKey,
        kind: "skill",
      });
    }
  }

  return entries;
}

/** Project-local commands: <cwd>/.claude/commands/*.md, invoked bare. */
function projectEntries(cwd: string): CommandEntry[] {
  const dir = path.join(cwd, ".claude", "commands");
  return collectMarkdown(dir).map(([rel, abs]) => {
    const fm = parseFrontmatter(readFileSync(abs, "utf8"));
    return {
      name: rel.replace(/\//g, ":"),
      description: fm.description ?? "",
      argumentHint: fm["argument-hint"] || undefined,
      plugin: null,
      kind: "project" as const,
    };
  });
}

function buildCatalog(cwd?: string): CommandEntry[] {
  const enabled = enabledPluginKeys();
  const paths = installPaths();
  const all: CommandEntry[] = [];

  for (const key of enabled) {
    const installPath = paths[key];
    if (!installPath || !existsSync(installPath)) continue;
    all.push(...pluginEntries(key, installPath));
  }
  if (cwd && existsSync(cwd)) all.push(...projectEntries(cwd));
  // Defaults last so a project/plugin command of the same bare name wins.
  all.push(...DEFAULT_COMMANDS);

  // Dedupe by name (first wins), then sort alphabetically.
  const seen = new Set<string>();
  const deduped = all.filter((e) => (seen.has(e.name) ? false : (seen.add(e.name), true)));
  deduped.sort((a, b) => a.name.localeCompare(b.name));
  return deduped;
}

export function commandRoutes(): Hono {
  const app = new Hono();

  app.get("/admin/commands", (c) => {
    const cwd = c.req.query("cwd") || undefined;
    let commands: CommandEntry[];
    try {
      commands = buildCatalog(cwd);
    } catch (err) {
      return c.json(
        { error: "failed to read command catalog", detail: String(err instanceof Error ? err.message : err) },
        500,
      );
    }
    return c.json({ commands, count: commands.length });
  });

  return app;
}
