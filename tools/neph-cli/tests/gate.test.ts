// tools/neph-cli/tests/gate.test.ts
// Unit tests for gate-parsers.ts — one describe block per agent parser.
// Covers both positive cases (valid gate event found) and negative cases (no gate).

import { describe, it, expect, vi } from "vitest";

vi.mock("../../lib/log", () => ({ debug: vi.fn() }));

import {
  parseClaudePayload,
  parseGeminiPayload,
  parseCodexPayload,
  parseCopilotPayload,
  parseCursorPayload,
  parseGatePayload,
  isWriteEvent,
  isLifecycleEvent,
  type ParsedGateEvent,
  type AgentName,
} from "../src/gate-parsers";

// ---------------------------------------------------------------------------
// Claude parser
// ---------------------------------------------------------------------------

describe("parseClaudePayload", () => {
  describe("positive: write events", () => {
    it("PreToolUse Write with file_path → write event", () => {
      const result = parseClaudePayload({
        hook_event_name: "PreToolUse",
        tool_name: "Write",
        tool_input: { file_path: "/tmp/foo.ts", content: "hello" },
      });
      expect(result).not.toBeNull();
      expect(result!.kind).toBe("write");
      if (result!.kind === "write") {
        expect(result.path).toBe("/tmp/foo.ts");
        expect(result.content).toBe("hello");
        expect(result.toolName).toBe("Write");
        expect(result.agent).toBe("claude");
      }
    });

    it("PreToolUse Edit with path alias → write event", () => {
      const result = parseClaudePayload({
        hook_event_name: "PreToolUse",
        tool_name: "Edit",
        tool_input: { path: "/src/main.ts", content: "// updated" },
      });
      expect(result?.kind).toBe("write");
      if (result?.kind === "write") {
        expect(result.path).toBe("/src/main.ts");
        expect(result.toolName).toBe("Edit");
      }
    });

    it("PreToolUse MultiEdit → write event", () => {
      const result = parseClaudePayload({
        hook_event_name: "PreToolUse",
        tool_name: "MultiEdit",
        tool_input: { file_path: "/a.ts", content: "x" },
      });
      expect(result?.kind).toBe("write");
    });

    it("PreToolUse NotebookEdit → write event", () => {
      const result = parseClaudePayload({
        hook_event_name: "PreToolUse",
        tool_name: "NotebookEdit",
        tool_input: { file_path: "/notebook.ipynb", content: "{}" },
      });
      expect(result?.kind).toBe("write");
    });

    it("PreToolUse Write with empty content → write event with empty content", () => {
      const result = parseClaudePayload({
        hook_event_name: "PreToolUse",
        tool_name: "Write",
        tool_input: { file_path: "/x.ts" },
      });
      expect(result?.kind).toBe("write");
      if (result?.kind === "write") {
        expect(result.content).toBe("");
      }
    });
  });

  describe("positive: lifecycle events", () => {
    const lifecycleHooks = ["SessionStart", "SessionEnd", "UserPromptSubmit", "Stop", "PostToolUse"];
    for (const hook of lifecycleHooks) {
      it(`${hook} → lifecycle event`, () => {
        const result = parseClaudePayload({ hook_event_name: hook });
        expect(result?.kind).toBe("lifecycle");
        if (result?.kind === "lifecycle") {
          expect(result.hookName).toBe(hook);
          expect(result.agent).toBe("claude");
        }
      });
    }
  });

  describe("negative: passthrough cases", () => {
    it("PreToolUse with non-write tool → passthrough", () => {
      const result = parseClaudePayload({
        hook_event_name: "PreToolUse",
        tool_name: "Bash",
        tool_input: { command: "ls" },
      });
      expect(result?.kind).toBe("passthrough");
    });

    it("PreToolUse Write without file_path → passthrough", () => {
      const result = parseClaudePayload({
        hook_event_name: "PreToolUse",
        tool_name: "Write",
        tool_input: {},
      });
      expect(result?.kind).toBe("passthrough");
    });

    it("PreToolUse without tool_name → passthrough", () => {
      const result = parseClaudePayload({ hook_event_name: "PreToolUse" });
      expect(result?.kind).toBe("passthrough");
    });

    it("unknown hook_event_name → passthrough", () => {
      const result = parseClaudePayload({ hook_event_name: "FutureHook" });
      expect(result?.kind).toBe("passthrough");
    });

    it("no hook_event_name field → passthrough", () => {
      const result = parseClaudePayload({ tool_name: "Write" });
      expect(result?.kind).toBe("passthrough");
    });
  });

  describe("null returns (parse failure)", () => {
    it("null input → null", () => {
      expect(parseClaudePayload(null)).toBeNull();
    });

    it("undefined input → null", () => {
      expect(parseClaudePayload(undefined)).toBeNull();
    });

    it("empty string → null", () => {
      expect(parseClaudePayload("")).toBeNull();
    });

    it("malformed JSON string → null", () => {
      expect(parseClaudePayload("{bad json")).toBeNull();
    });

    it("JSON array → null", () => {
      expect(parseClaudePayload("[]")).toBeNull();
    });

    it("number → null", () => {
      expect(parseClaudePayload(42)).toBeNull();
    });
  });

  describe("immutability", () => {
    it("does not mutate its input object", () => {
      const input = {
        hook_event_name: "PreToolUse",
        tool_name: "Write",
        tool_input: { file_path: "/x.ts", content: "abc" },
      };
      const before = JSON.stringify(input);
      parseClaudePayload(input);
      expect(JSON.stringify(input)).toBe(before);
    });
  });
});

// ---------------------------------------------------------------------------
// Gemini parser
// ---------------------------------------------------------------------------

describe("parseGeminiPayload", () => {
  describe("positive: write events", () => {
    it("write_file with file_path → write event", () => {
      const result = parseGeminiPayload({
        tool_name: "write_file",
        tool_input: { file_path: "/tmp/out.lua", content: "return {}" },
      });
      expect(result?.kind).toBe("write");
      if (result?.kind === "write") {
        expect(result.path).toBe("/tmp/out.lua");
        expect(result.content).toBe("return {}");
        expect(result.agent).toBe("gemini");
      }
    });

    it("edit_file with file_path → write event", () => {
      const result = parseGeminiPayload({
        tool_name: "edit_file",
        tool_input: { file_path: "/src/x.py", content: "x = 1" },
      });
      expect(result?.kind).toBe("write");
    });

    it("camelCase toolName alias → write event", () => {
      const result = parseGeminiPayload({
        toolName: "write_file",
        toolInput: { file_path: "/a.ts", content: "hello" },
      });
      expect(result?.kind).toBe("write");
    });

    it("filepath alias in tool_input → write event", () => {
      const result = parseGeminiPayload({
        tool_name: "write_file",
        tool_input: { filepath: "/b.ts", content: "world" },
      });
      expect(result?.kind).toBe("write");
      if (result?.kind === "write") {
        expect(result.path).toBe("/b.ts");
      }
    });
  });

  describe("positive: lifecycle events", () => {
    const lifecycleHooks = ["SessionStart", "SessionEnd", "BeforeAgent", "AfterAgent", "AfterTool"];
    for (const hook of lifecycleHooks) {
      it(`${hook} → lifecycle event`, () => {
        const result = parseGeminiPayload({ hook_event_name: hook });
        expect(result?.kind).toBe("lifecycle");
        if (result?.kind === "lifecycle") {
          expect(result.agent).toBe("gemini");
        }
      });
    }
  });

  describe("negative: passthrough cases", () => {
    it("read_file tool → passthrough", () => {
      const result = parseGeminiPayload({
        tool_name: "read_file",
        tool_input: { file_path: "/tmp/x.ts" },
      });
      expect(result?.kind).toBe("passthrough");
    });

    it("write_file without file_path → passthrough", () => {
      const result = parseGeminiPayload({
        tool_name: "write_file",
        tool_input: {},
      });
      expect(result?.kind).toBe("passthrough");
    });

    it("no tool_name and no lifecycle hook → passthrough", () => {
      const result = parseGeminiPayload({ some_field: "value" });
      expect(result?.kind).toBe("passthrough");
    });
  });

  describe("null returns", () => {
    it("null → null", () => expect(parseGeminiPayload(null)).toBeNull());
    it("empty string → null", () => expect(parseGeminiPayload("")).toBeNull());
    it("malformed JSON → null", () => expect(parseGeminiPayload("{oops")).toBeNull());
  });
});

// ---------------------------------------------------------------------------
// Codex parser
// ---------------------------------------------------------------------------

describe("parseCodexPayload", () => {
  describe("positive: write events", () => {
    it("PreToolUse Write → write event", () => {
      const result = parseCodexPayload({
        hook_event_name: "PreToolUse",
        tool_name: "Write",
        tool_input: { file_path: "/x.ts", content: "const x = 1;" },
      });
      expect(result?.kind).toBe("write");
      if (result?.kind === "write") {
        expect(result.agent).toBe("codex");
        expect(result.path).toBe("/x.ts");
      }
    });

    it("PreToolUse Edit → write event", () => {
      const result = parseCodexPayload({
        hook_event_name: "PreToolUse",
        tool_name: "Edit",
        tool_input: { file_path: "/y.rs", content: "fn main() {}" },
      });
      expect(result?.kind).toBe("write");
    });
  });

  describe("positive: lifecycle events", () => {
    it("SessionStart → lifecycle", () => {
      const result = parseCodexPayload({ hook_event_name: "SessionStart" });
      expect(result?.kind).toBe("lifecycle");
    });

    it("Stop → lifecycle", () => {
      const result = parseCodexPayload({ hook_event_name: "Stop" });
      expect(result?.kind).toBe("lifecycle");
    });
  });

  describe("negative cases", () => {
    it("Bash tool → passthrough", () => {
      const result = parseCodexPayload({
        hook_event_name: "PreToolUse",
        tool_name: "Bash",
        tool_input: { command: "ls" },
      });
      expect(result?.kind).toBe("passthrough");
    });

    it("no file_path → passthrough", () => {
      const result = parseCodexPayload({
        hook_event_name: "PreToolUse",
        tool_name: "Write",
        tool_input: {},
      });
      expect(result?.kind).toBe("passthrough");
    });
  });

  describe("null returns", () => {
    it("null → null", () => expect(parseCodexPayload(null)).toBeNull());
    it("number → null", () => expect(parseCodexPayload(123)).toBeNull());
    it("array → null", () => expect(parseCodexPayload([])).toBeNull());
  });
});

// ---------------------------------------------------------------------------
// Copilot parser
// ---------------------------------------------------------------------------

describe("parseCopilotPayload", () => {
  describe("positive: write events", () => {
    it("preToolUse with file_path → write event", () => {
      const result = parseCopilotPayload({
        hook_event_name: "preToolUse",
        tool_input: { file_path: "/tmp/copilot.ts", content: "export {}" },
      });
      expect(result?.kind).toBe("write");
      if (result?.kind === "write") {
        expect(result.path).toBe("/tmp/copilot.ts");
        expect(result.agent).toBe("copilot");
      }
    });

    it("preToolUse with no tool_name still produces write event (toolName defaults to 'preToolUse')", () => {
      // Copilot sometimes omits tool_name — file_path presence is sufficient signal
      const result = parseCopilotPayload({
        hook_event_name: "preToolUse",
        tool_input: { file_path: "/tmp/y.ts", content: "hello" },
      });
      expect(result?.kind).toBe("write");
      if (result?.kind === "write") {
        expect(result.toolName).toBe("preToolUse");
      }
    });

    it("preToolUse with known tool_name uses that name", () => {
      const result = parseCopilotPayload({
        hook_event_name: "preToolUse",
        tool_name: "writeFile",
        tool_input: { file_path: "/tmp/z.ts", content: "bye" },
      });
      expect(result?.kind).toBe("write");
      if (result?.kind === "write") {
        expect(result.toolName).toBe("writeFile");
      }
    });

    it("preToolUse with path alias in tool_input → write event", () => {
      const result = parseCopilotPayload({
        hook_event_name: "preToolUse",
        tool_input: { path: "/tmp/alias.ts", content: "x" },
      });
      expect(result?.kind).toBe("write");
      if (result?.kind === "write") {
        expect(result.path).toBe("/tmp/alias.ts");
      }
    });
  });

  describe("positive: lifecycle events", () => {
    it("sessionStart → lifecycle", () => {
      const result = parseCopilotPayload({ hook_event_name: "sessionStart" });
      expect(result?.kind).toBe("lifecycle");
    });

    it("sessionEnd → lifecycle", () => {
      const result = parseCopilotPayload({ hook_event_name: "sessionEnd" });
      expect(result?.kind).toBe("lifecycle");
    });

    it("postToolUse → lifecycle", () => {
      const result = parseCopilotPayload({ hook_event_name: "postToolUse" });
      expect(result?.kind).toBe("lifecycle");
    });
  });

  describe("negative cases", () => {
    it("preToolUse without file_path → passthrough", () => {
      const result = parseCopilotPayload({
        hook_event_name: "preToolUse",
        tool_input: {},
      });
      expect(result?.kind).toBe("passthrough");
    });

    it("unknown hook → passthrough", () => {
      const result = parseCopilotPayload({ hook_event_name: "weirdHook" });
      expect(result?.kind).toBe("passthrough");
    });

    it("no hook_event_name → passthrough", () => {
      const result = parseCopilotPayload({ tool_name: "write" });
      expect(result?.kind).toBe("passthrough");
    });
  });

  describe("null returns", () => {
    it("null → null", () => expect(parseCopilotPayload(null)).toBeNull());
    it("undefined → null", () => expect(parseCopilotPayload(undefined)).toBeNull());
    it("whitespace string → null", () => expect(parseCopilotPayload("   ")).toBeNull());
  });
});

// ---------------------------------------------------------------------------
// Cursor parser
// ---------------------------------------------------------------------------

describe("parseCursorPayload", () => {
  describe("positive: lifecycle events", () => {
    it("afterFileEdit → lifecycle", () => {
      const result = parseCursorPayload({ hook_event_name: "afterFileEdit" });
      expect(result?.kind).toBe("lifecycle");
      if (result?.kind === "lifecycle") {
        expect(result.agent).toBe("cursor");
        expect(result.hookName).toBe("afterFileEdit");
      }
    });

    it("beforeShellExecution → lifecycle", () => {
      const result = parseCursorPayload({ hook_event_name: "beforeShellExecution" });
      expect(result?.kind).toBe("lifecycle");
    });

    it("beforeMCPExecution → lifecycle", () => {
      const result = parseCursorPayload({ hook_event_name: "beforeMCPExecution" });
      expect(result?.kind).toBe("lifecycle");
    });
  });

  describe("negative cases", () => {
    it("unknown hook → passthrough", () => {
      const result = parseCursorPayload({ hook_event_name: "unknownHook" });
      expect(result?.kind).toBe("passthrough");
    });

    it("no hook_event_name → passthrough", () => {
      const result = parseCursorPayload({ command: "ls" });
      expect(result?.kind).toBe("passthrough");
    });
  });

  describe("null returns", () => {
    it("null → null", () => expect(parseCursorPayload(null)).toBeNull());
    it("empty string → null", () => expect(parseCursorPayload("")).toBeNull());
  });
});

// ---------------------------------------------------------------------------
// parseGatePayload router
// ---------------------------------------------------------------------------

describe("parseGatePayload", () => {
  it("routes to claude parser", () => {
    const result = parseGatePayload("claude", { hook_event_name: "SessionStart" });
    expect(result?.kind).toBe("lifecycle");
    expect((result as any)?.agent).toBe("claude");
  });

  it("routes to gemini parser", () => {
    const result = parseGatePayload("gemini", {
      tool_name: "write_file",
      tool_input: { file_path: "/x.ts", content: "y" },
    });
    expect(result?.kind).toBe("write");
  });

  it("routes to codex parser", () => {
    const result = parseGatePayload("codex", { hook_event_name: "Stop" });
    expect(result?.kind).toBe("lifecycle");
  });

  it("routes to copilot parser", () => {
    const result = parseGatePayload("copilot", { hook_event_name: "sessionStart" });
    expect(result?.kind).toBe("lifecycle");
  });

  it("routes to cursor parser", () => {
    const result = parseGatePayload("cursor", { hook_event_name: "afterFileEdit" });
    expect(result?.kind).toBe("lifecycle");
  });

  it("returns null for null input regardless of agent", () => {
    const agents: AgentName[] = ["claude", "gemini", "codex", "copilot", "cursor"];
    for (const agent of agents) {
      expect(parseGatePayload(agent, null)).toBeNull();
    }
  });
});

// ---------------------------------------------------------------------------
// Type guards
// ---------------------------------------------------------------------------

describe("type guards", () => {
  it("isWriteEvent returns true for write events", () => {
    const result = parseClaudePayload({
      hook_event_name: "PreToolUse",
      tool_name: "Write",
      tool_input: { file_path: "/x.ts", content: "y" },
    }) as ParsedGateEvent;
    expect(isWriteEvent(result)).toBe(true);
  });

  it("isWriteEvent returns false for lifecycle events", () => {
    const result = parseClaudePayload({ hook_event_name: "SessionStart" }) as ParsedGateEvent;
    expect(isWriteEvent(result)).toBe(false);
  });

  it("isLifecycleEvent returns true for lifecycle events", () => {
    const result = parseGeminiPayload({ hook_event_name: "SessionStart" }) as ParsedGateEvent;
    expect(isLifecycleEvent(result)).toBe(true);
  });

  it("isLifecycleEvent returns false for write events", () => {
    const result = parseGeminiPayload({
      tool_name: "write_file",
      tool_input: { file_path: "/x.ts", content: "y" },
    }) as ParsedGateEvent;
    expect(isLifecycleEvent(result)).toBe(false);
  });
});
