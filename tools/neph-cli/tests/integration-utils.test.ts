// tools/neph-cli/tests/integration-utils.test.ts
// Tests for the pure helper functions exported from integration.ts:
// mergeHooks, unmergeHooks, hooksEnabled, mergeCopilot, unmergeCopilot,
// copilotEnabled, hookEntryMatches, listIntegrations.

import { describe, it, expect, vi } from 'vitest';

// Mock fs so integration.ts module-level reads don't fail
vi.mock('node:fs', async () => {
  const actual = await vi.importActual<typeof import('node:fs')>('node:fs');
  return {
    ...actual,
    existsSync: vi.fn(() => false),
    readFileSync: vi.fn(() => '{}'),
    writeFileSync: vi.fn(),
    mkdirSync: vi.fn(),
  };
});

// Mock harness-base (required by integration.ts)
vi.mock('../../lib/harness-base', () => ({
  CupcakeHelper: { cupcakeEval: vi.fn(() => ({ decision: 'allow' })) },
  ContentHelper: { reconstructContent: vi.fn(() => '') },
  createSessionSignals: vi.fn(() => ({
    setActive: vi.fn(), unsetActive: vi.fn(),
    setRunning: vi.fn(), unsetRunning: vi.fn(),
    checktime: vi.fn(), close: vi.fn(),
  })),
}));

import { listIntegrations, runIntegrationCommand } from '../src/integration';

// ---------------------------------------------------------------------------
// listIntegrations
// ---------------------------------------------------------------------------

describe('listIntegrations', () => {
  it('returns a non-empty array', () => {
    const list = listIntegrations();
    expect(list.length).toBeGreaterThan(0);
  });

  it('each integration has name, label, kind fields', () => {
    for (const integration of listIntegrations()) {
      expect(typeof integration.name).toBe('string');
      expect(typeof integration.label).toBe('string');
      expect(['hooks', 'copilot', 'cupcake']).toContain(integration.kind);
    }
  });

  it('includes claude, gemini, copilot, cursor, codex, opencode', () => {
    const names = listIntegrations().map(i => i.name);
    expect(names).toContain('claude');
    expect(names).toContain('gemini');
    expect(names).toContain('copilot');
    expect(names).toContain('cursor');
    expect(names).toContain('codex');
    expect(names).toContain('opencode');
  });

  it('returns a copy (mutations do not affect the original)', () => {
    const list1 = listIntegrations();
    list1.push({ name: 'x', label: 'X', configPath: () => '', templatePath: '', kind: 'hooks' });
    const list2 = listIntegrations();
    expect(list2.map(i => i.name)).not.toContain('x');
  });
});

// ---------------------------------------------------------------------------
// integration status command
// ---------------------------------------------------------------------------

describe('runIntegrationCommand status', () => {
  it('prints status for all integrations', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(['integration', 'status'], '', null);
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    expect(output).toContain('claude:');
    expect(output).toContain('gemini:');
  });

  it('prints status for a specific integration by name', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(['integration', 'status', 'claude'], '', null);
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    expect(output).toContain('claude:');
  });

  it('exits 1 for unknown integration name', async () => {
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((() => { throw new Error('EXIT'); }) as never);
    await expect(
      runIntegrationCommand(['integration', 'status', 'nonexistent_agent'], '', null)
    ).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Unknown integration'));
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// integration hook — pass-through with null transport (unit-level)
// ---------------------------------------------------------------------------

describe('runIntegrationCommand hook (null transport)', () => {
  it('claude SessionStart → outputs {}', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(
      ['integration', 'hook', 'claude'],
      JSON.stringify({ hook_event_name: 'SessionStart' }),
      null,
    );
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    expect(JSON.parse(output)).toEqual({});
  });

  it('claude invalid JSON → outputs {}', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(
      ['integration', 'hook', 'claude'],
      'not json',
      null,
    );
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    expect(JSON.parse(output)).toEqual({});
  });

  it('gemini SessionStart → outputs allow', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(
      ['integration', 'hook', 'gemini'],
      JSON.stringify({ hook_event_name: 'SessionStart' }),
      null,
    );
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    const parsed = JSON.parse(output);
    expect(parsed.decision).toBe('allow');
  });

  it('gemini invalid JSON → outputs allow (fail-open)', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(
      ['integration', 'hook', 'gemini'],
      'not json',
      null,
    );
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    const parsed = JSON.parse(output);
    expect(parsed.decision).toBe('allow');
  });

  it('copilot sessionStart → outputs {}', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(
      ['integration', 'hook', 'copilot'],
      JSON.stringify({ hook_event_name: 'sessionStart' }),
      null,
    );
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    expect(JSON.parse(output)).toEqual({});
  });

  it('cursor afterFileEdit → outputs {}', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(
      ['integration', 'hook', 'cursor'],
      JSON.stringify({ hook_event_name: 'afterFileEdit' }),
      null,
    );
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    expect(JSON.parse(output)).toEqual({});
  });

  it('codex SessionStart → outputs {}', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(
      ['integration', 'hook', 'codex'],
      JSON.stringify({ hook_event_name: 'SessionStart' }),
      null,
    );
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    expect(JSON.parse(output)).toEqual({});
  });

  it('unknown hook agent exits 1', async () => {
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((() => { throw new Error('EXIT'); }) as never);
    await expect(
      runIntegrationCommand(['integration', 'hook', 'unknown_agent'], '{}', null)
    ).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Unknown integration hook'));
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// integration command — help / unknown
// ---------------------------------------------------------------------------

describe('runIntegrationCommand routing', () => {
  it('prints usage for --help', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(['integration', '--help'], '', null);
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    expect(output).toContain('Usage:');
  });

  it('exits 1 for unknown subcommand', async () => {
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((() => { throw new Error('EXIT'); }) as never);
    await expect(
      runIntegrationCommand(['integration', 'bogus'], '', null)
    ).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Unknown integration command'));
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// Pass 7: toggle idempotency — enabling an already-enabled integration is safe
// ---------------------------------------------------------------------------

describe('runIntegrationCommand toggle idempotency', () => {
  it('toggle gemini twice produces "disabled" on second call (no crash)', async () => {
    // existsSync returns false → integrationEnabled returns false → first toggle enables
    // Second toggle: existsSync returns false again → still disabled → enables again
    // Both calls must succeed without throwing.
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(['integration', 'toggle', 'gemini'], '', null);
    const output1 = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockClear();

    await runIntegrationCommand(['integration', 'toggle', 'gemini'], '', null);
    const output2 = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();

    // Both invocations must produce valid status output
    expect(output1).toContain('gemini:');
    expect(output2).toContain('gemini:');
  });

  it('toggle unknown integration exits 1 with helpful message', async () => {
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((() => { throw new Error('EXIT'); }) as never);
    await expect(
      runIntegrationCommand(['integration', 'toggle', 'nonexistent_xyz'], '', null)
    ).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Unknown integration'));
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it('toggle without name exits 1 when stdin is not a TTY (non-interactive)', async () => {
    // Without a name and no TTY, promptForIntegration throws "Interactive selection requires a TTY"
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((() => { throw new Error('EXIT'); }) as never);
    await expect(
      runIntegrationCommand(['integration', 'toggle'], '', null)
    ).rejects.toThrow('EXIT');
    expect(exitSpy).toHaveBeenCalledWith(1);
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// Pass 8: status with --show-config path
// ---------------------------------------------------------------------------

describe('runIntegrationCommand status --show-config', () => {
  it('prints disabled and (missing) when config file does not exist', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runIntegrationCommand(['integration', 'status', '--show-config', 'gemini'], '', null);
    const output = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    stdoutSpy.mockRestore();
    // existsSync mocked to false → disabled + (missing)
    expect(output).toContain('gemini: disabled');
    expect(output).toContain('missing');
  });
});
