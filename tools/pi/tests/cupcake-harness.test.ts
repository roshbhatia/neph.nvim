import { describe, it, expect, vi, beforeEach, type Mock } from "vitest";

// Mock child_process before imports
const mockExecFileSync = vi.fn();
vi.mock("node:child_process", () => ({
  execFileSync: (...args: any[]) => mockExecFileSync(...args),
}));

vi.mock("node:fs", () => ({ readFileSync: vi.fn() }));
vi.mock("@mariozechner/pi-coding-agent", () => ({
  createWriteTool: vi.fn(),
  createEditTool: vi.fn(),
}));

import { readFileSync } from "node:fs";
import { createWriteTool, createEditTool } from "@mariozechner/pi-coding-agent";

// Minimal ExtensionAPI stub
function createPiStub() {
  const tools: Record<string, any> = {};
  const handlers: Record<string, Function[]> = {};
  return {
    registerTool(spec: any) { tools[spec.name] = spec; },
    on(event: string, handler: Function) {
      if (!handlers[event]) handlers[event] = [];
      handlers[event].push(handler);
    },
    sendUserMessage: vi.fn(),
    tools,
    handlers,
    async fire(event: string, ...args: any[]) {
      for (const h of (handlers[event] || [])) await h(...args);
    },
  };
}

function mockCtx(cwd = "/project") {
  return { cwd, ui: { setStatus: vi.fn() } };
}

describe("cupcake-harness", () => {
  let pi: ReturnType<typeof createPiStub>;

  beforeEach(() => {
    vi.clearAllMocks();
    pi = createPiStub();

    // Default: cupcake --version succeeds
    mockExecFileSync.mockImplementation((cmd: string, args: string[]) => {
      if (cmd === "cupcake" && args[0] === "--version") return "";
      if (cmd === "cupcake" && args[0] === "eval") {
        return JSON.stringify({ decision: "allow" });
      }
      if (cmd === "neph-cli") return "";
      return "";
    });

    // Mock native tools
    const mockWriteExecute = vi.fn().mockResolvedValue({
      content: [{ type: "text", text: "Written" }],
      details: undefined,
    });
    (createWriteTool as Mock).mockReturnValue({
      parameters: { type: "object", properties: {} },
      execute: mockWriteExecute,
    });
    (createEditTool as Mock).mockReturnValue({
      parameters: { type: "object", properties: {} },
      execute: vi.fn().mockResolvedValue({
        content: [{ type: "text", text: "Edited" }],
        details: undefined,
      }),
    });
  });

  async function loadAndInit() {
    // Dynamic import to get fresh module
    const mod = await import("../cupcake-harness");
    mod.default(pi as any);
    await pi.fire("session_start", {}, mockCtx());
    return pi;
  }

  describe("assertCupcakeInstalled", () => {
    it("throws when cupcake is not installed", async () => {
      mockExecFileSync.mockImplementation((cmd: string, args: string[]) => {
        if (cmd === "cupcake" && args[0] === "--version") {
          throw new Error("ENOENT");
        }
        return "";
      });

      const mod = await import("../cupcake-harness");
      mod.default(pi as any);

      await expect(pi.fire("session_start", {}, mockCtx())).rejects.toThrow("Cupcake is not installed");
    });
  });

  describe("write tool", () => {
    it("calls cupcake eval and writes on allow", async () => {
      await loadAndInit();

      const result = await pi.tools.write.execute(
        "call-1",
        { path: "foo.lua", content: "new content" },
        undefined, vi.fn(), mockCtx(),
      );

      // Verify cupcake eval was called
      const cupcakeCalls = mockExecFileSync.mock.calls.filter(
        (c: any[]) => c[0] === "cupcake" && c[1]?.[0] === "eval"
      );
      expect(cupcakeCalls.length).toBe(1);

      // Verify native write was called
      expect(createWriteTool(process.cwd()).execute).toHaveBeenCalled();
      expect(result.content[0].text).toBe("Written");
    });

    it("rejects when cupcake denies", async () => {
      mockExecFileSync.mockImplementation((cmd: string, args: string[]) => {
        if (cmd === "cupcake" && args[0] === "--version") return "";
        if (cmd === "cupcake" && args[0] === "eval") {
          return JSON.stringify({ decision: "deny", reason: "Protected path" });
        }
        return "";
      });

      await loadAndInit();

      const result = await pi.tools.write.execute(
        "call-1",
        { path: ".env", content: "SECRET=foo" },
        undefined, vi.fn(), mockCtx(),
      );

      expect(result.content[0].text).toContain("rejected");
      expect(result.content[0].text).toContain("Protected path");
    });

    it("applies modified content on partial accept", async () => {
      mockExecFileSync.mockImplementation((cmd: string, args: string[]) => {
        if (cmd === "cupcake" && args[0] === "--version") return "";
        if (cmd === "cupcake" && args[0] === "eval") {
          return JSON.stringify({
            decision: "allow",
            updated_input: { content: "modified content" },
          });
        }
        return "";
      });

      await loadAndInit();

      const result = await pi.tools.write.execute(
        "call-1",
        { path: "foo.lua", content: "original" },
        undefined, vi.fn(), mockCtx(),
      );

      expect(result.content).toContainEqual({ type: "text", text: "Note: partial accept" });
    });
  });

  describe("edit tool", () => {
    it("reconstructs content and calls cupcake eval", async () => {
      (readFileSync as Mock).mockReturnValue("hello foo world");
      await loadAndInit();

      await pi.tools.edit.execute(
        "call-1",
        { path: "foo.lua", oldText: "foo", newText: "bar" },
        undefined, vi.fn(), mockCtx(),
      );

      const cupcakeCalls = mockExecFileSync.mock.calls.filter(
        (c: any[]) => c[0] === "cupcake" && c[1]?.[0] === "eval"
      );
      expect(cupcakeCalls.length).toBe(1);
      const event = JSON.parse(cupcakeCalls[0][2].input);
      expect(event.tool_input.content).toBe("hello bar world");
    });
  });

  describe("lifecycle events", () => {
    it("sets pi_active on session_start", async () => {
      await loadAndInit();
      const setCalls = mockExecFileSync.mock.calls.filter(
        (c: any[]) => c[0] === "neph-cli" && c[1]?.[0] === "set" && c[1]?.[1] === "pi_active"
      );
      expect(setCalls.length).toBe(1);
    });

    it("unsets pi_active on session_shutdown", async () => {
      await loadAndInit();
      await pi.fire("session_shutdown");
      const setCalls = mockExecFileSync.mock.calls.filter(
        (c: any[]) => c[0] === "neph-cli" && c[1]?.[0] === "set" && c[1]?.[1] === "pi_active" && c[1]?.[2] === ""
      );
      expect(setCalls.length).toBe(1);
    });
  });

  describe("non-mutation tools", () => {
    it("read tool does not call cupcake eval", async () => {
      await loadAndInit();
      await pi.fire("tool_call", { toolName: "read", input: { path: "foo.lua" } }, mockCtx());

      const cupcakeEvalCalls = mockExecFileSync.mock.calls.filter(
        (c: any[]) => c[0] === "cupcake" && c[1]?.[0] === "eval"
      );
      expect(cupcakeEvalCalls.length).toBe(0);
    });
  });
});
