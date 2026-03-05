# neph.nvim

> Consolidated AI agent terminal manager for Neovim.

## Requirements

- Neovim ≥ 0.10
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) (for native backend & pickers)
- [nvim-treesitter/nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) *(optional – for `+function` / `+class`)*
- [Saghen/blink.cmp](https://github.com/Saghen/blink.cmp) *(optional – for `+token` completion)*

## Installation

```lua
-- lazy.nvim
{
  "roshbhatia/neph.nvim",
  dependencies = {
    "folke/snacks.nvim",
    -- "nvim-treesitter/nvim-treesitter",
    -- "Saghen/blink.cmp",
  },
  opts = {},
  keys = function()
    local api = require("neph.api")
    return {
      { "<leader>jj", api.toggle,       desc = "Neph: toggle / pick agent" },
      { "<leader>jJ", api.kill_and_pick, desc = "Neph: kill session & pick new" },
      { "<leader>jx", api.kill,          desc = "Neph: kill active session" },
      { "<leader>ja", api.ask,           mode = { "n", "v" }, desc = "Neph: ask active" },
      { "<leader>jf", api.fix,           desc = "Neph: fix diagnostics" },
      { "<leader>jc", api.comment,       mode = { "n", "v" }, desc = "Neph: comment" },
      { "<leader>jv", api.resend,        desc = "Neph: resend previous prompt" },
      { "<leader>jh", api.history,       desc = "Neph: browse prompt history" },
    }
  end,
}
```

## Configuration

```lua
require("neph").setup({
  -- Extra environment variables forwarded to every agent
  env = {},

  -- Extend or override built-in agents
  agents = {
    -- { name = "myagent", label = "My Agent", icon = " ", cmd = "myagent", args = {} },
  },

  file_refresh = {
    enable         = true,
    timer_interval = 1000, -- ms
    updatetime     = 750,  -- sets vim.o.updatetime
  },

  -- Terminal multiplexer backend.
  -- nil (default): auto-detect — WezTerm if WEZTERM_PANE is set, otherwise native.
  -- "native":  snacks.nvim right-split (works everywhere)
  -- "wezterm": WezTerm pane split (requires WEZTERM_PANE env var and wezterm CLI)
  -- "tmux":    tmux pane (stub — falls back to native with a warning)
  -- "zellij":  zellij pane (stub — falls back to native with a warning)
  multiplexer = nil,
})
```

## Companion Tools

`neph.nvim` ships companion tooling in its `tools/` directory and **auto-installs
it** during `setup()` by creating symlinks:

| Tool | Symlinked to | Purpose |
|------|-------------|---------|
| `tools/core/shim.py` | `~/.local/bin/shim` | Python msgpack-rpc Neovim client for LLM agents. Provides blocking hunk-by-hunk diff review via `nvim_exec_lua`. Requires `uv`. |
| `tools/pi/pi.ts` | `~/.pi/agent/extensions/nvim.ts` | [pi coding agent](https://github.com/mariozechner/pi-coding-agent) extension. Intercepts `write`/`edit` tool calls and triggers a vimdiff review in Neovim before writing to disk. |

`tools/core/nvim-shim` (bash alternative to `shim.py`) is bundled but **not**
auto-symlinked — add it to your PATH manually if preferred.

If a source file is missing (e.g., non-lazy plugin manager), a warning is
emitted via `vim.notify` and that symlink is skipped.

## API

All user-facing actions live in `require("neph.api")`:

| Function | Description |
|----------|-------------|
| `toggle()` | Toggle active session or open agent picker |
| `kill_and_pick()` | Kill active session & open picker |
| `kill()` | Kill active session |
| `ask()` | Ask prompt (visual mode → `+selection`, normal → `+cursor`) |
| `fix()` | Fix diagnostics prompt |
| `comment()` | Comment prompt (visual mode → `+selection`, normal → `+cursor`) |
| `resend()` | Resend previous prompt |
| `history()` | Browse prompt history |

## Context Placeholders

These tokens get replaced by `neph` prior to being sent to your agent instance.

| Token | Expands to |
|-------|-----------|
| `+position` | `@file:line:col` |
| `+file` | Current file path |
| `+line` / `+cursor` | `@file:line` |
| `+selection` | Visual selection text |
| `+word` | Word under cursor |
| `+diagnostics` | All buffer diagnostics |
| `+diagnostic` | Diagnostics at current line |
| `+function` | Surrounding function (treesitter) |
| `+class` | Surrounding class (treesitter) |
| `+git` | `git status` output |
| `+diff` | `git diff` for current file |
| `+buffers` | Open buffer list |
| `+quickfix` / `+qflist` | Quickfix entries |
| `+loclist` | Location list entries |

## Running Tests

```bash
nvim --headless \
  --cmd "set rtp+=~/.local/share/nvim/lazy/plenary.nvim" \
  --cmd "set rtp+=." \
  -c "PlenaryBustedDirectory tests/ {minimal_init='tests/minimal_init.lua'}" \
  -c "qa!"
```
