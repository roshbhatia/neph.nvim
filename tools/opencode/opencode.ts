import type { Plugin } from "@opencode-ai/plugin";
import { NephClient } from "../lib/neph-client";
import { debug as log } from "../lib/log";

/**
 * Neovim companion plugin for OpenCode.
 *
 * Provides a persistent side channel to Neovim via NephClient.
 * - Bridges real-time status (busy/idle) to Neovim statusline.
 * - Intercepts shell tool calls for native Neovim approval.
 * - Listens for prompts from Neovim via 'neph:prompt'.
 */
export const NephCompanion: Plugin = async ({ client }) => {
  const neph = new NephClient();

  // Connect to Neovim
  try {
    await neph.connect();
    await neph.register("opencode");
    log("opencode", "Companion bridge connected to Neovim");
  } catch (e) {
    log(
      "opencode",
      `Companion bridge failed to connect: ${e instanceof Error ? e.message : String(e)}`,
    );
  }

  // Listen for prompts from Neovim
  neph.onPrompt((text) => {
    log("opencode", `Received prompt from Neovim (len=${text.length})`);
    // OpenCode SDK equivalent of sendUserMessage
    client.chat.append({ role: "user", content: text });
  });

  return {
    // Lifecycle events
    event: async ({ event }) => {
      switch (event.type) {
        case "session.created":
          await neph.setStatus("opencode_active", "true");
          break;
        case "session.busy":
          await neph.setStatus("opencode_running", "true");
          break;
        case "session.idle":
          await neph.unsetStatus("opencode_running");
          await neph.checktime();
          break;
      }
    },

    // Tool interception
    tool: {
      execute: {
        before: async (input) => {
          // Intercept shell tool for native approval
          if (input.tool === "shell") {
            const command = (input.args as any).command;
            const choice = await neph.uiSelect(
              `OpenCode wants to run shell command:
${command}`,
              ["Yes", "No"],
            );

            if (choice !== "Yes") {
              throw new Error("User denied shell execution in Neovim");
            }
          }
        },
      },
    },
  };
};

export default NephCompanion;
