# Design: Deep Harness Integrations

## Core Architecture Decision

**`neph integration hook <agent>` pattern** — rather than standalone compiled harness binaries,
all agent-side hook logic lives as handlers inside the neph CLI (`neph integration hook claude`,
`neph integration hook gemini`, etc.). This is already how Gemini works. The agent's config
file (settings.json / hooks.json) points to `neph integration hook <agent>`, and the neph CLI
handles the full protocol: stdin JSON in, stdout JSON out.

This keeps deployment simple — no separate binary installs, no path resolution, neph CLI is
already on PATH. The Gemini handler in `integration.ts` is the reference; we generalize and
strengthen it.

## Cupcake Integration Pattern

All file-write hook handlers (PreToolUse, BeforeTool, tool.call) route through Cupcake:

```
neph integration hook <agent> (stdin: tool event JSON)
  1. Parse event, identify tool and file path
  2. Reconstruct proposed full content
  3. cupcake eval --harness <agent>  (stdin: normalized event)
     → protected_paths.rego → block dangerous writes before review
     → dangerous_commands.rego → block risky shell commands
     → review.rego → neph_review signal → neph-cli review → vimdiff
     → returns: { decision, updated_input? }
  4. Map Cupcake decision → agent hook response format
     allow  → hookSpecificOutput { permissionDecision: "allow" }
     deny   → hookSpecificOutput { permissionDecision: "deny" }
     modify → hookSpecificOutput { permissionDecision: "allow", updatedInput: {...} }
  5. Write JSON to stdout
```

**Lifecycle hooks** (SessionStart/End, Stop, UserPromptSubmit, agent start/end) bypass Cupcake
and call `neph connect` directly via the persistent queue.

## `lib/harness-base.ts` — Shared Infrastructure

Extracted from Pi and Amp. Used by new hook handlers in integration.ts.

### ContentHelper

```typescript
// Reconstruct full proposed file content from tool input
function reconstructContent(filePath: string, toolInput: Record<string, unknown>): string
// Handles: content field, old_string+new_string replacement, new file creation
// Falls back gracefully when file doesn't exist or old_string doesn't match
```

### CupcakeHelper

```typescript
interface CupcakeDecision {
  decision: "allow" | "deny" | "block" | "ask" | "modify"
  reason?: string
  updated_input?: { content?: string; [key: string]: unknown }
}

function cupcakeEval(harnessName: string, event: Record<string, unknown>): CupcakeDecision
// Synchronous (execFileSync) — hook protocol is synchronous
// Returns deny on Cupcake not found or eval error
// Timeout: 600s (matches existing rulebook.yml pattern)
```

### SessionHelper

```typescript
interface SessionSignals {
  setActive(): void
  unsetActive(): void
  setRunning(): void
  unsetRunning(): void
  checktime(): void
  close(): void  // drain queue and stop persistent process
}

function createSessionSignals(agentName: string): SessionSignals
// Uses createPersistentQueue internally
// agentName → vim.g key: "<agentName>_active", "<agentName>_running"
```

### Shared Types

```typescript
type HookDecision =
  | { action: "allow" }
  | { action: "deny"; reason?: string }
  | { action: "allow-with-modification"; updatedInput: Record<string, unknown> }
```

## Hook Handler Design per Agent

### Claude (`neph integration hook claude`)

Input events (Claude sends one at a time on stdin):

| Hook | Action |
|------|--------|
| `SessionStart` | `signals.setActive()` |
| `SessionEnd` | `signals.unsetActive()`, `signals.close()` |
| `UserPromptSubmit` | `signals.setRunning()` |
| `Stop` | `signals.unsetRunning()`, `signals.checktime()` |
| `PreToolUse` (Edit\|Write) | `cupcakeEval("claude", event)` → hookSpecificOutput |
| `PostToolUse` (Edit\|Write) | `signals.checktime()` |
| anything else | `{ decision: "allow" }` (pass-through) |

Output format (hookSpecificOutput):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow|deny",
    "updatedInput": { "content": "..." }
  }
}
```
Exit 0 always (structured JSON, no exit-code hacks).

### Gemini (`neph integration hook gemini`)

Existing handler upgraded:
- Add `cupcakeEval("gemini", ...)` before calling neph review directly
- Add `BeforeAgent`/`AfterAgent`/`SessionStart`/`SessionEnd` lifecycle signal handling
- Add `updatedInput` threading for `modify` decisions
- Keep existing `hookSpecificOutput.tool_input` for write_file partial accept (Gemini-specific format)

| Hook | Action |
|------|--------|
| `SessionStart` | `signals.setActive()` |
| `SessionEnd` | `signals.unsetActive()`, `signals.close()` |
| `BeforeAgent` | `signals.setRunning()` |
| `AfterAgent` | `signals.unsetRunning()`, `signals.checktime()` |
| `BeforeTool` (write_file\|edit_file\|replace) | `cupcakeEval("gemini", ...)` → hookSpecificOutput |
| `AfterTool` (write_file\|edit_file\|replace) | `signals.checktime()` |

### Codex (`neph integration hook codex`)

Same pattern as Claude. Codex supports PreToolUse with `updatedInput`. New handler in
integration.ts, new `tools/codex/` directory with hooks config.

Codex hooks config (`~/.codex/hooks.json` or project `.codex/hooks.json`):
```json
{
  "hooks": {
    "PreToolUse": [{ "matcher": "edit|write|create", "command": "neph integration hook codex" }],
    "PostToolUse": [{ "matcher": "edit|write|create", "command": "neph integration hook codex" }],
    "UserPromptSubmit": [{ "command": "neph integration hook codex" }],
    "Stop": [{ "command": "neph integration hook codex" }]
  }
}
```

### Copilot (`neph integration hook copilot`)

Copilot's `preToolUse` only supports `allow/deny/ask` — no `updatedInput`. So Cupcake
`modify` decisions degrade to `allow` (we can't inject modified content). Still worth adding:
lifecycle signals and clean JSON output.

Copilot hooks config (replaces existing `cupcake eval --harness copilot`):
```json
{
  "hooks": [
    { "event": "preToolUse", "filter": {"toolNames": ["edit","create"]}, "command": "neph integration hook copilot" },
    { "event": "postToolUse", "filter": {"toolNames": ["edit","create"]}, "command": "neph integration hook copilot" },
    { "event": "sessionStart", "command": "neph integration hook copilot" },
    { "event": "sessionEnd", "command": "neph integration hook copilot" }
  ]
}
```

### Amp (plugin modification, not hook handler)

`tools/amp/neph-plugin.ts` modified to:
1. Add Cupcake eval before calling `review()` directly
2. Return `{ action: 'modify', input: {...} }` when Cupcake returns `modify` decision

Since Amp is a persistent plugin (not per-invocation), use `execFileSync` for Cupcake (same
as Pi) rather than spawn, to keep the tool.call handler synchronous-ish.

### Cursor (hooks.json update only)

`tools/cursor/hooks.json` changes:
- `afterFileEdit`: remove Cupcake eval, replace with `neph integration hook cursor --checktime` 
  (just fires checktime, no review — file already written)
- Add `beforeShellExecution`: `neph integration hook cursor --shell` → `cupcakeEval("cursor", event)`
- Add `beforeMCPExecution`: `neph integration hook cursor --mcp` → `cupcakeEval("cursor", event)`

Or simpler: one `neph integration hook cursor` handler that dispatches by `hook_event_name`.

### OpenCode (Lua-side, session.lua)

OpenCode's SSE integration lacks lifecycle signals. Add to `session.lua`'s opencode open/kill:
- On open: `neph-cli set opencode_active true` (already happens via `vim.g[termname.."_active"]`
  — but not surfaced to status layer. Wire via `pq.call` or the existing set mechanism)
- The `vim.g[termname.."_active"]` is already set — the gap is that status modules read
  agent-specific keys like `claude_active`. Standardize so opencode maps correctly.

## Cupcake Harness Names

Each agent needs a Cupcake harness registered. The existing `.cupcake/` in the repo has
policies for `claude`, `pi`, `cursor`, `copilot`. We need to add/verify: `amp`, `gemini`,
`codex`. These just need `cupcake init --harness <name>` run once, or the harness name to
match existing policies.

## Build Changes

- `lib/harness-base.ts` is imported by `neph-cli/src/integration.ts` and `tools/amp/neph-plugin.ts`
- No new compiled binaries — everything routes through `neph` CLI or existing plugin entry points
- `tools/codex/` directory: add `package.json` (for build) and hooks config templates
- `scripts/build.sh` may need updating for new tools/ subdirectory if Codex has buildable assets

## File Map

```
tools/
  lib/
    harness-base.ts          (new) — ContentHelper, CupcakeHelper, SessionHelper, types
  amp/
    neph-plugin.ts           (modify) — add Cupcake + partial accept
  claude/
    settings.json            (modify) — point hooks to neph integration hook claude
  copilot/
    hooks.json               (modify) — replace cupcake eval with neph integration hook copilot
                                        add sessionStart/End, postToolUse hooks
  cursor/
    hooks.json               (modify) — add beforeShellExecution/beforeMCPExecution,
                                        remove review from afterFileEdit
  gemini/
    settings.json            (modify) — add lifecycle hooks (SessionStart/End, Before/AfterAgent)
  codex/
    hooks.json               (new) — hook config template for Codex
  neph-cli/src/
    integration.ts           (modify) — add hook handlers: claude, codex, copilot, cursor
                                        upgrade gemini handler to use Cupcake + lifecycle
lua/neph/internal/
  session.lua                (minor) — ensure opencode lifecycle signals use consistent key names
```
