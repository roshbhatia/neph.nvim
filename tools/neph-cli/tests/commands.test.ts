import { describe, it, expect, vi } from 'vitest';
import { runCommand } from '../src/index';
import { FakeTransport } from './fake_transport';

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
