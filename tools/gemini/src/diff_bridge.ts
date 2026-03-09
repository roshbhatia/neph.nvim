import * as fs from "node:fs";
import * as path from "node:path";
import { NephClient, type ReviewEnvelope } from "../../lib/neph-client";
import { debug as log } from "../../lib/log";

export interface DiffNotificationSink {
  sendDiffAccepted(filePath: string, content: string): void;
  sendDiffRejected(filePath: string): void;
}

export function createDiffTools(neph: NephClient, sink: DiffNotificationSink) {
  return {
    openDiff: {
      description: "Open a diff view for a file change in the IDE",
      inputSchema: {
        type: "object" as const,
        properties: {
          filePath: { type: "string", description: "Absolute path to the file" },
          newContent: { type: "string", description: "Proposed new content for the file" },
        },
        required: ["filePath", "newContent"],
      },
      handler: async (params: Record<string, unknown>) => {
        const filePath = params.filePath as string;
        const newContent = params.newContent as string;

        if (!filePath) {
          return { content: [{ type: "text", text: "Missing filePath" }], isError: true };
        }

        const resolved = path.resolve(filePath);
        log("diff-bridge", `openDiff: ${resolved}`);

        let result: ReviewEnvelope;
        try {
          result = await neph.review(resolved, newContent);
        } catch (err) {
          const msg = err instanceof Error ? err.message : String(err);
          return { content: [{ type: "text", text: `Review failed: ${msg}` }], isError: true };
        }

        // Write accepted content to disk
        if (result.decision === "accept" || result.decision === "partial") {
          const finalContent = result.content ?? newContent;
          try {
            const dir = path.dirname(resolved);
            fs.mkdirSync(dir, { recursive: true });
            fs.writeFileSync(resolved, finalContent);
            await neph.checktime();
            log("diff-bridge", `openDiff: wrote ${resolved} (decision=${result.decision})`);
          } catch (err) {
            log("diff-bridge", `openDiff: write failed: ${err}`);
          }
          sink.sendDiffAccepted(resolved, finalContent);
        } else {
          sink.sendDiffRejected(resolved);
        }

        return { content: [] };
      },
    },

    closeDiff: {
      description: "Close a diff view and return the file's current content",
      inputSchema: {
        type: "object" as const,
        properties: {
          filePath: { type: "string", description: "Absolute path to the file" },
        },
        required: ["filePath"],
      },
      handler: async (params: Record<string, unknown>) => {
        const filePath = params.filePath as string;
        if (!filePath) {
          return { content: [{ type: "text", text: "Missing filePath" }], isError: true };
        }

        const resolved = path.resolve(filePath);
        log("diff-bridge", `closeDiff: ${resolved}`);

        let content = "";
        try {
          content = fs.readFileSync(resolved, "utf-8");
        } catch {
          // File doesn't exist — return empty
        }

        return { content: [{ type: "text", text: content }] };
      },
    },
  };
}
