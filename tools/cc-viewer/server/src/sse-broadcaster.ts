/**
 * Tiny SSE fan-out. Replaces SSEExporter + SSEFormatter from the original
 * runtime — the viewer only needs to push one event name to N connected
 * clients, no profile filtering, no canonical-event mapping.
 *
 * Wire format per connection: `event: <name>\ndata: <JSON>\n\n`.
 *
 * Keepalive: a `:keepalive` comment frame is pushed to every client every
 * 15s. EventSource ignores comment frames but the bytes-on-the-wire keep
 * proxies / browsers / Bun's own idle policy from closing the connection.
 */

const KEEPALIVE_INTERVAL_MS = 15_000;

interface Client {
  controller: ReadableStreamDefaultController<Uint8Array>;
}

export class SSEBroadcaster {
  private readonly clients = new Map<ReadableStream<Uint8Array>, Client>();
  private readonly encoder = new TextEncoder();
  private readonly keepaliveFrame: Uint8Array;
  private keepaliveTimer: ReturnType<typeof setInterval> | null = null;

  constructor() {
    this.keepaliveFrame = this.encoder.encode(":keepalive\n\n");
  }

  /** Open a new client stream. Hand the returned stream to the HTTP response. */
  connect(): ReadableStream<Uint8Array> {
    let controllerRef: ReadableStreamDefaultController<Uint8Array>;
    const stream = new ReadableStream<Uint8Array>({
      start: (controller) => {
        controllerRef = controller;
        // Push an immediate keepalive byte. The browser's EventSource
        // stays in CONNECTING (readyState 0) until it sees the first body
        // byte from the server. Without this, a freshly-loaded page sits
        // showing "reconnecting…" until either a real event or the 15s
        // keepalive tick lands — silent SSE for up to 15s on load.
        controller.enqueue(this.keepaliveFrame);
      },
    });
    this.clients.set(stream, { controller: controllerRef! });
    this.ensureKeepalive();
    return stream;
  }

  disconnect(stream: ReadableStream<Uint8Array>): void {
    const client = this.clients.get(stream);
    if (!client) return;
    try {
      client.controller.close();
    } catch {
      // already closed
    }
    this.clients.delete(stream);
  }

  /** Push a named event to every connected client. */
  broadcast(name: string, data: unknown): void {
    if (this.clients.size === 0) return;
    const frame = this.encoder.encode(
      `event: ${name}\ndata: ${JSON.stringify(data)}\n\n`,
    );
    for (const [stream, client] of this.clients) {
      try {
        client.controller.enqueue(frame);
      } catch {
        this.clients.delete(stream);
      }
    }
  }

  /** Current connected-client count. Useful for diagnostics. */
  get size(): number {
    return this.clients.size;
  }

  private ensureKeepalive(): void {
    if (this.keepaliveTimer !== null) return;
    this.keepaliveTimer = setInterval(() => {
      if (this.clients.size === 0) {
        clearInterval(this.keepaliveTimer!);
        this.keepaliveTimer = null;
        return;
      }
      for (const [stream, client] of this.clients) {
        try {
          client.controller.enqueue(this.keepaliveFrame);
        } catch {
          this.clients.delete(stream);
        }
      }
    }, KEEPALIVE_INTERVAL_MS);
    this.keepaliveTimer.unref?.();
  }
}
