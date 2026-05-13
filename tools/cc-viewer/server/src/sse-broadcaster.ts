/**
 * Tiny SSE fan-out. Replaces SSEExporter + SSEFormatter from the original
 * runtime — the viewer only needs to push one event name to N connected
 * clients, no profile filtering, no canonical-event mapping.
 *
 * Wire format per connection: `event: <name>\ndata: <JSON>\n\n`.
 */

interface Client {
  controller: ReadableStreamDefaultController<Uint8Array>;
}

export class SSEBroadcaster {
  private readonly clients = new Map<ReadableStream<Uint8Array>, Client>();
  private readonly encoder = new TextEncoder();

  /** Open a new client stream. Hand the returned stream to the HTTP response. */
  connect(): ReadableStream<Uint8Array> {
    let controllerRef: ReadableStreamDefaultController<Uint8Array>;
    const stream = new ReadableStream<Uint8Array>({
      start: (controller) => {
        controllerRef = controller;
      },
    });
    this.clients.set(stream, { controller: controllerRef! });
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
}
