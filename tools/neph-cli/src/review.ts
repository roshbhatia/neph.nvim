import * as crypto from 'node:crypto';
import { NvimTransport } from './transport';
import type { HunkResult } from '../../lib/neph-run';

const RPC_CALL = 'return require("neph.rpc").request(...)';

export interface ReviewOptions {
  stdin: string;
  timeout: number;
  transport: NvimTransport | null;
}

export interface ReviewInput {
  path: string;
  content: string;
  agent?: string;
}

export interface ReviewEnvelope {
  schema: 'review/v1';
  decision: 'accept' | 'reject' | 'partial';
  content: string;
  hunks: HunkResult[];
  reason?: string;
}

/**
 * Run the review command.
 *
 * Protocol:
 *   stdin:  { path: string, content: string }
 *   stdout: { schema: "review/v1", decision: "accept"|"reject"|"partial", content: string, hunks: HunkResult[], reason?: string }
 *
 * Exit codes: 0 = accept/partial, 2 = reject, 3 = timeout
 */
export async function runReview(opts: ReviewOptions): Promise<number> {
  const { stdin, timeout, transport } = opts;

  // Parse stdin
  let input: ReviewInput;
  try {
    const parsed = JSON.parse(stdin);
    if (!parsed || typeof parsed.path !== 'string' || typeof parsed.content !== 'string') {
      process.stderr.write('neph review: stdin must be { "path": "...", "content": "..." }\n');
      return 0; // fail-open
    }
    input = parsed as ReviewInput;
  } catch {
    process.stderr.write('neph review: invalid JSON on stdin\n');
    return 0; // fail-open
  }

  // Dry-run mode
  if (process.env.NEPH_DRY_RUN === '1') {
    const envelope: ReviewEnvelope = { schema: 'review/v1', decision: 'accept', content: input.content, hunks: [], reason: 'Dry-run auto-accept' };
    process.stdout.write(JSON.stringify(envelope) + '\n');
    return 0;
  }

  // No socket — fail-open with warning
  if (!transport) {
    process.stderr.write('neph review: WARNING — no Neovim socket found, auto-accepting\n');
    const envelope: ReviewEnvelope = { schema: 'review/v1', decision: 'accept', content: input.content, hunks: [], reason: 'No Neovim connection' };
    process.stdout.write(JSON.stringify(envelope) + '\n');
    return 0;
  }

  // Set statusline
  try {
    await transport.executeLua(RPC_CALL, ['status.set', { name: 'neph_connected', value: 'true' }]);
  } catch {}

  let done = false;
  const cleanup = async () => {
    if (done) return;
    done = true;
    try {
      await transport.executeLua(RPC_CALL, ['status.unset', { name: 'neph_connected' }]);
    } catch {}
    // close() is wrapped in try/catch: if the transport is already broken the
    // executeLua above may have thrown (caught above), and close() itself could
    // throw on a dead connection.  We still want cleanup to complete.
    try {
      await transport.close();
    } catch {}
  };

  const requestId = crypto.randomUUID();
  let channelId: number;
  try {
    channelId = await transport.getChannelId();
  } catch (err) {
    process.stderr.write(`neph review: failed to get channel id: ${err}\n`);
    const envelope: ReviewEnvelope = { schema: 'review/v1', decision: 'accept', content: input.content, hunks: [], reason: 'RPC error (fail-open)' };
    process.stdout.write(JSON.stringify(envelope) + '\n');
    await transport.close();
    return 0;
  }

  return new Promise<number>((resolve) => {
    // Safety: onNotification registers synchronously here, before executeLua is
    // called below.  Because JS is single-threaded, the microtask queue cannot
    // dispatch the Neovim notification callback until after this synchronous
    // setup block completes — so there is no race between listener registration
    // and the RPC call even though executeLua is async.
    transport.onNotification('neph:review_done', async (args: unknown[]) => {
      // A late notification arriving after timeout is safely ignored here.
      if (done) return;
      try {
        const raw = args[0];
        if (raw === null || raw === undefined || typeof raw !== 'object' || Array.isArray(raw)) return;
        const payload = raw as Record<string, unknown>;
        if (payload.request_id !== requestId) return;

        const decision = (typeof payload.decision === 'string' ? payload.decision : 'accept') as ReviewEnvelope['decision'];
        // content from the notification arrives as `unknown`; coerce to string
        // defensively so that JSON.stringify cannot encounter a circular ref or
        // non-serializable value from a misbehaving Neovim plugin.
        const rawContent = payload.content;
        const content = typeof rawContent === 'string' ? rawContent : JSON.stringify(rawContent) ?? input.content;
        // hunks from the notification: Lua always sends an array; fall back to []
        // if the field is absent or not an array (e.g. old Neovim plugin version).
        const rawHunks = payload.hunks;
        const hunks: HunkResult[] = Array.isArray(rawHunks) ? rawHunks as HunkResult[] : [];
        const envelope: ReviewEnvelope = {
          schema: 'review/v1',
          decision,
          content,
          hunks,
          reason: typeof payload.reason === 'string' ? payload.reason : undefined,
        };

        try {
          process.stdout.write(JSON.stringify(envelope) + '\n');
        } catch (serializeErr) {
          process.stderr.write(`neph review: failed to serialize envelope: ${serializeErr}\n`);
          const fallback: ReviewEnvelope = { schema: 'review/v1', decision: 'accept', content: input.content, hunks: [], reason: 'serialize error (fail-open)' };
          process.stdout.write(JSON.stringify(fallback) + '\n');
        }
        await cleanup();
        resolve(decision === 'reject' ? 2 : 0);
      } catch (err) {
        const msg = err instanceof Error ? err.message : String(err);
        process.stderr.write(`neph review: notification handler error: ${msg}\n`);
      }
    });

    // Open the review in Neovim.  If Neovim auto-completes synchronously (zero
    // hunks), the RPC result carries { ok: true, msg: 'No changes' } and we
    // resolve immediately.  For all other results (e.g. 'Review enqueued') we
    // correctly wait for the neph:review_done notification registered above.
    transport.executeLua(RPC_CALL, [
      'review.open',
      {
        request_id: requestId,
        channel_id: channelId,
        path: input.path,
        content: input.content,
        agent: input.agent,
      },
    ]).then(async (result) => {
      // Check if auto-completed (no hunks)
      const rpcResult = result as { ok?: boolean; msg?: string } | undefined;
      if (rpcResult?.ok && rpcResult?.msg === 'No changes') {
        const envelope: ReviewEnvelope = { schema: 'review/v1', decision: 'accept', content: input.content, hunks: [] };
        process.stdout.write(JSON.stringify(envelope) + '\n');
        await cleanup();
        resolve(0);
      }
      // Any other msg (e.g. 'Review enqueued', 'Review started') means the
      // review is in progress — remain pending and wait for neph:review_done.
    }).catch(async (err: unknown) => {
      const msg = err instanceof Error ? err.message : String(err);
      process.stderr.write(`neph review: RPC error: ${msg}\n`);
      const envelope: ReviewEnvelope = { schema: 'review/v1', decision: 'accept', content: input.content, hunks: [], reason: 'RPC error (fail-open)' };
      process.stdout.write(JSON.stringify(envelope) + '\n');
      await cleanup();
      resolve(0); // fail-open
    });

    // Timeout.  After this fires, done=true so any late neph:review_done
    // notification is silently ignored (the `if (done) return` guard above).
    // Exit code 3 is propagated to process.exit() by the caller in index.ts.
    setTimeout(() => {
      if (!done) {
        process.stderr.write(`neph review: timed out after ${timeout}s\n`);
        cleanup().then(() => { resolve(3); }).catch((cleanupErr: unknown) => {
          process.stderr.write(`neph review: cleanup error after timeout: ${cleanupErr instanceof Error ? cleanupErr.message : String(cleanupErr)}\n`);
          resolve(3);
        });
      }
    }, timeout * 1000);
  });
}
