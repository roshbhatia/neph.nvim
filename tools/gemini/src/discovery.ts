import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { debug as log } from "../../lib/log";

export interface DiscoveryFile {
  port: number;
  workspacePath: string;
  authToken: string;
  ideInfo: {
    name: string;
    displayName: string;
  };
}

let discoveryFilePath: string | null = null;

export function writeDiscoveryFile(port: number, workspacePath: string, authToken: string): string {
  const dir = path.join(os.tmpdir(), "gemini", "ide");
  fs.mkdirSync(dir, { recursive: true });

  const filename = `gemini-ide-server-${process.pid}-${port}.json`;
  discoveryFilePath = path.join(dir, filename);

  const content: DiscoveryFile = {
    port,
    workspacePath,
    authToken,
    ideInfo: {
      name: "neovim",
      displayName: "Neovim (neph)",
    },
  };

  fs.writeFileSync(discoveryFilePath, JSON.stringify(content, null, 2));
  log("discovery", `wrote ${discoveryFilePath}`);
  return discoveryFilePath;
}

export function removeDiscoveryFile(): void {
  if (discoveryFilePath && fs.existsSync(discoveryFilePath)) {
    try {
      fs.unlinkSync(discoveryFilePath);
      log("discovery", `removed ${discoveryFilePath}`);
    } catch (err) {
      log("discovery", `failed to remove: ${err}`);
    }
  }
  discoveryFilePath = null;
}

export function getDiscoveryFilePath(): string | null {
  return discoveryFilePath;
}
