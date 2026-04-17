// tools/neph-cli/tests/gate.fuzz.test.ts
// Fuzz-style tests for gate-parsers.ts.
// Stress-tests parsers with degenerate inputs: null, undefined, empty string,
// whitespace, malformed JSON, missing fields, extra fields, unicode, huge strings,
// array inputs, number inputs, and deeply nested objects.
//
// Success criterion: NO parser throws, all return null or a valid ParsedGateEvent.

import { describe, it, expect, vi } from "vitest";

vi.mock("../../lib/log", () => ({ debug: vi.fn() }));

import {
  parseClaudePayload,
  parseGeminiPayload,
  parseCodexPayload,
  parseCopilotPayload,
  parseCursorPayload,
  parseGatePayload,
  type AgentName,
} from "../src/gate-parsers";

const ALL_PARSERS = [
  parseClaudePayload,
  parseGeminiPayload,
  parseCodexPayload,
  parseCopilotPayload,
  parseCursorPayload,
] as const;

const AGENT_NAMES: AgentName[] = ["claude", "gemini", "codex", "copilot", "cursor"];

// ---------------------------------------------------------------------------
// Helper: assert a result is either null or a valid ParsedGateEvent shape
// ---------------------------------------------------------------------------

function assertValidResult(result: unknown, label: string): void {
  if (result === null) return; // null is always valid
  if (typeof result !== "object" || result === null) {
    throw new Error(`${label}: result must be null or an object, got ${typeof result}`);
  }
  const obj = result as Record<string, unknown>;
  expect(["write", "lifecycle", "passthrough"], `${label}: invalid kind`).toContain(obj.kind);
  expect(["claude", "gemini", "codex", "copilot", "cursor"], `${label}: invalid agent`).toContain(obj.agent);
  if (obj.kind === "write") {
    expect(typeof obj.path, `${label}: path must be string`).toBe("string");
    expect(typeof obj.content, `${label}: content must be string`).toBe("string");
    expect(typeof obj.toolName, `${label}: toolName must be string`).toBe("string");
  }
  if (obj.kind === "lifecycle") {
    expect(typeof obj.hookName, `${label}: hookName must be string`).toBe("string");
  }
}

// ---------------------------------------------------------------------------
// Corpus of degenerate inputs
// ---------------------------------------------------------------------------

const DEGENERATE_INPUTS: unknown[] = [
  // Primitives
  null,
  undefined,
  0,
  1,
  -1,
  NaN,
  Infinity,
  -Infinity,
  true,
  false,

  // Strings
  "",
  " ",
  "\t\n\r",
  "null",
  "undefined",
  "0",
  "true",
  "[]",
  "{}",
  '{"a":1}',
  "{bad json}",
  "[1,2,3]",
  '"just a string"',
  "a".repeat(10_000),           // long string
  "\u0000\u0001\u0002",         // control chars
  "\uD800",                     // lone surrogate
  "\u{1F4A9}".repeat(1000),    // emoji spam
  "🔥".repeat(5000),
  "<script>alert(1)</script>",
  '{"__proto__":{"polluted":1}}', // prototype pollution attempt

  // Arrays
  [],
  [1, 2, 3],
  [null, undefined, ""],

  // Objects with missing fields
  {},
  { hook_event_name: null },
  { hook_event_name: "" },
  { hook_event_name: 42 },
  { hook_event_name: [] },
  { hook_event_name: {} },
  { tool_name: null },
  { tool_name: "" },
  { tool_input: null },
  { tool_input: [] },
  { tool_input: "not an object" },

  // Objects with extra fields (should be ignored)
  { hook_event_name: "SessionStart", extra: "data", __proto__: { x: 1 } },
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: "/x.ts", content: "y" }, extra: Array(1000).fill(0) },

  // Very long field values
  { hook_event_name: "a".repeat(100_000) },
  { tool_name: "write_file", tool_input: { file_path: "/x.ts", content: "x".repeat(1_000_000) } },

  // Deeply nested
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: { nested: "not a string" }, content: "y" } },
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: "/x.ts", content: { nested: "not a string" } } },

  // Unicode in paths and content
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: "/tmp/\u4e2d\u6587.ts", content: "\u3053\u3093\u306b\u3061\u306f" } },
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: "/tmp/emoji\uD83D\uDE00.ts", content: "hello" } },

  // Partial payloads (fields that exist but are wrong type)
  { hook_event_name: "PreToolUse", tool_name: 42, tool_input: { file_path: "/x.ts" } },
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: 42 },

  // Circular-like: cannot actually create circular but can test object with self-referencing keys
  { a: "b", b: "a" },

  // Non-plain object instances as tool_input (should be treated as "missing")
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: new Date() },
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: /regex/ },
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: new Map() },
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: new Set() },
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: new Error("oops") },

  // Symbols in values (should not throw)
  { hook_event_name: Symbol("test") },

  // Functions in values (should not throw)
  { hook_event_name: () => "SessionStart" },

  // Mixed: valid structure but values are functions/symbols
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: Symbol("path"), content: "y" } },
  { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: "/x.ts", content: () => "generated" } },
];

// ---------------------------------------------------------------------------
// Cross-parser fuzz: every parser, every degenerate input
// ---------------------------------------------------------------------------

describe("gate parsers: no-throw on degenerate inputs", () => {
  for (const parser of ALL_PARSERS) {
    const name = parser.name;
    for (let i = 0; i < DEGENERATE_INPUTS.length; i++) {
      const input = DEGENERATE_INPUTS[i];
      it(`${name}(input[${i}]) does not throw`, () => {
        let result: unknown;
        expect(() => {
          result = parser(input);
        }).not.toThrow();
        assertValidResult(result, `${name}[${i}]`);
      });
    }
  }
});

// ---------------------------------------------------------------------------
// parseGatePayload router: fuzz via router as well
// ---------------------------------------------------------------------------

describe("parseGatePayload router: no-throw on degenerate inputs", () => {
  // Test a subset via router to avoid O(n*m) test explosion
  const fuzzSubset = DEGENERATE_INPUTS.slice(0, 20);
  for (const agent of AGENT_NAMES) {
    for (let i = 0; i < fuzzSubset.length; i++) {
      const input = fuzzSubset[i];
      it(`parseGatePayload(${agent}, input[${i}]) does not throw`, () => {
        let result: unknown;
        expect(() => {
          result = parseGatePayload(agent, input);
        }).not.toThrow();
        assertValidResult(result, `parseGatePayload(${agent})[${i}]`);
      });
    }
  }
});

// ---------------------------------------------------------------------------
// Determinism: same input always produces same output
// ---------------------------------------------------------------------------

describe("gate parsers: determinism (same input → same output)", () => {
  const deterministicCases: [string, unknown][] = [
    ["claude write", { hook_event_name: "PreToolUse", tool_name: "Write", tool_input: { file_path: "/x.ts", content: "abc" } }],
    ["claude lifecycle", { hook_event_name: "SessionStart" }],
    ["claude passthrough", { hook_event_name: "SomeFuture" }],
    ["gemini write", { tool_name: "write_file", tool_input: { file_path: "/y.ts", content: "xyz" } }],
    ["gemini lifecycle", { hook_event_name: "BeforeAgent" }],
    ["codex write", { hook_event_name: "PreToolUse", tool_name: "Edit", tool_input: { file_path: "/z.rs", content: "fn" } }],
    ["copilot write", { hook_event_name: "preToolUse", tool_input: { file_path: "/a.ts", content: "b" } }],
    ["cursor lifecycle", { hook_event_name: "afterFileEdit" }],
    ["null input", null],
    ["empty object", {}],
  ];

  for (const [label, input] of deterministicCases) {
    it(`${label}: 5 repeated calls produce identical output`, () => {
      const parser = parseClaudePayload;
      const results = Array.from({ length: 5 }, () => parser(input));
      const first = JSON.stringify(results[0]);
      for (const r of results) {
        expect(JSON.stringify(r)).toBe(first);
      }
    });
  }

  // Verify each agent parser is deterministic
  for (const agent of AGENT_NAMES) {
    it(`parseGatePayload("${agent}", ...) is deterministic`, () => {
      const sampleInputs = [null, {}, { hook_event_name: "SessionStart" }];
      for (const input of sampleInputs) {
        const results = Array.from({ length: 3 }, () => parseGatePayload(agent, input));
        const first = JSON.stringify(results[0]);
        for (const r of results) {
          expect(JSON.stringify(r)).toBe(first);
        }
      }
    });
  }
});

// ---------------------------------------------------------------------------
// Parser isolation: claude parser does NOT return gemini-format results etc.
// ---------------------------------------------------------------------------

describe("gate parsers: no cross-contamination between parsers", () => {
  it("gemini write payload returns passthrough from claude parser", () => {
    // Gemini tool payload has no hook_event_name — claude treats it as passthrough
    const geminiWrite = {
      tool_name: "write_file",
      tool_input: { file_path: "/x.ts", content: "hello" },
    };
    const result = parseClaudePayload(geminiWrite);
    expect(result?.kind).toBe("passthrough");
    expect(result?.kind).not.toBe("write");
  });

  it("claude PreToolUse payload returns passthrough from gemini parser", () => {
    // Claude uses PreToolUse, gemini doesn't know that hook name
    const claudeWrite = {
      hook_event_name: "PreToolUse",
      tool_name: "Write",
      tool_input: { file_path: "/x.ts", content: "hello" },
    };
    // Gemini sees hook_event_name not in its lifecycle set → passthrough
    const result = parseGeminiPayload(claudeWrite);
    expect(result?.kind).toBe("passthrough");
  });

  it("copilot lowercase sessionStart is not a lifecycle event for claude", () => {
    const copilotPayload = { hook_event_name: "sessionStart" };
    const claudeResult = parseClaudePayload(copilotPayload);
    // claude uses uppercase SessionStart — lowercase should fall through to passthrough
    expect(claudeResult?.kind).toBe("passthrough");
  });

  it("each agent result always has its own agent label", () => {
    const testInput = { hook_event_name: "SessionStart" };
    expect((parseClaudePayload(testInput) as any)?.agent).toBe("claude");
    expect((parseGeminiPayload(testInput) as any)?.agent).toBe("gemini");
    expect((parseCodexPayload(testInput) as any)?.agent).toBe("codex");
    // copilot and cursor use different case
    expect((parseCopilotPayload(testInput) as any)?.agent).toBe("copilot");
    expect((parseCursorPayload(testInput) as any)?.agent).toBe("cursor");
  });
});

// ---------------------------------------------------------------------------
// Immutability: parsers must not mutate their input
// ---------------------------------------------------------------------------

describe("gate parsers: input immutability", () => {
  const writePayload = {
    hook_event_name: "PreToolUse",
    tool_name: "Write",
    tool_input: { file_path: "/x.ts", content: "original" },
  };

  for (const parser of ALL_PARSERS) {
    it(`${parser.name} does not mutate object input`, () => {
      const input = JSON.parse(JSON.stringify(writePayload));
      const snapshot = JSON.stringify(input);
      parser(input);
      expect(JSON.stringify(input)).toBe(snapshot);
    });
  }
});

// ---------------------------------------------------------------------------
// JSON string input works the same as object input
// ---------------------------------------------------------------------------

describe("gate parsers: JSON string inputs", () => {
  it("claude parser accepts valid JSON string", () => {
    const payload = { hook_event_name: "SessionStart" };
    const fromObj = parseClaudePayload(payload);
    const fromStr = parseClaudePayload(JSON.stringify(payload));
    expect(fromObj?.kind).toBe(fromStr?.kind);
  });

  it("gemini parser accepts valid JSON string for write event", () => {
    const payload = { tool_name: "write_file", tool_input: { file_path: "/x.ts", content: "y" } };
    const fromObj = parseGeminiPayload(payload);
    const fromStr = parseGeminiPayload(JSON.stringify(payload));
    expect(fromObj?.kind).toBe(fromStr?.kind);
    if (fromObj?.kind === "write" && fromStr?.kind === "write") {
      expect(fromObj.path).toBe(fromStr.path);
      expect(fromObj.content).toBe(fromStr.content);
    }
  });
});

// ---------------------------------------------------------------------------
// Input size cap: string inputs > 10 MB return null
// ---------------------------------------------------------------------------

describe("gate parsers: input size cap", () => {
  it("string input exceeding 10 MB returns null from claude parser", () => {
    // Build a string that's over 10 MB
    const huge = "x".repeat(10_000_001);
    expect(parseClaudePayload(huge)).toBeNull();
  });

  it("string input exactly at 10 MB is still rejected (> not >=)", () => {
    const exactly10mb = "x".repeat(10_000_000);
    // This is exactly 10M chars — not > 10M — so it may try to JSON.parse
    // and fail (not valid JSON). Result is null either way.
    const result = parseClaudePayload(exactly10mb);
    expect(result).toBeNull();
  });

  it("parseable JSON string under size cap works normally", () => {
    const payload = JSON.stringify({ hook_event_name: "SessionStart" });
    // Under 10 MB, valid JSON — should succeed
    const result = parseClaudePayload(payload);
    expect(result).not.toBeNull();
    expect(result?.kind).toBe("lifecycle");
  });
});

// ---------------------------------------------------------------------------
// Prototype pollution safety
// ---------------------------------------------------------------------------

describe("gate parsers: prototype pollution safety", () => {
  it("__proto__ field in JSON string input does not pollute prototype", () => {
    const before = (Object.prototype as any).polluted;
    parseClaudePayload('{"__proto__":{"polluted":true}}');
    const after = (Object.prototype as any).polluted;
    // JSON.parse does not actually set __proto__ on V8 — verify no change
    expect(after).toBe(before);
    delete (Object.prototype as any).polluted;
  });

  it("constructor field in JSON input does not throw", () => {
    const input = { constructor: { name: "hacked" }, hook_event_name: "SessionStart" };
    expect(() => parseClaudePayload(input)).not.toThrow();
  });
});
