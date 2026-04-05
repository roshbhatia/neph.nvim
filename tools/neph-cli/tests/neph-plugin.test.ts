// tools/neph-cli/tests/neph-plugin.test.ts
// Unit tests for tools/amp/neph-plugin.ts covering session handlers,
// tool.call branches, and error paths.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ---------------------------------------------------------------------------
// Hoist mocks before the module under test is imported.
// ---------------------------------------------------------------------------

vi.mock('../../lib/log', () => ({ debug: vi.fn() }));
vi.mock('node:fs', () => ({ readFileSync: vi.fn() }));

// Control all neph-run exports via a single shared spy object so individual
// tests can override resolved values without re-importing the module.
const mockReview = vi.fn();
const mockUiSelect = vi.fn();
const mockUiInput = vi.fn();
const mockUiNotify = vi.fn();
const mockCreatePersistentQueue = vi.fn();

vi.mock('../../lib/neph-run', () => ({
  review: (...args: unknown[]) => mockReview(...args),
  uiSelect: (...args: unknown[]) => mockUiSelect(...args),
  uiInput: (...args: unknown[]) => mockUiInput(...args),
  uiNotify: (...args: unknown[]) => mockUiNotify(...args),
  createPersistentQueue: (...args: unknown[]) => mockCreatePersistentQueue(...args),
}));

import { readFileSync } from 'node:fs';
import nephPluginDefault from '../../amp/neph-plugin';

// ---------------------------------------------------------------------------
// Fake amp event bus
// ---------------------------------------------------------------------------

type Handler = (...args: unknown[]) => unknown;

function makeAmp() {
  const handlers: Record<string, Handler[]> = {};
  const ui: Record<string, unknown> = {};
  return {
    handlers,
    ui,
    on(event: string, handler: Handler) {
      if (!handlers[event]) handlers[event] = [];
      handlers[event].push(handler);
    },
    async emit(event: string, ...args: unknown[]) {
      for (const h of handlers[event] ?? []) {
        await h(...args);
      }
    },
  };
}

// ---------------------------------------------------------------------------
// Fake persistent queue
// ---------------------------------------------------------------------------

function makeFakePQ() {
  return {
    call: vi.fn(),
    close: vi.fn(),
  };
}

// ---------------------------------------------------------------------------
// Setup
// ---------------------------------------------------------------------------

beforeEach(() => {
  vi.clearAllMocks();

  // Default: createPersistentQueue returns a fresh fake PQ each call
  mockCreatePersistentQueue.mockImplementation(() => makeFakePQ());

  // Default: review resolves accept
  mockReview.mockResolvedValue({
    schema: 'review/v1',
    decision: 'accept',
    content: 'hello world',
    hunks: [],
  });

  // Default: readFileSync returns a placeholder
  vi.mocked(readFileSync).mockReturnValue('existing content' as any);
});

afterEach(() => {
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// session.start — amp.ui wiring
// ---------------------------------------------------------------------------

describe('session.start', () => {
  it('wires amp.ui.notify to uiNotify', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);
    await amp.emit('session.start');

    (amp.ui as any).notify('hello', 'info');
    expect(mockUiNotify).toHaveBeenCalledWith('hello', 'info');
  });

  it('wires amp.ui.confirm — Yes resolves true', async () => {
    mockUiSelect.mockResolvedValue('Yes');
    const amp = makeAmp();
    nephPluginDefault(amp);
    await amp.emit('session.start');

    const result = await (amp.ui as any).confirm('Confirm?', 'Are you sure?');
    expect(result).toBe(true);
    expect(mockUiSelect).toHaveBeenCalledWith(expect.stringContaining('Confirm?'), ['Yes', 'No']);
  });

  it('wires amp.ui.confirm — No resolves false', async () => {
    mockUiSelect.mockResolvedValue('No');
    const amp = makeAmp();
    nephPluginDefault(amp);
    await amp.emit('session.start');

    const result = await (amp.ui as any).confirm('Title', 'Msg');
    expect(result).toBe(false);
  });

  it('wires amp.ui.input to uiInput', async () => {
    mockUiInput.mockResolvedValue('typed value');
    const amp = makeAmp();
    nephPluginDefault(amp);
    await amp.emit('session.start');

    const result = await (amp.ui as any).input('Enter name', 'placeholder');
    expect(result).toBe('typed value');
    expect(mockUiInput).toHaveBeenCalledWith('Enter name', 'placeholder');
  });

  it('wires amp.ui.input — undefined from uiInput returns empty string', async () => {
    mockUiInput.mockResolvedValue(undefined);
    const amp = makeAmp();
    nephPluginDefault(amp);
    await amp.emit('session.start');

    const result = await (amp.ui as any).input('Prompt');
    expect(result).toBe('');
  });
});

// ---------------------------------------------------------------------------
// session.end — queue teardown and recreation
// ---------------------------------------------------------------------------

describe('session.end', () => {
  it('closes the persistent queue on session.end', async () => {
    const pq = makeFakePQ();
    mockCreatePersistentQueue.mockReturnValueOnce(pq);

    const amp = makeAmp();
    nephPluginDefault(amp);

    await amp.emit('session.end');
    expect(pq.close).toHaveBeenCalledOnce();
  });

  it('creates a fresh queue after session.end so session restart works', async () => {
    const pq1 = makeFakePQ();
    const pq2 = makeFakePQ();
    mockCreatePersistentQueue
      .mockReturnValueOnce(pq1)  // initial queue on plugin load
      .mockReturnValueOnce(pq2); // replacement after session.end

    const amp = makeAmp();
    nephPluginDefault(amp);

    await amp.emit('session.end');
    // Two calls: one at plugin init, one at session.end
    expect(mockCreatePersistentQueue).toHaveBeenCalledTimes(2);

    // The new queue receives subsequent agent.start calls
    await amp.emit('agent.start');
    expect(pq2.call).toHaveBeenCalledWith('set', 'amp_running', 'true');
  });
});

// ---------------------------------------------------------------------------
// agent.start / agent.end
// ---------------------------------------------------------------------------

describe('agent.start', () => {
  it('calls pq.call("set", "amp_running", "true")', async () => {
    const pq = makeFakePQ();
    mockCreatePersistentQueue.mockReturnValueOnce(pq);

    const amp = makeAmp();
    nephPluginDefault(amp);
    await amp.emit('agent.start');

    expect(pq.call).toHaveBeenCalledWith('set', 'amp_running', 'true');
  });
});

describe('agent.end', () => {
  it('calls pq.call("unset", "amp_running") and pq.call("checktime")', async () => {
    const pq = makeFakePQ();
    mockCreatePersistentQueue.mockReturnValueOnce(pq);

    const amp = makeAmp();
    nephPluginDefault(amp);
    await amp.emit('agent.end');

    expect(pq.call).toHaveBeenCalledWith('unset', 'amp_running');
    expect(pq.call).toHaveBeenCalledWith('checktime');
    expect(pq.call).toHaveBeenCalledTimes(2);
  });
});

// ---------------------------------------------------------------------------
// tool.call — allowed (non-write) tools pass through
// ---------------------------------------------------------------------------

describe('tool.call — non-write tools', () => {
  it('returns allow for run_bash', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);

    const result = await amp.emit('tool.call', { tool: 'run_bash', input: {} }, {});
    expect(result).toBe(undefined); // emit returns last handler result; confirm no rejection
    // More precisely: handler should have returned { action: 'allow' }
    // We must call the handler directly for the return value
    const handler = amp.handlers['tool.call'][0];
    const rv = await handler({ tool: 'run_bash', input: {} }, {});
    expect(rv).toEqual({ action: 'allow' });
  });

  it('returns allow for edit_file with no filePath', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);

    const handler = amp.handlers['tool.call'][0];
    const rv = await handler({ tool: 'edit_file', input: {} }, {});
    expect(rv).toEqual({ action: 'allow' });
    expect(mockReview).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// tool.call — create_file
// ---------------------------------------------------------------------------

describe('tool.call — create_file', () => {
  it('passes content directly to review and allows on accept', async () => {
    mockReview.mockResolvedValue({ schema: 'review/v1', decision: 'accept', content: 'new', hunks: [] });

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    const rv = await handler({
      tool: 'create_file',
      input: { file_path: '/tmp/newfile.lua', content: 'new' },
    }, {});

    expect(mockReview).toHaveBeenCalledWith('/tmp/newfile.lua', 'new', 'amp');
    expect(rv).toEqual({ action: 'allow' });
  });

  it('rejects when review returns reject decision', async () => {
    mockReview.mockResolvedValue({
      schema: 'review/v1',
      decision: 'reject',
      content: '',
      hunks: [],
      reason: 'Not allowed',
    });

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    const rv = await handler({
      tool: 'create_file',
      input: { file_path: '/tmp/newfile.lua', content: 'evil' },
    }, {}) as any;

    expect(rv.action).toBe('reject-and-continue');
    expect(rv.message).toContain('Not allowed');
  });

  it('uses empty string content when input.content is missing', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({ tool: 'create_file', input: { file_path: '/tmp/x.lua' } }, {});
    expect(mockReview).toHaveBeenCalledWith('/tmp/x.lua', '', 'amp');
  });
});

// ---------------------------------------------------------------------------
// tool.call — edit_file
// ---------------------------------------------------------------------------

describe('tool.call — edit_file', () => {
  it('applies old_string/new_string replacement against current file content', async () => {
    vi.mocked(readFileSync).mockReturnValue('hello world' as any);

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({
      tool: 'edit_file',
      input: {
        file_path: '/tmp/edit.lua',
        old_string: 'hello',
        new_string: 'goodbye',
      },
    }, {});

    expect(mockReview).toHaveBeenCalledWith('/tmp/edit.lua', 'goodbye world', 'amp');
  });

  it('falls back to input.content when readFileSync throws', async () => {
    vi.mocked(readFileSync).mockImplementation(() => { throw new Error('ENOENT'); });

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({
      tool: 'edit_file',
      input: { file_path: '/tmp/missing.lua', content: 'fallback content' },
    }, {});

    expect(mockReview).toHaveBeenCalledWith('/tmp/missing.lua', 'fallback content', 'amp');
  });

  it('uses current file content when no old/new strings and no content override', async () => {
    vi.mocked(readFileSync).mockReturnValue('original' as any);

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({
      tool: 'edit_file',
      input: { file_path: '/tmp/noreplace.lua' },
    }, {});

    expect(mockReview).toHaveBeenCalledWith('/tmp/noreplace.lua', 'original', 'amp');
  });

  it('supports old_str/new_str aliases', async () => {
    vi.mocked(readFileSync).mockReturnValue('alpha beta' as any);

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({
      tool: 'edit_file',
      input: { file_path: '/tmp/alias.lua', old_str: 'alpha', new_str: 'omega' },
    }, {});

    expect(mockReview).toHaveBeenCalledWith('/tmp/alias.lua', 'omega beta', 'amp');
  });
});

// ---------------------------------------------------------------------------
// tool.call — apply_patch
// ---------------------------------------------------------------------------

describe('tool.call — apply_patch', () => {
  it('sends patch content to review', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({
      tool: 'apply_patch',
      input: { file_path: '/tmp/patched.lua', patch: '--- a\n+++ b\n' },
    }, {});

    expect(mockReview).toHaveBeenCalledWith('/tmp/patched.lua', '--- a\n+++ b\n', 'amp');
  });

  it('falls back to input.content when patch field is absent', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({
      tool: 'apply_patch',
      input: { file_path: '/tmp/patched.lua', content: 'inline patch' },
    }, {});

    expect(mockReview).toHaveBeenCalledWith('/tmp/patched.lua', 'inline patch', 'amp');
  });

  it('uses filepath alias from input.path', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({
      tool: 'apply_patch',
      input: { path: '/tmp/via-path.lua', patch: 'diff' },
    }, {});

    expect(mockReview).toHaveBeenCalledWith('/tmp/via-path.lua', 'diff', 'amp');
  });

  it('uses filepath alias from input.filepath', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({
      tool: 'apply_patch',
      input: { filepath: '/tmp/via-filepath.lua', patch: 'diff' },
    }, {});

    expect(mockReview).toHaveBeenCalledWith('/tmp/via-filepath.lua', 'diff', 'amp');
  });
});

// ---------------------------------------------------------------------------
// tool.call — review() error path
// ---------------------------------------------------------------------------

describe('tool.call — review() throws', () => {
  it('allows the write and calls uiNotify on review failure', async () => {
    mockReview.mockRejectedValue(new Error('neph not running'));

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    const rv = await handler({
      tool: 'create_file',
      input: { file_path: '/tmp/err.lua', content: 'content' },
    }, {}) as any;

    expect(rv).toEqual({ action: 'allow' });
    expect(mockUiNotify).toHaveBeenCalledWith(
      expect.stringContaining('/tmp/err.lua'),
      'warn',
    );
  });

  it('uiNotify message includes the error text', async () => {
    mockReview.mockRejectedValue(new Error('socket closed'));

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({
      tool: 'create_file',
      input: { file_path: '/tmp/err.lua', content: 'c' },
    }, {});

    const notifyMsg = mockUiNotify.mock.calls[0][0] as string;
    expect(notifyMsg).toContain('socket closed');
  });
});

// ---------------------------------------------------------------------------
// tool.call — reject reason fallback
// ---------------------------------------------------------------------------

describe('tool.call — reject reason fallback', () => {
  it('uses default reason when result.reason is undefined', async () => {
    mockReview.mockResolvedValue({
      schema: 'review/v1',
      decision: 'reject',
      content: '',
      hunks: [],
      // no reason field
    });

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    const rv = await handler({
      tool: 'create_file',
      input: { file_path: '/tmp/x.lua', content: 'x' },
    }, {}) as any;

    expect(rv.action).toBe('reject-and-continue');
    expect(rv.message).toContain('User rejected changes');
  });
});
