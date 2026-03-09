/**
 * pi.test.ts — unit tests for tools/pi/pi.ts
 *
 * Strategy:
 *  - vi.mock("../lib/neph-client") stubs NephClient (persistent socket connection)
 *  - vi.mock("node:fs") controls readFileSync for edit-tool tests
 *  - vi.mock("@mariozechner/pi-coding-agent") stubs createWriteTool + createEditTool
 *  - A hand-rolled `pi` stub satisfies ExtensionAPI: records registerTool calls
 *    and lets us fire events programmatically
 */

import { describe, it, expect, vi, beforeEach, type Mock } from "vitest";

// ── Module mocks (hoisted before imports) ────────────────────────────────────

const mockNephInstance = {
  connect: vi.fn().mockResolvedValue(undefined),
  register: vi.fn().mockResolvedValue(undefined),
  onPrompt: vi.fn(),
  setStatus: vi.fn().mockResolvedValue(undefined),
  unsetStatus: vi.fn().mockResolvedValue(undefined),
  review: vi.fn().mockResolvedValue({
    schema: "review/v1",
    decision: "accept",
    content: "accepted",
    hunks: [],
  }),
  checktime: vi.fn().mockResolvedValue(undefined),
  disconnect: vi.fn(),
  isConnected: vi.fn().mockReturnValue(true),
};

vi.mock("../../lib/neph-client", () => ({
  NephClient: vi.fn(() => mockNephInstance),
}));
vi.mock("node:fs", () => ({ readFileSync: vi.fn() }));
vi.mock("@mariozechner/pi-coding-agent", () => ({
  createWriteTool: vi.fn(),
  createEditTool: vi.fn(),
}));
vi.mock("../../lib/log", () => ({ debug: vi.fn() }));

// Import after mocks are registered
import { readFileSync } from "node:fs";
import { createWriteTool, createEditTool } from "@mariozechner/pi-coding-agent";
import piExtension from "../pi.ts";

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Build a minimal pi ExtensionAPI stub. */
function makePI() {
  const handlers: Record<string, Function[]> = {};
  const tools: Record<string, any> = {};
  const stub = {
    on(event: string, handler: Function) {
      (handlers[event] ??= []).push(handler);
    },
    registerTool(spec: { name: string; [k: string]: any }) {
      tools[spec.name] = spec;
    },
    sendUserMessage: vi.fn(),
    async emit(event: string, ...args: any[]) {
      const fns = handlers[event] ?? [];
      return Promise.all(fns.map((fn) => fn(...args)));
    },
    handlers,
    tools,
    ui: { setStatus: vi.fn() },
  };
  return stub;
}

// ── Setup ─────────────────────────────────────────────────────────────────────

const readFileSyncMock = readFileSync as unknown as Mock;
const createWriteToolMock = createWriteTool as unknown as Mock;
const createEditToolMock = createEditTool as unknown as Mock;

let pi: ReturnType<typeof makePI>;

beforeEach(() => {
  vi.clearAllMocks();
  pi = makePI();

  // Reset default mock behaviors
  mockNephInstance.connect.mockResolvedValue(undefined);
  mockNephInstance.register.mockResolvedValue(undefined);
  mockNephInstance.review.mockResolvedValue({
    schema: "review/v1",
    decision: "accept",
    content: "accepted",
    hunks: [],
  });
  mockNephInstance.setStatus.mockResolvedValue(undefined);
  mockNephInstance.unsetStatus.mockResolvedValue(undefined);
  mockNephInstance.checktime.mockResolvedValue(undefined);

  createWriteToolMock.mockReturnValue({
    parameters: {},
    execute: vi.fn().mockResolvedValue({
      content: [{ type: "text", text: "written" }],
      details: {},
    }),
  });
  createEditToolMock.mockReturnValue({
    parameters: {},
    execute: vi.fn().mockResolvedValue({
      content: [{ type: "text", text: "edited" }],
      details: {},
    }),
  });

  piExtension(pi as any);
});

// Helper: activate the extension by firing session_start
async function activate(): Promise<void> {
  await pi.emit("session_start", {}, { ui: pi.ui });
}

// ── Connection lifecycle tests ──────────────────────────────────────────────

describe("connection lifecycle", () => {
  it("session_start connects and registers with bus", async () => {
    await activate();

    expect(mockNephInstance.connect).toHaveBeenCalled();
    expect(mockNephInstance.register).toHaveBeenCalledWith("pi");
  });

  it("session_start registers onPrompt callback", async () => {
    await activate();

    expect(mockNephInstance.onPrompt).toHaveBeenCalledWith(
      expect.any(Function),
    );
  });

  it("session_start sets nvim status", async () => {
    await activate();

    expect(pi.ui.setStatus).toHaveBeenCalledWith("nvim", "🗿NEPH");
  });

  it("session_start registers write and edit tools", async () => {
    await activate();

    expect(pi.tools["write"]).toBeDefined();
    expect(pi.tools["edit"]).toBeDefined();
  });

  it("session_shutdown disconnects from bus", async () => {
    await activate();
    await pi.emit("session_shutdown");

    expect(mockNephInstance.disconnect).toHaveBeenCalled();
  });
});

// ── Prompt delivery tests ───────────────────────────────────────────────────

describe("prompt delivery", () => {
  it("prompts from bus are forwarded to pi.sendUserMessage", async () => {
    await activate();

    // Get the onPrompt callback and invoke it
    const promptCallback = mockNephInstance.onPrompt.mock.calls[0][0];
    promptCallback("fix the bug");

    expect(pi.sendUserMessage).toHaveBeenCalledWith("fix the bug");
  });
});

// ── Status event tests ──────────────────────────────────────────────────────

describe("status events", () => {
  it("agent_start sets pi_running status via bus", async () => {
    await activate();
    mockNephInstance.setStatus.mockClear();

    await pi.emit("agent_start");

    expect(mockNephInstance.setStatus).toHaveBeenCalledWith(
      "pi_running",
      "true",
    );
  });

  it("agent_end unsets pi_running and pi_reading, calls checktime", async () => {
    await activate();
    mockNephInstance.unsetStatus.mockClear();
    mockNephInstance.checktime.mockClear();

    await pi.emit("agent_end", {}, { ui: pi.ui });

    expect(mockNephInstance.unsetStatus).toHaveBeenCalledWith("pi_running");
    expect(mockNephInstance.unsetStatus).toHaveBeenCalledWith("pi_reading");
    expect(mockNephInstance.checktime).toHaveBeenCalled();
    expect(pi.ui.setStatus).toHaveBeenCalledWith("nvim-reading", "");
  });

  it("tool_call with read sets pi_reading status via bus", async () => {
    await activate();
    mockNephInstance.setStatus.mockClear();

    await pi.emit(
      "tool_call",
      { toolName: "read", input: { path: "/foo/bar.ts" } },
      { ui: pi.ui, cwd: "/foo" },
    );

    expect(mockNephInstance.setStatus).toHaveBeenCalledWith(
      "pi_reading",
      "bar.ts",
    );
  });

  it("tool_call with read sets ctx.ui.setStatus with short path", async () => {
    await activate();
    pi.ui.setStatus.mockClear();

    await pi.emit(
      "tool_call",
      { toolName: "read", input: { path: "bar.ts" } },
      { ui: pi.ui, cwd: "/foo" },
    );

    expect(pi.ui.setStatus).toHaveBeenCalledWith(
      "nvim-reading",
      expect.stringContaining("bar.ts"),
    );
  });

  it("tool_result with write/edit calls checktime", async () => {
    await activate();
    mockNephInstance.checktime.mockClear();

    await pi.emit("tool_result", { toolName: "write" });

    expect(mockNephInstance.checktime).toHaveBeenCalled();
  });
});

// ── review() via NephClient tests ───────────────────────────────────────────

describe("review via NephClient", () => {
  beforeEach(async () => {
    await activate();
  });

  it("returns accept decision from NephClient review", async () => {
    mockNephInstance.review.mockResolvedValue({
      schema: "review/v1",
      decision: "accept",
      content: "final",
      hunks: [],
    });

    const writeTool = pi.tools["write"];
    const result = await writeTool.execute(
      "id",
      { path: "/tmp/a.ts", content: "new" },
      null,
      vi.fn(),
      { cwd: "/tmp" },
    );
    expect(result.content[0].text).toBe("written");
  });

  it("returns reject decision from NephClient review", async () => {
    mockNephInstance.review.mockResolvedValue({
      schema: "review/v1",
      decision: "reject",
      content: "",
      hunks: [],
      reason: "too noisy",
    });

    const writeTool = pi.tools["write"];
    const result = await writeTool.execute(
      "id",
      { path: "/tmp/b.ts", content: "new" },
      null,
      vi.fn(),
      { cwd: "/tmp" },
    );
    expect(result.content[0].text).toMatch(/rejected.*too noisy/i);
  });

  it("calls NephClient.review with resolved file path and content", async () => {
    mockNephInstance.review.mockResolvedValue({
      schema: "review/v1",
      decision: "accept",
      content: "ok",
      hunks: [],
    });

    const writeTool = pi.tools["write"];
    await writeTool.execute(
      "id",
      { path: "x.ts", content: "proposed content" },
      null,
      vi.fn(),
      { cwd: "/tmp" },
    );

    expect(mockNephInstance.review).toHaveBeenCalledWith(
      "/tmp/x.ts",
      "proposed content",
    );
  });
});

// ── write tool override tests ─────────────────────────────────────────────────

describe("write tool override", () => {
  beforeEach(async () => {
    await activate();
  });

  it("calls createWriteTool execute with accepted content", async () => {
    const mockExecute = vi.fn().mockResolvedValue({
      content: [{ type: "text", text: "written" }],
      details: {},
    });
    createWriteToolMock.mockReturnValue({
      parameters: {},
      execute: mockExecute,
    });

    mockNephInstance.review.mockResolvedValue({
      schema: "review/v1",
      decision: "accept",
      content: "accepted!",
      hunks: [],
    });

    const writeTool = pi.tools["write"];
    await writeTool.execute(
      "id",
      { path: "/f.ts", content: "new" },
      null,
      vi.fn(),
      { cwd: "/" },
    );
    expect(mockExecute).toHaveBeenCalledWith(
      "id",
      expect.objectContaining({ content: "accepted!" }),
      null,
      expect.any(Function),
    );
  });

  it("does not call execute when rejected", async () => {
    const mockExecute = vi.fn();
    createWriteToolMock.mockReturnValue({
      parameters: {},
      execute: mockExecute,
    });

    mockNephInstance.review.mockResolvedValue({
      schema: "review/v1",
      decision: "reject",
      content: "",
      hunks: [],
      reason: "nope",
    });

    const writeTool = pi.tools["write"];
    const result = await writeTool.execute(
      "id",
      { path: "/f.ts", content: "new" },
      null,
      vi.fn(),
      { cwd: "/" },
    );

    expect(mockExecute).not.toHaveBeenCalled();
    expect(result.content[0].text).toMatch(/rejected.*nope/i);
  });

  it("surfaces partial rejection notes for decision:partial", async () => {
    createWriteToolMock.mockReturnValue({
      parameters: {},
      execute: vi.fn().mockResolvedValue({
        content: [{ type: "text", text: "written" }],
        details: {},
      }),
    });

    mockNephInstance.review.mockResolvedValue({
      schema: "review/v1",
      decision: "partial",
      content: "ok",
      hunks: [
        { index: 1, decision: "accept" },
        { index: 2, decision: "reject", reason: "hunk 2 skipped" },
      ],
      reason: "hunk 2 skipped",
    });

    const writeTool = pi.tools["write"];
    const result = await writeTool.execute(
      "id",
      { path: "/f.ts", content: "new" },
      null,
      vi.fn(),
      { cwd: "/" },
    );
    const texts = (result.content as { text: string }[]).map(
      (c: { text: string }) => c.text,
    );
    expect(texts.some((t: string) => t.includes("hunk 2 skipped"))).toBe(true);
  });
});

// ── edit tool override tests ──────────────────────────────────────────────────

describe("edit tool override", () => {
  beforeEach(async () => {
    await activate();
  });

  it("returns error when file cannot be read", async () => {
    readFileSyncMock.mockImplementation(() => {
      throw new Error("ENOENT");
    });
    const editTool = pi.tools["edit"];
    const result = await editTool.execute(
      "id",
      { path: "/missing.ts", oldText: "x", newText: "y" },
      null,
      vi.fn(),
      { cwd: "/" },
    );
    expect(result.content[0].text).toMatch(/cannot read/i);
  });

  it("returns error when oldText is not found, does not call review", async () => {
    readFileSyncMock.mockReturnValue("hello world");
    const editTool = pi.tools["edit"];
    const result = await editTool.execute(
      "id",
      { path: "/f.ts", oldText: "not present", newText: "y" },
      null,
      vi.fn(),
      { cwd: "/" },
    );
    expect(result.content[0].text).toMatch(/edit failed/i);
    expect(mockNephInstance.review).not.toHaveBeenCalled();
  });

  it("applies accepted content via createWriteTool (full file content)", async () => {
    readFileSyncMock.mockReturnValue("hello world");
    const mockEditExecute = vi.fn();
    const mockWriteExecute = vi.fn().mockResolvedValue({
      content: [{ type: "text", text: "written" }],
      details: {},
    });
    createEditToolMock.mockReturnValue({
      parameters: {},
      execute: mockEditExecute,
    });
    createWriteToolMock.mockReturnValue({
      parameters: {},
      execute: mockWriteExecute,
    });

    mockNephInstance.review.mockResolvedValue({
      schema: "review/v1",
      decision: "accept",
      content: "hello universe",
      hunks: [],
    });

    const editTool = pi.tools["edit"];
    const result = await editTool.execute(
      "id",
      { path: "/f.ts", oldText: "world", newText: "universe" },
      null,
      vi.fn(),
      { cwd: "/" },
    );
    expect(mockWriteExecute).toHaveBeenCalledWith(
      "id",
      expect.objectContaining({ content: "hello universe" }),
      null,
      expect.any(Function),
    );
    expect(mockEditExecute).not.toHaveBeenCalled();
    expect(result.content[0].text).toBe("written");
  });

  it("returns rejection text when review rejects", async () => {
    readFileSyncMock.mockReturnValue("hello world");
    createEditToolMock.mockReturnValue({ parameters: {}, execute: vi.fn() });

    mockNephInstance.review.mockResolvedValue({
      schema: "review/v1",
      decision: "reject",
      content: "",
      hunks: [],
      reason: "bad change",
    });

    const editTool = pi.tools["edit"];
    const result = await editTool.execute(
      "id",
      { path: "/f.ts", oldText: "world", newText: "x" },
      null,
      vi.fn(),
      { cwd: "/" },
    );
    expect(result.content[0].text).toMatch(/rejected.*bad change/i);
  });
});
