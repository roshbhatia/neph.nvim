import { NvimTransport } from '../src/transport';

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
