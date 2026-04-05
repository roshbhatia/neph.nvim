// tools/neph-cli/tests/neph-plugin.test.ts
// Unit tests for tools/amp/neph-plugin.ts covering session handlers,
// tool.call branches, and error paths.

import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';

// ---------------------------------------------------------------------------
// Hoist mocks before the module under test is imported.
// ---------------------------------------------------------------------------

vi.mock('../../lib/log', () => ({ debug: vi.fn() }));
vi.mock('node:fs', () => ({ readFileSync: vi.fn() }));

const mockUiSelect = vi.fn();
const mockUiInput = vi.fn();
const mockUiNotify = vi.fn();
const mockCreatePersistentQueue = vi.fn();

vi.mock('../../lib/neph-run', () => ({
  uiSelect: (...args: unknown[]) => mockUiSelect(...args),
  uiInput: (...args: unknown[]) => mockUiInput(...args),
  uiNotify: (...args: unknown[]) => mockUiNotify(...args),
  createPersistentQueue: (...args: unknown[]) => mockCreatePersistentQueue(...args),
}));

const mockCupcakeEval = vi.fn();
const mockReconstructContent = vi.fn();

vi.mock('../../lib/harness-base', () => ({
  CupcakeHelper: {
    cupcakeEval: (...args: unknown[]) => mockCupcakeEval(...args),
  },
  ContentHelper: {
    reconstructContent: (...args: unknown[]) => mockReconstructContent(...args),
  },
}));

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

  // Default: cupcakeEval returns allow
  mockCupcakeEval.mockReturnValue({ decision: 'allow' });

  // Default: reconstructContent returns the content or empty string
  mockReconstructContent.mockImplementation((_path: string, input: Record<string, unknown>) => {
    return (input.content as string) ?? '';
  });
});

afterEach(() => {
  vi.restoreAllMocks();
});

// ---------------------------------------------------------------------------
// session.start — amp.ui wiring and active signal
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

  it('sets amp_active via persistent queue', async () => {
    const pq = makeFakePQ();
    mockCreatePersistentQueue.mockReturnValueOnce(pq);

    const amp = makeAmp();
    nephPluginDefault(amp);
    await amp.emit('session.start');

    expect(pq.call).toHaveBeenCalledWith('set', 'amp_active', 'true');
  });
});

// ---------------------------------------------------------------------------
// session.end — queue teardown and recreation
// ---------------------------------------------------------------------------

describe('session.end', () => {
  it('clears amp_active and amp_running on session.end', async () => {
    const pq = makeFakePQ();
    mockCreatePersistentQueue.mockReturnValueOnce(pq);

    const amp = makeAmp();
    nephPluginDefault(amp);

    await amp.emit('session.end');
    expect(pq.call).toHaveBeenCalledWith('unset', 'amp_running');
    expect(pq.call).toHaveBeenCalledWith('unset', 'amp_active');
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
    expect(mockCreatePersistentQueue).toHaveBeenCalledTimes(2);

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
  });
});

// ---------------------------------------------------------------------------
// tool.call — allowed (non-write) tools pass through
// ---------------------------------------------------------------------------

describe('tool.call — non-write tools', () => {
  it('returns allow for run_bash', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);

    const handler = amp.handlers['tool.call'][0];
    const rv = await handler({ tool: 'run_bash', input: {} }, {});
    expect(rv).toEqual({ action: 'allow' });
    expect(mockCupcakeEval).not.toHaveBeenCalled();
  });

  it('returns allow for edit_file with no filePath', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);

    const handler = amp.handlers['tool.call'][0];
    const rv = await handler({ tool: 'edit_file', input: {} }, {});
    expect(rv).toEqual({ action: 'allow' });
    expect(mockCupcakeEval).not.toHaveBeenCalled();
  });
});

// ---------------------------------------------------------------------------
// tool.call — cupcake allow
// ---------------------------------------------------------------------------

describe('tool.call — cupcake allow', () => {
  it('allows create_file on cupcake allow', async () => {
    mockCupcakeEval.mockReturnValue({ decision: 'allow' });

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    const rv = await handler({
      tool: 'create_file',
      input: { file_path: '/tmp/newfile.lua', content: 'new' },
    }, {});

    expect(mockCupcakeEval).toHaveBeenCalledWith('amp', expect.objectContaining({
      tool_name: 'create_file',
      tool_input: expect.objectContaining({ file_path: '/tmp/newfile.lua' }),
    }));
    expect(rv).toEqual({ action: 'allow' });
  });

  it('passes reconstructed content into cupcake event', async () => {
    mockReconstructContent.mockReturnValue('reconstructed content');

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({
      tool: 'edit_file',
      input: { file_path: '/tmp/edit.lua', old_string: 'old', new_string: 'new' },
    }, {});

    expect(mockReconstructContent).toHaveBeenCalledWith('/tmp/edit.lua', expect.any(Object));
    expect(mockCupcakeEval).toHaveBeenCalledWith('amp', expect.objectContaining({
      tool_input: expect.objectContaining({ content: 'reconstructed content' }),
    }));
  });
});

// ---------------------------------------------------------------------------
// tool.call — cupcake deny
// ---------------------------------------------------------------------------

describe('tool.call — cupcake deny', () => {
  it('returns reject-and-continue on deny', async () => {
    mockCupcakeEval.mockReturnValue({ decision: 'deny', reason: 'Protected path' });

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    const rv = await handler({
      tool: 'create_file',
      input: { file_path: '/tmp/.env', content: 'SECRET=x' },
    }, {}) as any;

    expect(rv.action).toBe('reject-and-continue');
    expect(rv.message).toContain('Protected path');
  });

  it('returns reject-and-continue on block', async () => {
    mockCupcakeEval.mockReturnValue({ decision: 'block', reason: 'Dangerous command' });

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    const rv = await handler({
      tool: 'create_file',
      input: { file_path: '/tmp/x.lua', content: 'x' },
    }, {}) as any;

    expect(rv.action).toBe('reject-and-continue');
    expect(rv.message).toContain('Dangerous command');
  });

  it('uses default reason when cupcake reason is undefined', async () => {
    mockCupcakeEval.mockReturnValue({ decision: 'deny' });

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    const rv = await handler({
      tool: 'create_file',
      input: { file_path: '/tmp/x.lua', content: 'x' },
    }, {}) as any;

    expect(rv.action).toBe('reject-and-continue');
    expect(rv.message).toBeDefined();
  });
});

// ---------------------------------------------------------------------------
// tool.call — cupcake modify (partial accept)
// ---------------------------------------------------------------------------

describe('tool.call — cupcake modify (partial accept)', () => {
  it('returns modify action with updated content', async () => {
    mockCupcakeEval.mockReturnValue({
      decision: 'modify',
      updated_input: { content: 'modified by review' },
    });

    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    const rv = await handler({
      tool: 'create_file',
      input: { file_path: '/tmp/partial.lua', content: 'original' },
    }, {}) as any;

    expect(rv.action).toBe('modify');
    expect(rv.input.content).toBe('modified by review');
    expect(rv.input.file_path).toBe('/tmp/partial.lua');
  });
});

// ---------------------------------------------------------------------------
// tool.call — error path
// ---------------------------------------------------------------------------

describe('tool.call — error path', () => {
  it('allows the write and calls uiNotify when cupcakeEval throws', async () => {
    mockCupcakeEval.mockImplementation(() => { throw new Error('unexpected error'); });

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
    mockCupcakeEval.mockImplementation(() => { throw new Error('socket closed'); });

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
// tool.call — filepath aliases
// ---------------------------------------------------------------------------

describe('tool.call — filepath aliases', () => {
  it('uses input.path as filepath', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({ tool: 'apply_patch', input: { path: '/tmp/via-path.lua', content: 'x' } }, {});
    expect(mockCupcakeEval).toHaveBeenCalledWith('amp', expect.objectContaining({
      tool_input: expect.objectContaining({ file_path: '/tmp/via-path.lua' }),
    }));
  });

  it('uses input.filepath as filepath', async () => {
    const amp = makeAmp();
    nephPluginDefault(amp);
    const handler = amp.handlers['tool.call'][0];

    await handler({ tool: 'apply_patch', input: { filepath: '/tmp/via-filepath.lua', content: 'x' } }, {});
    expect(mockCupcakeEval).toHaveBeenCalledWith('amp', expect.objectContaining({
      tool_input: expect.objectContaining({ file_path: '/tmp/via-filepath.lua' }),
    }));
  });
});
