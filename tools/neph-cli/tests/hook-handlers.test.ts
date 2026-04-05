// tools/neph-cli/tests/hook-handlers.test.ts
// Tests for runClaudeHook, runGeminiHook, runCursorHook in integration.ts.

import { describe, it, expect, vi, beforeEach } from "vitest";

// ---------------------------------------------------------------------------
// Mock harness-base before integration.ts is imported
// ---------------------------------------------------------------------------

const mockCupcakeEval = vi.fn();
const mockReconstructContent = vi.fn();

const mockPqCall = vi.fn();
const mockPqClose = vi.fn();
const mockCreateSessionSignals = vi.fn();

vi.mock("../../lib/harness-base", () => ({
  CupcakeHelper: {
    cupcakeEval: (...args: unknown[]) => mockCupcakeEval(...args),
  },
  ContentHelper: {
    reconstructContent: (...args: unknown[]) => mockReconstructContent(...args),
  },
  createSessionSignals: (...args: unknown[]) => mockCreateSessionSignals(...args),
}));

// Mock review (still referenced for legacy gemini path)
vi.mock("../src/review", () => ({ runReview: vi.fn() }));

// Mock fs so template reads don't fail
vi.mock("node:fs", async () => {
  const actual = await vi.importActual<typeof import("node:fs")>("node:fs");
  return {
    ...actual,
    existsSync: vi.fn(() => false),
    readFileSync: vi.fn(() => "{}"),
    writeFileSync: vi.fn(),
    mkdirSync: vi.fn(),
  };
});

import { runIntegrationCommand } from "../src/integration";

function fakeSignals() {
  return {
    setActive: vi.fn(),
    unsetActive: vi.fn(),
    setRunning: vi.fn(),
    unsetRunning: vi.fn(),
    checktime: vi.fn(),
    close: vi.fn(),
  };
}

beforeEach(() => {
  vi.clearAllMocks();
  // Default: createSessionSignals returns a fresh fake signals object
  mockCreateSessionSignals.mockImplementation(() => fakeSignals());
  // Default: cupcakeEval returns allow
  mockCupcakeEval.mockReturnValue({ decision: "allow" });
  // Default: reconstructContent returns empty string
  mockReconstructContent.mockReturnValue("reconstructed");
});

// ---------------------------------------------------------------------------
// runClaudeHook tests (task 9.2)
// ---------------------------------------------------------------------------

describe("runClaudeHook", () => {
  function invoke(event: Record<string, unknown>) {
    const chunks: string[] = [];
    const orig = process.stdout.write.bind(process.stdout);
    process.stdout.write = ((c: any) => { chunks.push(c.toString()); return true; }) as any;
    return runIntegrationCommand(
      ["integration", "hook", "claude"],
      JSON.stringify(event),
      null,
    ).then(() => {
      process.stdout.write = orig;
      return chunks.join("");
    });
  }

  it("SessionStart → sets signals active and outputs {}", async () => {
    const signals = fakeSignals();
    mockCreateSessionSignals.mockReturnValueOnce(signals);

    const out = await invoke({ hook_event_name: "SessionStart" });
    expect(signals.setActive).toHaveBeenCalled();
    expect(signals.close).toHaveBeenCalled();
    expect(JSON.parse(out)).toEqual({});
  });

  it("SessionEnd → unsets signals active and outputs {}", async () => {
    const signals = fakeSignals();
    mockCreateSessionSignals.mockReturnValueOnce(signals);

    const out = await invoke({ hook_event_name: "SessionEnd" });
    expect(signals.unsetActive).toHaveBeenCalled();
    expect(signals.close).toHaveBeenCalled();
    expect(JSON.parse(out)).toEqual({});
  });

  it("UserPromptSubmit → sets running", async () => {
    const signals = fakeSignals();
    mockCreateSessionSignals.mockReturnValueOnce(signals);

    await invoke({ hook_event_name: "UserPromptSubmit" });
    expect(signals.setRunning).toHaveBeenCalled();
  });

  it("Stop → unsets running and calls checktime", async () => {
    const signals = fakeSignals();
    mockCreateSessionSignals.mockReturnValueOnce(signals);

    await invoke({ hook_event_name: "Stop" });
    expect(signals.unsetRunning).toHaveBeenCalled();
    expect(signals.checktime).toHaveBeenCalled();
  });

  it("PostToolUse → calls checktime", async () => {
    const sig1 = fakeSignals();
    const sig2 = fakeSignals();
    mockCreateSessionSignals
      .mockReturnValueOnce(sig1) // first createSessionSignals call (immediately closed)
      .mockReturnValueOnce(sig2); // second call for checktime

    await invoke({ hook_event_name: "PostToolUse" });
    expect(sig2.checktime).toHaveBeenCalled();
  });

  it("PreToolUse with allow → hookSpecificOutput permissionDecision allow", async () => {
    mockCupcakeEval.mockReturnValue({ decision: "allow" });

    const out = await invoke({
      hook_event_name: "PreToolUse",
      tool_name: "Edit",
      tool_input: { file_path: "/tmp/test.lua", content: "hello" },
    });

    const parsed = JSON.parse(out);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
    expect(parsed.hookSpecificOutput.hookEventName).toBe("PreToolUse");
  });

  it("PreToolUse with deny → hookSpecificOutput permissionDecision deny", async () => {
    mockCupcakeEval.mockReturnValue({ decision: "deny", reason: "Protected path" });

    const out = await invoke({
      hook_event_name: "PreToolUse",
      tool_name: "Write",
      tool_input: { file_path: "/tmp/.env", content: "SECRET=x" },
    });

    const parsed = JSON.parse(out);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("deny");
  });

  it("PreToolUse with modify → hookSpecificOutput includes updatedInput", async () => {
    mockCupcakeEval.mockReturnValue({
      decision: "modify",
      updated_input: { content: "modified content" },
    });

    const out = await invoke({
      hook_event_name: "PreToolUse",
      tool_name: "Edit",
      tool_input: { file_path: "/tmp/test.lua", content: "original" },
    });

    const parsed = JSON.parse(out);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
    expect(parsed.hookSpecificOutput.updatedInput.content).toBe("modified content");
  });

  it("PreToolUse with no filePath → allow passthrough", async () => {
    const out = await invoke({
      hook_event_name: "PreToolUse",
      tool_name: "Edit",
      tool_input: {},
    });

    const parsed = JSON.parse(out);
    expect(parsed.hookSpecificOutput.permissionDecision).toBe("allow");
    expect(mockCupcakeEval).not.toHaveBeenCalled();
  });

  it("unknown hook name → outputs {}", async () => {
    const out = await invoke({ hook_event_name: "SomeUnknownHook" });
    expect(JSON.parse(out)).toEqual({});
  });

  it("invalid JSON stdin → outputs {}", async () => {
    const chunks: string[] = [];
    const orig = process.stdout.write.bind(process.stdout);
    process.stdout.write = ((c: any) => { chunks.push(c.toString()); return true; }) as any;
    await runIntegrationCommand(["integration", "hook", "claude"], "not json", null);
    process.stdout.write = orig;
    expect(JSON.parse(chunks.join(""))).toEqual({});
  });
});

// ---------------------------------------------------------------------------
// runGeminiHook tests (task 9.3)
// ---------------------------------------------------------------------------

describe("runGeminiHook", () => {
  function invoke(event: Record<string, unknown>) {
    const chunks: string[] = [];
    const orig = process.stdout.write.bind(process.stdout);
    process.stdout.write = ((c: any) => { chunks.push(c.toString()); return true; }) as any;
    return runIntegrationCommand(
      ["integration", "hook", "gemini"],
      JSON.stringify(event),
      null,
    ).then(() => {
      process.stdout.write = orig;
      return chunks.join("");
    });
  }

  it("BeforeAgent → sets running", async () => {
    const signals = fakeSignals();
    mockCreateSessionSignals.mockReturnValueOnce(signals);

    await invoke({ hook_event_name: "BeforeAgent" });
    expect(signals.setRunning).toHaveBeenCalled();
    expect(signals.close).toHaveBeenCalled();
  });

  it("AfterAgent → unsets running and calls checktime", async () => {
    const signals = fakeSignals();
    mockCreateSessionSignals.mockReturnValueOnce(signals);

    await invoke({ hook_event_name: "AfterAgent" });
    expect(signals.unsetRunning).toHaveBeenCalled();
    expect(signals.checktime).toHaveBeenCalled();
  });

  it("SessionStart → sets active", async () => {
    const signals = fakeSignals();
    mockCreateSessionSignals.mockReturnValueOnce(signals);

    await invoke({ hook_event_name: "SessionStart" });
    expect(signals.setActive).toHaveBeenCalled();
  });

  it("BeforeTool write_file → calls cupcakeEval with gemini harness", async () => {
    mockCupcakeEval.mockReturnValue({ decision: "allow" });

    await invoke({
      tool_name: "write_file",
      tool_input: { file_path: "/tmp/test.lua", content: "hello" },
    });

    expect(mockCupcakeEval).toHaveBeenCalledWith("gemini", expect.objectContaining({
      tool_name: "write_file",
    }));
  });

  it("BeforeTool with deny → outputs deny decision", async () => {
    mockCupcakeEval.mockReturnValue({ decision: "deny", reason: "Protected" });

    const out = await invoke({
      tool_name: "write_file",
      tool_input: { file_path: "/tmp/test.lua", content: "x" },
    });

    const parsed = JSON.parse(out);
    expect(parsed.decision).toBe("deny");
  });

  it("BeforeTool with modify → threads updated content into hookSpecificOutput", async () => {
    mockCupcakeEval.mockReturnValue({
      decision: "modify",
      updated_input: { content: "modified by review" },
    });

    const out = await invoke({
      tool_name: "write_file",
      tool_input: { file_path: "/tmp/test.lua", content: "original" },
    });

    const parsed = JSON.parse(out);
    expect(parsed.decision).toBe("allow");
    expect(parsed.hookSpecificOutput.tool_input.content).toBe("modified by review");
  });
});

// ---------------------------------------------------------------------------
// runCursorHook tests (task 9.4)
// ---------------------------------------------------------------------------

describe("runCursorHook", () => {
  function invoke(event: Record<string, unknown>) {
    const chunks: string[] = [];
    const orig = process.stdout.write.bind(process.stdout);
    process.stdout.write = ((c: any) => { chunks.push(c.toString()); return true; }) as any;
    return runIntegrationCommand(
      ["integration", "hook", "cursor"],
      JSON.stringify(event),
      null,
    ).then(() => {
      process.stdout.write = orig;
      return chunks.join("");
    });
  }

  it("afterFileEdit → calls checktime only (no cupcake eval)", async () => {
    const signals = fakeSignals();
    mockCreateSessionSignals.mockReturnValueOnce(signals);

    await invoke({ hook_event_name: "afterFileEdit" });

    expect(signals.checktime).toHaveBeenCalled();
    expect(mockCupcakeEval).not.toHaveBeenCalled();
  });

  it("beforeShellExecution → routes to cupcakeEval with cursor harness", async () => {
    mockCupcakeEval.mockReturnValue({ decision: "allow" });

    const out = await invoke({
      hook_event_name: "beforeShellExecution",
      command: "rm -rf /",
    });

    expect(mockCupcakeEval).toHaveBeenCalledWith("cursor", expect.objectContaining({
      hook_event_name: "beforeShellExecution",
    }));
    expect(JSON.parse(out).permission).toBe("allow");
  });

  it("beforeShellExecution with deny → returns deny permission", async () => {
    mockCupcakeEval.mockReturnValue({ decision: "deny", reason: "Dangerous" });

    const out = await invoke({
      hook_event_name: "beforeShellExecution",
      command: "rm -rf /",
    });

    expect(JSON.parse(out).permission).toBe("deny");
  });

  it("beforeMCPExecution → routes to cupcakeEval", async () => {
    mockCupcakeEval.mockReturnValue({ decision: "allow" });

    const out = await invoke({
      hook_event_name: "beforeMCPExecution",
      tool: "dangerous_tool",
    });

    expect(mockCupcakeEval).toHaveBeenCalledWith("cursor", expect.objectContaining({
      hook_event_name: "beforeMCPExecution",
    }));
    expect(JSON.parse(out).permission).toBe("allow");
  });

  it("unknown hook name → outputs {}", async () => {
    const out = await invoke({ hook_event_name: "unknownCursorHook" });
    expect(JSON.parse(out)).toEqual({});
  });
});
