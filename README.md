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
})
```

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
