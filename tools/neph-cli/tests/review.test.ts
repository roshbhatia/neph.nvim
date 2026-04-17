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

    it('returns 0 when close() throws after a broken transport', async () => {
      // Covers Issue 4: cleanup() calls transport.close() even if executeLua
      // already threw; the try/catch around close() must prevent an unhandled
      // rejection from escaping.
      const transport = new FakeTransport();
      const origExec = transport.executeLua.bind(transport);
      transport.executeLua = async (code: string, args: unknown[]) => {
        const method = args[0] as string;
        if (method === 'review.open') throw new Error('connection lost');
        return origExec(code, args);
      };
      transport.close = async () => { throw new Error('socket already closed'); };
      const code = await runReview(makeOpts({ transport }));
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.decision).toBe('accept');
    });
  });

  describe('notification with non-string content', () => {
    it('coerces non-string content from notification and emits valid JSON', async () => {
      // Covers Issue 5: payload.content arriving as an object (e.g. from a
      // misbehaving Neovim plugin) must not cause JSON.stringify to throw.
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'Review started' };

      const promise = runReview(makeOpts({ transport }));
      await new Promise(r => setTimeout(r, 10));

      const openCall = transport.calls.find(c => c.args[0] === 'review.open');
      const requestId = (openCall?.args[1] as any)?.request_id;

      // Send an object instead of a string for content
      transport.fireNotification('neph:review_done', [{
        request_id: requestId,
        decision: 'accept',
        content: { nested: 'object' },
      }]);

      const code = await promise;
      expect(code).toBe(0);
      // Must be valid JSON on stdout
      expect(() => JSON.parse(stdoutSpy.mock.calls[0][0] as string)).not.toThrow();
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.decision).toBe('accept');
    });
  });

  describe('review enqueued waits for notification', () => {
    it('does not resolve immediately when msg is Review enqueued', async () => {
      // Covers Issue 3: when review.open returns { ok: true, msg: 'Review enqueued' }
      // the function must stay pending until neph:review_done fires.
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'Review enqueued' };

      const promise = runReview(makeOpts({ transport }));
      await new Promise(r => setTimeout(r, 30));

      // Should still be pending — no stdout written yet
      expect(stdoutSpy.mock.calls.length).toBe(0);

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
    });
  });

  describe('late notification after timeout is ignored', () => {
    it('does not write to stdout after timeout resolves with 3', async () => {
      // Covers Issue 2: a late neph:review_done after the timeout must be
      // silently dropped.  The done guard prevents a second stdout write.
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'Review started' };

      const promise = runReview(makeOpts({ transport, timeout: 1 }));
      // Let the timeout fire
      const code = await promise;
      expect(code).toBe(3);

      const callCountAfterTimeout = stdoutSpy.mock.calls.length;

      // Fire a late notification — should be a no-op
      const openCall = transport.calls.find(c => c.args[0] === 'review.open');
      const requestId = (openCall?.args[1] as any)?.request_id;
      transport.fireNotification('neph:review_done', [{
        request_id: requestId,
        decision: 'accept',
        content: 'late',
      }]);

      await new Promise(r => setTimeout(r, 10));
      expect(stdoutSpy.mock.calls.length).toBe(callCountAfterTimeout);
    });
  });

  describe('protocol shape', () => {
    it('stdout is always { schema, decision, content, hunks, reason? } — no agent-specific fields', async () => {
      process.env.NEPH_DRY_RUN = '1';
      await runReview(makeOpts());
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      const keys = Object.keys(output).sort();
      expect(keys).toEqual(['content', 'decision', 'hunks', 'reason', 'schema']);
      expect(output.schema).toBe('review/v1');
      expect(Array.isArray(output.hunks)).toBe(true);
    });
  });

  describe('hunks field', () => {
    it('hunks is empty array in dry-run mode', async () => {
      process.env.NEPH_DRY_RUN = '1';
      await runReview(makeOpts());
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.hunks).toEqual([]);
    });

    it('hunks defaults to [] when notification omits the field', async () => {
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
        // hunks intentionally absent
      }]);

      const code = await promise;
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(Array.isArray(output.hunks)).toBe(true);
      expect(output.hunks).toEqual([]);
    });

    it('hunks passes through when provided in notification', async () => {
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
        hunks: [{ lnum: 1, text: 'changed' }],
      }]);

      const code = await promise;
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.hunks).toEqual([{ lnum: 1, text: 'changed' }]);
    });
  });

  describe('agent field forwarding', () => {
    it('forwards agent field to review.open RPC call', async () => {
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'No changes' };

      await runReview(makeOpts({
        transport,
        stdin: JSON.stringify({ path: '/tmp/test.lua', content: 'hello', agent: 'claude' }),
      }));

      const openCall = transport.calls.find(c => c.args[0] === 'review.open');
      expect(openCall).toBeDefined();
      expect((openCall!.args[1] as any).agent).toBe('claude');
    });

    it('agent field is undefined when not provided in stdin', async () => {
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'No changes' };

      await runReview(makeOpts({ transport }));

      const openCall = transport.calls.find(c => c.args[0] === 'review.open');
      expect(openCall).toBeDefined();
      expect((openCall!.args[1] as any).agent).toBeUndefined();
    });
  });

  describe('notification with wrong request_id is ignored', () => {
    it('does not resolve when request_id does not match', async () => {
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'Review started' };

      const promise = runReview(makeOpts({ transport, timeout: 1 }));
      await new Promise(r => setTimeout(r, 5));

      // Fire notification with a wrong request_id
      transport.fireNotification('neph:review_done', [{
        request_id: 'wrong-id',
        decision: 'accept',
        content: 'hello world',
      }]);

      const code = await promise;
      // Should timeout (3), not accept (0), since the notification was ignored
      expect(code).toBe(3);
    });
  });

  // Pass 6: reason field forwarding from reject notification
  describe('reason field in reject notification', () => {
    it('forwards reason string from notification payload', async () => {
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
        reason: 'Looks risky',
      }]);

      const code = await promise;
      expect(code).toBe(2);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.reason).toBe('Looks risky');
    });

    it('reason is undefined when not provided in accept notification', async () => {
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
        // reason intentionally absent
      }]);

      const code = await promise;
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      // reason must be absent or undefined (not stringified as "undefined")
      expect(output.reason).toBeUndefined();
    });

    it('non-string reason in notification is omitted from output', async () => {
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
        reason: 42, // non-string
      }]);

      const code = await promise;
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      // Non-string reason must be dropped (typed as undefined in the envelope)
      expect(output.reason).toBeUndefined();
    });
  });

  // Pass 6: empty stdin edge case
  describe('empty stdin', () => {
    it('returns 0 (fail-open) for empty stdin string', async () => {
      const code = await runReview(makeOpts({ stdin: '' }));
      expect(code).toBe(0);
    });
  });

  // Pass 10: getChannelId failure → fail-open
  describe('getChannelId failure', () => {
    it('returns 0 (fail-open) when getChannelId throws', async () => {
      const transport = new FakeTransport();
      transport.getChannelId = async () => { throw new Error('channel unavailable'); };
      const code = await runReview(makeOpts({ transport }));
      expect(code).toBe(0);
      const output = JSON.parse(stdoutSpy.mock.calls[0][0] as string);
      expect(output.decision).toBe('accept');
      expect(output.reason).toContain('RPC error');
    });
  });

  // Pass 10: review.open returning ok: false stays pending until timeout
  describe('review.open returns ok: false', () => {
    it('does not auto-accept on ok: false (waits for notification, then times out)', async () => {
      const transport = new FakeTransport();
      // ok: false but NOT the special "No changes" msg — should stay pending
      transport.responses['review.open'] = { ok: false, msg: 'Failed to open' };
      const code = await runReview(makeOpts({ transport, timeout: 1 }));
      // Since neither "No changes" nor neph:review_done fires, times out
      expect(code).toBe(3);
    });
  });

  // Pass 10: status.set RPC is called before opening review
  describe('status.set RPC call ordering', () => {
    it('status.set is called before review.open', async () => {
      const transport = new FakeTransport();
      transport.responses['review.open'] = { ok: true, msg: 'No changes' };
      await runReview(makeOpts({ transport }));
      const calls = transport.calls.map(c => c.args[0] as string);
      const statusSetIdx = calls.indexOf('status.set');
      const reviewOpenIdx = calls.indexOf('review.open');
      expect(statusSetIdx).toBeGreaterThanOrEqual(0);
      expect(reviewOpenIdx).toBeGreaterThan(statusSetIdx);
    });
  });
});
