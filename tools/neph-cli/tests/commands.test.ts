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
