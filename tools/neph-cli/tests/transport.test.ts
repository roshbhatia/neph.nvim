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
import { discoverNvimSocket, SocketTransport } from '../src/transport';
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

  it('returns null when no sockets exist', () => {
    vi.mocked(globSync).mockReturnValue([]);
    expect(discoverNvimSocket()).toBeNull();
  });

  it('returns null when all PIDs are dead', () => {
    vi.mocked(globSync).mockReturnValue([sockFor(111)]);
    killSpy.mockImplementation(() => { throw new Error('no such process'); });
    expect(discoverNvimSocket()).toBeNull();
  });

  it('returns the single candidate without needing a cwd match', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111)] : [],
    );
    vi.mocked(childProcess.execSync).mockImplementation(() => { throw new Error(); });
    expect(discoverNvimSocket()).toBe(sockFor(111));
  });

  it('returns the single candidate even when not in a git repo', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111)] : [],
    );
    cwdSpy.mockReturnValue('/tmp/agent-workdir');
    vi.mocked(childProcess.execSync).mockImplementation(() => { throw new Error(); });
    expect(discoverNvimSocket()).toBe(sockFor(111));
  });

  it('returns the candidate whose cwd exactly matches', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111), sockFor(222)] : [],
    );
    cwdSpy.mockReturnValue('/project/b');
    setupExecSync({ 111: '/project/a', 222: '/project/b' }, {});
    expect(discoverNvimSocket()).toBe(sockFor(222));
  });

  it('returns the candidate whose cwd is a parent of the current directory', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111), sockFor(222)] : [],
    );
    cwdSpy.mockReturnValue('/project/a/subdir/deep');
    setupExecSync({ 111: '/project/a', 222: '/project/b' }, {});
    expect(discoverNvimSocket()).toBe(sockFor(111));
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
    expect(discoverNvimSocket()).toBe(sockFor(111));
  });

  it('returns null with multiple instances when not in a git repo', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? [sockFor(111), sockFor(222)] : [],
    );
    cwdSpy.mockReturnValue('/tmp/agent-workdir');
    setupExecSync(
      { 111: '/project/a', 222: '/project/b' },
      { '/project/a': '/project/a', '/project/b': '/project/b' },
    );
    expect(discoverNvimSocket()).toBeNull();
  });

  it('returns null when two instances share the same git root (ambiguous)', () => {
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
    expect(discoverNvimSocket()).toBeNull();
  });

  it('returns null when multiple instances exist and git roots differ', () => {
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
    expect(discoverNvimSocket()).toBeNull();
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
    expect(discoverNvimSocket()).toBe(macSock);
  });

  // Issue 2: non-numeric pid string skipped — process.kill never called with NaN
  it('skips sockets whose parent directory yields a non-numeric pid', () => {
    vi.mocked(globSync).mockImplementation((p: any) =>
      String(p).startsWith('/tmp') ? ['/tmp/nvim.garbage/0'] : [],
    );
    expect(() => discoverNvimSocket()).not.toThrow();
    expect(killSpy).not.toHaveBeenCalled();
    expect(discoverNvimSocket()).toBeNull();
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
});
