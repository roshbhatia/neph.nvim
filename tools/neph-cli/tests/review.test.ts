import { describe, it, expect, vi, beforeEach, afterEach } from 'vitest';
import { runReview, type ReviewOptions } from '../src/review';
import { FakeTransport } from './fake_transport';

function makeOpts(overrides: Partial<ReviewOptions> = {}): ReviewOptions {
  return {
    stdin: JSON.stringify({ path: '/tmp/test.lua', content: 'hello world' }),
    timeout: 5,
    transport: new FakeTransport(),
    ...overrides,
  };
}

describe('runReview', () => {
  let stdoutSpy: ReturnType<typeof vi.spyOn>;
  let stderrSpy: ReturnType<typeof vi.spyOn>;

  beforeEach(() => {
    stdoutSpy = vi.spyOn(process.stdout, 'write').mockImplementation(() => true);
    stderrSpy = vi.spyOn(process.stderr, 'write').mockImplementation(() => true);
  });

  afterEach(() => {
    stdoutSpy.mockRestore();
    stderrSpy.mockRestore();
    delete process.env.NEPH_DRY_RUN;
  });

  describe('input validation', () => {
    it('returns 0 (fail-open) for invalid JSON', async () => {
      const code = await runReview(makeOpts({ stdin: 'not json' }));
      expect(code).toBe(0);
    });

    it('returns 0 (fail-open) for missing path field', async () => {
      const code = await runReview(makeOpts({ stdin: JSON.stringify({ content: 'foo' }) }));
      expect(code).toBe(0);
    });

    it('returns 0 (fail-open) for missing content field', async () => {
      const code = await runReview(makeOpts({ stdin: JSON.stringify({ path: '/foo' }) }));
      expect(code).toBe(0);
    });
  });

  describe('dry-run mode', () => {
    it('auto-accepts with NEPH_DRY_RUN=1', async () => {
      process.env.NEPH_DRY_RUN = '1';
      const code = await runReview(makeOpts());
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.decision).toBe('accept');
      expect(output.content).toBe('hello world');
    });
  });

  describe('no socket (fail-open)', () => {
    it('auto-accepts when transport is null', async () => {
      const code = await runReview(makeOpts({ transport: null }));
      expect(code).toBe(0);
      expect(stderrSpy).toHaveBeenCalledWith(expect.stringContaining('WARNING'));
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.decision).toBe('accept');
      expect(output.content).toBe('hello world');
    });
  });

  describe('no-changes auto-accept', () => {
    it('returns accept when review.open says no changes', async () => {
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'No changes' };
      const code = await runReview(makeOpts({ transport }));
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.decision).toBe('accept');
    });
  });

  describe('accept via notification', () => {
    it('returns neph protocol on accept', async () => {
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'Review started' };

      const promise = runReview(makeOpts({ transport }));
      await new Promise(r => setTimeout(r, 10));

      const openCall = transport.calls.find(c => c.args[0] === 'review.open');
      const requestId = (openCall?.args[1] as any)?.request_id;

      transport.fireNotification('neph:review_done', [{
        request_id: requestId,
        decision: 'accept',
        content: 'hello world',
      }]);

      const code = await promise;
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.decision).toBe('accept');
      expect(output.content).toBe('hello world');
      // No agent-specific fields
      expect(output.hookSpecificOutput).toBeUndefined();
    });
  });

  describe('partial accept', () => {
    it('returns 0 with partial decision and merged content', async () => {
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'Review started' };

      const promise = runReview(makeOpts({ transport }));
      await new Promise(r => setTimeout(r, 10));

      const openCall = transport.calls.find(c => c.args[0] === 'review.open');
      const requestId = (openCall?.args[1] as any)?.request_id;

      transport.fireNotification('neph:review_done', [{
        request_id: requestId,
        decision: 'partial',
        content: 'merged content',
      }]);

      const code = await promise;
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.decision).toBe('partial');
      expect(output.content).toBe('merged content');
    });
  });

  describe('reject', () => {
    it('returns exit code 2 on reject', async () => {
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'Review started' };

      const promise = runReview(makeOpts({ transport }));
      await new Promise(r => setTimeout(r, 10));

      const openCall = transport.calls.find(c => c.args[0] === 'review.open');
      const requestId = (openCall?.args[1] as any)?.request_id;

      transport.fireNotification('neph:review_done', [{
        request_id: requestId,
        decision: 'reject',
        content: '',
        reason: 'User rejected',
      }]);

      const code = await promise;
      expect(code).toBe(2);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.decision).toBe('reject');
      expect(output.reason).toBe('User rejected');
    });
  });

  describe('timeout', () => {
    it('returns exit code 3 on timeout', async () => {
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'Review started' };
      const code = await runReview(makeOpts({ transport, timeout: 1 }));
      expect(code).toBe(3);
    });
  });

  describe('RPC error (fail-open)', () => {
    it('returns 0 on RPC error', async () => {
      const transport = new FakeTransport();
      const origExec = transport.executeLua.bind(transport);
      transport.executeLua = async (code: string, args: unknown[]) => {
        const method = args[0] as string;
        if (method === 'review.open') throw new Error('connection lost');
        return origExec(code, args);
      };
      const code = await runReview(makeOpts({ transport }));
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.decision).toBe('accept');
      expect(output.reason).toContain('fail-open');
    });
  });

  describe('protocol shape', () => {
    it('stdout is always { decision, content, reason? } — no agent-specific fields', async () => {
      process.env.NEPH_DRY_RUN = '1';
      await runReview(makeOpts());
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      const keys = Object.keys(output).sort();
      expect(keys).toEqual(['content', 'decision', 'reason']);
    });
  });
});
