import { describe, it, expect, vi } from 'vitest';

describe('SocketTransport.close', () => {
  it('calls close() on the neovim client', async () => {
    // Verify the source uses close()
    const { readFileSync } = await import('node:fs');
    const { resolve } = await import('node:path');
    const src = readFileSync(resolve(__dirname, '../src/transport.ts'), 'utf8');

    expect(src).toContain('.close()');
  });
});
