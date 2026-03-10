// @i-know-the-amp-plugin-api-is-wip-and-very-experimental-right-now
import type { PluginAPI } from "@ampcode/plugin";
import { NephClient } from "../lib/neph-client";
import { debug as log } from "../lib/log";
import { readFileSync } from "node:fs";

/**
 * Neovim companion plugin for Amp.
 *
 * Provides a persistent side channel to Neovim via NephClient.
 * - Bridges real-time status (running/idle) to Neovim statusline.
 * - Bridges ctx.ui (notify, confirm, input) to native Neovim UI.
 * - Intercepts file tools for native Neph review.
 * - Listens for prompts from Neovim via 'neph:prompt'.
 */
export default function (amp: PluginAPI) {
  const neph = new NephClient();

  amp.on("session.start", async () => {
    try {
      await neph.connect();
      await neph.register("amp");
      await neph.setStatus("amp_active", "true");
      log("amp", "Companion bridge connected to Neovim");
    } catch (e) {
      log(
        "amp",
        `Companion bridge failed to connect: ${e instanceof Error ? e.message : String(e)}`,
      );
    }

    // Listen for prompts from Neovim
    neph.onPrompt((text) => {
      log("amp", `Received prompt from Neovim (len=${text.length})`);
      // Amp SDK equivalent of sending a message to the thread
      amp.thread.append({ role: "user", content: text });
    });

    // Bridge ctx.ui to Neovim
    // Note: In some SDKs we wrap the context object passed to handlers.
    // In Amp, we might need to intercept the global ctx or wrap it in each handler.
    // However, if the SDK allows modifying ctx.ui globally:
    const originalUi = amp.ui;
    (amp as any).ui = {
      ...originalUi,
      notify: (message: string, type?: string) => {
        neph.uiNotify(message, type);
        originalUi.notify(message, type as any);
      },
      confirm: async (title: string, message: string) => {
        const choice = await neph.uiSelect(`${title}\n${message}`, [
          "Yes",
          "No",
        ]);
        return choice === "Yes";
      },
      input: async (title: string, placeholder?: string) => {
        return (await neph.uiInput(title, placeholder)) ?? "";
      },
    };
  });

  amp.on("agent.start", async () => {
    try {
      await neph.setStatus("amp_running", "true");
    } catch (err) {
      log("amp", `agent.start handler error: ${err}`);
    }
  });

  amp.on("agent.end", async () => {
    try {
      await neph.unsetStatus("amp_running");
      await neph.checktime();
    } catch (err) {
      log("amp", `agent.end handler error: ${err}`);
    }
  });

  amp.on("tool.call", async (event, _ctx) => {
    const tool = event.tool as string;

    // Only intercept file mutation tools
    if (tool !== "edit_file" && tool !== "create_file" && tool !== "apply_patch")
      return { action: "allow" as const };

    const input = event.input as Record<string, unknown>;
    const filePath = (input.file_path ?? input.path ?? input.filepath) as
      | string
      | undefined;
    if (!filePath) return { action: "allow" as const };

    let content: string;
    if (tool === "create_file") {
      content = (input.content as string) ?? "";
    } else if (tool === "edit_file") {
      try {
        const current = readFileSync(filePath, "utf-8");
        const oldStr = (input.old_string ?? input.old_str) as
          | string
          | undefined;
        const newStr = (input.new_string ?? input.new_str) as
          | string
          | undefined;
        if (oldStr !== undefined && newStr !== undefined) {
          content = current.replaceAll(oldStr, newStr);
        } else {
          content = (input.content as string) ?? current;
        }
      } catch {
        content = (input.content as string) ?? "";
      }
    } else {
      content = ((input.patch ?? input.content) as string) ?? "";
    }

    try {
      const result = await neph.review(filePath, content);

      if (result.decision === "reject") {
        const reason = result.reason ? `: ${result.reason}` : "";
        return {
          action: "reject-and-continue" as const,
          message: `Write rejected by neph review${reason}`,
        };
      }
      return { action: "allow" as const };
    } catch (e) {
      log("amp", `Review failed: ${e}`);
      return { action: "allow" as const }; // Fallback to allow if review system fails
    }
  });
}
