// tests/review-ctrl.test.ts
// Error-path tests for runReviewCtrlCommand and gate status null guard.
import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { runReviewCtrlCommand } from '../src/review-ctrl';
import { runGateCommand } from '../src/gate';
import { FakeTransport } from './fake_transport';

// Helper: make process.exit throw so we can assert on it within async tests.
function mockExit() {
  return vi.spyOn(process, 'exit').mockImplementation((() => {
    throw new Error('EXIT');
  }) as never);
}

describe('runReviewCtrlCommand — unwrapResult error paths', () => {
  let stderrSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    exitSpy = mockExit();
  });

  afterEach(() => {
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it('status: surfaces MALFORMED error when RPC returns object without ok field', async () => {
    const transport = new FakeTransport();
    // Return an object that is missing the 'ok' boolean field.
    transport.responses['review.status'] = { data: 'surprise' };
    await expect(runReviewCtrlCommand('status', [], transport)).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining("Response missing 'ok' boolean field"),
    );
  });

  it('status: surfaces UNEXPECTED error when RPC returns a primitive string', async () => {
    const transport = new FakeTransport();
    transport.responses['review.status'] = 'not-an-object' as unknown as Record<string, unknown>;
    await expect(runReviewCtrlCommand('status', [], transport)).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining("Expected object response"),
    );
  });

  it('status: surfaces RPC transport error with actionable message', async () => {
    const transport = new FakeTransport();
    transport.executeLuaError = new Error('connection reset by peer');
    await expect(runReviewCtrlCommand('status', [], transport)).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining('connection reset by peer'),
    );
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining('Is Neovim running'),
    );
  });

  it('accept: surfaces inner result error from review.accept', async () => {
    const transport = new FakeTransport();
    // ok=true outer, but inner result has ok=false
    transport.responses['review.accept'] = { ok: true, result: { ok: false, error: 'no active review' } };
    await expect(runReviewCtrlCommand('accept', [], transport)).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining('no active review'),
    );
  });

  it('unknown subcommand: exits with usage message', async () => {
    const transport = new FakeTransport();
    await expect(runReviewCtrlCommand('bogus', [], transport)).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining('Unknown review subcommand: bogus'),
    );
  });
});

describe('runGateCommand — status null guard', () => {
  let stderrSpy: ReturnType<typeof vi.spyOn>;
  let stdoutSpy: ReturnType<typeof vi.spyOn>;
  let exitSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
    stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    exitSpy = mockExit();
  });

  afterEach(() => {
    stderrSpy.mockRestore();
    stdoutSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it('gate status: exits with actionable error when RPC returns null', async () => {
    const transport = new FakeTransport();
    // Override executeLua to return null for the gate status call.
    transport.executeLua = async () => null;
    await expect(runGateCommand(['gate', 'status'], transport)).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining('status returned no value'),
    );
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining(':NephHealth'),
    );
    expect(exitSpy).toHaveBeenCalledWith(1);
  });

  it('gate status: outputs the gate state string when RPC succeeds', async () => {
    const transport = new FakeTransport();
    transport.executeLua = async () => 'normal';
    await runGateCommand(['gate', 'status'], transport);
    expect(stdoutSpy).toHaveBeenCalledWith('normal\n');
  });

  it('gate: exits with error when no transport is provided', async () => {
    await expect(runGateCommand(['gate', 'hold'], null)).rejects.toThrow('EXIT');
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining('no Neovim socket'),
    );
    expect(exitSpy).toHaveBeenCalledWith(1);
  });
});
