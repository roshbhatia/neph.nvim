import type { ExtensionAPI } from "@mariozechner/pi-coding-agent";
import { createWriteTool, createEditTool } from "@mariozechner/pi-coding-agent";
import { readFileSync } from "node:fs";
import { resolve, relative, basename } from "node:path";
import process from "node:process";
import { createNephQueue, nephRun, NEPH_TIMEOUT_MS, review } from "../lib/neph-run";

// Neovim integration for pi.
//
// Uses the `neph` CLI as the universal Neovim bridge.
//
// write / edit tools are overridden to open a non-blocking vimdiff review in
// Neovim before any disk write.
//
// Per-hunk choices: Accept / Reject / Accept all / Reject all
// decision: "accept" | "reject" | "partial" (some hunks accepted, some rejected)
//
// vim.g globals for statusline integration:
//   vim.g.pi_active   — set while a pi session is live
//   vim.g.pi_running  — set while the agent is processing a turn
//   vim.g.pi_reading  — path of file currently being read by the agent (nil otherwise)

export default function (pi: ExtensionAPI) {
  let toolsRegistered = false;
  const neph = createNephQueue();
  let promptPollTimer: ReturnType<typeof setInterval> | undefined;

  /** Poll vim.g.neph_pending_prompt and deliver via pi.sendUserMessage(). */
  function startPromptPoll() {
    if (promptPollTimer) return;
    let polling = false;
    promptPollTimer = setInterval(async () => {
      if (polling) return; // skip if previous poll is still in-flight
      polling = true;
      try {
        const raw = await nephRun(["get", "neph_pending_prompt"], undefined, NEPH_TIMEOUT_MS);
        const res = JSON.parse(raw);
        if (res?.ok && res?.result?.value) {
          const prompt = res.result.value;
          // Clear the global before sending to avoid re-delivery
          await nephRun(["unset", "neph_pending_prompt"], undefined, NEPH_TIMEOUT_MS);
          pi.sendUserMessage(typeof prompt === "string" ? prompt : String(prompt));
        }
      } catch {
        // nvim may have closed or neph not available — ignore
      } finally {
        polling = false;
      }
    }, 500);
  }

  function stopPromptPoll() {
    if (promptPollTimer) {
      clearInterval(promptPollTimer);
      promptPollTimer = undefined;
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

        const result = await review(filePath, newContent);

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
        // Surface partial / rejection notes back to the agent
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
        const result = await review(filePath, newContent);

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
        // Write the full reconstructed content (not a partial edit replacement)
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

  // --- Session lifecycle: activate only when nvim socket is present ---

  pi.on("session_start", (_event, ctx) => {
    ctx.ui.setStatus("nvim", " >> ");
    neph("set", "pi_active", "true");
    registerTools();
    startPromptPoll();
  });

  pi.on("session_shutdown", () => {
    stopPromptPoll();
    neph("unset", "neph_pending_prompt");
    neph("unset", "pi_active");
    neph("unset", "pi_running");
  });

  pi.on("agent_start", () => {
    neph("set", "pi_running", "true");
  });

  pi.on("agent_end", (_event, ctx) => {
    neph("unset", "pi_running");
    neph("unset", "pi_reading");
    neph("checktime");
    ctx.ui.setStatus("nvim-reading", "");
  });

  pi.on("tool_call", (event, ctx) => {
    if (event.toolName === "read") {
      const path = event.input.path as string | undefined;
      if (path) {
        const abs = resolve(ctx.cwd, path);
        const rel = relative(ctx.cwd, abs);
        const shortPath = rel.startsWith("..") ? basename(abs) : rel;
        neph("set", "pi_reading", JSON.stringify(shortPath));
        ctx.ui.setStatus("nvim-reading", ` >> 󰍉 >> ${shortPath}`);
      }
    }
  });

  pi.on("tool_result", (event) => {
    if (event.toolName === "write" || event.toolName === "edit") {
      neph("checktime");
    }
  });
}
