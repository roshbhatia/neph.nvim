# neph.nvim tools

Companion tooling bundled with neph.nvim. `require("neph").setup()` automatically
symlinks the relevant files to their expected locations.

## `core/shim.py`

Python (uv script) — msgpack-rpc client for LLM agents.

Connects to a running Neovim instance via `NVIM_SOCKET_PATH` (set by Neovim on startup
and inherited by terminal panes spawned from within it). Uses blocking `nvim_exec_lua`
RPC calls for hunk-by-hunk diff review entirely inside Neovim with no polling or temp files.

**Auto-symlinked** by `setup()` to `~/.local/bin/shim`.

Requires `uv` in PATH.

Commands: `status`, `open <file>`, `preview <file>` (stdin = proposed content, prints JSON),
`revert <file>`, `close-tab`, `checktime`, `set <name> <lua-value>`, `unset <name>`

## `pi/pi.ts`

TypeScript — [pi coding agent](https://github.com/mariozechner/pi-coding-agent) extension.

Overrides `write` and `edit` tools to trigger a vimdiff review in Neovim before any
disk write. Activates only when `NVIM_SOCKET_PATH` is set. Tracks agent session
lifecycle via `vim.g.pi_active` / `vim.g.pi_running` for statusline integration.

**Auto-symlinked** by `setup()` to `~/.pi/agent/extensions/nvim.ts`.

## Auto-install

Both `shim.py` and `pi.ts` are symlinked during `require("neph").setup()`. If a source
file is not found (e.g., non-lazy plugin manager with a different install path), a
`vim.notify` warning is emitted and that symlink is skipped.

## Running tests

Run all tool tests from the repo root:
```sh
task tools:test
```

Or run each suite individually:
```sh
# Python shim tests
cd tools/core && uv run pytest tests/ -v

# TypeScript extension tests
cd tools/pi && npm test
```
