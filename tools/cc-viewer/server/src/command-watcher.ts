/**
 * Command-catalog watcher.
 *
 * Watches the on-disk sources that GET /admin/commands reads (plugin enable
 * toggles + install/update) and broadcasts `commands_changed` on the SSE
 * stream so open composers re-fetch the palette live.
 *
 * We watch the containing directories (not the files) so atomic writes
 * (write-temp + rename, which Claude Code does) keep firing — a file watch
 * goes dead once the original inode is replaced. Events are debounced into a
 * single broadcast.
 *
 * Scope: user-level config only (`~/.claude/settings*.json`,
 * `~/.claude/plugins/installed_plugins.json`). Per-project command edits are
 * picked up on the composer's mount/cwd re-fetch, not watched here.
 */

import { type FSWatcher, watch } from "node:fs";
import { homedir } from "node:os";
import path from "node:path";
import { COMMANDS_CHANGED_TYPE } from "./event-types.js";
import type { SSEBroadcaster } from "./sse-broadcaster.js";

const DEBOUNCE_MS = 300;

interface WatchTarget {
  dir: string;
  files: Set<string>;
}

export function watchCommandSources(broadcaster: SSEBroadcaster): () => void {
  const home = homedir();
  const targets: WatchTarget[] = [
    {
      dir: path.join(home, ".claude"),
      files: new Set(["settings.json", "settings.local.json"]),
    },
    {
      dir: path.join(home, ".claude", "plugins"),
      files: new Set(["installed_plugins.json"]),
    },
  ];

  let timer: ReturnType<typeof setTimeout> | null = null;
  const fire = () => {
    if (timer) return;
    timer = setTimeout(() => {
      timer = null;
      broadcaster.broadcast(COMMANDS_CHANGED_TYPE, {});
    }, DEBOUNCE_MS);
  };

  const watchers: FSWatcher[] = [];
  for (const target of targets) {
    try {
      const w = watch(target.dir, (_event, filename) => {
        if (filename && target.files.has(path.basename(filename.toString()))) fire();
      });
      w.on("error", () => {
        /* directory vanished / platform hiccup — best-effort */
      });
      watchers.push(w);
    } catch {
      // Directory may not exist (e.g. no plugins yet); skip silently.
    }
  }

  return () => {
    if (timer) clearTimeout(timer);
    for (const w of watchers) {
      try {
        w.close();
      } catch {
        /* already closed */
      }
    }
  };
}
