import { spawn } from "node:child_process";
import process from "node:process";
import { Buffer } from "node:buffer";

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
      rej(e);
    });
    child.on("close", (code) => {
      if (timer !== undefined) clearTimeout(timer);
      if (code !== 0)
        rej(
          new Error(
            Buffer.concat(err).toString().trim() || `neph exited ${code}`,
          ),
        );
      else res(Buffer.concat(out).toString());
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
 * Blocking vimdiff review. Proposed content is sent via stdin.
 * Returns the user's decision plus the final buffer content (may be partial).
 * No timeout — this is interactive and waits for the user.
 */
export async function review(
  filePath: string,
  content: string,
): Promise<ReviewEnvelope> {
  try {
    const json = await nephRun(["review", filePath], content);
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
