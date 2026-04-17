// tools/neph-cli/src/gate-parsers.ts
// Per-agent parsers for extracting write-intent (path + content) from hook payloads.
//
// Contract:
//   - Every parser accepts an unknown input and returns ParsedGateEvent | null.
//   - Parsers MUST NOT throw. On any error, log via debug() and return null.
//   - Parsers MUST NOT mutate their input.
//   - Same input ALWAYS produces the same output (deterministic, no side effects).
//   - Each parser is isolated: claude parser only handles claude payloads, etc.

import { debug } from "../../lib/log";

// ---------------------------------------------------------------------------
// Discriminated union return types
// ---------------------------------------------------------------------------

/** A write-intent extracted from a hook payload — the gate inspects this. */
export interface ParsedWriteEvent {
  readonly kind: "write";
  /** Absolute or repo-relative file path from the agent payload. */
  readonly path: string;
  /** Full proposed file content (may be reconstructed). */
  readonly content: string;
  /** Name of the tool the agent called (e.g. "Write", "write_file"). */
  readonly toolName: string;
  /** Which agent produced this payload. */
  readonly agent: AgentName;
}

/** The event is a lifecycle hook (SessionStart/Stop/etc.) — no file write. */
export interface ParsedLifecycleEvent {
  readonly kind: "lifecycle";
  readonly hookName: string;
  readonly agent: AgentName;
}

/** The event payload is not a write and not a lifecycle event — pass through. */
export interface ParsedPassthroughEvent {
  readonly kind: "passthrough";
  readonly agent: AgentName;
}

export type ParsedGateEvent =
  | ParsedWriteEvent
  | ParsedLifecycleEvent
  | ParsedPassthroughEvent;

export type AgentName = "claude" | "gemini" | "codex" | "copilot" | "cursor";

// ---------------------------------------------------------------------------
// Write tool name sets — anchored, no regex catastrophic backtracking risk
// ---------------------------------------------------------------------------

const CLAUDE_WRITE_TOOLS = new Set(["Write", "Edit", "MultiEdit", "NotebookEdit"]);
const GEMINI_WRITE_TOOLS = new Set(["write_file", "edit_file", "create_file", "replace_file"]);
const CODEX_WRITE_TOOLS = new Set(["Write", "Edit", "MultiEdit"]);

// Claude lifecycle hook names (uppercase, exact match via Set — no regex)
const CLAUDE_LIFECYCLE_HOOKS = new Set([
  "SessionStart",
  "SessionEnd",
  "UserPromptSubmit",
  "Stop",
  "PreToolUse",
  "PostToolUse",
]);

// Gemini lifecycle hook names
const GEMINI_LIFECYCLE_HOOKS = new Set([
  "SessionStart",
  "SessionEnd",
  "BeforeAgent",
  "AfterAgent",
  "AfterTool",
]);

// Codex lifecycle hook names
const CODEX_LIFECYCLE_HOOKS = new Set([
  "SessionStart",
  "SessionEnd",
  "UserPromptSubmit",
  "Stop",
  "PreToolUse",
  "PostToolUse",
]);

// Copilot lifecycle hook names
const COPILOT_LIFECYCLE_HOOKS = new Set([
  "sessionStart",
  "sessionEnd",
  "preToolUse",
  "postToolUse",
]);

// Cursor lifecycle hook names
const CURSOR_LIFECYCLE_HOOKS = new Set([
  "afterFileEdit",
  "beforeShellExecution",
  "beforeMCPExecution",
]);

// ---------------------------------------------------------------------------
// Safe JSON parse helper — never throws
// ---------------------------------------------------------------------------

function safeParseJson(input: unknown): Record<string, unknown> | null {
  if (typeof input === "object" && input !== null && !Array.isArray(input)) {
    // Already an object — return a shallow copy to avoid mutating the original
    return { ...(input as Record<string, unknown>) };
  }
  if (typeof input !== "string") {
    return null;
  }
  const trimmed = input.trim();
  if (trimmed.length === 0) {
    return null;
  }
  // Bound the input size to avoid memory issues with huge strings
  if (trimmed.length > 10_000_000) {
    debug("gate-parsers", "safeParseJson: input exceeds 10 MB, rejecting");
    return null;
  }
  try {
    const parsed = JSON.parse(trimmed);
    if (typeof parsed !== "object" || parsed === null || Array.isArray(parsed)) {
      return null;
    }
    return parsed as Record<string, unknown>;
  } catch (err) {
    debug("gate-parsers", `safeParseJson: JSON parse error: ${err}`);
    return null;
  }
}

// ---------------------------------------------------------------------------
// Field extraction helpers — never throw, never mutate
// ---------------------------------------------------------------------------

function getString(obj: Record<string, unknown>, ...keys: string[]): string | undefined {
  for (const key of keys) {
    const val = obj[key];
    if (typeof val === "string" && val.length > 0) return val;
  }
  return undefined;
}

function getObject(obj: Record<string, unknown>, ...keys: string[]): Record<string, unknown> | undefined {
  for (const key of keys) {
    const val = obj[key];
    // Accept only plain objects: reject null, arrays, Date, RegExp, etc.
    if (
      typeof val === "object" &&
      val !== null &&
      !Array.isArray(val) &&
      Object.getPrototypeOf(val) === Object.prototype
    ) {
      return val as Record<string, unknown>;
    }
  }
  return undefined;
}

// ---------------------------------------------------------------------------
// Claude parser
// ---------------------------------------------------------------------------
//
// Input format (Claude PreToolUse hook):
// {
//   hook_event_name: "PreToolUse",
//   tool_name: "Write" | "Edit" | "MultiEdit" | "NotebookEdit",
//   tool_input: {
//     file_path?: string,
//     path?: string,
//     content?: string,
//     old_string?: string,
//     new_string?: string,
//   }
// }
//
// Returns ParsedWriteEvent when hook_event_name is "PreToolUse" and tool_name
// is a write tool with a resolvable file_path.
// Returns ParsedLifecycleEvent for other known hook names.
// Returns ParsedPassthroughEvent for anything else.
// Returns null only on parse failure.

export function parseClaudePayload(input: unknown): ParsedGateEvent | null {
  const obj = safeParseJson(input);
  if (obj === null) {
    debug("gate-parsers", "parseClaudePayload: failed to parse input as object");
    return null;
  }

  const hookName = getString(obj, "hook_event_name");

  // Lifecycle events
  if (hookName && hookName !== "PreToolUse" && CLAUDE_LIFECYCLE_HOOKS.has(hookName)) {
    return { kind: "lifecycle", hookName, agent: "claude" };
  }

  if (hookName === "PreToolUse") {
    const toolName = getString(obj, "tool_name");
    if (!toolName) {
      return { kind: "passthrough", agent: "claude" };
    }

    if (!CLAUDE_WRITE_TOOLS.has(toolName)) {
      return { kind: "passthrough", agent: "claude" };
    }

    const toolInput = getObject(obj, "tool_input") ?? {};
    const filePath = getString(toolInput, "file_path", "path");
    if (!filePath) {
      debug("gate-parsers", `parseClaudePayload: PreToolUse ${toolName} has no file_path`);
      return { kind: "passthrough", agent: "claude" };
    }

    const content = getString(toolInput, "content") ?? "";

    return {
      kind: "write",
      path: filePath,
      content,
      toolName,
      agent: "claude",
    };
  }

  // Unknown hook name or no hook name
  return { kind: "passthrough", agent: "claude" };
}

// ---------------------------------------------------------------------------
// Gemini parser
// ---------------------------------------------------------------------------
//
// Input format (Gemini BeforeTool hook):
// {
//   hook_event_name?: "SessionStart" | "BeforeAgent" | ...,  // lifecycle events
//   tool_name?: "write_file" | "edit_file" | ...,            // OR tool-level events
//   toolName?: "write_file" | ...,                           // camelCase alias
//   tool_input?: { file_path?: string, filepath?: string, content?: string },
//   toolInput?: { ... },                                     // camelCase alias
// }
//
// Gemini uses snake_case or camelCase fields depending on the CLI version.

export function parseGeminiPayload(input: unknown): ParsedGateEvent | null {
  const obj = safeParseJson(input);
  if (obj === null) {
    debug("gate-parsers", "parseGeminiPayload: failed to parse input as object");
    return null;
  }

  const hookName = getString(obj, "hook_event_name");

  // Lifecycle events
  if (hookName && GEMINI_LIFECYCLE_HOOKS.has(hookName)) {
    return { kind: "lifecycle", hookName, agent: "gemini" };
  }

  // Tool events: extract tool_name (either casing)
  const toolName = getString(obj, "tool_name", "toolName");
  if (!toolName) {
    return { kind: "passthrough", agent: "gemini" };
  }

  if (!GEMINI_WRITE_TOOLS.has(toolName)) {
    return { kind: "passthrough", agent: "gemini" };
  }

  const toolInput = getObject(obj, "tool_input", "toolInput") ?? {};
  const filePath = getString(toolInput, "file_path", "filepath", "path");
  if (!filePath) {
    debug("gate-parsers", `parseGeminiPayload: ${toolName} has no file_path`);
    return { kind: "passthrough", agent: "gemini" };
  }

  const content = getString(toolInput, "content") ?? "";

  return {
    kind: "write",
    path: filePath,
    content,
    toolName,
    agent: "gemini",
  };
}

// ---------------------------------------------------------------------------
// Codex parser
// ---------------------------------------------------------------------------
//
// Input format (same structure as Claude — codex mirrors Claude hooks):
// {
//   hook_event_name: "PreToolUse" | ...,
//   tool_name: "Write" | "Edit" | ...,
//   tool_input: { file_path?: string, path?: string, content?: string }
// }

export function parseCodexPayload(input: unknown): ParsedGateEvent | null {
  const obj = safeParseJson(input);
  if (obj === null) {
    debug("gate-parsers", "parseCodexPayload: failed to parse input as object");
    return null;
  }

  const hookName = getString(obj, "hook_event_name");

  if (hookName && hookName !== "PreToolUse" && CODEX_LIFECYCLE_HOOKS.has(hookName)) {
    return { kind: "lifecycle", hookName, agent: "codex" };
  }

  if (hookName === "PreToolUse") {
    const toolName = getString(obj, "tool_name");
    if (!toolName || !CODEX_WRITE_TOOLS.has(toolName)) {
      return { kind: "passthrough", agent: "codex" };
    }

    const toolInput = getObject(obj, "tool_input") ?? {};
    const filePath = getString(toolInput, "file_path", "path");
    if (!filePath) {
      debug("gate-parsers", `parseCodexPayload: PreToolUse ${toolName} has no file_path`);
      return { kind: "passthrough", agent: "codex" };
    }

    const content = getString(toolInput, "content") ?? "";

    return {
      kind: "write",
      path: filePath,
      content,
      toolName,
      agent: "codex",
    };
  }

  return { kind: "passthrough", agent: "codex" };
}

// ---------------------------------------------------------------------------
// Copilot parser
// ---------------------------------------------------------------------------
//
// Input format (GitHub Copilot preToolUse hook — camelCase):
// {
//   hook_event_name: "preToolUse" | "sessionStart" | ...,
//   tool_input: { file_path?: string, content?: string }
// }

export function parseCopilotPayload(input: unknown): ParsedGateEvent | null {
  const obj = safeParseJson(input);
  if (obj === null) {
    debug("gate-parsers", "parseCopilotPayload: failed to parse input as object");
    return null;
  }

  const hookName = getString(obj, "hook_event_name");

  if (hookName && hookName !== "preToolUse" && COPILOT_LIFECYCLE_HOOKS.has(hookName)) {
    return { kind: "lifecycle", hookName, agent: "copilot" };
  }

  if (hookName === "preToolUse") {
    const toolInput = getObject(obj, "tool_input") ?? {};
    const filePath = getString(toolInput, "file_path", "path");
    if (!filePath) {
      return { kind: "passthrough", agent: "copilot" };
    }

    // Copilot does not always send a tool_name — treat any preToolUse with a
    // file_path as a write intent. When a tool_name is present and it's a known
    // write tool, use it; otherwise fall back to the raw hook name as a label.
    const toolName = getString(obj, "tool_name", "tool") ?? "preToolUse";

    const content = getString(toolInput, "content") ?? "";

    return {
      kind: "write",
      path: filePath,
      content,
      toolName,
      agent: "copilot",
    };
  }

  return { kind: "passthrough", agent: "copilot" };
}

// ---------------------------------------------------------------------------
// Cursor parser
// ---------------------------------------------------------------------------
//
// Input format (Cursor hooks):
// {
//   hook_event_name: "afterFileEdit" | "beforeShellExecution" | "beforeMCPExecution",
//   filePath?: string,       // afterFileEdit
//   newContent?: string,     // afterFileEdit
//   command?: string,        // beforeShellExecution
//   tool?: string,           // beforeMCPExecution
// }
//
// Note: Cursor's afterFileEdit fires AFTER the write — the file is already
// written. The gate treats this as informational (lifecycle) not a writable
// intercept. beforeShellExecution / beforeMCPExecution are execution gates,
// not file-write events.

export function parseCursorPayload(input: unknown): ParsedGateEvent | null {
  const obj = safeParseJson(input);
  if (obj === null) {
    debug("gate-parsers", "parseCursorPayload: failed to parse input as object");
    return null;
  }

  const hookName = getString(obj, "hook_event_name");

  if (!hookName) {
    return { kind: "passthrough", agent: "cursor" };
  }

  if (CURSOR_LIFECYCLE_HOOKS.has(hookName)) {
    return { kind: "lifecycle", hookName, agent: "cursor" };
  }

  return { kind: "passthrough", agent: "cursor" };
}

// ---------------------------------------------------------------------------
// Router — dispatch to the right parser by agent name
// ---------------------------------------------------------------------------

export type ParserFn = (input: unknown) => ParsedGateEvent | null;

const PARSERS: Record<AgentName, ParserFn> = {
  claude: parseClaudePayload,
  gemini: parseGeminiPayload,
  codex: parseCodexPayload,
  copilot: parseCopilotPayload,
  cursor: parseCursorPayload,
};

/**
 * Parse a hook payload for the given agent.
 * Returns null only when the input cannot be parsed at all (not JSON, not object).
 * Returns a ParsedGateEvent (write | lifecycle | passthrough) on success.
 */
export function parseGatePayload(agent: AgentName, input: unknown): ParsedGateEvent | null {
  const parser = PARSERS[agent];
  if (!parser) {
    debug("gate-parsers", `parseGatePayload: unknown agent "${agent}"`);
    return null;
  }
  try {
    return parser(input);
  } catch (err) {
    // parsers must not throw, but belt-and-suspenders
    debug("gate-parsers", `parseGatePayload: parser for ${agent} threw unexpectedly: ${err}`);
    return null;
  }
}

/** Type guard: checks if a ParsedGateEvent is a write event. */
export function isWriteEvent(event: ParsedGateEvent): event is ParsedWriteEvent {
  return event.kind === "write";
}

/** Type guard: checks if a ParsedGateEvent is a lifecycle event. */
export function isLifecycleEvent(event: ParsedGateEvent): event is ParsedLifecycleEvent {
  return event.kind === "lifecycle";
}
