import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// Must be hoisted before the module under test is imported.
vi.mock('glob', () => ({ globSync: vi.fn(() => []) }));
vi.mock('node:fs');
vi.mock('node:child_process');

import * as fs from 'node:fs';
import * as childProcess from 'node:child_process';
import { globSync } from 'glob';
import { discoverNvimSocket } from '../src/transport';

// Helper: make a socket path that encodes pid using the Linux /tmp/nvim.<pid>/0 pattern.
const sockFor = (pid: number) => `/tmp/nvim.${pid}/0`;

describe('SocketTransport.close', () => {
  it('calls close() on the neovim client', async () => {
    const { readFileSync } = await vi.importActual<typeof import('node:fs')>('node:fs');
    const { resolve } = await import('node:path');
    const src = readFileSync(resolve(__dirname, '../src/transport.ts'), 'utf8');
    expect(src).toContain('.close()');
  });
});

describe('discoverNvimSocket', () => {
  let killSpy: ReturnType<typeof vi.spyOn>;
  let cwdSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    // Every socket file "exists".
    vi.mocked(fs.existsSync).mockReturnValue(true as any);
    // /proc/<pid>/cwd doesn't exist on macOS CI; throw so we fall through to lsof.
    vi.mocked(fs.lstatSync).mockImplementation(() => { throw new Error('no proc'); });
    // All PIDs are alive by default.
    killSpy = vi.spyOn(process, 'kill').mockReturnValue(true as any);
    cwdSpy = vi.spyOn(process, 'cwd').mockReturnValue('/project/a');
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  // Make execSync return lsof output for a given pid→cwd mapping, and
  // git-rev-parse output for a given dir→root mapping.
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
    // lsof and git both fail — no cwd info — but there is only one Neovim
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
    // CLI is at the project root; Neovim was opened inside src/ —
    // cwd prefix check fails in both directions, so git root is the tie-breaker.
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
      // CLI cwd is not in the gitRoots map → git rev-parse throws → no match
      { '/project/a': '/project/a', '/project/b': '/project/b' },
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
});
