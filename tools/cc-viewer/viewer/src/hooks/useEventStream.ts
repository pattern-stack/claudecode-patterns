import { useEffect, useRef, useState } from "react";

export interface StreamEvent {
  id: string;
  type: string;
  data: Record<string, unknown>;
  timestamp: string;
}

const DEFAULT_MAX_EVENTS = 500;
const INITIAL_RETRY_MS = 1000;
const MAX_RETRY_MS = 30_000;

interface UseEventStreamResult {
  events: StreamEvent[];
  connected: boolean;
  error: string | null;
  clear: () => void;
}

export interface UseEventStreamOptions {
  /**
   * Events to seed `events` with on first render. Pages that hydrate from
   * REST history pass these in so the UI doesn't start empty on cold load.
   */
  initialEvents?: StreamEvent[];
  /**
   * Cap on the retained event buffer. A live tail view wants a small cap; the
   * session index (which reduces the whole buffer into sessions/teammates) must
   * keep enough history that a swarm's `TeammateIdle` tags aren't evicted, so it
   * passes a cap above the seed size. Default 500.
   */
  maxEvents?: number;
  /**
   * SSE event names to subscribe to. Defaults to both `claude_code.hook` and
   * `claude_code.transcript_delta`. Consumers that only reduce hook events (the
   * session index) should pass `["claude_code.hook"]` so transcript deltas don't
   * flood the buffer and trigger a full re-reduction per streamed line.
   */
  eventNames?: string[];
}

const DEFAULT_EVENT_NAMES = ["claude_code.hook", "claude_code.transcript_delta"];

export function useEventStream(
  path: string,
  options: UseEventStreamOptions = {},
): UseEventStreamResult {
  const maxEvents = options.maxEvents ?? DEFAULT_MAX_EVENTS;
  const eventNames = options.eventNames ?? DEFAULT_EVENT_NAMES;
  const [events, setEvents] = useState<StreamEvent[]>(options.initialEvents ?? []);
  const [connected, setConnected] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const counterRef = useRef(0);
  const retryDelayRef = useRef(INITIAL_RETRY_MS);
  const retryTimerRef = useRef<ReturnType<typeof setTimeout> | undefined>(undefined);

  useEffect(() => {
    // Allow callers to defer the connection by passing an empty path. Useful
    // when the page is still hydrating from REST and the SSE feed shouldn't
    // start until that's done.
    if (!path) return;

    let cancelled = false;
    let source: EventSource | null = null;

    function connect() {
      if (cancelled) return;

      source = new EventSource(path);

      source.onopen = () => {
        setConnected(true);
        setError(null);
        retryDelayRef.current = INITIAL_RETRY_MS;
      };

      const ingest = (type: string, data: string) => {
        try {
          const parsed = JSON.parse(data);
          const streamEvent: StreamEvent = {
            id: String(counterRef.current++),
            type,
            data: parsed,
            timestamp: parsed.timestamp ?? new Date().toISOString(),
          };
          setEvents((prev) => {
            const next = [...prev, streamEvent];
            return next.length > maxEvents ? next.slice(-maxEvents) : next;
          });
        } catch {
          // ignore malformed events
        }
      };

      source.onmessage = (e) => ingest(e.type || "message", e.data);
      for (const name of eventNames) {
        source.addEventListener(name, (e) => ingest(name, (e as MessageEvent).data));
      }

      source.onerror = () => {
        setConnected(false);
        setError("Connection lost. Reconnecting...");
        source?.close();
        source = null;

        if (!cancelled) {
          const delay = retryDelayRef.current;
          retryDelayRef.current = Math.min(delay * 2, MAX_RETRY_MS);
          retryTimerRef.current = setTimeout(connect, delay);
        }
      };
    }

    connect();

    return () => {
      cancelled = true;
      source?.close();
      source = null;
      setConnected(false);
      if (retryTimerRef.current) {
        clearTimeout(retryTimerRef.current);
      }
    };
  }, [path]);

  const clear = () => setEvents([]);

  return { events, connected, error, clear };
}
