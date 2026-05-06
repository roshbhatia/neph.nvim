# AGENTS.md

> Essential guide for AI agents working in the neph.nvim codebase.

## Project Overview

**neph.nvim** is a Neovim plugin that provides a universal bridge between AI coding agents and Neovim. Agents and backends are injected explicitly via `setup()` — no hardcoded lists, no string-enum config. It enables interactive diff reviews, state management, and tool discovery through a clean RPC interface.

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
bash scripts/run-lua-tests.sh

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
├── init.lua              # Main setup() entry point (DI wiring)
├── config.lua            # Configuration types and defaults
├── api.lua               # User-facing API (keybindings)
├── rpc.lua               # RPC dispatch facade (single entry point)
├── tools.lua             # Generic tool manifest executor
├── agents/               # Agent submodules (pure data tables)
│   ├── all.lua           # Re-exports all 10 agents
│   ├── claude.lua        # Claude agent definition
│   ├── goose.lua         # Goose agent definition
│   ├── pi.lua            # Pi agent (type=extension, with tools manifest)
│   └── ...               # amp, codex, copilot, crush, cursor, gemini, opencode
├── backends/             # Backend modules (injected via setup)
│   ├── snacks.lua        # snacks.nvim terminal backend
│   ├── wezterm.lua      # WezTerm pane backend
│   └── zellij.lua       # Zellij pane backend
├── api/                  # RPC-exposed modules
│   ├── buffers.lua       # Buffer/tab operations
│   ├── status.lua        # vim.g status management
│   └── review/           # Diff review system
│       ├── init.lua      # Public review API
│       ├── engine.lua    # Pure hunk computation logic
│       └── ui.lua        # Neovim UI layer (signs, picker)
└── internal/             # Private implementation
    ├── agents.lua        # Agent accessor (thin wrapper over injected defs)
    ├── contracts.lua     # Contract validation (agents, backends, tools)
    ├── completion.lua    # Cmdline completion
    ├── context.lua       # Editor state helpers
    ├── file_refresh.lua  # Auto-reload changed files
    ├── history.lua       # Prompt history
    ├── input.lua         # Input popup
    ├── log.lua           # Debug logger (writes to /tmp/neph-debug.log)
    ├── picker.lua        # Agent picker (Snacks.nvim)
    ├── placeholders.lua  # +token expansion
    ├── session.lua       # Terminal session management
    └── terminal.lua      # Terminal wrapper
```

### TypeScript CLI (`tools/neph-cli/`)

```
src/
├── index.ts          # CLI entry point, command router
├── gate.ts           # Gate system (declarative agent schemas, review interception)
└── transport.ts      # Neovim msgpack-rpc client

tests/
├── commands.test.ts       # CLI command tests
├── contract.test.ts       # protocol.json contract validation
├── gate.test.ts           # Gate parser tests (all agents)
├── gate.contract.test.ts  # Gate schema contract validation
├── gate.fuzz.test.ts      # Fuzz testing for gate parsers
├── hook-configs.test.ts   # Hook configuration generation
├── transport.test.ts      # Transport layer tests
├── fake_transport.ts      # Mock Neovim transport
└── integration/
    └── rpc.test.ts        # RPC round-trip tests
```

### Shared Library (`tools/lib/`)

```
log.ts                # Debug logger (writes to /tmp/neph-debug-<ppid>.log when NEPH_DEBUG=1)
neph-run.ts           # CLI runner — spawn `neph` binary for review/ui/status calls
tests/
└── log.test.ts       # Logger tests
```

### Pi Extension (`tools/pi/`)

```
cupcake-harness.ts    # Pi Cupcake harness (intercepts write/edit tool_call events)
tests/
└── cupcake-harness.test.ts  # Harness tests
```

### Amp Plugin (`tools/amp/`)

```
neph-plugin.ts        # Amp plugin — review interception via tool.call hook
                      # Symlinked to ~/.config/amp/plugins/neph-plugin.ts
dist/amp.js           # Built bundle (esbuild)
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

The diff review system is asynchronous. All agents go through the CLI review path:

**CLI agents (via neph CLI):**
1. CLI calls `review.open` with `request_id`, `result_path`, `channel_id`
2. Neovim opens diff UI, user makes per-hunk decisions
3. Neovim writes `ReviewEnvelope` JSON to `result_path`
4. Neovim fires `rpcnotify` to `channel_id` to signal completion
5. CLI reads result from `result_path`, prints to stdout

**Amp plugin (direct RPC):**
1. Plugin intercepts `tool.call` events for file writes
2. Calls `neph review <filePath>` via `neph-run.ts` with proposed content on stdin
3. Returns `{ action: "allow" | "reject-and-continue" }` based on user decision

**Key files:**
- `lua/neph/api/review/engine.lua` – Pure hunk computation logic
- `lua/neph/api/review/ui.lua` – Vimdiff tab with per-hunk review keymaps
- `tools/lib/neph-run.ts:review()` – CLI-based review path
- `tools/neph-cli/src/index.ts:runCommand('review')` – CLI review path

### 3. Review Engine vs. UI Split

**Engine** (`engine.lua`): Testable in headless Neovim
- `compute_hunks(old_lines, new_lines)` – Uses `vim.diff`
- `apply_decisions(new_lines, hunks, decisions)` – Reconstructs content
- `build_envelope(decision, content, hunks, reason)` – JSON response

**UI** (`ui.lua`): Neovim-specific
- Opens vimdiff tab (current left, proposed right) with per-hunk keymaps
- Manages signs, virtual text hints, and winbar status display
- Calls engine functions for logic

### 4. Claude Integration — `--settings` Separation

Neph writes its Claude hooks to `.neph/claude.json` (not `.claude/settings.json`).
This avoids mutating the user's own Claude Code settings file. Claude Code merges the
file on top of existing settings when invoked with:

```bash
claude --settings .neph/claude.json
```

Add this as an alias or shell function to avoid repeating the flag:

```bash
alias claude='claude --settings .neph/claude.json'
```

`.neph/` is gitignored — the generated config is machine-local.

### 5. Global Hook Installation (`neph install`)

For zero-friction setup across all supported agents, neph ships a one-shot installer that writes globally-scoped hook configs. No per-project commits required.

```bash
# Install hooks for all agents (gemini, cursor, codex)
neph install

# Install for a single agent
neph install gemini

# Remove hooks from global configs
neph uninstall
neph uninstall cursor
```

**What `neph install` does per agent:**

| Agent  | Global config written                | Notes                                   |
|--------|--------------------------------------|-----------------------------------------|
| gemini | `~/.gemini/settings.json`            | Merges; safe to re-run after updates    |
| cursor | `~/.cursor/hooks.json`               | Merges; safe to re-run                  |
| codex  | `~/.codex/hooks.json`                | Merges; safe to re-run                  |
| claude | (none)                               | Uses shell alias instead — see below    |

Install embeds the **absolute path** to the current `neph` binary in every hook command, so hooks fire without needing `$PATH` to be configured at hook execution time. Re-running `neph install` after a neph update rewrites configs with the new binary path.

Install is **idempotent**: running it multiple times produces the same result. The merge logic deduplicates entries by command string.

**Shell alias setup (printed after install):**

```bash
# Add to ~/.zshrc or ~/.bashrc:
alias claude='claude --settings "$(neph print-settings claude)"'
alias codex='codex --enable codex_hooks'
```

The `claude` alias injects neph hooks inline via `--settings` — no config file needs to be committed or written to disk. The `codex` alias enables hook processing (off by default in Codex).

**Gemini warning:** Gemini bug #23138 may overwrite `~/.gemini/settings.json` when themes change. Re-run `neph install gemini` after any theme change.

**`neph print-settings <agent>`:** Prints the hook config template for an agent as minified JSON. Used by the `claude` shell alias:

```bash
# Print claude hook settings (useful in shell aliases or CI)
neph print-settings claude

# Print gemini settings (same content that neph install writes for gemini)
neph print-settings gemini
```

**Per-project override:** `neph integration toggle <agent>` still works for enabling hooks in a specific project directory. This writes to `.neph/`, `.gemini/`, `.cursor/`, or `.codex/` under `process.cwd()`. Useful when you need project-scoped config separate from the global install.

### 6. Agent Submodules

Each agent is a pure data table at `lua/neph/agents/<name>.lua` returning an `AgentDef`:

```lua
-- lua/neph/agents/claude.lua
---@type neph.AgentDef
return {
  name = "claude",
  label = "Claude",
  icon = "",
  cmd = "claude",
  args = { "--permission-mode", "plan" },
  type = "hook",
  ready_pattern = "^%s*>",
  integration_group = "harness",
}
```

**Agent types:**
- **`"hook"`** — Agents integrated via config file hooks (claude, gemini, cursor, copilot, pi). Neph writes to a temp file and the agent's hook config calls `neph review` on file writes.
- **`"terminal"`** — Terminal-only agents (amp, codex, crush, goose). Prompts are sent directly to the terminal. Amp uses its own plugin for review interception.
- **(no type)** — Defaults to terminal.

**Key points:**
- Agents are injected via `setup({ agents = { ... } })` — no hardcoded list
- `contracts.validate_agent()` runs at setup time — invalid agents fail loud
- `full_cmd` is computed lazily by `internal/agents.lua` only for installed agents
- `all.lua` re-exports all built-in agents as a convenience
- The `type` field determines send routing: hook agents use the hook pipeline, others use the terminal

### 6. Context Placeholders

Tokens like `+cursor`, `+selection`, `+diagnostics` are expanded before sending prompts.

**Providers:** `lua/neph/internal/placeholders.lua`

```lua
M.providers.cursor = function(ctx)
  return string.format("@%s:%d", path, ctx.row)
end
```

**Expansion:** `lua/neph/internal/input.lua` calls `placeholders.apply(text, ctx)`.

**Supported tokens:**
- `+file`, `+cursor`, `+line`, `+position` – File location (repo-relative paths)
- `+selection` – Visual selection with repo-relative path and line range
- `+word` – Word under cursor
- `+diagnostic` – Diagnostics at current line
- `+diagnostics` – All buffer diagnostics (max 20)
- `+function`, `+class` – Surrounding treesitter node
- `+git` – `git status`
- `+diff` – `git diff` for current file
- `+buffers`, `+quickfix`, `+loclist`, `+folder`, `+marks`, `+search` – Neovim state

### 7. Socket Integration

Neph forwards `$NVIM_SOCKET_PATH` to every agent terminal. The `neph` CLI uses this for one-off RPC calls to Neovim. The Amp plugin (`tools/amp/neph-plugin.ts`) uses it directly for real-time review interception.

**Discovery:** `tools/neph-cli/src/transport.ts:discoverNvimSocket()`

```typescript
// Tries in order:
// 1. $NVIM_SOCKET_PATH
// 2. $NVIM
// 3. Glob search in /tmp/nvim.*/0
```

### 8. Dry-Run Mode



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

Neovim UI components (vimdiff tabs, signs, virtual text, winbar) require manual testing:
1. Open Neovim with neph.nvim installed
2. Trigger an agent that edits a file (e.g., `claude code`)
3. Verify vimdiff tab opens with current (left) and proposed (right) panes
4. Test `ga` (accept) / `gr` (reject) on individual hunks
5. Test `gA` (accept all) / `gR` (reject all)
6. Verify signs, winbar status, and virtual text hints update correctly

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

### 1. Contract Validation Fails Loud

`setup()` validates every agent and the backend at init time using `contracts.validate_agent()` and `contracts.validate_backend()`. If an agent is missing required fields (name, label, icon, cmd) or a backend is missing required methods, setup throws immediately — not at runtime.

**Why:** Catch wiring errors early. A typo in an agent submodule or an incomplete backend should never silently pass.

**Impact:** If you see "neph: agent validation failed" on startup, check your agent definitions against the `neph.AgentDef` type in `lua/neph/internal/agents.lua`.

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

The snacks backend (`neph.backends.snacks`) requires [folke/snacks.nvim](https://github.com/folke/snacks.nvim).

**Check before using:** `lua/neph/backends/snacks.lua`

If snacks.nvim is not installed, the backend will error when `require`'d. Use the wezterm backend as an alternative if snacks.nvim is not available.

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

Each agent session stores state in `lua/neph/internal/session.lua`. The backend is injected via `setup()` — there is no auto-detection. **State is not persisted across Neovim restarts.**

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

1. **Create `lua/neph/agents/aider.lua`:**

```lua
---@type neph.AgentDef
return {
  name = "aider",
  label = "Aider",
  icon = "󰚩",
  cmd = "aider",
  args = { "--yes" },
}
```

2. **Add to `lua/neph/agents/all.lua`:** (if it should be in the default set)

```lua
return {
  -- ... existing agents
  require("neph.agents.aider"),
}
```

3. **Users include it in setup:**

```lua
neph.setup({
  agents = { require("neph.agents.aider"), ... },
  backend = require("neph.backends.snacks"),
})
```

4. **Add test:** Add `"aider"` to the agent list in `tests/agent_submodules_spec.lua`.

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
  opts = {
    agents = {
      require("neph.agents.claude"),
      require("neph.agents.goose"),
      -- or require("neph.agents.all") for all 10 agents
    },
    backend = require("neph.backends.snacks"),
  },
}
```

## Project-Specific Context

### Design Philosophy

1. **Single entry point:** All RPC calls flow through `lua/neph/rpc.lua`
2. **Pure logic separation:** Engine logic (e.g., hunk computation) is separate from UI
3. **Contract validation:** `protocol.json` is enforced by tests
4. **Testability first:** UI-free logic can be tested in headless Neovim
5. **Zero config by default:** Works out-of-the-box with sensible defaults

### Backend Modules

Backends are modules at `lua/neph/backends/<name>.lua` injected via `setup()`:

- **snacks** (`neph.backends.snacks`): Native Neovim splits via snacks.nvim
- **wezterm** (`neph.backends.wezterm`): WezTerm panes (requires `WEZTERM_PANE` env var)
- **zellij** (`neph.backends.zellij`): Zellij panes (requires `ZELLIJ` env var; single agent pane at a time)

**Backend interface** (validated by `contracts.validate_backend()` at setup time):

| Method | Signature | Description |
|--------|-----------|-------------|
| `setup` | `(config)` | Initialize with neph config |
| `open` | `(name, agent_cfg, cwd) → term_data` | Open a terminal for an agent |
| `focus` | `(term_data) → boolean` | Focus an existing terminal |
| `hide` | `(term_data)` | Hide/close a terminal |
| `is_visible` | `(term_data) → boolean` | Check if terminal is visible |
| `kill` | `(term_data)` | Kill a terminal process |
| `cleanup_all` | `(terminals)` | Clean up all terminals on exit |

**Adding a new backend:**
1. Create `lua/neph/backends/my_backend.lua` implementing all 7 methods above
2. Users pass it as `backend = require("neph.backends.my_backend")` in `setup()`
3. Contract validation runs automatically — missing methods fail at setup time

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

**Built-in debug logging:** Neph has a unified debug log at `/tmp/neph-debug.log`.

```bash
# Enable Lua-side logging
:NephDebug on

# Enable TypeScript-side logging
export NEPH_DEBUG=1

# Tail the log
:NephDebug tail
# or: tail -f /tmp/neph-debug.log
```

Both Lua (`lua/neph/internal/log.lua`) and TypeScript (`tools/lib/log.ts`) write timestamped entries to the same file. Entries include module name and `[lua]`/`[ts]` tag for filtering.

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

**Last Updated:** 2026-03-08
