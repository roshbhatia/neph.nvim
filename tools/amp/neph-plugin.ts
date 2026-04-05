// @i-know-the-amp-plugin-api-is-wip-and-very-experimental-right-now
import { readFileSync } from "node:fs";
import { debug } from "../lib/log";
import { review, uiSelect, uiInput, uiNotify, createPersistentQueue } from "../lib/neph-run";

function neph_plugin_default(amp: any) {
  // Persistent queue: one long-lived `neph connect` subprocess per session.
  // Eliminates per-call spawn overhead for set/unset/checktime.
  // Falls back to per-spawn silently if the connect process can't start.
  let pq = createPersistentQueue();

  amp.on("session.start", async () => {
    debug("amp", "session.start");

    // Wire amp UI to Neovim
    amp.ui = {
      ...amp.ui,
      notify: (message: string, type?: string) => {
        uiNotify(message, type);
      },
      confirm: async (title: string, message: string) => {
        const choice = await uiSelect(`${title}\n${message}`, ["Yes", "No"]);
        return choice === "Yes";
      },
      input: async (title: string, placeholder?: string) => {
        return (await uiInput(title, placeholder)) ?? "";
      },
    };
  });

  amp.on("session.end", async () => {
    debug("amp", "session.end");
    pq.close();
    // Create a fresh queue in case the session restarts in the same process
    pq = createPersistentQueue();
  });

  amp.on("agent.start", async () => {
    pq.call("set", "amp_running", "true");
  });

  amp.on("agent.end", async () => {
    pq.call("unset", "amp_running");
    pq.call("checktime");
  });

  amp.on("tool.call", async (event: any, _ctx: any) => {
    const tool = event.tool as string;
    if (tool !== "edit_file" && tool !== "create_file" && tool !== "apply_patch") {
      return { action: "allow" };
    }

    const input = event.input as Record<string, string>;
    const filePath = input.file_path ?? input.path ?? input.filepath;
    if (!filePath) return { action: "allow" };

    let content: string;
    if (tool === "create_file") {
      content = input.content ?? "";
    } else if (tool === "edit_file") {
      try {
        const current = readFileSync(filePath, "utf-8");
        const oldStr = input.old_string ?? input.old_str;
        const newStr = input.new_string ?? input.new_str;
        if (oldStr !== undefined && newStr !== undefined) {
          content = current.replace(oldStr, newStr);
        } else {
          content = input.content ?? current;
        }
      } catch {
        content = input.content ?? "";
      }
    } else {
      content = input.patch ?? input.content ?? "";
    }

    try {
      const result = await review(filePath, content, "amp");
      if (result.decision === "reject") {
        const reason = result.reason ?? "User rejected changes";
        return {
          action: "reject-and-continue",
          message: `Write rejected by neph review: ${reason}`,
        };
      }
      return { action: "allow" };
    } catch (e) {
      debug("amp", `Review failed: ${e}`);
      return { action: "allow" };
    }
  });
}

export default neph_plugin_default;
