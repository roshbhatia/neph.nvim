import * as crypto from 'node:crypto';
import { NvimTransport } from './transport';

const RPC_CALL = 'return require("neph.rpc").request(...)';

export interface ReviewOptions {
  stdin: string;
  timeout: number;
  transport: NvimTransport | null;
}

export interface ReviewInput {
  path: string;
  content: string;
}

export interface ReviewEnvelope {
  decision: string;
  content: string;
  reason?: string;
}

/**
 * Run the review command.
 *
 * Protocol:
 *   stdin:  { path: string, content: string }
 *   stdout: { decision: "accept"|"reject"|"partial", content: string, reason?: string }
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
    const envelope: ReviewEnvelope = { decision: 'accept', content: input.content, reason: 'Dry-run auto-accept' };
    process.stdout.write(JSON.stringify(envelope) + '\n');
    return 0;
  }

  // No socket — fail-open with warning
  if (!transport) {
    process.stderr.write('neph review: WARNING — no Neovim socket found, auto-accepting\n');
    const envelope: ReviewEnvelope = { decision: 'accept', content: input.content, reason: 'No Neovim connection' };
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
    await transport.close();
  };

  const requestId = crypto.randomUUID();
  let channelId: number;
  try {
    channelId = await transport.getChannelId();
  } catch (err) {
    process.stderr.write(`neph review: failed to get channel id: ${err}\n`);
    const envelope: ReviewEnvelope = { decision: 'accept', content: input.content, reason: 'RPC error (fail-open)' };
    process.stdout.write(JSON.stringify(envelope) + '\n');
    await transport.close();
    return 0;
  }

  return new Promise<number>((resolve) => {
    // Listen for review completion
    transport.onNotification('neph:review_done', async (args: unknown[]) => {
      if (done) return;
      try {
        const payload = args[0] as Record<string, unknown> | undefined;
        if (!payload || payload.request_id !== requestId) return;

        const decision = typeof payload.decision === 'string' ? payload.decision : 'accept';
        const envelope: ReviewEnvelope = {
          decision,
          content: (payload.content as string) ?? input.content,
          reason: payload.reason as string | undefined,
        };

        process.stdout.write(JSON.stringify(envelope) + '\n');
        await cleanup();
        resolve(decision === 'reject' ? 2 : 0);
      } catch (err) {
        process.stderr.write(`neph review: notification handler error: ${err}\n`);
      }
    });

    // Open the review in Neovim
    transport.executeLua(RPC_CALL, [
      'review.open',
      {
        request_id: requestId,
        channel_id: channelId,
        path: input.path,
        content: input.content,
      },
    ]).then(async (result) => {
      // Check if auto-completed (no hunks)
      const rpcResult = result as { ok?: boolean; msg?: string } | undefined;
      if (rpcResult?.ok && rpcResult?.msg === 'No changes') {
        const envelope: ReviewEnvelope = { decision: 'accept', content: input.content };
        process.stdout.write(JSON.stringify(envelope) + '\n');
        await cleanup();
        resolve(0);
      }
    }).catch(async (err) => {
      process.stderr.write(`neph review: RPC error: ${err}\n`);
      const envelope: ReviewEnvelope = { decision: 'accept', content: input.content, reason: 'RPC error (fail-open)' };
      process.stdout.write(JSON.stringify(envelope) + '\n');
      await cleanup();
      resolve(0); // fail-open
    });

    // Timeout
    setTimeout(async () => {
      if (!done) {
        process.stderr.write(`neph review: timed out after ${timeout}s\n`);
        await cleanup();
        resolve(3);
      }
    }, timeout * 1000);
  });
}
