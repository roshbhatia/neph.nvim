// tools/lib/harness-base.ts
// Shared infrastructure for all neph agent harnesses.
// Provides ContentHelper, CupcakeHelper, SessionHelper, and shared types.

import { readFileSync, existsSync } from "node:fs";
import { execFileSync } from "node:child_process";
import { debug } from "./log";
import { createPersistentQueue } from "./neph-run";

// ---------------------------------------------------------------------------
// Shared types
// ---------------------------------------------------------------------------

export interface CupcakeDecision {
  decision: "allow" | "deny" | "block" | "ask" | "modify";
  reason?: string;
  updated_input?: { content?: string; [key: string]: unknown };
}

// ---------------------------------------------------------------------------
// ContentHelper — reconstruct full proposed file content from tool input
// ---------------------------------------------------------------------------

export const ContentHelper = {
  /**
   * Reconstruct the full proposed content for a file-write tool call.
   *
   * Handles:
   * - Direct content field (create_file / write_file)
   * - old_string + new_string replacement (edit_file / apply_patch)
   * - Falls back to new_string or "" when the file is missing or old_string
   *   doesn't match (avoids crashing on edge cases)
   */
  reconstructContent(
    filePath: string,
    toolInput: Record<string, unknown>,
  ): string {
    // Direct content field — used by create_file, write_file
    if (typeof toolInput.content === "string") {
      return toolInput.content;
    }

    const oldStr =
      (toolInput.old_string as string | undefined) ??
      (toolInput.old_str as string | undefined);
    const newStr =
      (toolInput.new_string as string | undefined) ??
      (toolInput.new_str as string | undefined) ??
      "";

    if (oldStr === undefined) {
      // No old_string and no content — nothing to reconstruct
      return newStr;
    }

    // Read the current file
    let current = "";
    try {
      current = readFileSync(filePath, "utf-8");
    } catch {
      debug("harness-base", `reconstructContent: cannot read ${filePath}, using newStr`);
      return newStr;
    }

    if (!current.includes(oldStr)) {
      debug(
        "harness-base",
        `reconstructContent: old_string not found in ${filePath}, returning current content`,
      );
      return current;
    }

    const replaceAll = toolInput.replace_all === true;
    return replaceAll
      ? current.replaceAll(oldStr, newStr)
      : current.replace(oldStr, newStr);
  },
};

// ---------------------------------------------------------------------------
// CupcakeHelper — synchronous Cupcake policy evaluation
// ---------------------------------------------------------------------------

export const CupcakeHelper = {
  /**
   * Run `cupcake eval --harness <harnessName>` with the event as stdin JSON.
   * Returns the parsed decision. On any error (Cupcake not found, eval error,
   * parse error), returns deny so writes fail-closed.
   *
   * Synchronous by design — hook protocol is synchronous (stdin/stdout).
   * Timeout: 600s to allow for slow interactive reviews.
   */
  cupcakeEval(
    harnessName: string,
    event: Record<string, unknown>,
  ): CupcakeDecision {
    debug("harness-base", `cupcakeEval: harness=${harnessName} event=${JSON.stringify(event).slice(0, 200)}`);
    try {
      const stdout = execFileSync(
        "cupcake",
        ["eval", "--harness", harnessName],
        {
          input: JSON.stringify(event),
          encoding: "utf-8",
          timeout: 600_000,
          stdio: ["pipe", "pipe", "pipe"],
        },
      );
      const result = JSON.parse(stdout.trim()) as CupcakeDecision;
      debug("harness-base", `cupcakeEval: decision=${result.decision}`);
      return result;
    } catch (err: unknown) {
      const e = err as { status?: number; stderr?: Buffer | string; message?: string };
      // Exit code 2 = explicit deny from Cupcake
      if (e.status === 2) {
        const reason = e.stderr?.toString().trim() || "Cupcake denied";
        debug("harness-base", `cupcakeEval: explicit deny (exit 2): ${reason}`);
        return { decision: "deny", reason };
      }
      // Cupcake not on PATH or eval error — fail-closed
      const msg = e.message ?? String(err);
      debug("harness-base", `cupcakeEval: error (fail-closed): ${msg}`);
      return { decision: "deny", reason: `Cupcake eval failed: ${msg}` };
    }
  },

  /** Check if cupcake is available on PATH. */
  isAvailable(): boolean {
    try {
      execFileSync("cupcake", ["--version"], { stdio: "ignore", timeout: 3000 });
      return true;
    } catch {
      return false;
    }
  },
};

// ---------------------------------------------------------------------------
// NvimGuard — detect whether a Neovim instance is reachable
// ---------------------------------------------------------------------------

/**
 * Returns true if a Neovim socket is reachable from this process.
 * Uses the same env var lookup as neph-cli's index.ts.
 * Synchronous and fast (no spawns, no network).
 */
export function isNvimAvailable(): boolean {
  const socketPath = process.env.NVIM ?? process.env.NVIM_SOCKET_PATH;
  if (!socketPath) return false;
  try {
    return existsSync(socketPath);
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// SessionHelper — lifecycle state signals to Neovim
// ---------------------------------------------------------------------------

export interface SessionSignals {
  setActive(): void;
  unsetActive(): void;
  setRunning(): void;
  unsetRunning(): void;
  checktime(): void;
  close(): void;
}

/**
 * Create session signals for an agent backed by a persistent neph connect
 * subprocess. The agentName determines the vim.g key names:
 *   <agentName>_active   — session is open
 *   <agentName>_running  — agent loop is actively working
 *
 * Caller must call .close() on session end to drain the queue.
 */
export function createSessionSignals(agentName: string): SessionSignals {
  const pq = createPersistentQueue();

  return {
    setActive() {
      debug("harness-base", `${agentName}: setActive`);
      pq.call("set", `${agentName}_active`, "true");
    },
    unsetActive() {
      debug("harness-base", `${agentName}: unsetActive`);
      pq.call("unset", `${agentName}_active`);
    },
    setRunning() {
      debug("harness-base", `${agentName}: setRunning`);
      pq.call("set", `${agentName}_running`, "true");
    },
    unsetRunning() {
      debug("harness-base", `${agentName}: unsetRunning`);
      pq.call("unset", `${agentName}_running`);
    },
    checktime() {
      debug("harness-base", `${agentName}: checktime`);
      pq.call("checktime");
    },
    close() {
      debug("harness-base", `${agentName}: close`);
      pq.close();
    },
  };
}
