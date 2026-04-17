// tools/neph-cli/src/review-ctrl.ts
// CLI subcommands for controlling a live neph review session from the terminal.
// Exposes: neph review status|accept|reject|accept-all|reject-all|submit|next

import { NvimTransport } from './transport';

const RPC_CALL = 'return require("neph.rpc").request(...)';

type ReviewStatusResult = {
  active: boolean;
  file?: string;
  total?: number;
  accepted?: number;
  rejected?: number;
  undecided?: number;
};

type ReviewMutateResult = {
  ok: boolean;
  idx?: number;
  next?: number | null;
  count?: number;
  error?: string;
};

async function rpc(transport: NvimTransport, method: string, params: Record<string, unknown> = {}): Promise<unknown> {
  return transport.executeLua(RPC_CALL, [method, params]);
}

function unwrapResult(raw: unknown): { ok: boolean; result?: unknown; error?: { code: string; message: string } } {
  if (typeof raw !== 'object' || raw === null) {
    return { ok: false, error: { code: 'UNEXPECTED', message: `Expected object response, got ${typeof raw}: ${String(raw)}` } };
  }
  const obj = raw as Record<string, unknown>;
  if (typeof obj['ok'] !== 'boolean') {
    return { ok: false, error: { code: 'MALFORMED', message: `Response missing 'ok' boolean field: ${JSON.stringify(raw)}` } };
  }
  const error = obj['error'];
  const typedError =
    typeof error === 'object' && error !== null &&
    typeof (error as Record<string, unknown>)['code'] === 'string' &&
    typeof (error as Record<string, unknown>)['message'] === 'string'
      ? (error as { code: string; message: string })
      : error !== undefined
        ? { code: 'ERROR', message: String(error) }
        : undefined;
  return { ok: obj['ok'] as boolean, result: obj['result'], error: typedError };
}

export async function runReviewCtrlCommand(
  subcommand: string,
  args: string[],
  transport: NvimTransport,
): Promise<void> {
  // Parse common flags
  const idxFlag = args.indexOf('--idx');
  const idx: number | undefined = idxFlag >= 0 ? parseInt(args[idxFlag + 1], 10) : undefined;

  const reasonFlag = args.indexOf('--reason');
  const reason: string | undefined = reasonFlag >= 0 ? args[reasonFlag + 1] : undefined;

  // All RPC calls are wrapped in a single try/catch. Any transport or protocol
  // error surfaces a consistent, actionable error message.
  try {
    switch (subcommand) {
      case 'status': {
        const raw = await rpc(transport, 'review.status', {});
        const outer = unwrapResult(raw);
        if (!outer.ok) {
          process.stderr.write(`Error: ${outer.error?.message ?? String(raw)}\n`);
          process.exit(1);
        }
        const r = outer.result as ReviewStatusResult;
        if (!r.active) {
          process.stdout.write('No active review.\n');
        } else {
          process.stdout.write(`Active review: ${r.file ?? '(unknown)'}\n`);
          process.stdout.write(
            `  Total hunks: ${r.total}  \u2713 ${r.accepted} accepted  \u2717 ${r.rejected} rejected  ? ${r.undecided} undecided\n`,
          );
        }
        break;
      }

      case 'accept': {
        const params: Record<string, unknown> = {};
        if (idx !== undefined && !isNaN(idx)) params.idx = idx;
        const raw = await rpc(transport, 'review.accept', params);
        const outer = unwrapResult(raw);
        if (!outer.ok) {
          process.stderr.write(`Error: ${outer.error?.message ?? String(raw)}\n`);
          process.exit(1);
        }
        const r = outer.result as ReviewMutateResult;
        if (!r.ok) {
          process.stderr.write(`Failed: ${r.error ?? 'unknown'}\n`);
          process.exit(1);
        }
        const remainingAccept = r.next != null ? `(next undecided: hunk ${r.next})` : '(no more undecided)';
        process.stdout.write(`\u2713 Hunk ${r.idx} accepted ${remainingAccept}\n`);
        break;
      }

      case 'reject': {
        const params: Record<string, unknown> = {};
        if (idx !== undefined && !isNaN(idx)) params.idx = idx;
        if (reason) params.reason = reason;
        const raw = await rpc(transport, 'review.reject', params);
        const outer = unwrapResult(raw);
        if (!outer.ok) {
          process.stderr.write(`Error: ${outer.error?.message ?? String(raw)}\n`);
          process.exit(1);
        }
        const r = outer.result as ReviewMutateResult;
        if (!r.ok) {
          process.stderr.write(`Failed: ${r.error ?? 'unknown'}\n`);
          process.exit(1);
        }
        const remainingReject = r.next != null ? `(next undecided: hunk ${r.next})` : '(no more undecided)';
        process.stdout.write(`\u2717 Hunk ${r.idx} rejected ${remainingReject}\n`);
        break;
      }

      case 'accept-all': {
        const raw = await rpc(transport, 'review.accept_all', {});
        const outer = unwrapResult(raw);
        if (!outer.ok) {
          process.stderr.write(`Error: ${outer.error?.message ?? String(raw)}\n`);
          process.exit(1);
        }
        const r = outer.result as ReviewMutateResult;
        if (!r.ok) {
          process.stderr.write(`Failed: ${r.error ?? 'unknown'}\n`);
          process.exit(1);
        }
        process.stdout.write(`\u2713 Accepted all remaining (${r.count} hunks)\n`);
        break;
      }

      case 'reject-all': {
        const params: Record<string, unknown> = {};
        if (reason) params.reason = reason;
        const raw = await rpc(transport, 'review.reject_all', params);
        const outer = unwrapResult(raw);
        if (!outer.ok) {
          process.stderr.write(`Error: ${outer.error?.message ?? String(raw)}\n`);
          process.exit(1);
        }
        const r = outer.result as ReviewMutateResult;
        if (!r.ok) {
          process.stderr.write(`Failed: ${r.error ?? 'unknown'}\n`);
          process.exit(1);
        }
        process.stdout.write(`\u2717 Rejected all remaining (${r.count} hunks)\n`);
        break;
      }

      case 'submit': {
        const raw = await rpc(transport, 'review.submit', {});
        const outer = unwrapResult(raw);
        if (!outer.ok) {
          process.stderr.write(`Error: ${outer.error?.message ?? String(raw)}\n`);
          process.exit(1);
        }
        const r = outer.result as ReviewMutateResult;
        if (!r.ok) {
          process.stderr.write(`Failed: ${r.error ?? 'unknown'}\n`);
          process.exit(1);
        }
        process.stdout.write('Review submitted.\n');
        break;
      }

      case 'next': {
        const raw = await rpc(transport, 'review.next', {});
        const outer = unwrapResult(raw);
        if (!outer.ok) {
          process.stderr.write(`Error: ${outer.error?.message ?? String(raw)}\n`);
          process.exit(1);
        }
        const r = outer.result as ReviewMutateResult;
        if (!r.ok) {
          process.stderr.write(`No undecided hunks remaining.\n`);
          process.exit(1);
        }
        process.stdout.write(`Jumped to hunk ${r.idx}\n`);
        break;
      }

      default:
        process.stderr.write(
          `Unknown review subcommand: ${subcommand}\n` +
            'Usage: neph review <status|accept|reject|accept-all|reject-all|submit|next>\n' +
            '  neph review status\n' +
            '  neph review accept [--idx N]\n' +
            '  neph review reject [--idx N] [--reason "..."]\n' +
            '  neph review accept-all\n' +
            '  neph review reject-all [--reason "..."]\n' +
            '  neph review submit\n' +
            '  neph review next\n',
        );
        process.exit(1);
    }
  } catch (err) {
    // Avoid re-wrapping errors from explicit process.exit() paths.
    // process.exit() throws a specific error type in test mocks; let those propagate.
    if (err instanceof Error && err.message === 'EXIT') throw err;
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(
      `neph review ${subcommand}: RPC failed — ${msg}\n` +
      'Is Neovim running with the neph plugin loaded? Check :NephHealth.\n',
    );
    process.exit(1);
  }
}
