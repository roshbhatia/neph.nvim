import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { EventEmitter } from 'node:events';
import { runCommand } from '../src/index';
import { FakeTransport } from './fake_transport';

// Flush all pending microtasks and one round of setImmediate callbacks so that
// async processLine calls spawned inside event handlers have a chance to
// resolve before we assert on them.
function flushAsync() {
  return new Promise<void>((resolve) => setImmediate(resolve));
}

describe('neph commands', () => {
  it('outputs spec JSON', async () => {
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runCommand(null, 'spec', ['spec']);
    expect(stdoutSpy).toHaveBeenCalled();
    const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
    expect(output.name).toBe('neph');
    stdoutSpy.mockRestore();
  });

  it('handles status command', async () => {
    const transport = new FakeTransport();
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runCommand(transport, 'status', ['status']);
    expect(stdoutSpy).toHaveBeenCalledWith(expect.stringContaining('connected'));
    stdoutSpy.mockRestore();
  });

  it('handles set command', async () => {
    const transport = new FakeTransport();
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runCommand(transport, 'set', ['set', 'foo', 'bar']);
    expect(transport.calls[0].args[0]).toBe('status.set');
    expect(transport.calls[0].args[1]).toEqual({ name: 'foo', value: 'bar' });
    stdoutSpy.mockRestore();
  });

  it('handles dry-run review', async () => {
    process.env.NEPH_DRY_RUN = '1';
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((() => { throw new Error('EXIT'); }) as any);
    try {
      await runCommand(null, 'review', ['review'], JSON.stringify({ path: '/tmp/test.txt', content: 'new content' }));
    } catch (e: any) {
      if (e.message !== 'EXIT') throw e;
    }
    const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
    expect(output.decision).toBe('accept');
    expect(output.content).toBe('new content');
    delete process.env.NEPH_DRY_RUN;
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

describe('review command', () => {
  it('handles unset command routing to status.unset', async () => {
    const transport = new FakeTransport();
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runCommand(transport, 'unset', ['unset', 'myvar']);
    expect(transport.calls[0].args[0]).toBe('status.unset');
    expect(transport.calls[0].args[1]).toEqual({ name: 'myvar' });
    stdoutSpy.mockRestore();
  });

  it('handles checktime command routing to buffers.check', async () => {
    const transport = new FakeTransport();
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runCommand(transport, 'checktime', ['checktime']);
    expect(transport.calls[0].args[0]).toBe('buffers.check');
    stdoutSpy.mockRestore();
  });

  it('handles close-tab command routing to tab.close', async () => {
    const transport = new FakeTransport();
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runCommand(transport, 'close-tab', ['close-tab']);
    expect(transport.calls[0].args[0]).toBe('tab.close');
    stdoutSpy.mockRestore();
  });

  it('handles get command routing to status.get', async () => {
    const transport = new FakeTransport();
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    await runCommand(transport, 'get', ['get', 'my_var']);
    expect(transport.calls[0].args[0]).toBe('status.get');
    expect(transport.calls[0].args[1]).toEqual({ name: 'my_var' });
    stdoutSpy.mockRestore();
  });

  it('exits with error for unknown command', async () => {
    const transport = new FakeTransport();
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation(() => undefined as never);
    await runCommand(transport, 'bogus', ['bogus']);
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Unknown command: bogus'));
    expect(exitSpy).toHaveBeenCalledWith(1);
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

describe('neph_connected status', () => {
  it('review command sets neph_connected via runReview', async () => {
    const transport = new FakeTransport();
    transport.responses['review.open'] = { ok: true, msg: 'No changes' };

    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation((() => { throw new Error('EXIT'); }) as any);

    try {
      await runCommand(transport, 'review', ['review'], JSON.stringify({ path: '/tmp/test.txt', content: 'new content' }));
    } catch (e: any) {
      if (e.message !== 'EXIT') throw e;
    }

    // Verify status.set was called (neph_connected)
    const statusCalls = transport.calls.filter(c => c.args[0] === 'status.set');
    expect(statusCalls.length).toBeGreaterThan(0);

    stderrSpy.mockRestore();
    stdoutSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

describe('error cases', () => {
  it('handles transport errors gracefully', async () => {
    const transport = new FakeTransport();
    transport.executeLua = async () => { throw new Error('connection lost'); };
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation(() => undefined as never);
    await runCommand(transport, 'set', ['set', 'foo', 'bar']);
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('connection lost'));
    expect(exitSpy).toHaveBeenCalledWith(1);
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it('review with empty stdin fails open (invalid JSON)', async () => {
    const transport = new FakeTransport();
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation(() => undefined as never);
    await runCommand(transport, 'review', ['review'], '');
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('invalid JSON'));
    expect(exitSpy).toHaveBeenCalledWith(0); // fail-open
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

// ---------------------------------------------------------------------------
// connect command
// ---------------------------------------------------------------------------
describe('connect command', () => {
  let fakeStdin: EventEmitter & { setEncoding: ReturnType<typeof vi.fn> };
  let stdoutSpy: ReturnType<typeof vi.spyOn>;
  let stderrSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;
  let stdinSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    fakeStdin = Object.assign(new EventEmitter(), { setEncoding: vi.fn() });
    stdinSpy = vi.spyOn(process, 'stdin', 'get').mockReturnValue(fakeStdin as any);
    stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    exitSpy = vi.spyOn(process, 'exit').mockImplementation(() => undefined as never);
  });

  afterEach(() => {
    stdinSpy.mockRestore();
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it('exits with code 1 when transport is null', async () => {
    await runCommand(null, 'connect', ['connect'], '');
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('no Neovim socket found'));
    expect(exitSpy).toHaveBeenCalledWith(1);
  });

  it('processes a single complete JSON line and writes a success response', async () => {
    const transport = new FakeTransport();
    transport.responses['status.get'] = { value: 'ok' };

    runCommand(transport, 'connect', ['connect'], '');

    const req = JSON.stringify({ id: 1, method: 'status.get', params: {} });
    fakeStdin.emit('data', req + '\n');

    await flushAsync();

    const written = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    const parsed = JSON.parse(written.trim());
    expect(parsed).toMatchObject({ id: 1, ok: true, result: { value: 'ok' } });
  });

  it('handles a JSON object split across multiple data chunks', async () => {
    const transport = new FakeTransport();
    transport.responses['status.get'] = { value: 'split' };

    runCommand(transport, 'connect', ['connect'], '');

    const req = JSON.stringify({ id: 2, method: 'status.get', params: {} });
    // Split the line at an arbitrary boundary — no newline until the second chunk
    const mid = Math.floor(req.length / 2);
    fakeStdin.emit('data', req.slice(0, mid));
    fakeStdin.emit('data', req.slice(mid) + '\n');

    await flushAsync();

    const written = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    const parsed = JSON.parse(written.trim());
    expect(parsed).toMatchObject({ id: 2, ok: true, result: { value: 'split' } });
  });

  it('returns an error response for malformed JSON', async () => {
    const transport = new FakeTransport();

    runCommand(transport, 'connect', ['connect'], '');

    fakeStdin.emit('data', 'not valid json\n');

    await flushAsync();

    const written = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    const parsed = JSON.parse(written.trim());
    expect(parsed).toMatchObject({ id: -1, ok: false, error: 'invalid JSON' });
  });

  it('processes remaining buffer content on stdin end', async () => {
    const transport = new FakeTransport();
    transport.responses['status.get'] = { value: 'end' };

    runCommand(transport, 'connect', ['connect'], '');

    // Send a line without a trailing newline, then close stdin
    fakeStdin.emit('data', JSON.stringify({ id: 3, method: 'status.get', params: {} }));
    fakeStdin.emit('end');

    await flushAsync();

    const written = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    const parsed = JSON.parse(written.trim());
    expect(parsed).toMatchObject({ id: 3, ok: true });
    expect(exitSpy).toHaveBeenCalledWith(0);
  });

  it('closes transport and exits 0 on stdin end with empty buffer', async () => {
    const transport = new FakeTransport();
    const closeSpy = vi.spyOn(transport, 'close');

    runCommand(transport, 'connect', ['connect'], '');

    fakeStdin.emit('end');

    await flushAsync();

    expect(closeSpy).toHaveBeenCalled();
    expect(exitSpy).toHaveBeenCalledWith(0);
  });

  it('exits with code 1 and writes error response when transport.executeLua throws', async () => {
    const transport = new FakeTransport();
    transport.executeLua = async () => { throw new Error('connection lost'); };

    runCommand(transport, 'connect', ['connect'], '');

    fakeStdin.emit('data', JSON.stringify({ id: 4, method: 'status.get', params: {} }) + '\n');

    await flushAsync();

    const written = (stdoutSpy.mock.calls.map(c => c[0]) as string[]).join('');
    const parsed = JSON.parse(written.trim());
    expect(parsed).toMatchObject({ id: 4, ok: false });
    expect(parsed.error).toContain('connection lost');
    expect(exitSpy).toHaveBeenCalledWith(1);
  });

  it('ignores data chunks after connection is broken', async () => {
    const transport = new FakeTransport();
    let callCount = 0;
    transport.executeLua = async () => {
      callCount++;
      throw new Error('broken');
    };

    runCommand(transport, 'connect', ['connect'], '');

    fakeStdin.emit('data', JSON.stringify({ id: 5, method: 'status.get' }) + '\n');
    await flushAsync();

    // Emit a second line after the connection is broken — should be silently dropped
    fakeStdin.emit('data', JSON.stringify({ id: 6, method: 'status.get' }) + '\n');
    await flushAsync();

    // executeLua should only have been called once (the second chunk is dropped)
    expect(callCount).toBe(1);
  });

  it('handles transport.close() throwing on stdin error without propagating', async () => {
    const transport = new FakeTransport();
    transport.close = async () => { throw new Error('close failed'); };

    runCommand(transport, 'connect', ['connect'], '');

    // Should not throw; the error handler swallows transport.close() failures
    expect(() => fakeStdin.emit('error', new Error('stdin broke'))).not.toThrow();

    await flushAsync();

    expect(exitSpy).toHaveBeenCalledWith(0);
  });
});
