import { describe, it, expect, vi, beforeEach } from "vitest";
import { runCommand } from "../src/index";
import { runIntegrationCommand } from "../src/integration";
import * as fs from "node:fs";

const mockWriteFileSync = vi.fn();

vi.mock("node:fs", async () => {
  const actual = await vi.importActual<typeof fs>("node:fs");
  return {
    ...actual,
    existsSync: vi.fn((path: string) => path.includes("settings.json") || path.includes("hooks.json") || path.includes(".neph/")),
    readFileSync: vi.fn((filePath: string, encoding?: unknown) => {
      // Return real template file contents for toggle to work with,
      // but only for files that actually exist on disk (the tool templates).
      if (typeof filePath === "string" && actual.existsSync(filePath)) {
        return actual.readFileSync(filePath, (encoding ?? "utf-8") as BufferEncoding);
      }
      return JSON.stringify({});
    }),
    writeFileSync: (...args: any[]) => mockWriteFileSync(...args),
    mkdirSync: vi.fn(),
  };
});

describe("integration commands", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("prints integration status", async () => {
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    await runCommand(null, "integration", ["integration", "status"]);
    expect(stdoutSpy).toHaveBeenCalled();
    stdoutSpy.mockRestore();
  });

  it("toggle claude: written config has no _kind fields", async () => {
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    await runIntegrationCommand(["integration", "toggle", "claude"], "", null);
    stdoutSpy.mockRestore();

    expect(mockWriteFileSync).toHaveBeenCalled();
    const writtenContent = mockWriteFileSync.mock.calls[0][1] as string;
    const parsed = JSON.parse(writtenContent);
    const serialized = JSON.stringify(parsed);
    expect(serialized).not.toContain("_kind");
  });

  it("toggle copilot: written config has no _kind fields", async () => {
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    await runIntegrationCommand(["integration", "toggle", "copilot"], "", null);
    stdoutSpy.mockRestore();

    expect(mockWriteFileSync).toHaveBeenCalled();
    const writtenContent = mockWriteFileSync.mock.calls[0][1] as string;
    const parsed = JSON.parse(writtenContent);
    const serialized = JSON.stringify(parsed);
    expect(serialized).not.toContain("_kind");
  });
});

describe("integration error paths", () => {
  it("toggle: surfaces write error with actionable message", async () => {
    mockWriteFileSync.mockImplementationOnce(() => {
      throw new Error("EACCES: permission denied");
    });
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => undefined as never);
    await runIntegrationCommand(["integration", "toggle", "claude"], "", null);
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining("failed to update claude config"),
    );
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining("EACCES"),
    );
    expect(exitSpy).toHaveBeenCalledWith(1);
    stderrSpy.mockRestore();
    exitSpy.mockRestore();
  });

  it("status: surfaces read error when direct readFileSync throws during --show-config", async () => {
    // The --show-config block calls fs.readFileSync(configPath) directly after
    // integrationEnabled() succeeds. Mock readFileSync to throw only for non-real paths.
    vi.mocked(fs.readFileSync).mockImplementation((filePath: unknown, encoding?: unknown) => {
      const p = String(filePath);
      // Real on-disk files (template files) go through actual fs.
      const realFs = require("node:fs");
      if (realFs.existsSync(p)) {
        return realFs.readFileSync(p, encoding ?? "utf-8");
      }
      // Fake config path (not on disk) — throw permission error.
      throw new Error(`EACCES: permission denied, open '${p}'`);
    });
    const stderrSpy = vi.spyOn(process.stderr, "write").mockImplementation(() => true);
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => undefined as never);
    await runIntegrationCommand(["integration", "status", "claude", "--show-config"], "", null);
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining("neph integration status: cannot read"),
    );
    expect(stderrSpy).toHaveBeenCalledWith(
      expect.stringContaining("Check file permissions"),
    );
    stderrSpy.mockRestore();
    stdoutSpy.mockRestore();
    exitSpy.mockRestore();
  });
});

describe("deps command", () => {
  it("prints deps status", async () => {
    const stdoutSpy = vi.spyOn(process.stdout, "write").mockImplementation(() => true);
    const exitSpy = vi.spyOn(process, "exit").mockImplementation(() => undefined as never);
    await runCommand(null, "deps", ["deps", "status"]);
    expect(stdoutSpy).toHaveBeenCalled();
    stdoutSpy.mockRestore();
    exitSpy.mockRestore();
  });
});
