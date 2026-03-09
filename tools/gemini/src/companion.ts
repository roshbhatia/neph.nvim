#!/usr/bin/env node
import process from "node:process";
import * as http from "node:http";
import { NephClient } from "../../lib/neph-client";
import { McpServer, generateAuthToken } from "./server";
import { writeDiscoveryFile, removeDiscoveryFile } from "./discovery";
import { createDiffTools, type DiffNotificationSink } from "./diff_bridge";
import { debug as log } from "../../lib/log";

const workspacePath = process.argv[2] || process.cwd();

async function main(): Promise<void> {
  log("companion", `starting (workspace=${workspacePath})`);

  // Connect to Neovim
  const neph = new NephClient();
  await neph.connect();
  await neph.register("gemini");

  // Generate auth token
  const authToken = generateAuthToken();

  // Pending notifications to send to Gemini CLI.
  // Gemini CLI connects to us — we can't push notifications directly.
  // Instead, notifications are queued and delivered when Gemini CLI polls or
  // via a separate notification endpoint if the spec supports it.
  // For now, we store them and they can be retrieved via a custom method.
  const pendingNotifications: { method: string; params: Record<string, unknown> }[] = [];

  const notificationSink: DiffNotificationSink = {
    sendDiffAccepted(filePath: string, content: string): void {
      pendingNotifications.push({
        method: "ide/diffAccepted",
        params: { filePath, content },
      });
      log("companion", `queued ide/diffAccepted for ${filePath}`);
    },
    sendDiffRejected(filePath: string): void {
      pendingNotifications.push({
        method: "ide/diffRejected",
        params: { filePath },
      });
      log("companion", `queued ide/diffRejected for ${filePath}`);
    },
  };

  // Create diff tools
  const diffTools = createDiffTools(neph, notificationSink);

  // Create MCP server
  const server = new McpServer({
    authToken,
    tools: {
      openDiff: diffTools.openDiff,
      closeDiff: diffTools.closeDiff,
    },
    notifications: {
      "notifications/initialized": async () => {
        log("companion", "client initialized");
      },
    },
  });

  const port = await server.start();
  const discoveryPath = writeDiscoveryFile(port, workspacePath, authToken);
  log("companion", `discovery file: ${discoveryPath}`);

  // Listen for context updates from Neovim
  neph.onNotification("neph:context", (args: unknown[]) => {
    const context = args[0] as Record<string, unknown> | undefined;
    if (context) {
      pendingNotifications.push({
        method: "ide/contextUpdate",
        params: context,
      });
    }
  });

  // Listen for prompts from Neovim (standard extension agent pattern)
  neph.onPrompt((text) => {
    log("companion", `received prompt (len=${text.length}) — no-op for companion`);
  });

  // Cleanup on exit
  const cleanup = async () => {
    log("companion", "shutting down");
    removeDiscoveryFile();
    await server.stop();
    neph.disconnect();
  };

  process.on("SIGTERM", async () => {
    await cleanup();
    process.exit(0);
  });
  process.on("SIGINT", async () => {
    await cleanup();
    process.exit(0);
  });
  process.on("exit", () => {
    removeDiscoveryFile();
  });

  log("companion", `ready on port ${port}`);
}

main().catch((err) => {
  log("companion", `fatal: ${err}`);
  removeDiscoveryFile();
  process.exit(1);
});
