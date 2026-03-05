import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { createWriteTool, createEditTool } from "@mariozechner/pi-coding-agent";
import { readFileSync } from "node:fs";
import { resolve, relative, basename } from "node:path";
import { spawn } from "node:child_process";
import process from "node:process";
import { Buffer } from "node:buffer";

// Neovim integration for pi.
//
// Requires `shim` in PATH (installed via home-manager as a uv Python script).
// Only activates when NVIM_SOCKET_PATH is set — Neovim exports it on startup
// and terminal panes spawned from within Neovim inherit it automatically.
// When absent the extension is a complete no-op.
//
// write / edit tools are overridden to open a vimdiff review in Neovim before
// any disk write. The shim speaks msgpack-rpc directly to nvim_exec_lua, which
// is a blocking RPC call — the hunk review (vim.fn.confirm / vim.fn.input)
// happens entirely inside that call, and the result comes back as JSON on
// stdout. No polling, no temp files, no race conditions.
//
// Per-hunk choices: Accept / Reject (+ optional reason) / Accept all / Reject all
// Partial acceptance is supported: only accepted hunks reach disk.
//
// vim.g globals for statusline integration:
//   vim.g.pi_active   — set while a pi session is live
//   vim.g.pi_running  — set while the agent is processing a turn
//   vim.g.pi_reading  — path of file currently being read by the agent (nil otherwise)

interface NvimPreviewResult {
  decision: "accept" | "reject";
  content?: string;
  reason?: string;
}

// Timeout for fire-and-forget shim calls (ms). Interactive preview has no timeout.
export const SHIM_TIMEOUT_MS = 15_000;

export default function (pi: ExtensionAPI) {
  let toolsRegistered = false;

  // Serial queue for fire-and-forget shim calls. Each call is appended via
  // .then() so commands reach nvim in the order they were dispatched, and a
  // single hung call cannot starve subsequent ones beyond its own timeout.
  let _shimQueue: Promise<void> = Promise.resolve();

  // Run the shim and await exit. stdin is optional; stdout is returned.
  // timeoutMs: kill the child and reject after this many ms. Omit for interactive calls.
  function shimRun(args: string[], stdin?: string, timeoutMs?: number): Promise<string> {
    return new Promise((res, rej) => {
      const child = spawn("shim", args, {
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
          rej(new Error(`shim timed out after ${timeoutMs}ms (args: ${args.join(" ")})`));
        }, timeoutMs);
      }

      child.on("error", (e) => {
        if (timer !== undefined) clearTimeout(timer);
        rej(e);
      });
      child.on("close", (code) => {
        if (timer !== undefined) clearTimeout(timer);
        if (code !== 0) rej(new Error(Buffer.concat(err).toString().trim() || `shim exited ${code}`));
        else res(Buffer.concat(out).toString());
      });
    });
  }

  // Fire-and-forget: enqueue a shim command, swallow errors.
  // Commands are executed serially in dispatch order.
  function shim(...args: string[]): void {
    _shimQueue = _shimQueue.then(() =>
      shimRun(args, undefined, SHIM_TIMEOUT_MS).catch(() => { /* nvim may have closed */ })
    );
  }

  // Blocking vimdiff review. Proposed content is sent via stdin.
  // Returns the user's decision plus the final buffer content (may be partial).
  // No timeout — this is interactive and waits for the user.
  async function preview(
    filePath: string,
    content: string,
  ): Promise<NvimPreviewResult> {
    try {
      const json = await shimRun(["preview", filePath], content);
      return JSON.parse(json) as NvimPreviewResult;
    } catch {
      return { decision: "reject", reason: "Preview failed or timed out" };
    }
  }

  function registerTools() {
    if (toolsRegistered) return;
    toolsRegistered = true;

    pi.registerTool({
      name: "write",
      label: "write",
      description:
        "Write content to a file. Creates the file if it doesn't exist, overwrites if it does. Automatically creates parent directories.",
      parameters: createWriteTool(process.cwd()).parameters,

      async execute(toolCallId, params, signal, onUpdate, ctx) {
        const filePath = resolve(ctx.cwd, params.path as string);
        const newContent = params.content as string;

        const result = await preview(filePath, newContent);

        if (result.decision === "reject") {
          shim("revert", filePath);
          const reason = result.reason ? `: ${result.reason}` : "";
          return {
            content: [{ type: "text", text: `Write rejected${reason}` }],
            details: {},
          };
        }

        const finalContent = result.content ?? newContent;
        const writeResult = await createWriteTool(ctx.cwd).execute(
          toolCallId,
          { ...params, content: finalContent },
          signal,
          onUpdate,
        );
        // Surface partial-rejection notes back to the agent so it knows
        // which hunks were not applied and why.
        if (result.reason) {
          return {
            content: [
              ...(writeResult as { content: { type: string; text: string }[] }).content,
              { type: "text", text: `Note: some hunks were rejected — ${result.reason}` },
            ],
            details: (writeResult as { details: unknown }).details,
          };
        }
        return writeResult;
      },
    });

    pi.registerTool({
      name: "edit",
      label: "edit",
      description:
        "Edit a file by replacing exact text. The oldText must match exactly (including whitespace). Use this for precise, surgical edits.",
      // Use createEditTool schema: { path, oldText, newText }
      parameters: createEditTool(process.cwd()).parameters,

      async execute(toolCallId, params, signal, onUpdate, ctx) {
        const filePath = resolve(ctx.cwd, params.path as string);
        const oldText = params.oldText as string;
        const newText = params.newText as string;

        let currentContent: string;
        try {
          currentContent = readFileSync(filePath, "utf-8");
        } catch {
          return {
            content: [{ type: "text", text: `Cannot read ${params.path as string}` }],
            details: {},
          };
        }

        if (!currentContent.includes(oldText)) {
          return {
            content: [{ type: "text", text: `Edit failed: oldText not found in ${params.path as string}` }],
            details: {},
          };
        }

        const newContent = currentContent.replace(oldText, newText);
        const result = await preview(filePath, newContent);

        if (result.decision === "reject") {
          shim("revert", filePath);
          const reason = result.reason ? `: ${result.reason}` : "";
          return {
            content: [{ type: "text", text: `Edit rejected${reason}` }],
            details: {},
          };
        }

        const finalContent = result.content ?? newContent;
        // Delegate final write to createEditTool so the agent gets a proper diff result
        const writeResult = await createEditTool(ctx.cwd).execute(
          toolCallId,
          { path: params.path as string, oldText, newText: finalContent },
          signal,
          onUpdate,
        );
        if (result.reason) {
          return {
            content: [
              ...(writeResult as { content: { type: string; text: string }[] }).content,
              { type: "text", text: `Note: some hunks were rejected — ${result.reason}` },
            ],
            details: (writeResult as { details: unknown }).details,
          };
        }
        return writeResult;
      },
    });
  }

  // --- Session lifecycle: activate only when nvim socket is present ---

  pi.on("session_start", (_event, ctx) => {
    if (!process.env.NVIM_SOCKET_PATH) return;
    ctx.ui.setStatus("nvim", "nvim");
    shim("set", "pi_active", "true");
    registerTools();
  });

  pi.on("session_shutdown", () => {
    if (!process.env.NVIM_SOCKET_PATH) return;
    shim("close-tab");
    shim("unset", "pi_active");
    shim("unset", "pi_running");
  });

  pi.on("agent_start", () => {
    if (!process.env.NVIM_SOCKET_PATH) return;
    shim("set", "pi_running", "true");
  });

  pi.on("agent_end", (_event, ctx) => {
    if (!process.env.NVIM_SOCKET_PATH) return;
    shim("unset", "pi_running");
    shim("unset", "pi_reading");
    shim("checktime");
    // Note: close-tab is intentionally NOT called here — the agent tab
    // persists across turns and is only closed at session_shutdown.
    ctx.ui.setStatus("nvim-reading", "");
  });

  pi.on("tool_call", (event, ctx) => {
    if (!process.env.NVIM_SOCKET_PATH) return;
    if (event.toolName === "read") {
      const path = event.input.path as string | undefined;
      if (path) {
        // Compute a short display path (relative to cwd when possible, otherwise basename)
        const abs = resolve(ctx.cwd, path);
        const rel = relative(ctx.cwd, abs);
        const shortPath = rel.startsWith("..") ? basename(abs) : rel;
        // Set vim.g.pi_reading so users can surface it in their statusline.
        // JSON.stringify produces a valid Lua double-quoted string literal.
        shim("set", "pi_reading", JSON.stringify(shortPath));
        ctx.ui.setStatus("nvim-reading", `📖 ${shortPath}`);
      }
    }
  });

  pi.on("tool_result", (event) => {
    if (!process.env.NVIM_SOCKET_PATH) return;
    if (event.toolName === "write" || event.toolName === "edit") {
      shim("checktime");
    }
  });
}
