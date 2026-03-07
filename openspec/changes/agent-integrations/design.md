## Context

Neph's pi integration is the gold standard: it overrides built-in `write` and `edit` tools so every file mutation goes through `neph review`. The user sees a vimdiff, makes per-hunk accept/reject decisions, and the agent receives structured feedback. This is deterministic — no file write can bypass the gate.

Research shows 6 other agents support file write interception, but with important caveats:

```
┌──────────────┬─────────────────────┬──────────┬───────────────────────────┐
│ Agent        │ Hook Mechanism      │ Can Block│ Config Location           │
├──────────────┼─────────────────────┼──────────┼───────────────────────────┤
│ pi           │ Tool override (TS)  │ YES      │ ~/.pi/agent/extensions/   │
│ amp          │ Plugin tool.call    │ YES      │ ~/.config/amp/plugins/    │
│ opencode     │ Custom tool (TS)    │ YES      │ .opencode/tools/          │
│ claude       │ PreToolUse hook     │ YES      │ .claude/settings.json     │
│ copilot      │ preToolUse hook     │ YES      │ .github/hooks/hooks.json  │
│ gemini       │ BeforeTool hook     │ YES      │ .gemini/settings.json     │
│ cursor       │ afterFileEdit hook  │ NO ⚠️    │ .cursor/hooks.json        │
├──────────────┼─────────────────────┼──────────┼───────────────────────────┤
│ goose        │ NONE                │ N/A      │ N/A (terminal only)       │
│ codex        │ NONE (MCP only)     │ N/A      │ N/A (terminal only)       │
│ crush        │ UNKNOWN             │ N/A      │ N/A (terminal only)       │
└──────────────┴─────────────────────┴──────────┴───────────────────────────┘
```

**Critical finding:** Cursor's `afterFileEdit` hook is **informational only** — it fires after the file is already written and cannot block the operation. This means Cursor cannot participate in the review-gating pattern. It can still trigger a post-write `checktime` and statusline update, but not deterministic review.

These fall into three categories:
- **Shell-hook agents** (claude, copilot, gemini): run a command, receive JSON on stdin, exit code controls allow/block
- **Plugin-API agents** (amp, opencode): TypeScript plugin/tool override, programmatic API like pi
- **Post-write only** (cursor): informational hook, can observe but not gate writes

## Goals / Non-Goals

**Goals:**
- Every agent with hook support has file writes gated through `neph review`
- Single binary (`neph`) handles all shell-hook agents — no separate scripts, no jq
- Shared TypeScript module for all plugin-API agents — no duplicated nephRun code
- Declarative agent capability metadata drives behavior
- 100% of new code testable without neovim
- Passive autoattach (agents running outside neovim get statusline state for free)
- Pi integration preserved, refactored to use shared module
- CI passes locally and remotely

**Non-Goals:**
- Integrating agents without hook systems (goose, codex, crush)
- Modifying upstream agent CLIs
- Moving the review engine from Lua to TypeScript (headless neovim tests are fine)
- Active autoattach (rpc.lua tracking callers, virtual session entries)
- Per-project hook customization (global install for now)

## Decisions

### 1. `neph gate` subcommand instead of a separate shell script

All shell-hook agents (claude, copilot, cursor, gemini) use the same pattern: run a command, pipe JSON to stdin, read exit code. Rather than a separate `neph-gate.sh` script requiring jq, we add a `gate` subcommand to the existing `neph` CLI.

```
Agent CLI ──stdin──▶ neph gate --agent claude
                         │
                         ├─ Parse agent-specific JSON from stdin
                         ├─ Extract file_path + content
                         ├─ neph set claude_active true  (passive autoattach)
                         ├─ Run review flow internally
                         ├─ neph unset claude_active
                         │
                         ├─ exit 0  (accept/partial)
                         └─ exit 2  (reject)
```

**Why this over a shell script:**
- No jq dependency — Node parses JSON natively
- No separate binary to install — `neph` is already on PATH
- Shares code with existing CLI — FakeTransport testing, same build pipeline
- One test infrastructure — vitest for everything
- Handles agent format normalization in TypeScript (clean, type-safe)

**Agent format normalization:** Each agent sends a different JSON stdin schema. The `--agent` flag selects the parser. Exact schemas from upstream documentation:

**Claude Code** (PreToolUse):
```json
{
  "session_id": "abc123",
  "hook_event_name": "PreToolUse",
  "tool_name": "Write",                        // or "Edit"
  "tool_input": {
    "file_path": "/path/to/file.txt",
    "content": "full file content"              // Write tool
    // OR for Edit tool:
    // "old_str": "text to find",
    // "new_str": "replacement text"            // NOTE: old_str/new_str, NOT old_string/new_string
  }
}
```

**Copilot CLI** (preToolUse):
```json
{
  "timestamp": 1704614400000,
  "cwd": "/path/to/project",
  "toolName": "edit",                           // or "create"
  "toolArgs": "{\"filepath\":\"/path/to/file.txt\",\"content\":\"file content\"}"
  // NOTE: toolArgs is a JSON-FORMATTED STRING, requires double-parsing
}
```

**Gemini CLI** (BeforeTool):
```json
{
  "session_id": "string",
  "hook_event_name": "BeforeTool",
  "tool_name": "write_file",
  "tool_input": {
    "filepath": "/path/to/file",                // NOTE: "filepath" not "file_path"
    "content": "file content"
    // OR: "new_string" for edit operations
  }
}
```

**Cursor** (afterFileEdit — informational only, CANNOT block):
```json
{
  "file_path": "/absolute/path/to/file.txt",
  "edits": [{ "old_string": "original", "new_string": "replacement" }],
  "hook_event_name": "afterFileEdit"
}
```

Each normalizes to `{ filePath: string, content: string }` before calling the review flow. Cursor is the exception — since it cannot block writes, its gate handler only calls `checktime` and manages statusline state (no review).

**Alternative considered:** Separate POSIX shell script with jq. Rejected because it adds a runtime dependency, requires separate test infrastructure, and can't share code with the neph CLI.

### 2. Shared `tools/lib/neph-run.ts` extracted from pi.ts

Pi.ts contains ~50 lines of core logic: `nephRun()` (spawn neph subprocess), `review()` (call nephRun with review args, parse ReviewEnvelope), fire-and-forget `neph()` (queue commands). This is identical for amp and opencode adapters.

```
tools/
  lib/
    neph-run.ts          ← nephRun(), review(), neph() — extracted from pi.ts
  pi/
    pi.ts                ← imports { nephRun, review, neph } from '../lib/neph-run'
  amp/
    neph-plugin.ts       ← imports { nephRun, review, neph } from '../lib/neph-run'
  opencode/
    neph-write.ts        ← imports { nephRun, review, neph } from '../lib/neph-run'
```

**Why extract vs duplicate:**
- One place to fix bugs (timeout handling, error recovery)
- Testable in isolation with mock child_process
- Pi.ts refactor is mechanical — import instead of inline

**Alternative considered:** Keep nephRun inline in each adapter. Rejected because it creates N copies of the same timeout/error/queue logic.

### 3. Agent capability metadata in agents.lua

Each agent definition gains an `integration` field:

```lua
{
  name = "claude",
  cmd = "claude",
  args = { "--permission-mode", "plan" },
  integration = {
    type = "hook",     -- "hook" (shell) | "extension" (TS plugin) | nil (terminal only)
    capabilities = { "review", "status", "checktime" },
  },
}
```

Session.lua behavior:

| integration.type | vim.g state | Review gating | Who manages lifecycle |
|-----------------|-------------|---------------|----------------------|
| `nil` | session.lua sets on open/kill | None | session.lua |
| `"hook"` | neph gate sets via RPC | neph gate | neph gate |
| `"extension"` | Extension sets via RPC | Extension | Extension |

**Why in agents.lua:** It's the single source of truth, session.lua already queries it, users can override via `config.agents` merge.

**Alternative considered:** Capability metadata in tool config files. Rejected because it's harder to query at runtime from Lua.

### 4. Passive autoattach via neph gate state management

When `neph gate` runs (triggered by any agent hook), it calls:
1. `neph set <agent>_active true` before the review
2. `neph unset <agent>_active` after the review completes

This means agents running OUTSIDE neovim (e.g., amp in a separate terminal auto-discovering the socket) still register in `vim.g` for statusline. No new concepts — it's the pi pattern.

**Why passive over active:**
- Already works (pi does this)
- No state management in rpc.lua
- Can't focus/toggle external agent terminals anyway
- Zero-overhead: if no socket, neph gate auto-accepts silently

### 5. Testing strategy: protocol contract as the boundary

```
┌─────────────────────────────────────────────────────┐
│ Testable WITHOUT neovim (vitest):                    │
│                                                      │
│  neph gate ──────── FakeTransport                    │
│  lib/neph-run ───── mock child_process               │
│  amp plugin ─────── mock nephRun                     │
│  opencode tool ──── mock nephRun                     │
│  hook config JSON ─ parse + structure validate       │
│  protocol.json ──── contract tests (both sides)      │
│  pi.ts ──────────── existing mocks                   │
├─────────────────────────────────────────────────────┤
│ Requires headless neovim (plenary/busted):           │
│                                                      │
│  review engine ──── existing, unchanged              │
│  rpc dispatch ───── existing, unchanged              │
│  session.lua ────── add capability metadata tests    │
│  agents.lua ─────── add integration field tests      │
└─────────────────────────────────────────────────────┘
```

ALL new code lives in the top box. The bottom box is existing code with existing tests.

### 6. Hook config installation strategy

For agents with user-level settings files (claude, gemini), we can't overwrite the entire file — the user may have other settings. Two strategies:

**A) Standalone hook file** — for agents that support `include` or separate hook files:
- Copilot: `.github/hooks/hooks.json` is already a standalone file
- Cursor: `~/.cursor/hooks.json` is standalone

**B) Merge strategy** — for agents that use a shared settings file:
- Claude: `.claude/settings.json` — merge `hooks` key only
- Gemini: `.gemini/settings.json` — merge `hooks` key only

`tools.lua` will implement a JSON merge helper for (B): read existing file, deep-merge the `hooks` key, write back. If no existing file, write the full config.

## Risks / Trade-offs

- **[Agent stdin format changes]** Agent CLIs may change their hook stdin JSON format between versions. → Mitigation: `--agent` flag selects parser, each parser is ~10 lines, easy to update. Version-pinned comments in code.

- **[Settings file merge conflicts]** Merging into `~/.claude/settings.json` could conflict with user config. → Mitigation: Only touch the `hooks` key. Warn on first install. Add `neph uninstall` command to remove hooks.

- **[Pi refactor regression]** Extracting nephRun into shared lib could break pi. → Mitigation: Pi's existing test suite validates behavior. Refactor is mechanical (import vs inline). Run tests before and after.

- **[Gate command adds CLI surface area]** More commands = more to maintain. → Mitigation: Gate is just a stdin normalizer + existing review call. Most of the logic already exists.

## Open Questions (Resolved)

- **Cursor `afterFileEdit` is post-write only** — RESOLVED: Cursor's hook is informational. It cannot block writes. Cursor's gate handler will call `checktime` and manage statusline state only. No review gating possible. This is documented and accepted.
- **Copilot hooks location** — `.github/hooks/hooks.json` must be on the default branch. This means it's effectively project-level, not user-level. For user-level install, we'll document this limitation. Users who want copilot integration need to commit the hooks file (or use a local git hook workaround).
- **Copilot toolArgs is a JSON string** — RESOLVED: `toolArgs` is a JSON-formatted string, not an object. The gate parser must call `JSON.parse(toolArgs)` before extracting fields.
- **Claude uses `old_str`/`new_str`** — RESOLVED: NOT `old_string`/`new_string`. The Edit tool fields are `old_str` and `new_str`.
- **Gemini uses `filepath`** — RESOLVED: NOT `file_path`. The field name is `filepath` (no underscore).
- **OpenCode custom tool naming** — Still needs verification: what are the exact built-in tool names to override?
