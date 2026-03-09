import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { createWriteTool, createEditTool } from "@mariozechner/pi-coding-agent";
import { readFileSync } from "node:fs";
import { resolve, relative, basename } from "node:path";
import process from "node:process";
import { NephClient } from "../lib/neph-client";
import { debug as log } from "../lib/log";

// Neovim integration for pi.
//
// Uses a persistent socket connection to Neovim via NephClient.
// Prompts are received via neph:prompt notifications (push, no polling).
//
// write / edit tools are overridden to open a non-blocking vimdiff review in
// Neovim before any disk write.
//
// Per-hunk choices: Accept / Reject / Accept all / Reject all
// decision: "accept" | "reject" | "partial" (some hunks accepted, some rejected)
//
// vim.g globals for statusline integration:
//   vim.g.pi_active   — set by bus registration while a pi session is live
//   vim.g.pi_running  — set while the agent is processing a turn
//   vim.g.pi_reading  — path of file currently being read by the agent (nil otherwise)

export default function (pi: ExtensionAPI) {
  let toolsRegistered = false;
  const neph = new NephClient();

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

        const result = await neph.review(filePath, newContent);

        if (result.decision === "reject") {
          const reason = result.reason ? `: ${result.reason}` : "";
          return {
            content: [
              { type: "text" as const, text: `Write rejected${reason}` },
            ],
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
        const notes: string[] = [];
        if (result.decision === "partial") notes.push("partial accept");
        if (result.reason) notes.push(result.reason);
        if (notes.length > 0) {
          return {
            content: [
              ...(writeResult as { content: { type: "text"; text: string }[] })
                .content,
              { type: "text" as const, text: `Note: ${notes.join(" — ")}` },
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
            content: [
              {
                type: "text" as const,
                text: `Cannot read ${params.path as string}`,
              },
            ],
            details: {},
          };
        }

        if (!currentContent.includes(oldText)) {
          return {
            content: [
              {
                type: "text" as const,
                text: `Edit failed: oldText not found in ${params.path as string}`,
              },
            ],
            details: {},
          };
        }

        const newContent = currentContent.replace(oldText, newText);
        const result = await neph.review(filePath, newContent);

        if (result.decision === "reject") {
          const reason = result.reason ? `: ${result.reason}` : "";
          return {
            content: [
              { type: "text" as const, text: `Edit rejected${reason}` },
            ],
            details: {},
          };
        }

        const finalContent = result.content ?? newContent;
        const writeResult = await createWriteTool(ctx.cwd).execute(
          toolCallId,
          { path: params.path as string, content: finalContent },
          signal,
          onUpdate,
        );
        const notes: string[] = [];
        if (result.decision === "partial") notes.push("partial accept");
        if (result.reason) notes.push(result.reason);
        if (notes.length > 0) {
          return {
            content: [
              ...(writeResult as { content: { type: "text"; text: string }[] })
                .content,
              { type: "text" as const, text: `Note: ${notes.join(" — ")}` },
            ],
            details: (writeResult as { details: unknown }).details,
          };
        }
        return writeResult;
      },
    });
  }

  // --- Session lifecycle ---

  pi.on("session_start", async (_event, ctx) => {
    ctx.ui.setStatus("nvim", "🗿NEPH");
    try {
      await neph.connect();
      await neph.register("pi");
      log("pi", "connected and registered with bus");
    } catch (e) {
      log(
        "pi",
        `connection failed: ${e instanceof Error ? e.message : String(e)}`,
      );
    }
    registerTools();

    // Listen for prompts from Neovim
    neph.onPrompt((text) => {
      log("pi", `received prompt (len=${text.length})`);
      pi.sendUserMessage(text);
    });
  });

  pi.on("session_shutdown", () => {
    neph.disconnect();
  });

  pi.on("agent_start", async () => {
    await neph.setStatus("pi_running", "true");
  });

  pi.on("agent_end", async (_event, ctx) => {
    await neph.unsetStatus("pi_running");
    await neph.unsetStatus("pi_reading");
    await neph.checktime();
    ctx.ui.setStatus("nvim-reading", "");
  });

  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "read") {
      const path = event.input.path as string | undefined;
      if (path) {
        const abs = resolve(ctx.cwd, path);
        const rel = relative(ctx.cwd, abs);
        const shortPath = rel.startsWith("..") ? basename(abs) : rel;
        await neph.setStatus("pi_reading", shortPath);
        ctx.ui.setStatus("nvim-reading", `󰈔 ${shortPath}`);
      }
    }
  });

  pi.on("tool_result", async (event) => {
    if (event.toolName === "write" || event.toolName === "edit") {
      await neph.checktime();
    }
  });
}
