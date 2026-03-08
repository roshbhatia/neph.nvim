import { describe, it, expect, vi } from 'vitest';

describe('SocketTransport.close', () => {
  it('calls disconnect() not quit() on the neovim client', async () => {
    // Verify the source uses disconnect, not quit
    // This is a static analysis guard — if someone changes disconnect back to quit,
    // this test will catch it
    const { readFileSync } = await import('node:fs');
    const { resolve } = await import('node:path');
    const src = readFileSync(resolve(__dirname, '../src/transport.ts'), 'utf8');

    expect(src).toContain('.disconnect()');
    expect(src).not.toContain('.quit()');
  });
});
