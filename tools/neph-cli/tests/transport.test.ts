// tests/transport.test.ts
// Unit tests for discoverNvimSocket() and SocketTransport reliability.
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// Must be hoisted before the module under test is imported.
vi.mock('glob', () => ({ globSync: vi.fn(() => []) }));
vi.mock('node:fs');
vi.mock('node:child_process');

import * as fs from 'node:fs';
import * as childProcess from 'node:child_process';
import { globSync } from 'glob';
import { discoverNvimSocket, SocketTransport, DEFAULT_REQUEST_TIMEOUT_MS } from '../src/transport';
import { EventEmitter } from 'node:events';
import type * as net from 'node:net';

// ---------------------------------------------------------------------------
// Socket / client fakes
// ---------------------------------------------------------------------------

function makeFakeSocket(): net.Socket {
  const emitter = new EventEmitter();
  const sock = Object.assign(emitter, {
    write: vi.fn(),
    end: vi.fn((_cb?: () => void) => { if (typeof _cb === 'function') _cb(); }),
    destroy: vi.fn(),
    pipe: vi.fn(),
  }) as unknown as net.Socket;
  return sock;
}

function makeFakeNeovimClient(overrides: Partial<{
  executeLua: ReturnType<typeof vi.fn>;
  request: ReturnType<typeof vi.fn>;
  close: ReturnType<typeof vi.fn>;
}> = {}) {
  const emitter = new EventEmitter();
  return Object.assign(emitter, {
    executeLua: overrides.executeLua ?? vi.fn().mockResolvedValue(undefined),
    request: overrides.request ?? vi.fn().mockResolvedValue([1, {}]),
    close: overrides.close ?? vi.fn().mockResolvedValue(undefined),
    off: vi.fn((event: string, listener: (...args: any[]) => void) =>
      emitter.removeListener(event, listener),
    ),
  });
}

// Build a SocketTransport with injected fakes.
// connectImmediately: if true, the fake socket emits 'connect' via setImmediate.
function makeTransport(
  fakeSocket: net.Socket,
  fakeClient: ReturnType<typeof makeFakeNeovimClient>,
  connectImmediately = false,
): SocketTransport {
  if (connectImmediately) {
    setImmediate(() => (fakeSocket as unknown as EventEmitter).emit('connect'));
  }
  return new SocketTransport('/fake.sock', {
    socketFactory: () => fakeSocket,
    clientFactory: () => fakeClient as any,
  });
}

// Helper: wait one macrotask tick so queued microtasks/setImmediates have run.
const tick = () => new Promise<void>(r => setImmediate(r));

// ---------------------------------------------------------------------------
// discoverNvimSocket helpers
// ---------------------------------------------------------------------------

const sockFor = (pid: number) => `/tmp/nvim.${pid}/0`;

// ---------------------------------------------------------------------------
// SocketTransport.close — source-level check
// ---------------------------------------------------------------------------
describe('SocketTransport.close', () => {
  it('calls close() on the neovim client', async () => {
    const { readFileSync } = await vi.importActual<typeof import('node:fs')>('node:fs');
    const { resolve } = await import('node:path');
    const src = readFileSync(resolve(__dirname, '../src/transport.ts'), 'utf8');
    expect(src).toContain('.close()');
  });
});

// ---------------------------------------------------------------------------
// discoverNvimSocket
// ---------------------------------------------------------------------------
describe('discoverNvimSocket', () => {
  let killSpy: ReturnType<typeof vi.spyOn>;
  let cwdSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    vi.mocked(fs.existsSync).mockReturnValue(true as any);
    vi.mocked(fs.lstatSync).mockImplementation(() => { throw new Error('no proc'); });
    killSpy = vi.spyOn(process, 'kill').mockReturnValue(true as any);
    cwdSpy = vi.spyOn(process, 'cwd').mockReturnValue('/project/a');
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  function setupExecSync(
    pidCwds: Record<number, string>,
    gitRoots: Record<string, string>,
  ) {
    vi.mocked(childProcess.execSync).mockImplementation((cmd: any, opts?: any) => {
      const cmdStr = String(cmd);
      const lsofMatch = cmdStr.match(/lsof -a -p (\d+)/);
      if (lsofMatch) {
        const pid = parseInt(lsofMatch[1], 10);
        if (pid in pidCwds) return `n${pidCwds[pid]}\n` as any;
        throw new Error('unknown pid');
      }
      if (cmdStr.includes('git rev-parse --show-toplevel')) {
        const dir = (opts as { cwd?: string } | undefined)?.cwd ?? '';
        if (dir in gitRoots) return `${gitRoots[dir]}\n` as any;
        throw new Error('not a git repo');
      }
      throw new Error(`unexpected execSync call: ${cmdStr}`);
    });
  }

  it('returns error:none when no sockets exist', () => {
    vi.mocked(globSync).mockReturnValue([]);
    expect(discoverNvimSocket()).toMatchObject({ error: 'none' });
  });

  // Pass 1: error:none carries triedPatterns for descriptive error messages.
  it('returns error:none with triedPatterns when no sockets exist', () => {
    vi.mocked(globSync).mockReturnValue([]);
    const result = discoverNvimSocket();
    expect(result).toMatchObject({ error: 'none' });
    if ('triedPatterns' in result) {
      expect(result.triedPatterns.length).toBeGreaterThan(0);
      expect(result.triedPatterns[0]).toContain('/tmp/nvim');
    }
  });

  it('returns error:none when all PIDs are dead', () => {
    vi.mocked(globSync).mockReturnValue([sockFor(111)]);
    killSpy.mockImplementation(() => { throw new Error('no such process'); });
    expect(discoverNvimSocket()).toMatchObject({ error: 'none' });
  });

  it('returns the single candidate without needing a cwd match', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111)] : [],
    );
    vi.mocked(childProcess.execSync).mockImplementation(() => { throw new Error(); });
    expect(discoverNvimSocket()).toEqual({ path: sockFor(111) });
  });

  it('returns the single candidate even when not in a git repo', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111)] : [],
    );
    cwdSpy.mockReturnValue('/tmp/agent-workdir');
    vi.mocked(childProcess.execSync).mockImplementation(() => { throw new Error(); });
    expect(discoverNvimSocket()).toEqual({ path: sockFor(111) });
  });

  it('returns the candidate whose cwd exactly matches', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111), sockFor(222)] : [],
    );
    cwdSpy.mockReturnValue('/project/b');
    setupExecSync({ 111: '/project/a', 222: '/project/b' }, {});
    expect(discoverNvimSocket()).toEqual({ path: sockFor(222) });
  });

  it('returns the candidate whose cwd is a parent of the current directory', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111), sockFor(222)] : [],
    );
    cwdSpy.mockReturnValue('/project/a/subdir/deep');
    setupExecSync({ 111: '/project/a', 222: '/project/b' }, {});
    expect(discoverNvimSocket()).toEqual({ path: sockFor(111) });
  });

  it('falls back to git-root matching when Neovim was opened in a project subdirectory', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111), sockFor(222)] : [],
    );
    cwdSpy.mockReturnValue('/project/a');
    setupExecSync(
      { 111: '/project/a/src', 222: '/project/b' },
      {
        '/project/a': '/project/a',
        '/project/a/src': '/project/a',
        '/project/b': '/project/b',
      },
    );
    expect(discoverNvimSocket()).toEqual({ path: sockFor(111) });
  });

  it('returns error:ambiguous with multiple instances when not in a git repo', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111), sockFor(222)] : [],
    );
    cwdSpy.mockReturnValue('/tmp/agent-workdir');
    setupExecSync(
      { 111: '/project/a', 222: '/project/b' },
      { '/project/a': '/project/a', '/project/b': '/project/b' },
    );
    expect(discoverNvimSocket()).toMatchObject({ error: 'ambiguous' });
  });

  // Pass 1: error:ambiguous carries candidatePaths for descriptive error messages.
  it('returns error:ambiguous with candidatePaths listing all found sockets', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111), sockFor(222)] : [],
    );
    cwdSpy.mockReturnValue('/tmp/agent-workdir');
    setupExecSync(
      { 111: '/project/a', 222: '/project/b' },
      { '/project/a': '/project/a', '/project/b': '/project/b' },
    );
    const result = discoverNvimSocket();
    expect(result).toMatchObject({ error: 'ambiguous' });
    if ('candidatePaths' in result) {
      expect(result.candidatePaths).toContain(sockFor(111));
      expect(result.candidatePaths).toContain(sockFor(222));
    }
  });

  it('returns error:ambiguous when two instances share the same git root', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111), sockFor(222)] : [],
    );
    cwdSpy.mockReturnValue('/project/a/scripts');
    setupExecSync(
      { 111: '/project/a/src', 222: '/project/a/tests' },
      {
        '/project/a/scripts': '/project/a',
        '/project/a/src': '/project/a',
        '/project/a/tests': '/project/a',
      },
    );
    expect(discoverNvimSocket()).toMatchObject({ error: 'ambiguous' });
  });

  it('returns error:ambiguous when multiple instances exist and git roots differ', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111), sockFor(222)] : [],
    );
    cwdSpy.mockReturnValue('/project/c');
    setupExecSync(
      { 111: '/project/a', 222: '/project/b' },
      {
        '/project/c': '/project/c',
        '/project/a': '/project/a',
        '/project/b': '/project/b',
      },
    );
    expect(discoverNvimSocket()).toMatchObject({ error: 'ambiguous' });
  });

  // Issue 1: macOS glob pattern corrected to /var/folders/*/*/T/nvim.<pid>/0
  it('discovers macOS-style sockets from /var/folders/*/*/T/nvim.<pid>/0', () => {
    const macSock = '/var/folders/ab/xyz123/T/nvim.9999/0';
    vi.mocked(globSync).mockImplementation((p: any) => {
      const ps = String(p);
      if (ps.startsWith('/tmp')) return [];
      if (ps.startsWith('/var/folders')) return [macSock];
      return [];
    });
    vi.mocked(childProcess.execSync).mockImplementation(() => { throw new Error(); });
    expect(discoverNvimSocket()).toEqual({ path: macSock });
  });

  // Issue 2: non-numeric pid string skipped — process.kill never called with NaN
  it('skips sockets whose parent directory yields a non-numeric pid', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? ['/tmp/nvim.garbage/0'] : [],
    );
    expect(() => discoverNvimSocket()).not.toThrow();
    expect(killSpy).not.toHaveBeenCalled();
    expect(discoverNvimSocket()).toMatchObject({ error: 'none' });
  });
});

// ---------------------------------------------------------------------------
// SocketTransport.ensureConnected — Issue 3
// ---------------------------------------------------------------------------
describe('SocketTransport.ensureConnected', () => {
  afterEach(() => vi.restoreAllMocks());

  it('rejects executeLua immediately when the socket connection fails', async () => {
    const fakeSocket = makeFakeSocket();
    const fakeClient = makeFakeNeovimClient();
    const transport = makeTransport(fakeSocket, fakeClient);

    setImmediate(() =>
      (fakeSocket as unknown as EventEmitter).emit('error', new Error('ENOENT: no such file')),
    );

    await expect(transport.executeLua('return 1', [])).rejects.toThrow('ENOENT');
  });

  it('rejects executeLua after close() with "Transport is closed"', async () => {
    const fakeSocket = makeFakeSocket();
    const fakeClient = makeFakeNeovimClient();
    const transport = makeTransport(fakeSocket, fakeClient);

    await transport.close();

    await expect(transport.executeLua('return 1', [])).rejects.toThrow('Transport is closed');
  });

  it('allows executeLua after socket connects successfully', async () => {
    const fakeSocket = makeFakeSocket();
    const expectedResult = 'hello';
    const fakeClient = makeFakeNeovimClient({
      executeLua: vi.fn().mockResolvedValue(expectedResult),
    });
    const transport = makeTransport(fakeSocket, fakeClient, true);

    await expect(transport.executeLua('return "hello"', [])).resolves.toBe(expectedResult);
  });
});

// ---------------------------------------------------------------------------
// SocketTransport.close — pending request rejection — Issue 4
// ---------------------------------------------------------------------------
describe('SocketTransport.close — pending request rejection', () => {
  afterEach(() => vi.restoreAllMocks());

  it('rejects in-flight requests when close() is called', async () => {
    const fakeSocket = makeFakeSocket();
    const hangingLua: Promise<unknown> = new Promise(() => {}); // never resolves
    const fakeClient = makeFakeNeovimClient({
      executeLua: vi.fn().mockReturnValue(hangingLua),
    });
    const transport = makeTransport(fakeSocket, fakeClient, true);

    // Wait for the connect event to fire
    await new Promise(r => setImmediate(r));

    const pending = transport.executeLua('vim.wait(1e9)', []);
    await transport.close();

    await expect(pending).rejects.toThrow('Transport is closed');
  });

  it('is idempotent — calling close() twice does not throw', async () => {
    const fakeSocket = makeFakeSocket();
    const fakeClient = makeFakeNeovimClient();
    const transport = makeTransport(fakeSocket, fakeClient);

    await transport.close();
    await expect(transport.close()).resolves.toBeUndefined();
  });
});

// ---------------------------------------------------------------------------
// SocketTransport.getChannelId — validation — Issue 5
// ---------------------------------------------------------------------------
describe('SocketTransport.getChannelId — validation', () => {
  afterEach(() => vi.restoreAllMocks());

  it('throws when nvim_get_api_info returns a non-array', async () => {
    const fakeSocket = makeFakeSocket();
    const fakeClient = makeFakeNeovimClient({
      request: vi.fn().mockResolvedValue('not-an-array'),
    });
    const transport = makeTransport(fakeSocket, fakeClient, true);

    await expect(transport.getChannelId()).rejects.toThrow(
      'nvim_get_api_info returned unexpected value',
    );
  });

  it('throws when nvim_get_api_info returns an array without a numeric first element', async () => {
    const fakeSocket = makeFakeSocket();
    const fakeClient = makeFakeNeovimClient({
      request: vi.fn().mockResolvedValue(['not-a-number', {}]),
    });
    const transport = makeTransport(fakeSocket, fakeClient, true);

    await expect(transport.getChannelId()).rejects.toThrow(
      'nvim_get_api_info returned unexpected value',
    );
  });

  it('returns the channel id from a valid nvim_get_api_info response', async () => {
    const fakeSocket = makeFakeSocket();
    const fakeClient = makeFakeNeovimClient({
      request: vi.fn().mockResolvedValue([42, { version: {}, functions: [] }]),
    });
    const transport = makeTransport(fakeSocket, fakeClient, true);

    await expect(transport.getChannelId()).resolves.toBe(42);
  });

  // Pass 7: error message includes socket path for diagnostics.
  it('error message includes socket path', async () => {
    const fakeSocket = makeFakeSocket();
    const fakeClient = makeFakeNeovimClient({
      // Returns bad value after connect resolves
      request: vi.fn().mockResolvedValue('bad'),
    });
    const transport = new SocketTransport('/specific/path.sock', {
      socketFactory: () => fakeSocket,
      clientFactory: () => fakeClient as any,
      // Short timeout so test doesn't hang on default 30s
      requestTimeoutMs: 5000,
    });
    // Connect synchronously then wait for microtasks to process the connect event
    (fakeSocket as unknown as EventEmitter).emit('connect');
    await tick();

    await expect(transport.getChannelId()).rejects.toThrow('/specific/path.sock');
    await transport.close();
  });
});

// ---------------------------------------------------------------------------
// SocketTransport — mid-session socket death drains pending requests — Pass 3
// ---------------------------------------------------------------------------
describe('SocketTransport — mid-session socket death', () => {
  afterEach(() => vi.restoreAllMocks());

  it('rejects in-flight requests when the socket emits close after connect', async () => {
    const fakeSocket = makeFakeSocket();
    const hangingLua: Promise<unknown> = new Promise(() => {}); // never resolves
    const fakeClient = makeFakeNeovimClient({
      executeLua: vi.fn().mockReturnValue(hangingLua),
    });
    const transport = new SocketTransport('/fake.sock', {
      socketFactory: () => fakeSocket,
      clientFactory: () => fakeClient as any,
      requestTimeoutMs: 30_000,
    });
    // Connect then wait for microtasks (ensureConnected resolves after awaiting connectionReady).
    (fakeSocket as unknown as EventEmitter).emit('connect');
    await tick();

    const pending = transport.executeLua('vim.wait(1e9)', []);
    // Allow executeLua to reach trackRequest before we emit close
    await tick();

    // Simulate an unexpected socket close (no error).
    (fakeSocket as unknown as EventEmitter).emit('close', false);

    await expect(pending).rejects.toThrow('closed unexpectedly');
    await transport.close();
  });

  it('rejects in-flight requests when the socket emits an error after connect', async () => {
    const fakeSocket = makeFakeSocket();
    const hangingLua: Promise<unknown> = new Promise(() => {});
    const fakeClient = makeFakeNeovimClient({
      executeLua: vi.fn().mockReturnValue(hangingLua),
    });
    const transport = new SocketTransport('/fake.sock', {
      socketFactory: () => fakeSocket,
      clientFactory: () => fakeClient as any,
      requestTimeoutMs: 30_000,
    });
    (fakeSocket as unknown as EventEmitter).emit('connect');
    await tick();

    const pending = transport.executeLua('vim.wait(1e9)', []);
    await tick();

    // Simulate a mid-session socket error.
    (fakeSocket as unknown as EventEmitter).emit('error', new Error('ECONNRESET'));

    await expect(pending).rejects.toThrow('ECONNRESET');
    await transport.close();
  });
});

// ---------------------------------------------------------------------------
// SocketTransport — request timeout — Pass 2
// ---------------------------------------------------------------------------
describe('SocketTransport — request timeout', () => {
  afterEach(() => vi.restoreAllMocks());

  it('DEFAULT_REQUEST_TIMEOUT_MS is 30000', () => {
    expect(DEFAULT_REQUEST_TIMEOUT_MS).toBe(30_000);
  });

  it('rejects a hanging request after the configured timeout', async () => {
    const fakeSocket = makeFakeSocket();
    const hangingLua: Promise<unknown> = new Promise(() => {}); // never resolves
    const fakeClient = makeFakeNeovimClient({
      executeLua: vi.fn().mockReturnValue(hangingLua),
    });
    // Use a very short 50ms timeout so the test runs fast without fake timers.
    const transport = new SocketTransport('/fake.sock', {
      socketFactory: () => fakeSocket,
      clientFactory: () => fakeClient as any,
      requestTimeoutMs: 50,
    });
    // Emit connect and wait for ensureConnected to resolve.
    (fakeSocket as unknown as EventEmitter).emit('connect');
    await tick();

    const pending = transport.executeLua('vim.wait(1e9)', []);

    await expect(pending).rejects.toThrow('timed out after 50ms');
    await transport.close();
  });

  it('does not fire timeout after close() cancels pending requests', async () => {
    const fakeSocket = makeFakeSocket();
    const hangingLua: Promise<unknown> = new Promise(() => {});
    const fakeClient = makeFakeNeovimClient({
      executeLua: vi.fn().mockReturnValue(hangingLua),
    });
    const transport = new SocketTransport('/fake.sock', {
      socketFactory: () => fakeSocket,
      clientFactory: () => fakeClient as any,
      requestTimeoutMs: 5000,
    });
    (fakeSocket as unknown as EventEmitter).emit('connect');
    await tick();

    const pending = transport.executeLua('vim.wait(1e9)', []);
    // close() before timeout fires
    await transport.close();

    await expect(pending).rejects.toThrow('Transport is closed');
  });

  it('timeout message includes the socket path', async () => {
    const fakeSocket = makeFakeSocket();
    const hangingLua: Promise<unknown> = new Promise(() => {});
    const fakeClient = makeFakeNeovimClient({
      executeLua: vi.fn().mockReturnValue(hangingLua),
    });
    const transport = new SocketTransport('/special/socket.sock', {
      socketFactory: () => fakeSocket,
      clientFactory: () => fakeClient as any,
      requestTimeoutMs: 50,
    });
    (fakeSocket as unknown as EventEmitter).emit('connect');
    await tick();

    const pending = transport.executeLua('vim.wait(1e9)', []);
    await expect(pending).rejects.toThrow('/special/socket.sock');
    await transport.close();
  });
});

// ---------------------------------------------------------------------------
// FakeTransport — lifecycle and interface coverage — Passes 4/6/9/10
// ---------------------------------------------------------------------------
describe('FakeTransport — lifecycle and interface', () => {
  it('tracks isClosed after close()', async () => {
    const { FakeTransport } = await import('./fake_transport');
    const t = new FakeTransport();
    expect(t.isClosed).toBe(false);
    await t.close();
    expect(t.isClosed).toBe(true);
  });

  it('increments closeCallCount on each call to close()', async () => {
    const { FakeTransport } = await import('./fake_transport');
    const t = new FakeTransport();
    await t.close();
    await t.close();
    expect(t.closeCallCount).toBe(2);
  });

  it('returns responses[method] when set', async () => {
    const { FakeTransport } = await import('./fake_transport');
    const t = new FakeTransport();
    t.responses['my.method'] = { value: 42 };
    const result = await t.executeLua('...', ['my.method']);
    expect(result).toEqual({ value: 42 });
  });

  it('returns { ok: true } as default when no response is set', async () => {
    const { FakeTransport } = await import('./fake_transport');
    const t = new FakeTransport();
    const result = await t.executeLua('...', ['unknown.method']);
    expect(result).toEqual({ ok: true });
  });

  // Pass 10: Error injection
  it('throws executeLuaError on the next call and clears it afterwards', async () => {
    const { FakeTransport } = await import('./fake_transport');
    const t = new FakeTransport();
    t.executeLuaError = new Error('injected failure');
    await expect(t.executeLua('...', ['foo'])).rejects.toThrow('injected failure');
    // Subsequent call succeeds — error was cleared.
    await expect(t.executeLua('...', ['foo'])).resolves.toEqual({ ok: true });
  });

  it('records all calls in order', async () => {
    const { FakeTransport } = await import('./fake_transport');
    const t = new FakeTransport();
    await t.executeLua('code-a', ['method-a']);
    await t.executeLua('code-b', ['method-b']);
    expect(t.calls).toHaveLength(2);
    expect(t.calls[0]).toEqual({ code: 'code-a', args: ['method-a'] });
    expect(t.calls[1]).toEqual({ code: 'code-b', args: ['method-b'] });
  });

  it('getChannelId returns 42', async () => {
    const { FakeTransport } = await import('./fake_transport');
    const t = new FakeTransport();
    await expect(t.getChannelId()).resolves.toBe(42);
  });

  // Pass 6: Connection lifecycle — notification subscribe and fire
  it('fireNotification delivers to all registered handlers for the event', async () => {
    const { FakeTransport } = await import('./fake_transport');
    const t = new FakeTransport();
    const received: unknown[][] = [];
    t.onNotification('my:event', args => received.push(args));
    t.onNotification('my:event', args => received.push(args));
    t.fireNotification('my:event', [1, 2, 3]);
    expect(received).toHaveLength(2);
    expect(received[0]).toEqual([1, 2, 3]);
  });

  it('fireNotification is a no-op for unregistered events', async () => {
    const { FakeTransport } = await import('./fake_transport');
    const t = new FakeTransport();
    expect(() => t.fireNotification('no:subscribers', [])).not.toThrow();
  });
});

// ---------------------------------------------------------------------------
// SocketTransport — connection lifecycle (connect/disconnect) — Pass 6
// ---------------------------------------------------------------------------
describe('SocketTransport — connection lifecycle', () => {
  afterEach(() => vi.restoreAllMocks());

  it('can close immediately without ever connecting', async () => {
    const fakeSocket = makeFakeSocket();
    const fakeClient = makeFakeNeovimClient();
    const transport = new SocketTransport('/fake.sock', {
      socketFactory: () => fakeSocket,
      clientFactory: () => fakeClient as any,
    });
    // Never emit 'connect'; close should still resolve without hanging.
    await expect(transport.close()).resolves.toBeUndefined();
  });

  it('allows onNotification to be registered before connect', async () => {
    const fakeSocket = makeFakeSocket();
    const fakeClient = makeFakeNeovimClient();
    const transport = new SocketTransport('/fake.sock', {
      socketFactory: () => fakeSocket,
      clientFactory: () => fakeClient as any,
    });
    const received: unknown[][] = [];
    transport.onNotification('neph:test', args => received.push(args));
    // Fire the notification via the fake client emitter.
    (fakeClient as unknown as EventEmitter).emit('notification', 'neph:test', ['payload']);
    expect(received).toHaveLength(1);
    await transport.close();
  });

  it('rejects all callers waiting for connect when close() is called first', async () => {
    const fakeSocket = makeFakeSocket();
    const fakeClient = makeFakeNeovimClient();
    const transport = new SocketTransport('/fake.sock', {
      socketFactory: () => fakeSocket,
      clientFactory: () => fakeClient as any,
    });
    // Start executeLua before socket connects — it will block in ensureConnected.
    const blocked = transport.executeLua('return 1', []);
    // close() before socket ever connects.
    await transport.close();
    await expect(blocked).rejects.toThrow('Transport is closed');
  });
});
