import { tool } from "@opencode-ai/plugin";
import { readFileSync, writeFileSync } from "node:fs";
import { resolve } from "node:path";
import { createNephQueue, review } from "../lib/neph-run";

const neph = createNephQueue();

export default tool({
  description:
    "Edit a file by replacing exact text, gated through neph review.",
  args: {
    file_path: tool.schema.string().describe("Absolute or relative file path"),
    old_str: tool.schema.string().describe("Exact text to find and replace"),
    new_str: tool.schema.string().describe("Replacement text"),
  },
  async execute(args, context) {
    const filePath = resolve(context.directory, args.file_path);

    let currentContent: string;
    try {
      currentContent = readFileSync(filePath, "utf-8");
    } catch {
      return `Cannot read ${args.file_path}`;
    }

    if (!currentContent.includes(args.old_str)) {
      return `Edit failed: old_str not found in ${args.file_path}`;
    }

    const newContent = currentContent.replace(args.old_str, args.new_str);

    neph("set", "opencode_active", "true");
    try {
      const result = await review(filePath, newContent);

      if (result.decision === "reject") {
        const reason = result.reason ? `: ${result.reason}` : "";
        return `Edit rejected${reason}`;
      }

      const finalContent = result.content ?? newContent;
      writeFileSync(filePath, finalContent, "utf-8");
      return `File edited: ${args.file_path}`;
    } finally {
      neph("unset", "opencode_active");
    }
  },
});
