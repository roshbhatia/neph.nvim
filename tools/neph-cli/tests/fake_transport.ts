import { NvimTransport } from '../src/transport';

// ---------------------------------------------------------------------------
// Shared review-stdin factory
// ---------------------------------------------------------------------------

/**
 * Build the JSON string that neph review / runReview expects on stdin.
 * Override any field to exercise validation branches.
 */
export function makeReviewStdin(overrides: Partial<{
  path: string;
  content: string;
  agent: string;
}> = {}): string {
  return JSON.stringify({
    path: '/tmp/test.lua',
    content: 'hello world',
    ...overrides,
  });
}

/**
 * Pass 4/6/9/10: FakeTransport is a complete, mockable implementation of
 * NvimTransport that covers all lifecycle states and failure modes.
 *
 * Key capabilities:
 *  - responses[method]: map an RPC method name (args[0]) to a return value.
 *  - executeLuaError: if set, the next executeLua call throws this error.
 *  - isClosed: reflects whether close() has been called.
 *  - closeCallCount: how many times close() was called.
 *  - calls: record of all executeLua invocations for assertion.
 *  - notifications / fireNotification: simulate Neovim push notifications.
 */
export class FakeTransport implements NvimTransport {
  /** All executeLua invocations, in order. */
  public calls: { code: string; args: unknown[] }[] = [];

  /** Notification handlers registered via onNotification, keyed by event name. */
  public notifications: { [event: string]: ((args: unknown[]) => void)[] } = {};

  /**
   * Response map: keyed by the RPC method name (args[0] in executeLua calls).
   * If a key is absent, executeLua returns { ok: true }.
   */
  public responses: { [method: string]: unknown } = {};

  /**
   * Pass 10: If set, the next executeLua call rejects with this error.
   * Cleared after use so only the next call is affected.
   */
  public executeLuaError: Error | null = null;

  /**
   * Pass 4: True after close() has been called — tests can assert lifecycle state.
   */
  public isClosed = false;

  /**
   * Pass 6: Number of times close() has been called — tests can assert idempotency.
   */
  public closeCallCount = 0;

  async executeLua(code: string, args: unknown[]): Promise<unknown> {
    this.calls.push({ code, args });

    // Pass 10: Error injection — cleared after use.
    if (this.executeLuaError !== null) {
      const err = this.executeLuaError;
      this.executeLuaError = null;
      throw err;
    }

    const method = args[0] as string;
    return this.responses[method] ?? { ok: true };
  }

  onNotification(event: string, handler: (args: unknown[]) => void): void {
    if (!this.notifications[event]) this.notifications[event] = [];
    this.notifications[event].push(handler);
  }

  async getChannelId(): Promise<number> {
    return 42;
  }

  async close(): Promise<void> {
    // Pass 6: Track lifecycle — idempotent in the sense that it never throws,
    // but closeCallCount increments so tests can detect duplicate calls.
    this.closeCallCount += 1;
    this.isClosed = true;
  }

  /**
   * Simulate a Neovim push notification arriving from the server.
   * Triggers all handlers registered for the given event.
   */
  public fireNotification(event: string, args: unknown[]): void {
    if (this.notifications[event]) {
      for (const handler of this.notifications[event]) {
        handler(args);
      }
    }
  }
}
