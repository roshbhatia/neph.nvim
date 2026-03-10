import { describe, it, expect } from 'vitest';
import * as fs from 'node:fs';
import * as path from 'node:path';

describe('protocol.json contract', () => {
  const protocolPath = path.resolve(__dirname, '../../../protocol.json');
  const protocol = JSON.parse(fs.readFileSync(protocolPath, 'utf8'));

  it('has a version field', () => {
    expect(protocol.version).toBe('neph-rpc/v1');
  });

  it('defines all expected methods', () => {
    const expectedMethods = [
      'review.open',
      'status.set',
      'status.unset',
      'buffers.check',
      'tab.close',
      'ui.select',
      'ui.input',
      'ui.notify',
    ];
    for (const method of expectedMethods) {
      expect(protocol.methods[method]).toBeDefined();
    }
  });

  it('each method has a params array', () => {
    for (const [name, spec] of Object.entries(protocol.methods)) {
      expect(Array.isArray((spec as any).params)).toBe(true);
    }
  });

  it('CLI commands map to known protocol methods', () => {
    const cliMethods = ['status.set', 'status.unset', 'buffers.check', 'tab.close', 'review.open'];
    for (const method of cliMethods) {
      expect(protocol.methods[method]).toBeDefined();
    }
  });
});
