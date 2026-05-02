import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';
import { runContextCommand } from '../src/context';

// `neph context current` reads `${XDG_STATE_HOME}/nvim/neph/context.json`
// (or `~/.local/state/nvim/neph/context.json`). The tests redirect XDG_STATE_HOME
// to a fresh tmp dir so they don't see real Neovim state.
function withTempState<T>(fn: (dir: string, target: string) => T): T {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'neph-ctx-'));
  const target = path.join(dir, 'nvim', 'neph', 'context.json');
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const orig = process.env.XDG_STATE_HOME;
  process.env.XDG_STATE_HOME = dir;
  try {
    return fn(dir, target);
  } finally {
    if (orig === undefined) {
      delete process.env.XDG_STATE_HOME;
    } else {
      process.env.XDG_STATE_HOME = orig;
    }
    fs.rmSync(dir, { recursive: true, force: true });
  }
}

function nowMs(): number {
  return Number(process.hrtime.bigint() / 1_000_000n);
}

describe('neph context current', () => {
  let stdoutSpy: ReturnType<typeof vi.spyOn>;
  let stderrSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    exitSpy = vi.spyOn(process, 'exit').mockImplementation(((code?: number) => {
      throw new Error(`__EXIT__:${code ?? 0}`);
    }) as never);
  });

  afterEach(() => {
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it('prints the JSON snapshot when fresh', async () => {
    await withTempState(async (_dir, target) => {
      const payload = { ts: nowMs(), cwd: '/tmp', visible: [], diagnostics: {} };
      fs.writeFileSync(target, JSON.stringify(payload));
      await runContextCommand(['current']);
      expect(stdoutSpy).toHaveBeenCalled();
      const printed = stdoutSpy.mock.calls.map((c) => String(c[0])).join('');
      expect(JSON.parse(printed.trim())).toMatchObject({ cwd: '/tmp' });
    });
  });

  it('errors with no_snapshot when the file is missing', async () => {
    await withTempState(async () => {
      let code: number | undefined;
      try {
        await runContextCommand(['current']);
      } catch (e) {
        code = Number(String((e as Error).message).split(':')[1]);
      }
      expect(code).not.toBe(0);
      const printed = stderrSpy.mock.calls.map((c) => String(c[0])).join('');
      expect(printed).toContain('no_snapshot');
    });
  });

  it('errors with stale_snapshot when ts is older than the threshold', async () => {
    await withTempState(async (_dir, target) => {
      const stale = { ts: nowMs() - 60_000, cwd: '/tmp', visible: [], diagnostics: {} };
      fs.writeFileSync(target, JSON.stringify(stale));
      let code: number | undefined;
      try {
        await runContextCommand(['current', '--max-age-ms', '5000']);
      } catch (e) {
        code = Number(String((e as Error).message).split(':')[1]);
      }
      expect(code).not.toBe(0);
      const printed = stderrSpy.mock.calls.map((c) => String(c[0])).join('');
      expect(printed).toContain('stale_snapshot');
    });
  });

  it('--max-age-ms overrides the staleness threshold', async () => {
    await withTempState(async (_dir, target) => {
      // 30s old, with a generous --max-age-ms it should print fine.
      const old = { ts: nowMs() - 30_000, cwd: '/tmp', visible: [], diagnostics: {} };
      fs.writeFileSync(target, JSON.stringify(old));
      await runContextCommand(['current', '--max-age-ms', '60000']);
      expect(stdoutSpy).toHaveBeenCalled();
    });
  });

  it('--field extracts a single key path as plain text', async () => {
    await withTempState(async (_dir, target) => {
      const payload = {
        ts: nowMs(),
        cwd: '/tmp',
        visible: [],
        diagnostics: {},
        buffer: { uri: 'file:///foo.lua' },
      };
      fs.writeFileSync(target, JSON.stringify(payload));
      await runContextCommand(['current', '--field', 'buffer.uri']);
      const printed = stdoutSpy.mock.calls.map((c) => String(c[0])).join('');
      expect(printed.trim()).toBe('file:///foo.lua');
    });
  });

  it('rejects unknown subcommand', async () => {
    let code: number | undefined;
    try {
      await runContextCommand(['nonsense']);
    } catch (e) {
      code = Number(String((e as Error).message).split(':')[1]);
    }
    expect(code).not.toBe(0);
    const printed = stderrSpy.mock.calls.map((c) => String(c[0])).join('');
    expect(printed.toLowerCase()).toContain('usage');
  });
});
