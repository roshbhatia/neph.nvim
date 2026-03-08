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
    await runCommand(null, 'review', ['review', 'test.txt'], 'new content');
    const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
    expect(output.decision).toBe('accept');
    expect(output.content).toBe('new content');
    delete process.env.NEPH_DRY_RUN;
    stdoutSpy.mockRestore();
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
  it('review command sets neph_connected before review.open', async () => {
    const transport = new FakeTransport();
    // Make review.open fail so we don't hang waiting for result
    transport.executeLua = vi.fn()
      .mockResolvedValueOnce({ ok: true }) // status.set neph_connected
      .mockResolvedValueOnce(42) // getChannelId (via nvim_get_api_info mock)
      .mockRejectedValueOnce(new Error('review failed')); // review.open

    // getChannelId calls executeLua internally, but FakeTransport may differ
    // Override getChannelId to return a value
    transport.getChannelId = vi.fn().mockResolvedValue(42);

    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation(() => undefined as never);

    await runCommand(transport, 'review', ['review', 'test.txt'], 'new content');

    expect(transport.executeLua).toHaveBeenCalledWith(
      expect.any(String),
      ['status.set', { name: 'neph_connected', value: 'true' }],
    );

    stderrSpy.mockRestore();
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

  it('exits with usage when review has no file path', async () => {
    const transport = new FakeTransport();
    const stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, 'exit').mockImplementation(() => undefined as never);
    await runCommand(transport, 'review', ['review']);
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Usage: neph review <path>'));
    expect(exitSpy).toHaveBeenCalledWith(1);
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });
});
