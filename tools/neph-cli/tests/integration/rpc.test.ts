/**
 * Integration tests — spawn a real headless Neovim instance with neph.nvim
 * on the runtimepath, exercise SocketTransport against it.
 *
 * Requires `nvim` on PATH. Skipped if nvim is unavailable.
 *
 * NOTE: We test at the transport layer rather than through runCommand because
 * runCommand → SocketTransport.close() calls client.quit() which kills nvim.
 * The CLI is designed as a short-lived process; integration tests verify the
 * RPC contract works end-to-end.
 */
import { describe, it, expect, beforeAll, afterAll } from 'vitest';
import { spawn, ChildProcess, execSync } from 'node:child_process';
import * as fs from 'node:fs';
import * as path from 'node:path';
import * as os from 'node:os';
import { SocketTransport } from '../../src/transport';

const REPO_ROOT = path.resolve(__dirname, '../../../..');
const SOCKET_PATH = path.join(os.tmpdir(), `neph-test-${process.pid}.sock`);
const RPC_CALL = 'return require("neph.rpc").request(...)';

let nvimProc: ChildProcess | null = null;

function nvimAvailable(): boolean {
  try {
    execSync('nvim --version', { stdio: 'ignore' });
    return true;
  } catch {
    return false;
  }
}

function waitForSocket(sockPath: string, timeoutMs = 5000): Promise<void> {
  return new Promise((resolve, reject) => {
    const start = Date.now();
    const check = () => {
      if (fs.existsSync(sockPath)) return resolve();
      if (Date.now() - start > timeoutMs) return reject(new Error('nvim socket not created'));
      setTimeout(check, 50);
    };
    check();
  });
}

/** Create a transport that disconnects without quitting nvim */
function connect(): SocketTransport {
  return new SocketTransport(SOCKET_PATH);
}

const HAS_NVIM = nvimAvailable();

describe.runIf(HAS_NVIM)('integration: headless nvim', () => {
  beforeAll(async () => {
    try { fs.unlinkSync(SOCKET_PATH); } catch {}

    nvimProc = spawn('nvim', [
      '--headless',
      '--noplugin',
      '-u', 'NONE',
      '--cmd', `set rtp+=${REPO_ROOT}`,
      '--listen', SOCKET_PATH,
    ], {
      stdio: ['pipe', 'ignore', 'ignore'],
    });

    await waitForSocket(SOCKET_PATH);
  }, 10000);

  afterAll(async () => {
    if (nvimProc) {
      nvimProc.kill('SIGTERM');
      await new Promise<void>((resolve) => {
        if (!nvimProc) return resolve();
        nvimProc.on('exit', () => resolve());
        setTimeout(resolve, 1000);
      });
    }

    try { fs.unlinkSync(SOCKET_PATH); } catch {}
  }, 5000);

  it('connects and gets API info', async () => {
    const t = connect();
    const channelId = await t.getChannelId();
    expect(channelId).toBeGreaterThan(0);
    // Don't call t.close() — it quits nvim. The socket stays open.
  }, 10000);

  it('status.set writes to vim.g', async () => {
    const t = connect();
    const result = await t.executeLua(RPC_CALL, ['status.set', { name: 'neph_integ_test', value: 'hello' }]);
    expect(result).toEqual({ ok: true, result: { ok: true } });

    // Read back
    const val = await t.executeLua('return vim.g.neph_integ_test', []);
    expect(val).toBe('hello');
  }, 10000);

  it('status.unset clears vim.g', async () => {
    const t = connect();
    // Pre-set
    await t.executeLua('vim.g.neph_integ_unset = "exists"', []);

    const result = await t.executeLua(RPC_CALL, ['status.unset', { name: 'neph_integ_unset' }]);
    expect(result).toEqual({ ok: true, result: { ok: true } });

    const val = await t.executeLua('return vim.g.neph_integ_unset', []);
    expect(val).toBeNull();
  }, 10000);

  it('buffers.check executes without error', async () => {
    const t = connect();
    const result = await t.executeLua(RPC_CALL, ['buffers.check', {}]);
    expect(result).toEqual({ ok: true, result: { ok: true } });
  }, 10000);

  it('unknown method returns METHOD_NOT_FOUND', async () => {
    const t = connect();
    const result = await t.executeLua(RPC_CALL, ['nonexistent.method', {}]) as any;
    expect(result.ok).toBe(false);
    expect(result.error.code).toBe('METHOD_NOT_FOUND');
  }, 10000);
});
