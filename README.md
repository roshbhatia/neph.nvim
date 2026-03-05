# neph.nvim

> Consolidated AI agent terminal manager for Neovim.

## Requirements

- Neovim ≥ 0.10
- [folke/snacks.nvim](https://github.com/folke/snacks.nvim) (for native backend & pickers)
- [nvim-treesitter/nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) *(optional – for `+function` / `+class`)*
- [Saghen/blink.cmp](https://github.com/Saghen/blink.cmp) *(optional – for `+token` completion)*

### Companion tool requirements

These are only needed if you use `shim` or the pi extension:

| Tool | Requirement | Notes |
|------|------------|-------|
| `shim` | [uv](https://docs.astral.sh/uv/) ≥ 0.4, Python ≥ 3.11 | `uv` runs the script and manages the `msgpack` dep inline — no venv needed |
| `pi.ts` | [pi coding agent](https://github.com/mariozechner/pi-coding-agent) | Extension is auto-symlinked to `~/.pi/agent/extensions/nvim.ts` on `setup()` |

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

  -- Periodically call :checktime to pick up file changes made by agents
  file_refresh = {
    enable = true,
  },

  -- Terminal multiplexer backend (default: "snacks")
  -- "snacks":  snacks.nvim right-split — works everywhere, no extra setup
  -- "wezterm": WezTerm pane split (requires WEZTERM_PANE env var and wezterm CLI)
  -- "tmux":    tmux pane (stub — falls back to snacks with a warning)
  -- "zellij":  zellij pane (stub — falls back to snacks with a warning)
  multiplexer = "snacks",
})
```

## Socket Integration

When Neovim exposes a socket, `neph.nvim` forwards it to every agent terminal so
that companion tools (`shim`, `pi.ts`) can call back into the editor for
hunk-by-hunk diff review.

**Enable the socket** in your Neovim config:

```lua
-- init.lua — listen on a fixed path
vim.fn.serverstart(vim.fn.expand("~/.local/state/nvim/server.pipe"))
```

Or launch Neovim with `--listen`:

```bash
nvim --listen /tmp/nvim.sock
```

Once the socket is active, Neovim sets `$NVIM_SOCKET_PATH` in every terminal it
opens. Agent tools that use `shim` can then:

- Open files in the editor (`shim open <file>`)
- Trigger a live vimdiff hunk review before any disk write (`shim preview <file>`)
- Reload changed buffers (`shim checktime`)
- Update statusline globals (`shim set pi_running true`)

`neph.nvim` does **not** create the socket itself — it only forwards the path if
it's already set.

## Companion Tools

`neph.nvim` ships companion tooling in its `tools/` directory and **auto-installs
it** during `setup()` by creating symlinks:

| Tool | Symlinked to | Purpose |
|------|-------------|---------|
| `tools/core/shim.py` | `~/.local/bin/shim` | Python msgpack-rpc Neovim client for LLM agents. Provides blocking hunk-by-hunk diff review via `nvim_exec_lua`. Requires `uv`. |
| `tools/pi/pi.ts` | `~/.pi/agent/extensions/nvim.ts` | [pi coding agent](https://github.com/mariozechner/pi-coding-agent) extension. Intercepts `write`/`edit` tool calls and triggers a vimdiff review in Neovim before writing to disk. |

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
