// @i-know-the-amp-plugin-api-is-wip-and-very-experimental-right-now
import type { PluginAPI } from "@ampcode/plugin";
import { createNephQueue, review } from "../lib/neph-run";
import { readFileSync } from "node:fs";

export default function (amp: PluginAPI) {
  const neph = createNephQueue();

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
      // Reconstruct full content for review
      try {
        const current = readFileSync(filePath, "utf-8");
        const oldStr = (input.old_string ?? input.old_str) as
          | string
          | undefined;
        const newStr = (input.new_string ?? input.new_str) as
          | string
          | undefined;
        if (oldStr !== undefined && newStr !== undefined) {
          content = current.replace(oldStr, newStr);
        } else {
          content = (input.content as string) ?? current;
        }
      } catch {
        content = (input.content as string) ?? "";
      }
    } else {
      // apply_patch — pass the patch content for review
      content = (input.patch ?? input.content) as string ?? "";
    }

    neph("set", "amp_active", "true");
    try {
      const result = await review(filePath, content);

      if (result.decision === "reject") {
        const reason = result.reason ? `: ${result.reason}` : "";
        return {
          action: "reject-and-continue" as const,
          message: `Write rejected by neph review${reason}`,
        };
      }
      return { action: "allow" as const };
    } finally {
      neph("unset", "amp_active");
    }
  });
}
