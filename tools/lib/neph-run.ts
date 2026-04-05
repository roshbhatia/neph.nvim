import { spawn, ChildProcess } from "node:child_process";
import process from "node:process";
import { Buffer } from "node:buffer";
import { debug as log } from "./log";

export interface HunkResult {
  index: number;
  decision: "accept" | "reject";
  reason?: string;
}

export interface ReviewEnvelope {
  schema: "review/v1";
  decision: "accept" | "reject" | "partial";
  content: string;
  hunks: HunkResult[];
  reason?: string;
}

/** Timeout for fire-and-forget neph calls (ms). Interactive review has no timeout. */
export const NEPH_TIMEOUT_MS = 5_000;

/**
 * Run the neph CLI and await exit. stdin is optional; stdout is returned.
 * timeoutMs: kill the child and reject after this many ms. Omit for interactive calls.
 */
export function nephRun(
  args: string[],
  stdin?: string,
  timeoutMs?: number,
): Promise<string> {
  return new Promise((res, rej) => {
    log("neph-run", `spawn: neph ${args.join(" ")}`);
    const child = spawn("neph", args, {
      stdio: ["pipe", "pipe", "pipe"],
      env: process.env,
    });
    const out: Buffer[] = [];
    const err: Buffer[] = [];
    child.stdout.on("data", (d: Buffer) => out.push(d));
    child.stderr.on("data", (d: Buffer) => err.push(d));
    if (stdin !== undefined) child.stdin.write(stdin, "utf-8");
    child.stdin.end();

    let timer: ReturnType<typeof setTimeout> | undefined;
    if (timeoutMs !== undefined && isFinite(timeoutMs)) {
      timer = setTimeout(() => {
        child.kill("SIGTERM");
        rej(
          new Error(
            `neph timed out after ${timeoutMs}ms (args: ${args.join(" ")})`,
          ),
        );
      }, timeoutMs);
    }

    child.on("error", (e) => {
      if (timer !== undefined) clearTimeout(timer);
      log("neph-run", `spawn error: ${e.message} (args: ${args.join(" ")})`);
      rej(e);
    });
    child.on("close", (code) => {
      if (timer !== undefined) clearTimeout(timer);
      if (code !== 0) {
        const stderr = Buffer.concat(err).toString().trim();
        log("neph-run", `exit ${code}: ${stderr || "(no stderr)"} (args: ${args.join(" ")})`);
        rej(new Error(stderr || `neph exited ${code}`));
      } else {
        const stdout = Buffer.concat(out).toString();
        log("neph-run", `exit 0 (args: ${args.join(" ")}, stdout_len=${stdout.length})`);
        res(stdout);
      }
    });
  });
}

/**
 * Create a fire-and-forget neph command queue.
 * Commands are executed serially in dispatch order. Errors are swallowed.
 */
export function createNephQueue(): (...args: string[]) => void {
  let queue: Promise<void> = Promise.resolve();
  return (...args: string[]): void => {
    queue = queue.then(() =>
      nephRun(args, undefined, NEPH_TIMEOUT_MS).catch(() => {
        /* nvim may have closed */
      }),
    );
  };
}

/**
 * Create a fire-and-forget command queue backed by a persistent
 * `neph connect` subprocess.  Eliminates per-call process spawn overhead.
 *
 * Falls back to per-call spawn if the persistent process dies unexpectedly.
 * The caller should call .close() when done (e.g. on session end).
 */
export function createPersistentQueue(): {
  call: (...args: string[]) => void;
  close: () => void;
} {
  let proc: ChildProcess | null = null;
  let nextId = 1;
  let queue: Promise<void> = Promise.resolve();
  const pending = new Map<number, { resolve: () => void; reject: (e: Error) => void }>();
  let outBuf = '';
  let closed = false;

  function startProc(): void {
    if (closed) return;
    outBuf = ''; // reset partial-line buffer so stale bytes don't corrupt new proc
    proc = spawn('neph', ['connect'], {
      stdio: ['pipe', 'pipe', 'pipe'],
      env: process.env,
    });

    (proc.stdout as import('stream').Readable).setEncoding('utf8');
    proc.stdout?.on('data', (chunk: string) => {
      outBuf += chunk;
      const lines = outBuf.split('\n');
      outBuf = lines.pop() ?? '';
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed) continue;
        try {
          const msg: { id: number; ok: boolean; error?: string } = JSON.parse(trimmed);
          const p = pending.get(msg.id);
          if (p) {
            pending.delete(msg.id);
            if (msg.ok) {
              p.resolve();
            } else {
              p.reject(new Error(msg.error ?? 'rpc error'));
            }
          }
        } catch { /* malformed line */ }
      }
    });

    proc.on('error', () => {
      proc = null;
      for (const [, p] of pending) p.reject(new Error('neph connect error'));
      pending.clear();
    });

    proc.on('close', () => {
      proc = null;
      for (const [, p] of pending) p.reject(new Error('neph connect closed'));
      pending.clear();
    });
  }

  function sendCommand(method: string, params: Record<string, unknown>): Promise<void> {
    return new Promise((resolve, reject) => {
      if (closed) { reject(new Error('queue closed')); return; }
      if (!proc || !proc.stdin?.writable) startProc();
      if (!proc?.stdin?.writable) { resolve(); return; } // failed to start — fail-open
      const id = nextId++;
      pending.set(id, { resolve, reject });
      try {
        proc.stdin.write(JSON.stringify({ id, method, params }) + '\n');
      } catch (e) {
        pending.delete(id);
        reject(e as Error);
      }
    });
  }

  const call = (...args: string[]): void => {
    let method = '';
    let params: Record<string, unknown> = {};
    switch (args[0]) {
      case 'set':    method = 'status.set';   params = { name: args[1], value: args[2] }; break;
      case 'unset':  method = 'status.unset'; params = { name: args[1] }; break;
      case 'checktime': method = 'buffers.check'; break;
      default:
        log('persistent-queue', `unknown command dropped: ${args[0]}`);
        return;
    }
    queue = queue.then(() =>
      sendCommand(method, params).catch(() => { /* fire-and-forget */ })
    );
  };

  const close = (): void => {
    closed = true;
    if (proc?.stdin?.writable) proc.stdin.end();
    proc = null;
    // reject all in-flight requests so callers don't hang forever
    for (const [, p] of pending) p.reject(new Error('queue closed'));
    pending.clear();
  };

  return { call, close };
}

/**
 * Blocking vimdiff review. Proposed content is sent via stdin.
 * Returns the user's decision plus the final buffer content (may be partial).
 * No timeout — this is interactive and waits for the user.
 */
export async function review(
  filePath: string,
  content: string,
  agent?: string,
): Promise<ReviewEnvelope> {
  try {
    const json = await nephRun(
      ["review"],
      JSON.stringify({ path: filePath, content, agent }),
    );
    return JSON.parse(json) as ReviewEnvelope;
  } catch {
    return {
      schema: "review/v1",
      decision: "reject",
      content: "",
      hunks: [],
      reason: "Review failed or timed out",
    };
  }
}

/**
 * Trigger a selection list in Neovim via CLI.
 */
export async function uiSelect(
  title: string,
  options: string[],
): Promise<string | undefined> {
  try {
    const result = await nephRun(["ui-select", title, ...options]);
    return result.trim() || undefined;
  } catch {
    return undefined;
  }
}

/**
 * Trigger a text input prompt in Neovim via CLI.
 */
export async function uiInput(
  title: string,
  defaultValue?: string,
): Promise<string | undefined> {
  try {
    const args = ["ui-input", title];
    if (defaultValue) args.push(defaultValue);
    const result = await nephRun(args);
    return result.trim() || undefined;
  } catch {
    return undefined;
  }
}

/**
 * Trigger a notification in Neovim via CLI (fire-and-forget).
 */
export function uiNotify(message: string, level?: string): void {
  const args = ["ui-notify", message];
  if (level) args.push(level);
  nephRun(args, undefined, NEPH_TIMEOUT_MS).catch(() => {
    /* ignore */
  });
}
