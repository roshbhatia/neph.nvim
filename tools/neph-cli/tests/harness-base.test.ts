// tools/neph-cli/tests/harness-base.test.ts
// Unit tests for tools/lib/harness-base.ts covering ContentHelper.reconstructContent,
// CupcakeHelper.cupcakeEval, and createSessionSignals.

import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";

const mockReadFileSync = vi.fn();
const mockExecFileSync = vi.fn();

const mockExistsSync = vi.fn();
vi.mock("node:fs", () => ({
  readFileSync: (...args: any[]) => mockReadFileSync(...args),
  existsSync: (...args: any[]) => mockExistsSync(...args),
}));
vi.mock("node:child_process", () => ({ execFileSync: (...args: any[]) => mockExecFileSync(...args) }));
vi.mock("../../lib/log", () => ({ debug: vi.fn() }));

const mockPqCall = vi.fn();
const mockPqClose = vi.fn();
vi.mock("../../lib/neph-run", () => ({
  createPersistentQueue: vi.fn(() => ({ call: mockPqCall, close: mockPqClose })),
}));

import { ContentHelper, CupcakeHelper, createSessionSignals, isNvimAvailable } from "../../lib/harness-base";

describe("ContentHelper.reconstructContent", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns content field directly when present", () => {
    const result = ContentHelper.reconstructContent("/some/file.ts", { content: "hello world" });
    expect(result).toBe("hello world");
    expect(mockReadFileSync).not.toHaveBeenCalled();
  });

  it("applies old_string + new_string replacement", () => {
    mockReadFileSync.mockReturnValue("hello foo world");
    const result = ContentHelper.reconstructContent("/some/file.ts", {
      old_string: "foo",
      new_string: "bar",
    });
    expect(result).toBe("hello bar world");
  });

  it("falls back to new_string when file is missing", () => {
    mockReadFileSync.mockImplementation(() => { throw new Error("ENOENT"); });
    const result = ContentHelper.reconstructContent("/missing/file.ts", {
      old_string: "foo",
      new_string: "bar fallback",
    });
    expect(result).toBe("bar fallback");
  });

  it("returns current file content when old_string doesn't match", () => {
    mockReadFileSync.mockReturnValue("hello world");
    const result = ContentHelper.reconstructContent("/some/file.ts", {
      old_string: "not-in-file",
      new_string: "replacement",
    });
    expect(result).toBe("hello world");
  });

  it("returns new_string when no content and no old_string provided", () => {
    const result = ContentHelper.reconstructContent("/some/file.ts", { new_string: "just new" });
    expect(result).toBe("just new");
  });

  it("replaces all occurrences when replace_all is true", () => {
    mockReadFileSync.mockReturnValue("foo foo foo");
    const result = ContentHelper.reconstructContent("/some/file.ts", {
      old_string: "foo",
      new_string: "bar",
      replace_all: true,
    });
    expect(result).toBe("bar bar bar");
  });

  it("replaces only first occurrence when replace_all is false", () => {
    mockReadFileSync.mockReturnValue("foo foo foo");
    const result = ContentHelper.reconstructContent("/some/file.ts", {
      old_string: "foo",
      new_string: "bar",
      replace_all: false,
    });
    expect(result).toBe("bar foo foo");
  });
});

describe("CupcakeHelper.cupcakeEval", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("returns allow decision on successful eval", () => {
    mockExecFileSync.mockReturnValue(JSON.stringify({ decision: "allow" }));
    const result = CupcakeHelper.cupcakeEval("claude", { tool_input: {} });
    expect(result.decision).toBe("allow");
    const call = mockExecFileSync.mock.calls[0];
    expect(call[0]).toBe("cupcake");
    expect(call[1]).toEqual(["eval", "--harness", "claude"]);
  });

  it("returns deny decision from cupcake response", () => {
    mockExecFileSync.mockReturnValue(JSON.stringify({ decision: "deny", reason: "Protected path" }));
    const result = CupcakeHelper.cupcakeEval("claude", { tool_input: {} });
    expect(result).toEqual({ decision: "deny", reason: "Protected path" });
  });

  it("returns modify decision with updated_input", () => {
    mockExecFileSync.mockReturnValue(
      JSON.stringify({ decision: "modify", updated_input: { content: "modified" } }),
    );
    const result = CupcakeHelper.cupcakeEval("claude", { tool_input: {} });
    expect(result.decision).toBe("modify");
    expect(result.updated_input?.content).toBe("modified");
  });

  it("returns deny (fail-closed) when cupcake is not on PATH", () => {
    mockExecFileSync.mockImplementation(() => {
      throw Object.assign(new Error("ENOENT"), { message: "ENOENT" });
    });
    const result = CupcakeHelper.cupcakeEval("claude", { tool_input: {} });
    expect(result.decision).toBe("deny");
    expect(result.reason).toContain("ENOENT");
  });

  it("returns deny on exit code 2 (explicit deny from Cupcake)", () => {
    const err = Object.assign(new Error("denied"), {
      status: 2,
      stderr: Buffer.from("Protected path"),
    });
    mockExecFileSync.mockImplementation(() => { throw err; });
    const result = CupcakeHelper.cupcakeEval("claude", { tool_input: {} });
    expect(result.decision).toBe("deny");
    expect(result.reason).toBe("Protected path");
  });

  it("passes event JSON as stdin to cupcake eval", () => {
    mockExecFileSync.mockReturnValue(JSON.stringify({ decision: "allow" }));
    const event = { hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: { content: "x" } };
    CupcakeHelper.cupcakeEval("gemini", event);
    const opts = mockExecFileSync.mock.calls[0][2];
    expect(JSON.parse(opts.input)).toEqual(event);
  });
});

describe("createSessionSignals", () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  it("calls pq.call set <agent>_active on setActive", () => {
    const signals = createSessionSignals("claude");
    signals.setActive();
    expect(mockPqCall).toHaveBeenCalledWith("set", "claude_active", "true");
  });

  it("calls pq.call unset <agent>_active on unsetActive", () => {
    const signals = createSessionSignals("claude");
    signals.unsetActive();
    expect(mockPqCall).toHaveBeenCalledWith("unset", "claude_active");
  });

  it("calls pq.call set <agent>_running on setRunning", () => {
    const signals = createSessionSignals("amp");
    signals.setRunning();
    expect(mockPqCall).toHaveBeenCalledWith("set", "amp_running", "true");
  });

  it("calls pq.call unset <agent>_running on unsetRunning", () => {
    const signals = createSessionSignals("amp");
    signals.unsetRunning();
    expect(mockPqCall).toHaveBeenCalledWith("unset", "amp_running");
  });

  it("calls pq.call checktime on checktime", () => {
    const signals = createSessionSignals("claude");
    signals.checktime();
    expect(mockPqCall).toHaveBeenCalledWith("checktime");
  });

  it("calls pq.close on close", () => {
    const signals = createSessionSignals("claude");
    signals.close();
    expect(mockPqClose).toHaveBeenCalled();
  });
});

describe("isNvimAvailable", () => {
  const origEnv = { ...process.env };

  beforeEach(() => {
    vi.clearAllMocks();
    delete process.env.NVIM;
    delete process.env.NVIM_SOCKET_PATH;
  });

  afterEach(() => {
    process.env.NVIM = origEnv.NVIM;
    process.env.NVIM_SOCKET_PATH = origEnv.NVIM_SOCKET_PATH;
  });

  it("returns false when no NVIM env vars are set", () => {
    expect(isNvimAvailable()).toBe(false);
    expect(mockExistsSync).not.toHaveBeenCalled();
  });

  it("returns true when NVIM is set and socket exists", () => {
    process.env.NVIM = "/tmp/nvim.12345/0";
    mockExistsSync.mockReturnValue(true);
    expect(isNvimAvailable()).toBe(true);
  });

  it("returns false when NVIM is set but socket does not exist", () => {
    process.env.NVIM = "/tmp/nvim.99999/0";
    mockExistsSync.mockReturnValue(false);
    expect(isNvimAvailable()).toBe(false);
  });

  it("uses NVIM_SOCKET_PATH as fallback", () => {
    process.env.NVIM_SOCKET_PATH = "/tmp/nvim.socket";
    mockExistsSync.mockReturnValue(true);
    expect(isNvimAvailable()).toBe(true);
    expect(mockExistsSync).toHaveBeenCalledWith("/tmp/nvim.socket");
  });
});
