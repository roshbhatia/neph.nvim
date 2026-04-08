import type { ExtensionAPI, EditToolInput, WriteToolInput } from "@mariozechner/pi-coding-agent";
import { createWriteTool, createEditTool } from "@mariozechner/pi-coding-agent";
import { readFileSync } from "node:fs";
import { resolve, relative, basename } from "node:path";
import { execFileSync } from "node:child_process";
import process from "node:process";

// Cupcake-based Pi harness for neph.nvim.
//
// Requires Cupcake to be installed. No fallbacks.
// Write/edit tools are intercepted and routed through Cupcake policy evaluation.
// Cupcake's neph_review signal opens interactive vimdiff in Neovim.

interface CupcakeResponse {
  decision: "allow" | "deny" | "block" | "ask";
  reason?: string;
  updated_input?: { content?: string };
}

function assertCupcakeInstalled(): void {
  try {
    execFileSync("cupcake", ["--version"], { stdio: "ignore", timeout: 3000 });
  } catch {
    throw new Error(
      "Cupcake is not installed. Pi integration requires Cupcake.\n" +
      "Install: curl -fsSL https://get.eqtylab.io/cupcake | bash"
    );
  }
}

function runCupcakeEval(event: Record<string, unknown>): CupcakeResponse {
  const stdout = execFileSync("cupcake", ["eval", "--harness", "pi"], {
    input: JSON.stringify(event),
    encoding: "utf-8",
    timeout: 600_000,
    stdio: ["pipe", "pipe", "pipe"],
  });
  return JSON.parse(stdout.trim());
}

function evaluateWrite(
  filePath: string,
  content: string,
  toolName: string,
): { decision: string; content?: string; reason?: string } {
  const event = {
    hook_event_name: "PreToolUse",
    tool_name: toolName,
    tool_input: { file_path: filePath, content },
    session_id: process.pid.toString(),
    cwd: process.cwd(),
  };

  let result: CupcakeResponse;
  try {
    result = runCupcakeEval(event);
  } catch (err: unknown) {
    const e = err as { status?: number; stderr?: Buffer | string; message?: string };
    if (e.status === 2) {
      return { decision: "reject", reason: e.stderr?.toString() || "Cupcake blocked" };
    }
    // Cupcake error — reject, don't silently allow
    return { decision: "reject", reason: `Cupcake eval failed: ${e.message ?? String(err)}` };
  }

  if (result.decision === "deny" || result.decision === "block") {
    return { decision: "reject", reason: result.reason };
  }
  if (result.updated_input?.content !== undefined) {
    return { decision: "partial", content: result.updated_input.content };
  }
  return { decision: "accept", content };
}

export default function (pi: ExtensionAPI) {
  let toolsRegistered = false;

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
        const writeParams = params as WriteToolInput;
        const filePath = resolve(ctx.cwd, writeParams.path);
        const newContent = writeParams.content;

        const result = evaluateWrite(filePath, newContent, "write");

        if (result.decision === "reject") {
          return {
            content: [{ type: "text" as const, text: `Write rejected: ${result.reason ?? ""}` }],
            details: undefined,
          };
        }

        const finalContent = result.content ?? newContent;
        const writeResult = await createWriteTool(ctx.cwd).execute(
          toolCallId,
          { ...writeParams, content: finalContent },
          signal,
          onUpdate,
        );

        if (result.decision === "partial") {
          return {
            content: [
              ...(writeResult as { content: { type: "text"; text: string }[] }).content,
              { type: "text" as const, text: "Note: partial accept" },
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
        "Edit a file by replacing exact text. The oldText must match exactly (including whitespace).",
      parameters: createEditTool(process.cwd()).parameters,

      async execute(toolCallId, params, signal, onUpdate, ctx) {
        const editParams = params as EditToolInput;
        const filePath = resolve(ctx.cwd, editParams.path);

        // Reconstruct full new content by applying all edits sequentially
        let newContent: string;
        try {
          let currentContent = readFileSync(filePath, "utf-8");
          for (const { oldText, newText } of editParams.edits) {
            if (currentContent.includes(oldText)) {
              currentContent = currentContent.replaceAll(oldText, newText);
            }
          }
          newContent = currentContent;
        } catch {
          newContent = editParams.edits.map((e) => e.newText).join("\n");
        }

        const result = evaluateWrite(filePath, newContent, "edit");

        if (result.decision === "reject") {
          return {
            content: [{ type: "text" as const, text: `Edit rejected: ${result.reason ?? ""}` }],
            details: undefined,
          };
        }

        // If content was modified by review, write full content instead of edit
        const actualResult = result.content
          ? await createWriteTool(ctx.cwd).execute(
              toolCallId,
              { path: editParams.path, content: result.content },
              signal,
              onUpdate,
            )
          : await createEditTool(ctx.cwd).execute(toolCallId, editParams, signal, onUpdate);

        if (result.decision === "partial") {
          return {
            content: [
              ...(actualResult as { content: { type: "text"; text: string }[] }).content,
              { type: "text" as const, text: "Note: partial accept" },
            ],
            details: (actualResult as { details: unknown }).details,
          };
        }
        return actualResult;
      },
    });
  }

  // --- Session lifecycle ---

  pi.on("session_start", async (_event, ctx) => {
    assertCupcakeInstalled();
    ctx.ui.setStatus("nvim", "🗿NEPH");
    registerTools();

    try {
      execFileSync("neph-cli", ["set", "pi_active", "true"], { timeout: 5000, stdio: "ignore" });
    } catch {}
  });

  pi.on("session_shutdown", () => {
    try {
      execFileSync("neph-cli", ["set", "pi_active", ""], { timeout: 5000, stdio: "ignore" });
    } catch {}
  });

  pi.on("agent_start", async () => {
    try {
      execFileSync("neph-cli", ["set", "pi_running", "true"], { timeout: 5000, stdio: "ignore" });
    } catch {}
  });

  pi.on("agent_end", async (_event, ctx) => {
    try {
      execFileSync("neph-cli", ["set", "pi_running", ""], { timeout: 5000, stdio: "ignore" });
      execFileSync("neph-cli", ["set", "pi_reading", ""], { timeout: 5000, stdio: "ignore" });
      execFileSync("neph-cli", ["checktime"], { timeout: 5000, stdio: "ignore" });
      ctx.ui.setStatus("nvim-reading", "");
    } catch {}
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "read") {
      const path = event.input.path as string | undefined;
      if (path) {
        const abs = resolve(ctx.cwd, path);
        const rel = relative(ctx.cwd, abs);
        const shortPath = rel.startsWith("..") ? basename(abs) : rel;
        try {
          execFileSync("neph-cli", ["set", "pi_reading", shortPath], { timeout: 5000, stdio: "ignore" });
        } catch {}
        ctx.ui.setStatus("nvim-reading", `󰈔 ${shortPath}`);
      }
    }
  });

  pi.on("tool_result", async (event) => {
    if (event.toolName === "write" || event.toolName === "edit") {
      try {
        execFileSync("neph-cli", ["checktime"], { timeout: 5000, stdio: "ignore" });
      } catch {}
    }
  });
}
