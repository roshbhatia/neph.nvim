import { describe, it, expect, vi, beforeEach } from 'vitest';
import { runCommand } from '../src/index';
import { FakeTransport } from './fake_transport';

describe('neph ui commands', () => {
  let transport: FakeTransport;
  let stdoutSpy: any;
  let stderrSpy: any;
  let exitSpy: any;

  beforeEach(() => {
    transport = new FakeTransport();
    stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    exitSpy = vi.spyOn(process, 'exit').mockImplementation(() => undefined as never);
  });

  afterEach(() => {
    vi.restoreAllMocks();
  });

  it('handles ui-notify command', async () => {
    await runCommand(transport, 'ui-notify', ['ui-notify', 'hello world', 'warn']);
    expect(transport.calls[0].args[0]).toBe('ui.notify');
    expect(transport.calls[0].args[1]).toEqual({ message: 'hello world', level: 'warn' });
  });

  it('ui-select sends RPC and waits for notification', async () => {
    transport.responses['ui.select'] = { ok: true };

    // Simulate notification
    setTimeout(() => {
      // Find the ui.select call to get the requestId
      const selectCall = transport.calls.find(c => c.args[0] === 'ui.select');
      if (selectCall) {
        const requestId = (selectCall.args[1] as any).request_id;
        transport.fireNotification('neph:ui_response', [{ request_id: requestId, choice: 'Option B' }]);
      }
    }, 50);

    await runCommand(transport, 'ui-select', ['ui-select', 'Pick one', 'Option A', 'Option B']);

    // Wait for the exit mock to be called (max 1s)
    for (let i = 0; i < 100; i++) {
      if (exitSpy.mock.calls.length > 0) break;
      await new Promise(r => setTimeout(r, 10));
    }

    const selectCall = transport.calls.find(c => c.args[0] === 'ui.select');
    expect(selectCall).toBeDefined();
    expect(selectCall!.args[1]).toEqual(expect.objectContaining({ title: 'Pick one', options: ['Option A', 'Option B'] }));
    expect(stdoutSpy).toHaveBeenCalledWith("Option B\n");
    expect(exitSpy).toHaveBeenCalledWith(0);
  });

  it('ui-input sends RPC and waits for notification', async () => {
    transport.responses['ui.input'] = { ok: true };

    // Simulate notification
    setTimeout(() => {
      const inputCall = transport.calls.find(c => c.args[0] === 'ui.input');
      if (inputCall) {
        const requestId = (inputCall.args[1] as any).request_id;
        transport.fireNotification('neph:ui_response', [{ request_id: requestId, choice: 'user input text' }]);
      }
    }, 50);

    await runCommand(transport, 'ui-input', ['ui-input', 'Enter name', 'default value']);

    // Wait for the exit mock to be called
    for (let i = 0; i < 100; i++) {
      if (exitSpy.mock.calls.length > 0) break;
      await new Promise(r => setTimeout(r, 10));
    }

    const inputCall = transport.calls.find(c => c.args[0] === 'ui.input');
    expect(inputCall).toBeDefined();
    expect(inputCall!.args[1]).toEqual(expect.objectContaining({ title: 'Enter name', default: 'default value' }));
    expect(stdoutSpy).toHaveBeenCalledWith("user input text\n");
    expect(exitSpy).toHaveBeenCalledWith(0);
  });

  it('ui-select exits with usage if arguments are missing', async () => {
    await runCommand(transport, 'ui-select', ['ui-select', 'Title']);
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Usage: neph ui-select'));
    expect(exitSpy).toHaveBeenCalledWith(1);
  });

  it('ui-input exits with usage if title is missing', async () => {
    await runCommand(transport, 'ui-input', ['ui-input']);
    expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('Usage: neph ui-input'));
    expect(exitSpy).toHaveBeenCalledWith(1);
  });
});
