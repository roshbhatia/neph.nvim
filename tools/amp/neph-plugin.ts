// @i-know-the-amp-plugin-api-is-wip-and-very-experimental-right-now
import { readFileSync } from "node:fs";
import { debug } from "../lib/log";
import { review, uiSelect, uiInput, uiNotify, createNephQueue } from "../lib/neph-run";

const nephQueue = createNephQueue();

function neph_plugin_default(amp: any) {
  amp.on("session.start", async () => {
    debug("amp", "session.start");

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

  amp.on("agent.start", async () => {
    nephQueue("status-set", "amp_running", "true");
  });

  amp.on("agent.end", async () => {
    nephQueue("status-unset", "amp_running");
    nephQueue("buffers-check");
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
      const result = await review(filePath, content);
      if (result.decision === "reject") {
        const reason = result.reason ? `: ${result.reason}` : "";
        return {
          action: "reject-and-continue",
          message: `Write rejected by neph review${reason}`,
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
