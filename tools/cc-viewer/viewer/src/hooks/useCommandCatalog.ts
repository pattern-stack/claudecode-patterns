/**
 * useCommandCatalog — the slash-command palette source, kept live.
 *
 * Lazy: nothing is fetched and no stream is opened until `enabled` flips true
 * (the composer flips it on the first "/"). Once enabled, it fetches the
 * catalog and subscribes to the SSE `commands_changed` event so toggling a
 * plugin / installing a command updates the palette without a reload.
 */

import { useEffect, useState } from "react";
import { type CommandEntry, fetchCommands } from "../lib/eventApi";

const COMMANDS_CHANGED_EVENT = "cc_viewer.commands_changed";

export function useCommandCatalog(cwd: string | undefined, enabled: boolean): CommandEntry[] | null {
  const [commands, setCommands] = useState<CommandEntry[] | null>(null);

  useEffect(() => {
    if (!enabled) return;
    let alive = true;

    const load = () => {
      fetchCommands(cwd)
        .then((c) => {
          if (alive) setCommands(c);
        })
        .catch(() => {
          if (alive) setCommands([]);
        });
    };

    load();

    // Re-fetch when the on-disk command sources change.
    const es = new EventSource("/admin/events/stream");
    const onChange = () => load();
    es.addEventListener(COMMANDS_CHANGED_EVENT, onChange);

    return () => {
      alive = false;
      es.removeEventListener(COMMANDS_CHANGED_EVENT, onChange);
      es.close();
    };
  }, [enabled, cwd]);

  return commands;
}
