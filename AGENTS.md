# AGENTS.md

> Essential guide for AI agents working in the neph.nvim codebase.

## Project Overview

**neph.nvim** is a Neovim plugin that provides a universal bridge between AI coding agents and Neovim. It manages multiple agent backends (crush, claude, goose, pi, etc.) and enables interactive diff reviews, state management, and tool discovery through a clean RPC interface.

### Key Components

1. **Lua Plugin** (`lua/neph/`) – Core Neovim integration
2. **Node.js CLI** (`tools/neph-cli/`) – Universal bridge that external agents call
3. **Pi Extension** (`tools/pi/`) – Integration for the pi coding agent
4. **RPC Protocol** (`protocol.json`) – Contract between CLI and Lua

## Essential Commands

All commands use [Task](https://taskfile.dev/) (modern Make alternative).

### Testing

```bash
# Run all tests (Lua + TypeScript)
task test

# Lua tests only (uses plenary.nvim)
nvim --headless \
  --cmd 'set rtp+=.' \
  --cmd "set rtp+=~/.local/share/nvim/lazy/plenary.nvim" \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
  -c 'qa!'

# TypeScript CLI tests
task tools:test:neph

# Pi extension tests
task tools:test:pi
```

### Linting

```bash
# Run all linters
task lint

# Lua linting
stylua --check lua/ tests/
luacheck lua/ tests/ --globals vim Snacks describe it before_each after_each assert

# TypeScript linting (neph-cli)
task tools:lint:neph  # runs: npx tsc --noEmit

# Deno linting (pi)
task tools:lint:pi    # runs: deno lint pi.ts
```

### CI

```bash
# Run full CI pipeline locally (via Dagger)
task dagger  # runs: deno run -A .fluentci/ci.ts

# CI runs both lint + test
task ci
```

### Documentation

```bash
# Generate vimdoc from EmmyLua annotations
task docs  # runs: nvim --headless -u NONE -l scripts/docgen.lua
```

## Code Organization

### Lua Structure

```
lua/neph/
├── init.lua              # Main setup() entry point
├── config.lua            # Configuration types and defaults
├── api.lua               # User-facing API (keybindings)
├── rpc.lua               # RPC dispatch facade (single entry point)
├── tools.lua             # Auto-install companion tools
├── api/                  # RPC-exposed modules
│   ├── buffers.lua       # Buffer/tab operations
│   ├── status.lua        # vim.g status management
│   └── review/           # Diff review system
│       ├── init.lua      # Public review API
│       ├── engine.lua    # Pure hunk computation logic
│       └── ui.lua        # Neovim UI layer (signs, picker)
└── internal/             # Private implementation
    ├── agents.lua        # Agent registry (crush, claude, etc.)
    ├── backends/         # Terminal backend adapters
    ├── completion.lua    # Cmdline completion
    ├── context.lua       # Editor state helpers
    ├── file_refresh.lua  # Auto-reload changed files
    ├── history.lua       # Prompt history
    ├── input.lua         # Input popup
    ├── picker.lua        # Agent picker (Snacks.nvim)
    ├── placeholders.lua  # +token expansion
    ├── session.lua       # Terminal session management
    └── terminal.lua      # Terminal wrapper
```

### TypeScript CLI (`tools/neph-cli/`)

```
src/
├── index.ts          # CLI entry point, command router
└── transport.ts      # Neovim msgpack-rpc client

tests/
├── commands.test.ts  # CLI command tests
├── contract.test.ts  # protocol.json contract validation
└── fake_transport.ts # Mock Neovim transport
```

### Pi Extension (`tools/pi/`)

```
pi.ts                 # Pi extension that spawns neph CLI
tests/pi.test.ts      # Extension tests
```

## Critical Patterns

### 1. RPC Architecture

**All external RPC calls flow through a single entry point:**

```lua
-- lua/neph/rpc.lua
function M.request(method, params)
  local handler = dispatch[method]
  -- Routes to lua/neph/api/* modules
end
```

**External callers (TypeScript CLI):**

```typescript
const result = await transport.request(
  'nvim_exec_lua',
  [RPC_CALL, [method, params]]
);
```

**Contract validation:** Changes to `protocol.json` must be reflected in both:
- `lua/neph/rpc.lua` dispatch table
- `tools/neph-cli/tests/contract.test.ts`

### 2. Review Protocol (Async, Request-Correlated)

The diff review system is asynchronous and uses temp files + notifications:

1. **CLI** calls `review.open` with `request_id`, `result_path`, `channel_id`
2. **Neovim** opens diff UI, user makes per-hunk decisions
3. **Neovim** writes `ReviewEnvelope` JSON to `result_path`
4. **Neovim** fires `rpcnotify` to `channel_id` to signal completion
5. **CLI** reads result from `result_path`, prints to stdout

**Key files:**
- `lua/neph/api/review/engine.lua` – Pure hunk computation logic
- `lua/neph/api/review/ui.lua` – Snacks.picker integration
- `tools/neph-cli/src/index.ts:runCommand('review')` – CLI orchestration

### 3. Review Engine vs. UI Split

**Engine** (`engine.lua`): Testable in headless Neovim
- `compute_hunks(old_lines, new_lines)` – Uses `vim.diff`
- `apply_decisions(new_lines, hunks, decisions)` – Reconstructs content
- `build_envelope(decision, content, hunks, reason)` – JSON response

**UI** (`ui.lua`): Neovim-specific
- Manages signs, virtual text, and `Snacks.picker` lifecycle
- Calls engine functions for logic

### 4. Agent Registration

Built-in agents are defined in `lua/neph/internal/agents.lua`:

```lua
local agents = {
  {
    name = "crush",
    label = "Crush",
    icon = "  ",
    cmd = "crush",
    args = {},
  },
  -- ... etc
}
```

**Adding a new agent:**
1. Add entry to `agents` table
2. Ensure `cmd` is executable via `vim.fn.executable(cmd)`
3. The `full_cmd` field is computed at runtime

**User override:** Users can extend/override via `setup({ agents = {...} })`.

### 5. Context Placeholders

Tokens like `+cursor`, `+selection`, `+diagnostics` are expanded before sending prompts.

**Providers:** `lua/neph/internal/placeholders.lua`

```lua
M.providers.cursor = function(ctx)
  return string.format("@%s:%d", path, ctx.row)
end
```

**Expansion:** `lua/neph/internal/input.lua` calls `placeholders.expand(text, ctx)`.

**Supported tokens:**
- `+file`, `+cursor`, `+line`, `+position` – File location
- `+selection` – Visual selection text
- `+diagnostics` – Buffer diagnostics
- `+git` – `git status`
- `+diff` – `git diff` for current file
- `+buffers`, `+quickfix`, `+loclist`, `+folder`, `+marks`, `+search` – Neovim state

### 6. Socket Integration

Neph forwards `$NVIM_SOCKET_PATH` to every agent terminal. The `neph` CLI uses this to discover and connect back to Neovim.

**Discovery:** `tools/neph-cli/src/transport.ts:discoverNvimSocket()`

```typescript
// Tries in order:
// 1. $NVIM_SOCKET_PATH
// 2. $NVIM
// 3. Glob search in /tmp/nvim.*/0
```

### 7. Dry-Run Mode

Set `NEPH_DRY_RUN=1` to auto-accept all review hunks (for non-interactive CI/testing).

**Check:** `tools/neph-cli/src/index.ts`

```typescript
const dryRun = process.env.NEPH_DRY_RUN === '1';
if (dryRun) {
  // Auto-accept, skip RPC call
}
```

## Testing Strategy

### 1. Lua Unit Tests

**Framework:** `plenary.busted`

**Key test files:**
- `tests/api/review/engine_spec.lua` – Hunk computation, decision application
- `tests/contract_spec.lua` – Validates Lua RPC dispatch matches `protocol.json`
- `tests/agents_spec.lua`, `tests/config_spec.lua`, etc.

**Run:** `task test` or directly with `nvim --headless` (see Commands)

**Pattern:**
```lua
describe("module", function()
  it("should do something", function()
    assert.equals(expected, actual)
  end)
end)
```

### 2. TypeScript CLI Tests

**Framework:** `vitest`

**Key test files:**
- `tools/neph-cli/tests/commands.test.ts` – CLI argument parsing
- `tools/neph-cli/tests/contract.test.ts` – Validates CLI matches `protocol.json`
- `tools/neph-cli/tests/integration/rpc.test.ts` – RPC round-trip tests

**Run:** `task tools:test:neph` or `npm test -- --run` in `tools/neph-cli/`

**Pattern:**
```typescript
describe('command', () => {
  it('should handle args', async () => {
    expect(result).toBe(expected);
  });
});
```

### 3. Contract Tests

**Both Lua and TypeScript validate against `protocol.json`.**

When adding a new RPC method:
1. Update `protocol.json`
2. Add dispatch handler in `lua/neph/rpc.lua`
3. Update `tests/contract_spec.lua` expected methods
4. Update `tools/neph-cli/tests/contract.test.ts` expected methods

### 4. Manual UI Verification

Neovim UI components (signs, virtual text, `Snacks.picker`) require manual testing:
1. Open Neovim with neph.nvim installed
2. Trigger an agent that edits a file (e.g., `claude code`)
3. Verify diff tab opens with correct hunks
4. Test Accept/Reject/Comment on individual hunks
5. Test "Accept all" / "Reject all"
6. Verify signs and virtual text update correctly

## Naming Conventions

### Lua

- **Public modules:** `require("neph.api")`, `require("neph.config")`
- **Internal modules:** `require("neph.internal.agents")`
- **Function names:** `snake_case` (e.g., `get_active_session`)
- **Private functions:** `local function helper()` (not in module table)
- **EmmyLua annotations:** All public functions must have type annotations

### TypeScript

- **Functions:** `camelCase` (e.g., `discoverNvimSocket`)
- **Classes/Interfaces:** `PascalCase` (e.g., `NvimTransport`)
- **Constants:** `UPPER_SNAKE_CASE` (e.g., `RPC_CALL`)

### Files

- Lua: `snake_case.lua` (e.g., `review_engine.lua`)
- TypeScript: `snake_case.ts` (e.g., `fake_transport.ts`)
- Tests: `*_spec.lua` (Lua), `*.test.ts` (TypeScript)

## Code Style

### Lua Formatting

**Tool:** `stylua` (config: `.stylua.toml`)

```toml
column_width = 120
line_endings = "Unix"
indent_type = "Spaces"
indent_width = 2
quote_style = "AutoPreferDouble"
call_parentheses = "Always"
```

**Auto-format:** `stylua lua/ tests/`

### TypeScript Formatting

**No explicit formatter configured.** Follow existing patterns:
- 2-space indentation
- Double quotes for strings
- Semicolons required
- Use `async/await` over raw promises

### Lua Style Guidelines

1. **Prefer explicit returns:** Always return a value or `nil` (don't rely on implicit `nil`)
2. **Guard early:** Check preconditions at the top of functions
3. **Use local functions:** Don't pollute module table with helpers
4. **Avoid global state:** Pass state explicitly via parameters
5. **EmmyLua annotations:** Required for all public APIs

**Example:**
```lua
---@param name string
---@param value any
---@return boolean success
function M.set_status(name, value)
  if not name or name == "" then
    return false
  end
  vim.g[name] = value
  return true
end
```

### TypeScript Style Guidelines

1. **Explicit return types:** Annotate function return types
2. **Null checks:** Always check for `null`/`undefined` before accessing properties
3. **Error handling:** Use `try/catch` for async operations
4. **Async/await:** Prefer over `.then()` chains

## Important Gotchas

### 1. Lua LSP Warnings about `full_cmd`

The LSP complains about missing `full_cmd` in agent definitions. **This is expected.** The field is populated at runtime by `build_full_cmd()` in `lua/neph/internal/agents.lua`.

**Why:** The `full_cmd` string is computed lazily (only for installed agents).

**Fix:** Suppress the warning or annotate `full_cmd?` as optional in the type definition.

### 2. `protocol.json` is Source of Truth

**Never add RPC methods without updating `protocol.json` first.**

Contract tests in both Lua and TypeScript validate against this file. Changes require updates in three places:
1. `protocol.json` – Add method definition
2. `lua/neph/rpc.lua` – Add dispatch handler
3. Contract test files – Update expected method lists

### 3. Review Result Path Must Be Unique

The `neph review` command uses a randomly-generated temp file path to avoid collisions. **Never hardcode a result path.**

**Correct:** `tools/neph-cli/src/index.ts`

```typescript
const resultPath = path.join(os.tmpdir(), `neph-review-${crypto.randomUUID()}.json`);
```

### 4. Neovim Buffer Reloading

Agents that modify files externally must call `neph checktime` or `:checktime` to reload buffers.

**Auto-refresh:** Neph has a built-in periodic file refresh (see `lua/neph/internal/file_refresh.lua`), but agents should still call `checktime` after edits for immediate updates.

### 5. Sign Management in Review UI

The review UI uses Neovim signs to mark hunks. **Signs must be cleaned up when the tab closes.**

**Implementation:** `lua/neph/api/review/ui.lua` uses autocommands to clean signs on `BufWipeout`.

### 6. Snacks.nvim Dependency

The native terminal backend (`multiplexer = "snacks"`) requires [folke/snacks.nvim](https://github.com/folke/snacks.nvim).

**Check before using:** `lua/neph/internal/backends/snacks.lua`

```lua
local has_snacks = pcall(require, "snacks")
if not has_snacks then
  error("snacks.nvim not found")
end
```

### 7. Luacheck Globals

Luacheck must be configured with Neovim globals:

```bash
luacheck lua/ tests/ --globals vim Snacks describe it before_each after_each assert
```

**Test globals:** `describe`, `it`, `before_each`, `after_each`, `assert` (from plenary.busted)

### 8. Plenary Requirement for Tests

Lua tests require [nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim) to be installed.

**Default path:** `~/.local/share/nvim/lazy/plenary.nvim`

**Override:** Set `PLENARY_PATH` environment variable.

### 9. Nix Flake for CI

The CI pipeline uses `flake.nix` to provide a deterministic environment with:
- Neovim 0.10+
- Node.js
- Deno
- Task
- plenary.nvim

**Local usage:** `nix develop` to enter the shell.

### 10. Agent Terminal State

Each agent session stores state in `lua/neph/internal/session.lua`. **State is not persisted across Neovim restarts.**

When adding session state, consider:
- Should it be saved to disk?
- Should it be cleared on agent switch?
- Should it be exposed via RPC?

## Adding New Features

### Adding a New RPC Method

**Example:** Add a method to get buffer diagnostics.

1. **Update `protocol.json`:**

```json
{
  "methods": {
    "diagnostics.get": {
      "params": ["bufnr"],
      "async": false
    }
  }
}
```

2. **Add Lua module:** `lua/neph/api/diagnostics.lua`

```lua
local M = {}

function M.get(params)
  local bufnr = params[1] or 0
  return vim.diagnostic.get(bufnr)
end

return M
```

3. **Register in `lua/neph/rpc.lua`:**

```lua
local dispatch = {
  ["diagnostics.get"] = function(p)
    return require("neph.api.diagnostics").get(p)
  end,
  -- ... existing methods
}
```

4. **Add CLI command in `tools/neph-cli/src/index.ts`:**

```typescript
if (command === 'diagnostics') {
  const bufnr = args[0] ? parseInt(args[0]) : 0;
  const result = await transport.request('nvim_exec_lua', [
    RPC_CALL,
    ['diagnostics.get', [bufnr]]
  ]);
  console.log(JSON.stringify(result));
  return;
}
```

5. **Update contract tests:**
   - `tests/contract_spec.lua` – Add `"diagnostics.get"` to expected methods
   - `tools/neph-cli/tests/contract.test.ts` – Add to expected methods

6. **Write unit tests:**
   - `tests/api/diagnostics_spec.lua` – Test Lua module
   - `tools/neph-cli/tests/commands.test.ts` – Test CLI command

### Adding a New Agent

**Example:** Add support for "aider" agent.

1. **Add to `lua/neph/internal/agents.lua`:**

```lua
local agents = {
  -- ... existing agents
  {
    name = "aider",
    label = "Aider",
    icon = " 󰚩 ",
    cmd = "aider",
    args = { "--yes" },
  },
}
```

2. **Test:** Open Neovim, run `:lua require("neph.internal.agents").list()` and verify "aider" appears if installed.

3. **Document:** Update README.md agent list.

### Adding a New Placeholder

**Example:** Add `+branch` to expand current git branch.

1. **Add provider in `lua/neph/internal/placeholders.lua`:**

```lua
M.providers.branch = function(ctx)
  local result = vim.fn.system("git rev-parse --abbrev-ref HEAD 2>/dev/null")
  if vim.v.shell_error ~= 0 then
    return nil
  end
  return vim.trim(result)
end
```

2. **Document:** Update README.md placeholder table.

3. **Test:** Open Neovim in a git repo, run `:lua print(require("neph.internal.placeholders").expand("+branch", require("neph.internal.context").capture()))`

## Dependencies

### Runtime

- **Neovim:** ≥ 0.10
- **Node.js:** For `neph` CLI (auto-installed during `setup()`)
- **[folke/snacks.nvim](https://github.com/folke/snacks.nvim):** For native terminal backend and picker

### Development

- **Lua:** stylua, luacheck
- **TypeScript:** tsc, esbuild, vitest
- **Deno:** For pi extension linting
- **Task:** Command runner (alternative to Make)
- **[nvim-lua/plenary.nvim](https://github.com/nvim-lua/plenary.nvim):** For Lua tests
- **Dagger:** For CI pipeline orchestration
- **Nix:** For deterministic CI environment

### Installation

```lua
-- lazy.nvim
{
  "roshbhatia/neph.nvim",
  dependencies = { "folke/snacks.nvim" },
  opts = {},
}
```

## Project-Specific Context

### Design Philosophy

1. **Single entry point:** All RPC calls flow through `lua/neph/rpc.lua`
2. **Pure logic separation:** Engine logic (e.g., hunk computation) is separate from UI
3. **Contract validation:** `protocol.json` is enforced by tests
4. **Testability first:** UI-free logic can be tested in headless Neovim
5. **Zero config by default:** Works out-of-the-box with sensible defaults

### Multi-Protocol Architecture (Planned)

See `openspec/changes/multi-protocol-architecture/` for ongoing architectural changes. The project is evolving toward a more modular protocol dispatch system.

**Key documents:**
- `openspec/changes/multi-protocol-architecture/proposal.md` – High-level design
- `openspec/changes/multi-protocol-architecture/tasks.md` – Implementation checklist

### Multiplexer Backends

Neph supports multiple terminal backends:
- **snacks** (default): Native Neovim splits via snacks.nvim
- **wezterm**: WezTerm panes (experimental)
- **tmux**: tmux splits (stub)
- **zellij**: zellij panes (stub)

**Backend adapter location:** `lua/neph/internal/backends/`

**Adding a new backend:**
1. Create `lua/neph/internal/backends/my_backend.lua`
2. Implement interface: `open()`, `send()`, `close()`, `focus()`
3. Add to `lua/neph/internal/terminal.lua` backend selection
4. Add integration tests

## Common Workflows

### Running a Single Test File

**Lua:**
```bash
nvim --headless \
  --cmd 'set rtp+=.' \
  --cmd 'set rtp+=~/.local/share/nvim/lazy/plenary.nvim' \
  -c "lua require('plenary.busted').run('tests/agents_spec.lua')" \
  -c 'qa!'
```

**TypeScript:**
```bash
cd tools/neph-cli
npm test -- tests/commands.test.ts
```

### Debugging RPC Calls

**Enable logging in CLI:**

```bash
# Add to tools/neph-cli/src/index.ts
console.error(`[DEBUG] Calling ${method} with params:`, params);
```

**Enable logging in Lua:**

```lua
-- Add to lua/neph/rpc.lua
vim.notify(vim.inspect({ method = method, params = params }), vim.log.levels.DEBUG)
```

### Testing Review Flow Manually

```bash
# 1. Start Neovim in one terminal
nvim test.txt

# 2. In another terminal, call neph CLI
echo "new content here" | neph review test.txt
```

**Expected:** Neovim opens a diff tab, allows per-hunk decisions, returns JSON on stdout.

### Regenerating Documentation

```bash
task docs
# Opens nvim headless, reads EmmyLua annotations, writes doc/neph.txt
```

**Commit the generated vimdoc** after API changes.

## Resources

- **Architecture doc:** `docs/architecture.md`
- **Testing strategy:** `docs/testing.md`
- **RPC protocol spec:** `docs/rpc-protocol.md`
- **Canonical contract:** `protocol.json`
- **OpenSpec changes:** `openspec/changes/` – Design docs for ongoing work

## Quick Reference

| Task | Command |
|------|---------|
| Run all tests | `task test` |
| Run Lua tests | `task test` (includes Lua subset) |
| Run CLI tests | `task tools:test:neph` |
| Run pi tests | `task tools:test:pi` |
| Run all linters | `task lint` |
| Lint Lua | `stylua --check lua/ tests/ && luacheck lua/ tests/ --globals vim Snacks describe it before_each after_each assert` |
| Lint CLI | `task tools:lint:neph` |
| Lint pi | `task tools:lint:pi` |
| Generate docs | `task docs` |
| Run CI locally | `task dagger` |
| Format Lua | `stylua lua/ tests/` |

---

**Last Updated:** 2026-03-06
