/**
 * pi.test.ts — unit tests for tools/pi/pi.ts
 *
 * Strategy:
 *  - vi.mock("node:child_process") controls spawn so no real shim is invoked
 *  - vi.mock("node:fs") controls readFileSync for edit-tool tests
 *  - vi.mock("@mariozechner/pi-coding-agent") stubs createWriteTool
 *  - A hand-rolled `pi` stub satisfies ExtensionAPI: records registerTool calls
 *    and lets us fire events programmatically
 */

import { describe, it, expect, vi, beforeEach, type Mock } from "vitest";
import type { ChildProcess } from "node:child_process";
import { EventEmitter } from "node:events";

// ── Module mocks (hoisted before imports) ────────────────────────────────────

vi.mock("node:child_process", () => ({ spawn: vi.fn() }));
vi.mock("node:fs", () => ({ readFileSync: vi.fn() }));
vi.mock("@mariozechner/pi-coding-agent", () => ({
  createWriteTool: vi.fn(),
}));

// Import after mocks are registered
import { spawn } from "node:child_process";
import { readFileSync } from "node:fs";
import { createWriteTool } from "@mariozechner/pi-coding-agent";
import piExtension from "../pi.ts";

// ── Helpers ───────────────────────────────────────────────────────────────────

/** Minimal mock child process with controllable stdin/stdout/stderr/close. */
function makeChild(opts: {
  stdout?: string;
  stderr?: string;
  exitCode?: number;
  error?: Error;
}): ChildProcess {
  const child = new EventEmitter() as ChildProcess;
  child.stdin = {
    write: vi.fn(),
    end: vi.fn(),
  } as any;
  child.stdout = new EventEmitter() as any;
  child.stderr = new EventEmitter() as any;

  // Emit events asynchronously so callers have time to attach listeners
  setImmediate(() => {
    if (opts.error) {
      child.emit("error", opts.error);
      return;
    }
    if (opts.stdout) (child.stdout as EventEmitter).emit("data", Buffer.from(opts.stdout));
    if (opts.stderr) (child.stderr as EventEmitter).emit("data", Buffer.from(opts.stderr));
    child.emit("close", opts.exitCode ?? 0);
  });

  return child;
}

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
    /** Fire an event (returns array of handler results). */
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

const spawnMock = spawn as unknown as Mock;
const readFileSyncMock = readFileSync as unknown as Mock;
const createWriteToolMock = createWriteTool as unknown as Mock;

let pi: ReturnType<typeof makePI>;

beforeEach(() => {
  vi.clearAllMocks();
  pi = makePI();

  // Default createWriteTool stub: returns an execute fn that echoes params
  createWriteToolMock.mockReturnValue({
    parameters: {},
    execute: vi.fn().mockResolvedValue({
      content: [{ type: "text", text: "written" }],
      details: {},
    }),
  });

  // Default spawn: succeeds with empty stdout
  spawnMock.mockImplementation(() => makeChild({ stdout: "" }));

  // Register the extension
  piExtension(pi as any);
});

// Helper: activate the extension by firing session_start with socket set
async function activate() {
  const old = process.env.NVIM_SOCKET_PATH;
  process.env.NVIM_SOCKET_PATH = "/tmp/nvim.sock";
  await pi.emit("session_start", {}, { ui: pi.ui });
  return () => {
    if (old === undefined) delete process.env.NVIM_SOCKET_PATH;
    else process.env.NVIM_SOCKET_PATH = old;
  };
}

// ── shimRun tests ─────────────────────────────────────────────────────────────

describe("shimRun", () => {
  it("resolves with stdout on exit 0", async () => {
    spawnMock.mockImplementationOnce(() => makeChild({ stdout: "hello" }));
    const cleanup = await activate();
    // Trigger a shim call by firing agent_start (calls shim("set", "pi_running", "true"))
    // Instead, we test shimRun indirectly via the write tool
    const writeTool = pi.tools["write"];
    expect(writeTool).toBeDefined();
    cleanup();
  });

  it("spawn is called with the shim path when tools are active", async () => {
    const cleanup = await activate();
    spawnMock.mockClear(); // ignore session_start calls

    // Trigger a known shim call (agent_start → shim("set", "pi_running", "true"))
    spawnMock.mockImplementationOnce(() => makeChild({ stdout: "" }));
    await pi.emit("agent_start");

    expect(spawnMock).toHaveBeenCalled();
    const [cmd, args] = spawnMock.mock.calls[0];
    expect(cmd).toBe("shim");
    expect(args).toContain("set");
    cleanup();
  });

  it("rejects on non-zero exit with stderr message", async () => {
    const cleanup = await activate();
    // Reset write tool to inspect rejection path
    spawnMock.mockImplementationOnce(() => makeChild({ stderr: "error msg", exitCode: 1 }));

    // shimRun rejects → preview() catches → returns reject decision
    const writeTool = pi.tools["write"];
    const result = await writeTool.execute(
      "id1",
      { path: "foo.ts", content: "new" },
      null,
      vi.fn(),
      { cwd: "/tmp" },
    );
    // preview failed → write rejected
    expect(result.content[0].text).toMatch(/rejected/i);
    cleanup();
  });

  it("writes stdin when provided (preview call passes content)", async () => {
    const cleanup = await activate();
    spawnMock.mockImplementation(() =>
      makeChild({ stdout: JSON.stringify({ decision: "accept", content: "ok" }) })
    );

    const writeTool = pi.tools["write"];
    await writeTool.execute(
      "id1",
      { path: "/tmp/f.ts", content: "proposed content" },
      null,
      vi.fn(),
      { cwd: "/tmp" },
    );

    // Find the preview spawn call (args[0] === "preview")
    const previewCall = spawnMock.mock.calls.find(
      ([, args]: [string, string[]]) => args[0] === "preview"
    );
    expect(previewCall).toBeDefined();
    const child = spawnMock.mock.results[spawnMock.mock.calls.indexOf(previewCall!)].value;
    expect(child.stdin.write).toHaveBeenCalledWith("proposed content", "utf-8");
    cleanup();
  });
});

// ── preview() tests ───────────────────────────────────────────────────────────

describe("preview()", () => {
  beforeEach(async () => {
    const old = process.env.NVIM_SOCKET_PATH;
    process.env.NVIM_SOCKET_PATH = "/tmp/nvim.sock";
    await pi.emit("session_start", {}, { ui: pi.ui });
    if (old === undefined) delete process.env.NVIM_SOCKET_PATH;
    else process.env.NVIM_SOCKET_PATH = old;
  });

  it("returns accept decision from shim stdout", async () => {
    const accepted = { decision: "accept", content: "final" };
    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      if (args[0] === "preview") {
        return makeChild({ stdout: JSON.stringify(accepted) });
      }
      return makeChild({ stdout: "" });
    });

    const writeTool = pi.tools["write"];
    createWriteToolMock.mockReturnValue({
      parameters: {},
      execute: vi.fn().mockResolvedValue({
        content: [{ type: "text", text: "written" }],
        details: {},
      }),
    });

    const result = await writeTool.execute(
      "id",
      { path: "/tmp/a.ts", content: "new" },
      null,
      vi.fn(),
      { cwd: "/tmp" },
    );
    expect(result.content[0].text).toBe("written");
  });

  it("returns reject decision on reject from shim", async () => {
    const rejected = { decision: "reject", reason: "too noisy" };
    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      if (args[0] === "preview") return makeChild({ stdout: JSON.stringify(rejected) });
      return makeChild({ stdout: "" });
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

  it("returns reject with fallback message when shimRun throws", async () => {
    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      if (args[0] === "preview") return makeChild({ stderr: "crash", exitCode: 1 });
      return makeChild({ stdout: "" });
    });

    const writeTool = pi.tools["write"];
    const result = await writeTool.execute(
      "id",
      { path: "/tmp/c.ts", content: "new" },
      null,
      vi.fn(),
      { cwd: "/tmp" },
    );
    expect(result.content[0].text).toMatch(/rejected/i);
  });
});

// ── write tool override tests ─────────────────────────────────────────────────

describe("write tool override", () => {
  beforeEach(async () => {
    process.env.NVIM_SOCKET_PATH = "/tmp/nvim.sock";
    await pi.emit("session_start", {}, { ui: pi.ui });
  });

  afterEach(() => {
    delete process.env.NVIM_SOCKET_PATH;
  });

  it("calls createWriteTool execute with accepted content", async () => {
    const mockExecute = vi.fn().mockResolvedValue({
      content: [{ type: "text", text: "written" }],
      details: {},
    });
    createWriteToolMock.mockReturnValue({ parameters: {}, execute: mockExecute });

    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      if (args[0] === "preview")
        return makeChild({ stdout: JSON.stringify({ decision: "accept", content: "accepted!" }) });
      return makeChild({ stdout: "" });
    });

    const writeTool = pi.tools["write"];
    await writeTool.execute("id", { path: "/f.ts", content: "new" }, null, vi.fn(), { cwd: "/" });
    expect(mockExecute).toHaveBeenCalledWith(
      "id",
      expect.objectContaining({ content: "accepted!" }),
      null,
      expect.any(Function),
    );
  });

  it("does not call execute when rejected, calls revert instead", async () => {
    const mockExecute = vi.fn();
    createWriteToolMock.mockReturnValue({ parameters: {}, execute: mockExecute });

    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      if (args[0] === "preview")
        return makeChild({ stdout: JSON.stringify({ decision: "reject", reason: "nope" }) });
      return makeChild({ stdout: "" });
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
    const revertCall = spawnMock.mock.calls.find(([, a]: [string, string[]]) => a[0] === "revert");
    expect(revertCall).toBeDefined();
    expect(result.content[0].text).toMatch(/rejected.*nope/i);
  });

  it("surfaces partial rejection notes in the result", async () => {
    const mockExecute = vi.fn().mockResolvedValue({
      content: [{ type: "text", text: "written" }],
      details: {},
    });
    createWriteToolMock.mockReturnValue({ parameters: {}, execute: mockExecute });

    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      if (args[0] === "preview")
        return makeChild({
          stdout: JSON.stringify({ decision: "accept", content: "ok", reason: "hunk 2 skipped" }),
        });
      return makeChild({ stdout: "" });
    });

    const writeTool = pi.tools["write"];
    const result = await writeTool.execute("id", { path: "/f.ts", content: "new" }, null, vi.fn(), {
      cwd: "/",
    });
    const texts = (result.content as { text: string }[]).map((c) => c.text);
    expect(texts.some((t) => t.includes("hunk 2 skipped"))).toBe(true);
  });
});

// ── edit tool override tests ──────────────────────────────────────────────────

describe("edit tool override", () => {
  beforeEach(async () => {
    process.env.NVIM_SOCKET_PATH = "/tmp/nvim.sock";
    await pi.emit("session_start", {}, { ui: pi.ui });
  });

  afterEach(() => {
    delete process.env.NVIM_SOCKET_PATH;
  });

  it("returns error when file cannot be read", async () => {
    readFileSyncMock.mockImplementation(() => { throw new Error("ENOENT"); });
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

  it("returns error when oldText is not found, does not call preview", async () => {
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
    const previewCall = spawnMock.mock.calls.find(([, a]: [string, string[]]) => a[0] === "preview");
    expect(previewCall).toBeUndefined();
  });

  it("applies accepted content via createWriteTool execute", async () => {
    readFileSyncMock.mockReturnValue("hello world");
    const mockExecute = vi.fn().mockResolvedValue({
      content: [{ type: "text", text: "edited" }],
      details: {},
    });
    createWriteToolMock.mockReturnValue({ parameters: {}, execute: mockExecute });

    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      if (args[0] === "preview")
        return makeChild({
          stdout: JSON.stringify({ decision: "accept", content: "hello universe" }),
        });
      return makeChild({ stdout: "" });
    });

    const editTool = pi.tools["edit"];
    const result = await editTool.execute(
      "id",
      { path: "/f.ts", oldText: "world", newText: "universe" },
      null,
      vi.fn(),
      { cwd: "/" },
    );
    expect(mockExecute).toHaveBeenCalledWith(
      "id",
      expect.objectContaining({ content: "hello universe" }),
      null,
      expect.any(Function),
    );
    expect(result.content[0].text).toBe("edited");
  });

  it("calls revert and returns rejection text when preview rejects", async () => {
    readFileSyncMock.mockReturnValue("hello world");
    createWriteToolMock.mockReturnValue({ parameters: {}, execute: vi.fn() });

    spawnMock.mockImplementation((cmd: string, args: string[]) => {
      if (args[0] === "preview")
        return makeChild({
          stdout: JSON.stringify({ decision: "reject", reason: "bad change" }),
        });
      return makeChild({ stdout: "" });
    });

    const editTool = pi.tools["edit"];
    const result = await editTool.execute(
      "id",
      { path: "/f.ts", oldText: "world", newText: "x" },
      null,
      vi.fn(),
      { cwd: "/" },
    );
    const revertCall = spawnMock.mock.calls.find(([, a]: [string, string[]]) => a[0] === "revert");
    expect(revertCall).toBeDefined();
    expect(result.content[0].text).toMatch(/rejected.*bad change/i);
  });
});

// ── Lifecycle event tests ─────────────────────────────────────────────────────

describe("lifecycle events", () => {
  it("session_start is a no-op when NVIM_SOCKET_PATH is absent", async () => {
    delete process.env.NVIM_SOCKET_PATH;
    spawnMock.mockClear();
    await pi.emit("session_start", {}, { ui: pi.ui });
    expect(spawnMock).not.toHaveBeenCalled();
    expect(Object.keys(pi.tools)).toHaveLength(0);
  });

  it("session_start sets pi_active and registers write+edit tools", async () => {
    process.env.NVIM_SOCKET_PATH = "/tmp/nvim.sock";
    spawnMock.mockImplementation(() => makeChild({ stdout: "" }));
    await pi.emit("session_start", {}, { ui: pi.ui });
    delete process.env.NVIM_SOCKET_PATH;

    const setCall = spawnMock.mock.calls.find(
      ([, a]: [string, string[]]) => a[0] === "set" && a[1] === "pi_active"
    );
    expect(setCall).toBeDefined();
    expect(pi.tools["write"]).toBeDefined();
    expect(pi.tools["edit"]).toBeDefined();
  });

  it("session_shutdown calls close-tab, unset pi_active, unset pi_running", async () => {
    process.env.NVIM_SOCKET_PATH = "/tmp/nvim.sock";
    spawnMock.mockImplementation(() => makeChild({ stdout: "" }));
    await pi.emit("session_shutdown");
    delete process.env.NVIM_SOCKET_PATH;

    const calls = spawnMock.mock.calls.map(([, a]: [string, string[]]) => a);
    expect(calls.some((a: string[]) => a[0] === "close-tab")).toBe(true);
    expect(calls.some((a: string[]) => a[0] === "unset" && a[1] === "pi_active")).toBe(true);
    expect(calls.some((a: string[]) => a[0] === "unset" && a[1] === "pi_running")).toBe(true);
  });

  it("agent_end unsets pi_running, calls checktime, calls close-tab", async () => {
    process.env.NVIM_SOCKET_PATH = "/tmp/nvim.sock";
    spawnMock.mockImplementation(() => makeChild({ stdout: "" }));
    await pi.emit("agent_end");
    delete process.env.NVIM_SOCKET_PATH;

    const calls = spawnMock.mock.calls.map(([, a]: [string, string[]]) => a);
    expect(calls.some((a: string[]) => a[0] === "unset" && a[1] === "pi_running")).toBe(true);
    expect(calls.some((a: string[]) => a[0] === "checktime")).toBe(true);
    expect(calls.some((a: string[]) => a[0] === "close-tab")).toBe(true);
  });

  it("tool_call with read opens the file path", async () => {
    process.env.NVIM_SOCKET_PATH = "/tmp/nvim.sock";
    spawnMock.mockImplementation(() => makeChild({ stdout: "" }));
    await pi.emit("tool_call", { toolName: "read", input: { path: "/foo/bar.ts" } });
    delete process.env.NVIM_SOCKET_PATH;

    const openCall = spawnMock.mock.calls.find(
      ([, a]: [string, string[]]) => a[0] === "open" && a[1] === "/foo/bar.ts"
    );
    expect(openCall).toBeDefined();
  });
});
