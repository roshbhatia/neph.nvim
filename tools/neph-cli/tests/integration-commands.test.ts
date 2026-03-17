import { describe, it, expect, vi, beforeEach } from "vitest";
import { runCommand } from "../src/index";
import * as fs from "node:fs";

vi.mock("node:fs", async () => {
  const actual = await vi.importActual<typeof fs>("node:fs");
  return {
    ...actual,
    existsSync: vi.fn((path: string) => path.includes("settings.json") || path.includes("hooks.json")),
    readFileSync: vi.fn(() => JSON.stringify({ hooks: {} })),
    writeFileSync: vi.fn(),
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
