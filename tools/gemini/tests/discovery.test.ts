import { describe, it, expect, afterEach } from "vitest";
import * as fs from "node:fs";
import * as path from "node:path";
import * as os from "node:os";
import { writeDiscoveryFile, removeDiscoveryFile, getDiscoveryFilePath } from "../src/discovery";

describe("discovery file", () => {
  afterEach(() => {
    removeDiscoveryFile();
  });

  it("creates discovery file with correct schema", () => {
    const filePath = writeDiscoveryFile(12345, "/home/user/project", "test-token-123");

    expect(fs.existsSync(filePath)).toBe(true);
    const content = JSON.parse(fs.readFileSync(filePath, "utf-8"));
    expect(content.port).toBe(12345);
    expect(content.workspacePath).toBe("/home/user/project");
    expect(content.authToken).toBe("test-token-123");
    expect(content.ideInfo.name).toBe("neovim");
    expect(content.ideInfo.displayName).toBe("Neovim (neph)");
  });

  it("creates file in gemini/ide temp directory", () => {
    const filePath = writeDiscoveryFile(8080, "/workspace", "token");
    const dir = path.dirname(filePath);
    expect(dir).toBe(path.join(os.tmpdir(), "gemini", "ide"));
  });

  it("uses PID and PORT in filename", () => {
    const filePath = writeDiscoveryFile(9999, "/workspace", "token");
    const filename = path.basename(filePath);
    expect(filename).toBe(`gemini-ide-server-${process.pid}-9999.json`);
  });

  it("removes discovery file on cleanup", () => {
    const filePath = writeDiscoveryFile(8080, "/workspace", "token");
    expect(fs.existsSync(filePath)).toBe(true);

    removeDiscoveryFile();
    expect(fs.existsSync(filePath)).toBe(false);
    expect(getDiscoveryFilePath()).toBeNull();
  });

  it("handles double removal gracefully", () => {
    writeDiscoveryFile(8080, "/workspace", "token");
    removeDiscoveryFile();
    expect(() => removeDiscoveryFile()).not.toThrow();
  });
});
