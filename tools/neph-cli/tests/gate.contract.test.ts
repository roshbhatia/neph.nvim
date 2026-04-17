// tools/neph-cli/tests/gate.contract.test.ts
// Contract tests for gate-parsers.ts.
//
// These tests validate the SHAPE of the returned data — they're stability
// tests that lock down the discriminated union contract so future refactors
// cannot accidentally change the public API.
//
// Contract rules:
//   1. Every parser exports a function matching (input: unknown) => ParsedGateEvent | null
//   2. ParsedWriteEvent has: kind="write", path: string, content: string, toolName: string, agent: AgentName
//   3. ParsedLifecycleEvent has: kind="lifecycle", hookName: string, agent: AgentName
//   4. ParsedPassthroughEvent has: kind="passthrough", agent: AgentName
//   5. null is returned only when input cannot be parsed (not JSON or not an object)
//   6. Write events ALWAYS have non-empty path
//   7. Write events have a consistent agent label matching the parser that produced them
//   8. Results are readonly — no mutable fields

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
  type ParsedWriteEvent,
  type ParsedLifecycleEvent,
  type ParsedPassthroughEvent,
  type AgentName,
  type ParserFn,
} from "../src/gate-parsers";

// ---------------------------------------------------------------------------
// Contract 1: parser function signatures
// ---------------------------------------------------------------------------

describe("parser function signatures", () => {
  const parsers: [string, unknown][] = [
    ["parseClaudePayload", parseClaudePayload],
    ["parseGeminiPayload", parseGeminiPayload],
    ["parseCodexPayload", parseCodexPayload],
    ["parseCopilotPayload", parseCopilotPayload],
    ["parseCursorPayload", parseCursorPayload],
  ];

  for (const [name, parser] of parsers) {
    it(`${name} is a function`, () => {
      expect(typeof parser).toBe("function");
    });

    it(`${name} accepts one argument`, () => {
      expect((parser as Function).length).toBe(1);
    });

    it(`${name} satisfies ParserFn type (returns null or ParsedGateEvent)`, () => {
      const _check: ParserFn = parser as ParserFn;
      expect(_check).toBeDefined();
    });
  }
});

// ---------------------------------------------------------------------------
// Contract 2: ParsedWriteEvent shape
// ---------------------------------------------------------------------------

describe("ParsedWriteEvent contract", () => {
  function getWriteEvent(): ParsedWriteEvent {
    const result = parseClaudePayload({
      hook_event_name: "PreToolUse",
      tool_name: "Write",
      tool_input: { file_path: "/contract/test.ts", content: "export const x = 1;" },
    });
    if (!result || result.kind !== "write") {
      throw new Error("Expected write event");
    }
    return result;
  }

  it("has kind='write'", () => {
    expect(getWriteEvent().kind).toBe("write");
  });

  it("has path as non-empty string", () => {
    const evt = getWriteEvent();
    expect(typeof evt.path).toBe("string");
    expect(evt.path.length).toBeGreaterThan(0);
  });

  it("has content as string (may be empty)", () => {
    const evt = getWriteEvent();
    expect(typeof evt.content).toBe("string");
  });

  it("has toolName as non-empty string", () => {
    const evt = getWriteEvent();
    expect(typeof evt.toolName).toBe("string");
    expect(evt.toolName.length).toBeGreaterThan(0);
  });

  it("has agent as a valid AgentName", () => {
    const validAgents: AgentName[] = ["claude", "gemini", "codex", "copilot", "cursor"];
    expect(validAgents).toContain(getWriteEvent().agent);
  });

  it("has exactly the expected keys", () => {
    const evt = getWriteEvent();
    const keys = Object.keys(evt).sort();
    expect(keys).toEqual(["agent", "content", "kind", "path", "toolName"]);
  });

  it("path matches the input file_path verbatim", () => {
    const result = parseClaudePayload({
      hook_event_name: "PreToolUse",
      tool_name: "Write",
      tool_input: { file_path: "/exact/path/check.ts", content: "x" },
    });
    if (result?.kind !== "write") throw new Error("Expected write");
    expect(result.path).toBe("/exact/path/check.ts");
  });

  it("content matches the input content verbatim", () => {
    const content = "const foo = 'bar';\n// comment\n";
    const result = parseClaudePayload({
      hook_event_name: "PreToolUse",
      tool_name: "Write",
      tool_input: { file_path: "/x.ts", content },
    });
    if (result?.kind !== "write") throw new Error("Expected write");
    expect(result.content).toBe(content);
  });
});

// ---------------------------------------------------------------------------
// Contract 3: ParsedLifecycleEvent shape
// ---------------------------------------------------------------------------

describe("ParsedLifecycleEvent contract", () => {
  function getLifecycleEvent(): ParsedLifecycleEvent {
    const result = parseClaudePayload({ hook_event_name: "SessionStart" });
    if (!result || result.kind !== "lifecycle") {
      throw new Error("Expected lifecycle event");
    }
    return result;
  }

  it("has kind='lifecycle'", () => {
    expect(getLifecycleEvent().kind).toBe("lifecycle");
  });

  it("has hookName as non-empty string", () => {
    const evt = getLifecycleEvent();
    expect(typeof evt.hookName).toBe("string");
    expect(evt.hookName.length).toBeGreaterThan(0);
  });

  it("has agent as a valid AgentName", () => {
    const validAgents: AgentName[] = ["claude", "gemini", "codex", "copilot", "cursor"];
    expect(validAgents).toContain(getLifecycleEvent().agent);
  });

  it("has exactly the expected keys", () => {
    const evt = getLifecycleEvent();
    const keys = Object.keys(evt).sort();
    expect(keys).toEqual(["agent", "hookName", "kind"]);
  });

  it("hookName matches the input hook_event_name verbatim", () => {
    const result = parseGeminiPayload({ hook_event_name: "BeforeAgent" });
    if (result?.kind !== "lifecycle") throw new Error("Expected lifecycle");
    expect(result.hookName).toBe("BeforeAgent");
  });
});

// ---------------------------------------------------------------------------
// Contract 4: ParsedPassthroughEvent shape
// ---------------------------------------------------------------------------

describe("ParsedPassthroughEvent contract", () => {
  function getPassthroughEvent(): ParsedPassthroughEvent {
    const result = parseClaudePayload({ hook_event_name: "UnknownHook" });
    if (!result || result.kind !== "passthrough") {
      throw new Error("Expected passthrough event");
    }
    return result;
  }

  it("has kind='passthrough'", () => {
    expect(getPassthroughEvent().kind).toBe("passthrough");
  });

  it("has agent as a valid AgentName", () => {
    const validAgents: AgentName[] = ["claude", "gemini", "codex", "copilot", "cursor"];
    expect(validAgents).toContain(getPassthroughEvent().agent);
  });

  it("has exactly the expected keys", () => {
    const evt = getPassthroughEvent();
    const keys = Object.keys(evt).sort();
    expect(keys).toEqual(["agent", "kind"]);
  });
});

// ---------------------------------------------------------------------------
// Contract 5: null returned only on parse failure
// ---------------------------------------------------------------------------

describe("null is returned only on parse failure", () => {
  const parseFailureInputs: unknown[] = [
    null,
    undefined,
    "",
    " ",
    "not json",
    "{bad",
    "[]",
    '"string"',
    42,
    true,
    false,
    [],
  ];

  for (const input of parseFailureInputs) {
    it(`claude parser returns null for ${JSON.stringify(input)}`, () => {
      const result = parseClaudePayload(input);
      expect(result).toBeNull();
    });
  }

  // Parseable inputs that ARE objects must return a ParsedGateEvent (never null)
  const parseableInputs: unknown[] = [
    {},
    { hook_event_name: "anything" },
    { tool_name: "read_file" },
    { random: "object" },
  ];

  for (const input of parseableInputs) {
    it(`claude parser returns non-null for parseable object ${JSON.stringify(input)}`, () => {
      const result = parseClaudePayload(input);
      expect(result).not.toBeNull();
    });
  }
});

// ---------------------------------------------------------------------------
// Contract 6: write events ALWAYS have non-empty path
// ---------------------------------------------------------------------------

describe("write events always have non-empty path", () => {
  const writeInputs = [
    {
      agent: "claude" as AgentName,
      input: { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: "/x.ts", content: "y" } },
    },
    {
      agent: "gemini" as AgentName,
      input: { tool_name: "write_file", tool_input: { file_path: "/a.py", content: "pass" } },
    },
    {
      agent: "codex" as AgentName,
      input: { hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: { file_path: "/b.rs", content: "fn" } },
    },
    {
      agent: "copilot" as AgentName,
      input: { hook_event_name: "preToolUse", tool_input: { file_path: "/c.go", content: "package main" } },
    },
  ];

  for (const { agent, input } of writeInputs) {
    it(`${agent} write event has non-empty path`, () => {
      const result = parseGatePayload(agent, input);
      expect(result).not.toBeNull();
      if (result?.kind === "write") {
        expect(result.path.length).toBeGreaterThan(0);
      }
    });
  }
});

// ---------------------------------------------------------------------------
// Contract 7: agent label consistency
// ---------------------------------------------------------------------------

describe("agent label consistency", () => {
  const agentToParser: [AgentName, typeof parseClaudePayload][] = [
    ["claude", parseClaudePayload],
    ["gemini", parseGeminiPayload],
    ["codex", parseCodexPayload],
    ["copilot", parseCopilotPayload],
    ["cursor", parseCursorPayload],
  ];

  for (const [agent, parser] of agentToParser) {
    it(`${agent} parser always labels results with agent="${agent}"`, () => {
      const inputs = [
        {},
        { hook_event_name: "SessionStart" },
        { hook_event_name: "UnknownEvent" },
        null,
      ];
      for (const input of inputs) {
        const result = parser(input);
        if (result !== null) {
          expect(result.agent).toBe(agent);
        }
      }
    });
  }

  it("parseGatePayload agent label matches the requested agent", () => {
    const agents: AgentName[] = ["claude", "gemini", "codex", "copilot", "cursor"];
    for (const agent of agents) {
      const result = parseGatePayload(agent, {});
      if (result !== null) {
        expect(result.agent).toBe(agent);
      }
    }
  });
});

// ---------------------------------------------------------------------------
// Contract 8: kind discriminant is one of exactly three values
// ---------------------------------------------------------------------------

describe("kind discriminant is exactly one of: write | lifecycle | passthrough", () => {
  const validKinds = new Set(["write", "lifecycle", "passthrough"]);

  const testCases: [string, unknown][] = [
    ["claude", { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: "/x.ts", content: "y" } }],
    ["claude", { hook_event_name: "SessionStart" }],
    ["claude", { hook_event_name: "Unknown" }],
    ["gemini", { tool_name: "write_file", tool_input: { file_path: "/x.ts", content: "y" } }],
    ["gemini", { hook_event_name: "BeforeAgent" }],
    ["codex", { hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: { file_path: "/x.rs", content: "fn" } }],
    ["copilot", { hook_event_name: "preToolUse", tool_input: { file_path: "/x.go", content: "go" } }],
    ["cursor", { hook_event_name: "afterFileEdit" }],
    ["cursor", { hook_event_name: "unknownCursor" }],
  ];

  for (const [agent, input] of testCases) {
    it(`${agent}/${JSON.stringify(input).slice(0, 60)} produces valid kind`, () => {
      const result = parseGatePayload(agent as AgentName, input);
      if (result !== null) {
        expect(validKinds.has(result.kind)).toBe(true);
      }
    });
  }
});

// ---------------------------------------------------------------------------
// Contract 9: type guards satisfy TypeScript narrowing at runtime
// ---------------------------------------------------------------------------

describe("type guards narrow correctly", () => {
  it("isWriteEvent narrows to ParsedWriteEvent", () => {
    const result = parseClaudePayload({
      hook_event_name: "PreToolUse",
      tool_name: "Write",
      tool_input: { file_path: "/x.ts", content: "y" },
    }) as ParsedGateEvent;

    if (isWriteEvent(result)) {
      // TypeScript should allow these accesses without error at compile time:
      expect(result.path).toBe("/x.ts");
      expect(result.content).toBe("y");
      expect(result.toolName).toBe("Write");
    } else {
      throw new Error("Expected write event");
    }
  });

  it("isLifecycleEvent narrows to ParsedLifecycleEvent", () => {
    const result = parseGeminiPayload({ hook_event_name: "AfterAgent" }) as ParsedGateEvent;

    if (isLifecycleEvent(result)) {
      expect(result.hookName).toBe("AfterAgent");
    } else {
      throw new Error("Expected lifecycle event");
    }
  });

  it("isWriteEvent returns false for all non-write kinds", () => {
    const lifecycle = parseClaudePayload({ hook_event_name: "SessionStart" }) as ParsedGateEvent;
    const passthrough = parseClaudePayload({ hook_event_name: "Unknown" }) as ParsedGateEvent;
    expect(isWriteEvent(lifecycle)).toBe(false);
    expect(isWriteEvent(passthrough)).toBe(false);
  });

  it("isLifecycleEvent returns false for all non-lifecycle kinds", () => {
    const write = parseClaudePayload({
      hook_event_name: "PreToolUse",
      tool_name: "Write",
      tool_input: { file_path: "/x.ts", content: "y" },
    }) as ParsedGateEvent;
    const passthrough = parseClaudePayload({ hook_event_name: "Unknown" }) as ParsedGateEvent;
    expect(isLifecycleEvent(write)).toBe(false);
    expect(isLifecycleEvent(passthrough)).toBe(false);
  });
});
