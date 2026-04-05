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

export class FakeTransport implements NvimTransport {
  public calls: { code: string, args: unknown[] }[] = [];
  public notifications: { [event: string]: ((args: unknown[]) => void)[] } = {};
  public responses: { [method: string]: any } = {};

  async executeLua(code: string, args: unknown[]): Promise<unknown> {
    const method = (args[0] as string);
    this.calls.push({ code, args });
    return this.responses[method] || { ok: true };
  }

  onNotification(event: string, handler: (args: unknown[]) => void): void {
    if (!this.notifications[event]) this.notifications[event] = [];
    this.notifications[event].push(handler);
  }

  async getChannelId(): Promise<number> {
    return 42;
  }

  async close(): Promise<void> {}

  public fireNotification(event: string, args: unknown[]) {
    if (this.notifications[event]) {
      for (const handler of this.notifications[event]) {
        handler(args);
      }
    }
  }
}
