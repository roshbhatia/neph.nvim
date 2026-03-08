import { tool } from "@opencode-ai/plugin";
import { writeFileSync, mkdirSync } from "node:fs";
import { dirname, resolve } from "node:path";
import { createNephQueue, review } from "../lib/neph-run";

const neph = createNephQueue();

export default tool({
  description:
    "Write content to a file, gated through neph review. Creates parent directories automatically.",
  args: {
    file_path: tool.schema.string().describe("Absolute or relative file path"),
    content: tool.schema.string().describe("File content to write"),
  },
  async execute(args, context) {
    const filePath = resolve(context.directory, args.file_path);

    neph("set", "opencode_active", "true");
    try {
      const result = await review(filePath, args.content);

      if (result.decision === "reject") {
        const reason = result.reason ? `: ${result.reason}` : "";
        return `Write rejected${reason}`;
      }

      const finalContent = result.content ?? args.content;
      mkdirSync(dirname(filePath), { recursive: true });
      writeFileSync(filePath, finalContent, "utf-8");
      return `File written: ${args.file_path}`;
    } finally {
      neph("unset", "opencode_active");
    }
  },
});
