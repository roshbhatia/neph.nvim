// neph context — read the broadcast snapshot written by the in-Neovim
// context_broadcast module. No socket required: the file lives at a
// well-known XDG path and is updated continuously while Neovim runs.

import * as fs from 'node:fs';
import * as os from 'node:os';
import * as path from 'node:path';

interface ContextOptions {
  maxAgeMs: number;
  field: string | null;
}

const DEFAULT_MAX_AGE_MS = 5_000;

function broadcastPath(): string {
  // Mirror Neovim's vim.fn.stdpath("state") resolution:
  //   * macOS / Linux: $XDG_STATE_HOME or ~/.local/state, then `/nvim/`
  //   * Linux fallback honours the XDG spec
  //   * Note: stdpath("state") on Neovim already includes `/nvim/`,
  //     so we don't append a second `nvim` segment.
  const xdg = process.env.XDG_STATE_HOME;
  const stateDir = xdg && xdg.length > 0
    ? path.join(xdg, 'nvim')
    : path.join(os.homedir(), '.local', 'state', 'nvim');
  return path.join(stateDir, 'neph', 'context.json');
}

function parseOptions(args: string[]): ContextOptions {
  const opts: ContextOptions = { maxAgeMs: DEFAULT_MAX_AGE_MS, field: null };
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === '--max-age-ms') {
      const value = Number(args[++i]);
      if (!Number.isFinite(value) || value < 0) {
        throw new Error(`--max-age-ms expects a non-negative number, got "${args[i]}"`);
      }
      opts.maxAgeMs = value;
    } else if (arg === '--field') {
      const value = args[++i];
      if (!value) {
        throw new Error('--field expects a key path argument');
      }
      opts.field = value;
    } else {
      throw new Error(`unknown flag: ${arg}`);
    }
  }
  return opts;
}

function pickField(payload: unknown, keyPath: string): unknown {
  let current: unknown = payload;
  for (const part of keyPath.split('.')) {
    if (current && typeof current === 'object') {
      current = (current as Record<string, unknown>)[part];
    } else {
      return undefined;
    }
  }
  return current;
}

function emitField(value: unknown): void {
  if (value === undefined || value === null) {
    process.stdout.write('\n');
    return;
  }
  if (typeof value === 'string' || typeof value === 'number' || typeof value === 'boolean') {
    process.stdout.write(`${value}\n`);
    return;
  }
  process.stdout.write(`${JSON.stringify(value)}\n`);
}

export async function runContextCommand(args: string[]): Promise<void> {
  const sub = args[0];
  if (sub !== 'current') {
    process.stderr.write(
      `Usage: neph context current [--max-age-ms <ms>] [--field <key.path>]\n`
    );
    process.exit(1);
    return;
  }

  let opts: ContextOptions;
  try {
    opts = parseOptions(args.slice(1));
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(`neph context: ${msg}\n`);
    process.exit(1);
    return;
  }

  const target = broadcastPath();
  if (!fs.existsSync(target)) {
    process.stderr.write(JSON.stringify({ error: 'no_snapshot', path: target }) + '\n');
    process.exit(1);
    return;
  }

  let content: string;
  try {
    content = fs.readFileSync(target, 'utf8');
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(JSON.stringify({ error: 'read_failed', path: target, message: msg }) + '\n');
    process.exit(1);
    return;
  }

  let payload: Record<string, unknown>;
  try {
    payload = JSON.parse(content) as Record<string, unknown>;
  } catch (err) {
    const msg = err instanceof Error ? err.message : String(err);
    process.stderr.write(JSON.stringify({ error: 'parse_failed', path: target, message: msg }) + '\n');
    process.exit(1);
    return;
  }

  const ts = typeof payload.ts === 'number' ? payload.ts : 0;
  // Compare on the same clock the snapshot was written with: vim.uv.hrtime()
  // is monotonic (since process start, not wall clock), so we have to use
  // process.hrtime.bigint() for parity. This is best-effort — when neph and
  // the CLI run on the same machine the drift is bounded by IO latency.
  const nowMs = Number(process.hrtime.bigint() / 1_000_000n);
  const ageMs = nowMs - ts;
  if (opts.maxAgeMs > 0 && ageMs > opts.maxAgeMs) {
    process.stderr.write(JSON.stringify({ error: 'stale_snapshot', age_ms: ageMs, max_age_ms: opts.maxAgeMs }) + '\n');
    process.exit(1);
    return;
  }

  if (opts.field) {
    emitField(pickField(payload, opts.field));
    return;
  }
  process.stdout.write(content + (content.endsWith('\n') ? '' : '\n'));
}
